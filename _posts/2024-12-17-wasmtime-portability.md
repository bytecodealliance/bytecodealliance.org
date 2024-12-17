---
title: "Making WebAssembly and Wasmtime More Portable"
author: "Nick Fitzgerald"
github_name: "fitzgen"
---

Portability is among the first properties promoted on [WebAssembly's official
homepage][WebAssembly]:

[WebAssembly]: https://webassembly.org

> WebAssembly (abbreviated Wasm) is a binary instruction format for a
> stack-based virtual machine. Wasm is designed as a portable compilation target
> for programming languages, enabling deployment on the web for client and
> server applications.

This portability has led [many](https://wasmbyexample.dev/home.en-us.html)
[people](https://www.cs.cmu.edu/wrc/) to
[claim](https://www.infoq.com/news/2015/06/webassembly-wasm/) that it is a
"universal bytecode" &mdash; an instruction set that can run on any computer,
abstracting away the underlying native architecture and operating system. In
practice, however, there remain places you cannot take standard WebAssembly, for
example certain memory-constrained embedded devices. Runtimes have been forced
to choose between deviating from the standard with ad-hoc language modifications
or else avoiding these platforms. This article details in-progress standards
proposals to lift these extant language limitations; enumerates recent
engineering efforts to greatly expand Wasmtime's platform support; and, finally,
shares some ways that you can get involved and help us further improve Wasm's
portability.

WebAssembly has a lot going for it. It has a [formal specification] that is
developed in an open, collaborative [standards process] by browser, runtime,
hardware, and language toolchain vendors, among others. It's [sandboxed], so a
Wasm program cannot access any resource you don't explicitly give it access to,
leading to the development of [standard Wasm APIS][WASI] leveraging
[capability-based security]. It is [designed] such that, after compilation to
native code, it can be executed at near-native speeds. And, even if there is
room for improvement, it is [portable] across many systems, running in Web
browsers and on servers, workstations, phones, and more. These qualities are
worth commending, preserving, and making available in even more places.

[formal specification]: https://webassembly.github.io/spec/core/
[standards process]: https://github.com/WebAssembly/meetings/blob/main/process/phases.md
[sandboxed]: https://webassembly.org/docs/security/
[WASI]: https://wasi.dev/
[capability-based security]: https://en.wikipedia.org/wiki/Capability-based_security
[designed]: https://webassembly.org/docs/high-level-goals/
[portable]: https://webassembly.org/docs/portability/

What does Wasm need in order to run on a given platform? A Wasm runtime that
supports that platform. In this article, we'll focus on the runtime we're
building: Wasmtime.

[Wasmtime] is a lightweight, standalone WebAssembly runtime developed openly
within the Bytecode Alliance. Wasmtime is fast. It can, for example, [spawn new
Wasm instances in just 5 microseconds][fast]. We, the Wasmtime developers, labor
to ensure that Wasmtime is [correct and secure], leveraging ubiquitous fuzzing
and formal verification, because Wasm's theoretical security properties are only
as strong as the runtime's actual implementation. We are [committed] to open
standards and actively participate in Wasm standardization; Wasmtime does not
and will never implement ad-hoc, non-standard Wasm
extensions.[^constrained-by-spec] We believe that bringing Wasmtime, its
principles, and its strengths to more platforms is a worthwhile endeavor.

[Wasmtime]: https://wasmtime.dev/
[fast]: https://bytecodealliance.org/articles/wasmtime-10-performance
[correct and secure]: https://bytecodealliance.org/articles/security-and-correctness-in-wasmtime
[committed]: https://bytecodealliance.org/about
[^constrained-by-spec]: If an engine chooses not to abide by the constraints
    imposed by the WebAssembly language specification, then it is not
    implementing WebAssembly. It is instead implementing a language that is
    similar to but subtly different from WebAssembly. This leads to
    interoperability hazards, de facto standards, and ecosystem splits. We saw
    this during the early days of the Web, when Websites used non-standard,
    Internet Explorer-specific APIs. This led to broken Websites for people
    using other browsers, and eventually forced other browsers to reverse
    engineer the non-standard APIs. The Web is still stuck with the resulting
    baggage and tech debt today. We must prevent this from happening to
    WebAssembly. Therefore we refuse the temptation to deviate from the
    WebAssembly specification. Instead, when we identify language-level
    constraints, we engage with the standards process to create solutions that
    the whole ecosystem can rely on.

So what must Wasmtime, or any other Wasm runtime, have in order to run Wasm on a
given platform? There are two fundamental operations that, no matter how they
are implemented, a Wasm runtime requires:

1. A method for allocating a Wasm program's state, such as its linear memories
2. A method to execute Wasm instructions

A Wasm runtime's portability is determined by how few assumptions it makes about
its underlying platform in its implementation of those operations. Does it
assume an operating system that provides the `mmap` syscall or a CPU that
supports virtual memory? Does it support just a small, fixed set of instructions
sets, such as `x86_64` and `aarch64`, or a wide, extensible set of ISAs? And, as
previously mentioned, no matter which implementation choices are made,
assumptions baked into the Wasm language specification itself can also limit a
runtime's portability.

## Removing Runtime Assumptions

Wasmtime's runtime previously made unnecessary assumptions, artificially
constraining its portability, and we've spent the last year or so removing them
one by one. Wasmtime is now a [`no_std`][no-std] crate with minimal platform
assumptions. It doesn't require that the underlying platform provide `mmap` in
order to allocate Wasm memories like it previously did; in fact, it no longer
even depends upon an underlying operating system at all. As of today, Wasmtime's
only mandatory platform requirement is a global memory allocator
(i.e. `malloc`).

[no-std]: https://docs.rust-embedded.org/book/intro/no-std.html

Wasmtime previously assumed that it could always use guard pages to catch
out-of-bounds memory accesses, constraining its portability to platforms with
virtual memory. Wasmtime can now be configured to rely only on explicit checks
to catch out-of-bounds accesses, and Wasmtime no longer assumes the presence of
virtual memory.

Wasmtime previously assumed that it could always detect division-by-zero by
installing a signal handler. It would translate Wasm division instructions into
unguarded, native `div` instructions and catch the corresponding signals that
the operating system translated from divide-by-zero exceptions. This constrained
Wasmtime's portability to only operating systems with signals and instruction
sets that raise exceptions on division by zero. Wasmtime can now be configured
to emit explicit tests for zero divisors, removing the assumption that
divide-by-zero signals are always available.

Configure Wasmtime to avoid depending upon virtual memory and signals by
building without the `signals-based-traps` cargo feature and with
[`Config::signals_based_traps(false)`][config-signals]. More information about
configuring minimal Wasmtime builds, as well as integrating with custom
operating systems, can be found in [the Wasmtime guide][minimal-build].

[config-signals]: https://docs.rs/wasmtime/latest/wasmtime/struct.Config.html#method.signals_based_traps
[minimal-build]: https://docs.wasmtime.dev/examples-minimal.html

This effort was spearheaded by [Alex Crichton], with contributions from [Chris
Fallin].

[Alex Crichton]: https://github.com/alexcrichton
[Chris Fallin]: https://www.cfallin.org/

## Lifting Spec Constraints

The WebAssembly language specification imposes a fairly well-known portability
constraint on standards-compliant implementations: Wasm memories are composed of
pages, and Wasm pages have a fixed size of 64KiB. Therefore, a Wasm memory's
size is always a multiple of 64KiB, and the smallest non-zero memory size is
64KiB. But there exist embedded devices with less than 64KiB of memory available
for Wasm, but where developers nonetheless want to run Wasm. I have been
championing a new proposal in the WebAssembly standardization group to address
this mismatch.

[The custom-page-sizes proposal][custom-page-sizes] allows a Wasm module to
specify a memory's page size, in bytes, in the memory's static definition. This
gives Wasm modules finer-grained control over their resource consumption: with a
one-byte page size, for example, a Wasm memory can be sized to exactly the
embedded device's capacity, even when less than 64KiB are available.

[custom-page-sizes]: https://github.com/WebAssembly/custom-page-sizes

I implemented support for the custom-page-sizes proposal in Wasmtime. You can
experiment with it via the `--wasm=custom-page-sizes` flag on the command line
or via [the `Config::wasm_custom_page_sizes`
method](https://docs.rs/wasmtime/latest/wasmtime/struct.Config.html#method.wasm_custom_page_sizes)
in the library. Since then, three other Wasm engines have added [support] for
the proposal as well.

[support]: https://github.com/WebAssembly/custom-page-sizes/blob/main/proposals/custom-page-sizes/Overview.md#implementation-status

The proposal is on the standards track and is currently in phase 2 of the
standardization process. I intend to shepherd it to phase 3 in 2025. The phase 3
entry requirements (spec tests and an implementation) are already satisfied
multiple times over today.

## Compilers Without Backends

We've discussed allocating Wasm memories portably and removing assumptions from
the runtime and language specification; now we turn our attention to portably
executing Wasm instructions. Wasmtime previously had two available approaches to
Wasm execution:

1. [Cranelift], an optimizing compiler backend that is comparable to the
   optimizing tier in a [just-in-time] system, such as V8's [TurboFan] or
   SpiderMonkey's [Ion].
2. [Winch], a single-pass, "baseline" compiler that gives you [fast, low-latency
   compilation][wingo-blog] but generates worse machine code, leading to slower
   Wasm execution throughput.

[Cranelift]: https://cranelift.dev/
[just-in-time]: https://en.wikipedia.org/wiki/Just-in-time_compilation
[TurboFan]: https://v8.dev/docs/turbofan
[Ion]: https://spidermonkey.dev/blog/2024/10/16/75x-faster-optimizing-the-ion-compiler-backend.html
[Winch]: https://github.com/bytecodealliance/wasmtime/blob/main/winch/README.md
[wingo-blog]: https://www.wingolog.org/archives/2020/03/25/firefoxs-low-latency-webassembly-compiler

Both options compile Wasm down to native instructions, which has two portability
consequences. First, when loaded into memory, the compiled Wasm's machine code
must be executable, and non-portable assumptions around the presence of `mmap`,
memory permissions, and virtual memory on the underlying platform creep in
again. Second, compiling to native code as an execution strategy requires a
compiler backend for the target platform's architecture. We cannot translate
Wasm instructions into native instructions without a compiler backend that knows
how to emit those native instructions. Cranelift has backends for `aarch64`,
`riscv64`, `s390x`, and `x86_64`. Winch has an `aarch64` backend and an `x86_64`
backend. If you wanted to execute Wasm on a different architecture, say `armv7`
or `riscv32`, you had to first author a whole compiler backend for that
architecture, which is not a quick-and-easy task for established Wasmtime and
Cranelift hackers, let alone new contributors. This was a huge roadblock to
Wasmtime's portability.

The typical way to add portable execution is with an interpreter written in a
portable manner, and we started investigating the design space for
Wasmtime. With a portable interpreter, you can execute Wasm on any platform you
can compile the interpreter. In Wasmtime's case, because it is written in Rust,
a portable interpreter would expand Wasmtime's portability to [all of the many
platforms that `rustc` supports][rust-targets].

[rust-targets]: https://doc.rust-lang.org/nightly/rustc/platform-support.html

We want to maximize the interpreter's execution throughput — how fast it can run
Wasm.[^fast-goal] If people are running the interpreter due to the absence of a
compiler backend for their architecture, then the usual method of tuning
Wasmtime for fast Wasm execution (using Cranelift as the execution strategy) is
unavailable. Beyond optimizing the interpreter's core loop and opcode dispatch,
the best way to speed up an interpreter is to execute fewer instructions, doing
relatively more work per instruction. This pushes us towards translating Wasm
into a custom, internal bytecode format. The internal bytecode format can be
register-based, rather than stack-based like Wasm, which generally requires
fewer instructions to encode the same program. With an internal bytecode we also
have the freedom to define "super-instructions" or "macro-ops" — single
instructions that do the work of multiple smaller instructions all at once —
whenever we determine it would be beneficial. The Wasm-to-internal-bytecode
translation step gives us a place to optimize the resulting bytecode before we
begin executing it. In addition to coalescing multiple operations into
macro-ops, we have the opportunity to do things like deduplicate subexpressions
and eliminate redundant moves. This is when we realized that this translation
step was sounding more and more like a proper optimizing compiler, and we
already maintain an optimizing compiler that already performs these sorts of
optimizations, we just need to teach it to emit the interpreter's internal
bytecode, rather than native code.

[^fast-goal]: To build the very fastest interpreter possible, [you probably want
    to write assembly by hand][hand-written-asm], but that directly conflicts
    with our primary goal of portability so it is unacceptable. We want to
    maximize interpreter speed to the degree we can, but we cannot prioritize it
    over portability.

[hand-written-asm]: https://www.reddit.com/r/programming/comments/badl2/luajit_2_beta_3_is_out_support_both_x32_x64/c0lrus0/

The [Pulley] interpreter is the culmination of this line of thinking. When
Wasmtime is using Pulley, it translates Wasm to Cranelift's intermediate
representation, CLIF; then Cranelift runs its mid-end optimizations on the CLIF,
such as [constant propagation], [GVN], and [LICM]; next, Cranelift lowers the
CLIF to Pulley bytecode, coalescing multiple CLIF instructions into single
Pulley macro-ops, eliminating dead code, and (re)allocating (virtual) registers
to reduce moves; and finally, Wasmtime interprets the resulting optimized
bytecode.

           ┌──────┐
           │ Wasm │
           └──────┘
              │
              │
    Wasm-to-CLIF translation
              │
              ▼
           ┌──────┐
           │ CLIF │
           └──────┘
              │
              │
     mid-end optimizations
              │
              ▼
           ┌──────┐
           │ CLIF │
           └──────┘
              │
              │
           lowering
              │
              ▼
     ┌─────────────────┐
     │ Pulley bytecode │
     └─────────────────┘

Just like Wasm-to-native-code compilation, Wasm-to-Pulley-bytecode compilation
can be performed offline and ahead of time. Bytecode compilation need not be on
the critical path and, given an already-bytecode-compiled Wasm module, Pulley
execution can leverage the same 5-microsecond instantiation that native
compilation strategies enjoy.

[Pulley]: https://github.com/bytecodealliance/wasmtime/blob/main/pulley/README.md
[constant propagation]: https://en.wikipedia.org/wiki/Constant_folding
[GVN]: https://en.wikipedia.org/wiki/Value_numbering
[LICM]: https://en.wikipedia.org/wiki/Loop-invariant_code_motion

Initial Pulley support has landed in Wasmtime, but it is still a work in
progress and at times incomplete. We have not spent time optimizing Pulley, its
interpreter loop, or selection of macro-ops yet, so it is expected that its
performance today is not as good as it should be. You can experiment with Pulley
by enabling the `pulley` cargo feature and passing the `--target pulley32` or
`--target pulley64` command line flag (depending on if you are on a 32- or
64-bit machine respectively) or by calling [`config.target("pulley32")` or
`config.target("pulley64)`][config-target] when using Wasmtime as a
library. Note that you must use the (default) Cranelift compilation strategy
with Pulley; Winch doesn't support emitting Pulley bytecode at this time.

[config-target]: https://docs.rs/wasmtime/latest/wasmtime/struct.Config.html#method.target

The architecture and pipeline for Pulley emerged from discussions between myself
and Alex Crichton. The initial Pulley interpreter and Cranelift backend to emit
Pulley bytecode were both developed by me. Alex integrated the interpreter into
Wasmtime's runtime and has since been filling in its full breadth of Wasm
support.

## Write Once, Run Anywhere?

We've been focusing on Wasmtime's portability and the ability to run *any* Wasm
code on as many platforms as possible. The infamous ["write once, run anywhere"
(WORA)][wora] ambition aims even higher: to run the *exact same* code on all
platforms, without changing its source or recompiling it.

[wora]: https://en.wikipedia.org/wiki/Write_once,_run_anywhere

At a high level, an application requires certain core capabilities. Not all code
needs to or should run on platforms that lack their required capabilities:
running an IRC chat client on a device that isn't connected to the internet
doesn't generally make sense because an IRC chat client requires network
access. WORA across two given platforms is a worthy goal only when the platforms
both provide the application's required capabilities (at a high level,
regardless if they happen to use incompatible syscalls or different mechanisms
to expose the capabilities).

[The WebAssembly Component Model][cm] makes explicit the capability dependencies
of a Wasm component and introduces the concept of a [world] to formalize an
environment's available capabilities. With components and worlds, we can
precisely answer the question of whether WORA makes sense across two given
platforms. Along with the standard worlds and interfaces defined by [WASI], we
already have all the tools we need to make WORA a reality for Wasm where it
makes sense.[^parts]

[^parts]: The component model also gives us tools to break Wasm applications
    down into their constituent parts, and share those parts across different
    applications. Even when WORA doesn't make sense for a full application, it
    might make sense for some subset of its business logic that happens to
    require fewer capabilities than the full application. For example, we may
    want to share the logic for maintaining the set of active IRC users between
    both the server and the client.

[cm]: https://component-model.bytecodealliance.org/
[world]: https://component-model.bytecodealliance.org/design/worlds.html

## Come Help Us!

Do you believe in our vision and want to contribute to our portability efforts?
The work here isn't done and there are many opportunities to get involved!

* Try [building a minimal Wasmtime][minimal-build] for your niche platform, kick
  the tires, and share your feedback with us.

* Help us [get Pulley passing all of the `.wast` spec
  tests](https://github.com/bytecodealliance/wasmtime/issues/9783)! Making a
  failing test start passing is usually pretty straightforward and just involves
  adding a missing instruction or two. This is a great way to start contributing
  to Wasmtime and Cranelift.

* Once Pulley is complete, or at least mostly completely, we can start analyzing
  and improving its performance. We can run our [Sightglass
  benchmarks](https://github.com/bytecodealliance/sightglass) like
  `spidermonkey.wasm` under Pulley to determine what can be improved. We can
  inspect the generated bytecode, identify which pairs of opcodes are often
  found one after the other, and create new macro-ops. There is a lot of fun,
  meaty performance engineering work available here for folks who enjoy making
  number go up.

* Support for running Wasm binaries that use custom page sizes is complete in
  Wasmtime, but toolchain support for generating Wasm binaries with custom page
  sizes is still largely missing. Adding [support for the custom-page-sizes
  proposal to
  `wasm-ld`](https://github.com/WebAssembly/custom-page-sizes/blob/main/proposals/custom-page-sizes/Overview.md#expected-toolchain-integration)
  is what is needed most. It's expected that this implementation should be
  relatively straightforward and that [exposing a `__wasm_page_size` symbol can
  be modelled after the existing `__tls_size`
  symbol](https://github.com/WebAssembly/custom-page-sizes/issues/13#issuecomment-2135584903).

* At the time of writing, a minimal dynamic library that runs pre-compiled Wasm
  modules is a 315KiB binary on `x86_64`. A minimal build of Wasmtime's whole C
  API as a dynamic library is 698KiB. These numbers aren't terrible, but we also
  haven't put any effort into optimizing Wasmtime for code size yet, so we
  expect there to be a fair amout of potential code size wins and low-hanging
  fruit available. We suspect error strings are a major code size offender, and
  revamping `wasmtime::Error` to optionally (based on compile-time features)
  contain just error codes, instead of full strings, is one idea we
  have. Analyzing code size with [`cargo
  bloat`](https://github.com/RazrFalcon/cargo-bloat) would also be fantastic.

We also publish [high-level contributor documentation in the Wasmtime
guide](https://docs.wasmtime.dev/contributing.html).

## Thanks

Big thanks to everyone who has contributed to the recent portability effort and
to Wasmtime over the years. Thanks also to [Alex Crichton] and [Till
Schneidereit] for reviewing early drafts of this article.

[Till Schneidereit]: https://github.com/tschneidereit
