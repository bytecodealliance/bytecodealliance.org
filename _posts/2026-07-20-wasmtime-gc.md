---
title: "GC and Exceptions in Wasmtime"
author: "Nick Fitzgerald"
github_name: fitzgen
---

The Wasm GC and exceptions proposals are both enabled by default in today's
[Wasmtime 47 release]! We are excited to help bring more languages to WebAssembly
and everywhere that Wasmtime runs. Getting to this point involved large Wasmtime
changes and represents the culmination of years of engineering effort.

## Wasmtime

[Wasmtime] is a WebAssembly runtime that is [fast][inliner],
[safe][safety-and-correctness], and [portable]. It is standalone, lightweight,
and easy to [embed][api]. Wasmtime maintainers are [committed][ba-about] to open
standards and actively participate in Wasm standardization.

## Wasm GC

Originally, in the first versions of WebAssembly, high-level languages with an
objects-and-references data model, as opposed to a raw-pointers-and-memory data
model, had to embed their own garbage collector inside their `.wasm`
binaries. This led to bloated `.wasm` binaries and many techniques often used
when implementing collectors in native code, such as using [stack maps] and
stack walking to identify GC roots, were unavailable. And, unfortunately, many
languages fell into this bucket.

The [Wasm GC][wasm-gc] proposal improves the situation, adding efficient support
for these high-level languages to WebAssembly.[^outdated] It extends the
WebAssembly language, allowing Wasm programs to define their own `struct` and
`array` types and subtyping relationships. The Wasm program needn't worry about
managing these types' instances' lifetimes or manually deallocating them; the
runtime handles all of that. Therefore, embedding their own garbage collector is
unnecessary, and these toolchains can instead take advantage of the WebAssembly
runtime's collector. This opens the door for many more languages to easily and
more efficiently target WebAssembly.

[^outdated]: Note that the GC proposal has merged into the main WebAssembly
    specification, so the proposal page is now an archived snapshot of a
    particular moment in time.

