---
title: "Implementing a WASI Proposal in Wasmtime: wasi-nn"
author: "Andrew Brown"
github_name: abrown
---

In a previous post, [Machine Learning in WebAssembly: Using wasi-nn in
Wasmtime](https://bytecodealliance.org/articles/using-wasi-nn-in-wasmtime), we described the
[wasi-nn] specification and a user-level view of its usage in Wasmtime. In this post, we dive into
the details of implementing the proposal using [wasi-nn] as an example. If you are interested in
designing new WASI specifications and making them work--especially in the Wasmtime engine--you may
find this post useful.

Others have done related work: Aaron Turner has described how to [build graphical applications with
Wasmer and WASI](https://medium.com/wasmer/wasmer-io-devices-announcement-6f2a6fe23081) and Radu
Matei has written about [adding a new WASI syscall in
Wasmtime](https://radu-matei.com/blog/adding-wasi-syscall). This guide, unlike Aaron's article, will
focus on integration with Wasmtime, a Rust project, so the following sections will be Rust-focused
and Wasmtime-specific. If you squint, the general approach will be similar for other Wasm runtimes
(e.g. NodeJS) but the details may look substantially different. This guide will build on Radu's
article, encompassing the end-to-end process of a WASI proposal and diving into more detail. The
process involves several steps:
 - design the WASI API
 - provide a backing implementation (in this case, by porting an ML framework to Rust)
 - implement the WITX specification with the backing implementation
 - expose the implementation in the runtime
 - optionally, provide bindings to compile programs to the specification (in this case, from Rust to wasi-nn)



### WASI API

WASI exists to expose system interfaces to WebAssembly programs. It divides its API surface into
separate [proposals](https://github.com/WebAssembly/WASI/blob/master/docs/Proposals.md), organized
by theme into proposals such as filesystem, IO, clocks, crypto, etc. Our proposal, [wasi-nn], is a
more exotic addition to this list. We discuss the motivation more in [the previous
post](https://bytecodealliance.org/articles/using-wasi-nn-in-wasmtime), but briefly, machine
learning is a popular feature that benefits from a system interface and, until wasi-nn, WebAssembly
had no access to the hardware's peak ML performance.

WASI proposals follow a [process](https://github.com/WebAssembly/WASI/blob/master/docs/Process.md)
through several stages. The first step involves presenting an idea (half-baked even!) to the WASI
subgroup. This is usually enough to reach stage 0.

Eventually the proposal "champion," in WASI terms, must define the interface. To do so, the WASI
repository defines the WITX language and associated tools. For [wasi-nn], we defined several new
types (e.g. the [`tensor`
struct](https://github.com/WebAssembly/wasi-nn/blob/f72b983c4cc91ac575af6babc57b5bccb7db7ba9/phases/ephemeral/witx/wasi_ephemeral_nn.witx#L56-L68),
the [`tensor_type` enum](https://github.com/WebAssembly/wasi-nn/blob/f72b983c4cc91ac575af6babc57b5bccb7db7ba9/phases/ephemeral/witx/wasi_ephemeral_nn.witx#L37-L44), etc.) along with methods like [`set_input`](https://github.com/WebAssembly/wasi-nn/blob/f72b983c4cc91ac575af6babc57b5bccb7db7ba9/phases/ephemeral/witx/wasi_ephemeral_nn.witx#L131-L142) to
pass tensors into the inference engine:

```
  ;;; Define the inputs to use for inference.
  (@interface func (export "set_input")
    (param $context $graph_execution_context)
    ;;; The index of the input to change.
    (param $index u32)
    ;;; The tensor to set as the input.
    (param $tensor $tensor)

    (result $error $nn_errno)
  )
```

The WASI repository provides [tools](https://github.com/WebAssembly/WASI/tree/master/tools/witx)
that parse the WITX specification and generate human-readable documentation:

```
# Create or modify a witx file in-tree, then:
cd tools/witx
cargo run --example witx repo-docs
```

The output for wasi-nn is available [here](https://github.com/WebAssembly/wasi-nn/blob/master/phases/ephemeral/docs.md).



### Backing Implementation

Once the API is defined in WITX, we must build (or find) an implementation of the API. If you
already have an implementation for your API, you can safely jump to the next section. If not, this
section describes how we exposed OpenVINO&trade; in Rust.

We decided to use OpenVINO&trade; to implement wasi-nn, since:
 1. it can execute models on various devices (e.g. not solely the CPU) and
 2. it has received considerable attention to improve inference performance on Intel CPUs (full
    disclosure: I work for Intel). 

The wasi-nn API is flexible enough to accept different, even multiple, backing implementations, so
choosing OpenVINO&trade; here does not prohibit similar work using TensorFlow or WinML--in fact,
that work would be beneficial to prove out wasi-nn's generality.

Since OpenVINO&trade; does not have Rust bindings, I implemented both
[`openvino-sys`](https://crates.io/crates/openvino-sys) and
[`openvino`](https://crates.io/crates/openvino) and published the crates. Rust bindings (allowing
calls from Rust to the backing implementation) are necessary for integration with Wasmtime; other
Wasm engines will have different language requirements.

Note: Using OpenVINO&trade; means that the models accepted by this implementation must be in
OpenVINO&trade; IR format. This format uses two files for encoding an ML graph: a graph description
XML file and a binary file with the weights. The OpenVINO&trade; IR is not the most common encoding
format out in the wild, so OpenVINO&trade; provides a model-optimizer tool to convert models from
other formats (e.g. Caffe, TensorFlox, ONNX) to OpenVINO&trade; IR. If you are interested in
executing your model with this implementation of wasi-nn, see the [model-optimizer
documentation](https://docs.openvinotoolkit.org/latest/openvino_docs_MO_DG_prepare_model_Prepare_Trained_Model.html)
and my [test
example](https://github.com/intel/openvino-rs/tree/main/crates/openvino/tests/fixtures). 



### Implement WITX with a Backing Implementation

Now that we have a WITX specification and a backing implementation (e.g. `openvino`) we can attempt
to bind them together using [`wiggle`](https://crates.io/crates/wiggle). The __guest__, a Wasm
module, will write code using the API exposed in the WITX file and the __host__, Wasmtime in our
case, provides the implementation. The host code is contained in a new crate, `crates/wasi-nn`, to
which I immediately added my version of the WASI spec (the one containing the wasi-nn proposal) as a
Git submodule:

```sh
cd crates/wasi-nn
git submodule add https://github.com/abrown/
```

Then, in my crate's
[`build.rs`](https://github.com/bytecodealliance/wasmtime/blob/e09b9400f8434907894949e37f791fbd507d57b3/crates/wasi-nn/build.rs),
I set up an environment variable to inform `wiggle` of the location of the WITX files:

```rust
let wasi_root = PathBuf::from("./spec").canonicalize().unwrap();
println!("cargo:rustc-env=WASI_ROOT={}", wasi_root.display());
```

I then used `wiggle::from_witx` to bind together the WITX specification to the host structures it
expects me to create (`WasiNnCtx` and `WasiNnError`):

```rust
wiggle::from_witx!({
    witx: ["$WASI_ROOT/phases/ephemeral/witx/wasi_ephemeral_nn.witx"],
    ctx: WasiNnCtx,
    errors: { errno => WasiNnError }
});
```

[`WasiNnCtx`](https://github.com/bytecodealliance/wasmtime/blob/e09b9400f8434907894949e37f791fbd507d57b3/crates/wasi-nn/src/ctx.rs#L96)
should contain any state necessary for implementing the proposal; e.g., we return `u32` handles to
the loaded graphs and execution contexts, so `WasiNnCtx` maintains a hash map of handles to these
structures. `WasiNnError` is a wrapper structure for the errors that the implementation could
return. `wiggle::from_witx` will rather abruptly alert you of any missing implementations. For
example, you will see in `witx.rs` how we must implement the `GuestErrorConversion` and
`UserErrorConversion` traits for our context, `WasiNnCtx`; these translate errors (from the guest
and from our implementation, respectively) into error codes that user of our WASI module can
interact with (all WASI errors are currently encoded as integers). I found it quite helpful to use
the `cargo-expand` CLI tool to visualize what `wiggle` was doing for me:

```sh
$ cargo expand witx
```

Redacting the macro expansions to see the overall structure, you may notice that `wiggle` generates
Rust types from our WITX specification:

```rust
pub mod types {
    ...
    pub enum Errno { ...
    pub type TensorDimensions<'a> = wiggle::GuestPtr<'a, [u32]>; ...
    pub enum TensorType { ...
    pub struct Graph(u32); ...
}
```

Then it generates wrapper functions that will type-convert, log, etc. guest-side calls (e.g. from
Wasm) and proxy them into the `WasiEphemeralNn` trait, which it also generates. The
`WasiEphemeralNn` trait is important because that is where we tie our backing implementation to the
context:

```rust
pub mod wasi_ephemeral_nn {
    ...
    pub fn load(ctx: &WasiNnCtx, memory: &dyn wiggle::GuestMemory, builder_ptr: i32..., builder_len: i32, encoding: i32, target: i32, graph_ptr: i32) -> i32 { ...
    pub fn init_execution_context(ctx: &WasiNnCtx, memory: &dyn wiggle::GuestMemory, graph: i32, context_ptr: i32) -> i32 { ...
    pub fn set_input(ctx: &WasiNnCtx, memory: &dyn wiggle::GuestMemory, context: i32, index: i32, tensor_ptr: i32) -> i32 { ...
    pub fn get_output(ctx: &WasiNnCtx, memory: &dyn wiggle::GuestMemory, context: i32, index: i32, out_buffer: i32, out_buffer_max_size: i32, bytes_written_ptr: i32) -> i32 { ...
    pub fn compute(ctx: &WasiNnCtx, memory: &dyn wiggle::GuestMemory, context: i32) -> i32 {
    ...
    pub trait WasiEphemeralNn {
        fn load<'a>(&self, builder: &GraphBuilderArray<'a>, encoding: GraphEncoding, target: ExecutionTarget) -> Result<(Graph), super::WasiNnError>;
        fn init_execution_context(&self, graph: Graph) -> Result<(GraphExecutionContext), super::WasiNnError>;
        fn set_input<'a>(&self, context: GraphExecutionContext, index: u32, tensor: &Tensor<'a>) -> Result<(), super::WasiNnError>;
        fn get_output<'a>(&self, context: GraphExecutionContext, index: u32, out_buffer: &wiggle::GuestPtr<'a, u8>, out_buffer_max_size: Size) -> Result<(Size), super::WasiNnError>;
        fn compute(&self, context: GraphExecutionContext) -> Result<(), super::WasiNnError>;
    }
}
```

Now that we can see the types and traits that `wiggle` has generated for us, we can actually
implement wasi-nn. In
[`impl.rs`](https://github.com/bytecodealliance/wasmtime/blob/e09b9400f8434907894949e37f791fbd507d57b3/crates/wasi-nn/src/impl.rs),
I use the `WasiNnCtx` structure which I control along with imported functions from my backing
implementation, `openvino`, to implement `WasiEphemeralNn`:

```rust
impl<'a> WasiEphemeralNn for WasiNnCtx {
    fn load<'b>(&self, builders: &GraphBuilderArray<'_>, encoding: GraphEncoding, target: ExecutionTarget) -> Result<Graph> {
        if encoding != GraphEncoding::Openvino {
            return Err(UsageError::InvalidEncoding(encoding).into());
        }
        if builders.len() != 2 {
            return Err(UsageError::InvalidNumberOfBuilders(builders.len()).into());
        }
...
```

For primitive types and enumerations (e.g. `GraphEncoding` above), this is quite simple, but any
kind of buffer-passing (e.g. `GraphBuilderArray` above) is tricky across the guest-host divide. To
cross this divide, `wiggle` exposes structures that allow the host to "see" and alter the guest
code's memory (see [`GuestPtr`](https://docs.rs/wiggle/0.20.0/wiggle/struct.GuestPtr.html),
[`GuestSlice`](https://docs.rs/wiggle/0.20.0/wiggle/struct.GuestSlice.html), e.g.). I highly
recommend reading through the documentation to these host-to-guest structures, since their misuse
could result in errors or unsafe code.



### Expose the Implementation in the Runtime

At this point, we have implemented the wasi-nn specification but we must inform Wasmtime that it
should actually use our implementation when it executes Wasm modules. To do this, we use a
Wasmtime-specific macro to generate implementation-to-runtime binding code:

```rust
wasmtime_wiggle::wasmtime_integration!({:
    target: witx,
    witx: ["$WASI_ROOT/phases/ephemeral/witx/wasi_ephemeral_nn.witx"],
    ctx: WasiNnCtx,
    modules: {
        wasi_ephemeral_nn => {
          name: WasiNn,
          docs: "An instantiated instance of the wasi-nn exports.",
          function_override: {}
        }
    },
    missing_memory: { witx::types::Errno::MissingMemory },
});
```

If we glance again at the output of `cargo expand`, we now see a new generated structure, `WasiNn`:

```rust
...
pub struct WasiNn {
    pub load: wasmtime::Func,
    pub init_execution_context: wasmtime::Func,
    pub set_input: wasmtime::Func,
    pub get_output: wasmtime::Func,
    pub compute: wasmtime::Func,
}
...
impl WasiNn {
    ...
    pub fn add_to_linker(&self, linker: &mut wasmtime::Linker) -> anyhow::Result<()> { ...
}
```

`WasiNn::add_to_linker` is used when we want to expose wasi-nn functionality to the user's Wasm
modules--using Wasmtime's `Linker`, we instantiate `WasiNn` and add it to the functions available to
import:

```rust
use wasmtime::{Linker, Module, Store};
use wasmtime_wasi_nn::{WasiNn, WasiNnCtx};
// ...
let store = Store::default();
let mut linker = Linker::new(&store);
let wasi_nn = WasiNn::new(&store, WasiNnCtx::new()?);
wasi_nn.add_to_linker(&mut linker)?;
let module = Module::from_file(store.engine(), file)?;
linker.module("", &module)?;
linker.get_default("")?.get0::<()>()?()?;
```

This section and its immediate predecessor are the most challenging: any new WASI proposal must
first bind the WITX specification to an implementation and then implementation to the runtime, and
to do so concretely in Wasmtime we:
1. use `wiggle::from_witx!` to generate the necessary types and traits
2. fill in the implementation trait (i.e. `WasiEphemeralNn`) with our implementation code (i.e. a
   combination of `WasiNnCtx` and `openvino`)
3. use `wasmtime_wiggle::wasmtime_integration!` to generate the linking code to the runtime (i.e. `WasiNn::add_to_linker`)
4. configure the runtime to import our new functionality

The full code described in this section is available
[here](https://github.com/bytecodealliance/wasmtime/tree/main/crates/wasi-nn).



### Provide WITX Bindings: wasi-nn-bindings

In order to compile a program to a wasi-nn Wasm binary, the programmer must call the wasi-nn API
functions. In certain languages (e.g. Rust), this may be un-ergonomic. Using
[`witx-bindgen`](https://github.com/bytecodealliance/wasi/tree/main/crates/witx-bindgen) I generated
Rust bindings for wasi-nn that are available [here](https://github.com/bytecodealliance/wasmtime/tree/main/crates/wasi-nn/examples/wasi-nn-rust-bindings). This enables the user to import a Rust-friendly wrapper of our API and write Rust code against it:

```rust
use wasi_nn;

unsafe {
    wasi_nn::load(&[&xml.into_bytes(), &weights], wasi_nn::GRAPH_ENCODING_OPENVINO, wasi_nn::EXECUTION_TARGET_CPU)
    .unwrap()
}
```

Unfortunately, the output of `witx-bindgen` is not perfect (see, e.g., [this
issue](https://github.com/bytecodealliance/wasi/issues/47) about pointers) but the resulting wrapper
does eliminate some boilerplate. As an aside on toolchain ease-of-use, it would be quite nice if the
WITX tooling automatically generated these bindings for us; bonus points would be for this automatic
generation to occur for several languages (e.g. C, Rust).



### Conclusion

This post walked through the process of implementing a new WASI proposal using wasi-nn as an
example--from WITX specification to implementation in Wasmtime. Having walked this process, here are
some possible improvements:
 - since working with macros is not particularly easy, offering a way to statically generate the
   glue code would benefit larger proposals (a la `bindgen`)
 - the `wiggle` documentation needs to continue to improve--some examples would be highly
   appreciated, as well as "do not do this"-style warnings
 - some portions of this article should be adapted for the [Wasmtime
   book](https://bytecodealliance.github.io/wasmtime)

If you would like to contribute to this effort or implement your own WASI proposal, there is help
available: open an issue or pull request on the [WASI](https://github.com/WebAssembly/wasi) or
[Wasmtime](https://github.com/bytecodealliance/wasmtime) repositories. Also, someone related to the
project is usually online on the [BytecodeAlliance Zulip
channel](https://bytecodealliance.zulipchat.com)

Special thanks to [Pat Hickey](https://github.com/pchickey) for answering all my questions about
WITX, `wiggle`, and Wasmtime! Also, thanks to [Mingqiu Sun](https://github.com/mingqiusun) and
[Johnnie Birch](https://github.com/jlb6740) for reviewing drafts of this article.



[wasi-nn]: https://github.com/WebAssembly/wasi-nn
