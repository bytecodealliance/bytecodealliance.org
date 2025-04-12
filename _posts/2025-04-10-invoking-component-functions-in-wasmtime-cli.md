---
title: "Running WebAssembly (Wasm) Components From the Command Line"
author: "Tim McCallum"
date: "2025-04-10"
github_name: "tpmccallum"
excerpt_separator: <!--end_excerpt-->
---
Wasmtime now supports invoking Wasm component exports directly from the command line with the new `--invoke` flag. 
This article walks through building a Wasm component in Rust and using `wasmtime run --invoke` to execute specific functions (enabling powerful workflows for scripting, testing, and integrating Wasm into modern development pipelines).
<!--end_excerpt-->

## The Evolution of Wasmtime's CLI

Wasmtime's `run` subcommand has traditionally excelled at running Wasm **modules**, whether in binary (`.wasm`) or text (`.wat`) format. In this article, we will create a Wasm **component** that exports a function and then demonstrate how to invoke the function using `wasmtime run --invoke`.

## Tooling & Dependencies

If you want to follow along, please install:

* [Rust](https://www.rust-lang.org/tools/install) (if you already have Rust installed, make sure you are on [the latest version](https://github.com/rust-lang/rust/releases) using `rustup update`),
* [`cargo`](https://crates.io/crates/cargo) via the `cargo install cargo` command (if already installed, please make sure you are on [the latest version](https://crates.io/crates/cargo)),
* [`cargo component`](https://crates.io/crates/cargo-component) via the `cargo install cargo-component` command (if already installed, please make sure you are on [the latest version](https://crates.io/crates/cargo-component)), and
* [`wasmtime` CLI](https://docs.wasmtime.dev/cli-install.html) (or use a [precompiled binary](https://docs.wasmtime.dev/cli-install.html#download-precompiled-binaries)). If already installed, ensure you are using [the latest version](https://github.com/bytecodealliance/wasmtime/releases).

You can check versions using the following commands:

```console
$ wasmtime --version
$ cargo --version
$ cargo component --version
$ rustc --version
```

For `cargo component` to generate a Wasm binary that is compatible with the WASI Preview 1 standard, we must explicitly `add` the `wasm32-wasip1` target. This ensures that our component adheres to WASI’s system interface for non-browser environments (e.g., file system access, networking):

```console
$ rustup target add wasm32-wasip1
```

## New Library

Let's start by creating a new Rust library that we will later convert to a Wasm component using `cargo component`:

```console
$ cargo component new --lib wasm_answer
$ cd wasm_answer
```

If you open the `Cargo.toml` file, you will notice that the `cargo component` command has automatically added some essential configurations.

The `wit-bindgen-rt` dependency (with the `["bitflags"]` feature) under `[dependencies]`, and the crate-type = `["cdylib"]` setting under the `[lib]` section.

Your `Cargo.toml` should now include these entries (as shown in the example below):

```toml
[package]
name = "wasm_answer"
version = "0.1.0"
edition = "2024"

[dependencies]
wit-bindgen-rt = { version = "0.41.0", features = ["bitflags"] }

[lib]
crate-type = ["cdylib"]

[package.metadata.component]
package = "component:wasm-answer"

[package.metadata.component.dependencies]
```

The directory structure of the `wasm_answer` example is automatically scaffolded out for us by `cargo component`:

```console
$ tree wasm_answer

wasm_answer
├── Cargo.lock
├── Cargo.toml
├── src
│   ├── bindings.rs
│   └── lib.rs
└── wit
    └── world.wit
```

Next, we add a `get_answer` function in the `src/lib.rs` file:

```rust
#[allow(warnings)]
mod bindings;

use bindings::Guest;

struct Component;

impl Guest for Component {
    fn get_answer() -> u32 {
        42
    }
}

bindings::export!(Component with_types_in bindings);
```

## WIT

Now, we need to open the `.wit` file and slightly modify it for our use case:

```console
$ vi wit/world.wit
```

Add the following content to the `answer.wit` file:

```wit
package component:wasm-answer;

world example {
    export get-answer: func() -> u32;
}
```

Now, let's create the Wasm component with our exported `get_answer()` function:

```console
$ cargo component build --target wasm32-wasip1
```

Our newly generated `.wasm` file now lives at the following location:

```console
$ file target/wasm32-wasip1/debug/wasm_answer.wasm
target/wasm32-wasip1/debug/wasm_answer.wasm: WebAssembly (wasm) binary module version 0x1000d
```

We can also use the `--release` option which optimises builds for production:

```console
$ cargo component build --target wasm32-wasip1 --release
```

If we check the sizes of the `debug` and `release`, we see a difference of `1.9M` and `16K`, respectively.

Debug:

```console
$ du -mh target/wasm32-wasip1/debug/wasm_answer.wasm
1.9M	target/wasm32-wasip1/debug/wasm_answer.wasm
```

Release:

```console
$ du -mh target/wasm32-wasip1/release/wasm_answer.wasm
16K	target/wasm32-wasip1/release/wasm_answer.wasm
```

## How Invoke Works: A Practical Example

Originally, the `wasmtime run` command would take one positional argument (the name of the module) and just run that `.wasm` file:

```console
$ wasmtime run foo.wasm
```

The `wasmtime run` command now accepts an optional `--invoke` argument, which can execute the name of an exported function that resides in the (`.wasm`) **component**:

```console
$ wasmtime run --invoke 'get-answer()' target/wasm32-wasip1/debug/wasm_answer.wasm
```

You will notice that the above example does not pass any arguments into the `get-answer()` function. Let's discuss how to represent the values passed into function calls in a structured way.

## Wasm Value Encoding (WAVE)

Transferring and invoking complex argument data via the command line is challenging, especially with Wasm components that use diverse value types. To simplify this, Wasm Value Encoding ([WAVE](https://github.com/bytecodealliance/wasm-tools/blob/main/crates/wasm-wave/README.md)) was introduced offering a concise way to represent structured values directly in the CLI.

[WAVE](https://github.com/bytecodealliance/wasm-tools/blob/main/crates/wasm-wave/README.md) provides a standard way to encode function calls and/or results. WAVE is a human-oriented text encoding of Wasm Component Model values and is designed to be consistent with the [WIT IDL format](https://github.com/WebAssembly/component-model/blob/main/design/mvp/WIT.md). 

Below we provide a few additional pointers for constructing your `wasmtime run --invoke` commands using WAVE.

## Quotes

The exported function's name and mandatory exported function's parentheses must all be enclosed in one set of single quotes, i.e. `'get-answer()'`.

The result from our correctly typed command above is as follows:

```console
42
```

## Parentheses

Parentheses after the exported function's name are mandatory. The presence of the parenthesis `()` signifies function invocation, as opposed to the function name just being referenced. If your function takes a string argument, ensure that you envelop your string in double quotes (**inside the parentheses**). For example:

```console
$ wasmtime run --invoke 'initialize("hello")' foo.wasm
```

If your exported function takes more than one argument, you will need to separate each argument with a single comma `,` as shown below:

```console
$ wasmtime run --invoke 'initialize("Pi", 3.14)' foo.wasm
$ wasmtime run --invoke 'add(1, 2)' foo.wasm
```

# Conclusion

## Wasm Modules vs. Wasm Components

Let's wrap this article up with a recap to crystallize your knowledge.

### Wasm Modules

If we are not using the component model and just creating a binary executable, we use a simple command like `wasmtime run foo.wasm` (**without** WAVE syntax) to execute our the binary executable. This typically applies to modules, which export a `_start` function, or reactor modules, which can optionally export the `wasi:cli/run` interface—standardized to enable consistent execution semantics. 

Example of running a Wasm **module** that exports a raw function directly:

```console
$ wasmtime run --invoke initialize foo.wasm
```

### Wasm Components

Now that Wasm is evolving beyond simple modules to embrace the Wasm Component Model, developers have more granular control over the execution and composition of individual components. Wasm component that use the WebAssembly Interface Types (WIT) can now use the `wasmtime run` command with the optional `--invoke` argument to call their exported function from their component (**with** [WAVE](https://github.com/bytecodealliance/wasm-tools/tree/main/crates/wasm-wave)).

Example of running a Wasm **component** that exports a function:

```console
$ wasmtime run --invoke 'add(1, 2)' foo.wasm
```

For more information, visit the [cli-options section](https://docs.wasmtime.dev/cli-options.html#run) of the Wasmtime documentation.

## Benefits and Usefulness

The addition of support for the run `--invoke` feature [for components](https://github.com/bytecodealliance/wasmtime/pull/10054) allows users to specify and execute exported functions from a Wasm component. This enables greater flexibility for testing, debugging, and integration. We now have the ability to perform the execution of arbitrary exported functions directly from the command line, this feature opens up a world of possibilities for integrating Wasm into modern development pipelines.

Here are some of the powerful workflows made possible by `--invoke`:

* Shell Scripting: Embed Wasm logic directly into Bash or Python scripts for seamless automation.
* CI/CD Pipelines: Validate components in GitHub Actions, GitLab CI, or other automation tools without embedding them in host applications.
* Cross-Language Testing: Quickly verify that interfaces match across implementations in Rust, JavaScript, and Python.
* Debugging: Inspect exported functions during development with ease.
* Microservices: Chain components in serverless workflows, such as compress → encrypt → upload, leveraging Wasm's modularity.

**This evolution from monolithic Wasm modules to composable, CLI-friendly components exemplifies the versatility and power of WebAssembly in real-world scenarios.**