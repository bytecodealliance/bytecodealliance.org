---
title: "Wasmtime 1.0: A Look at Performance"
author: "Chris Fallin"
github_name: cfallin
---

In preparation for our upcoming release of Wasmtime 1.0 on September
20, we have prepared two blog posts describing the work we have put
into the compiler and runtime recently. This first post will describe
*performance*-related projects: making the compiler generate faster
code, making the compiler itself run faster, making Wasmtime
instantiate a compiled module faster, and making Wasmtime's runtime as
efficient as possible once the module is running. Our subsequent post
will describe the work we have done to ensure that Wasmtime is secure
and that the compiler generates correct code. We're excited to present
all of our work in both of these directions!

## What is Performance?

We care about making Wasmtime and Cranelift *fast*, because speed has
both direct effects (a faster system!) and indirect effects
(newly-possible applications! higher developer productivity!). But
what do we mean by "fast"? In fact, there are multiple *kinds* of
speed.

When Wasmtime executes a Wasm program, the CPU executes both native
instructions that have been compiled from the Wasm bytecode, and parts
of the "Wasmtime runtime", which is the part of Wasmtime that
maintains data structures to help implement Wasm semantics. For each
of these two halves of the execution, there are two *phases*:
startup/initialization (compilation of Wasm code, and initialization
of runtime), and steady-state execution. All four combinations of
these two dimensions have some impact on performance and can be
optimized separately:

|                    | Compiler (Cranelift)      | Runtime (Wasmtime)                |
|--------------------|---------------------------|-----------------------------------|
| Startup Phase      | Time to compile code      | Time to instantiate a Wasm module |
| Steady-State Phase | Speed of generated code   | Speed of runtime primitives       |

We have done extensive work to improve each of these four quadrants,
and we'll discuss each of them in this blog post!

## Wasm Module Instantiation

A key aspect of WebAssembly's security approach is the *isolation
between separate instances*: each instantiation of a Wasm module gets
its own state and cannot affect the state of others. To use this
isolation effectively, some applications of Wasm will instantiate a
fresh instance for *every unit of work*, such as an incoming request
on a server. This fine-grained isolation means that a bug triggered
while processing one unit of work can't affect any subsequent unit
(either accidentally or maliciously!). Instead, each unit of work
starts from a well-defined state and the "blast radius", or potential
damage, of a bug is limited.

Extremely fast module instantiation is thus a key requirement for a
Wasm VM like Wasmtime. Over the past year, we have done substantial
work to take module instantiation from *milliseconds* to
*microseconds*. How is this possible? In brief, by doing as little
work as possible, and doing it lazily when we must, or ahead-of-time
if we can.

