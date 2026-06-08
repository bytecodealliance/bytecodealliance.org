---
title: "Endive and the Next Chapter of WebAssembly on the JVM"
author: "Andrea Peruffo"
date: "2026-05-26"
github_name: "andreatp"
---

<p align="center">
  <img src="/images/endive-logo.png" alt="Endive" width="200">
</p>

## Announcement: Endive begins

In September 2023, a small group of contributors set out to answer a simple question: can WebAssembly run on the JVM with zero native dependencies? The project they built, Chicory, proved it could. Within two years it was powering [JRuby](https://github.com/jruby/jruby)'s Prism parser, a pure-Java [SQLite driver](https://github.com/roastedroot/sqlite4j), an [embedded PostgreSQL](https://github.com/roastedroot/pglite4j), a pure-Java [QuickJs runtime](https://github.com/roastedroot/quickjs4j), [TrinoDB Python UDFs](https://trino.io/docs/current/udf/python.html), and [many more](https://github.com/dylibso/chicory#who-uses-chicory). What started as an experiment became infrastructure.

Today we're announcing **Endive**, the next chapter for that project and community. Endive is a fork of Chicory and a Bytecode Alliance Hosted project, a vendor-neutral home where the project can grow openly.

Java developers should be able to embed Wasm modules without treating them as foreign native artifacts. They should be able to package, load, test, observe, and deploy Wasm using familiar Java workflows. That was the promise of Chicory, and it remains the promise of Endive. The community, the vision, and the code carry forward. What changes is that the project now belongs to its ecosystem.

## Why the Bytecode Alliance?

Chicory was founded and incubated as a cross-company, open-source collaboration that proved WebAssembly can fit naturally into Java applications. As the project grew, the community saw an opportunity to place it under vendor-neutral stewardship.

The Bytecode Alliance is that home. Its mission is to build secure, portable, modular foundations for WebAssembly, WASI, runtimes, compilers, and language tooling. The JVM is not a niche embedding target. It is a major managed runtime ecosystem with decades of production experience. If WebAssembly is to become a durable cross-language component format, the JVM should be part of that story. Endive gives the Bytecode Alliance community a place to collaborate on that work directly.

## Redline and Cranelift: performance without giving up the JVM story

The next major step is bringing the experimental [Redline](https://github.com/roastedroot/chicory-redline) compiler into the mainline.

Redline uses Cranelift to compile WebAssembly to native machine code, building on the same compiler foundation used by Wasmtime. This gives Endive a path to performance that is consistently comparable with Rust/Wasmtime-class runtimes, while preserving the Java packaging and embedding experience that made Chicory valuable.

With Endive, JVM-hosted Wasm no longer means choosing between integration and performance. You get Java-native embedding and native-speed execution in the same runtime. And on Java 25+, Redline achieves this with zero additional dependencies, thanks to the Foreign Function & Memory API (Panama) becoming a standard part of the platform.

## The Component Model and the JVM

Looking further ahead, Endive aims to bring full Component Model support to the JVM.

The Component Model defines typed, language-neutral interfaces between components, hosts, and libraries. Implementing it on the JVM means Java developers will be able to consume components written in Rust, Go, C, JavaScript, or other languages through explicit contracts rather than bespoke plugin APIs or native bindings.

A Java service should be able to load a component, expose only the capabilities that component needs, call it through generated typed bindings, observe it with JVM tooling, and deploy it using familiar Java packaging workflows.

As the Component Model gains traction across the ecosystem, the JVM will be one of the first managed runtimes to pursue deep integration. We hope that the lessons learned on the JVM will be useful as Component Model support reaches other managed runtimes.

## What happens next

The [Endive repository](https://github.com/bytecodealliance/endive) is already available. The first release will prioritize strong continuity with the latest Chicory release, preserving compatibility where possible, documenting migration steps clearly, and avoiding unnecessary disruption for existing users. Before that release, we will complete the security, governance, and supply-chain diligence expected of Bytecode Alliance Hosted projects. The path forward should be obvious for current Chicory users: the project has a new name and a new home, and the technical mission becomes even more ambitious.

Looking ahead, the project's focus areas are:

- merging the Cranelift-based Redline compiler into the mainline;
- tightening spec conformance, including WasmGC support and proposal alignment across runtimes;
- deepening WASI and Component Model support for JVM applications.

## Join the next chapter

Endive starts from the foundation Chicory established, but its future is about the broader community. The project stays Apache-2.0 licensed.

The goal is to make WebAssembly on the JVM neutral, durable, secure, high-performance, and ready for the Component Model.

If you care about Java, WebAssembly, secure plugin systems, cross-language components, or the future of portable software, [come build with us](https://github.com/bytecodealliance/endive).
