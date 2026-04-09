---
title: 'Wasmtime''s April 9, 2026 Security Advisories'
author: "The Wasmtime Project Maintainers"
date: "2026-04-09"
github_name: "pchickey"
---

### A new world for security-critical projects

The technology security landscape has fundamentally changed. LLM-based tooling has evolved significantly and is now uncovering many classes of vulnerabilities [faster and more effectively than ever before](https://blog.mozilla.org/en/firefox/hardening-firefox-anthropic-red-team/), especially in [large, security-critical codebases](https://mtlynch.io/claude-code-found-linux-vulnerability/). Over the past three weeks, the Wasmtime team has responded with urgency: through strong collaboration between Bytecode Alliance members Mozilla, UCSD, Akamai, and F5, the team used new LLM tools to find a significant set of vulnerabilities, which have been remediated in patch releases today. This moment reinforces a new reality for open-source developers, as well as a project-long principle for Wasmtime: security is central to our mission. We are committed to confronting this new reality directly, investing in better techniques, and continuing to raise the bar for the security of Wasmtime and the WebAssembly ecosystem.

### The latest patch releases

Today, we released Wasmtime versions 43.0.1, 42.0.2, 36.0.7, and 24.0.7, which include fixes for 12 distinct security advisories. Two of these security advisories have a CVSS severity at the Critical level. We recommend all users of Wasmtime upgrade to one of these versions as soon as possible.

11 of these 12 advisories were discovered by the Wasmtime team using new LLM-based tools. There is also one security advisory for a Low severity issue reported by a user and only affecting the latest stable 43.0.0 release[^1], but is otherwise unrelated to this effort.

This is the largest set of advisories Wasmtime has ever published at once, is triple the total number of advisories published in all of 2025, and doubles the number of Critical severity advisories published in the project's history.

### Wasmtime's existing security practices

Security is critical to the [mission of the Bytecode Alliance] as well as to the [users of Wasmtime]. The security guarantees Wasmtime makes for sandboxed WebAssembly execution are [documented], and the Wasmtime project already takes [extensive measures] towards security and correctness:
* Wasmtime is implemented in Rust with judicious and regulated use of `unsafe`, and all `unsafe` is tested with [Miri].
* Wasmtime's maintainers audit the project's dependencies using [`cargo vet`].
* Wasmtime requires continuous fuzzing for all applicable [tier 1] functionality
* Wasmtime includes [mitigations for Spectre] attacks
* Wasmtime's Cranelift code generator has been [formally verified].

[mission of the Bytecode Alliance]: https://bytecodealliance.org/about
[documented]: https://docs.wasmtime.dev/security.html
[extensive measures]: https://bytecodealliance.org/articles/security-and-correctness-in-wasmtime
[users of Wasmtime]: https://github.com/bytecodealliance/wasmtime/blob/main/ADOPTERS.md
[Miri]: https://github.com/rust-lang/miri
[`cargo vet`]: https://mozilla.github.io/cargo-vet/
[mitigations for Spectre]: https://docs.wasmtime.dev/security.html#spectre
[formally verified]: https://dl.acm.org/doi/10.1145/3617232.3624862

### Discovering and remediating these issues

This exceptional release is the result of the Wasmtime team deploying new state-of-the-art LLM tools to discover security flaws in Wasmtime. Wasmtime team members at Mozilla, UCSD, Akamai, and F5 collaborated on the discovery of these issues over an intense 3-week sprint.

We developed a multi-agent harness that (1) analyzes the Wasmtime codebase, targeting Wasmtime across different architectures and backend, and (2) validates potential bugs by reproducing proof-of-concept exploits and test vectors. To date, we primarily focused on using this harness to analyze the most security-sensitive areas of the Wasmtime codebase: native code generation in the [tier 1] Cranelift and Winch engines, and in Wasmtime crate's runtime implementation (under `src/runtime/`), where unsafe Rust is used.

The Wasmtime maintainers thank, in particular:

* Alex Crichton [@alexcrichton] (Akamai) led the remediation effort. In addition to guiding the LLMs to analyze security sensitive and tricky parts of the codebase, he also found and fixed many non-security discovered through related prompts.
* Bobby Holley [@bholley] (Mozilla) helped us re-use techniques Mozilla found fruitful in a [similar effort] underway for Firefox.
* Shun Kashiwa [@shumbo] (UCSD) developed the multi-agent harness and the LLM prompts which uncovered many of the security issues issues in this release.
* Chris Fallin [@cfallin] (F5) focused on prompts to search for issues in Wasmtime's Cranelift and Winch code generators.

[@alexcrichton]: https://github.com/alexcrichton
[@bholley]: https://github.com/bholley
[@shumbo]: https://github.com/shumbo
[@cfallin]: https://github.com/cfallin 
[similar effort]: https://blog.mozilla.org/en/firefox/hardening-firefox-anthropic-red-team/

The team's efforts produced 11 different security issues over our 3-week sprint, with diminishing returns after the end of the first week. No additional unique issues were found after the end of the second week. The LLM search also turned up a significant number of minor, non-security bugs in Wasmtime, as well as in dependencies such as `wasmparser`. These bugs have been fixed in the `main` branch of Wasmtime but, per our [security policy], will not be backported to the release branches.

[security policy]: https://docs.wasmtime.dev/stability-release.html

The infrastructure running the agent harness and prompts are still in early stages, and we are actively improving this tooling and generalizing the harness. Our efforts have been focused on completing security remediation, and we have a backlog of minor non-security bugs that need to be fixed in `main` as well. Over the coming weeks, we will be exploring how to land all Wasmtime-specific pieces of the LLM-driven search tooling into Wasmtime repo, and determining how to depend on our own or external services to provide continuous LLM scanning.

### Security issues discovered using LLMs

The complete set of LLM-discovered issues in these releases are, sorted high to low severity:

| GHSA | CVE | Severity | Title |
| -    | -   | -        | -     |
|[GHSA-xx5w-cvp6-jv83]| CVE-2026-34987 | Critical (9.0) | Wasmtime with Winch compiler backend may allow a sandbox-escaping memory access |
|[GHSA-jhxm-h53p-jm7w]| CVE-2026-34971 | Critical (9.0) | Miscompiled guest heap access enables sandbox escape on aarch64 Cranelift |
|[GHSA-hx6p-xpx3-jvvv]| CVE-2026-34941 | Moderate (6.9) | Heap OOB read in component model UTF-16 to latin1+utf16 string transcoding |
|[GHSA-f984-pcp8-v2p7]| CVE-2026-35186 | Moderate (6.1) | Improperly masked return value from `table.grow` with Winch compiler backend |
|[GHSA-394w-hwhg-8vgm]| CVE-2026-35195 | Moderate (6.1) | Out-of-bounds write or crash when transcoding component model strings |
|[GHSA-jxhv-7h78-9775]| CVE-2026-34942 | Moderate (5.9) | Panic when transcoding misaligned component model UTF-16 strings |
|[GHSA-q49f-xg75-m9xw]| CVE-2026-34946 | Moderate (5.9) | Host panic when Winch compiler executes `table.fill` |
|[GHSA-m758-wjhj-p3jq]| CVE-2026-34943 | Moderate (5.6) | Panic when lifting `flags` component value |
|[GHSA-qqfj-4vcm-26hv]| CVE-2026-34944 | Moderate (4.1) | Wasmtime segfault or unused out-of-sandbox load with `f64x2.splat` operator on Cranelift x86-64 |
|[GHSA-m9w2-8782-2946]| CVE-2026-34945 | Low (2.3) | Host data leakage with 64-bit tables and Winch |
|[GHSA-6wgr-89rj-399p]| CVE-2026-34988 | Low (2.3) | Data leakage between pooling allocator instances |

[GHSA-hx6p-xpx3-jvvv]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-hx6p-xpx3-jvvv
[GHSA-xx5w-cvp6-jv83]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-xx5w-cvp6-jv83
[GHSA-jhxm-h53p-jm7w]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-jhxm-h53p-jm7w
[GHSA-m758-wjhj-p3jq]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-m758-wjhj-p3jq
[GHSA-jxhv-7h78-9775]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-jxhv-7h78-9775
[GHSA-f984-pcp8-v2p7]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-f984-pcp8-v2p7
[GHSA-qqfj-4vcm-26hv]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-qqfj-4vcm-26hv
[GHSA-q49f-xg75-m9xw]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-q49f-xg75-m9xw
[GHSA-m9w2-8782-2946]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-m9w2-8782-2946
[GHSA-6wgr-89rj-399p]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-6wgr-89rj-399p
[GHSA-394w-hwhg-8vgm]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-394w-hwhg-8vgm

To start with the positive news: users of Wasmtime's Cranelift backend on x86_64 were not affected by either of the two Critical-severity sandbox escapes. This backend is the focus of the most scrutiny because, historically, it is the backend most used in production systems.

However, the compiler backends accounted for the majority of the issues found in this release. Four issues were discovered in the Winch backend: [GHSA-xx5w-cvp6-jv83], [GHSA-f984-pcp8-v2p7], [GHSA-q49f-xg75-m9xw], [GHSA-m9w2-8782-2946], and two in Cranelift: [GHSA-jhxm-h53p-jm7w], [GHSA-qqfj-4vcm-26hv]. Winch and Cranelift are the two compilers with [tier 1] stability in the Wasmtime project. Each of these compilers have had thousands of engineer-hours of effort applied to their development and correctness, however, the Winch backend is newer.

Component Model string handling was a source of 3 issues: [GHSA-hx6p-xpx3-jvvv], [GHSA-394w-hwhg-8vgm], and [GHSA-jxhv-7h78-9775]. Wasmtime has unit tests for valid and invalid cases of passing strings, and a fuzzing harness that checks that valid strings are passed between components correctly. However, there was no fuzzing to check that invalid strings are handled correctly, and each of these issues could have concievably been discovered if such a fuzzing harness had been written.

There is no continuous fuzzing of either Cranelift or Winch on aarch64 at this time, which is a significant shortcoming. This is largely because [Google's oss-fuzz], which Wasmtime relies on for continuous fuzzing, does not support aarch64-based runners. Wasmtime developers do use the existing fuzzing harnesses for one-off fuzzing during development of Winch and Cranelift changes affecting the aarch64 architecture. We do not know if continuous fuzzing would have found the issues affecting aarch64 discovered in this effort.

[Google's oss-fuzz]: https://github.com/google/oss-fuzz

The Critical-serverity advisory [GHSA-jhxm-h53p-jm7w] found a correctness problem in Cranelift's instruction lowering rules, a bug which was introduced in Wasmtime 32.0.0. Cranelift's instruction lowering rules have been formally verified, and published in peer-reviewed conferences: [verification repository], [initial paper], [follow-on work], [accompanying artifact]. However, the model had not been updated against the Cranelift sources to include the changes in 32.0.0. Upon updating the formal model to check against the latest Cranelift lowering rules, verification flags the same bug as was found with the LLM search. This underscores the importance of a tight integration between formal verification and Cranelift development.

[verification repository]: https://github.com/mmcloughlin/arrival
[initial paper]: https://dl.acm.org/doi/10.1145/3617232.3624862
[follow-on work]: https://dl.acm.org/doi/10.1145/3764383
[accompanying artifact]: https://zenodo.org/records/15788021

### Improving Wasmtime's processes going forward

These issues have convinced the Wasmtime maintainer team that LLM-based tools will be a permanent addition to our security toolbox. LLMs have proven to be effective at searching for security vulnerabilities that were present in Wasmtime for a long time. These new tools strengthen the already strong security practices in our project.

Beyond the remediation of some non-security bugs, the Wasmtime team will be taking the following steps in the upcoming weeks and months:

* We will explore options for infrastructure providers of continuous LLM-based security scanning of Wasmtime codebase to support both continous and development-driven focused bug searching. We will also refactor and place the Wasmtime-specific parts of our LLM agent harnesses into the Wasmtime repository. If any LLM providers want to help our project (e.g., with credits or access to preview models) please [reach out]!
* We will require the use of LLM based vulnerability discovery as part of the tier 1 requirements for all future tier 1 features.
* We will explore improvements our fuzzing harnesses to include checking that invalid programs trap as required. Historically we have found this to be much more difficult than checking that valid programs behave correctly, so we expect this will pose some challenges.
* We will investigate ways to provide continuous fuzzing on aarch64 for both the Cranelift and Winch engines. If any infrastructure providers offering continuous fuzzing like [Google's oss-fuzz] and offer aarch64 runners can help our project, please [reach out]!
* We will accelarate the work in progress to land formal verification of Cranelift into the Wasmtime repo, so that all changes to Cranelift's lowering rules will be verified as part of CI checks.
* We will apply everything we learned from this effort to other Bytecode Alliance projects, and help the TSC form recommendations that will apply to all BA projects.

[reach out]: mailto:membership@bytecodealliance.org
[tier 1]: https://docs.wasmtime.dev/stability-tiers.html#tier-1

[^1]: [GHSA-hfr4-7c6c-48w2] fixes a bug introduced in Wasmtime 43.0.0 (the previous stable release) and was reported and fixed by Flavio Castelli [@flavio] as PR [#12906]. It was discovered in ordinary use, not through using an LLM.

[@flavio]: https://github.com/flavio
[#12906]: https://github.com/bytecodealliance/wasmtime/pull/12906
[GHSA-hfr4-7c6c-48w2]: https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-hfr4-7c6c-48w2