We have already [discussed how we do Wasm-level
snapshotting](https://bytecodealliance.org/articles/making-javascript-run-fast-on-webassembly)
to make startup of certain workloads fast. This technique can be
applied to any WebAssembly context, because it generates a
purpose-built Wasm module with the initialized state
included. However, even this is often not enough: a simple Wasm
runtime will need to allocate memory, initialize data structures, and
copy the initial heap image from this pre-initialized module into the
Wasm heap before it executes a single Wasm instruction. Can we do
better?

### Virtual Memory Tricks

Modern computers use [virtual
memory](https://en.wikipedia.org/wiki/Virtual_memory): an abstracted
view of memory that lets the operating system compose a "virtual" view
of an address space from many different physical parts, and lazily
load or generate contents of a single memory "page" (a small unit,
typically 4 to 16 KiB) when it is first accessed. The processor
includes hardware that gives us this remapping ability without
significant extra cost, and so finding ways to leverage
"virtual-memory tricks" is often the best way to implement complex
behavior with memory.

Let's recap: our issue is that we have an "image" of a Wasm program's
heap state, and instantiating the Wasm program requires initializing a
large block of memory (the heap) to this image. The simplest
implementation would be to allocate the block (via `malloc` or `mmap`
or some other allocator) and then copy the data into the right
locations. This is in fact how Wasmtime used to work!

But virtual memory lets us use a technique known as
"[copy-on-write](https://en.wikipedia.org/wiki/Copy-on-write)" as
well. The key idea is that because we can (i) change the physical page
that a virtual page of memory refers to, and (ii) *apply permissions*
such as read-only protection, we can keep one copy of the "initial
state" around and create a new Wasm heap by setting up read-only
mappings to this one copy.

This means that now the cost of instantiation is reduced to the cost
of making that mapping. This may even be a constant-time operation
(i.e., not dependent on how large the heap is) if the kernel is smart
about lazily populating the per-page mappings: it can just create a
single node in a mapping data structure instead. Production operating
systems like the Linux kernel, and also macOS and Windows, work this
way.

According to the Wasm specification, the Wasm heap must behave *as if*
it were a separate copy. But there is a subtle trick we can play here:
sharing a single copy of the data is fine as long as the program only
performs reads. This is because if no instance of the program changes
the one data copy, then no other instance can tell it is being
shared. This is why instantiating without copying anything is still
a *correct* approach.

But what do we do when one instance *does* modify some of its heap? In
this case, we do as the "copy-on-write" technique's name implies: we
catch the write before it happens (because of the read-only
permissions), we make a new copy of that single page, and we alter the
mapping so that the particular instance gets that "private", and now
writeable, copy of the page.

We implemented [an "instance
allocator"](https://github.com/bytecodealliance/wasmtime/pull/3697) in
Wasmtime that makes use of this copy-on-write (CoW) technique for very
fast instantiations. It also uses a Linux syscall known as `madvise`
to quickly "reset" the page mappings back to the original read-only
heap image, so we can reuse the same mappings over and over when the
same Wasm program is re-instantiated many times. (One might imagine
this would be the case in a server serving many requests, for
example!)

There is more we could do here still: we have studied the way that the
Linux kernel's locking, and its interaction with the hardware ("TLB
flushes" and "inter-processor interrupts" (IPIs)), can cause
bottlenecks, and we have further plans down the road. But for now,
this virtual-memory-based approach is extremely fast compared to the
earlier explicit memory initialization.

### Lazy Initialization

After building the basic copy-on-write implementation above, we next
realized that the Wasmtime runtime was spending significant time
initializing data structures before starting to execute the compiled
Wasm code.

A WebAssembly virtual machine needs to implement various abstractions
that the Wasm program expects to have available. We have already
talked about heaps above, but there are others too. The VM needs to
provide "function imports", or the ability to call functions from
other modules or the embedding context (the application that embeds
Wasmtime). It needs to implement "tables", which are a way for Wasm
program to store references to functions or other objects. And there
are quite a few more. All of these need to be initialized to the
proper state before the program starts.

It turns out that when a large program executes, it may only use a
small number of the imported functions, or function references stored
in a table. So the time spent to fill out this state &mdash; in some
cases, hundreds of kilobytes of memory, with some work to compute each
individual word or struct &mdash; is mostly wasted.

This was a prime use-case for the technique of "lazy initialization":
that is, deferring the work of setting up some state until it is
actually needed. To make this work, one needs a way to track the "not
yet initialized" state and differentiate it from the normal state at
runtime, and then one needs to check for this and do the
initialization at a fine granularity &mdash; for a single item
&mdash; right before using it.

We
[implemented](https://github.com/bytecodealliance/wasmtime/pull/3733)
lazy initialization for tables of function references and the function
closure objects they point to. This optimization removed the other big
piece of work done when instantiating a large Wasm module. For the
multi-megabyte test case we were using (a version of the SpiderMonkey
JS engine compiled to Wasm), the heap initialization involved writing
tens of megabytes. After using virtual-memory tricks as above we were
down to hundreds of kilobytes. Finally with lazy table and
function-object initialization we wrote just a few kilobytes to memory
per instantiation with no expensive computations at all.[^1]

[^1]: Interesting anecdote: it turns out that at the scale we reached,
      even *zeroing an array* of the closure objects ("anyfuncs") had
      a measurable impact. Every cache miss counts! The PR initially
      used a bitmap to track whether a slot was initialized instead,
      but eventually my colleague Alex suggested a brilliantly simple
      approach where we re-initialize an anyfunc whenever we take a
      pointer to it. (This turns out to be non-racy because of Rust's
      aliasing protections.)

Following this work, we did a series of optimizations to other
bottlenecks that removing the two major ones exposed
([1](https://github.com/bytecodealliance/wasmtime/pull/3742),
[2](https://github.com/bytecodealliance/wasmtime/pull/3741),
[3](https://github.com/bytecodealliance/wasmtime/pull/3739),
[4](https://github.com/bytecodealliance/wasmtime/pull/3727),
[5](https://github.com/bytecodealliance/wasmtime/pull/3791),
[6](https://github.com/bytecodealliance/wasmtime/pull/3850),
[7](https://github.com/bytecodealliance/wasmtime/pull/4041),
[8](https://github.com/bytecodealliance/wasmtime/pull/4051)). At the
end of that line of work, we were satisfied that we had pared
instantiation down to its bare essentials, and any further bottlenecks
were likely to be elsewhere in the system &mdash; either the thing
that requests the instantiation, or the Wasm program that is
instantiated!

We should note, too, that Wasmtime had already been designed to
frontload a lot of the work of loading and verifying a Wasm module
prior to the instantiation event itself. For example, the
[Linker](https://docs.rs/wasmtime/latest/wasmtime/struct.Linker.html)
and
[InstancePre](https://docs.rs/wasmtime/latest/wasmtime/struct.InstancePre.html)
structs allow the user of Wasmtime to explicitly do import resolution
and typechecking beforehand, amortized over many instantiations. It
was in this context that we were able to focus solely on the mechanics
of setting up the runtime-internal state for an instance.

### Fast Instantiation: Results

As a result of all of this work, instantiation time of
`SpiderMonkey.wasm` went from about 2 milliseconds (eager initialization
of all heap and other data structures) to 5 microseconds, or [400
times
faster](https://github.com/bytecodealliance/wasmtime/pull/3733#pullrequestreview-877688702). Not
bad!

## Runtime Performance

Now that we've started the Wasm program, we need to help it run as
quickly as possible with fast runtime primitives!

While most of the CPU time during Wasm execution is typically spent in
the Wasm program itself, or in the "hostcalls" that it invokes (which
are code that the Wasmtime user plugs into Wasmtime and which we don't
control directly), there are parts of Wasmtime itself that have to run
in certain cases. These bits of code are what we call the "VM
runtime".

We need bits of the runtime, for example, to help us "walk the stack"
and list all of the active stack frames when we generate a stacktrace
for a trap, or when we trace all active object references for garbage
collection. We also need a small part of the runtime called a
"trampoline" when we invoke code outside of Wasmtime, or when code
outside of Wasmtime initially invokes Wasm code.

### Fast Stack-Walking

We have completed several projects to speed up parts of the runtime
over the past year. The most impressive win is perhaps the [fast stack
walking](https://github.com/bytecodealliance/wasmtime/pull/4431)
work. Previously, in order to allow Wasmtime to enumerate all
stackframes, the Cranelift compiler generated what is known as "unwind
info". This is a kind of metadata that describes where the compiled
code will put values on the stack at any given point. Using this
metadata, Wasmtime's "unwinder" is able to reverse-engineer the
program state: it understands the stack frame of one active function
call at a time, eventually finding out who called it and iterating up
the stack until it reaches the initial entry into Wasm.

This turns out to be extremely slow, for several reasons. First, the
metadata format, known as
[DWARF](https://en.wikipedia.org/wiki/DWARF)[^2], is quite complex,
and takes significant effort to interpret. This is an advantage when
it comes to working for any conceivable stack-frame layout &mdash; so
it can be produced by many different compilers &mdash; but in our
case, this flexibility is overkill. Second, the system library
typically used to walk a stack with DWARF metadata is known as
[libunwind](https://www.nongnu.org/libunwind/), and though it is
widely used and generally reliable, it has significant scalability
issues. For example, we discovered that the system unwinder has poor
performance when thousands of Wasm modules (each with their own DWARF
metadata) are loaded into a single process. Collecting a trap
stacktrace in such a case could take up to half a second! Interacting
with the system unwinder is also a source of bugs in some cases, and
makes fixing them harder. We have had such issues on multiple
platforms. Controlling our own unwind process lets us solve these
issues.

[^2]: DWARF is supposedly named as it is because it is often used with
      the
      [ELF](https://en.wikipedia.org/wiki/Executable_and_Linkable_Format)
      executable format, and even compiler and linker nerds sometimes
      like to have fun.

To address this issue, we developed a [custom
stack-walker](https://github.com/bytecodealliance/wasmtime/pull/4431). We
started with the observation that because we control the compiled
code, we can limit the complexity of the stack format to something
that is much easier and faster to traverse. Specifically, we can
ensure that we always maintain a linked list of [frame
pointers](https://en.wikipedia.org/wiki/Call_stack#Stack_and_frame_pointers). A
stack walk is then as simple as a linked-list traversal, with saved
return addresses immediately adjacent to each frame-pointer value.

According to the
[benchmarks](https://github.com/bytecodealliance/wasmtime/pull/4431#issue-1301146972),
this change improved the speed of stack walking by between 64% and
99.95%, depending on the situation, and it completely removed the
quadratic worst-case and other potential issues, known or unknown, of
relying on `libunwind` and its complex metadata. This performance
improvement is a huge qualitative improvement: it allows stack traces
to be enabled in contexts where they previously could not be, and
improves Wasmtime's robustness substantially.

### Fast Cooperative Multitasking with Epoch Interruption

A common use-case for Wasmtime is to run many different WebAssembly
guests concurrently and timeslice between them. Wasmtime has [built-in
support](https://docs.rs/wasmtime/latest/wasmtime/struct.Config.html#method.async_support)
for running calls to Wasm on an async event loop.

One issue that a Wasmtime user might have in such a situation is how
to *limit the execution time* of a Wasm program. Typically when
running asynchronously with an event loop, a compute-intensive task
should be split into segments so that the event loop is not stalled
for more than a maximum "timeslice".

With a standard compilation of Wasm bytecode to native machine code, a
loop in Wasm becomes a loop in the compiled code and runs as many
iterations as it likes, with no limit. If the user calls this function
from an event loop, then that event loop may be stalled indefinitely.

Thus, especially when running untrusted code, it is important for the
Wasmtime user to establish a way to *regain control* after a certain
time limit. So Wasmtime must provide a way to *interrupt* Wasm
execution at a certain point.

Prior to this year, the main way to implement this behavior was via
["fuel"](https://docs.rs/wasmtime/latest/wasmtime/struct.Config.html#method.consume_fuel). This
is a mechanism by which the compiled Wasm code is augmented with code
that counts "operations", checks this current count against a limit,
and yields back to the caller or event loop if the limit is exceeded.

Fuel is an effective mechanism, but it is heavyweight: it requires
augmenting every piece of code with the "counting", and frequently
storing that count to memory and checking it.

In our [epoch
interruption](https://github.com/bytecodealliance/wasmtime/pull/3699)
work, we realized that there is actually a much faster way. Fuel is
overly precise: it counts operations and stops at exactly the
limit. But if we could instead rely on some external agent to change a
flag in memory at approximately the right time, we could just test
that flag and branch to the yield if it changes. This removes the need
to account fuel usage (which is almost as expensive as the main Wasm
computation itself), and removes the frequent updates to the count in
memory. Instead a single, infrequently-changing value can be touched
once by a periodically-waking thread and this "broadcasts" an
interrupt to all worker threads in Wasm code.

It turns out that this makes execution of `SpiderMonkey.wasm` roughly
twice as fast as when using fuel interruption. For applications that
require interruption schemes because of their asynchronous event loop,
this is quite a significant boost!

## Cranelift: Compiled-Code Quality

We'll talk now about the compiler,
[Cranelift](https://github.com/bytecodealliance/wasmtime/tree/main/cranelift/),
that underpins Wasmtime. We use Cranelift to compile Wasm bytecode to
native machine code that the computer can execute directly.  We have
had a number of long-running projects to overhaul pieces of the
Cranelift compiler pipeline to improve performance. Broadly speaking,
we can improve the quality of generated code by implementing more
optimization passes, tuning the instruction-selection rules as needed,
and improving the core algorithms such as register allocation to
support more advanced heuristics and approaches.

### Register Allocator Revamp: regalloc2

One major compiler effort that we have made over the past year or so
is the introduction of our new register allocator,
[regalloc2](https://github.com/bytecodealliance/regalloc2). A
*register allocator* is a piece of a compiler that assigns storage
locations to values in the program. WebAssembly, as an abstract and
hardware-independent virtual machine, does not have a notion of input
and output locations for most instructions. Rather it just speaks of
an abstract "operand stack" (and locals and the heap, but most
instructions do not operate on these). In a real CPU, instructions
operate on data in *registers*, which are small storage locations that
can hold one value (e.g. a 64-bit number) each. A register allocator
decides which values to keep in which registers at which times. Doing
this well improves program performance substantially because it
implies less moving around of values.

regalloc2 was designed to support more advanced kinds of algorithms to
decide how to allocate values to registers (you can read [more detail
in this
post](https://cfallin.org/blog/2022/06/09/cranelift-regalloc2/) or [in
its design
document](https://github.com/bytecodealliance/regalloc2/blob/main/doc/DESIGN.md)). When
introduced, it improved runtime performance of `SpiderMonkey.wasm` by
about 5% and another CPU-intensive benchmark, `bz2`, by 4% (for
example). It also had a substantial impact on compile time, as we'll
discuss below. (Both impacts will be augmented further in the future
as we adjust Cranelift's code generation to make more use of
regalloc2's additional features.)

### Better Pattern Maching: New Backends, ISLE, and Ongoing Tuning

The next major set of improvements we have done are in the area of
*instruction selection*. The instruction-selection problem is that of
choosing the best CPU instructions to implement a given program
behavior. Because each CPU has its own unique set of instructions, and
because these can be combined in many different ways, this is a very
difficult combinatorial puzzle to solve. Cranelift initially [adopted
a new compiler-backend
design](https://cfallin.org/blog/2020/09/18/cranelift-isel-1/) that
enables more advanced pattern-matching, and currently takes an
approach of [expressing instruction lowerings in a pattern-matching
DSL (domain-specific
language)](https://github.com/bytecodealliance/rfcs/pull/15) so that
we can more easily tune these patterns.

Measuring from just before we switched to the new backend framework by
default, up to just before adopting regalloc2 &mdash; so, measuring
the effect of the new backend framework and a year of tuning it
&mdash; we improved performance on `SpiderMonkey.wasm` by 22%, and
`bz2` by 18%. This was a substantial win and we continue to find ways
to tune the instruction patterns.

### Future: Mid-end Optimizations

In the future, we plan to introduce [more advanced mid-end
optimizations](https://github.com/bytecodealliance/rfcs/pull/27) to
Cranelift. A "mid-end optimizer" is the part of the compiler that
transforms the program in ways that make it faster *before* it is
"lowered" into a machine-specific form (that is, before instruction
selection). There is a [classical set of
optimizations](https://www.clear.rice.edu/comp512/Lectures/Papers/1971-allen-catalog.pdf)
that almost all compilers will perform that includes basic rules like
simplifying constant expressions (`1 + 1` becomes `2`). But there are
many more complex and subtle transformations too.

Our
[prototype](https://github.com/bytecodealliance/wasmtime/pull/4249)
"mid-end optimizer" improves performance of `SpiderMonkey.wasm` by 13%
and `bz2` by 3%, and serves as a framework in which we can more easily
write a large number of "rewrite rules" to express algebraic
identities, clever implementations of particular computations (such as
bit-twiddling tricks), and many others. We are excited by the
potential that this carries!

## Cranelift: Compile-Time Optimizations

Aside from optimizing Cranelift's generated code, the compilation
process itself is a nontrivial computation, and if it is too slow,
then Wasmtime could take a long time to start up with a new piece of
code, hindering productivity (for Wasm developers) and responsiveness
(for end-users accessing new applications). Thus, *compiler speed* is
an important metric, and we've worked hard to improve this. Broadly
speaking, we can improve compile time by choosing better algorithms in
the key parts of the backend, such as the register allocator or the
optimization passes, or by doing general program optimizations, like
reducing memory use.

### regalloc2

Many of the above revamps that we designed to improve the quality of
the compiler's output also, by virtue of better design or more careful
construction, run faster. The regalloc2 switchover improved compile
times substantially, because register allocation is a large fraction
of compile time: measuring single-thread time (not compiling in
parallel), `SpiderMonkey.wasm` builds 6% faster and `bz2` 10%
faster. One of the explicit design goals of regalloc2 was to avoid bad
outliers with more robust algorithms, and this has a particular effect
on parallel compilation, where hard-to-compile functions "stick out"
more: on a 12-core system, `SpiderMonkey.wasm` builds 21% faster and
`bz2` builds 15% faster. The best improvement was in `clang.wasm`, a
Wasm-module version of the Clang compiler, which now builds 42% faster
in Cranelift. Improvements of 20% or so are typical.

### Mid-End Optimizer: Many Passes into One

Algorithmic redesign can substantially improve compile time as
well. In our mid-end optimizer prototype, we have taken a new approach
to the relevant part of the compiler design: several different
"passes", or specific algorithms that transform the program in a
certain way, have been combined into one unified framework that passes
over the program only once. This approach allows better compile times
in many cases. We measured `bz2` compiling 15% faster under our
prototype, for example (and `SpiderMonkey.wasm` is roughly at parity).

### Standard Program Optimizations

A compiler is a computer program like any other &mdash; perhaps more
CPU-intensive than most &mdash; and the sorts of changes that one
would make to any program to speed it up, one can make to a compiler
as well. One particularly effective kind of change for speed is to
*reduce memory allocation and usage*. The less memory the program
allocates, the faster it runs, for at least two reasons: the memory
allocator itself can be slow, and using more memory can cause more
cache misses and memory traffic as well. Cranelift also tends to
stress allocators especially hard because of its multithreaded
compilation model.

We recently had a series of changes
([1](https://github.com/bytecodealliance/wasmtime/pull/4536),
[2](https://github.com/bytecodealliance/wasmtime/pull/4584),
[3](https://github.com/bytecodealliance/wasmtime/pull/4586),
[4](https://github.com/bytecodealliance/wasmtime/pull/4621),
[5](https://github.com/bytecodealliance/wasmtime/pull/4710)) that
improve compiler performance by about 5% in aggregate with Rust's
default allocator, and substantially more (22-32%, 11%, 9-13%, 8-10%,
and 2-6% respectively) if the system allocator is particularly slow
(as it is in the Sightglass benchmark suite, or more realistically,
with [custom
allocators](https://twitter.com/gabrielesvelto/status/1558083461059153920)
that some programs use for various reasons). These wins are important
because over-dependence on fast malloc makes Cranelift less flexible
and less applicable in some situations.

## Conclusions

This post has been a whirlwind tour of many of the ways we have
optimized Wasmtime and Cranelift to perform better in each of the four
quadrants: Wasm compiler speed, speed of compiled Wasm code, runtime
initialization speed, and runtime steady-state speed. High performance
is a critical aspect of any software that aspires to be part of a
foundation for building efficient, long-lasting systems. If
WebAssembly is to succeed, it needs tools that execute it as quickly
as possible, so that it can compete with native code. We continue to
work toward this goal.
