---
title: "The XZ Backdoor and Wasmtime"
author: "Nick Fitzgerald"
github_name: "fitzgen"
---

We are aware that the account responsible for the recent [XZ backdoor]
contributed a [pull request] to [Wasmtime]. After reviewing the pull request in
detail, we've concluded that Wasmtime's safety has not been compromised. The
pull request only made changes to documentation. It did not modify source code,
build systems, or binaries.

We take [security and correctness] extremely seriously in the Wasmtime
project. Follow [these guidelines] if you think you may have discovered a
security vulnerability in Wasmtime or any other Bytecode Alliance project.

We [believe] that fine-grained sandboxing and capabilities-based security can
strengthen our collective security posture against backdoors and other [supply
chain attacks]. That is why we are investing in standardizing and implementing
technologies like WebAssembly's [component model] and [WASI].

[XZ backdoor]: https://en.wikipedia.org/wiki/XZ_Utils_backdoor
[pull request]: https://github.com/bytecodealliance/wasmtime/pull/6839
[Wasmtime]: https://wasmtime.dev/
[security and correctness]: https://bytecodealliance.org/articles/security-and-correctness-in-wasmtime
[these guidelines]: https://bytecodealliance.org/security#reporting-a-security-bug-in-a-bytecode-alliance-project
[believe]: https://bytecodealliance.org/about
[supply-chain attacks]: https://en.wikipedia.org/wiki/Supply_chain_attack
[component model]: https://component-model.bytecodealliance.org/
[WASI]: https://wasi.dev/
