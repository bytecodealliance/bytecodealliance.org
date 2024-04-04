---
title: "The XZ Backdoor and Wasmtime"
author: "Nick Fitzgerald"
github_name: "fitzgen"
---

We are aware that the account responsible for the recent [XZ backdoor]
contributed a documentation-only [pull request] to [Wasmtime], however
Wasmtime's safety remains intact. We have reviewed the pull request in detail
and confirmed that it only modified a single markdown file, and contained no
changes to source code, build systems, or binaries. Furthermore, the
documentation was not altered in such a way that it could trick unsuspecting
readers into sabotaging themselves.

We [believe] that fine-grained sandboxing and capabilities-based security can
strengthen our collective security posture against backdoors and other [supply
chain attacks]. That is why we are investing in standardizing and implementing
technologies like WebAssembly's [component model] and [WASI].

We take [security and correctness] extremely seriously in the Wasmtime
project. Our secure development practices include:

* A safe-by-default implementation language
* Dependency auditing with [`cargo vet`]
* Ubiquitous fuzzing
* Formal verification

We believe that this is the minimum you should demand from a WebAssembly
runtime. We are constantly trying to raise this bar and further strengthen
Wasmtime's security and correctness assurances.

Follow [these guidelines] if you think you may have discovered a
security vulnerability in Wasmtime or any other Bytecode Alliance project.

[XZ backdoor]: https://en.wikipedia.org/wiki/XZ_Utils_backdoor
[pull request]: https://github.com/bytecodealliance/wasmtime/pull/6839
[Wasmtime]: https://wasmtime.dev/
[security and correctness]: https://bytecodealliance.org/articles/security-and-correctness-in-wasmtime
[these guidelines]: https://bytecodealliance.org/security#reporting-a-security-bug-in-a-bytecode-alliance-project
[believe]: https://bytecodealliance.org/about
[supply chain attacks]: https://en.wikipedia.org/wiki/Supply_chain_attack
[component model]: https://component-model.bytecodealliance.org/
[WASI]: https://wasi.dev/
[`cargo vet`]: https://mozilla.github.io/cargo-vet/
