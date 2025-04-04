---
title: "Running WebAssembly (Wasm) Components From the Command Line"
author: "Liang He"
date: "2025-04-10"
github_name: "tpmccallum"
excerpt_separator: <!--end_excerpt-->
---
Wasmtime now supports invoking Wasm component exports directly from the command line with the new `--invoke` flag. This article walks through building a Wasm component in Rust, writing a WIT interface, and using `wasmtime run --invoke` to execute specific functions (enabling powerful workflows for scripting, testing, and integrating Wasm into modern development pipelines).
<!--end_excerpt-->

## The Evolution of Wasmtime's CLI

Wasmtime's `run` subcommand has traditionally excelled at running Wasm modules, whether in binary (`.wasm`) or text (`.wat`) format. In this article, we will create a Wasm component that exports a function and then demonstrate how to invoke the function using `wasmtime run --invoke`.

## Housekeeping

If you want to follow along, please install:

* [Rust](https://www.rust-lang.org/tools/install) (if you already have Rust installed, make sure you are on [the latest version](https://github.com/rust-lang/rust/releases) using `rustup update`), and
* Cargo Component via the `cargo install cargo-component` command (if already installed, please make sure you are on [the latest version](https://github.com/bytecodealliance/cargo-component/releases)), and
* [Wasmtime](https://docs.wasmtime.dev/cli-install.html) or download a [Wasmtime precompiled binary](https://docs.wasmtime.dev/cli-install.html#download-precompiled-binaries). (If you already have wasmtime installed, please make sure you are using [the latest version](https://github.com/bytecodealliance/wasmtime/releases).)

You can check versions using the following commands:

```bash
wasmtime --version
cargo component --version
rustc --version
```

## New Library

Let's start by creating a new Rust library that we will later convert to a Wasm component using `cargo component`:

```bash
cargo new --lib wasm-answer
cd wasm-answer
```

Install `wit-bindgen`:

```bash
cargo add wit-bindgen
```

If you open the `Cargo.toml` file, you will notice that the `wit-bindgen` dependency has been automatically added for us (by the above `cargo add command`). While you have the `Cargo.toml` open, please go ahead and add the following:

```toml
[lib]
crate-type = ["cdylib"]
```

The `Cargo.toml` file will look something like the following:

```toml
[package]
name = "wasm-answer"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
wit-bindgen = "0.41.0"
```

We need to set a special target that allows us to leverage the Wasm component model via `cargo component`. So please go ahead and add the Wasm target shown below and also set your default Rust toolchain to `nightly`:

```bash
rustup toolchain install nightly
rustup default nightly
rustup target add wasm32-wasip1
```

## WIT

Now, let's create a hand-written `.wit` file. Open a new file `answer.wit` in and new directory `wit`:

```bash
mkdir wit
vi wit/answer.wit
```

Add the following content to the `answer.wit` file:

```wit
package example:answer;
world answer-world {
    export get-answer: func() -> u32;
}
```

Your directory structure should look like the following:

```bash
tree .
.
├── Cargo.lock
├── Cargo.toml
├── src
│   └── lib.rs
└── wit
    └── answer.wit
```

Next, we write the logic that supports our WIT. Open the `src/lib.rs` file and add the following content:

```rust
wit_bindgen::generate!({
    world: "answer-world",  
    path: "wit/answer.wit",
});

struct Answer;
impl Guest for Answer {
    fn get_answer() -> u32 {
        42
    }
}
export!(Answer);
```

Now, let's create the Wasm component with the exported function:

```bash
cargo component build --target wasm32-wasip1
```

If we take another look at our directory structure, we will see that cargo component has automatically generated `bindings.rs` and that we now have a target directory that contains `wasm32-wasip1` path. This is where our our `.wasm` file now lives:

```bash
ls target/wasm32-wasip1/debug/wasm_answer.wasm 
```

## Default Entry Point vs. Exported Function

If we were not using the component model and just creating binary executable, we could use a simple command like `wasmtime run foo.wasm` to execute our code.

But in this case, we are making the point that Wasm has evolved beyond simple modules to embrace the Wasm Component Model. Developers need more granular control over the execution and composition of components. The benefits are code reuse and cross-language sharing. For example, Rust, Javascript, and Python logic can all interoperate when the explicit interfaces are defined using WIT. For example, [seamlessly interoperable compression tasks across native C++, Rust, and also in a Wasm runtime](https://medium.com/wasm/wasm-component-model-seamless-compression-c-rust-and-wasm-3b8d52ed8b31).

## Invoking Exported Functions

The addition of the `--invoke` feature (within the `wasmtime run` subcommand) allows users to specify an exported function to execute, complete with arguments, directly from the command line interface (CLI) terminal. Being able to invoke functions in the CLI is a huge step forward for not only executing Wasm via consoles or Bash scripting but will also play a big role in testing, debugging, and integrating Wasm components into workflows without having to embed them into a host application during development.

## How Invoke Works: A Practical Example

Originally, the `wasmtime run` command would take one positional argument (the name of the module) and just run that `.wasm` file:

```bash
wasmtime run foo.wasm
```

The `wasmtime run` command now accepts an optional `--invoke` argument, which can execute the name of an exported function that resides in the (`.wasm`) module:

```bash
wasmtime run --invoke "get-answer()" target/wasm32-wasip1/debug/wasm_answer.wasm
```

## Wasm Value Encoding (WAVE)

Invoke leverages `wasm-wave` as a standard way to encode function calls and/or results. WAVE is a human-oriented text encoding of Wasm Component Model values and is designed to be consistent with the [WIT IDL format](https://github.com/WebAssembly/component-model/blob/main/design/mvp/WIT.md). Here are a few pointers for constructing your `wasmtime run --invoke` commands using WAVE.

## Parentheses

Parentheses after the exported function's name are mandatory. The presence of the parenthesis `()` signifies function invocation, as opposed to the function name just being referenced.

## Double Quotes

The exported function's name and mandatory exported function's parentheses must all be enclosed in one set of double quotes, i.e. `"get-answer()"`.

The result from our correctly typed command above is as follows:

```bash
42
```

Note: If your function takes a string argument, ensure that you use escaped double quotes inside the parentheses. For example:

```bash
wasmtime run - invoke "initialize(\"hello\")" foo.wasm
```

And lastly, if your exported function takes more than one argument, you will need to separate each argument with a single comma `,` as shown below:

```bash
wasmtime run - invoke "initialize(\"Pi\", 3.14)" foo.wasm
wasmtime run - invoke "add(1, 2)" foo.wasm
```

With the ability to invoke Wasm component exports directly from the command line, developers unlock powerful workflows:

* Shell Scripting: Embedding Wasm logic in Bash/Python scripts,
* CI/CD Pipelines: Validating components in GitHub Actions or GitLab CI,
* Cross-Language Testing: Quickly verifying that interfaces match across different language implementations (Rust/JS/Python),
* Debugging: Quickly inspect exports during development, and
* Microservices: Chaining components in serverless workflows (e.g., compress → encrypt → upload).

This evolution from monolithic modules to composable, CLI-friendly components is a big leap forward.