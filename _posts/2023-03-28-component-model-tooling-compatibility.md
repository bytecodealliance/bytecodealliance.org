---
title: "Component Model Tooling Compatibility"
author: "Peter Huene"
github_name: peterhuene

# Published versions
wasmtime: 7.0.0
wasmtime-wit-bindgen: 7.0.0
wit-bindgen-c: 0.4.0
wit-bindgen-go: 0.2.0
wit-bindgen-rust: 0.4.0
wit-bindgen-teavm-java: 0.4.0
wasm-compose: 0.2.11
wasm-encoder: 0.25.0
wasm-metadata: 0.3.1
wasmparser: 0.102.0
wasmprinter: 0.2.54
wat: 1.0.61
wit-component: 0.7.4
wit-parser: 0.6.4
wasm-tools: 1.0.28
wit-bindgen: 0.4.0
componentize-js: 0.0.3
jco: 0.5.3
preview2-shim: 0.0.5

# Unpublished versions
wasi-preview2: 408f0bf
cargo-component: 2101df5
---

Here at the Bytecode Alliance, we are very excited about the potential of the 
[WebAssembly Component Model][proposal] proposal and we understand that many of 
you are actively exploring ways to build solutions that use WebAssembly 
components as well!

We have been working hard on an implementation of the proposal across many of 
our repositories. However, keeping track of the various versions of the tooling 
that are compatible with one another is not an easy undertaking.

As work on an implementation progresses, we would like to periodically publish 
a "matrix" of known-compatible versions of the tooling to make it easier for 
users to work with our component model implementation.

### Compatibility Matrix

The compatibility matrix is a ***snapshot*** of the tooling that aligns on the 
underlying support for the textual and binary representations of WebAssembly 
components (as specified in the [proposal][proposal]) and also on 
component-model-compatible [WASI][wasi] interfaces.

Note that the matrix is not a guarantee of the _quality_ of the implementation: 
as many of the tools are very much in active development and bugs will 
definitely be encountered, please consider the tooling to be a ***technology 
preview***.

When the proposal and implementation have stabilized, we will announce that
it is ready to use in a production environment.

Here is the current compatibility matrix for the component model tooling:

| Runtime                                   | Bindings                                                              | WASI (preview2)                                                | Tooling                                                   | CLI Tools                                                 |
|:------------------------------------------|:----------------------------------------------------------------------|:---------------------------------------------------------------|:----------------------------------------------------------|:----------------------------------------------------------|
| [wasmtime][0] ([{{ page.wasmtime }}][v0]) | [wasmtime-wit-bindgen][1] ([{{ page.wasmtime-wit-bindgen }}][v1])     | [host][6] ([{{ page.wasi-preview2 }}][v6])                     | [componentize-js][7] ([{{ page.componentize-js }}][v7])   | [cargo-component][16] ([{{ page.cargo-component }}][v16]) |
|                                           | [wit-bindgen-c][2] ([{{ page.wit-bindgen-c }}][v2])                   | [js-preview2-shim][20] ([{{ page.preview2-shim }}][v20])       | [wasm-compose][8] ([{{ page.wasm-compose }}][v8])         | [jco][17] ([{{ page.jco }}][v17])                         |
|                                           | [wit-bindgen-go][3] ([{{ page.wit-bindgen-go }}][v3])                 | [preview1-command-adapter][6] ([{{ page.wasi-preview2 }}][v6]) | [wasm-encoder][9] ([{{ page.wasm-encoder }}][v9])         | [wasm-tools][18] ([{{ page.wasm-tools }}][v18])           |
|                                           | [wit-bindgen-rust][4] ([{{ page.wit-bindgen-rust }}][v4])             | [preview1-reactor-adapter][6] ([{{ page.wasi-preview2 }}][v6]) | [wasm-metadata][10] ([{{ page.wasm-metadata }}][v10])     | [wit-bindgen][19] ([{{ page.wit-bindgen }}][v19])         |
|                                           | [wit-bindgen-teavm-java][5] ([{{ page.wit-bindgen-teavm-java }}][v5]) | [wasi-cap-std-sync][6] ([{{ page.wasi-preview2 }}][v6])        | [wasmparser][11] ([{{ page.wasmparser }}][v11])           |                                                           |
|                                           |                                                                       | [wasi-common][6] ([{{ page.wasi-preview2 }}][v6])              | [wasmprinter][12] ([{{ page.wasmprinter }}][v12])         |                                                           |
|                                           |                                                                       | [wasi-tokio][6] ([{{ page.wasi-preview2 }}][v6])               | [wat][13] ([{{ page.wat }}][v13])                         |                                                           |
|                                           |                                                                       |                                                                | [wit-component][14] ([{{ page.wit-component }}][v14])     |                                                           |
|                                           |                                                                       |                                                                | [wit-parser][15] ([{{ page.wit-parser }}][v15])           |                                                           |

