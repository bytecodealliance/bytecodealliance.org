---
title: "Wasmtime and Cranelift in 2023"
author: "Nick Fitzgerald, Chris Fallin, and Pat Hickey"
github_name: "bytecodealliance"
---

It's that time of year: time to start winding down for the winter holiday
season, time to reflect on the past year, and time to think about what we can
accomplish together in 2024. The Wasmtime and Cranelift projects are no
exception. This article recounts Wasmtime and Cranelift progress in 2023 and
explores what we might do in 2024.

[Wasmtime] is a standalone WebAssembly runtime. It is [fast], [secure],
embeddable, and standards compliant.

[Wasmtime]: https://wasmtime.dev/
[fast]: https://bytecodealliance.org/articles/wasmtime-10-performance
[secure]: https://bytecodealliance.org/articles/security-and-correctness-in-wasmtime

[Cranelift] is a fast, secure, (relatively) simple, and innovative compiler
backend. It is developed in tandem with, and primarily used by, Wasmtime.

[Cranelift]: https://cranelift.dev/

<!-- $ git shortlog -s -n --since 2023-01-01 | wc -l -->
<!-- 129 -->
<!-- $ git log --oneline --since 2023-01-01 | wc -l -->
<!-- 1679 -->

Wasmtime and Cranelift have had 1679 commits from 129 different authors in 2023
&mdash; and the year isn't even over yet! Huge thanks to [everyone] who helped
make this happen.

[everyone]: https://github.com/bytecodealliance/wasmtime/graphs/contributors?from=2023-01-01&to=2023-12-31&type=c

> **Want to get involved in Wasmtime and Cranelift? [Check out our contributor
> documentation!]**

[Check out our contributor documentation!]: https://docs.wasmtime.dev/contributing.html

The year's overall theme was maturity and reliability. Progress generally fell
under one of three big umbrellas:

1. Cranelift compiler
2. WASI interface design and implementation
3. Wasmtime Runtime

Apologies in advance: this is not the quickest read! But we accomplished a lot
this year and that's reflected in the length.

## Wasmtime Runtime

Wasmtime added support for a variety of WebAssembly proposals in 2023:

* The [tail calls proposal] adds guaranteed tail call elimination to Wasm,
  helping functional languages and other constructs like finite state machines
  efficiently target Wasm. The proposal was implemented by Nick Fitzgerald and
  Jamey Sharp.

* The [relaxed SIMD proposal] introduces new SIMD instructions whose precise
  results may vary depending on the underlying hardware to Wasm, unlocking new
  speed up opportunities for certain classes of programs. This proposal was
  implemented by Alex Crichton.

* Initial support for the [function references proposal] was implemented by Luna
  P-C, Daniel Hillerström, and Alex Crichton. This proposal is a prerequisite to
  the GC proposal, introduces subtyping to WebAssembly reference types, and
  eliminates some type checks when indirectly calling typed function
  references. There is still work to be done to expose typed function references
  in Wasmtime's embedding API.

* The [component model] aims to enable building interoperable and composable
  Wasm libraries, applications, and environments. Initial support for running
  components in Wasmtime was implemented by Alex Crichton, with some help from
  Nick Fitzgerald, towards the end of 2022. In 2023, the component model
  specification added the concept of *resources* which are passed by handle
  (like a file descriptor) instead of by copying (like data in a pipe) and Alex
  Crichton implemented [support for resources] in Wasmtime.

Additionally, the threads, multi-memory, and relaxed SIMD proposals reached
phase 4, and since [we have confidence in their implementations] and they have
been thoroughly fuzzed, [we have enabled them by default in Wasmtime].

[tail calls proposal]: https://github.com/WebAssembly/tail-call/blob/main/proposals/tail-call/Overview.md
[relaxed SIMD proposal]: https://github.com/WebAssembly/relaxed-simd/blob/main/proposals/relaxed-simd/Overview.md
[function references proposal]: https://github.com/WebAssembly/function-references/blob/master/proposals/function-references/Overview.md
[component model]: https://github.com/WebAssembly/component-model/blob/main/design/mvp/Explainer.md
[support for resources]: https://github.com/bytecodealliance/wasmtime/pull/6769
[we have confidence in their implementations]: https://docs.wasmtime.dev/contributing-implementing-wasm-proposals.html#enabling-support-for-a-proposal-by-default
[we have enabled them by default in Wasmtime]: https://github.com/bytecodealliance/wasmtime/pull/7285

We also shipped a number of new features for profiling, debugging, and checking
the correctness of Wasm programs running within Wasmtime:

* Sophia Sunkin and Chris Fallin added [a `valgrind`-style memory access checker
  for Wasm programs] running within Wasmtime. It checks Wasm programs for
  classic memory bugs like invalid `free`s and accesses of non-`malloc`ed memory
  regions.

