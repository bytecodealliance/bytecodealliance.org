---
title: "Plumber’s Summit Day 2: Async, DevEx, and the road ahead"
author: "Eric Gregory"
date: "2024-02-05"
github_name: "ericgregory"
excerpt_separator: <!--end_excerpt-->
---
Last week, the Bytecode Alliance Plumber’s Summit gathered in Raleigh, NC to map the road ahead for the WebAssembly ecosystem.  

You can read a [summary of the summit’s first day](https://bytecodealliance.org/articles/plumbers-summit-day-1) on the Bytecode Alliance blog or watch the [full recording](https://www.youtube.com/watch?v=eZF2MLMgXhk) on YouTube. While much of the second day was conducted in breakout sessions, some consistent themes ran through many of those conversations, including the implementation of **async** and **developer experience**. 
<!--end_excerpt-->

A recording of the Day 2 livestream is [available on YouTube](https://www.youtube.com/watch?v=HGspgXNFisc); the summaries below include timestamps for those portions of the recording.  

<iframe width="560" height="315" src="https://www.youtube-nocookie.com/embed/HGspgXNFisc?si=SHdhA2cWlLs_XD2j" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>

## Async and WASI 0.3.0

Luke Wagner of Fastly delivered ([26:00](https://youtu.be/HGspgXNFisc?t=1560)) a look at his sketch for async implementation in WASI 0.3.0.&mdash;with an eye toward bringing users simple, composable HTTP interfaces with concurrency.  

The presentation provided a high-level design summary that delved into lifting and lowering async, and how those would come into play under a variety of circumstances in which two components are communicating with one another:  

* Both components are async
* Sync calling async
* Async calling sync

Joel Dice of Fermyon demonstrated ([1:11:00](https://youtu.be/HGspgXNFisc?t=4260)) a prototype of the first milestone with [`isyswasfa`](https://github.com/dicej/isyswasfa) (I sync, you sync, we all sync for async), which he described as providing “a ‘polyfill’ that devs can play with today while they’re waiting for Preview 3 and real async.” The project aims to make it easier for developers to begin implementing async (and minimize changes needed later) while also providing implementation feedback for the WASI 0.3.0 design process.  

The demo is [available on GitHub](https://github.com/dicej/isyswasfa) and shows how a component written in idiomatic Rust can await a WASI 0.2.0 monotonic clock poll. 

## Developer experience

Two morning sessions focused on different aspects of developer experience.  

First, Lann Martin of Fermyon led a discussion ([1:44:45](https://youtu.be/HGspgXNFisc?t=6285)) on the current experience of working with WIT packages, and how it may evolve in the future.  

Work is underway on a tooling to push WIT packages to a Warg registry as part of the cargo component project. The group agreed that from a broader perspective, the problem of registry tooling is downstream of a larger question: what is the single source of truth for WIT packages? From this conversation emerged a consensus on creating binary artifacts from snapshots of WIT entity trees and using that as the primary distribution mechanism across repositories.  

A related discussion ([2:07:09](https://youtu.be/HGspgXNFisc?t=7629)) led by Fermyon’s Ryan Levick dealt with developer experience around component tooling. There was general agreement that existing component tooling needs better error messaging and documentation. Dan Gohman of Mozilla noted that the process of building out tutorial documentation often drives development by surfacing feature and DevEx gaps.  

During an afternoon breakout session, Yoshua Wuyts of Microsoft explained his project [`wasm-http-tools`](https://github.com/yoshuawuyts/wasm-http-tools), which enables components to communicate with one another over HTTP and features an in-progress bidirectional binding between WIT and OpenAPI. The group held preliminary conversations on how and whether the project might become a Bytecode Alliance project, and potential advantages in expanding the project scope to encompass other bidirectional bindings (e.g., WIT to RPC, WIT to Smithy), perhaps under a name like `wasi-api-tools`.

## The road ahead

Additional breakout sessions brought together smaller groups for focused discussions on topics including:

* Documentation
* Bounding WASI
* `shared-everything` linking in guest toolchains
* Approaches to the `wasi-nn` and `wasi-sql` proposals
* A potential `wasi-TLS/SSL` proposal
* Diving deeper into async
* Debugging Wasmtime
* Diving deeper into host plugins

Among the many important conclusions reached on Day 2, the group decided to adopt a “tick tock” development pattern wherein feature development cycles (like the road to WASI 0.2.1) will be followed by a stabilization cycle, marking a strong commitment to ongoing stability and improvement to developer experience.  

As the WebAssembly ecosystem enters a new era of enhanced portability and interoperability after WASI 0.2.0, the Bytecode Alliance is dedicated to making it as easy as possible for more developers to get involved. If you have questions or ideas, [join our Zulip chat](https://bytecodealliance.zulipchat.com/) to be part of the conversation.
