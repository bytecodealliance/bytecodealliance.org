---
title: "Announcing Monthly Community Streams"
author: "Bailey Hayes"
github_name: ricochet
---

I am happy to announce that the Bytecode Alliance now hosts a [community stream](https://www.youtube.com/playlist?list=PLdpcq7g42YhZvLP8jjqaAvFc2DYqyM1LP) the last Tuesday of every month.

## Our First Community Stream

It was a huge pleasure to host our first ever Bytecode Alliance Community stream for the month of January. Thanks to all who joined - hope you found it useful! If you weren’t able to make this session, view the recording on our [@bytecodealliance YouTube channel](https://www.youtube.com/watch?v=9pLa7PUhPYA). Details about the stream, including agenda and slides, can be found in the [bytecodealliance/meetings](https://github.com/bytecodealliance/meetings/tree/main/community) repo. We’ll continue the discussion on Zulip in [community-stream](https://bytecodealliance.zulipchat.com/#narrow/stream/368134-community-stream).

Every last Tuesday of the month we’ll hold this virtual meetup to hear updates from all of the projects across our community. We also want to use this session to highlight recognized contributors and, hopefully, we’ll be able to run live demos! If you want to update the community, or give a demo, [get in touch](#contact)!

## Technical Steering Committee Update

If you're not yet familiar with the Bytecode Alliance, welcome! Our mission is to build runtime environments and language toolchains where security, efficiency, portability, and modularity all coexist. We do this by implementing standards such as [WebAssembly](https://webassembly.org/), [WASI](https://github.com/WebAssembly/wasi), and the [component model](https://github.com/WebAssembly/component-model) with an eye towards fine-grained sandboxing and capabilities-based security.

The Technical Standards Committee (TSC) exists to provide technical governance for Bytecode Alliance projects. Our Bytecode Alliance recognized contributors nominated the following members to the TSC:

* [Till Schneidereit](https://github.com/tschneidereit) is our new Director at-large, responsible for representing the interests of the community and recognized contributors directly to the board.
* Our TSC Chair - [Nick Fitzgerald](https://github.com/fitzgen) - whom most of you know well from his work on Cranelift and Wasmtime.
* I, [Bailey Hayes](https://github.com/ricochet), am honored to be voted into the role of TSC Director, as voted by the current group of TSC members. My role is similar to Till's as a "director" and I am responsible for representing the TSC on the board.

Thanks, of course, to our outgoing proto-TSC members [Xin Wang](https://github.com/xwang98) and [Matt Butcher](https://github.com/technosophos).

## Project Updates

We hope to hear from a host of new and diverse voices from our community! We encourage you to get in touch and join the discussion. In this month’s session, we heard from technical leaders from across Bytecode Alliance projects.

* [Xin Wang](https://github.com/xwang98), a technical lead within the [Wamr](https://github.com/bytecodealliance/wasm-micro-runtime) (WebAssembly Micro Runtime) project shared the most recent  accomplishments and provided a roadmap for 2023.
* [Nick Fitzgerald](https://github.com/fitzgen) covered the recently released [Wasmtime 5.0](https://github.com/bytecodealliance/wasmtime/blob/main/RELEASES.md#500), which includes `wasmtime::component::bingen!` macro.
* We then heard from [Dan Gohman](https://github.com/sunfishcode) on the [WASI](https://github.com/WebAssembly/wasi) side - with a very exciting update on WASI preview 2.
* [Luke Wagner](https://github.com/lukewagner) gave an implementation status update on the [component model](https://github.com/WebAssembly/component-model), particularly around new tool sets designed to target and link components, and high level tooling codecs to improve the developer experience. I plug Luke's CNCF Wasm Day keynote everywhere, so why not here too? Checkout [The Path to Components](https://www.youtube.com/watch?v=phodPLY8zNE) for a deeper dive into the component model.

## <a name="contact"></a>How to Get in Touch

The best way to provide feedback or add items to the agenda is to post in the [community-stream](https://bytecodealliance.zulipchat.com/#narrow/stream/368134-community-stream) channel on Zulip or create a PR to the agenda at [bytecodealliance/meetings/community](https://github.com/bytecodealliance/meetings/blob/main/community).

## Next Stream

At **6PM PST** today (February 28th) we'll host our next community stream. We will continue this alternating pattern every month to accommodate as many timezones as we can.

Until next time!

Bailey

