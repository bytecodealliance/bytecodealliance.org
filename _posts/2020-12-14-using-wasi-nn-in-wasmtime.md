---
title: "Machine Learning in WebAssembly: Using wasi-nn in Wasmtime"
author: "Andrew Brown"
github_name: abrown
---

The [wasi-nn proposal][wasi-nn] allows WebAssembly programs to access host-provided machine learning
(ML) functions. This post will explain the motivation for wasi-nn, a brief look at the
specification, and how to use it in Wasmtime to do machine learning inference. You may find this
post interesting if you want to execute ML inference in a standalone WebAssembly runtime (i.e. not
in a browser) or if you would like to understand the process for implementing new WASI
specifications. In a follow-on post (to be released soon), I will explain how I implemented the
wasi-nn proposal in [Wasmtime](https://wasmtime.dev/) using
[OpenVINO&trade;](https://docs.openvinotoolkit.org/latest/index.html).



### Motivation

First, why design and implement a WASI ML specification? There are efforts to port ML frameworks to
Wasm SIMD (e.g. TensorFlow), but these are hampered by the "lowest-common denominator" approach of
Wasm and Wasm SIMD: Wasm specifications must consider the limitations of all CPU architectures and
therefore cannot take advantage of specialized instructions in any single architecture (in our case,
x86). For peak performance, another approach was needed: the implementation described here uses
OpenVINO&trade; for peak performance on x86 architectures and extending support to other
architectures is completely possible.

Missing CPU instructions are not the only problem: many ML models take advantage of auxiliary
processing units (e.g. GPUs, TPUs). It is [difficult to
see](https://github.com/WebAssembly/design/issues/273) how Wasm could compile to such devices (at
least currently) so some other way of using those devices is necessary--a higher-level API like
wasi-nn provides a way to use them.

Finally, deploying ML inference to Wasm runtimes is difficult enough without adding the complexity
of a translation to a lower-level abstraction. So wasi-nn allows programmers to deploy models
directly, shifting the work of compiling the models for the appropriate device to other tools (e.g.
OpenVINO&trade;, TF)--the wasi-nn specification is agnostic to which one is used. If at some point a
Wasm proposal were available that made it possible to use a machine's full ML performance (e.g.
flexible-vectors, gpu), it is conceivable that wasi-nn could be implemented "under the hood" with
only Wasm primitives--until that time, ML programmers will still be able to execute inference using
the approach described here and should see minimal changes if such a switch were to happen.

In summary, something like wasi-nn is needed because:
 - Wasm is unlikely to expose instructions necessary for peak ML performance in the near future
 - Wasm is unlikely to compile to non-CPU architectures any time soon
 - A high-level API is helpful and, if the above become true, wasi-nn could be re-implemented on top
   of them



### Specification 

When we began investigating how to expose ML functionality to Wasm programs, we considered
[WebNN](https://webmachinelearning.github.io/webnn). WebNN is a draft browser API with a similar
goal--to provide ML functionality to users. Keeping wasi-nn's API surface close to WebNN's seemed a
worthy goal: ideally, users could compile Wasm programs using ML features that could execute in
either environment (browser or standalone Wasm runtimes).

Unfortunately, WebNN (like [Android's NDK](https://developer.android.com/ndk/guides/neuralnetworks))
allows users to craft the ML computation graph node-by-node--we call this a "graph builder" API.
This means that the API must expose nodes for every mathematical operation. Since the ML ecosystem
is still growing, the set of operations is not complete. By some accounts, the number of operations
in TF is growing at 20% per year.

To avoid this, we chose to specify wasi-nn as a "graph loader" API (at least initially, more below).
Like Microsoft's WinML API, wasi-nn allows users to ["load, bind, and
evaluate"](https://docs.microsoft.com/en-us/windows/ai/windows-ml/integrate-model) models. But
whereas WinML expects the model to be packaged in ONNX format, wasi-nn is format-agnostic: it
assumes models can be one or more blobs of bytes that are passed along unchanged to the
implementation which is determined by a `$graph_encoding` enumeration. This makes it possible to
implement wasi-nn with different underlying implementations: it could pass ONNX models on to a WinML
backend, TF models on to a TF backend, OpenVINO&trade; models to an OpenVINO&trade; backend, etc.

The decision to specify wasi-nn as a "graph loader" API does not preclude a "graph builder" addition
in the future. But initially, while the set of operations stabilizes, the "graph loader" approach
has the least churn for ML developers targeting standalone Wasm. (In fact, if WebNN were to add a
"loader" API, the interoperability gap would be considerably smaller--with a polyfill, wasi-nn
programs could run in the browser using WebNN).

As it stands today, the wasi-nn specification expects users to:
 - [`load`] a model using one or more opaque byte arrays
 - [`init_execution_context`] and bind some tensors to it using [`set_input`]
 - [`compute`] the ML inference using the bound context
 - retrieve the inference result tensors using [`get_output`]

[`load`]: https://github.com/WebAssembly/wasi-nn/blob/f72b983c4cc91ac575af6babc57b5bccb7db7ba9/phases/ephemeral/witx/wasi_ephemeral_nn.witx#L108-L118
[`init_execution_context`]: https://github.com/WebAssembly/wasi-nn/blob/f72b983c4cc91ac575af6babc57b5bccb7db7ba9/phases/ephemeral/witx/wasi_ephemeral_nn.witx#L125-L129
[`set_input`]: https://github.com/WebAssembly/wasi-nn/blob/f72b983c4cc91ac575af6babc57b5bccb7db7ba9/phases/ephemeral/witx/wasi_ephemeral_nn.witx#L134-L142
[`compute`]: https://github.com/WebAssembly/wasi-nn/blob/f72b983c4cc91ac575af6babc57b5bccb7db7ba9/phases/ephemeral/witx/wasi_ephemeral_nn.witx#L165
[`get_output`]: https://github.com/WebAssembly/wasi-nn/blob/f72b983c4cc91ac575af6babc57b5bccb7db7ba9/phases/ephemeral/witx/wasi_ephemeral_nn.witx#L147-L160



### Use

In its first iteration, the [wasi-nn] specification is implemented in the Wasmtime engine using
OpenVINO&trade; as the backing implementation. A follow-on post will describe the details of the
implementation. Here we focus on how to use wasi-nn in Wasmtime.

The first step is to build or retrieve the ML artifacts. The inputs to OpenVINO&trade; will be a
model, the model weights, and one or more input tensors. For this example, I generated
OpenVINO&trade;-compatible artifacts for an AlexNet model as a [test fixture
here](https://github.com/intel/openvino-rs/tree/main/crates/openvino/tests/fixtures/alexnet). To do
this, I used [OpenVINO&trade;'s model
optimizer](https://docs.openvinotoolkit.org/latest/openvino_docs_MO_DG_Deep_Learning_Model_Optimizer_DevGuide.html),
which has support for various model types, such as Caffe, TensorFlow, MXNet, Kaldi, and ONNX.
Because [wasi-nn] does not pre-process the input tensors (i.e. decode and resize images), I created
[a tool](https://github.com/intel/openvino-rs/tree/main/crates/openvino-tensor-converter) to read
images and generate the raw tensors (i.e. BGR) offline with the dimensions and precision the model
expects. The artifacts include:
 - `alexnet.xml`: the model description
 - `alexnet.bin`: the model weights
 - `tensor-1x3x227x227-f32.bgr`: the image tensor, adapted for the model
 - `build.sh`: a script for regenerating the artifacts

Next, we build Wasmtime with [wasi-nn] enabled; since ML inference is an optional (and highly
experimental!) feature, we must explicitly include it as a build option. Enabling wasi-nn in
Wasmtime turns on the `wasmtime-wasi-nn` crate that imports the
[`openvino`](https://crates.io/crates/openvino) crate . Though the `openvino` crate can build
OpenVINO&trade; from source, the fastest and most stable route is to build it using existing
OpenVINO&trade; binaries:

```shell script
$ OPENVINO_INSTALL_DIR=/opt/intel/openvino cargo build -p wasmtime-cli --features wasi-nn
```

You can download OpenVINO&trade; binaries through package repositories such as
[apt](https://docs.openvinotoolkit.org/latest/openvino_docs_install_guides_installing_openvino_apt.html)
and
[yum](https://docs.openvinotoolkit.org/latest/openvino_docs_install_guides_installing_openvino_yum.html),
or optionally [build from
source](https://github.com/openvinotoolkit/openvino/blob/master/build-instruction.md). Your platform
may have require a different `OPENVINO_INSTALL_DIR` location, though `/opt/intel/openvino` is the
default Linux destination. If you run into issues, the `openvino` crate
[documentation](https://github.com/openvinotoolkit/openvino/pull/2342/files#diff-797836aff877bf81e5149c84eb772d8685d7a11451430ea89115fac9c3539082)
may be helpful.

Once Wasmtime is built with [wasi-nn] enabled, we can write an example using the [wasi-nn] APIs.
Here we use Rust to compile to WebAssembly, but any language that targets WebAssembly should work.
Note how we reference the ML artifacts we retrieved previously:

```rust
pub fn main() {
    // Load the graph.
    let xml = fs::read_to_string("fixture/alexnet.xml").unwrap();
    let weights = fs::read("fixture/alexnet.bin").unwrap();
    let graph = unsafe { wasi_nn::load(&[&xml.into_bytes(), &weights], wasi_nn::GRAPH_ENCODING_OPENVINO, wasi_nn::EXECUTION_TARGET_CPU).unwrap() };

    // Add the input tensor.
    let context = unsafe { wasi_nn::init_execution_context(graph).unwrap() };
    let tensor_data = fs::read("fixture/tensor-1x3x227x227-f32.bgr").unwrap();
    let tensor = wasi_nn::Tensor { dimensions: &[1, 3, 227, 227], r#type: wasi_nn::TENSOR_TYPE_F32, data: &tensor_data };
    unsafe { wasi_nn::set_input(context, 0, tensor).unwrap(); }

    // Execute the inference.
    unsafe { wasi_nn::compute(context).unwrap(); }

    // Retrieve the output tensor.
    let mut output_buffer = vec![0f32; 1000];
    unsafe { wasi_nn::get_output(context, 0, &mut output_buffer[..] as *mut [f32] as *mut u8, (output_buffer.len() * 4).try_into().unwrap()); }
}
```

If we compile the example using the `wasm-wasi32` target, we can see that it will import the
necessary [wasi-nn] functions:

```shell script
$ cargo build --release --target=wasm32-wasi
$ wasm2wat target/wasm32-wasi/release/wasi-nn-example.wasm | grep import
    (import "wasi_snapshot_preview1" "proc_exit" (func $__wasi_proc_exit (type 0)))
    (import "wasi_ephemeral_nn" "load" (func $_ZN7wasi_nn9generated17wasi_ephemeral_nn4load17hfba8f512ab8c63beE (type 9)))
    (import "wasi_ephemeral_nn" "init_execution_context" (func $_ZN7wasi_nn9generated17wasi_ephemeral_nn22init_execution_context17he6f1beedc2598fbdE (type 2)))
    (import "wasi_ephemeral_nn" "set_input" (func $_ZN7wasi_nn9generated17wasi_ephemeral_nn9set_input17h51e14f836a91281bE (type 8)))
    (import "wasi_ephemeral_nn" "get_output" (func $_ZN7wasi_nn9generated17wasi_ephemeral_nn10get_output17h6a86ab75f932394dE (type 9)))
    (import "wasi_ephemeral_nn" "compute" (func $_ZN7wasi_nn9generated17wasi_ephemeral_nn7compute17h49f58c91c97507d5E (type 5)))
    (import "wasi_snapshot_preview1" "fd_close" (func $_ZN4wasi13lib_generated22wasi_snapshot_preview18fd_close17he8c060f039f6c828E (type 5)))
    (import "wasi_snapshot_preview1" "fd_filestat_get" (func $_ZN4wasi13lib_generated22wasi_snapshot_preview115fd_filestat_get17h27caa6992e6ea3b8E (type 2)))
    ...
```

Now we can run this example using Wasmtime!

```shell script
# Ensure the OpenVINO libraries are on the library path (e.g. LD_LIBRARY_PATH) since they will be dynamically linked:
$ source /opt/intel/openvino/bin/setupvars.sh
# Run our example Wasm in Wasmtime with the wasi-nn feature enabled and tell it where to look for the model artifacts (i.e. $ARTIFACTS_DIR)
$ OPENVINO_INSTALL_DIR=/opt/intel/openvino cargo run --features wasi-nn -- run --mapdir fixture::$ARTIFACTS_DIR target/wasm32-wasi/release/wasi-nn-example.wasm
```

The full example is available
[here](https://github.com/bytecodealliance/wasmtime/blob/main/crates/wasi-nn/examples/classification-example/src/main.rs)
and the process described above can be run using a Wasmtime CI script,
[`ci/run-wasi-nn-example.sh`](https://github.com/bytecodealliance/wasmtime/blob/main/ci/run-wasi-nn-example.sh).

To recap:
 - retrieve and/or generate model artifacts
 - build Wasmtime with the `wasi-nn` feature
 - compile your code against the `wasm32-wasi` target (in Rust parlance)
 - run the resulting Wasm file in wasi-nn-enabled Wasmtime 



### Conclusion

This post introduces the [wasi-nn] specification and demonstrates how to use it in the Wasmtime
engine. These are early days for [wasi-nn] and further work is clearly needed: extending and
refining the API, supporting more backends in Wasmtime, implementing wasi-nn in other Wasmtime
engines, etc. If you are interested in contributing to this effort, please do!
 - for discussions on the specification, open an issue in the [wasi-nn] repository
 - to contribute to the implementation in Wasmtime, check out the [wasmtime-wasi-nn
   crate](https://github.com/bytecodealliance/wasmtime/tree/main/crates/wasi-nn)
 - for other questions, one of us is usually available on the [BytecodeAlliance Zulip
   channel](https://bytecodealliance.zulipchat.com)

Finally, thanks to [Mingqiu Sun](https://github.com/mingqiusun) for thinking through the
specification issues with me and [Johnnie Birch](https://github.com/jlb6740) for valuable review
feedback. [Alex Crichton](https://github.com/alexcrichton) reviewed most of the CI integration and
[Dan Gohman](https://github.com/sunfishcode) really guided us through the WASI specification
proposal process. Thanks!



[wasi-nn]: https://github.com/WebAssembly/wasi-nn