As an example, here is how a Wasm program might define [a node type for a binary
tree](https://github.com/bytecodealliance/sightglass/blob/98ff8a598b4b4f6eab0d8f391118411990efde96/benchmarks/splay/splay.wat#L15-L22):

```wat
(rec
  (type $node (struct
    (field $key (mut f64))
    (field $left (mut (ref null $node)))
    (field $right (mut (ref null $node)))
    (field $value (mut (ref null $payload)))
  ))
)
```

New instances are created by [`struct.new
$node`](https://github.com/bytecodealliance/sightglass/blob/98ff8a598b4b4f6eab0d8f391118411990efde96/benchmarks/splay/splay.wat#L310)
and fields accessed via, e.g., [`struct.get $node
$key`](https://github.com/bytecodealliance/sightglass/blob/98ff8a598b4b4f6eab0d8f391118411990efde96/benchmarks/splay/splay.wat#L327)
or [`struct.set $node
$left`](https://github.com/bytecodealliance/sightglass/blob/98ff8a598b4b4f6eab0d8f391118411990efde96/benchmarks/splay/splay.wat#L332)
instructions.

## Wasm Exceptions

Wasm's [exceptions proposal] has goals for exception-using languages similar to
the Wasm GC proposal's goals for objects-and-references languages: it aims to
enable efficient support for exceptions on WebAssembly, making WebAssembly a
better compilation target for languages with exceptions.[^outdated2] Without
this proposal, toolchains would need to implement custom calling conventions
that return not just function results, but also whether the function returned
normally or threw an exception. Every call site must test this condition and
branch appropriately, adding both bloat to the `.wasm` binary and runtime
overhead to the common, normal-return path. However, with the exceptions
proposal, all that goes away, and is replaced by `throw` and `try`/`catch`-style
constructs. The WebAssembly runtime is then free to implement these with the
classic unwinding approach that imposes zero overhead to the common,
normal-return call paths, resulting in faster execution and smaller `.wasm`
binaries.

[^outdated2]: Like the GC proposal, the exceptions proposal has also merged into
    the main WebAssembly specification, and the proposal repo is now an archived
    historical snapshot.

## Wasmtime's GC Implementation

Wasmtime has a simple [Cheney-style semi-space copying
collector][cheney-gc]. The GC heap is divided into two halves: the "active"
semi-space where new objects are allocated, and the "idle" semi-space. During
collection, live objects are copied from the idle space (which was the previous
active space) to the new active space, and all GC roots (e.g. active references
inside Wasm stack frames) are updated to point to the new locations. Allocation
is a simple bump pointer within the active semi-space and the collector does not
require any read or write barriers.

We reuse WebAssembly linear memories under the covers to implement and sandbox
the GC heap. A reference to a GC object is not a native pointer, it is a 32-bit
index into the GC heap's underlying linear memory. WebAssembly promises to be
fast, safe, and portable, but it is the runtime that must actually shoulder that
responsibility in its implementation, and reusing linear memories for the GC
heap has benefits in all three dimensions. Perhaps most obvious is the
defense-in-depth safety implication: even in the face of collector bugs that
corrupt the GC heap, a malicious Wasm program can't escape the sandbox to access
host memory. As far as being fast goes, it lets us use virtual-memory guard
pages to elide explicit bounds checks, just like we do for linear memories; we
get tight integration with our pooling instance allocator, ensuring we preserve
our 5-microsecond instantiation times; and, on 64-bit machines, 32-bit GC
references are more compact than 64-bit pointers, more efficiently utilizing CPU
caches. Finally, allocating, deallocating, and resetting large regions of memory
quickly across many platforms (including bare metal!), each of which have subtly
different capabilities, involves a lot of special-casing. Our existing
implementation of linear memories is already portable across these platforms and
already does that special-casing, so, by building our GC heap on top of a linear
memory, we get a portable GC heap "for free" as well.

To further ratchet up our confidence in the collector's correctness, we extended
our fuzzing infrastructure to hammer on Wasm GC. First, we extended
[`wasm-smith`] to support the GC proposal. It can, in theory, generate roughly
any GC-using Wasm program, given [enough time][fuzz-experiment].[^wasm-smith-gc]
But it might take a *looong* time to do that, which is why we supplemented it
with two additional fuzzers:

1. One designed to [exercise][gc-ops-fuzzer] interesting and arbitrary object
   graphs, type references, and subtyping relationships
2. Another designed to [detect][gc-access-fuzzer] heap corruption due to
   collector bugs or misoptimizations in our compiler

[^wasm-smith-gc]: `wasm-smith`'s only blind spot with regards to Wasm GC at the
    time of writing is that it will never generate non-nullable references.

Lastly, a small note regarding performance to set expectations: we've mainly
focused our engineering efforts on the correctness of our collector thus far,
and less so on its performance. It's brand new, and hasn't benefited from
decades of performance engineering, unlike collectors in, for example, [V8] and
[SpiderMonkey]. Our collector's throughput and latency won't match theirs
today. Additionally, we've been primarily designing the collector and its trade
offs for the use cases where Wasmtime is used most in production: creating many
small, disposable Wasm instances, each of which is processing a small handful of
tasks before it, and its GC heap, are thrown away. The system is designed first
to scale horizontally across many instances rather than focusing on
single-instance performance above all else. This scenario is different from,
say, a single long-lived server process with indefinite lifetime; tuning a
collector for it will also be different.

## What's Next

There's always lots of [performance work][gc-perf-issues] still to be done. We
are, for example, currently in the process of extending our compiler's
alias-analysis optimizations, like store-to-load forwarding and redundant-load
elimination, with GC-type information. When we know that two types can *never*
alias, that is, they cannot occupy the same memory location, we can be more
aggressive with these optimizations.

The next big milestone, functionality-wise, is to prototype [GC integration with
the component model][gc-cm] on top of [lazy value lowering]. This effort will
promote garbage-collected languages to first-class citizens in the component
ecosystem, since they will no longer need otherwise-unused linear memories just
to pass data across components.

## Conclusion

We are excited to have reached this milestone! Give Wasmtime's newly enabled GC
and exceptions support [a test run][Wasmtime] and [let us know][zulip] how it
goes.

[Wasmtime]: https://wasmtime.dev/
[inliner]: https://bytecodealliance.org/articles/inliner
[safety-and-correctness]: https://bytecodealliance.org/articles/security-and-correctness-in-wasmtime
[portable]: https://bytecodealliance.org/articles/wasmtime-portability
[api]: https://docs.wasmtime.dev/lang.html
[ba-about]: https://bytecodealliance.org/about
[wasm-gc]: https://github.com/WebAssembly/gc
[exceptions proposal]: https://github.com/WebAssembly/exception-handling
[`wasm-smith`]: https://github.com/bytecodealliance/wasm-tools/tree/main/crates/wasm-smith
[gc-ops-fuzzer]: https://github.com/bytecodealliance/wasmtime/issues/10327
[gc-access-fuzzer]: https://github.com/bytecodealliance/wasmtime/blob/86b242fcc4e508a2b4f7cd698063cad80d44f249/crates/fuzzing/src/generators/gc_access.rs
[cheney-gc]: https://en.wikipedia.org/wiki/Cheney%27s_algorithm
[gc-perf-issues]: https://github.com/bytecodealliance/wasmtime/issues?q=is%3Aissue%20state%3Aopen%20gc%20label%3Awasm-proposal%3Agc%20label%3Aperformance
[gc-cm]: https://github.com/WebAssembly/component-model/issues/525
[lazy value lowering]: https://github.com/WebAssembly/component-model/issues/383
[zulip]: https://bytecodealliance.zulipchat.com/#narrow/stream/217126-wasmtime
[fuzz-experiment]: https://fitzgen.com/2026/06/01/structure-aware-fuzzing-experiment.html
[stack maps]: https://fitzgen.com/2024/09/10/new-stack-maps-for-wasmtime.html
[ruby-setjmp]: https://docs.ruby-lang.org/capi/en/master/da/d7d/setjmp_8c_source.html
[V8]: https://v8.dev/
[SpiderMonkey]: https://spidermonkey.dev/
[Wasmtime 47 release]: https://github.com/bytecodealliance/wasmtime/releases/tag/v47.0.0