* An in-process, cross-platform [sampling profiler] was added to Wasmtime by
  Jamey Sharp. It helps you debug and diagnose performance issues of Wasm
  programs running within Wasmtime. The new profiler is built on top of
  Wasmtime's existing stack capturing and epoch interruption features. It
  generates profiles that use the same data format as Firefox's profiler, and
  therefore these profiles can be viewed in [the Firefox profiler's fantastic
  Web UI].

* Support for generating [Wasm core dumps] when a Wasm program traps was added
  by Rainy Sinclair and Nick Fitzgerald. See [the core dump subsection of the
  Wasmtime guide] to learn more about how this can help with post-mortem
  debugging.

* Wasmtime's VTune integration improved: one can now profile Wasm-level
  program symbols. Andrew Brown and Rahul Chaphalkar fixed a bug preventing
  VTune from understanding these symbols, so [profiling with VTune] is much
  better.

[the core dump subsection of the Wasmtime guide]: https://docs.wasmtime.dev/examples-debugging-core-dumps.html
[Wasm core dumps]: https://github.com/WebAssembly/tool-conventions/blob/main/Coredump.md
[sampling profiler]: https://docs.wasmtime.dev/examples-profiling-guest.html
[the Firefox profiler's fantastic Web UI]: https://profiler.firefox.com/
[profiling with VTune]: https://docs.wasmtime.dev/examples-profiling-vtune.html

There were also important embedder-facing improvements and additions that are
invisible to the Wasm programs running inside of Wasmtime:

* Calls between the host and the Wasm guest got 5% to 10% faster thanks to [an
  overhaul of the trampolines we use to enter and exit Wasm] by Nick Fitzgerald,
  Jamey Sharp, and Alex Crichton. [Calling out from a Wasm guest to the host] now
  takes as little as 10 nanoseconds.

* We now publish [minimal builds of Wasmtime tailored to embedded environments],
  and have compile-time build flags to turn most Wasmtime features on or off,
  thanks to the hard work of Alex Crichton. A minimal build of Wasmtime that
  supports loading and running pre-compiled Wasm modules is currently 2.1
  megabytes on `x86-64` and we expect to shrink this number further in 2024.

* Alex Crichton [redesigned Wasmtime's command-line interface (CLI)] with the goal
  to set us up for long-term CLI stability and while at the same time giving us
  extensibility without stagnation. We didn't initially roll it out smoothly,
  however, and we exposed users to unexpected breakage. We're sorry about
  that. In response, we developed a compatibility layer, backported it to the
  previous release, and created a [tracking issue for the CLI migration].

* A [new `wasmtime explore` subcommand] was added to Wasmtime's CLI by Nick
  Fitzgerald. This subcommand lets you explore how a WebAssembly module is
  compiled to native code and shows the WebAssembly text format side-by-side
  with its native code disassembly (similar to [the Godbolt Compiler Explorer]).

[an overhaul of the trampolines we use to enter and exit Wasm]: https://github.com/bytecodealliance/wasmtime/pull/6262
[Calling out from a Wasm guest to the host]: https://github.com/bytecodealliance/wasmtime/blob/24d945f3e34e3c24e0160850bb3f668c0eeabec4/benches/call.rs#L192
[minimal builds of Wasmtime tailored to embedded environments]: https://github.com/bytecodealliance/wasmtime/issues/7315
[redesigned Wasmtime's command-line interface (CLI)]: https://github.com/bytecodealliance/wasmtime/issues/6741
[tracking issue for the CLI migration]: https://github.com/bytecodealliance/wasmtime/issues/7384
[a `valgrind`-style memory access checker for Wasm programs]: https://docs.wasmtime.dev/wmemcheck.html
[new `wasmtime explore` subcommand]: https://github.com/bytecodealliance/wasmtime/pull/5975
[the Godbolt Compiler Explorer]: https://godbolt.org/

The [pooling allocator] &mdash; Wasmtime's fastest WebAssembly instance
allocation strategy that reserves a pool of memory for Wasm instances ahead of
time &mdash; received the following improvements in 2023:

* Nick Fitzgerald [significantly refactored the pooling allocator] to better
  support components and to avoid over-allocation when a particular instance
  doesn't use all `N` of the configured maximum memories or tables available to
  each instance.

* Support for ["color guard"] and [memory-protection key (MPK)] striping was
  [added to the pooling allocator] by Andrew Brown, with help from Alex Crichton
  and Nick Fitzgerald. This feature lets you fit up to fifteen times more
  WebAssembly linear memories and their guard pages within the same amount of
  virtual memory in a process.

[pooling allocator]: https://docs.rs/wasmtime/latest/wasmtime/struct.PoolingAllocationConfig.html
[significantly refactored the pooling allocator]: https://github.com/bytecodealliance/wasmtime/pull/6835
["color guard"]: https://plas2022.github.io/files/pdf/SegueColorGuard.pdf
[memory-protection key (MPK)]: https://www.kernel.org/doc/html/latest/core-api/protection-keys.html
[added to the pooling allocator]: https://github.com/bytecodealliance/wasmtime/pull/7072

In April, we were bitten by [a CVE caused by a `rustc` miscompilation] that we
root-caused all the way back to some undefined behavior (UB) deep inside the
`vmctx`-management code inside Wasmtime. Since then, Alex Crichton has enabled
running all Wasmtime tests that don't actually execute Wasm [under MIRI] for
every pull request. MIRI is an interpreter for `rustc`'s mid-level intermediate
representation that detects certain classes of UB. We can't actually execute
Wasm under MIRI, because it doesn't understand just-in-time compilation and
mapping new pages as executable, but we can exercise all of the
`vmctx`-management code and the libcalls that Wasm makes to modify VM state.
When executing those tests, MIRI immediately found the root-cause UB that
triggered the miscompilation that triggered the CVE, Alex fixed those bugs, and
we are now UB-free under MIRI. Running tests under MIRI gives us assurance that
we won't be bitten by this same class of bug again in the future.

[a CVE caused by a `rustc` miscompilation]: https://github.com/advisories/GHSA-ch89-5g45-qwc7
[under MIRI]: https://github.com/bytecodealliance/wasmtime/pull/6332

Finally, we are in the process of adding support for running Wasm that was
compiled by an alternative compiler from Cranelift: [Winch]. Winch is a baseline
compiler that does a single pass over the Wasm and emits native code very
quickly. Its implementation is a lot simpler than Cranelift's. The downside is
that it emits worse code that hasn't been optimized the way it would have been
by Cranelift. [Initial Winch integration with Wasmtime landed in April] and
there have been many follow-up pull requests since then. Thanks to Saúl Cabrera,
Jeffrey Charles, Kevin Rizzo, and others for their work on Winch.

[Winch]: https://github.com/bytecodealliance/rfcs/blob/main/accepted/wasmtime-baseline-compilation.md
[Initial Winch integration with Wasmtime landed in April]: https://github.com/bytecodealliance/wasmtime/pull/6119

### What's Next for the Runtime in 2024?

We'd like to implement (and finish implementing) support for a few key
WebAssembly proposals in 2024:

* Firstly, we want to implement and ship [the WebAssembly GC proposal] in 2024,
  which gives Wasm the ability to define struct and array types and allocate
  instances of those types whose lifetimes are dynamically managed by the
  runtime. We have an [implementation plan], and work is already [mostly done]
  on GC support in our binary decoder and validator by Nick Fitzgerald and Ivan
  Mikushin. Thanks also to Ryan Hunt and Ben Visness from the Firefox team for
  implementing support for the GC proposal in our Wasm text format parser, which
  Firefox also uses.

* As part of implementing the GC proposal, and exposing garbage-collected values
  in Wasmtime's public API, we will also [cross the last "t"s and dot the last
  "i"s for the function-references proposal].

* We'd like to implement and ship [the WebAssembly exception-handling proposal]
  in 2024. This will enable C++ with exceptions and Rust compiled with
  `panic=unwind` to run within Wasmtime. We also expect that most toolchains
  targeting Wasm GC will assume support for exceptions as well, so the proposal
  is simply part of what it will take to be a modern Wasm runtime in 2024.

* We are excited for the [nascent thread-spawning proposal] being created by
  Andrew Brown and Conrad Watt that adds finer-grained sharing of WebAssembly
  state than the initial threads proposal (which was just memories, no globals,
  tables, or GC objects) and potentially a `thread.spawn` instruction. The
  proposal is very early days and expected to change quite a bit, but we would
  like Wasmtime to be an early implementer and provide valuable spec feedback.

* We would like to enable the tail calls proposal by default, since the proposal
  is phase 4 and essentially complete, however we need to do some [final tweaks
  to the `tail` calling convention] to get its performance at par with the
  current default calling convention. Once we reach performance parity, we can
  turn tail calls on by default.

* We will continue work on the [component model]. Part of this work will be
  polishing Preview 2 (see the following WASI section) with better support for
  versioning interfaces. The other part of the work will be adding new component
  model features such as native async, optional imports, enhancements to
  resource methods.

[the WebAssembly GC proposal]: https://github.com/WebAssembly/gc/tree/main
[implementation plan]: https://github.com/bytecodealliance/rfcs/blob/main/accepted/wasm-gc.md
[mostly done]: https://github.com/bytecodealliance/wasm-tools/pull/1275
[cross the last "t"s and dot the last "i"s for the function-references proposal]: https://github.com/bytecodealliance/wasmtime/issues/6455
[the WebAssembly exception-handling proposal]: https://github.com/WebAssembly/exception-handling
[nascent thread-spawning proposal]: https://github.com/abrown/thread-spawn/blob/main/proposals/thread-spawn/Overview.md
[final tweaks to the `tail` calling convention]: https://github.com/bytecodealliance/wasmtime/issues/6759

We intend to keep working on Winch in 2024, and that work falls along two main
axes:

1. Wasm feature completeness: implementing all instructions and proposals in
   Winch that are supported in Cranelift.

2. Target completeness: right now Winch primarily targets `x86-64`, with some
   initial `aarch64` support. It would ideally support all the architectures
   that Cranelift and Wasmtime do: `x86-64`, `aarch64`, `s390x`, and `riscv64`.

We would also like to continue pushing on developer tooling for Wasmtime, and
Winch plays a role here as well. We have some [existing debugging support], but
the user experience isn't great and it requires using `gdb` or `lldb` to debug
the whole process, including host code and Wasmtime's internal VM code. It's the
equivalent of attaching `gdb` to Firefox when you want to debug some JavaScript
inside a Web page. We'd like to enable live Wasm guest debugging without being
distracted and overwhelmed by the rest of the code in the process. To provide
the most accurate debug information, without having locals optimized away, we
will leverage Winch. We also have lots of cool ideas about [`rr`-style record
and replay] and how to provide a good user experience, so keep your eyes peeled
for an [RFC] in this space early next year.

[existing debugging support]: https://docs.wasmtime.dev/examples-debugging-native-debugger.html
[`rr`-style record and replay]: https://rr-project.org/
[RFC]: https://github.com/bytecodealliance/rfcs/

Additionally, we intend to keep slimming down Wasmtime's code size foot print
and making it appropriate for more and more embedded environments. That work
will initially focus on the footprint of a Wasmtime build that can load and run
pre-compiled Wasm modules and components. As a stretch goal &mdash; and if the
available engineering resources permit it &mdash; we might even begin
investigating, make an RFC for, and start implementing an interpreter tier for
Wasmtime. If this is something you're interested in or interested in helping out
with, come [say hello on Zulip!]

Finally, we may also start exploring what a "host component" or [plugin system]
for Wasmtime looks like. This would tie in with the code size efforts, as it
could potentially spin functionality out from the base Wasmtime build, further
shrinking its footprint. It could also tie in with our WASI implementation and
how we expose new system capabilities to Wasm guests. The exact details of what
this might look like are very much up in the air, but if you think "host
components" or a plugin system could solve a problem you're having, chime in on
the linked issue and keep your eyes peeled for an [RFC] next year.

[say hello on Zulip!]: https://bytecodealliance.zulipchat.com/#narrow/stream/217126-wasmtime
[plugin system]: https://github.com/bytecodealliance/wasmtime/issues/7348

## WASI

[WASI] provides a set of standard, open interfaces for interacting with the
environment your Wasm is running within. Since its inception, Wasmtime has
always been on the forefront of WASI implementation, and 2023 was no different.

[WASI]: https://github.com/WebAssembly/WASI/

We wrote a new implementation of WASI in 2023 for [the upcoming Preview 2
release]. The design of WASI has been factored to use the component model to
provide resource types, and exposes a new low-level scheduling interface
(pollables) as well as streams which many other interfaces build on.

We [reimplemented WASI Preview 1] on top of the new Preview 2
implementation. This will allow us to retire the `wasi-common` implementation of
Preview 1 in the future, and simplify Wasmtime's WASI implementation's
maintenance. This implementation is enabled by default as of Wasmtime 15.

We also wrote a [WASI Preview 1 component adapter], which allows us to turn Wasm
Modules that use Preview 1 into Wasm Components that use Preview 2
interfaces. This is a critical piece of infrastructure that allows users to
adopt Preview 2 before the work to use it directly in `wasi-libc`, Rust's `std`,
and other languages' standard libraries is complete.

Wasmtime now implements the following Preview 2 WASI proposals:

* [`wasi-io`](https://github.com/WebAssembly/wasi-io): Foundational scheduling interface and stream types

* [`wasi-random`](https://github.com/WebAssembly/wasi-random): Random number generation

* [`wasi-clocks`](https://github.com/WebAssembly/wasi-clocks): Monotonic and wall clocks

* [`wasi-filesystem`](https://github.com/WebAssembly/wasi-filesystem): Filesystem access, structured much like in Preview 1

* [`wasi-sockets`](https://github.com/WebAssembly/wasi-sockets): New TCP and UDP networking functions

* [`wasi-cli`](https://github.com/WebAssembly/wasi-cli): Stdio, environment variables, and other command-line application
  concerns. Defines the `wasi:cli/command` world, which is more or less Preview
  1's functionality, plus sockets.

* [`wasi-http`](https://github.com/WebAssembly/wasi-http): HTTP client and server. Defines the `wasi:http/proxy` world,
  which is the common functionality available across many serverless Wasm
  providers, such as Fastly Compute and Fermyon Spin.

Furthermore, the Wasmtime CLI grew [the `wasmtime serve` subcommand] which starts a local HTTP server, and instantiates and runs the given Wasm component targeting the `wasi:http/proxy` world for each incoming HTTP request. The `wasmtime serve` subcommand first shipped in Wasmtime 14.

Similarly, the `wasmtime run` subcommand of the CLI can now [execute Wasm components] which use the `wasi:cli/command` world. This functionality shipped in Wasmtime 13.

Wasmtime also expanded its support for a new `wasi-nn` feature: [named models]. Named models allow Wasm modules to avoid downloading large ML models when computing inferences; instead, these models can be pre-loaded into a registry, e.g., with the `-S nn-graph` CLI option.

[the upcoming Preview 2 release]: https://bytecodealliance.org/articles/webassembly-the-updated-roadmap-for-developers
[WASI Preview 1 component adapter]: https://github.com/bytecodealliance/wasmtime/blob/main/crates/wasi-preview1-component-adapter/README.md
[reimplemented WASI Preview 1]: https://github.com/bytecodealliance/wasmtime/pull/7365
[the `wasmtime serve` subcommand]: https://github.com/bytecodealliance/wasmtime/pull/7091
[execute Wasm components]: https://github.com/bytecodealliance/wasmtime/pull/6836
[named models]: https://www.youtube.com/watch?v=dpOG5YnXDpM

Thanks so much to everyone who worked on Wasmtime's WASI implementation: Pat
Hickey, Dan Gohman, Alex Crichton, Trevor Elliott, Joel Dice, Roman Volostavos,
Eduardo Rodrigues, Luke Wagner, Brendan Burns, and others!

### What's Next for WASI in Wasmtime in 2024?

The most immediate goal is finalizing the standardization of Preview 2 in
collaboration with the WASI subgroup of the W3C's WebAssembly Community Group
and shipping an implementation of it in Wasmtime. Once that is complete, there
are a number of further things we intend to do:

* We will begin building native async support into the component model and WASI.

* We will continue working on more tools for providing WASI interface
  implementations, such as [`wasi-virt`].

* We will implement more WASI interface proposals in Wasmtime itself (or as
  Wasmtime plugins) such as `wasi-kv` and other interfaces in the WASI cloud
  family.

[`wasi-virt`]: https://github.com/bytecodealliance/WASI-Virt

## Cranelift

2023 was a big year for Cranelift! Most importantly and impressively, Cranelift
finally got its own Website: [https://cranelift.dev](https://cranelift.dev)!

Cranelift is also now distributed via `rustup` as an experimental backend to the
Rust compiler as part of the `rustc_codegen_cranelift` (a.k.a `cg_clif`)
project! Huge congrats to bjorn3, Afonso Bordado, and others on reaching this
milestone. Check out the instructions in [the latest progress report] if you
want to try it out. We've [heard reports] of build times being cut down to less
than half their original time after switching to `cg_clif` for debug builds. It
had historically been the case that certain combinations of CLIF opcode (say
`rotl`) and type (say 128-bit integers) were implemented in one backend but not
another. Especially if these combinations weren't exercised by Wasmtime. Afonso
Bordado and bjorn3 did the tireless whack-a-mole work of finding and filling
these gaps to unblock `cg_clif`.

[the latest progress report]: https://bjorn3.github.io/2023/10/31/progress-report-oct-2023.html
[heard reports]: https://www.reddit.com/r/rust/comments/17kg52s/progress_report_on_rustc_codegen_cranelift_oct/k782nez/?context=1

Last year we also [introduced a new mid-end framework] based on acyclic e-graphs
and ISLE rewrites. A ["mid-end"] is the architecture-independent portion of the
compiler pipeline that performs optimizations that are generally useful
regardless of whether you are targeting `x86-64` or `riscv64`. An [e-graph], or
equivalence graph, lets us represent when many different expressions are
equivalent so we can choose the version with the least cost (i.e. will
ultimately produce the fastest machine code). [ISLE] is our domain-specific
language for authoring rewrite rules and lowering our intermediate
representation into actual machine instructions.

This last January, once we had reached performance and code quality parity on
all of our benchmarks, and once we were confident in the correctness of the new
code, we flipped the switch and [enabled the new mid-end by default]. However,
out of an abundance of caution and care, we kept the old mid-end around just in
case we found a critical CVE and needed to temporarily disable the new mid-end
again. Finally, by April we were extremely confident in the new code, so we
[removed the old mid-end pipeline once and for all]. This was the culmination of
a lot of hard work by Chris Fallin with help from Jamey Sharp, Afonso Bordado,
Nick Fitzgerald, Trevor Elliott, and more.

Chris Fallin gave an [invited talk at the EGRAPHS workshop at PLDI] this year on
the design and implementation of the new mid-end:

<iframe src="https://player.vimeo.com/video/843540328?h=152ec167ef" frameborder="0" allow="autoplay; fullscreen; picture-in-picture" width="840" height="472" allowfullscreen></iframe>

([Slides])

<!-- git shortlog -s -n -- $(git ls-files | grep '\.isle$' | grep -v isa) -->

We've had 17 different contributors add or tweak ISLE rewrite rules in the
mid-end and it's become a common starting place for new folks to dive into
Cranelift development. We've also [automated] harvesting potential left-hand
sides from Wasm and synthesizing new optimization rules via [Souper].

Even so, there are plenty of rewrites we are still missing and ways we could
extend the mid-end framework and ISLE compiler in 2024:

* We'd like to synthesize more optimization rules via Souper that are based on
  hot functions in specific benchmarks we care a lot about (e.g. the
  interpreter-loop function in `spidermonkey.wasm`).

* It would be nice to do a census of rewrites in LLVM and GCC and port the
  rewrites we're missing to ISLE. This could be a great place for a motivated
  new contributor to start chipping away at!

* We'd like to extend the mid-end framework to be able to [rewrite
  side-effectful instructions] like [instructions that can trap] as well as
  instructions that produce multiple results. It can't rewrite either currently.

* We'd like to investigate fusing rewrite rules together inside the ISLE
  compiler, so that we rewrite an expression directly to its optimal form in one
  step, instead of incrementally across many rewrite invocations.

* Many operations are commutative, and we would like to have the [ISLE compiler
  automatically emit code] to match `add(foo(), x)` and `add(x, foo())` without
  needing to explicitly author both versions. This becomes even more important
  when we are matching against deep patterns that contain multiple nested
  commutative operations.

* We currently perform some legalization early in the compiler pipeline in
  open-coded Rust matches, that we would like to port to ISLE. [Some
  exploratory work has already begun].

* Finally, right now we elaborate out of the e-graph representation back to a
  control-flow graph, and then lower out of the control-flow graph into machine
  instructions. The elaboration step involves an explicit cost function where we
  assign a cost to each operator and use dynamic programming to extract
  minimum-cost expressions. Lowering also involves a cost function, but it is
  implicitly encoded in the patterns we have on the left-hand sides of our
  lowering rules. If we can combine a certain shape of add and multiply into an
  address mode of a load when targeting a particular architecture, those
  specific forms of adds and multiplies are cheaper than they otherwise would be
  if they feed into a load. At some time in the future, we'd like to explore
  combining these cost functions and lowering directly from the e-graph
  representation, without elaborating back into a control-flow graph in
  between. We suspect that, with the right design and implementation, we could
  both speed up compile times and emit better machine code.

[introduced a new mid-end framework]: https://github.com/bytecodealliance/wasmtime/pull/4953
["mid-end"]: https://en.wikipedia.org/wiki/Compiler#Middle_end
[e-graph]: https://en.wikipedia.org/wiki/E-graph
[ISLE]: https://github.com/bytecodealliance/wasmtime/tree/main/cranelift/isle
[enabled the new mid-end by default]: https://github.com/bytecodealliance/wasmtime/pull/5587
[removed the old mid-end pipeline once and for all]: https://github.com/bytecodealliance/wasmtime/pull/6167
[invited talk at the EGRAPHS workshop at PLDI]: https://pldi23.sigplan.org/details/egraphs-2023-papers/2/-graphs-Acyclic-E-graphs-for-Efficient-Optimization-in-a-Production-Compiler
[Slides]: https://cfallin.org/pubs/egraphs2023_aegraphs_slides.pdf
[automated]: https://github.com/bytecodealliance/wasmtime/pull/7312
[Souper]: https://github.com/google/souper/
[rewrite side-effectful instructions]: https://github.com/bytecodealliance/wasmtime/issues/6106
[instructions that can trap]: https://github.com/bytecodealliance/wasmtime/issues/5908
[ISLE compiler automatically emit code]: https://github.com/bytecodealliance/wasmtime/issues/6128
[Some exploratory work has already begun]: https://github.com/bytecodealliance/wasmtime/pull/7321

We also implemented a number of codegen improvements and optimizations outside
of the mid-end framework in 2023:

* Nick Fitzgerald optimized code produced when compiling Wasm with explicit
  bounds checks, [reducing their overhead] in comparison to using virtual memory
  guard pages to elide bounds checks. Before this work started, using explicit
  bounds checks was about three times slower than using guard pages. Now it is
  only about one and a half times slower, which matches what we've seen from
  other top-tier Wasm engines, like SpiderMonkey. We have ideas for new
  optimization passes to further speed up explicit bounds checks in 2024 as
  well.

* Trevor Elliot added support for [overlapping live ranges] in `regalloc2` and a
  number of other small but important optimizations. These changes involved
  migrating `regalloc2` to a fully static single-assignment (SSA) interface and
  hunting down all the little places in Cranelift's backend where we played a
  little too fast and loose but it didn't previously matter. This sets us up for
  more potential compile time and code quality wins in the future such as
  removing the redundant move eliminator.

* Afonso Bordado adopted the `riscv64` backend, performed a massive clean up,
  eliminated internal branches in the emitted code, and added a ton of [new
  lowering rules] to emit better code sequences for certain snippets of CLIF. He
  also added support for emitting RISC-V's [compressed instructions] which
  shrink code size, improve energy efficiency, and lower icache misses, TLB
  misses, and page faults.

* Alex Crichton added extensive [support for using AVX instructions] for both
  SIMD operations and non-SIMD floating point operations to our `x86-64`
  backend. This provides two primary benefits:

  1. These instructions are typically in "three-operand form" where one of the
  input registers is not necessarily also the destination, which gives more
  flexibility to the register allocator.

  2. These instructions don't typically fault on unaligned memory accesses, so
  we can sink loads and stores into other floating point operations. Because
  Wasm can't guarantee loads and stores within linear memory are aligned, we
  wouldn't otherwise be able to sink these memory operations, and would need to
  emit separate explicit load and store instructions that handle unaligned
  addresses.

* It was previously the case that enabling the Wasm SIMD proposal in Wasmtime
  (and using SIMD instructions in general with Cranelift) on `x86-64` required the
  SSE4.2 extension. Alex Crichton lifted that constraint and added fallback
  lowerings for [SSE4.1], [SSSE3], and [SSE2].

* Alex Crichton also improved a few SIMD benchmarks by finding and fixing
  missing special-case lowerings for SIMD [on `x86-64`] and [on `aarch64`].

[reducing their overhead]: https://github.com/bytecodealliance/wasmtime/issues/6094
[overlapping live ranges]: https://github.com/bytecodealliance/regalloc2/pull/122
[new lowering rules]: https://github.com/bytecodealliance/wasmtime/pull/7079
[compressed instructions]: https://github.com/bytecodealliance/wasmtime/pull/7057
[support for using AVX instructions]: https://github.com/bytecodealliance/wasmtime/pull/5795
[SSE4.1]: https://github.com/bytecodealliance/wasmtime/pull/6206
[SSSE3]: https://github.com/bytecodealliance/wasmtime/pull/6489
[SSE2]: https://github.com/bytecodealliance/wasmtime/pull/6625
[on `x86-64`]: https://github.com/bytecodealliance/wasmtime/pull/5930
[on `aarch64`]: https://github.com/bytecodealliance/wasmtime/pull/5977

Of course, we didn't only work on optimizations in Cranelift this year. One of
Cranelift's core goals and reasons for existence is its focus on security,
correctness, and lightweight verification. We made a number of improvements
along these lines in 2023 as well.

We are happy to share that we have formally verified our CLIF to machine
instruction lowerings for all of the integer operations in the `aarch64`
backend! This is a very strong guarantee: it proves that for all compilations,
the associated lowering rules are correct. We had [a CVE related to bad address
mode lowerings] in March, and by adding the relevant verification specs to the
`x86-64` lowering rules, we were able to identify the bug without even compiling
and running any Wasm code that leveraged the vulnerability. This is one way we
are mitigating sandbox escapes in the future. The paper has been conditionally
accepted for [ASPLOS 2024], and you can [read a pre-print here]. Big thanks to
Alexa VanHattum, Monica Pardeshi, Chris Fallin, Adrian Sampson, and Fraser
Brown, as well as Jamey Sharp, Nick Fitzgerald, Trevor Elliott, and everyone
else involved in this effort. In 2024, we hope to expand this work to our other
backend targets, like `x86-64`, as well as to the mid-end rewrite rules.

The second way we are mitigating potential miscompilations that can lead to
sandbox escapes is by [translation validation and proof-carrying code]. This
work aims to validate that every memory operation we emit on behalf of a
particular Wasm program is provably within that Wasm's linear memory
sandbox. The [VeriWasm paper] did this for an old version of Cranelift but
Cranelift and Wasmtime have grown up a lot since then: emitting better code that
takes advantage of more complicated address modes, and supporting multiple
memories with different configurations. Chris Fallin attempted to revive the
VeriWasm project and port it to modern Wasmtime, but found that updating its
forwards static analysis was both too difficult and too slow. However, he came
up with an alternative solution based on proof-carrying code, where the Wasm
frontend leaves "breadcrumbs" describing facts it believes to be true about the
values computed in the program, and then after we lower the program to machine
instructions we assert that we can prove that these facts still hold. Chris
Fallin and Nick Fitzgerald implemented this approach in October and November,
and it is very promising: initial benchmarks show as little as 1% overhead to
compilation. The proof-carrying code approach supports both static memories with
virtual guard pages to elide bounds checks and dynamic memories that rely on
explicit bounds checks. That said, there are currently known bugs and false
positives. We hope to fix these bugs and get our proof-carrying code safety
checks shipping and enabled by default in 2024.

Additionally, we continued pushing our boulder up the hill and making
improvements to our fuzzing infrastructure:

* Afonso Bordado contributed many fixes and additions to the [CLIF interpreter]
  and to the [CLIF test case generator]. We use the test case generator to
  create random inputs when fuzzing, and we use the interpreter as an oracle to
  do differential fuzzing against the compiler.

* Remo Senekowitsch, Falk Zwimpfer, MzrW and Chris Fallin added a ["chaos mode"]
  to Cranelift compilation. When enabled, Cranelift will make random (but
  deterministically seeded) and semantics-preserving changes to its output:
  invert a branch condition and swap the if/else branch targets, skip merging
  fallthrough blocks together, split live ranges randomly, etc... The goal
  is to uncover hidden bugs that require bizarre context in order to reproduce.

* And of course there was continued attention on the little things, like fixing
  the bugs we find while fuzzing, such as [avoiding quadratic behavior] when
  processing branch labels and [incorrect float-to-int conversion] on `riscv64`.

[a CVE related to bad address mode lowerings]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-ff4p-7xrq-q5r8
[ASPLOS 2024]: https://asplos-conference.org/
[read a pre-print here]: https://www.cs.cornell.edu/~avh/veri-isle-preprint.pdf
[translation validation and proof-carrying code]: https://github.com/bytecodealliance/wasmtime/issues/6090
[VeriWasm paper]: https://github.com/bytecodealliance/wasmtime/issues/6090
[CLIF interpreter]: https://github.com/bytecodealliance/wasmtime/pull/5991
[CLIF test case generator]: https://github.com/bytecodealliance/wasmtime/pull/5971
["chaos mode"]: https://github.com/bytecodealliance/wasmtime/pull/6039
[avoiding quadratic behavior]: https://github.com/bytecodealliance/wasmtime/pull/6804
[incorrect float-to-int conversion]: https://github.com/bytecodealliance/wasmtime/pull/6015

Cranelift also received support for some new features in 2023:

* Nick Fitzgerald and Jamey Sharp [implemented tail calls] and added the `tail`
  calling convention.

* Afonso Bordado [implemented SIMD lowerings for `riscv64`].

* Alex Crichton added [additional SIMD instructions and lowerings] as part of
  implementing the Wasm relaxed SIMD proposal.

[implemented tail calls]: https://github.com/bytecodealliance/wasmtime/pull/6635
[implemented SIMD lowerings for `riscv64`]: https://github.com/bytecodealliance/wasmtime/pull/6643
[additional SIMD instructions and lowerings]: https://github.com/bytecodealliance/wasmtime/pull/5846

Finally, we landed some internal refactorings that are largely invisible to the
outside world (but very important for the long-term health of the project!) such
as cleaning up CLIF as an intermediate representation. For example, Trevor
Elliott [added proper two-way conditional branches] so we don't need to maintain
the invariant that basic blocks ending in conditional control flow end with a
one-way conditional branch to the consequent followed by an unconditional branch
to the alternative. Trevor also [introduced the `uadd_overflow_trap` CLIF
instruction] to improve bounds-checks performance.

[added proper two-way conditional branches]: https://github.com/bytecodealliance/wasmtime/pull/5446
[introduced the `uadd_overflow_trap` CLIF instruction]: https://github.com/bytecodealliance/wasmtime/pull/5123

### What's Next for Cranelift in 2024?

We will continue to push on best-in-class safety and correctness. As previously
mentioned, we have lots of ways we'd like to extend ISLE and our mid-end
framework. We want to verify our lowering rules for more backends and verify our
mid-end rules. In general, the more parts of the compiler pipeline we can
rephrase as ISLE rewrites, the more of the compiler we can formally verify.
We'd like to ship the proof-carrying code safety checks and eventually enable
them by default. We want multiple layers of protection because no layer is
completely perfect on its own.

We intend to continue our ongoing performance efforts. We should continue to
improve both compile times and code quality. We have the big frameworks in
place, for the most part, and now we can start focusing on evolving the rule
sets within them.

Overall, we expect to fall into the steady development rhythm that reflects
Cranelift's position as a maturing compiler!

## See You in 2024!

We are extremely proud of the work we've done in 2023 and we are excited to
accomplish even more together in 2024! If you want to get involved in Wasmtime
or Cranelift, [check out the contributors documentation] and [come say hello in
our Zulip chat].

One more big thanks to everyone who contributed over the past year! Y'all are
spectacular and amazing!

See you next year!

[check out the contributors documentation]: https://docs.wasmtime.dev/contributing.html
[come say hello in our Zulip chat]: https://bytecodealliance.zulipchat.com/
