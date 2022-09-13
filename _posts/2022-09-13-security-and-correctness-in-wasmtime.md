---
title: "Security and Correctness in Wasmtime"
author: "Nick Fitzgerald"
github_name: "fitzgen"
---

The essence of software engineering is making trade-offs, and sometimes
engineers even trade away security for other priorities. When it comes to
running untrusted code from unknown sources, however, exceptionally strong
security is simply the bar to clear for serious participation: consider the
extraordinary efforts that Web browser and hypervisor maintainers take to
preserve their systems' integrity. WebAssembly runtimes also run untrusted code
from untrusted sources, and therefore such efforts are also a hard requirement
for WebAssembly runtimes.

WebAssembly programs are sandboxed and isolated from one another and from the
host, so they can't read or write external regions of memory, transfer control
to arbitrary code in the process, or freely access the network and
filesystem. This makes it safe to run untrusted WebAssembly programs: they
cannot escape the sandbox to steal private data from elsewhere on your laptop or
run a botnet on your servers. But these security properties only hold true if
the WebAssembly runtime's implementation is correct. This article will highlight
the ways we are ensuring correctness in [the Wasmtime WebAssembly runtime] and
in its compiler, Cranelift.

[the Wasmtime WebAssembly runtime]: https://wasmtime.dev/

This is our second blog post leading up to Wasmtime's upcoming 1.0 release on
September 20th, 2022. [The first blog post focused on Wasmtime's
performance.][first-blog] We're ready to release Wasmtime 1.0 because we believe
not only that it solidly clears the bar for security and correctness, but also
that we have the momentum, processes, and multi-stakeholder investment in place
to keep it that way in the future.

[first-blog]: https://bytecodealliance.org/articles/wasmtime-10-performance

## A Safe Implementation Language

Wasmtime is implemented in the Rust programming language. Google, Microsoft, and
Mozilla have each independently found that [around 70% of security bugs in their
browsers were memory safety bugs][70-percent], such as use-after-free bugs and
out-of-bounds heap accesses, including security bugs within those browsers'
WebAssembly implementations. Rust helps us avoid this whole class of bugs
without sacrificing the low-level control we need to efficiently implement a
language runtime. Large portions of Wasmtime even have zero `unsafe` blocks
&mdash; such as our WebAssembly parser, which is the first component to process
potentially-malicious input &mdash; and the parts that necessarily use `unsafe`
to implement primitives are carefully vetted.

[70-percent]: https://www.zdnet.com/article/chrome-70-of-all-security-bugs-are-memory-safety-issues/

Rust does not prevent all bugs, of course. It doesn't save us from
miscompilations due to logic errors in our compiler, for example, that could
ultimately lead to Wasm sandbox escapes. We'll discuss the techniques we use to
address these bugs and others that Rust doesn't catch throughout the rest of
this post.

