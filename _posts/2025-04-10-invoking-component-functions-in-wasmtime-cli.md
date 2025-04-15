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

Wasmtime's `run` subcommand has traditionally supported running Wasm modules as well as invoking that **module**'s exported function. However, with the evolution of the Wasm Component Model, this article focuses on a newer capability; creating a component that exports a function and then demonstrating how to invoke that **component**'s exported function.

By the end of this article, you’ll be ready to create Wasm components and orchestrate their exported component functions to improve your workflow's efficiency and promote reuse. Potential examples include:

* Shell Scripting: Embed Wasm logic directly into Bash or Python scripts for seamless automation.
* CI/CD Pipelines: Validate components in GitHub Actions, GitLab CI, or other automation tools without embedding them in host applications.
* Cross-Language Testing: Quickly verify that interfaces match across implementations in Rust, JavaScript, and Python.
* Debugging: Inspect exported functions during development with ease.
* Microservices: Chain components in serverless workflows, such as compress → encrypt → upload, leveraging Wasm's modularity.

## Tooling & Dependencies

If you want to follow along, please install:

* [Rust](https://www.rust-lang.org/tools/install) (if you already have Rust installed, make sure you are on [the latest version](https://github.com/rust-lang/rust/releases)),
* [`cargo`](https://crates.io/crates/cargo) (if already installed, please make sure you are on [the latest version](https://crates.io/crates/cargo)),
* [`cargo component`](https://crates.io/crates/cargo-component) (if already installed, please make sure you are on [the latest version](https://crates.io/crates/cargo-component)), and
* [`wasmtime` CLI](https://docs.wasmtime.dev/cli-install.html) (or use a [precompiled binary](https://docs.wasmtime.dev/cli-install.html#download-precompiled-binaries)). If already installed, ensure you are using [the latest version](https://github.com/bytecodealliance/wasmtime/releases).

You can check versions using the following commands:

```console
$ rustc --version
$ cargo --version
$ cargo component --version
$ wasmtime --version
```

We must explicitly `add` the `wasm32-wasip2` target. This ensures that our component adheres to WASI’s system interface for non-browser environments (e.g., file system access, sockets, random etc.):

```console
$ rustup target add wasm32-wasip2
```

## Creating a New Wasm Component With Rust

Let's start by creating a new Wasm library that we will later convert to a Wasm component using `cargo component` and the `wasm32-wasip2` target:

```console
$ cargo component new --lib wasm_answer
$ cd wasm_answer
```

If you open the `Cargo.toml` file, you will notice that the `cargo component` command has automatically added some essential configurations.

The `wit-bindgen-rt` dependency (with the `["bitflags"]` feature) under `[dependencies]`, and the `crate-type = ["cdylib"]` setting under the `[lib]` section.

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

## WIT

If we open the `wit/world.wit` file, that `cargo component` created for us, we can see that `cargo component` generates a minimal `world.wit` that exports a raw function:

```wit
package component:wasm-answer;

/// An example world for the component to target.
world example {
    export hello-world: func() -> string;
}
```

We can simply adjust the `export` line (as shown below):

```wit
package component:wasm-answer;

/// An example world for the component to target.
world example {
    export get-answer: func() -> u32;
}
```

> **But, instead, let's use an interface to export our function!**

While the above approach works, the [recommended best practice](https://github.com/bytecodealliance/component-docs/blob/main/component-model/examples/tutorial/wit/adder/world.wit) is to **wrap related functions inside an interface, which you then export from your world**. This is more modular, extensible, and aligns with how the Wasm Interface Type (WIT) format is used in multi-function or real-world components. Let's update the `wit/world.wit` file as follows:

```wit
package component:wasm-answer;

interface answer {
    get-answer: func() -> u32;
}

world example {
    export answer;
}
```

Next, we update our `src/lib.rs` file accordingly, by pasting in the following Rust code:

```rust
#[allow(warnings)]
mod bindings;

use bindings::exports::component::wasm_answer::answer::Guest;

struct Component;

impl Guest for Component {
    fn get_answer() -> u32 {
        42
    }
}

bindings::export!(Component with_types_in bindings);
```

Now, let's create the Wasm component with our exported `get_answer()` function:

```console
$ cargo component build --target wasm32-wasip2
```

Our newly generated `.wasm` file now lives at the following location:

```console
$ file target/wasm32-wasip2/debug/wasm_answer.wasm
target/wasm32-wasip2/debug/wasm_answer.wasm: WebAssembly (wasm) binary module version 0x1000d
```

We can also use the `--release` option which optimises builds for production:

```console
$ cargo component build --target wasm32-wasip2 --release
```

If we check the sizes of the `debug` and `release`, we see a difference of `2.1M` and `16K`, respectively.

Debug:

```console
$ du -mh target/wasm32-wasip2/debug/wasm_answer.wasm
2.1M	target/wasm32-wasip2/debug/wasm_answer.wasm
```

Release:

```console
$ du -mh target/wasm32-wasip2/release/wasm_answer.wasm
16K	target/wasm32-wasip2/release/wasm_answer.wasm
```

## How Invoke Works: A Practical Example

The `wasmtime run` command can take one positional argument and just run a `.wasm` or `.wat` file:

```console
$ wasmtime run foo.wasm
$ wasmtime run foo.wat
```

### Invoke: Wasm Modules

In the case of a Wasm **module** that exports a raw function directly, the `run` command accepts an optional `--invoke` argument, which is the name of an exported raw function (of the **module**) to run:

```console
$ wasmtime run --invoke initialize foo.wasm
```

### Invoke: Wasm Components

In the case of a Wasm **component** that uses typed interfaces (defined [in WIT](https://component-model.bytecodealliance.org/design/wit.html), in concert with [the Component Model](https://component-model.bytecodealliance.org/design/components.html)), the `run` command now also accepts the optional `--invoke` argument for calling an exported function of a **component**.

However, the calling of an exported function of a **component** uses [WAVE](https://github.com/bytecodealliance/wasm-tools/tree/a56e8d3d2a0b754e0465c668f8e4b68bad97590f/crates/wasm-wave#readme)(a human-oriented text encoding of Wasm Component Model values). For example:

```console
$ wasmtime run --invoke 'initialize()' foo.wasm
```

> You will notice the different syntax of `initialize` versus `'initialize()'` when referring to a **module** versus a **component**, respectively.

Back to our `get-answer()` example:

```console
$ wasmtime run --invoke 'get-answer()' target/wasm32-wasip2/debug/wasm_answer.wasm
42
```

You will notice that the above `get-answer()` function call does not pass in any arguments. Let's discuss how to represent the arguments passed into function calls in a structured way (using WAVE).

#### Wasm Value Encoding (WAVE)

Transferring and invoking complex argument data via the command line is challenging, especially with Wasm components that use diverse value types. To simplify this, Wasm Value Encoding ([WAVE](https://github.com/bytecodealliance/wasm-tools/blob/main/crates/wasm-wave/README.md)) was introduced; offering a concise way to represent structured values directly in the CLI. 

WAVE provides a standard way to encode function calls and/or results. WAVE is a human-oriented text encoding of Wasm Component Model values; designed to be consistent with the [WIT IDL format](https://github.com/WebAssembly/component-model/blob/main/design/mvp/WIT.md). 

Below are a few additional pointers for constructing your `wasmtime run --invoke` commands using WAVE.

#### Quotes

As shown above, the component's exported function name and mandatory parentheses are contained in one set of single quotes, i.e., `'get-answer()'`:

```console
$ wasmtime run --invoke 'get-answer()' target/wasm32-wasip2/release/wasm_answer.wasm
```

The result from our correctly typed command above is as follows:

```console
42
```

#### Parentheses

Parentheses after the exported function's name are mandatory. The presence of the parenthesis `()` signifies function invocation, as opposed to the function name just being referenced. If your function takes a string argument, ensure that you contain your string in double quotes (inside the parentheses). For example:

```console
$ wasmtime run --invoke 'initialize("hello")' foo.wasm
```

If your exported function takes more than one argument, ensure that each argument is separated using a single comma `,` as shown below:

```console
$ wasmtime run --invoke 'initialize("Pi", 3.14)' foo.wasm
$ wasmtime run --invoke 'add(1, 2)' foo.wasm
```

## Recap: Wasm Modules versus Wasm Components

Let's wrap this article up with a recap to crystallize your knowledge.

### Earlier Wasmtime Run Support for Modules

If we are not using the Component Model and just creating a module, we use a simple command like `wasmtime run foo.wasm` (**without** WAVE syntax). This approach typically applies to modules, which export a `_start` function, or reactor modules, which can optionally export the `wasi:cli/run` interface—standardized to enable consistent execution semantics. 

Example of running a Wasm **module** that exports a raw function directly:

```console
$ wasmtime run --invoke initialize foo.wasm
```

### Wasmtime Run Support for Components

As Wasm evolves with the Component Model, developers gain fine-grained control over component execution and composition. Components using WIT can now be run with `wasmtime run`, using the optional `--invoke` argument to call exported functions (**with** [WAVE](https://github.com/bytecodealliance/wasm-tools/tree/main/crates/wasm-wave)).

Example of running a Wasm **component** that exports a function:

```console
$ wasmtime run --invoke 'add(1, 2)' foo.wasm
```

For more information, visit the [cli-options section](https://docs.wasmtime.dev/cli-options.html#run) of the Wasmtime documentation.

## Benefits and Usefulness

The addition of support for the run `--invoke` feature [for components](https://github.com/bytecodealliance/wasmtime/pull/10054) allows users to specify and execute exported functions from a Wasm component. This enables greater flexibility for testing, debugging, and integration. We now have the ability to perform the execution of arbitrary exported functions directly from the command line, this feature opens up a world of possibilities for integrating Wasm into modern development pipelines.

**This evolution from monolithic Wasm modules to composable, CLI-friendly components exemplifies the versatility and power of Wasm in real-world scenarios.**