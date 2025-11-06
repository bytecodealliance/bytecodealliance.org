---
title: "Exceptions in Cranelift and Wasmtime"
author: "Chris Fallin"
date: "2025-11-06"
github_name: "cfallin"
excerpt_separator: <!--end_excerpt-->
---

This is a blog post outlining the odyssey I recently took to implement
the [Wasm exception-handling
proposal](https://github.com/webassembly/exception-handling) in
[Wasmtime](https://wasmtime.dev/), the open-source
[WebAssembly](https://webassembly.org/) engine for which I'm a core
team member/maintainer, and its [Cranelift](https://cranelift.dev/)
compiler backend.

<!--end_excerpt-->

*Note: this is a cross-post with my [personal blog](https://cfallin.org/blog/);
this post is also available
[here](https://cfallin.org/blog/2025/11/06/exceptions/).*

When first discussing this work, I made an off-the-cuff estimate in
the Wasmtime biweekly project meeting that it would be "maybe two
weeks on the compiler side and a week in Wasmtime". Reader, I need to
make a confession now: I was wrong and it was *not* a three-week
task. This work spanned from late March to August of this year
(roughly half-time, to be fair; I wear many hats). Let that be a
lesson![^1]

[^1]: To explain myself a bit, I underestimated the interactions of
      exception handling with garbage collection (GC); I hadn't
      realized yet that `exnref`s were a full first-class value and
      would need to be supported including in the host API. Also, it
      turns out that exceptions can cross the host/guest boundary, and
      goodness knows that gets really fun really fast. I was *only*
      off by a factor of two on the compiler side at least!

In this post we'll first cover what exceptions are and why some
languages want them (and what other languages do instead) -- in
particular what the big deal is about (so-called) "zero-cost"
exception handling. Then we'll see how Wasm has specified a
bytecode-level foundation that serves as a least-common denominator
but also has some unique properties. We'll then take a roundtrip
through what it means for a *compiler* to support exceptions -- the
control-flow implications, how one reifies the communication with the
unwinder, how all this intersects with the ABI, etc. -- before finally
looking at how Wasmtime puts it all together (and is careful to avoid
performance pitfalls and stay true to the intended performance of the
spec).

## Why Exceptions?

Many readers will already be familiar with exceptions as they are
present in languages as widely varied as
[Python](https://en.wikipedia.org/wiki/Python_(programming_language)),
[Java](https://en.wikipedia.org/wiki/Java_(programming_language)),
[JavaScript](https://en.wikipedia.org/wiki/JavaScript),
[C++](https://en.wikipedia.org/wiki/C%2B%2B),
[Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language)),
[OCaml](https://en.wikipedia.org/wiki/OCaml), and many more. But let's
briefly review so we can (i) be precise what we mean by an exception,
and (ii) discuss *why* exceptions are so popular.

[Exception
handling](https://en.wikipedia.org/wiki/Exception_handling_(programming))
is a mechanism for *nonlocal flow control*. In particular, most
flow-control constructs are *intraprocedural* (send control to other
code in the current function) and *lexical* (target a location that
can be known statically). For example, `if` statements and `loop`s
both work this way: they stay within the local function, and we know
exactly where they will transfer control. In contrast, exceptions are
(or can be) *interprocedural* (can transfer control to some point in
some other function) and *dynamic* (target a location that depends on
runtime state).[^2]

[^2]: From an implementation perspective, the dynamic, interprocedural
      nature of exceptions is what makes them far more interesting,
      and involved, than classical control flow such as conditionals,
      loops, or calls! This is why we need a mechanism that involves
      runtime data structrues, "stack walks", and lookup tables,
      rather than simply generating a jump to the right place: the
      target of an exception-throw can only be computed at runtime,
      and we need a convention to transfer control with "payload" to
      that location.

To unpack that a bit: an exception is *thrown* when we want to signal
an error or some other condition that requires "unwinding" the current
computation, i.e., backing out of the current context; and it is
*caught* by a "handler" that is interested in the particular kind of
exception and is currently "active" (waiting to catch that
exception). That handler can be in the current function, or in any
function that has called it. Thus, an exception throw and catch can
result in an abnormal, early return from a function.

One can understand the need for this mechanism by considering how
programs can handle errors. In some languages, such as Rust, it is
common to see function signatures of the form `fn foo(...) ->
Result<T, E>`. The
[`Result`](https://doc.rust-lang.org/std/result/enum.Result.html) type
indicates that `foo` normally returns a value of type `T`, but may
produce an error of type `E` instead. The key to making this ergonomic
is providing some way to "short-circuit" execution if an error is
returned, propagating that error upward: that is, Rust's `?` operator,
for example, which turns into essentially "if there was an error,
return that error from this function".[^3] This is quite conceptually
nice in many ways: why should error handling be different than any
other data flow in the program? Let's describe the type of results to
include the possibility of errors; and let's use normal control flow
to handle them. So we can write code like

```rust
fn f() -> Result<u32, Error> {
  if bad {
    return Err(Error::new(...));
  }
  Ok(0)
}

fn g() -> Result<u32, Error> {
  // The `?` propagates any error to our caller, returning early.
  let result = f()?;
  Ok(result + 1)
}
```

and we don't have to do anything special in `g` to propagate errors
from `f` further, other than use the `?` operator.

[^3]: For those so inclined, this is a
      [*monad*](https://en.wikipedia.org/wiki/Monad_(functional_programming)),
      and e.g. [Haskell](https://en.wikipedia.org/wiki/Haskell)
      implements the ability to have "result or error" types that
      return from a sequence early via
      [`Either`](https://hackage.haskell.org/package/base-4.21.0.0/docs/Data-Either.html#t:Either),
      explicitly describing the concept as such. The `?` operator
      serves as the "bind" of the monad: it connects an
      error-producing computation with a use of the non-error value,
      returning the error directly if one is given instead.

But there is a *cost* to this: it means that every error-producing
function has a larger return type, which might have ABI implications
(another return register at least, if not a stack-allocated
representation of the `Result` and the corresponding loads/stores to
memory), and also, there is at least one conditional branch after
every call to such a function that checks if we need to handle the
error. The dynamic efficiency of the "happy path" (with no thrown
exceptions) is thus impacted. Ideally, we skip any cost unless an
error actually occurs (and then perhaps we accept slightly more cost
in that case, as tradeoffs often go).

It turns out that this is possible with the *help of the language
runtime*. Consider what happens if we omit the `Result` return types
and error checks at each return. We will need to reach the code that
handles the error in some other way. Perhaps we can jump directly to
this code somehow?

The key idea of "zero-cost exception handling" is to get the compiler
to build side-tables to *tell us* where this code -- known as a
"handler" -- is. We can walk the callstack, visiting our caller and
its caller and onward, until we find a function that would be
interested in the error condition we are raising. This logic is
implemented with the help of these side-tables and some code in the
language runtime called the "unwinder" (because it "unwinds" the
stack). If no errors are raised, then none of this logic is executed
at runtime. And we no longer have our explicit checks for error
returns in the "happy path" where no errors occur. This is why the
common term for this style of error-handling is called "zero-cost":
more precisely, it is zero-cost when *no* errors occur, but the
unwinding in case of error can still be expensive.

This is the status quo for exception-handling implementations in most
production languages: for example, in the C++ world, exception
handling is commonly implemented via the [Itanium C++
ABI](https://itanium-cxx-abi.github.io/cxx-abi/abi-eh.html)[^4], which
defines a comprehensive set of tables emitted by the compiler and a
complex dance between the system unwinding library and
compiler-generated code to find and transfer control to
handlers. Handler tables and stack unwinders are common in interpreted
and just-in-time (JIT)-compiled language implementations, too: for
example, SpiderMonkey has [try
notes](https://searchfox.org/firefox-main/rev/50a34d25155fd70628ee69c7d68a2509c0e3445d/js/src/vm/StencilEnums.h#18)
on its bytecode (so named for "try blocks") and a
[HandleException](https://searchfox.org/firefox-main/rev/a5316cedc669bcec09efae23521e0af6b9d3d257/js/src/jit/JitFrames.cpp#691)
function that [walks stack
frames](https://searchfox.org/firefox-main/rev/a5316cedc669bcec09efae23521e0af6b9d3d257/js/src/jit/JitFrames.cpp#751-845)
to find a handler.

[^4]: So named for the [Intel Itanium
      (IA-64)](https://en.wikipedia.org/wiki/IA-64), an instruction-set
      architecture that happened to be the first ISA where this scheme was
      implemented for C++, and is now essentially dead (before its time! woefully
      misunderstood!) but for that legacy...

## The Wasm Exception-Handling Spec

The WebAssembly specification now (since version 3.0) has [exception
handling](https://github.com/webassembly/exception-handling). This
proposal was a long time in the making by various folks in the
standards, toolchain and browser worlds, and the CG (standards group)
has now merged it into the spec and included it in the
recently-released "Wasm 3.0" milestone. If you're already familiar
with the proposal, you can skip over this section to the Cranelift-
and Wasmtime-specific bits below.

First: let's discuss *why* Wasm needs an extension to the bytecode
definition to support exceptions. As we described above, the key idea
of zero-cost exception handling is that an unwinder visits stack
frames and looks for handlers, transferring control directly to the
first handler it finds, outside the normal function return
path. Because the call stack is *protected*, or not directly readable
or writable from Wasm code (part of Wasm's [control-flow
integrity](https://en.wikipedia.org/wiki/Control-flow_integrity)
aspect), an unwinder that works this way necessarily must be a
privileged part of the Wasm runtime itself. We can't implement it in
"userspace" because there is no way for Wasm bytecode to transfer
control directly back to a distant caller, aside from a chain of
returns. This missing functionality is what the extension to the
specification adds.

The implementation comes down to only three opcodes (!), and some new
types in the bytecode-level type system. (In other words -- given the
length of this post -- it's deceptively simple.) These opcodes are:

- `try_table`, which wraps an inner body, and specifies *handlers* to
  be active during that body. For example:

  ```wat
  (block $b1    ;; defines a label for a forward edge to the end of this block
    (block $b2  ;; likewise, another label
      (try_table
        (catch $tag1 $b1) ;; exceptions with tag `$tag1` will be caught by code at $b1
        (catch_all $b2)   ;; all other exceptions will be caught by code at $b2

        body...)))
  ```

  In this example, if an exception is thrown from within the code in
  `body`, and it matches one of the specified tags (more below!),
  control will transfer to the location defined by the end of the
  given block. (This is the same as other control-flow transfers in
  Wasm: for example, a branch `br $b1` also jumps to the end of
  `$b1`.)

  This construct is the single all-purpose "catch" mechanism, and is
  powerful enough to directly translate typical `try`/`catch` blocks
  in most programming languages with exceptions.

- `throw`: an instruction to directly throw a new exception. It
  carries the tag for the exception, like: `throw $tag1`.

- `throw_ref`, used to rethrow an exception that has already been
  caught and is held by reference (more below!).

And that's it! We implement those three opcodes and we are "done".

### Payloads

That's not the whole story, of course. Ordinarily a source language
will offer the ability to carry some *data* as part of an exception:
that is, the error condition is not just one of a static set of kinds
of errors, but contains some fields as well. (E.g.: not just "file not
found", but "file not found: $PATH".)

One could build this on top of an bytecode-level exception-throw
mechanism that only had throw/catch with static tags, with the help of
some global state, but that would be cumbersome; instead, the Wasm
specification offers *payloads* on each exception. For full
generality, this payload can actually take the form of a *list* of
values; i.e., it is a full product type (struct type).

We alluded to "tags" above but didn't describe them in detail. These
tags are key to the payload definition: each tag is effectively a type
definition that specifies its list of payload value types as
well. (Technically, in the Wasm AST, a tag definition names a
*function type* with only parameters, no returns, which is a nice way
of reusing an existing entity/concept.) Now we show how they are
defined with a sample module:

```wat
(module
 ;; Define a "tag", which serves to define the specific kind of exception
 ;; and specify its payload values.
 (tag $t (param i32 i64))

 (func $f (param i32 i64)
       ;; Throw an exception, to be caught by whatever handler is "closest"
       ;; dynamically.
       (throw $t (local.get 0) (local.get 1)))

 (func $g (result i32 i64)
       (block $b (result i32 i64)
              ;; Run a body below, with the given handlers (catch-clauses)
              ;; in-scope to catch any matching exceptions.
              ;;
              ;; Here, if an exception with tag `$t` is thrown within the body,
              ;; control is transferred to the end of block `$b` (as if we had
              ;; branched to it), with the payload values for that exception
              ;; pushed to the operand stack.
              (try_table (catch $t $b)
                         (call $f (i32.const 1) (i64.const 2)))
              (i32.const 3)
              (i64.const 4))))
```

Here we've defined one tag (the Wasm text format lets us attach a name
`$t`, but in the binary format it is only identified by its index, 0),
with two payload values. We can throw an exception with this tag given
values of these types (as in function `$f`) and we can catch it if we
specify a catch destination as the end of a block meant to return
exactly those types as well.  Here, if function `$g` is invoked, the
exception payload values `1` and `2` will be thrown with the
exception, which will be caught by the `try_table`; the results of
`$g` will be `1` and `2`. (The values `3` and `4` are present to allow
the Wasm module to validate, i.e. have correct types, but they are
dynamically unreachable because of the throw in `$f` and will not be
returned.)

This is an instance where Wasm, being a bytecode, can afford to
generalize a bit relative to real-metal ISAs and offer conveniences to
the Wasm producer (i.e., toolchain generating Wasm modules). In this
sense, it is a little more like a compiler IR. In contrast, most other
exception-throw ABIs have a fixed definition of payload, e.g., one or
two machine register-sized values. In practice some producers might
choose a small fixed signature for all exception tags anyway, but
there is no reason to impose such an artificial limit if there is a
compiler and runtime behind the Wasm in any case.

### Unwind, Cleanup, and Destructors

So far, we've seen how Wasm's primitives can allow for basic exception
throws and catches, but what about languages with scoped resources,
e.g. C++ with its destructors? If one writes something like

```c++
struct Scoped {
    Scoped() {}
    ~Scoped() { cleanup(); }
};

void f() {
    Scoped s();
    throw my_exception();
}
```

then the `throw` should transfer control out of `f` and upward to
whatever handler matches, but the destructor of `s` still needs to run
and call `cleanup`. This is not quite a "catch" because we don't want
to terminate the search: we aren't actually handling the error
condition.

The usual approach to compile such a program is to "catch and
rethrow". That is, the program is lowered to something like

```c++
try {
    throw ...
} catch_any(e) {
    cleanup();
    rethrow e;
}
```

where `catch_any` catches *any* exception propagating past this point
on the stack, and `rethrow` re-throws the same exception.

Wasm's exception primitives provide exactly the pieces we need for
this: a `catch_all_ref` clause, which *catches all exceptions* and
*boxes the caught exception as a reference*; and a `throw_ref`
instruction, which *re-throws a previously-caught exception*.[^9]

In actuality there is a two-by-two matrix of "catch" options: we can
`catch` a specific tag or `catch_all`; and we can catch and
immediately unpack the exception into its payload values (as we saw
above), or we can catch it as a reference. So we have `catch`,
`catch_ref`, `catch_all`, and `catch_all_ref`.[^5]

[^5]: To be precise, because it may be a little surprising:
      `catch_ref` pushes both the payload values *and* the exception
      reference onto the operand stack at the handler destination. In
      essence, the rule is: tag-specific variants always unpack the
      payloads; and *also*, `_ref` variants always push the exception
      reference.

[^9]: It's worth briefly noting here that the Wasm exception handling
      proposal went through a somewhat twisty journey, with an earlier
      variant (now called "legacy exception handling") that shipped in
      some browsers but was never standardized handling rethrows in a
      different way. In particular, that proposal did not offer
      first-class exception object references that could be rethrown;
      instead, it had an explicit `rethrow` instruction. I wasn't
      around for the early debates about this design, but in my
      opinion, providing first-class exception object references that
      can be plumbed around via ordinary dataflow is far nicer. It
      also permits a simpler implementation, as long as one literally
      implements the semantics by always allocating an exception
      object.[^6]

[^6]: Of course, always boxing exceptions is not the only way to
      implement the proposal. It should be possible to "unbox"
      exceptions and skip the allocation, carrying payloads directly
      through some other engine state, if they are not caught as
      references. We haven't implemented this optimization in Wasmtime
      and we expect the allocation performance for small exception
      objects to be adequate for most use-cases.

### Dynamic Identity and Compositionality

There is one final detail to the Wasm proposal, and in fact it's the
part that I find the most interesting and unique. Given the above
introduction, and any familiarity with exception systems in other
language semantics and/or runtime systems, one might expect that the
"tags" identifying kinds of exceptions and matching throws with
particular catch handlers would be static labels. In other words, if I
throw an exception with tag `$tA`, then the first handler for `$tA`
anywhere up the stack, from any module, should catch it.

However, one of Wasm's most significant properties as a bytecode is
its emphasis on isolation. It has a distinction between static
*modules* and dynamic *instances* of those modules, and modules have
no "static members": every entity (e.g., memory, table, or global
variable) defined by a module is replicated per instance of that
module. This creates a clean separation between instances and means
that, for example, one can freely reuse a common module (say, some
kind of low-level glue or helper module) with separate instances in
many places without them somehow communicating or interfering with
each other.

Consider what happens if we have an instance A that invokes some other
(dynamically provided) function reference which ultimately invokes a
callback in A. Say that the instance throws an exception from within
its callback in order to unwind all the way to its outer stack frames,
across the intermediate functions in some other Wasm instance(s):

```
                A.f   ---------call--------->   B.g   --------call--------->    A.callback
                 ^                                                                  v
               catch $t                                                           throw $t
                 |                                                                  |
                 `----------------------------<-------------------------------------'
```

The instance A expects that the exception that it throws from its
callback function to `f` is a *local* concern to that instance only,
and that B cannot interfere. After all, if the exception tag is
defined inside A, and Wasm preserves modularity, then B should not be
able to name that tag to catch exceptions by that tag, even if it also
uses exception handling internally. The two modules should not
interact: that is the meaning of modularity, and it permits us to
reason about each instance's behavior locally, with the effects of
"the rest of the world" confined to imports and exports.

Unfortunately, if one designed a straightforward "static" tag-matching
scheme, this might not be the case if B were an instance of the same
module as A: in that case, if B also used a tag `$t` internally and
registered handlers for that tag, it could interfere with the desired
throw/catch behavior, and violate modularity.

So the Wasm exception handling standard specifies that tags have
*dynamic instances* as well, just as memories, tables and globals
do. (Put in programming-language theory terms, tags are *generative*.)
Each instance of a module creates its own dynamic identities for the
statically-defined tags in those modules, and uses those dynamic
identities to tag exceptions and find handlers. This means that no
matter what instance B is, above, if instance A does not export its
tag `$t` for B to import, there is no way for B to catch the thrown
exception explicitly (it can still catch *all* exceptions, and it may
do so and rethrow to perform some cleanup). Local modular reasoning is
restored.

Once we have tags as dynamic entities, just like Wasm memories, we can
take the same approach that we do for the other entities to allow them
to be imported and exported. Thus, visibility of exception payloads
and ability for modules to catch certain exceptions is completely
controlled by the instantiation graph and the import/export linking,
just as for all other Wasm storage.

This is surprising (or at least was to me)! It creates some pretty
unique implementation challenges in the unwinder -- in essence, it
means that we need to know about instance identity for each stack
frame, not just static code location and handler list.

## Compiling Exceptions in Cranelift

Before we implement the primitives for exception handling in Wasmtime,
we need to support exceptions in our underlying compiler backend,
Cranelift.

Why should this be a compiler concern? What is special about
exceptions that makes them different from, say, new Wasm instructions
that implement additional mathematical operators (when we already have
many arithmetic operators in the IR), or Wasm memories (when we
already have loads/stores in the IR)?

In brief, the complexities come in three flavors: new kinds of control
flow, fundamentally different than ordinary branches or calls in that
they are "externally actuated" (by the unwinder); a new facet of the
ABI (that we get to define!) that governs how the unwinder interacts
with compiled code; and interactions between the "scoped" nature of
handlers and inlining in particular. We'll talk about each below.

Note that much of this discussion started with an
[RFC](https://github.com/bytecodealliance/rfcs/pull/36) for
Wasmtime/Cranelift, which had been posted way back in August of 2024
by Daniel Hillerstrom with help from my colleague Nick Fitzgerald, and
was discussed then; many of the choices within were subsequently
refined as I discovered interesting nuances during implementation and
we talked them through.

### Control Flow

There are a few ways to think about exception handlers from the point
of view of compiler [IR (intermediate
representation)](https://en.wikipedia.org/wiki/Intermediate_representation).
First, let's recognize that exception handling (i) is a form of
control flow, and (ii) has all the same implications various compiler
stages that other kinds of control flow do. For example, the register
allocator has to consider how to get registers into the right state
whenever control moves from one basic block to the next ("edge
moves"); exception catches are a new kind of edge, and so the regalloc
needs to be aware of that, too.

One could see every call or other opcode that could throw as having
regular control-flow edges to every possible handler that could
match. I'll call this the "regular edges" approach. The upside is that
it's pretty simple to retrofit: one "only" needs to add new kinds of
control-flow opcodes that have out-edges, but that's already a kind of
thing that IRs have. The disadvantage is that, in functions with a lot
of possible throwing opcodes and/or handlers, the overhead can get
quite high. And control-flow graph overhead is a bad kind of overhead:
many analyses' runtimes are heavily dependent the edge and node (basic
block) counts, sometimes superlinearly.

The other major option is to build a kind of *implicit* new control
flow into the IR's semantics. For example, one could lower the
source-language semantics of a "try block" down to regions in the IR,
with one set of handlers attached.  This is clearly more efficient
than adding out-edges from (say) every callsite within the try-block
to every handler in scope. On the other hand, it's hard to understate
how invasive this change would be. This means that *every* traversal
over IR, analyzing dataflow or reachability or any other property, has
to consider these new implicit edges anyway. In a large established
compiler like Cranelift, we can lean on Rust's type system for a lot
of different kinds of refactors, but changing a fundamental invariant
goes beyond that: we would likely have a long tail of issues stemming
from such a change, and it would permanently increase the cognitive
overhead of making new changes to the compiler. In general we want to
trend toward a smaller, simpler core and compositional rather than
entangled complexity.

Thus, the choice is clear: in Cranelift we opted to introduce one new
instruction, `try_call`, that calls a function and catches (some)
exceptions.  In other words, there are now two possible kinds of
return paths: a normal return or (possibly one of many) exceptional
return(s). The handled exceptions and block targets are enumerated in
an *exception table*. Because there are control-flow edges stemming
from this opcode, it is a block terminator, like a conditional
branch. It looks something like (in Cranelift's IR, CLIF):

```
function %f0(i32) -> i32, f32, f64 {
    sig0 = (i32) -> f32 tail
    fn0 = %g(i32) -> f32 tail

    block0(v1: i32):
        v2 = f64const 0x1.0
        ;; exception-catching callsite
        try_call fn0(v1), sig0, block1(ret0, v2), [ tag0: block2(exn0), default: block3(exn0) ]

    ;; normal return path
    block1(v3: f32, v4: f64):
        v5 = iconst.i32 1
        return v5, v3, v4

    ;; exception handler for tag0
    block2(v6: i64):
        v7 = ireduce.i32 v6
        v8 = iadd_imm.i32 v7, 1
        v9 = f32const 0x0.0        
        return v8, v9, v2

    ;; exception handler for all other exceptions
    block2(v10: i64):
        v11 = ireduce.i32 v10
        v12 = f32.const 0x0.0
        v13 = f64.const 0x0.0
        return v11, v12, v13
}
```

There are a few aspects to note here. First, why are we only concerned
with calls? What about other sources of exceptions? This is an
important invariant in the IR: exception *throws* are *only externally
sourced*. In other words, if an exception has been thrown, if we go
deep enough into the callstack, we will find that that throw was
implemented by calling out into the runtime.  The IR itself has no
other opcodes that throw! This turns out to be sufficient: (i) we only
need to build what Wasmtime needs, here, and (ii) we can implement
Wasm's throw opcodes as "libcalls", or calls into the Wasmtime
runtime. So, within Cranelift-compiled code, exception throws always
happen at callsites. We can thus get away with adding only one opcode,
`try_call`, and attach handler information directly to that opcode.

The next characteristic of note is that handlers are ordinary basic
blocks.  Thus may not seem remarkable unless one has seen other
compiler IRs, such as LLVM's, where exception handlers are definitely
special: they start with "landing pad" instructions, and cannot be
branched to as ordinary basic blocks. That might look something like:

```
function %f() {
    block0:
        ;; Callsite defining a return value `v0`, with normal
        ;; return path to `block1` and exception handler `block2`.
        v0 = try_call ..., block1, [ tag0: block2 ]
        
    block1:
        ;; Normal return; use returned value.
        return v0
        
    block2 exn_handler: ;; Specially-marked block!
        ;; Exception handler payload value.
        v1 = exception_landing_pad
        ...
}
```

This bifurcation of kinds of blocks (normal and exception handler) is
undesirable from our point of view: just as exceptional edges add a
new cross-cutting concern that every analysis and transform needs to
consider, so would new kinds of blocks with restrictions. It was an
explicit design goal (and we have tests that show!) that the same
block can be both an ordinary block and a handler block -- not because
that would be common, necessarily (handlers usually do very different
things than normal code paths), but because it's one less weird quirk
of the IR.

But then if handlers are normal blocks, the data flow question becomes
very interesting. An exception-catching call, unlike every other
opcode in our IR, has *conditionally-defined values*: that is, its
normal function return value(s) are available only if the callee
returns normally, and the *exception payload value(s)*, which are
passed in from the unwinder and carry information about the caught
exception, are available only if the callee throws an exception that
we catch. How can we ensure that these values are represented such
that they can only be used in valid ways? We can't make them all
regular SSA definitions of the opcode: that would mean that all
successors (regular return and exceptional) get to use them, as in:

```
function %f() {
    block0:
        ;; Callsite defining a return value `v0`, with normal return path
        ;; to `block1` and exception handler `block2`.
        v0 = try_call ..., block1, [ tag0: block2 ]
      
    block1:
        ;; Use `v0` legally: it is defined on normal return.
        return v0
      
    block2:
        ;; Oops! We use `v0` here, but the normal return value is undefined
        ;; when an exception is caught and control reaches this handler block.
        return v0
}
```

This is the reason that a compiler may choose to make handler blocks
special: by bifurcating the universe of blocks, one ensures that
normal-return and exceptional-return values are used only where
appropriate. Some compiler IRs reify exceptional return payloads via
"landing pad" instructions that must start handler blocks, just as
phis start regular blocks (in phi- rather than blockparam-based
SSA). But, again, this bifurcation is undesirable.

Our insight here, after [a lot of
discussion](https://github.com/bytecodealliance/rfcs/pull/36), was to
put the definitions where they belong: *on the edges*. That is,
regular returns are only defined once we know we're following the
regular-return edge, and likewise for exception payloads. But we don't
want to have special instructions that must be in the successor
blocks: that's a weird distributed invariant and, again, likely to
lead to bugs when transforming IR. Instead, we leverage the fact that
we use *blockparam-based SSA* and we widen the domain of allowable
block-call arguments.

Whereas previously one might end a block like `brif v1, block2(v2,
v3), block3(v4, v5)`, i.e. with blockparams assigned values in the
chosen successor via a list of value-uses in the branch, we now allow
(i) SSA values, (ii) a special "normal return value" sentinel, or
(iii) a special "exceptional return value" sentinel. The latter two
are indexed because there can be more than one of each. So one can
write a block-call in a `try_call` as `block2(ret0, v1, ret1)`, which
passes the two return values of the call and a normal SSA value; or
`block3(exn0, exn1)`, which passes just the two exception payload
values.  We do have a new well-formedness check on the IR that ensures
that (i) normal returns are used only in the normal-return blockcall,
and exception payloads are used only in the handler-table blockcalls;
(ii) normal returns' indices are bounded by the signature; and (iii)
exception payloads' indices are bounded by the ABI's number of
exception payload values; but all of these checks are local to the
instruction, not distributed across blocks. That's nice, and conforms
with the way that all of our other instructions work, too. (Block-call
argument types are then checked against block-parameter types in the
successor block, but that happens the same as for any branch.) So we
have, repeating from above, a callsite like

```
    block1:
        try_call fn0(v1), block2(ret0), [ tag0: block3(exn0, exn1) ]
```

with all of the desired properties: only one kind of block, explicit
control flow, and SSA values defined only where they are legal to use.

All of this may seem somewhat obvious in hindsight, but as attested by
the above GitHub discussions and Cranelift weekly meeting minutes, it
was far from clear when we started how to design all of this to
maximize simplicity and generality and minimize quirks and
footguns. I'm pretty happy with our final design: it feels like a
natural extension of our core blockparam-SSA control flow graph, and I
managed to [put it into the
compiler](https://github.com/bytecodealliance/wasmtime/pull/10510)
without too much trouble at all (well, [a
few](https://github.com/bytecodealliance/wasmtime/pull/10502)
[PRs](https://github.com/bytecodealliance/wasmtime/pull/10485) and
[associated](https://github.com/bytecodealliance/wasmtime/pull/10555)
[fixes](https://github.com/bytecodealliance/wasmtime/pull/10554) to
Cranelift
[and](https://github.com/bytecodealliance/regalloc2/pull/214)
[regalloc2](https://github.com/bytecodealliance/regalloc2/pull/220)
[functionality](https://github.com/bytecodealliance/regalloc2/pull/216)
[and testing](https://github.com/bytecodealliance/regalloc2/pull/224);
and I'm sure I've missed a few).

### Data Flow and ABI

So we have defined an IR that can express exception handlers -- what
about the interaction between this function body and the unwinder? We
will need to define a different kind of semantics to nail down that
interface: in essence, it is a property of the [ABI (Application
Binary
Interface)](https://en.wikipedia.org/wiki/Application_Binary_Interface).

As mentioned above, existing exception-handling ABIs exist for native
code, such as compiled C++. While we are certainly willing to draw
inspiration from native ABIs and align with them as much as makes
sense, in Wasmtime we already define our own ABI[^10], and so we are
not necessarily constrained by existing standards.

[^10]: In particular, we have defined our own ABI in Wasmtime to allow
       universal tail calls between any two signatures to work, as
       required by the Wasm tail-calling opcodes. This ABI, called
       "`tail`", is based on the standard System V calling convention
       but differs in that the callee cleans up any stack arguments.

In particular, there is a very good reason we would prefer not to: to
unwind to a particular exception handler, register state must be
restored as specified in the ABI, and the standard Itanium ABI
requires the usual callee-saved ("non-volatile") registers on the
target ISA to be restored. But this requires (i) having the register
state at time of throw, and (ii) processing unwind metadata at each
stack frame as we walk up the stack, reading out values of saved
registers from stack frames. The latter is [already
supported](https://github.com/bytecodealliance/wasmtime/pull/2710)
with a generic "unwind pseudoinstruction" framework I built four years
ago, but would still add complexity to our unwinder, and this
complexity would be load-bearing for correctness; and the former is
extremely difficult with Wasmtime's normal runtime-entry
trampolines. So we instead choose to have a simpler exception ABI: all
`try_call`s, that is, callsites with handlers, clobber *all*
registers. This means that the compiler's ordinary register-allocation
behavior will save all live values to the stack and restore them on
either a normal or exceptional return. We only have to restore the
stack (stack pointer and frame pointer registers) and redirect the
program counter (PC) to a handler.

The other aspect of the ABI that matters to the exception-throw
unwinder is exceptional payload. The native Itanium ABI specifies two
registers on most platforms (e.g.: `rax` and `rdx` on x86-64, or `x0`
and `x1` on aarch64) to carry runtime-defined playload; so for
simplicity, we adopt the same convention.

That's all well and good; now how do we implement `try_call` with the
appropriate register-allocator behavior to conform to this? We already
have fairly complex ABI handling
([machine-independent](https://github.com/bytecodealliance/wasmtime/blob/main/cranelift/codegen/src/machinst/abi.rs)
[and](https://github.com/bytecodealliance/wasmtime/blob/main/cranelift/codegen/src/isa/x64/abi.rs)
[five](https://github.com/bytecodealliance/wasmtime/blob/main/cranelift/codegen/src/isa/aarch64/abi.rs)
[different](https://github.com/bytecodealliance/wasmtime/blob/main/cranelift/codegen/src/isa/s390x/abi.rs)
[architecture](https://github.com/bytecodealliance/wasmtime/blob/main/cranelift/codegen/src/isa/riscv64/abi.rs)
[implementations](https://github.com/bytecodealliance/wasmtime/blob/main/cranelift/codegen/src/isa/pulley_shared/abi.rs))
in Cranelift, but it follows a general pattern: we generate a single
instruction at the register-allocator level, and emit uses and defs
with fixed-register constraints. That is, we tell regalloc that
parameters must be in certain registers (e.g., `rdi`, `rsi`, `rcx`,
`rdx`, `r8`, `r9` on x86-64 System-V calling-convention platforms, or
`x0` up to `x7` on aarch64 platforms) and let it handle any necessary
moves. So in the simplest case, a call might look like (on aarch64),
with register-allocator uses/defs and constraints annotated:

```
bl (call) v0 [def, fixed(x0)], v1 [use, fixed(x0)], v2 [use, fixed(x1)]
```

It is not always this simple, however: calls are not actually always a
single instruction, and this turned out to be quite problematic for
exception-handling support. In particular, when values are returned in
memory, as the ABI specifies they must be when there are more return
values than registers, we add (or added, prior to this work!) load
instructions *after* the call to load the extra results from their
locations on the stack. So a callsite might generate instructions like

```
bl v0 [def, fixed(x0)], ..., v7 [def, fixed(x7)] # first eight return values
ldr v8, [sp]     # ninth return value
ldr v9, [sp, #8] # tenth return value
```

and so on. This is problematic simply because we said that the
`try_call` was a terminator; and it is at the IR level, but no longer
at the regalloc level, and regalloc expects correctly-formed
control-flow graphs as well. So I had to [do a
refactor](https://github.com/bytecodealliance/wasmtime/pull/10502) to
merge these return-value loads into a single regalloc-level
pseudoinstruction, and in turn this cascaded into a few regalloc fixes
([allowing more than 256
operands](https://github.com/bytecodealliance/regalloc2/pull/226) and
[more aggressively splitting live-ranges to allow worst-case
allocation](https://github.com/bytecodealliance/regalloc2/pull/214),
plus a [fix to the live range-splitting
fix](https://github.com/bytecodealliance/regalloc2/pull/220) and a
[fuzzing
improvement](https://github.com/bytecodealliance/regalloc2/pull/216)).

There is one final question that might arise when considering the
interaction of exception handling and register allocation in
Cranelift-compiled code. In Cranelift, we have an invariant that the
register allocator is allowed to insert *moves* between any two
instructions -- register-to-register, or loads or stores to/from
spill-slots in the stack frame, or moves between different spill-slots
-- and indeed it does this whenever there is more state than fits in
registers. It also needs to insert *edge moves* "between" blocks,
because when jumping to another spot in the code, we might need the
register values in a differently-assigned configuration. When we have
an unwinder that jumps to a different spot in the code to invoke a
handler, we need to ensure that all the proper moves have executed so
the state is as expected.

The answer here turns out to be a careful argument that we don't need
to do anything at all. (That's the best kind of solution to a problem,
but only if one is correct!) The crux of the argument has to do with
critical edges. A critical edge is one from a block with multiple
successors to one with multiple predecessors: for example, in the graph

```
   A    D
  / \  /
 B   C
```

where A can jump to B or C, and D can also jump to C, then A-to-C is a
critical edge. The problem with critical edges is that there is
nowhere to put code that has to run on the transition from A to C (it
can't go in A, because we may go to B or C; and it can't go in C,
because we may have come from A or D). So the register allocator
prohibits them, and we "split" them when generating code by inserting
empty blocks (`e` below) on them:

```
   A    D
  / \   |
 |   e  |
 |   \ /
 B    C
```

The key insight is that a `try_call` always has more than one
successor as long as it has a handler (because it must always have a
normal return-path successor too)[^11]; and in this case, because we
split critical edges, the immediate successor block on the
exception-catch path has only one predecessor. So the register
allocator can always put its moves that have to run on catching an
exception in the successor (handler) block rather than the predecessor
block. Our rule for where to put edge moves prefers the successor
(block "after" the edge) unless it has multiple in-edges, so this was
already the case. The only thing we have to be careful about is to
record the address of the *inserted edge block*, if any (`e` above),
rather than the IR-level handler block (`C` above), in the handler
table.

[^11]: It's not compiler hacking without excessive trouble from
       edge-cases, of course, so we had one [interesting
       bug](https://github.com/bytecodealliance/wasmtime/pull/10709)
       from the *empty handler-list* case which means we have to force
       edge-splitting anyway for all `try_call`s for this subtle
       reason.

And that's pretty much it, as far as register allocation is concerned!

We've now covered the basics of Cranelift's exception support. At this
point, having landed the compiler half but not the Wasmtime half, I
context-switched away for a bit, and in the meantime, bjorn3 picked
this support up right away as a means to add panic-unwinding support
to
[`rustc_codegen_cranelift`](https://github.com/rust-lang/rustc_codegen_cranelift),
the Cranelift-based Rust compiler backend. With [a few small
changes](https://github.com/bytecodealliance/wasmtime/pull/10593) they
contributed, and a [followup edge-case
fix](https://github.com/bytecodealliance/wasmtime/pull/10709) and a
[refactor](https://github.com/bytecodealliance/wasmtime/pull/10609),
panic-unwinding support in `rustc_codegen_cranelift` was working. That
was very good intermediate validation that what I had built was usable
and relatively solid.

## Exceptions in Wasmtime

We have a compiler that supports exceptions; we understand Wasm
exception semantics; let's build support into Wasmtime! How hard could
it be?

### Challenge 1: Garbage Collection Interactions

I started by sketching out the codegen for each of the three opcodes
(`try_table`, `throw`, and `throw_ref`). My mental model at the very
beginning of this work, having read but not fully internalized the
Wasm exception-handling proposal, was that I would be able to
implement a "basic" throw/catch first, and then somehow build the
`exnref` objects later. And I had figured I could build `exnref`s in a
(in hindsight) somewhat hacky way, by aggregating values together in a
kind of tuple and creating a table of such tuples indexed by exnrefs,
just as Wasmtime does for externrefs.

This understanding quickly gave way to a deeper one when I realized a
few things:

- Exception objects (exnrefs) can carry references to other GC objects
  (that is, GC types can be part of the payload signature of an
  exception), and GC objects can store exnrefs in fields. Hence,
  exnrefs need to be traced, and can participate in GC cycles; this
  either implies an additional collector on top of our GC collector
  (ugh) or means that exception objects needs to be on the GC heap
  when GC is enabled.

- We'll need a host API to introspect and build exception objects, and
  we already have nice host APIs for GC objects.

There was a question [in an extensively-discussed
PR](https://github.com/bytecodealliance/wasmtime/pull/11230) whether
we could build a cheap "subset" implementation that doesn't mandate
the existence of a GC heap for storing exception objects. This would
be great in theory for guests that use exceptions for C-level
setjmp/longjmp but no other GC features.  However, it's a little
tricky for a few reasons. First, this would require the subset to
exclude `throw_ref` (so we don't have to invent another kind of
exception object storage). But it's not great to subset the spec --
and `throw_ref` is not just for GC guest languages, but also for
rethrows. Second, more generally, this is additional maintenance and
testing surface that we'd rather not have for now. Instead we expect
that we can make GC cheap enough, and its growth heuristic smart
enough that a "frequent setjmp/longjmp" stress-test of exceptions (for
example) should live within a very small (e.g., few-kilobyte) GC heap,
essentially approximating the purpose-built storage. My colleague Nick
Fitzgerald (who built and is driving improvements to Wasmtime's GC
support) wrote up [a nice
issue](https://github.com/bytecodealliance/wasmtime/issues/11256)
describing the tradeoffs and ideas we have.

All of that said, we'll only build one exception object implementation
-- great! -- but it will have to be a new kind of GC object. This
spawned a [large
PR](https://github.com/bytecodealliance/wasmtime/pull/11230) to build
out exception objects first, prior to actual support for throwing and
catching them, with host APIs to allocate them and inspect their
fields. In essence, they are structs with immutable fields and with a
less-exposed type lattice and no subtyping.

### Challenge 2: Generative Tags and Dynamic Identity

So there I was, implementing the `throw` instruction's libcall
(runtime implementation), and finally getting to the heart of the
matter: the unwinder itself, which walks stack frames to find a
matching exception handler.  This is the final bit of functionality
that ties it all together. We're almost there!

But wait: check out that [spec
language](https://webassembly.github.io/spec/core/exec/instructions.html#xref-syntax-instructions-syntax-instr-control-mathsf-throw-x).
We load the "tag address" from the store in step 9: we allocate the
exception instance `{tag z.tags[x], fields val^n}`. What is this
`tags` array on the store (`z`) in the runtime semantics? Tags have
dynamic identity, not static identity! (This is the part where I
learned about the thing I described
[above](#dynamic-identity-and-compositionality).)

This was a problem, because I had defined exception tables to
associate handlers with tags that were identified by integer (`u32`)
-- like most other entities in Cranelift IR, I had figured this would
be sufficient to let Wasmtime define indices (say: index of the tag in
the module), and then we could compare static tag IDs.

Perhaps this is no problem: the static index defines the entity ID in
the module (defined or imported tag), and we can compare that and the
instance ID to see if a handler is a match. But how do we get the
instance ID from the stack frame?

It turns out that Wasmtime didn't have a way, because nothing had
needed that yet. (This deficiency had been noticed before when
implementing Wasm coredumps, but there hadn't been enough reason or
motivation to fix it then.) So I [filed an
issue](https://github.com/bytecodealliance/wasmtime/issues/11285) with
a few ideas. We could add a new field in every frame storing the
instance pointer -- and in fact this is a simple version of what at
least one other production Wasm implementation, in the SpiderMonkey
web engine,
[does](https://searchfox.org/firefox-main/rev/643d732886fe0de4e2a3eee3c5ed9bd0d47c77cf/js/src/wasm/WasmFrame.h#112-115)
(though as described in that `[SMDOC]` comment, it only stores
instance pointers on transitions between frames of different
instances; this is enough for the unwinder when walking linearly up
the stack). But that would add overhead to *every* Wasm function (or
with SpiderMonkey's approach, require adding trampolines between
instances, which would be a large change for Wasmtime), and exception
handling is still used somewhat rarely in practice.  Ideally we'd have
a "pay-as-you-go" scheme with as little extra complexity as posible.

Instead, I came up with an idea to [add "dynamic context" items to
exception handler
lists](https://github.com/bytecodealliance/wasmtime/pull/11321). The
idea is that we inject an SSA value into the list and it is stored in
a stack location that is given in the handler table metadata, so the
stack-walker can find it. To Cranelift, this is some arbitrary opaque
value; Wasmtime will use it to store the raw instance pointer
(`vmctx`) for use by the unwinder.

This filled out the design to a more general state nicely: it is
symmetric with exception payload, in the sense that the compiled code
can communicate context or state *to* the unwinder as it reads the
frames, and the unwinder in turn can communicate data *to* the
compiled code when it unwinds.

It turns out -- though I didn't intend this at all at the time -- that
this also nicely solves the *inlining problem*. In brief, we want all
of our IR to be "local", not treating the function boundary specially;
this way, IR can be composed by the inliner without anything
breaking. Storing some "current instance" state for the whole function
will, of course, break when we inline a function from one module
(hence instance) into another!

Instead, we can give a nice operational semantics to handler tables
with dynamic-context items: the unwinder should read left-to-right,
updating its "current dynamic context" at each dynamic-context item,
and checking for a tag match at tag-handler items. Then the inliner
can *compose* exception tables: when a `try_call` callsite inlines a
function body as its callee, and that body itself has any other
callsites, we attach a handler table that simply concatenates the
exception table items.

It's important, here, to point out another surprising fact about Wasm
semantics: we *cannot do certain optimizations* to resolve handlers
statically or optimize the handler list, or at least not naively,
without global program analysis to understand where tags come
from. For example, if we see a handler for tag 0 then one for tag 1,
and we see a throw for tag 1 directly inside the `try_table`s body, we
cannot necessarily resolve it: tag 0 and tag 1 could be the same tag!

Wait, how can that be? Well, consider *tag imports*:

```
(module
  (import "test" "e0" (tag $e0))
  (import "test" "e1" (tag $e1))

  (func ...
        (try_table
                   (catch $e0 $b0)
                   (catch $e1 $b1)
                   (throw $e1)
                   (unreachable))))
```

We could instantiate this module giving the same dynamic tag instance
twice, for both imports; then the first handler (to block `$b0`)
matches; or separate tags; then the block `$b1` matches. The only way
to win the optimization game is not to play -- we have to preserve the
original handler list.  Fortunately, that makes the compiler's job
easier. We transcribe the `try_table`'s handlers directly to Cranelift
exception-handler tables, and those directly to metadata in the
compiled module, read in exactly that order by the unwinder's
handler-matching logic.

### Challenge 3: Rooting

Since exception objects are GC-managed objects, we have to ensure that
they are properly *rooted*: that is, any handles to these objects
outside of references inside other GC objects need to be known to the
GC so the objects remain alive (and so the references are updated in
the case of a moving GC).

Within a Wasm-to-Wasm exception throw scenario, this is fairly easy:
the references are rooted in the compiled code on either side of the
control-flow transfer, and the reference only briefly passes through
the unwinder. As long as we are careful to handle it with the
appropriate types, all will work fine.

Passing exceptions across the host/Wasm boundary is another matter,
though. We support the full matrix of {host, Wasm} x {host, Wasm}
exception catch/throw pairs: that is, exceptions can be thrown from
native host code called by Wasm (via a Wasm import), and exceptions
can be thrown out of Wasm code and returned as a kind of error to the
host code that invoked the Wasm. This works by boxing the exception
inside an `anyhow::Error` so we use Rust-style value-based error
propagation (via `Result` and the `?` operator) in host code.

What happens when we have a value inside the `Error` that holds an
exception object in the Wasmtime `Store`? How does Wasmtime know this
is rooted?

The answer in Wasmtime prior to recent work was to use one of two
kinds of external rooting wrappers: `Rooted` and
`ManuallyRooted`. Both wrappers hold an index into a table contained
inside the `Store`, and that table contains the actual GC
reference. This allows the GC to easily see the roots and update them.

The difference lies in the lifetime disciplines: `ManuallyRooted`
requires, as the name implies, manual unrooting; it has no `Drop`
implementation, and so easily creates leaks. `Rooted`, on the other
hand, had a LIFO (last-in first-out) discipline based on a `Scope`, an
RAII type created by the embedder (user) of Wasmtime. `Rooted` GC
references that escape that dynamic scope are unrooted, and will cause
an error (panic) at runtime if used. Neither of those behaviors is
ideal for a value type -- an exception -- that is *meant* to escape
scopes via `?`-propagation.

The design that we landed on, instead, takes a different and much
simpler approach: the `Store` has a single, explicit root slot for the
"pending exception", and host code can set this and then return a
*sentinel value* (`wasmtime::ThrownException`) in the `Result`'s error
type (boxed up into an `anyhow::Error`). This easily allows
propagation to work as expected, with no unbounded leaks (there is
only one pending exception that is rooted) and no unrooted propagating
exceptions (because no actual GC reference propagates, only the
sentinel).

As a side-quest, while thinking through this rooting dilemma, I also
[realized](https://github.com/bytecodealliance/wasmtime/issues/11445)
that it *should* be possible to create an "owned" rooted reference
that behaves more like a conventional owned Rust value (e.g. `Box`);
hence [`OwnedRooted` was born to replace
`ManuallyRooted`](https://github.com/bytecodealliance/wasmtime/pull/11514).
This type works without requiring access to the `Store` to unroot when
dropped; the key idea is to hold a refcount to a separate tiny
allocation that is used as a "drop flag", and then have the store
periodically scan these drop-flags and lazily remove roots, with a
thresholding algorithm to give that scanning amortized linear-time
behavior.[^7]

[^7]: Of course, while doing this, I managed to create
      [CVE-2025-61670](https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-vvp9-h8p2-xwfc)
      in the C/C++ API by a combination of (i) a simple typo in the C
      FFI bindings (`as` vs. `from`, which is important when
      transferring ownership!) and (ii) not realizing that the C++
      wrapper does not properly maintain single ownership. We didn't
      have ASAN tests, so I didn't see this upfront; Alex discovered
      the issue while updating the Python bindings (which quickly
      found the leak) and managed the CVE. Sorry and thanks!

Now that we have this, in theory, we could pass an
`OwnedRooted<ExnRef>` directly in the `Error` type to propagate
exceptions through host code; but the store-rooted approach is simple
enough, has a marginal performance advantage (no separate allocation),
and so I don't see a strong need to change the API at the moment.

### Life of an Exception: Quick Walkthrough

Now that we've discussed all the design choices, let's walk through
the life an exception throw/catch, from start to finish. Let's assume
a Wasm-to-Wasm throw/catch for simplicity here.

- First, the Wasm program is executing within a `try_table`, which
  results in an exception handler [catch blocks being
  created](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/cranelift/src/translate/code_translator.rs#L609-L613)
  for each handler case listed in the `try_table` instruction. The
  [`create_catch_block`](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/cranelift/src/translate/code_translator.rs#L4325)
  function generates code that invokes
  [`translate_exn_unbox`](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/cranelift/src/func_environ/gc/enabled.rs#L415),
  which reads out all of the fields from the exception object and
  pushes them onto the Wasm operand stack in the handler path. This
  handler block is registered in the
  [`HandlerState`](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/cranelift/src/translate/stack.rs#L570),
  which tracks the current lexical stack of handlers (and hands out
  checkpoints so that when we pop out of a Wasm block-type operator,
  we can pop the handlers off the state as well). These handlers are
  [provided as an
  iterator](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/cranelift/src/translate/stack.rs#L611)
  which is [passed to the `translate_call`
  method](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/cranelift/src/translate/code_translator.rs#L661)
  and eventually ends up [creating an exception
  table](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/cranelift/src/func_environ.rs#L2366-L2379)
  on a `try_call` instruction. This `try_call` will invoke whatever
  Wasm code is about to throw the exception.
- Then, the Wasm program reaches a `throw` opcode, which is
  [translated](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/cranelift/src/translate/code_translator.rs#L621)
  via
  [`FuncEnvironment::translate_exn_throw`](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/cranelift/src/func_environ.rs#L2825)
  to a [three-operation
  sequence](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/cranelift/src/func_environ/gc/enabled.rs#L473-L482)
  that fetches the current instance ID (via a libcall into the
  runtime), allocates a new exception object with that instance ID and
  a fixed tag number and fills in its slots with the given values
  popped from the Wasm operand stack, and delegates to `throw_ref`.
- The `throw_ref` opcode implementation then invokes the
  [`throw_ref`](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/cranelift/src/func_environ/gc/enabled.rs#L519)
  libcall.
- This libcall is deceptively simple: its
  [implementation](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/wasmtime/src/runtime/vm/libcalls.rs#L1695-L1707)
  sets the pending exception on the store, and returns a sentinel that
  signals a pending exception. That's it!
- This works because the glue code for *all* libcalls processes errors
  (via the
  [`HostResult`](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/wasmtime/src/runtime/vm/traphandlers.rs#L152)
  trait implementations) and eventually reaches [this
  case](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/wasmtime/src/runtime/vm/traphandlers.rs#L773-L786)
  which sees a pending exception sentinel and invokes
  [`compute_handler`](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/wasmtime/src/runtime/vm/throw.rs#L15). Now
  we're getting to the heart of the exception-throw implementation.
- `compute_handler` walks the stack with
  [`Handler::find`](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/unwinder/src/throw.rs#L45),
  which itself is based on
  [`visit_frames`](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/unwinder/src/stackwalk.rs#L248),
  which does about what one would expect for code with a frame-pointer
  chain: it walks the singly-linked list of frames. At each frame, the
  [closure](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/wasmtime/src/runtime/vm/throw.rs#L51)
  that `compute_handler` gave to `Handler::find` looks up the program
  counter in that frame (which will be a return address, i.e., the
  instruction after the call that created the next lower frame) using
  [`lookup_module_by_pc`](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/wasmtime/src/runtime/module/registry.rs#L74)
  to find a `Module`, which itself has an
  [`ExceptionTable`](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/unwinder/src/exception_table.rs#L225)
  (a parser for serialized metadata produced during compilation from
  Cranelift metadata) that knows how to look up a PC within a
  module. This will produce an [`Iterator` over
  handlers](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/unwinder/src/exception_table.rs#L310)
  which we [test in
  order](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/wasmtime/src/runtime/vm/throw.rs#L63)
  to see if any match. (The groups of exception-handler table items
  that come out of Cranelift are post-processed
  [here](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/unwinder/src/exception_table.rs#L144)
  to generate the tables that the above routines search.)
- If we find a handler, that is, if [the dynamic tag instance is the
  same](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/wasmtime/src/runtime/vm/throw.rs#L108-L109)
  or [we reach a catch-all
  handler](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/wasmtime/src/runtime/vm/throw.rs#L67),
  then we have an exception handler! We return the PC and SP to
  restore
  [here](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/wasmtime/src/runtime/vm/throw.rs#L112-L120),
  computing SP via an FP-to-SP offset (i.e., the size of the frame),
  which is fixed and included in the exception tables when we
  construct them.
- That action then becomes an `UnwindState::UnwindToWasm`
  [here](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/wasmtime/src/runtime/vm/traphandlers.rs#L779).
- This `UnwindToWasm` state then triggers [this
  case](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/wasmtime/src/runtime/vm/traphandlers.rs#L913-L933)
  in the `unwind` libcall, which is invoked whenever any libcall
  returns an error code; that eventually calls the no-return function
  `resume_to_exception_handler`, which is a little function written in
  inline assembly that does exactly what it says on the tin. [These
  three
  instructions](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/unwinder/src/arch/x86.rs#L32-L34)
  set `rsp` and `rbp` to their new values, and jump to the new `rip`
  (PC). The same stub exists for each of our four native-compilation
  architectures (x86-64 above,
  [aarch64](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/unwinder/src/arch/aarch64.rs#L60-L62),
  [riscv64](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/unwinder/src/arch/riscv64.rs#L29-L31),
  and
  [s390x](https://github.com/bytecodealliance/wasmtime/blob/8e22ff89f6affe4f79fcebdb416d0ab401d43c97/crates/unwinder/src/arch/s390x.rs#L32-L33)[^8]).
  That transfers control to the catch-block created above, and the
  Wasm continues running, unboxing the exception payload and running
  the handler!

[^8]: It turns out that even three lines of assembly are hard to get
      right: the s390x variant [had a
      bug](https://github.com/bytecodealliance/wasmtime/pull/10973)
      where we got the register constraints wrong (GPR 0 is special on
      s390x, and a branch-to-register can only take GPR 1--15; we
      needed a different constraint to represent that)and had a
      miscompilation as a result. Thanks to our resident s390x
      compiler hacker Ulrich Weigand for tracking this down.

## Conclusion

So we have Wasm exception handling now! For all of the interesting
design questions we had to work through, the end was pretty
anticlimactic. I landed [the final
PR](https://github.com/bytecodealliance/wasmtime/pull/11326), and
after a follow-up cleanup PR
([1](https://github.com/bytecodealliance/wasmtime/pull/11467)) and
some fuzzbug fixes
([1](https://github.com/bytecodealliance/wasmtime/pull/11500)
[2](https://github.com/bytecodealliance/wasmtime/pull/11507)
[3](https://github.com/bytecodealliance/wasmtime/pull/11530)
[4](https://github.com/bytecodealliance/wasmtime/pull/11531)
[5](https://github.com/bytecodealliance/wasmtime/pull/11535)
[6](https://github.com/bytecodealliance/wasmtime/pull/11564)
[7](https://github.com/bytecodealliance/wasmtime/pull/11554)) having
mostly to do with null-pointer handling and other edge cases in the
type system, plus one interaction with tail-calls (and a
separate/pre-existing [s390x ABI
bug](https://github.com/bytecodealliance/wasmtime/pull/11689) that it
uncovered), it has been basically stable. We pretty quickly got a few
user reports:
[here](https://bytecodealliance.zulipchat.com/#narrow/channel/217117-cranelift/topic/Running.20lua.205.2E1.20wasi/near/535368031)
it was reported as working for a Lua interpreter using setjmp/longjmp
inside Wasm based on exceptions, and
[here](https://bytecodealliance.zulipchat.com/#narrow/channel/217126-wasmtime/topic/WebAssembly.20exceptions.20proposal.20is.20now.20implemented/near/536299383)
it enabled Kotlin-on-Wasm to run and [pass a large
testsuite](https://bytecodealliance.zulipchat.com/#narrow/channel/217126-wasmtime/topic/WebAssembly.20exceptions.20proposal.20is.20now.20implemented/near/543748960).
Not bad!

<!--
  https://github.com/bytecodealliance/regalloc2/pull/220: +82 -84
  https://github.com/bytecodealliance/regalloc2/pull/223: +5 -6
  https://github.com/bytecodealliance/regalloc2/pull/224: +16 -19
  https://github.com/bytecodealliance/wasmtime/pull/10510: +4199 -423
  https://github.com/bytecodealliance/wasmtime/pull/10609: +109 -100
  https://github.com/bytecodealliance/wasmtime/pull/10709: +49 -5
  https://github.com/bytecodealliance/regalloc2/pull/226: +26 -10
  https://github.com/bytecodealliance/regalloc2/pull/221: +1 -1
  https://github.com/bytecodealliance/wasmtime/pull/10571: +36 -24
  https://github.com/bytecodealliance/regalloc2/pull/225: +1 -1
  https://github.com/bytecodealliance/wasmtime/pull/10590: +19 -5
  https://github.com/bytecodealliance/regalloc2/pull/227: +1 -1
  https://github.com/bytecodealliance/wasmtime/pull/10747: +84 -5
  https://github.com/bytecodealliance/wasmtime/pull/10748: +84 -5
  https://github.com/bytecodealliance/wasmtime/pull/10919: +1472 -347
  https://github.com/bytecodealliance/wasmtime/pull/11230: +2490 -191
  https://github.com/bytecodealliance/regalloc2/pull/231: +93 -12
  https://github.com/bytecodealliance/wasmtime/pull/11321: +1771 -322
  https://github.com/bytecodealliance/wasmtime/pull/11326: +2593 -523
  https://github.com/bytecodealliance/wasmtime/pull/11467: +269 -227
  https://github.com/bytecodealliance/wasmtime/pull/11500: +246 -116
  https://github.com/bytecodealliance/wasmtime/pull/11507: +15 -1
  https://github.com/bytecodealliance/wasmtime/pull/11511: +6 -2
  https://github.com/bytecodealliance/wasmtime/pull/11514: +758 -531
  https://github.com/bytecodealliance/wasmtime/pull/11530: +12 -2
  https://github.com/bytecodealliance/wasmtime/pull/11531: +1 -0
  https://github.com/bytecodealliance/wasmtime/pull/11533: +31 -20
  https://github.com/bytecodealliance/wasmtime/pull/11535: +31 -1
  https://github.com/bytecodealliance/wasmtime/pull/11554: +2 -0
  https://github.com/bytecodealliance/wasmtime/pull/11564: +29 -5
  https://github.com/bytecodealliance/wasmtime/pull/10485: +303 -203
  https://github.com/bytecodealliance/regalloc2/pull/212: +1 -2
  https://github.com/bytecodealliance/wasmtime/pull/10502: +1338 -767
  https://github.com/bytecodealliance/regalloc2/pull/214: +7 -3
  https://github.com/bytecodealliance/regalloc2/pull/216: +56 -8
  https://github.com/bytecodealliance/wasmtime/pull/10554: +15 -26
  https://github.com/bytecodealliance/wasmtime/pull/10555: +13 -6
-->


All told, this took 37 PRs with a diff-stat of `+16264 -4004` (16KLoC
total) -- certainly not the "small-to-medium-sized" project I had
initially optimistically expected, but I'm happy we were able to build
it out and get it to a stable state relatively easily. It was a
rewarding journey in a different way than a lot of my past work
(mostly on the Cranelift side) -- where many of my past projects have
been really very open-ended design or even research questions, here we
had the high-level shape already and all of the work was in designing
high-quality details and working out all the interesting interactions
with the rest of the system. I'm happy with how clean the IR design
turned out in particular, and I don't think it would have done so
without the really excellent continual discussion with the rest of the
Cranelift and Wasmtime contributors (thanks to Nick Fitzgerald and
Alex Crichton in particular here).

As an aside: I am happy to see how, aside from use-cases for Wasm
exception handling, the exception support in Cranelift itself has been
useful too.  As mentioned above, `cg_clif` picked it up almost as soon
as it was ready; but then, as an unexpected and pleasant surprise,
Alex subsequently [rewrote Wasmtime's trap
unwinding](https://github.com/bytecodealliance/wasmtime/pull/11592) to
use Cranelift exception handlers in our entry trampolines rather than
a setjmp/longjmp, as the latter have longstanding semantic
questions/issues in Rust. This took [one more
intrinsic](https://github.com/bytecodealliance/wasmtime/pull/11629),
which I implemented after discussing with Alex how best to expose
exception handler addresses to custom unwind logic without the full
exception unwinder, but was otherwise a pretty direct application of
`try_call` and our exception ABI.  General building blocks prove
generally useful, it seems!

---

*Thanks to Alex Crichton and Nick Fitzgerald for providing feedback on
a draft of this post!*
