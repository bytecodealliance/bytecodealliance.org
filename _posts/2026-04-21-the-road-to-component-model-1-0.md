---
title: "The Road to Component Model 1.0"
author: "Eric Gregory"
date: "2026-04-21"
github_name: "ericgregory"
excerpt_separator: <!--end_excerpt-->
---
WASI 0.3.0 is almost here, bringing native async support to the **WebAssembly System Interface (WASI)** and **Component Model**. In this post, we're looking to the *next* big milestone: a stable, formally specified Component Model 1.0.

At February's Bytecode Alliance Plumbers Summit, Luke Wagner and Alex Crichton gave a preview of what the path to a stable 1.0 actually looks like. Last month at [Wasm I/O 2026 in Barcelona](https://wasm.io/), Wagner [expanded on that vision](https://youtu.be/qq0Auw01tH8?si=4Zb2r52SNsAsUtkQ). So let's take a look at where the Component Model is heading.

<!--end_excerpt-->

## A quick refresher on the Component Model and WASI

Before we dive into the future of the Component Model, we should take a moment to review what the specification does, as well as its relationship to WASI.

* The [**Component Model**](https://github.com/WebAssembly/component-model) is the specification layered atop core WebAssembly that defines how Wasm binaries bundle, link, and communicate: it specifies the type system, the binary format, the interface definition language, and the calling conventions for passing typed values across component isolation boundaries. 

* The [**WebAssembly System Interface (WASI)**](https://github.com/WebAssembly/WASI), in turn, is a standardized set of APIs for accessing system resources like files, sockets, clocks, randomness, and more in a portable, capability-secure way. 

WASI interfaces are consumed through the Component Model; together they form the composable, portable foundation of the Wasm ecosystem. (It's worth noting that Component Model 1.0 and WASI 1.0 are related but distinct milestones: WASI 1.0 will follow from and depend on the Component Model reaching 1.0 first.)

At the Plumbers Summit, Wagner described the relationship between the Component Model and WASI as analogous to a microkernel architecture: the Component Model is the always-present microkernel, providing foundational primitives that run across any host. WASI layers on top like OS services (e.g., networking, storage, graphics) that run as processes on top of the microkernel and may or may not be present on a given device. A browser, for instance, has very strong opinions about what I/O APIs exist; WASI interfaces run there via polyfill. But the Component Model itself can be implemented natively in the browser alongside core WebAssembly, since it only provides computational primitives, not I/O.

In practical terms, the Component Model is already stable. P1 modules still work. P2 components still work. The team has been maintaining this stability since P1 using semantic versioning, side-by-side implementations, and Wasm-to-Wasm adapters. That story continues past 1.0. As Wagner put it: "We can start using this stuff now." But *getting* to Component Model 1.0 involves critical work across several important areas.

## Five areas of work

Wagner frames the path to 1.0 around five areas of work:

### 1. ABI improvements

The Component Model's current Application Binary Interface (ABI), the calling convention that governs how components pass data to each other, relies on a function conventionally called `cabi_realloc`. When a callee returns a value like a list of strings, the host calls `cabi_realloc` to allocate memory for each element, then copies everything before returning to the caller. This works, but experience has surfaced real friction: heap fragmentation over time, difficulty handling large allocation failures gracefully, one host-to-guest call per value in a list, and trouble using custom memory allocators.

One planned change inverts the control flow. Instead of the host eagerly allocating, the callee returns *lazy value handles*: opaque `i32` indices. When the caller is ready to place a value into memory, it calls a static built-in function with the destination address. Because these built-ins are statically known to the compiler, they can be inlined as if they were instructions.

This lazy ABI resolves the existing friction, and adds a few bonuses: lazy values can be zero-copy forwarded between calls, dropped if unused, and the approach cleans up some complex string transcoding logic that currently lives in the engine by moving it into guest code.

![Two sequence diagrams comparing the eager and lazy ABIs. In the eager diagram, the caller invokes the callee, and the callee makes repeated round-trip calls to cabi_realloc to allocate memory for each returned value before control returns to the caller. In the lazy diagram, the callee returns immediately with opaque handles; the caller then calls statically-known ABI built-ins that are inlined directly into the caller rather than crossing a component boundary.](../images/lazy-and-eager.png)

The transition is designed to be non-breaking: the lazy ABI ships as a new opt-in option in a 0.3.x minor release, and producer toolchains adopt it when ready. When 1.0 arrives and adoption is complete, the lazy ABI becomes the default and the option goes away. An adapter tool will handle converting eager components to lazy.

Bundled into the same transition are multivalue returns (using Wasm multivalue for return types at the C ABI level) and an error context value in every result's error case, so there's always a standard way for hosts to attach backtraces and debug information.

A related but distinct performance goal sits alongside the ABI work: sync-to-sync component-to-component calls with zero overhead. The current spec includes async state management flags that, according to Nick Fitzgerald's Plumbers Summit presentation, cause roughly 3.5x overhead on synchronous calls. These flags exist to handle reentrance and task switching in the async runtime, but they add cost even for purely synchronous call paths. Some of this has already been addressed at the spec level (the recursion check was removed during P3 development), and active work is underway in [Wasmtime](https://github.com/bytecodealliance/wasmtime) to move remaining task state into inline trampolines that [Cranelift](https://github.com/bytecodealliance/wasmtime/tree/main/cranelift) (Wasmtime's optimizing code generation backend) can optimize away.

There is one significant dependency: LLVM doesn't yet support multivalue at the C ABI level. Getting that upstream may be the longest lead time in this piece of work.

There's also a separate GC ABI option planned, enabling components to pass values via Wasm GC-allocated memory instead of linear memory, and avoiding copies through linear memory for GC-based languages. Nick Fitzgerald has a pre-proposal on this in [Component Model issue 525](https://github.com/WebAssembly/component-model/issues/525).

### 2. The browser path

The Component Model can't formally reach 1.0 without native implementation in at least two browser engines. The groundwork for browser implementations is being laid today: `jco`'s `transpile` command already converts any component into equivalent core Wasm and JavaScript glue, making components runnable in any browser without native support. That already works, but native support matters for two reasons:

- **Performance**: [Experiments](https://hacks.mozilla.org/wp-content/uploads/2026/02/Screenshot-2026-02-25-at-2.22.23-PM-1536x1018.png) by Ryan Hunt at Mozilla show that a DOM mutation-heavy Wasm VDOM reconciliation loop can get close to a 2x speedup from direct Wasm-to-browser API calls, bypassing the JavaScript glue layer. Real-world gains will vary by workload, but the ceiling is meaningful.

- **Reach**: Native Component Model support in browsers creates strong incentives for upstream Wasm support across languages, packages, and frameworks, which in turn feeds back into a better developer experience across all platforms where Wasm runs.

The strategy for earning that support borrows a page from [WebAssembly's own history](https://bytecodealliance.org/articles/ten-years-of-webassembly-a-retrospective). When asm.js shipped, it contained a no-op `"use asm"` string that browser engines could detect in their feature usage telemetry, building a data-driven case for optimization and eventually WebAssembly itself. `jco` is doing the same: its generated JavaScript glue now emits a `"use components"` identifier (renamed from `"use jco"` in jco 1.16.8). As `jco`-transpiled components accumulate real-world usage, that data becomes evidence for native implementation.

Both Mozilla and Chrome are paying attention. The Mozilla team presented performance results at a recent in-person WebAssembly CG meeting. The Chrome V8 team opened an issue for evaluating component model implementation. These aren't commitments, but they're meaningful signals. For folks working in the component ecosystem, now is a great time to use `jco`-transpiled components in browser contexts.

### 3. Making the Component Model easier to implement

Getting native browser support requires a manageable implementation burden. The plan here is a pair of C ABIs, one for guests and one for hosts, both expressed as header files generated by `wit-bindgen`.

- The **guest C-ABI** lets toolchains target the Component Model by compiling to a core Wasm module and calling Component Model imports via generated C headers, then wrapping the result into a component binary with a `wasm-component-ld` linker. Toolchain authors work in familiar territory, much like targeting WASI P1.

- The **host C-ABI** lets core Wasm runtimes implement Component Model support without re-implementing the full spec. A proposed new tool tentatively called `lower-components` would "smash" a compound component (containing multiple modules and memories) into a single core Wasm module with the same observable behavior, using Wasm multi-memory. The host would then interact with it through a generated host C-ABI header.

![Diagram showing two parallel paths from source code to a running component. The top path runs left to right: source code flows through producer toolchains into a WASI 0.3 component, which is then executed by Wasm runtimes. Below, branching arrows show an alternative implementation path using a pair of generated C header files: a Guest C ABI header that producer toolchains can target, and a Host C ABI header that Wasm runtimes can implement, with shared tools connecting the two.](../images/easier-to-implement.png)

The goal here is for implementing WASI and the Component Model to be about as easy as implementing WASI P1. Projects like `jco` and Gravity (built on wazero) are already doing something like "component smashing" by reusing parts of Wasmtime. A hypothetical `lower-components` tool would formalize this into a proper CLI tool.

### 4. Growing the ecosystem

In addition to everything above, the path to 1.0 will include a sustained documentation and ecosystem push:

- More introductory, tutorial, and reference content for each language and tool. The [Component Model book](https://component-model.bytecodealliance.org/) and Danilo Chiarlone's [*Server-Side WebAssembly*](https://www.manning.com/books/server-side-webassembly) are great starts, but more is needed.

- Getting stable P3 support upstream in the major language ecosystems. Progress is trackable in Yosh's [awesome-wasm-components](https://github.com/yoshuawuyts/awesome-wasm-components) repo. Rust, Tokio, LLVM, and CPython all have first steps underway.

- More cross-language tooling like `jco` (more Web API integration via WebIDL imports), `wac` (component composition from the command line or a linking language), and `wkg` (publishing and fetching from OCI registries, with higher-level discovery tooling still needed).

- Record/replay debugging, a capability uniquely suited to components' shared-nothing architecture. At the Summit, Yan Chen demoed a concrete implementation: instrumentation components wrap a target component's imports and exports, recording all WIT-level calls in WAVE format and replaying them later without the original host. Recorded traces are editable and human-writable in WAVE syntax, and can be replayed against a modified binary — a debugging workflow that the Component Model's isolation makes possible.

### 5. Closing expressivity gaps

[WebAssembly Interface Type (WIT)](https://component-model.bytecodealliance.org/design/wit.html) serves as the Component Model's interface definition language, describing the typed APIs a component imports and exports.

The path to 1.0 includes work on several WIT features, based on gaps identified in practice:

- **Optional imports**: Lets a component declare that it only optionally requires a capability. Standard libraries could compile against a minimal host world without forcing every component to unconditionally import files, sockets, and GPU capabilities. This pairs well with the guest C-ABI.

- **Callbacks**: Needed to express DOM APIs like `addEventListener` in WIT.

- **Resource subtyping**: Lets a resource type (like a DOM Node) extend another (like EventTarget), enabling method reuse without virtual dispatch or complex inheritance semantics.

- **Function subtyping**: Allows WIT interfaces to add parameters, record fields, and variant cases without having to add new functions or declare a breaking change, something that's currently painful in practice.

- **Enhanced import/export names**: Lets components import multiple of the same WIT interface with different arbitrary identifiers, enabling deployment-time configuration checking rather than runtime surprises.

- **Getters and setters**: Syntactic sugar for more idiomatic bindings in languages that expect property access patterns. Like constructors and methods, these would be sugar for regular functions with special names that binding generators recognize.

- **Map type**: For producing and consuming idiomatic objects, dictionaries, and associative arrays across languages. (Yordis Prieto is already working on this!)

- **Runtime instantiation**: The ability to instantiate components at runtime, within the Component Model. This is useful for lazy code loading, spawning subcommands, and giving different components different lifetimes. Browsers already support something more powerful in their JavaScript API; this would bring some of this functionality to the Component Model so that producer toolchains could address these use cases in a way that works both inside *and* outside the browser.

Not all of these will land before 1.0: some may come in 1.x releases. Sequencing depends on use cases and available resources.

## Cooperative threads and stream splicing

Sy Brand presented a deep dive on cooperative threads at the Plumbers Summit, and it's worth noting here that they're implemented at the Component Model level, below the WASI layer. A Rust component using `std::thread::spawn` gets cooperative thread support when it lands, with nothing special needed in WIT.

The implementation is in progress: `wasi-libc` pthreads support is largely done, LLVM patches are under review, and Wasmtime has a functional implementation under a feature flag. Cooperative threads support will ship in a WASI 0.3.x minor release. These advancements also pave the road for shared-everything threads later, since many of the heaviest toolchain lifts for cooperative threads carry over directly.

Also shipping in an early 0.3.x minor release is **stream splicing**, the ability to splice one stream directly into another without an intermediate copy. Stream splicing is important for streaming performance, since unnecessary copying through an intermediate buffer is costly on hot paths, and was simply too close to the wire to make 0.3.0.

## The toolchain view

At the Plumbers Summit, Alex Crichton highlighted the implementation pipeline for new features:

![A left-to-right pipeline of five boxes connected by arrows, showing how new features flow through the Component Model toolchain: the Component Model spec feeds into wasm-tools (binary format, validation), which feeds into Wasmtime (runtime semantics), which feeds into wit-bindgen (guest language bindings), which feeds into guest libraries and toolchains.](../images/toolchain-pipeline.png)

Each stage provides feedback that refines the previous one. The Bytecode Alliance controls much of this pipeline, but not all of it. Rust, LLVM, CPython, and the broader ecosystems have their own release cadences and decision-making processes. LLVM releases every six months; landing something in Rust takes roughly nine weeks to reach stable. Release cycles matter when you're coordinating changes across this many dependencies.

## Getting involved

If you want to help out on the road to Component Model 1.0, there are lots of different ways to contribute:

- **Spec discussion:** The [Component Model repo](https://github.com/WebAssembly/component-model) is where WIT expressivity feature proposals land.

- **Implementation:** [`wasm-tools`](https://github.com/bytecodealliance/wasm-tools), [Wasmtime](https://github.com/bytecodealliance/wasmtime), and [`wit-bindgen`](https://github.com/bytecodealliance/wit-bindgen) are the core implementation projects.

- **Language toolchains:** [`wit-bindgen-go`](https://github.com/bytecodealliance/go-modules), [`componentize-py`](https://github.com/bytecodealliance/componentize-py), [`componentize-js`](https://github.com/bytecodealliance/ComponentizeJS), and others need P3 support and ecosystem work.

- **Browser usage:** Using `jco`-transpiled components in browser contexts contributes directly to the telemetry signal that motivates native browser implementation.

- **Discussion:** The [Bytecode Alliance Zulip](https://bytecodealliance.zulipchat.com/) is the primary venue for day-to-day discussion across all of these projects.

WASI P3 is almost here. Now the work continues, taking the Component Model from a preview to a stable, long-term foundation for the Wasm ecosystem.