The benefits of a safe implementation language, however, extend to applications
embedding Wasmtime. Even a correct WebAssembly runtime's utility is weakened if
the interface to that runtime is unsafe or so clunky that it pushes embedders
towards unsafe code out of convenience or to meet performance goals. That's why
we [designed Wasmtime's user-facing API][api] such that misusing it is nearly
impossible, using it doesn't require any `unsafe` Rust, and that this safety
does not also sacrifice performance. Our [typed function API], for example,
leverages Rust's type system to do a single type check up front when taking a
reference to a WebAssembly function, and subsequent uses &mdash; such as calls
into WebAssembly through that function &mdash; don't do repeated checks. Our
strongly-typed APIs let us statically maintain critical safety invariants for
users, avoiding the potential for misuse and the overhead of repeated dynamic
checks.

[api]: https://github.com/bytecodealliance/rfcs/blob/main/accepted/new-api.md
[typed function API]: https://docs.rs/wasmtime/latest/wasmtime/struct.Func.html#method.typed

## Securing Our Supply Chain

Malicious dependencies are becoming more common. An attacker gains control over
a library that your application depends on, adds code to steal your SSH keys,
and your world falls apart the next time you run a build. We cannot let Wasmtime
&mdash; and by extension, any application that embeds Wasmtime &mdash; be
compromised by malicious third-party dependencies.

The [WebAssembly component model] will help protect against these attacks with
[capabilities-based security and lightweight isolation between software
components][nanoprocess]. Unfortunately that can't be a solution for Wasmtime
itself, since Wasmtime needs to implement the component model and sits below
that abstraction level.

[WebAssembly component model]: https://github.com/WebAssembly/component-model/blob/main/design/mvp/Explainer.md
[nanoprocess]: https://bytecodealliance.org/articles/announcing-the-bytecode-alliance#tomorrows-solution-webassembly-nanoprocesses

To secure Wasmtime against malicious dependencies, we are using [`cargo
vet`][cargo-vet]. Mozilla created this tool to mechanically ensure that all
third-party Rust libraries used inside Firefox have been manually reviewed by a
trusted auditor.

When performing an audit, reviewers double check:

* the use of `unsafe`,
* that potentially-malicious, user-supplied data is handled with care
  (e.g. there is no recursion over user input that could let attackers craft
  inputs that cause the library to blow the stack),
* that a markdown-parsing library, for example, doesn't access the file system
  or network when it shouldn't need those capabilities,
* and that using the crate won't otherwise open the door to security
  vulnerabilities in production.

Using `cargo vet` we now require that a trusted Wasmtime maintainer manually
reviews all new dependencies and the delta for updates to existing
dependencies. At the same time, we are burning down the list of
yet-to-be-reviewed libraries that Wasmtime already depended upon before we
adopted `cargo vet`.

`cargo vet` benefits from network effects: it allows us to import audits from
another organization, so the more trustworthy organizations that start using
`cargo vet` and auditing dependencies, then the fewer audits we will have to
perform ourselves. And the more organizations that trust our audits, the more
utility each of our audits provides. Right now, Wasmtime imports and trusts
Firefox's audits, Firefox likewise imports and trusts Wasmtime's audits, and we
hope to expand this as the `cargo vet` community grows.

[cargo-vet]: https://mozilla.github.io/cargo-vet/

## Enabling Secure Application Designs

The security of applications using Wasmtime isn't just determined by Wasmtime's
development process. It is also determined by how Wasmtime unlocks more-secure
application designs that couldn't have been considered before, because the
performance overhead was impractical. One example is our ongoing standardization
and implementation work on the previously-mentioned [WebAssembly component
model], and composing WebAssembly programs while maintaining isolation and
performance. Another is the "disposable instance" paradigm.

[We've worked hard][first-blog] to make instantiating WebAssembly instances so
fast that you can create a fresh instance per task, throw it away when the task
is completed, and create another new instance for the next task. This means that
you can instantiate a fresh WebAssembly instance per HTTP request in a
serverless application, for example. It provides isolation between tasks, so if
the WebAssembly module has a bug that is triggered by the input for one task,
that bug can't automatically infect all other subsequent tasks. This wouldn't be
possible without Wasmtime's fast instantiation.

## Ubiquitous Fuzzing

[Fuzzing] is a software testing technique used to find security and correctness
issues by feeding pseudo-random data as input into the system you're testing:

[Fuzzing]: https://en.wikipedia.org/wiki/Fuzz_testing

```rust
fn fuzz() {
    loop {
        // Generate some new input.
        let input = generate_pseudo_random_data();

        // Feed that input into the system under test.
        let result = run_system_under_test(input);

        // Finally, if the system under test crashed,
        // failed an assertion, etc... then report
        // that!
        if result.is_interesting() {
            report(input);
        }
    }
}
```

We love fuzzing. We do continuous fuzzing in the background, 24/7. We do
targeted fuzzing while developing new features. We fuzz in the large (e.g. all
of Wasmtime) and the small (e.g. just our WebAssembly text format parser). We
contribute to and help maintain some of the core fuzzing infrastructure for the
whole Rust ecosystem. Our pervasive fuzzing is probably the biggest single
contributing factor towards Wasmtime's code quality.

We fuzz because writing tests by hand, while necessary, is not enough. We are
fallible humans and will inevitably miss an edge case. Our minds aren't twisted
enough to come up with the kinds of inputs that a fuzzer will eventually find.

Fuzzing can be as simple as throwing random bytes at a WebAssembly binary parser
and looking for any crashes. It can be as complex as generating arbitrary,
guaranteed-valid WebAssembly modules, compiling them with and without
optimizations, and asserting that running them yields the same results either
way. We do both.

We primarily use [`libFuzzer`][libfuzzer], a coverage-guided fuzzing engine
developed as part of the LLVM project, for our fuzzing. Our fuzzers run 24/7 as
part of [the OSS-Fuzz project]. We contribute to and help maintain [the `cargo
fuzz` tool][cargo-fuzz] that makes building and running fuzzers in Rust easy,
[the `arbitrary` crate][arbitrary] for fuzzing with structured data, and [the
`libfuzzer-sys` crate][libfuzzer-sys] that provides Rust bindings to
`libFuzzer`.

[libfuzzer]: https://www.llvm.org/docs/LibFuzzer.html
[the OSS-Fuzz project]: https://google.github.io/oss-fuzz/
[cargo-fuzz]: https://github.com/rust-fuzz/cargo-fuzz
[arbitrary]: https://github.com/rust-fuzz/arbitrary
[libfuzzer-sys]: https://github.com/rust-fuzz/libfuzzer

We use *generators* to create new, pseudo-random test cases, and *oracles* to
check security and correctness properties when evaluating those test cases in
Wasmtime.

We have a variety of generators, but the one we use most is
[`wasm-smith`][wasm-smith]. We wrote `wasm-smith` to produce pseudo-random
WebAssembly modules that are guaranteed valid. It helps us test deeper within
Wasmtime and Cranelift by not bouncing off the WebAssembly parser because of a
malformed memory definition or failing the validator because of a type error
inside a function body. It has configuration options to avoid generating code
that will trap at runtime, to only generate certain kinds of instructions such
as numeric instructions, and to turn various WebAssembly proposals on and off,
among many other things. We like to use [swarm testing] to let the fuzzer
dynamically configure the kinds of test cases we generate, improving the
diversity of our generated test cases. Firefox has also started using
`wasm-smith` to exercise its WebAssembly engine.

[wasm-smith]: https://fitzgeraldnick.com/2020/08/24/writing-a-test-case-generator.html
[swarm testing]: https://www.cs.utah.edu/~regehr/papers/swarm12.pdf

We use a variety of oracles in our fuzzing:

* Did the program crash or fail an assertion?
* If we capture the WebAssembly's stack, do we see the expected stack frames?
* Do we have the expected number of garbage collector-managed allocations and
  deallocations? Are we unexpectedly leaking?
* Can we round trip a WebAssembly module through our parser, disassembler, and
  assembler and get the original input again?
* Do we get the same results evaluating the input in:
  * Wasmtime with and without compiler optimizations enabled?
  * Wasmtime and V8?
  * Wasmtime and ([a formally verified version of]) the WebAssembly
    specification's reference interpreter?
* And
  [many](https://github.com/bytecodealliance/wasmtime/tree/main/fuzz/fuzz_targets)
  [more](https://github.com/bytecodealliance/wasm-tools/tree/main/fuzz/fuzz_targets).

[a formally verified version of]: https://github.com/conrad-watt/spec

We even have [a symbolic checker for register allocation][regalloc-checker] that
we use as an oracle. The checker proves that a given allocation to a bounded
number of physical registers correctly implements the original program that used
an unbounded number of virtual registers, regardless of what actual values are
given to the program or which control-flow paths are taken. We then generate
arbitrary control-flow graphs of basic blocks containing instructions that
operate on virtual registers, ask the register allocator to assign the virtual
registers to physical registers, and finally use this checker as an oracle to
assert that the assignment is correct.

[regalloc-checker]: https://cfallin.org/blog/2021/03/15/cranelift-isel-3/

When we implement new features in Wasmtime, we write generators and oracles
specifically designed to exercise these new features. The symbolic register
allocation checker is one example, as it was developed alongside a new register
allocator for Cranelift. When implementing new WebAssembly proposals in
Wasmtime, the baseline is adding support for the new proposal in
`wasm-smith`. But we will also do things like create [generators][table-ops] for
testing the [inline garbage collector write barriers][barriers] that we emit in
our compiled code when WebAssembly's reference types proposal is enabled. And we
developed [a fuzzer for the component model's interface
functions][interface-functions-fuzzer] in concert with their implementation in
Wasmtime. We have fully embraced "fuzz-driven development".

[table-ops]: https://github.com/bytecodealliance/wasmtime/blob/8b6019909b17077ae43249e17c8e95809887f9fd/crates/fuzzing/src/generators/table_ops.rs
[barriers]: https://bytecodealliance.org/articles/reference-types-in-wasmtime#inline-fast-paths-for-gc-barriers
[interface-functions-fuzzer]: https://github.com/bytecodealliance/wasmtime/pull/4537

## Formal Verification Efforts

Fuzzing gives us a statistical claim that our program is correct with respect to
what the fuzzer is exercising. The longer we run the fuzzer, the closer that
claim gets to 100%, but in general we'll never reach 100% because our input
space is way too large or even infinite. This is where our efforts to formally
verify parts of Wasmtime and Cranelift come in.

The [VeriWasm] project &mdash; a collaboration between UCSD, Stanford, and
Fastly &mdash; is a translation validator for WebAssembly programs compiled with
Cranelift. It proves that the compiled program's control-flow and memory
accesses cannot escape its isolated sandbox. This is not a claim about a handful
of inputs that we ran with a fuzzer, it proves this true for *all* inputs that
could be given to the compiled program.

[VeriWasm]: https://github.com/plsyssec/veriwasm

We've recently redesigned instruction selection in Cranelift to be defined via
rewrite rules in a domain-specific language we call [ISLE] (Instruction
Selection and Lowering Expressions). We have an ongoing collaboration with some
folks from Cornell and CMU to formally verify the correctness of our ISLE-based
instruction selection, proving that the machine instructions we emit do in fact
implement the input Cranelift IR for all values they could be given. If it
discovers an incorrect rule, the verifier will give us a counterexample. The
counterexample is an input where the original Cranelift IR evaluates to one
value, and the lowered machine instructions evaluate to a different value. The
counterexample and its divergent results will help us diagnose and fix our buggy
rule.

[ISLE]: https://github.com/bytecodealliance/rfcs/blob/main/accepted/cranelift-isel-isle-peepmatic.md

Looking further ahead, we are [investigating refactoring Cranelift's middle end
to use ISLE and rewrite rules][egraphs-rfc]. This will let us formally verify
the correctness of these rewrite rules, and further shrink our unverified,
trusted compute base. We intend to keep applying this process to the whole
compiler pipeline.

[egraphs-rfc]: https://github.com/bytecodealliance/rfcs/pull/27

## Spectre Mitigations

[Spectre] is a class of attacks exploiting speculative execution in modern
processors. Speculative execution is when the processor guesses where control
will flow &mdash; even though it has not actually computed branch conditions or
indirect jump targets yet &mdash; and starts tentatively executing its
guess. When the processor guesses correctly, the speculative execution's results
are used, speeding up the program; when it guesses incorrectly, they are
discarded. Unfortunately, even discarded speculations can still affect the
contents of caches and other internal processor state. An attacker can
indirectly observe these effects by measuring the time it takes to perform
operations that access that same internal state. Under the right conditions,
this allows the attacker to deduce what happened in discarded speculative
executions and effectively "see past" bounds checks and other security measures.

[Spectre]: https://en.wikipedia.org/wiki/Spectre_(security_vulnerability)

It is tempting to take a heavy-handed approach to defending against Spectre
attacks. Operating system process boundaries are a common mitigation, however
one of WebAssembly's most enticing features is its lighter-weight-than-a-process
isolation. Additionally, attackers must have access to a timer to pull off a
Spectre attack, and while it is tempting to block access to timer APIs, it is
[surprisingly easy to find widgets that can be made into timers][timers]. The
nature and severity of Spectre vulnerabilities depend greatly on context; the
mitigations described below can form part of overall protection.

[timers]: https://gruss.cc/files/fantastictimers.pdf

Wasmtime implements a number of Spectre mitigations to prevent speculative
execution from leaking information to malicious programs:

* Function table bounds checks are protected from speculative attack, ensuring
  that speculated `call_indirect` instructions cannot transfer control to an
  arbitrary location.

* The `br_table` instruction is protected from speculative attack, ensuring that
  speculation cannot transfer control to an arbitrary location.

* Wasmtime's default configuration for WebAssembly linear memories elides
  explicit bounds checks, relying on virtual memory guard pages
  instead. However, when virtual memory guard pages are disabled and we must
  emit explicit bounds checks, we additionally emit mitigation code that
  prevents speculated accesses from escaping the linear memory.

* We've implemented support for some hardware control-flow integrity features,
  such as [BTI on aarch64], which help mitigate some Spectre attacks.

[BTI on aarch64]: https://github.com/bytecodealliance/rfcs/blob/main/accepted/cfi-improvements-with-pauth-and-bti.md

Security researchers keep discovering new Spectre attacks and inventing better
mitigations for them. Therefore, we expect we will keep expanding and refining
Wasmtime's Spectre mitigations in the future as well.

## A Plan When Things Go Wrong

Even the most carefully crafted plans can go wrong, so we have backup plans for
bugs that slip past our safeguards. It begins with our [guidelines for reporting
security bugs] and our [disclosure policy]. Handling a security bug is a
delicate matter, and we don't want to make mistakes, so we have a [vulnerability
response runbook] to walk ourselves through responding to security bugs in the
moment. Once a patch is written, we backport security fixes to the two
most-recent Wasmtime releases, as per our [release process].

[guidelines for reporting security bugs]: https://bytecodealliance.org/security#reporting-a-security-bug-in-a-bytecode-alliance-project
[disclosure policy]: https://bytecodealliance.org/security#disclosure-policy
[release process]: https://docs.wasmtime.dev/stability-release.html
[vulnerability response runbook]: https://github.com/bytecodealliance/rfcs/blob/main/accepted/vulnerability-response-runbook.md

We've tested this safety net when faced with [Cranelift miscompilations] and
[incomplete stack maps for garbage collection].

[Cranelift miscompilations]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-hpqh-2wqx-7qp5
[incomplete stack maps for garbage collection]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-5fhj-g3p3-pq9g

## Conclusion

This article detailed how Wasmtime uses language safety, fine-grained isolation,
dependency auditing, fuzzing, and verification to bolster its security posture
and the security postures of applications embedding Wasmtime and the WebAssembly
programs Wasmtime runs. We believe that these are the minimum practices you
should demand from WebAssembly runtimes when running untrusted or
security-sensitive code, and we are constantly trying to raise this bar and
strengthen Wasmtime's security and correctness assurances.
