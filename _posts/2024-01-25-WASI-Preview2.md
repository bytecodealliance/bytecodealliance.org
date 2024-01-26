---
title: WASI Preview 2 Launched
author: "Dan Gohman"
github_name: sunfishcode
---
> Original post from https://blog.sunfishcode.online/wasi-preview2/

The WASI Subgroup has just voted to launch WASI Preview 2! This blog post
is a brief look at the present, past, and future of WASI.

## The present

The Subgroup voted to launch Preview 2!

This is a major milestone! We made it! At the same time, the journey is
only just beginning. But let's talk this moment to step back and look at
what this means.

Most immediately, what this means is that the WASI Subgroup officially
says that the Preview 2 APIs are stable. There is still a lot more
to do, in writing more documentation, more tests, more toolchains, more
implementations, and there are a lot more features that we all want to add.
This vote today is a milestone along the way, rather than a destination in
itself.

It also means that WASI is now officially based on the Wasm [component model],
which makes it cross-language and virtualizable. Figuring out what a
component model even is, designing it, implementing it, and building APIs
using it has been a huge effort with involving many people, and it's now
officially in WASI. Yay!

Preview 2 includes two *worlds*:

  - *wasi-cli*, the "command-line interface" world, which roughly
    corresponds to POSIX. Files, sockets, clocks, random numbers, etc.

  - *wasi-http*, an HTTP proxy world, organized around requests
    and responses.

There are more worlds in development, but for now, the important thing is
that we do have multiple worlds included. This means wasi-cli world isn't
the only world, or even the primary world. It's just one world, among
multiple.

One things I'm looking forward to that's enabled by having multiple worlds is
[Typed Main] (some details in that presentation are out of date by now, but
the big ideas still make sense), because we can have new worlds with new
entrypoints, with new signatures. It's also a part of how we can grow WASI to
fit into new non-traditional computing environments. And this is just the
beginning.

## Looking back

All the way back since the beginning of WebAssembly, people have been talking
about using it outside of browsers. Node.js had famously made JavaScript popular
on servers and more, and if it made sense for JavaScript, it was pretty natural to
imagine WebAssembly doing similar things. But beyond the basic outline, there
were a lot of questions, and a lot of ideas.

 - How can we build a coherent ecosystem without fragmentation? And how do
   we prevent an NPM-like situation with one company gaining control over the
   ecosystem?

 - To some people, POSIX was the obvious place to start on a non-JS-based API.
   POSIX is a C API, so how do we ensure that our C *ABI* is future-proof?
   C ABIs tend to get baked in if one is not super careful, and bugs can
   [take decades to fix].

 - As much as POSIX was the obvious starting point for a lot of people, it was
   just as much an obvious non-starter for a lot of other people. WASI being based
   on POSIX made it *very* biased toward C, with raw pointers everywhere, implied
   data structures, and so on. And would there need to be a `fork` function, with
   all its ecosystem-wide implications? Building an ecosystem with C ABIs as its
   primary connective tissue is very undesirable from a security perspective. Also,
   what's the plan when Wasm GC arrives?

 - Should we always export linear memory, to ensure that we can pass pointers
   around? But if we do that, we lose the benefit of the sandboxing that Wasm is
   otherwise doing between modules&mdash;if you can corrupt a C program's memory,
   its game is over. But if we don't export linear memory, how else do we pass
   around complex data structures?

Looking at use cases, there are the "port existing code" use cases, and the "do things
that other systems can already do, but do them *IN WASM*" use cases, and these are
important. But there are also new use cases that we can imagine Wasm can do, and we
wanted to be sure we didn't define the system in terms of compatibility and exclude
these new use cases. One of the big themes that came up repeatedly was *virtualization*.
All I/O in Wasm goes through its imports and exports, so we can completely virtualize a
Wasm module's view of the outside just by controlling what the imports and exports are
linked to.

And, Wasm has a trusted stack, which is what makes it possible to call from
Wasm into JS and back within JS engines. In theory we should be able to use this
property to enable calling from Wasm into some other mutually untrusted Wasm.

Also, early on, some security-minded folks told us that we should look at something
called "capabilities", which they said were really great. And avoiding global state
sounded like a good direction to go in. CloudABI combined capability-based security and
some impressive work to simplify the Unix platform down to a relatively small set of
carefully-designed primitives, which made it especially appealing. Consequently, much
of WASI Preview 1 was closely derived from CloudABI.

