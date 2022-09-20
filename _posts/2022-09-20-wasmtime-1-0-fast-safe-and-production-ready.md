---
title: "Wasmtime Reaches 1.0: Fast, Safe and Production Ready!"
author: "Lin Clark"
github_name: linclark
feature-img: "/articles/img/2022-09-20-wasmtime-1/featured-image.png"
---

As of today, the [Wasmtime WebAssembly runtime](https://github.com/bytecodealliance/wasmtime) is now at 1.0! This means that all of us in the Bytecode Alliance agree that it is fully ready to use in production.

In truth, we could have called Wasmtime production-ready [more than a year ago](https://github.com/bytecodealliance/rfcs/pull/14#issuecomment-915589031). But we didn't want to release just any WebAssembly engine. We wanted to have a super fast and super safe WebAssembly engine. We wanted to feel really confident when we recommend that people choose Wasmtime.

So to make sure it's production ready for all of you, a number of us in the Bytecode Alliance have been running Wasmtime in production ourselves for the past year. And Wasmtime has been doing great in these production environments, providing a stable platform while also giving us security and speed wins.

<img src="/articles/img/2022-09-20-wasmtime-1/prod-timeline.png" alt="A timeline showing when companies went into production, from 2 years ago to 3 months ago. Maintainers at the bottom talk about how they haven't seen any problems, and one says 'Looks like we're ready' as they press the release button." />

Here are some of our experiences with the new, improved Wasmtime:

<ul>
  <li>
    <b>Shopify — 14 months in production</b>
    <p>
      Shopify switched to Wasmtime from another WebAssembly engine in July 2021. With the switch, Shopify saw an <b>average execution performance improvement of ~50%.</b>
    </p>
  </li>

  <li>
    <b>Fastly — 6 months in production</b>
    <p>
      Fastly switched to Wasmtime from another WebAssembly engine in March 2022. Fastly also saw a <b>~50% improvement in execution time</b>. In addition, Fastly saw a <b>72% to 163% increase in requests-per-second</b> it could serve. Fastly has since served <b>trillions of requests</b> using Wasmtime.
    </p>
  </li>

  <li>
    <b>DFINITY — 16 months in production</b>
    <p>
      DFINITY launched its blockchain using Wasmtime in May 2021. Since then, DFINITY has executed over <b>1 quintillion (10^18) instructions for over 150,000 smart contracts</b> without any production issues.
    </p>
  </li>

  <li>
    <b>InfinyOn — 14 months in production</b>
    <p>
      InfinyOn Cloud has been using Wasmtime in production since July 2021. With Wasmtime, InfinyOn has been able to deliver a greater than <b>5x throughput improvement in end-to-end stream processing</b> when compared with Java-based platforms like Kafka.
    </p>
  </li>

  <li>
    <b>Fermyon — 6 months in production</b>
    <p>
      Fermyon's Spin has been using Wasmtime since its release in March 2022. Since then, Fermyon has found tens of thousands of WebAssembly binaries can run in a single Spin instance while keeping startup times under a millisecond.
    </p>
  </li>

  <li>
    <b>Embark — 2 years in production</b>
    <p>
      Embark has been using Wasmtime in their game engine since 2020. Since then, Embark has been impressed with Wasmtime's exceptional stability, safety, and performance, keeping games running at 60 FPS.
    </p>
  </li>

  <li>
    <b>SingleStore — 3 months in production</b>
    <p>
      SingleStoreDB Cloud has been using Wasmtime since June 2022 to bring developers' code to the data, safely and with speed and scale.
    </p>
  </li>

  <li>
    <b>Microsoft — 11 months in preview</b>
    <p>
      Microsoft has had Wasmtime in preview for its WebAssembly System Interface (WASI) node pools in Azure Kubernetes Service since October 2021.
    </p>
  </li>
</ul>

With all of this experience running it in production without issues, we feel confident that we can recommend it to you, too.

So I want to tell you about how we made it super fast and super safe. But first, why would you want to use a WebAssembly runtime in the first place?

## Why use a WebAssembly Runtime?

Webassembly was originally created to make code running in the browser fast. This meant that you could run much more complex applications, like image editing apps or video games, in the browser. So each of the major browsers has its own WebAssembly runtime to run these kinds of applications.

But WebAssembly opens up lots of use cases outside the browser, too. So in these cases, you need to find a standalone WebAssembly runtime like Wasmtime.

Here are a few of the use cases that we've seen people use Wasmtime for.

### Microservices & serverless

A WebAssembly runtime like Wasmtime is a perfect fit for Microservices and Serverless platforms, where you have independent pieces of code that need to scale up and down quickly. That's because WebAssembly has a much lower start-up time than other similar technologies, such as JS isolates, containers, or VMs.

For example, it takes the fastest alternative—a JS isolate—about 5ms to start up. In contrast, it only takes a Wasm instance 5 microseconds to start up. And WebAssembly's lightweight isolation is great for multi-tenant platforms because you can fit so many more workloads on the same machine than you can with VMs, containers or other coarse-grained isolation technologies.

<img src="/articles/img/2022-09-20-wasmtime-1/use-case_serverless.png" alt="Devices connecting to a cloud that holds many instances of a WebAssembly module" />

### 3rd Party Plugin systems

WebAssembly is great for platforms, where you often want to run 3rd party code so you can support many different specific use cases&mdash;for example, through plug-in marketplaces where developers in the platform's ecosystem can share code with users.

But running this opens up a trust issue&mdash;can the platform trust the code written by these ecosystem developers?

With WebAssembly, platforms can run untrusted code but still have some security guarantees. Since WebAssembly is sandboxed-by-default and cannot access any resources you don't explicitly hand to it, the platform isn't put at risk. And the communication between the platform and plug-in is still fast.

<img src="/articles/img/2022-09-20-wasmtime-1/use-case_3rd-party.png" alt="Platform code standing on either side of a sandbox that contains WebAssembly code. The platform code passes data into the WebAssembly code, but the WebAssembly code is restricted from using any of the platform resources." />

### Databases, analytics, & event streaming

For database backed applications, WebAssembly can really speed things up. Database backed applications often waste a lot of time querying a database repeatedly, performing some computation based on the returned data and then issuing more queries to get more data. A way to speed this communication up is to bring the code to the data with User Defined Functions (UDFs). With these, you run the code right in the database, getting rid of network calls between them.

With the help of a WebAssembly runtime, databases can use WebAssembly-based UDFs to co-locate the code and data. This provides fast computation over the data without opening the database itself up to security risks.

And because it's WebAssembly, these databases can support a lot of different languages in their UDFs safely, without the risk of one UDF crashing and taking down the whole database. This makes UDFs much more approachable for users who aren't deeply familiar with a particular database.

<img src="/articles/img/2022-09-20-wasmtime-1/use-case_database.png" alt="On one side, a database making lots of slow calls to code. On the other side, the code running directly in the database" />

### Trusted execution environments

Trusted execution environments (TEEs) are designed for cases where the user can't or doesn't want to trust the lower levels of the system, like the hypervisor, kernel, or other system software. The TEEs provides a secure area on the CPU where the TEE-hosted code runs, isolated from all of this other software.

WebAssembly is great for these use cases because it supports lots of different languages and is CPU-architecture independent. This makes it easier to run a TEE across different hardware platforms.

<img src="/articles/img/2022-09-20-wasmtime-1/use-case_tee.png" alt="A CPU with a hypervisor and OS sitting on top of it, plus another, cordoned off section that contains the TEE with the WebAssembly code." />

### Portable clients

The browser is a good example of a portable client, and many applications can just run in the browser. But sometimes you need a portable client that lives outside of the browser&mdash;whether that's for performance or for a richer user experience.

For these cases, you can create your own portable client using a WebAssembly runtime, like [the BBC did for their iPlayer](https://medium.com/bbc-design-engineering/building-a-webassembly-runtime-for-bbc-iplayer-and-enhanced-audience-experiences-7087455808ef). The WebAssembly runtime takes care of the portability and making sure that guest code can run on different architectures. That means that you can focus on the features that you want your client to provide.

<img src="/articles/img/2022-09-20-wasmtime-1/use-case_portable-client.png" alt="An application window with a WebAssembly logo in it that is going to 3 different devices: a phone, a laptop, and a VR headset" />

So those are some use cases where you might want to use Wasmtime. Now let's talk about how we made sure Wasmtime could perform well for these use cases.

## How we make Wasmtime super-fast

For almost all of these use cases, speed makes a difference. That's why we focus so much on performance.

As [I've talked about before](https://bytecodealliance.org/articles/making-javascript-run-fast-on-webassembly#two-places-a-js-engine-spends-its-time), there are two parts of performance that we think about when we're making optimizations&mdash;instantiation and runtime.

If you want all of the details on how we made both of these fast, you can read [Chris Fallin's blog post about Wasmtime performance](https://bytecodealliance.org/articles/wasmtime-10-performance), but here's a basic breakdown.

### Instantiation

Instantiation is the time it takes to go from new work arriving (like a web request, a plugin invocation, or a database query) to having an instance of the WebAssembly module that is actually ready to run, with all of its memory and other state prepared for it.

This speed is really important for use cases where you're scaling up and down quickly, like some microservice architectures and serverless.

As Chris points out in his post, with some of our recent changes:
> Instantiation time of SpiderMonkey.wasm went from about 2 milliseconds... to 5 microseconds, or 400 times faster. Not bad!

<img src="/articles/img/2022-09-20-wasmtime-1/article-reference-chris.png" alt="A person saying '400 times faster... not bad!'" />

And that's just one example.

We achieved these results mostly by using two different kinds of optimizations: virtual memory tricks and lazy initialization. In both cases, what we're doing is putting off work until it really needs to be done.

With virtual memory tricks, we don't need to create a new memory every time we create a new instance. Instead, we depend on operating system features to share as much memory between instances as we can, and only create a new page of memory when one of those instances needs to change data.

We apply this same kind of thinking to initialization. A module could have lots of functions and state that it declares but won't use. So we put off initialization of things like function tables until the function is actually used. This speeds up start-up, and has the nice benefit of reducing the overall work that needs to be done in cases where functions or other state aren't used.

So we got a lot of speed ups in the instantiation phase just by delaying work until it needed to get done. But we didn't just need to make instantiation fast. We also need to make runtime fast.

### Runtime

Runtime is how fast the code actually runs once it has started up. This is especially important when you have long-running code, like portable clients.

We've been able to improve runtime performance with a variety of changes. Some of the biggest wins have come from changes we've made to our compiler, Cranelift, which takes the WebAssembly code and turns it into machine code.

For example, the [new register allocator](https://cfallin.org/blog/2022/06/09/cranelift-regalloc2/) makes SpiderMonkey.wasm run ~5% faster. And the new backend framework (which chooses the best machine instructions to use for blocks of code) makes SpiderMonkey.wasm run 22% faster than that!

We have some experiments that we're doing here, as well. For example, we've started work on a new mid-end optimization framework. In early prototypes, we're already seeing a 13% speed improvement when we run SpiderMonkey.wasm.

So that's how we drive speed improvements. But what about safety?

## How we make Wasmtime super-safe

Security is a big driver for us in the Bytecode Alliance. We believe that WebAssembly is uniquely positioned to solve some of the biggest emerging security threats, and we're committed to making sure that it does.

We've been pushing for WebAssembly proposals that make it easier for developers to create secure-by-default applications. But none of that matters if the runtime that's running the code isn't itself secure.

That's why we put so much effort into the security of Wasmtime itself.

Nick Fitzgerald wrote a [great article about all the different ways we make sure Wasmtime is secure](https://bytecodealliance.org/articles/security-and-correctness-in-wasmtime), and you should read that for more detail, but here are a few examples:

- **We have secured our supply chain using cargo vet.** We're already using a memory-safe language, which helps us avoid introducing vulnerabilities that attackers could exploit. But that safety doesn't necessarily protect us from malicious code that attackers slip into a dependency. To protect against this, we're use [cargo vet](https://mozilla.github.io/cargo-vet/) to ensure that dependencies are manually reviewed by a trusted auditor.

- **We've put a lot of work into fuzzing.** Fuzzing is a way to find hard-to-reason-through bugs in your code by just throwing a bunch of pseudo-randomly generated input at it. As Nick says, "Our pervasive fuzzing is probably the biggest single contributing factor towards Wasmtime's code quality. We fuzz because writing tests by hand, while necessary, is not enough."

- **We're working on formally verifying security-critical parts of the code.** With formal verification, you can actually prove that a program does what it's supposed to do, just like a proof in math class. This gives us extremely high confidence in the relevant code, and helps us pinpoint exactly where the issue is if we accidentally introduce new bugs.

<img src="/articles/img/2022-09-20-wasmtime-1/article-reference-nick.png" alt="A person shouting 'Fuzz all the things!'" />

So those are some of the ways that we make Wasmtime more secure.

This is something we feel really strongly about&mdash;all WebAssembly runtimes should be following the [best practices that Nick lays out](https://bytecodealliance.org/articles/security-and-correctness-in-wasmtime) and more to make sure they are secure. That's the only way we can have the kind of secure WebAssembly ecosystem we all want.

## What comes after 1.0?

Now that we're at 1.0, we plan to keep a frequent and predictable cycle of stable releases. We'll release a new version of Wasmtime every month.

Each release of Wasmtime will bump the major version number. This allows us to keep Wasmtime's version number in sync with that of the language-specific embeddings. For example, if you use wasmtime-py 7.0, you can be sure that you're using Wasmtime 7.0. You can [learn more about the release process here](https://docs.wasmtime.dev/stability-release.html).

Thank you to all of the contributors who made this possible, and if you want to help build out the future of Wasmtime, [join us on the Zulip chat](https://bytecodealliance.zulipchat.com)!
