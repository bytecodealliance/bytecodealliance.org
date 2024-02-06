---
title: "Plumber’s Summit Day 1: Wasmtime and plugins, WASI 0.2.1, OCI artifacts and registry roadmap"
author: "Eric Gregory"
date: "2024-02-04"
github_name: "ericgregory"
excerpt_separator: <!--end_excerpt-->
---

The Bytecode Alliance Plumber’s Summit gathered in Raleigh, NC on January 31, 2024 to celebrate the release of WASI 0.2 and collaborate on the next steps forward for the WebAssembly ecosystem.  

The first day of the two-day summit focused on topics of general interest, while the second day adopted an “unconference” structure with more narrowly focused breakout sessions.  
<!--end_excerpt-->

Member Director Ralph Squillace opened the day with a celebration of the Bytecode Alliance’s milestone release of WASI 0.2, and Technical Steering Committee Director Bailey Hayes set the tone with a guiding theme of “Building better together.”  

Day 1 topics included:  

* Wasmtime: Native plugins and core Wasm proposals
* WASI 0.2.1 planning and proposals
* OCI artifacts and a registry roadmap

You can [watch the recording in full on YouTube](https://www.youtube.com/watch?v=eZF2MLMgXhk) or read the summaries below&mdash;each summary includes a timestamp to find the discussion in the recording.  

<iframe width="560" height="315" src="https://www.youtube-nocookie.com/embed/eZF2MLMgXhk?si=HtDgebmnPfjnd89i" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>

## Wasmtime: Native plugins and core Wasm proposals

Till Schneidereit and Alex Chrichton of Fermyon led a discussion ([43:00](https://www.youtube.com/watch?v=eZF2MLMgXhk&t=2580s)) on potential approaches to implementing Wasmtime native plugins (also known as host components). Plugin functionality could deliver benefits including:  

* A smaller binary for Wasmtime
* Minimized trusted compute base
* Easier deployments
* Enablement of partial updates
* Out-of-tree development of APIs
* Easier experimentation with APIs

Till noted that for many users “in large-scale environments where you want to be able to specialize individual nodes to run specific content, you don’t want to have your own distribution of Wasmtime for each of these nodes.” 

Alex and Till outlined three potential approaches to implementation:

1. Support dynamic libraries
2. Support an RPC mechanism
3. Support self-hosted APIs

In order to frame the decision, the group discussed whether plugins should be implemented as components or core Wasm modules, given that it would be possible to support both implementations with dylibs.  

Luke Wagner of Fastly noted that the SDK for developing a plugin would be dramatically different for components and core Wasm, since core Wasm APIs are lower-level and memory management is more of a concern.  

There was general agreement that RPC and dylibs need not be an either/or proposition&mdash;Alex suggested that at minimum, dynamic libraries could serve as a least common denominator, while selectively lifting certain functionalities up to RPC.  

Representatives from multiple organizations expressed that an RPC mechanism is a compelling approach, enabling greater sandboxing of plugins. David Justice from Microsoft added that having the ability to use different languages to build these plugins would “open up our world to so many developers.”  

Bailey Hayes added that at Cosmonic and wasmCloud, “We started with dylibs and are working on an RPC implementation.”  

Future discussions will detail how the RPC implementation, known as **wRPC**, will integrate into `wasm-tools`. The session concluded with the sentiment that the group should work on both the dylib and RPC approaches, taking one as a baseline but pursuing both at a synchronized pace, with further details to be specified in an RFC.  

In a later session on inclusion of core Wasm proposals in wasmtime ([6:40:30](https://youtu.be/eZF2MLMgXhk?t=24030)), Luke Wagner and Nick Fitzgerald of Fastly walked through the implementation status for several core Wasm proposals in Wasmtime:  

* [`gc`](https://github.com/webAssembly/gc) - Adds user-defined, garbage-collected types to Wasm
* [`exception-handling`](https://github.com/webAssembly/exception-handling) - Adds throw/catch-style unwinding to Wasm
* [`shared-everything-threads`](https://github.com/webAssembly/shared-everything-threads) - Adds fine-grained sharing of Wasm state
* [`stack-switching`](https://github.com/webAssembly/stack-switching) - Adds fibers to core Wasm

Exception handling requires an implementation owner to get it incorporated into Wasmtime. Taken together, these proposals will help to enable support for more languages across the ecosystem.  

## WASI 0.2.1 planning and WASI proposals

Discussion of plans for WASI 0.2.1 ([1:49:15](https://www.youtube.com/watch?v=eZF2MLMgXhk&t=6555s)) touched on potential feature inclusions&mdash;timezone functionality for `wasi:clocks`, for example&mdash;but the bulk of conversation centered around the concrete implementation of patch releases:  

* What is the scope of additions for 0.2.x updates?
* How will minor version updates be experienced by users?
* How can the 0.2.1 release be as smooth as possible?

The group agreed that 0.2.x will strictly make additions to the API, and that additions to parameters on functions are not supported.  

Till Schneidereit stated that an improved developer experience around errors is needed&mdash;currently, if a user attempts to run a component with the “wrong” interface, they are simply told that the “expected function found nothing.” Instead, it would be helpful for users to receive error messaging that is higher-level and easier to reason about: for example, “You’re targeting version X of this interface, but version Y is the supported version.”  

The group agreed to target April 2024 for 0.2.1, with champions for specific features to drive those features’ addition to the release. 

In an afternoon session on WASI interface proposals ([5:42:22](https://youtu.be/eZF2MLMgXhk?t=20542)), Taylor Thomas of Cosmonic and Jiaxiao Zhou Mossaka of Microsoft discussed the status of the [`wasi-cloud-core`](https://github.com/webAssembly/wasi-cloud-core) world and included interface worlds such as [`wasi-http`](https://github.com/WebAssembly/wasi-http), [`wasi-keyvalue`](https://github.com/WebAssembly/wasi-keyvalue), and [`wasi-blobstore`](https://github.com/WebAssembly/wasi-blobstore). 

The `wasi-cloud-core` world aims to create a set of simple, portable interfaces that are used by a majority of all types of applications running in clouds&mdash;while more specifically targeted interfaces can be created, these represent the “lowest common denominator” cloud interfaces.

Taylor shared that [`wasi-distributed-lock-service`](https://github.com/WebAssembly/wasi-distributed-lock-service) has been deemed out of scope for the `cloud-core world` and removed. The [`wasi-runtime-config`](https://github.com/WebAssembly/wasi-runtime-config) and [`wasi-keyvalue`](https://github.com/WebAssembly/wasi-keyvalue) proposals have recently completed interface first drafts and are ready for implementation; `wasi-blobstore` requires some refinement and [`wasi-sql`](https://github.com/WebAssembly/wasi-sql) will need significant work.

An important point of emphasis was that each WIT package will have its own proposal and versioning requirements and will be voted upon independently. Taylor expressed a hope that work can progress along the following timeline:

* **2024 Q1** - Lock in basic interface definitions (other than `wasi-sql`) with at least one POC implementation
* **2024 Q2** - Get implementations in place and interfaces to Phase 2
* **2024 Q3** - Phase 3 and further stabilization

Bailey Hayes noted that process updates will be necessary to reflect independent voting on WIT packages.

## OCI artifacts and registry roadmap

Taylor Thomas of Cosmonic introduced the group to the initiative to use the OCI standard to distribute components ([5:11:00](https://youtu.be/eZF2MLMgXhk?t=18662)). Goals for this effort include:  

* Support for a common distribution interface
* The ability to use a single OCI-compliant manifest across runtimes
* Ease of adoption for container users

While the OCI representation will be single-layer at first, it is being designed to support an “exploded,” multi-layer view in which constituent components are organized by layer, facilitating familiar registry operation patterns and composable by either Wasm or container runtimes.  

Taylor defined the next steps as...  

* Working through stakeholder questions
* Producing an example manifest with an accompanying spec
* Returning a draft manifest to the main OCI group in 2 months or less
* Submitting for inclusion in a Wasm repo&mdash;likely the Component Model

Next was a registry update and roadmap from Robin Brown of SingleStore and Lann Martin of Fermyon ([5:22:52](https://youtu.be/eZF2MLMgXhk?t=19372)). Robin and Lann walked through Phase 1 and Phase 2 registry goals.  

Phase 1 emphasizes [`warg-loader`](https://github.com/lann/warg-loader) and work on OCI artifacts. This phase aims to...

* Support existing registries like OCI as quickly as possible
* Make it possible to publish and pull components without new infrastructure
* Focus on unifying the package consumer experience and integrating it into dev tools

All of this is intended to bootstrap adoption of the packaging system into ecosystem tooling.  

Phase 2 will focus on supply chain security and [WebAssembly Registry (Warg)](https://github.com/lann/warg-loader), continuing work on the `warg` protocol and integration with `warg-loader`, emphasizing:

* Core registry functionality
* Transparency design

The importance of component discoverability was a major topic of discussion. Discoverability was widely affirmed as a goal, but it was noted that fundamentals need to be in place to create a superior developer experience, and that this is an area where investing more resources can accelerate progress significantly.

## Conclusion

To conclude the day, Luke Wagner talked through “Luke’s Backlog”&mdash;a collection of features and projects for possible future implementation. Luke presented these as “a menu of cool stuff to think about over the next few years”&mdash;items that might happen within months, within years, or on an indefinite timescale.  

On the menu were several features for discussion on Day 2 of the Plumber’s Summit, including async, WIT package development, and much more. Check out [our summary of Day 2](https://bytecodealliance.org/articles/plumbers-day-2) to learn more about those conversations or watch the [Day 2 stream](https://www.youtube.com/watch?v=HGspgXNFisc) on YouTube.




