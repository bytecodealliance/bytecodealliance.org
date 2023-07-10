---
title: "Welcoming Javy: A new hosted project"
author: "Saúl Cabrera"
github_name: saulecabrera
excerpt_separator: <!--end_excerpt-->
---

We're happy to announce the inclusion of
[Javy](https://github.com/bytecodealliance/javy/tree/main) as a hosted project
under the Bytecode Alliance.  This post will delve into what Javy is, the
motivation behind its adoption, and the process that led to its integration into
the Bytecode Alliance.
<!--end_excerpt-->

## Javy

Javy is a JavaScript-to-WebAssembly toolchain originally developed by Shopify to
bring JavaScript support to [Shopify
Functions](https://shopify.dev/docs/apps/functions/language-support/javascript).
It is based on the QuickJS engine and generates compact and efficient
WebAssembly modules. Shopify has
[published](https://shopify.engineering/javascript-in-webassembly-for-shopify-functions)
a detailed technical article covering the original motivation and the technical
details of Javy.

## The motivation and process behind the adoption

While Javy was initially designed for a specific use-case, it eventually found
its way into multiple companies operating in the WebAssembly space as a means to
run JavaScript on WebAssembly. This adoption prompted the creators of
Javy to rethink its governance model, shifting towards an open, community-driven
model that ensures a healthy environment for the project's growth and
development.

The process to include Javy as a hosted project involved:

* A discussion between the [Bytecode Alliance's Technical Steering Committee
  (TSC)](https://github.com/bytecodealliance/governance/blob/main/TSC/charter.md#bytecode-alliance-technical-steering-committee-charter)
  and the team behind Javy, to discuss the process, requirements and
  expectations of granting Javy the status of a hosted project. 
* A review of  [the requirements for hosted
  projects](https://github.com/bytecodealliance/governance/blob/main/TSC/charter.md#requirements-for-hosted-projects),
  which involved minor code changes around naming and licensing.
* Lastly, the transfer of the repository from the Shopify GitHub organization to
  the Bytecode Alliance GitHub organization.

## Getting started 

The simplest way to try Javy is to invoke it through `npx javy-cli`, assuming
that `npm` is installed in your system.

Upon successful execution of the command, you can create a JavaScript source and compile it to WebAssembly.

Consider the following simple program, stored in a file named index.js:

```javascript
console.log("Hello, world!");
```

To generate a WebAssembly module, run `npx javy-cli compile index.js -o
index.wasm`.

If the process is successful, you should have `index.wasm` in your current working
directory, which then can be executed with Wasmtime via `wasmtime run
index.wasm --invoke _start` and you should see the string `Hello, world!` printed as
output.


For more details, please see the project's [README](https://github.com/bytecodealliance/javy#javy).

## Contributing

If you find a missing feature, a bug or any other kind of improvements, [come
talk to us on GitHub](https://github.com/bytecodealliance/javy/issues/new/). We
also have a [list of _good first
issues_](https://github.com/bytecodealliance/javy/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
if you're interested in contributing and getting familiar with Javy.