### Runtimes

The following table lists the versions of the runtime packages that are 
compatible:

| Package       | Version                   | Compilation Feature |
|:--------------|:--------------------------|:--------------------|
| [wasmtime][0] | [{{ page.wasmtime }}][v0] | _component-model_   |

### Host Bindings

The following table lists the versions of the host bindings generator packages 
that are compatible:

| Package                   | Version                               |
|:--------------------------|:--------------------------------------|
| [wasmtime-wit-bindgen][1] | [{{ page.wasmtime-wit-bindgen }}][v1] |

### Guest Bindings

The following table lists the versions of the guest bindings generator packages 
that are compatible:

| Package                     | Version                                 |
|:----------------------------|:----------------------------------------|
| [wit-bindgen-c][2]          | [{{ page.wit-bindgen-c }}][v2]          |
| [wit-bindgen-go][3]         | [{{ page.wit-bindgen-go }}][v3]         |
| [wit-bindgen-rust][4]       | [{{ page.wit-bindgen-rust }}][v4]       |
| [wit-bindgen-teavm-java][5] | [{{ page.wit-bindgen-teavm-java }}][v5] |

### WASI (preview2)

The following table lists the versions of the WASI preview2 packages that are 
compatible:

| Package                                            | Version                         |
|:---------------------------------------------------|:--------------------------------|
| [host][6]                                          | [{{ page.wasi-preview2 }}][v6]  |
| [js-preview2-shim][20]                             | [{{ page.preview2-shim }}][v20] |
| [wasi-common][6]                                   | [{{ page.wasi-preview2 }}][v6]  |
| [wasi-cap-std-sync][6]                             | [{{ page.wasi-preview2 }}][v6]  |
| [wasi_snapshot_preview1.command.wasm][6] (adapter) | [{{ page.wasi-preview2 }}][v6]  |
| [wasi_snapshot_preview1.reactor.wasm][6] (adapter) | [{{ page.wasi-preview2 }}][v6]  |
| [wasi-tokio][6]                                    | [{{ page.wasi-preview2 }}][v6]  |

_Note: most of the WASI preview2 packages above are from a repository serving 
as a prototype development fork; the intention is to merge the prototype work 
to upstream repositories once it is ready._

### Tooling Libraries

The following table lists the versions of the component tooling library 
packages that are compatible:

| Package               | Version                          |
|:----------------------|:---------------------------------|
| [componentize-js][7]  | [{{ page.componentize-js }}][v7] |
| [wasm-compose][8]     | [{{ page.wasm-compose }}][v8]    |
| [wasm-encoder][9]     | [{{ page.wasmparser }}][v9]      |
| [wasm-metadata][10]   | [{{ page.wasm-metadata }}][v10]  |
| [wasmparser][11]      | [{{ page.wasmparser }}][v11]     |
| [wasmprinter][12]     | [{{ page.wasmprinter }}][v12]    |
| [wat][13]             | [{{ page.wat }}][v13]            |
| [wit-component][14]   | [{{ page.wit-component }}][v14]  |
| [wit-parser][15]      | [{{ page.wit-parser }}][v15]     |

### CLI Tools

The following table lists the versions of the CLI tools that are compatible:

| Tool                               | Version                           |
|:-----------------------------------|:----------------------------------|
| [cargo-component][16] (Rust)       | [{{ page.cargo-component }}][v16] |
| [jco][17] (JavaScript)             | [{{ page.jco }}][v17]             |
| [wasm-tools][18]                   | [{{ page.wasm-tools }}][v18]      |
| [wit-bindgen][19]                  | [{{ page.wit-bindgen }}][v19]     |

#### Producing Components

To get started with producing components with Rust, see the [cargo-component][16]
repository.

To get started with producing components with JavaScript, see the [JavaScript Component Tool][17]
repository.

For other languages, see the [wit-bindgen][19] repository.

### Feedback

If you encounter issues with the component model tooling, please file an issue 
in the repository for the tool you are using.

