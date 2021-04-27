---
layout: default
---

<header id="hero" class="section-hero">
    <div class="container w-container"><img src="images/bytecode-alliance-logo.svg" width="730" alt="Bytecode Alliance logo"></div>
</header>

<section>
    <div class="container w-container">
        <div class="width-container" markdown="1">

## About the Bytecode Alliance

The Bytecode Alliance is a nonprofit organization dedicated to creating secure new software foundations, building on standards such as [WebAssembly](https://webassembly.org/) and [WebAssembly System Interface (WASI)](https://wasi.dev).

The Bytecode Alliance is committed to establishing a capable, secure platform that allows application developers and service providers to confidently run untrusted code, on any infrastructure, for any operating system or device, leveraging decades of experience doing so inside web browsers.

We have a [vision](/articles/announcing-the-bytecode-alliance) for a secure-by-default WebAssembly ecosystem for all platforms.

</div>
</div>
</section>

<section class="section section-tinted">
    <div class="container w-container">
        <div class="w-row">
            <div class="nopadding w-col w-col-6 w-col-medium-6"><img src="images/illustration.png"
                srcset="images/illustration-p-500.png 500w, images/illustration.png 894w"
                sizes="(max-width: 479px) 100vw, (max-width: 767px) 96vw, 49vw" alt="" class="illustration">
            </div>
            <div class="nopadding w-col w-col-6 w-col-medium-6" markdown="1">

## Become a member

The Bytecode Alliance welcomes contributions and participation from across the industry. Join as a member and help drive the future of computing.

<div id="join-callout"><div class="join-button"><a href="{{ site.baseurl }}/membership">Join Now</a></div></div>

</div>
</div>
</div>
</section>

<section>
    <div class="container w-container">
        <div class="width-container" markdown="1">

## Members

<div class="member-logos">
<img src="images/member-logos/arm.svg" alt="Arm Logo">
<img src="images/member-logos/dfinity.svg" alt="DFINITY Logo">
<img src="images/member-logos/embark-studios.png" alt="Embark Studios Logo">
<img src="images/member-logos/fastly.svg" alt="Fastly Logo">
<img src="images/member-logos/google.svg" alt="Google Logo">
<img src="images/member-logos/intel.svg" alt="Intel Logo">
<img src="images/member-logos/microsoft.svg" alt="Microsoft Logo">
<img src="images/member-logos/mozilla.svg" alt="Mozilla Logo">
<img src="images/member-logos/shopify.svg" alt="Shopify Logo">
<img src="images/member-logos/ucsd.svg" alt="UCSD Logo">
</div>

</div>
</div>
</section>

<section id="faq">
    <div class="container w-container">
        <div class="width-container">
            <div class="flex-center">
                <a href="#faq"><h4>FAQ</h4></a>
                <h2>Frequently Asked Questions</h2>
            </div>
            <ul id="faq-entries">
            <li class="fentry" id="what-is-the-bytecode-alliance">
                <a href="#what-is-the-bytecode-alliance"><h3>What is the Bytecode Alliance?</h3></a>
                <input type="checkbox">
                <div class="ficon">
                    <div class="fline fvertical"></div>
                    <div class="fline"></div>
                    <img src="images/circle.svg" alt="" class="fcircle">
                </div>
                <div class="fanswer">
                    <p>The Bytecode Alliance is a group of projects, organizations, and individuals working to
                        provide state-of-the-art foundations for the development of runtime environments and
                        language toolchains where security, efficiency, and modularity can all coexist across a wide
                        range of devices and architectures. We enable innovation in compilers, runtimes, and
                        tooling, focusing on fine-grained sandboxing, capabilities-based security, modularity, and
                        standards such as WebAssembly and WASI.</p>
                </div>
            </li>
            <li class="fentry" id="why-is-this-important-now">
                <a href="#why-is-this-important-now"><h3>Why is this an important focus right now?</h3></a>
                <input type="checkbox">
                <div class="ficon">
                    <div class="fline fvertical"></div>
                    <div class="fline"></div>
                    <img src="images/circle.svg" alt="" class="fcircle">
                </div>
                <div class="fanswer">
                <p>Developers are running untrusted code in many new places, from the cloud to IoT devices. But
                    this opens up many security concerns, and also portability challenges when you try to run
                    the same code across these different systems. We don’t yet have a solid foundation to build
                    upon.
                </p>
                <p>
                    With WebAssembly and emerging related standards such as WASI and WebAssembly Interface
                    Types, this solid foundation is taking shape. By building this foundation, we can address
                    some persistent fundamental issues of today’s software development practices.
                </p>
                </div>
            </li>
            <li class="fentry" id="why-a-cross-industry-effort">
                <a href="#why-a-cross-industry-effort"><h3>Why does this require a cross-industry effort?</h3></a>
                <input type="checkbox">
                <div class="ficon">
                    <div class="fline fvertical"></div>
                    <div class="fline"></div>
                    <img src="images/circle.svg" alt="" class="fcircle">
                </div>
                <div class="fanswer">
                <p>The problem we are attempting to solve is fundamentally a cross-industry problem. We want to
                    allow for safe interaction and code reuse across server, edge, browser, mobile, and more
                    platforms. These different platforms are developed by different groups across the industry.
                    Our intent is to bring them together to solve problems for everyone.</p>
                </div>
            </li>
            <li class="fentry" id="relation-to-standards-bodies">
                <a href="#relation-to-standards-bodies"><h3>How does this relate to standardization bodies like the W3C’s WebAssembly CG?</h3></a>
                <input type="checkbox">
                <div class="ficon">
                    <div class="fline fvertical"></div>
                    <div class="fline"></div>
                    <img src="images/circle.svg" alt="" class="fcircle">
                </div>
                <div class="fanswer">
                <p>The Bytecode Alliance is focused on creating a shared implementation of standards produced by
                    the WebAssembly CG and other standardization bodies.
                </p>
                <p>
                    We believe that standards are best informed by implementation. To enable this, we bring
                    together a wide range of different use cases. Many of our contributors are also active in
                    standardization and use this implementation experience and feedback to inform their work.
                </p>
                </div>
            </li>
            <li class="fentry" id="projects-of-the-alliance">
                <a href="#projects-of-the-alliance"><h3>What projects are already a part of this?</h3></a>
                <input type="checkbox">
                <div class="ficon">
                    <div class="fline fvertical"></div>
                    <div class="fline"></div>
                    <img src="images/circle.svg" alt="" class="fcircle">
                </div>
                <div class="fanswer">
                <h4>Wasmtime</h4>
                <p>
                    <a href="https://github.com/bytecodealliance/wasmtime">Wasmtime</a> is a WebAssembly runtime. It runs WebAssembly outside of the browser, in a fast,
                    portable, secure, and scalable way.
                </p>
                <p>
                    Wasmtime serves as the base layer for other hosts. For example, Fastly is refactoring the
                    Lucet runtime on top of Wasmtime, and Red Hat is building a WebAssembly runtime based on
                    Wasmtime for the Enarx project (part of the Confidential Computing Consortium).
                </p>
                <h4>Cranelift</h4>
                <p>
                    <a href="https://github.com/bytecodealliance/wasmtime/tree/main/cranelift">Cranelift</a> is a highly optimized code generator, focused on fast compilation. It’s used in
                    Wasmtime for both JIT and AOT compilation, and is currently being integrated into Firefox as
                    the optimizing compiler for WebAssembly. It’s also used as an experimental backend for the
                    Rust compiler.
                </p>
                <h4>Lucet</h4>
                <p>
                    <a href="https://github.com/bytecodealliance/lucet">Lucet</a> is an AOT compiler utilizing Cranelift. It is meant specifically for low-latency,
                    high-concurrency server-based applications of WebAssembly.
                </p>
                <h4>WebAssembly Micro-Runtime (WAMR)</h4>
                <p>
                    <a href="https://github.com/bytecodealliance/wasm-micro-runtime">WAMR</a> is an interpreter based WebAssembly runtime, optimized for embedded and
                    resource-constrained devices.
                </p>
                <h4>Enarx (affiliated)</h4>
                <p>
                    <a href="https://enarx.io">Enarx</a> is an application deployment system enabling applications to run within Trusted Execution Environments (TEEs) in a platform independent way. It's a project of the <a href="https://confidentialcomputing.io/">Confidential Computing Consortium</a> that is based on Wasmtime and closely affiliated with the Bytecode Alliance.
                </p>
                </div>
            </li>
            <li class="fentry" id="project-licenses">
                <a href="#project-licenses"><h3>How are these projects licensed?</h3></a>
                <input type="checkbox">
                <div class="ficon">
                    <div class="fline fvertical"></div>
                    <div class="fline"></div>
                    <img src="images/circle.svg" alt="" class="fcircle">
                </div>
                <div class="fanswer">
                <p>The main projects are licensed under the Apache 2.0 license + LLVM exception (which ensures GPL compatibility). Some supporting projects are licensed under Apache 2.0/MIT dual license.</p>
                </div>
            </li>
            <li class="fentry" id="how-to-get-involved">
                <a href="#how-to-get-involved"><h3>How do developers get involved?</h3></a>
                <input type="checkbox">
                <div class="ficon">
                    <div class="fline fvertical"></div>
                    <div class="fline"></div>
                    <img src="images/circle.svg" alt="" class="fcircle">
                </div>
                <div class="fanswer">
                <p>Developers are encouraged to participate in any open source project in the Bytecode Alliance.
                    Each project is governed by its own committer group. Developers who are very active in
                    shaping a project are eligible for nomination to the project’s committer group.
                </p>
                <p>
                    Developers can also join in by integrating the Bytecode Alliance’s projects into their
                    projects and products, and providing feedback based on their use cases.
                </p>
                </div>
            </li>
            <li class="fentry" id="how-to-join">
                <a href="#how-to-join"><h3>How do organizations join the Alliance?</h3></a>
                <input type="checkbox">
                <div class="ficon">
                    <div class="fline fvertical"></div>
                    <div class="fline"></div>
                    <img src="images/circle.svg" alt="" class="fcircle">
                </div>
                <div class="fanswer">
                <p>Organizations are encouraged to participate in the Alliance’s open source projects, and to
                    use them in their own projects and products.
                </p>
                <p>
                    We will also have Alliance-wide governance, which will be comprised of organizational
                    members. Once the Bytecode Alliance has been formally established and a governance model
                    finalized, organizations that provide strong and ongoing contributions to the Alliance’s
                    projects will be able to participate in Alliance governance.
                </p>
                <p>
                    If your organization is interested, please get in contact with us at:
                    <a href="mailto:hello@bytecodealliance.org">hello@bytecodealliance.org</a>
                </p>
                </div>
            </li>
            <li class="fentry" id="governance">
                <a href="#governance"><h3>How will the Alliance be governed?</h3></a>
                <input type="checkbox">
                <div class="ficon">
                    <div class="fline fvertical"></div>
                    <div class="fline"></div>
                    <img src="images/circle.svg" alt="" class="fcircle">
                </div>
                <div class="fanswer">
                <p>An open governance model consistent with open source best practices and strong community
                    norms will be established upon formal formation.
                </p>
                </div>
            </li>
            <li class="fentry" id="supported-platforms">
                <a href="#supported-platforms"><h3>Which architectures and OS platforms are supported?</h3></a>
                <input type="checkbox">
                <div class="ficon">
                    <div class="fline fvertical"></div>
                    <div class="fline"></div>
                    <img src="images/circle.svg" alt="" class="fcircle">
                </div>
                <div class="fanswer">
                <p>The Bytecode Alliance aims to cover as many hardware and OS configurations as possible. Right
                    now, the architectures covered are:
                </p>
                <p>Wasmtime and Cranelift are officially supported and tested on Linux, macOS 10.9+, and Windows 10 on x86_64, and reported to work on FreeBSD on x86_64.
                </p>
                <p>
                    Lucet is officially supported and tested on Linux and macOS 10.9+ on x86_64.
                </p>
                <p>
                    WAMR runs under Linux, macOS, Zephyr, AliOS Things, and VxWorks and has support for x86_32, x86_64, Arm, and MIPS.
                </p>
                </div>
            </li>
            <li class="fentry" id="supported-execution-modes">
                <a href="#supported-execution-modes"><h3>Which execution modes are supported?</h3></a>
                <input type="checkbox">
                <div class="ficon">
                    <div class="fline fvertical"></div>
                    <div class="fline"></div>
                    <img src="images/circle.svg" alt="" class="fcircle">
                </div>
                <div class="fanswer">
                <p>Different use cases are best served by different execution modes, or a mix of execution modes. Right now, the execution modes covered are:
                    </p>
                    <ul>
                        <li>Interpreter in WAMR</li>
                        <li>Baseline and optimizing JIT in Wasmtime through Lightbeam and Cranelift</li>
                        <li>AoT in Wasmtime/Cranelift and in Lucet</li>
                    </ul>
                    <p>Full support for all these execution modes, including tiering where applicable, is planned for Wasmtime.</p>
                </div>
            </li>
            </ul>
        </div>
    </div>
</section>