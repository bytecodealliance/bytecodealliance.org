---
name: "WebAssembly: An Updated Roadmap for Developers"
date: "2023-07-24"
title: "WebAssembly: An Updated Roadmap for Developers"
subtitle: "Bytecode Alliance is happy to publish the roadmap to WASI Preview 2."
author: "Bailey Hayes"
github_name: ricochet
excerpt_separator: <!--end_excerpt-->
---
The WebAssembly (Wasm) ecosystem is transforming. Developers can look forward to a modular, virtualizable, and robust environment for building applications, libraries, and services.

We are excited to be working towards this with implementations for WASI-Preview 2. This roadmap reflects changes occurring in standards within the WebAssembly Community Group (CG) and the WASI Subgroup within the W3C. This includes WebAssembly Core, WebAssembly Component Model, WASI (WebAssembly System Interface), and a number of WASI-based interfaces. This is a big update, and we are excited about the new capabilities on the way.
<!--end_excerpt-->

We have pulled together a distilled version of the roadmap, highlighting the ongoing developments and the new features expected to roll out soon. For a more detailed presentation, please check out the [July 2023 WebAssembly Roadmap](https://www.youtube.com/watch?v=Yl_O95zOJbs) overview with Bailey Hayes on the Bytecode Alliance YouTube page. There is a lot of detail in the video, and for best results, please try and watch the video in 4k if possible.

[![July 2023, Bytecode Alliance WebAssembly Roadmap, WASI Preview 2, walkthrough and explanation on Youtube- https://www.youtube.com/watch?v=Yl_O95zOJbs](/articles/img/2023-07-24-roadmap/Bytecode-Alliance-July-2023-WebAssembly-Roadmap-WASI-Preview-2-youtube-link.png)](https://www.youtube.com/watch?v=Yl_O95zOJbs)

<!-- <iframe width="420" height="315" src="https://www.youtube.com/embed/watch?v=Yl_O95zOJbs" frameborder="0" allowfullscreen></iframe>

# had some difficulty getting this to work
-->


## WASI-Preview 2, Three-Tiered Roadmap

To complete WASI-Preview 2 there are three different areas of focus where we are making improvements:

1. Core WebAssembly Specification
2. WebAssembly Components and WebAssembly Interface Types (WIT)
3. WebAssembly System Interface (WASI)

You can see the three themes of improvements highlighted in the roadmap below - click for high resolution version.

[![The components compiled together with wasi-sdk for the parallel compression benchmark.]({{
site.baseurl }}/articles/img/2023-07-24-roadmap/bytecode-alliance-roadmap-part1-wasi-preview-2.png)](/articles/img/2023-07-24-roadmap/bytecode-alliance-roadmap-part1-wasi-preview-2.png)

On the top of the roadmap, you'll see three different time measurements for where we are with each individual workstream.  Everything in `Now` is under active development or has been merged and is undergoing stabilization/first usage. Everything in `Next` is likely to occur before Kubecon in October. Everything in `Later` has a chance of landing this year but is at risk to sliding into next year.

### Core WebAssembly Specification

The core specification outlines the foundation of how to construct WebAssembly modules. Some of the notable work in progress includes:

* The development of [Core Wasm Threads Prototype](https://github.com/WebAssembly/threads) by [Conrad Watt](https://github.com/conrad-watt), [Andreas Rossberg](https://github.com/rossberg), and [Andrew Brown](https://github.com/abrown/) adding a new shared linear memory type and new operations for atomic memory access.
    * Related paper: [“Weakening WebAssembly”](https://github.com/WebAssembly/spec/blob/main/papers/oopsla2019.pdf) by Conrad Watt (University of Cambridge, UK), Andreas Rossberg (Dfinity, Stiftung, Germany) and Jean Pichon-Pharabod (University of Cambridge, UK).
* [WebAssembly Garbage Collection](https://github.com/WebAssembly/gc) being worked on by [Andreas Rossberg](https://github.com/rossberg), [Ivan Mikushin](https://github.com/imikushin), and [Nick Fitzgerald](https://github.com/fitzgen).

This work is on track for completion in the second half of 2023. There will be additional follow on work to implement the early draft of [thread-spawn](https://github.com/abrown/thread-spawn) by [Andrew Brown](https://github.com/abrown/) which will involve changes to projects including LLVM, wasm-tools, and Wasm runtimes. This will be started once we reach stage 0 or 1 consensus within the [WebAssembly Community Group](https://www.w3.org/community/webassembly/) on thread-spawn. 

## WebAssembly Components and WebAssembly Interface Types (WIT)

We know that developers love building libraries because we all want people to develop on top of them - to join a community, contribute features, and improve code quality. The problem is, we all write applications in different languages - creating silos of functionality that we reimplement over and over again. When we can enable interoperability we solve this by targeting a common denominator like C FFI bindings. Even then, we may need to resolve language-specific incompatibilities such as string types not matching; so we design our own application binary interface (ABI) so we can exchange information across language boundaries.

This can be painful and fraught with friction, and so many avoid it altogether. Language interoperability is a barrier to adoption and an opportunity the WebAssembly Component Model is designed to address. The Component Model provides developers with language-agnostic, composable, interoperable, and platform-virtualizable Wasm components that encapsulate Wasm modules.

The Component Model proposal, developed on top of the core specification, includes the WebAssembly Interface Types (WIT) IDL. WIT is the language of high-level types that we use to describe the interfaces of a component. The Component Model adds high-level types with imported and exported interfaces, making components composable and virtualizable. 

What this means simply is that you can create and combine components that were originally written in different programming languages. For example, Rust components, can be combined with components written in JavaScript, C, and Go.

Key work streams that we are on track to complete towards the Component Model and WIT are:
 
* Component Naming and Versioning: has been integrated and allows interfaces to evolve independently.
* Resource and Handle Types: which is the last significant feature to be added to the Component Model.

## WebAssembly System Interface (WASI)

[WASI](https://github.com/WebAssembly/WASI) is built on top of both the Component Model and the core WebAssembly specification. “WASI Preview 2” was defined by the WASI Subgroup of the WebAssembly Community Group. In the second half of this year, we are expecting Dan Gohman to champion a proposal to the Subgroup to officially define Preview 2, if this passes a group review we will adopt this formally as WASI Preview 2. 
Looking at what is coming in Preview 2, for those familiar with WASI Preview 1, interfaces have been adapted to use high-level types defined by the Component Model and are defined with WIT, including WASI IO, Filesystem, Clocks, and Random.

A WIT package is a collection of WIT interfaces and [worlds](https://github.com/WebAssembly/component-model/blob/main/design/mvp/WIT.md#wit-worlds). A world is a complete description of both imports and exports of a component and may be used to represent the execution environment of a component. The WASI Preview 2 will have at least two world definitions that encompass several WASI proposals:

* [CLI world](https://github.com/WebAssembly/wasi-cli) is a proposal for a Command-Line Interface (CLI) environment. It provides APIs commonly available in such environments, such as filesystems and sockets, and also provides command-line facilities.

```c
package wasi:cli

world command {
  import wasi:clocks/wall-clock
  import wasi:clocks/monotonic-clock
  import wasi:clocks/timezone
  import wasi:filesystem/types
  import wasi:sockets/instance-network
  import wasi:sockets/ip-name-lookup
  import wasi:sockets/network
  import wasi:sockets/tcp-create-socket
  import wasi:sockets/tcp
  import wasi:sockets/udp-create-socket
  import wasi:sockets/udp
  import wasi:random/random
  import wasi:random/insecure
  import wasi:random/insecure-seed
  import wasi:poll/poll
  import wasi:io/streams
  import environment
  import preopens
  import exit
  import stdin
  import stdout
  import stderr
  export run
}
```

* [HTTP Proxy world](https://github.com/WebAssembly/wasi-http-proxy) is a proposal for an environment that captures a widely-implementable intersection of hosts that includes HTTP forward and reverse proxies. Components targeting this world may concurrently stream in and out any number of incoming and outgoing HTTP requests.

````c
package wasi:http

// The `wasi:http/proxy` world captures a widely-implementable intersection of
// hosts that includes HTTP forward and reverse proxies. Components targeting
// this world may concurrently stream in and out any number of incoming and
// outgoing HTTP requests.
world proxy {
 // HTTP proxies have access to time and randomness.
  import wasi:clocks/wall-clock
  import wasi:clocks/monotonic-clock
  import wasi:clocks/timezone
  import wasi:random/random

 // Proxies have standard output and error streams which are expected to
 // terminate in a developer-facing console provided by the host.
  import wasi:cli/stdout
  import wasi:cli/stderr

 // This is the default handler to use when user code simply wants to make an
 // HTTP request (e.g., via `fetch()`).
  import outgoing-handler

 // The host delivers incoming HTTP requests to a component by calling the
 // `handle` function of this exported interface. A host may arbitrarily reuse
 // or not reuse component instance when delivering incoming HTTP requests and
 // thus a component must be able to handle 0..N calls to `handle`.
 export incoming-handler
}
````

The above forms the basis for WASI Preview 2’s standardized interfaces. All the interfaces used by the CLI and HTTP-Proxy worlds will need to have moved to at least Phase 3 by the WASI Sub Group before Preview 2 is officially approved by the WASI Subgroup. Please find more information at [WASI Proposals](https://github.com/WebAssembly/WASI/blob/main/Proposals.md).

In order to advance WASI Preview 2’s development to stable, we will need to provide documentation, a complete test suite and framework, and two different host implementations:

* [Wasmtime](https://github.com/bytecodealliance/wasmtime) is a WebAssembly Runtime written in Rust that is designed for server-side applications.
* JavaScript Host Implementation provided by [JCO](https://github.com/bytecodealliance/jco) is ongoing to ensure solid JavaScript host implementation for both Web browsers and server-side JavaScript environments like Node.js.

## Looking Ahead: New Features

There is a huge body of additional work underway that contributes features and functionality to the WebAssembly ecosystem, but does not necessarily block WASI Preview 2. We want to highlight three workstreams that may be finishing near the same timeline:

* Language Tooling and Registries: The roadmap emphasizes the development of tooling to allow different languages to compile into WebAssembly components. The implementation of registries within these languages will simplify the process of building, testing, and running components.
* Bytecode Alliance Dog Food Registry: The roadmap reveals the upcoming launch of a "Dog Food Registry" by the Bytecode Alliance. The registry will first go through a security review to ensure its robustness.
* WebAssembly Interface Proposals: There's a host of proposals for new WASI APIs that can independently move through different phases of adoption and standardization. Some of these APIs are WASI Key-Value and WASI Messaging.

[![July 2023 Bytecode Alliance Roadmap, Additional Features Completing independent of WASI Preview 2.]({{
site.baseurl }}/articles/img/2023-07-24-roadmap/bytecode-alliance-roadmap-part2-additional-features.png)](/articles/img/2023-07-24-roadmap/bytecode-alliance-roadmap-part2-additional-features.png)


### Language Tooling

As the Component Model and WASI arrive, we want to ensure that there is robust support for a variety of programming languages. We have two tools designed for their given language ecosystems that are on track to release at the same time as WASI Preview 2:

* Rust with [Cargo Component](https://github.com/bytecodealliance/cargo-component)
* JavaScript with top-level tool [jco](https://github.com/bytecodealliance/jco) which enables building JavaScript components with [componentize-js](https://github.com/bytecodealliance/componentize-js)

We also see several more language tools emerging to support other ecosystems, like [Joel Dice’s](https://github.com/dicej) [componentize-py](https://github.com/dicej/componentize-py) and golang language bindings. This work stream is led by the [Guest Languages SIG](https://github.com/bytecodealliance/SIG-Guest-Languages) (Special Interest Group).


### Registry

As the core [WebAssembly Registry (warg)](https://warg.io/) design has come together, initial work has begun around a prototype registry. Warg provides a component-oriented index allowing everyone to refer to federated namespaces of Wasm packages without being opinionated about how package content is stored and hosted.


### Modular WASI Interfaces

And possibly the most exciting category of new features on the way - are the core building blocks for cloud-native software; various Interfaces that are being pulled together to deliver common functionality in the form of components

* [Dan Chiarlone](https://github.com/danbugs), [David Justice](https://github.com/devigned), and [Jiaxiao Zhou](https://github.com/Mossaka) are championing [wasi-cloud-core world](https://github.com/WebAssembly/wasi-cloud-core) which provides a list of capabilities common to many applications such as [wasi-keyvalue](https://github.com/WebAssembly/wasi-keyvalue), [wasi-messaging](https://github.com/WebAssembly/wasi-messaging), [wasi-sql](https://github.com/WebAssembly/wasi-sql), and [wasi-blob-store](https://github.com/WebAssembly/wasi-blob-store)
* [Andrew Brown](https://github.com/abrown/) is championing [wasi-nn](https://github.com/WebAssembly/wasi-nn) is a WASI API for performing ML inference. Its name derives from the fact that ML models are also known as neural networks (nn). It will soon be able to avoid retrieving large models (some are gigabytes large!) using the new "named models" feature.

It is incredibly exciting to see what the community can build as the core WebAssembly standards, components, and WASI have been built.


## What’s Next, WASI Preview 3

As we look ahead to what we feel will be the GA release for the WebAssembly Component Model and WASI there are only a few notable but critical features identified for completion:

* Native Asynchronous Features: Native async, with futures and streams, is essential for the component model's seamless function, enabling them to comprehend async behaviors of the interfaces they work with. 

The implementation of the WebAssembly Component Model in WASI Preview 2, relies on the WebAssemly runtime or a singular component to orchestrate callback behavior. API's like the `streams` interface defined by [WASI I/O](https://github.com/WebAssembly/wasi-io/blob/main/wit/streams.wit#L221) are based on a `pollable` type from [WASI Poll](https://github.com/WebAssembly/wasi-poll). The primary goal of WASI Poll is to allow users to use WASI programs to be able to wait for stream read, stream write, stream error, and clock timeout events, on multiple handles. [Pat Hickey](https://github.com/pchickey) gave a series of demos that walkthrough this implementation within Wasmtime for [June's Bytecode Alliance Community Stream](https://www.youtube.com/watch?v=qynKt8b3yOw).

With WASI Preview 3, components will be able to seamlessly pass streaming operations between each other. While this feature won't be realized this year, it's slated for Preview 3 and will be a significant step toward Component Model 1.0.


## Conclusion & Call to Action

In conclusion, the WebAssembly ecosystem will soon have access to never before realized capabilities. With the upcoming updates and additions, developers can look forward to an increasingly modular, virtualizable, and robust environment for building WebAssembly modules and components.

We are excited and humbled to have all the support from our community and all of you coming on this journey with us. We specifically want to call out both documentation and test suites as great places where the community can get involved. To get involved, head along to one of our community calls or reach out to us in one of our open-source repos. 

If you’d like to get involved or attend a Bytecode Alliance meeting, you can find all of our meeting links, agendas, and notes on our Github at [Bytecode Alliance Meetings](https://github.com/bytecodealliance/meetings) repo. All are welcome, and we look forward to your contributions.