Additionally, many of the maintainers of the component model tooling are active 
on the [Bytecode Alliance Zulip][zulip]. Feel free to reach out there if you 
have questions or need help!

[proposal]: https://github.com/WebAssembly/component-model/
[wasi]: https://github.com/webAssembly/wasi
[zulip]: https://bytecodealliance.zulipchat.com/

[0]: https://github.com/bytecodealliance/wasmtime
[1]: https://github.com/bytecodealliance/wasmtime/tree/main/crates/wit-bindgen
[2]: https://github.com/bytecodealliance/wit-bindgen/tree/main/crates/c
[3]: https://github.com/bytecodealliance/wit-bindgen/tree/main/crates/go
[4]: https://github.com/bytecodealliance/wit-bindgen/tree/main/crates/rust
[5]: https://github.com/bytecodealliance/wit-bindgen/tree/main/crates/teavm-java
[6]: https://github.com/bytecodealliance/preview2-prototyping
[7]: https://github.com/bytecodealliance/componentize-js
[8]: https://github.com/bytecodealliance/wasm-tools/tree/main/crates/wasm-compose
[9]: https://github.com/bytecodealliance/wasm-tools/tree/main/crates/wasm-encoder
[10]: https://github.com/bytecodealliance/wasm-tools/tree/main/crates/wasm-metadata
[11]: https://github.com/bytecodealliance/wasm-tools/tree/main/crates/wasmparser
[12]: https://github.com/bytecodealliance/wasm-tools/tree/main/crates/wasmprinter
[13]: https://github.com/bytecodealliance/wasm-tools/tree/main/crates/wat
[14]: https://github.com/bytecodealliance/wasm-tools/tree/main/crates/wit-component
[15]: https://github.com/bytecodealliance/wasm-tools/tree/main/crates/wit-parser
[16]: https://github.com/bytecodealliance/cargo-component
[17]: https://github.com/bytecodealliance/jco
[18]: https://github.com/bytecodealliance/wasm-tools
[19]: https://github.com/bytecodealliance/wit-bindgen
[20]: https://github.com/bytecodealliance/jco/tree/main/packages/preview2-shim

[v0]: https://crates.io/crates/wasmtime/{{ page.wasmtime }}
[v1]: https://github.com/bytecodealliance/wasmtime/tree/{{ page.wasmtime }}
[v1]: https://crates.io/crates/wasmtime-wit-bindgen/{{ page.wasmtime-wit-bindgen }}
[v2]: https://crates.io/crates/wit-bindgen-c/{{ page.wit-bindgen-c }}
[v3]: https://crates.io/crates/wit-bindgen-go/{{ page.wit-bindgen-go }}
[v4]: https://crates.io/crates/wit-bindgen-rust/{{ page.wit-bindgen-rust }}
[v5]: https://crates.io/crates/wit-bindgen-teavm-java/{{ page.wit-bindgen-teavm-java }}
[v6]: https://github.com/bytecodealliance/preview2-prototyping/tree/{{ page.wasi-preview2 }}
[v7]: https://www.npmjs.com/package/@bytecodealliance/componentize-js/v/{{ page.componentize-js }}
[v8]: https://crates.io/crates/wasm-compose/{{ page.wasm-compose }}
[v9]: https://crates.io/crates/wasm-encoder/{{ page.wasm-encoder }}
[v10]: https://crates.io/crates/wasm-metadata/{{ page.wasm-metadata }}
[v11]: https://crates.io/crates/wasmparser/{{ page.wasmparser }}
[v12]: https://crates.io/crates/wasmprinter/{{ page.wasmprinter }}
[v13]: https://crates.io/crates/wat/{{ page.wat }}
[v14]: https://crates.io/crates/wit-component/{{ page.wit-component }}
[v15]: https://crates.io/crates/wit-parser/{{ page.wit-parser }}
[v16]: https://github.com/bytecodealliance/cargo-component/tree/{{ page.cargo-component }}
[v17]: https://www.npmjs.com/package/@bytecodealliance/jco/v/{{ page.jco }}
[v18]: https://crates.io/crates/wasm-tools/{{ page.wasm-tools }}
[v19]: https://crates.io/crates/wit-bindgen-cli/{{ page.wit-bindgen }}
[v20]: https://www.npmjs.com/package/@bytecodealliance/preview2-shim/v/{{ page.preview2-shim }}