That helped get us started, and helps us build systems that people could write
code with and get things working, but we still had all these open questions, and
big ideas to figure out.

### Component Model enters the chat

So while Preview 1 was out in the world, people were starting to think big
thoughts about how to answer all these big questions and how to fit all the
big ideas into a coherent design. There were these early proposals called
"interface types" and "module linking", which seemed to be pointing toward
something, but had been through numerous iterations and hadn't quite settled
in yet.

When I first heard about the idea for a component model, which would
subsume interface types and module linking, I didn't know what a "component"
meant. My knowledge of COM was "that's some Windows thing, right?". And I knew
only slightly more about CORBA. Mostly, I knew just barely enough to react
"surely we don't want to do *that*". But as I got into it, I learned that
the Wasm component model was a chance to both learn from those existing systems
which had solved many of the problems we needed to solve, and also to learn
from those systems and do some things differently.

We didn't want to force everyone to think about distributed computing just
to link libraries together. And we didn't want to lose the advantage of Wasm
sandboxing each module independently. And when we looked at where that leaves
us, the common theme that remained was *composition*. It's about building
things that can be easily put together to make larger things.

And then from there, composition ties together an entire family of ideas.
Even [Mark Miller's PhD thesis] about capability-based security is literally
titled "Robust Composition". It's right there. It's what this is all about.
How do we put together parts to make a whole, without all kinds of complexities
creeping in?

 - Cross-language interop is needed to compose components written in
   different languages.

 - Component isolation supports composition without the fear of components
   having unexpected conflicts.

 - No global namespace at runtime, so that composed component don't
   collide in or have differing requirements of the namespace.

 - Any interface can be virtualized, which is to say, composed with
   any implementation of that interface.

 - The output of linking two components is a component, so composition
   can happen incrementally.

 - Capabilities are a way to compose two components together, in which
   they share some parts of themselves with each other and not others.

There's a lot more to these topics, but this is hopefully enough to paint
the picture that there are some themes that all fit well with each other,
within the conceptual framework of composition.

And so, Preview 2 represents not just a new API, but a new approach to
APIs that gets us out of worrying about C ABI fragility, or C pointer hazards,
and that has reasonable paths forward for supporting many different
programming languages without hard fragmentation. It even allows us to not
worry so much about getting Preview 2 itself perfectly right for all time,
because we know we can virtualize Preview 2 itself in terms of future APIs.

This is why the Subgroup voting to launch Preview 2 is such a big deal.

## Looking ahead

Ok, that's a high-level view of how we got here. What's next?

In terms of standards, there are two activities that people are already
looking forward to. With Preview 2 finalized, it'll be time to start planning
for things we want to add in a Preview 2.1 soon after it. That'll be another
milestone: the first update to Preview 2, which will establish how to do updates,
and set up the rhythm for doing incremental updates. Preview 2 is small still;
we had to scope down a number of features that people really wanted, so we're
looking forward to doing many updates in 2.1 and beyond.

At the same time, work towards Preview 3 will be getting underway. The
major banner of Preview 3 is *async*, and adding the `future` and `stream` types
to Wit. And here again, the theme is *composability*. It's one thing to do
async, it's another to do *composable* async, where two components that are
async can be composed together without either event loop having to be nested
inside the other. Designing an async system flexible enough for Rust, C#,
JavaScript, Go, and many others, which all have their own perspectives on async,
will take some time, so while the design work is starting now, Preview 3
is expected to be at least a year away.
 
And when we do get there, the transition from Preview 2 to Preview 3 should be much smoother
than Preview 1 to Preview 2. The component model's virtualizability means it
should be easier to polyfill Preview 2 in terms of Preview 3. And, it should be
easier for engines to support both Preview 2 and Preview 3 at the same time if
they wish to, because Preview 2 will essentially use a subset of Preview 3's
language features.

## Wrapping it up

Preview 2 is a major milestone that many people have contributed to, and
it's now launched! It's an API, but it also represents a new way to define
APIs for Wasm.

[take decades to fix]: https://en.wikipedia.org/wiki/Year_2038_problem
[component model]: https://github.com/WebAssembly/component-model/
[Mark Miller's PhD thesis]: http://www.erights.org/talks/thesis/markm-thesis.pdf
[Typed Main]: https://sunfishcode.github.io/typed-main-wasi-presentation/chapter_1.html
