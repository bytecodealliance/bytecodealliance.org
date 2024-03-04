---
title: "February 2024 Community Stream"
author: "Eric Gregory"
date: "2024-03-04"
github_name: "ericgregory"
excerpt_separator: <!--end_excerpt-->
---
On February's community stream, Bytecode Alliance Technical Steering Committee Director Bailey Hayes and Consulting Executive Director David Bryant provided updates on individual projects, SIGs, and direction for the ecosystem. 
<!--end_excerpt-->

In addition to this summary, you can [view the recording](https://www.youtube.com/watch?v=UEtkb3bP7e4) on the Bytecode Alliance YouTube channel. Timestamps are included below for each of the major topics. 

<iframe width="560" height="315" src="https://www.youtube.com/embed/UEtkb3bP7e4?si=ezW0Hs4HgUaDfqRm" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>

## Plumber's Summit in review ([0:43](https://youtu.be/UEtkb3bP7e4?t=43))

Last month, the Bytecode Alliance Plumber's Summit gathered in Raleigh, North Carolina. Bailey and David reviewed the meeting's major highlights and outcomes (as well as the excellence of Food Halls and Carolina Reaper peppers). The Summit focused on the path ahead after the release of WASI P2, covering everything from the long-term roadmap, major themes for WASI P3, and the cadence for point releases. 

All Plumber's Summit sessions were streamed live so contributors around the world could take part, and the [stream recording is available to watch any time on YouTube](https://www.youtube.com/watch?v=eZF2MLMgXhk). Summary blogs for both [Day 1](https://bytecodealliance.org/articles/plumbers-day-1) and [Day 2](https://bytecodealliance.org/articles/plumbers-day-2) of the Summit are also available. 

While no specific date has been set for the next Plumber's Summit, there is preliminary discussion of meeting again in October 2024.

## Project updates

Bailey provided status reports on projects across the Bytecode Alliance ecosystem, including guest languages, two new Special Interest Groups (SIGs), WASI P2, and Wasmtime 18.

### SIG Guest Languages

This month brought updates on the ongoing "Gopherization" of tooling for Go developers and early steps for a C#/.NET workstream.

#### Go Working Group ([10:30](https://youtu.be/UEtkb3bP7e4?t=630))

The Go Working Group's Randy Reddig and Damian Gryski (both of Fastly) reported a "Hello Watson moment" for wit-bindgen-go, as idiomatic Go bindgen and WASI P2 syscalls converge to create a more "Gopherized" experience for Go developers. 

Randy and Damian have been working towards creating an idiomatic Go bindgen, and have reached a milestone in making this work end-to-end against a `wasi:cli/command`. This process takes WASI types and generates idiomatic Go bindings from those types, and while the work isn't done, it's a big step. Once the new bindgen is complete and integrated, `cgo` will no longer be required as part of the Go-Wasm toolchain (which should make many Gophers happy), and it will be possible to embed the bindgen in the upstream Go standard library. 

Meanwhile, WASI P2 syscalls are almost all ported and complete (not including `wasi-http`). This will make it easier to write normal Go code and simply compile to WASI for a smooth Go development experience. 

Many people are contributing to the Go effort, and the clear-eyes-full-hearts objective is to get full Component Model and WASI P2 support in upstream Go 1.23 at the end of August. "Aggressive goals, honest status," Bailey said. "There are a couple of different proposals that have to land to make this work well inside of Big Go, but once those work, I think a lot of the other paths are more straightforward."

#### C# / .NET Working Group ([15:10](https://youtu.be/UEtkb3bP7e4?t=910))

The C#/.NET workstream is at an earlier stage and actively looking for extra hands. Current efforts are focused on bootstrapping two tools:

* **`cm-dotnet`**: a library with all the common types used in binding generation. Most users won't interact directly with this library&mdash;instead, they'll use...
* **`componentize-dotnet`**: a developer tool analogous to [`componentize-py`](https://github.com/bytecodealliance/componentize-py). 

If you're interested in contributing, [reach out on Zulip](https://bytecodealliance.zulipchat.com/).

### New Special Interest Groups ([16:44](https://youtu.be/UEtkb3bP7e4?t=1004))

Speaking of getting involved, several Special Interest Groups are being created right now! 

* **SIG Documentation** focuses on docs across the ecosystem as well as developer onboarding and experience. Kate Goldenring has done a great deal of work to get this SIG off the ground, and one of the group's first tasks has been to document the process for creating a SIG within the Bytecode Alliance.
* **SIG Embedded** is forming now, providing a space for discussing and tackling the challenges specific to leveraging the Wasm ecosystem in embedded environments.

If you'd like to learn more about these new SIGs, join the threads on the [Zulip](https://bytecodealliance.zulipchat.com/) and check out the [Bytecode Alliance meetings GitHub repo](https://github.com/bytecodealliance/meetings/tree/main). 

### WASI P2 ([24:15](https://youtu.be/UEtkb3bP7e4?t=1455))

Coming out of the Plumber's Summit, much discussion around WASI P2 has centered around how to approach point releases. Contributors have settled on a "train" model with a to-be-determined but short cadence of point releases. In order to establish the process for these releases, WASI 0.2.1 will be very small, including only a `timezone` addition to `wasi-clocks`.

### Wasmtime 18 ([31:36](https://youtu.be/UEtkb3bP7e4?t=1896))

[Wasmtime](https://github.com/bytecodealliance/wasmtime) 18 was released on February 20th. Notably, support for the old `wasi-common` crate and the original implementation of WASI P1 is being deprecated. According to the release notes:

> Users should migrate to the wasmtime_wasi::preview2 implementation, which supports both WASIp1 and WASIp2, as in the next release the wasi-common-based reexports of wasmtime-wasi will be deleted.

### Next steps

As contributors shape WASI P2 point releases, work on WASI P3 proceeds in parallel, with a particular focus on async operations. Joel Dice's [isyswasfa](https://github.com/dicej/isyswasfa) (*I sync, you sync, we all sync for async*) project bridges these two streams with an experimental implementation of async using WASI P2.

David observed:

> We're going to see evolution of 0.2; we're going to see the new work that's going to be demonstrated on top of 0.2.X that helps us frame what we're going to do 0.3; and then other people are going to be thinking about 1.0.

### How to get in touch

To learn more about any of these projects and be part of the conversation, join us on the [Bytecode Alliance Zulip server](https://bytecodealliance.zulipchat.com/)! You can find more information on regular meetings (and submit a PR) on the [Bytecode Alliance meetings GitHub repo](https://github.com/bytecodealliance/meetings/tree/main). 