---
title: "Announcing wasi-threads"
author: "Andrew Brown"
github_name: abrown
---

Until now, one piece missing from WebAssembly standalone engines was the ability to spawn threads.
Browsers have had this ability for some time via Web Workers, but standalone engines had no standard
way to do this. This post describes the work of several collaborators to bring about
[wasi-threads](https://github.com/WebAssembly/wasi-threads), a proposal to add threads to WASI. It
will explain the history to this proposal, the work done to get to this point, and how one can
experiment with threaded applications in engines like Wasmtime and WAMR. To showcase this, we'll
look at how performing parallel compression with wasi-threads drastically improves performance.

## History

The core WebAssembly specification has a [threads
proposal](https://github.com/WebAssembly/threads/blob/master/proposals/threads/Overview.md) to add
support for thread primitives that is at [phase
3](https://github.com/WebAssembly/proposals#phase-3---implementation-phase-cg--wg). That proposal
adds support for three major features:

-   shared linear memory, via a `shared` annotation on `memory` declarations
-   atomic operations, e.g., `i32.atomic.rmw.cmpxchg`
-   `wait` and `notify`

Significantly, the WebAssembly threads proposal did not specify a mechanism for creating new
threads. A future vision for how this might work is described in [Weakening
WebAssembly](https://dl.acm.org/doi/10.1145/3360559), but, for practical reasons, the proposal left
this "spawn" detail up to implementors. After all, WebAssembly engines [in
browsers](https://webassembly.org/roadmap/) could already spawn new threads using Web Workers (see
Emscripten's [`pthreads` support](https://emscripten.org/docs/porting/pthreads.html)). But not
specifying a spawn mechanism meant that standalone WebAssembly engines (i.e., not in a browser)
could avoid the complexity of supporting multi-threaded execution. The key assumption was that not
all users of WebAssembly wanted or needed a threaded execution environment.

The lack of a specification did not stop people from investigating, though. In some areas of the
WebAssembly world, there is some interesting previous work to mention (a non-exhaustive list):

-   in 2018, Alex Crichton did some in-depth investigation to enable a WebAssembly raytracing
    example in the browser using Rust's `wasm-bindgen` ([blog
    post](https://rustwasm.github.io/2018/10/24/multithreading-rust-and-wasm.html))
-   in 2020, Ann Yuan and Marat Dukhan published browser results showing that the TensorFlow.js
    WebAssembly backend was fastest with threads and SIMD ([blog
    post](https://blog.tensorflow.org/2020/09/supercharging-tensorflowjs-webassembly.html))
-   in 2022, Alexandru Ene proposed wasi-threads largely based on the `pthreads` API

Building on Alexandru's initial proposal, an informal working group gathered to hash out the
details. These discussions pared down the API to a single call, `wasi_thread_spawn`, with some
simple parameters (e.g., see the [simpler
version](https://github.com/WebAssembly/wasi-threads/blob/main/wasi-threads.wit.md)). The current
specification is experimental and minimal; it is enough to run parallel programs (as we will show
below) but, due to its early nature, could change as users point out gaps.

## Motivation

It is hard to deny the performance implications of parallelism. Libraries like `pthreads` for C and
`rayon` for Rust are used in countless projects. Many algorithms have both parallel and sequential
versions, implying that peak performance requires parallelism. And in many cases, for systems with
multiple CPU cores available, the best performance *is* only available by using multiple threads.
With wasi-threads, this performance is now available in standalone WebAssembly engines.

Besides performance, another motivation for wasi-threads is developer productivity. Until now, any
library using multi-threading (e.g., for multi-tasking) was unusable for developers of standalone
engines. By enabling threads, wasi-threads expands the pool of libraries available.

But, in some standalone use cases, WebAssembly parallelism is not desired. For example, a blockchain
environment billing per WebAssembly instruction may never desire the complications of multiple
threads of execution. And some environments already parallelize execution along a different
dimension &mdash; per incoming HTTP request. In fact, it would be natural for some WebAssembly use
cases to remain solidly single-threaded. This motivates the *opt-in* aspect of
wasi-threads &mdash; users who need maximum performance from their WebAssembly host should be able
to use it and others should be able to ignore it.

It has been difficult to estimate the need for wasi-threads due to lack of tooling, preventing
experimentation &mdash; but this is changing. Until now, users could not compile `pthreads`
applications to WebAssembly &mdash; at least not easily and not for standalone engines (Emscripten
has had browser support for some time). With the pre-release of [wasi-sdk 20 with
threads](https://github.com/WebAssembly/wasi-sdk/releases/tag/wasi-sdk-20%2Bthreads) enabled, one
can now compile `pthreads` programs to the `wasm32-wasi-threads` target (we'll show that next). This
pre-release pulls together work from many contributors to build a `pthreads`-enabled `wasi-libc`.
Why is all of this necessary? Because of how WebAssembly features work with LLVM currently, all
linked WebAssembly objects need to share the same features (i.e., `threads`), all the way down to
the `libc` objects. Hopefully threads support can be extended to
[C++](https://github.com/WebAssembly/wasi-libc/issues/392) and
[Rust](https://github.com/rust-lang/compiler-team/issues/574) soon, but at least this pre-release
enables C users to experiment with wasi-threads, providing some idea for the demand for parallelism
in the standalone WebAssembly ecosystem.

## Demo

We can start with a simple example to demonstrate what wasi-threads makes possible. After retrieving
the
[wasi-sdk-20+threads](https://github.com/WebAssembly/wasi-sdk/releases/tag/wasi-sdk-20%2Bthreads)
pre-release for your OS, create the following program:

```c
#include <pthread.h>
#include <stdio.h>
#include <string.h>

#define NUM_THREADS 10

void *thread_entry_point(void *ctx) {
  int id = (int) ctx;
  printf(" in thread %d\n", id);
  return 0;
}

int main(int argc, char **argv) {
  pthread_t threads[10];
  for (int i = 0; i < NUM_THREADS; i++) {
    int ret = pthread_create(&threads[i], NULL, &thread_entry_point, (void *) i);
    if (ret) {
      printf("failed to spawn thread: %s", strerror(ret));
    }
  }
  for (int i = 0; i < NUM_THREADS; i++) {
    pthread_join(threads[i], NULL);
  }
  return 0;
}
```

This can be compiled with the following flags:

```shell
$ wasi-sdk/bin/clang --sysroot wasi-sdk/share/wasi-sysroot \
    --target=wasm32-wasi-threads -pthread \
    -Wl,--import-memory,--export-memory,--max-memory=67108864 \
    threads.c -o threads.wasm
```

This set of flags can seem daunting so let's walk through them:

- `--sysroot wasi-sdk/share/wasi-sysroot` is necessary when wasi-sdk is used outside its normal
  [installation directory](https://github.com/WebAssembly/wasi-sdk/tree/wasi-sdk-20%2Bthreads#use)
- `--target=wasm32-wasi-threads` tells the compiler we want to generate wasi-threads compatible
  modules (e.g., with shared memory, atomics support, a thread entry point, a `pthreads`-enabled
  wasi-libc)
- `-pthread` adds `pthreads` support, as expected
- `-Wl,--import-memory,--export-memory,--max-memory=67108864` tells the linker to import the memory
  (this is required by the wasi-threads specification), then export it (this is required by other
  WASI specifications), and make the memory large enough (without enough memory for their stack and
  TLS, threads cannot spawn)

Once we have the compiled `threads.wasm` file, we can run it in a recent version of Wasmtime (or
WAMR [^wamr]):

```shell
$ git clone --recurse-submodules https://github.com/bytecodealliance/wasmtime
$ cargo build --release --features=wasi-threads
$ target/release/wasmtime run --wasm-features=threads --wasi-modules=experimental-wasi-threads threads.wasm
  in thread 4
  in thread 2
  in thread 0
  in thread 5
  in thread 6
  in thread 1
  in thread 3
  in thread 7
  in thread 8
  in thread 9
```

[^wamr]: To run the `threads.wasm` example in WAMR:

    ```shell
    $ git clone https://github.com/bytecodealliance/wasm-micro-runtime.git -b dev/wasi_threads
    $ cd wasm-micro-runtime/product-mini/platforms/linux
    $ cmake -DWAMR_BUILD_LIB_WASI_THREADS=1 .
    $ ./iwasm threads.wasm
    ```

## Benchmarking

Now we can spawn threads, but will threads actually increase performance? I was concerned that some
of the Rust safeguards added to Wasmtime might impact threaded performance and indeed they did:
after removing sub-optimal copies, performance was back to normal
([#5566](https://github.com/bytecodealliance/wasmtime/pull/5566)). The workload I used for this
performed parallel compression &mdash; the idea is that the work of compressing chunks of a file can
be efficiently split into separate threads. (Why use WebAssembly for this? You tell me; I would
typically use natively-compiled binaries myself, but for demo purposes `gzip` is an
easily-parallelizable, recognizable workload).

![The components compiled together with wasi-sdk for the parallel compression benchmark.]({{
site.baseurl }}/articles/img/2023-02-21-wasi-threads/compiled-components.png)

I found a parallel implementation of `gzip`, called `pigz`, and added `Makefile`s to compile it to
WebAssembly. This also involved compiling `zlib`, a dependency, and patching `pigz` lightly. I
collected all of the tools necessary for compiling and running `pigz` and put them all in one place
[here](https://github.com/abrown/wasm-parallel-gzip). The `Makefile`s essentially compile the
WebAssembly objects using the same flags as shown above, but with the added project-specific
complexities of `pigz` and `libz`. You can build and run the benchmark yourself with:

```shell
$ git clone --recurse-submodules https://github.com/abrown/wasm-parallel-gzip
$ make
$ make benchmark NUM_THREADS=1
$ make benchmark NUM_THREADS=8
```

Using eight threads to compress 100MB of random bytes, I see linear speedups (\\~8x for eight
threads) when compared to a single thread! I am interested in your results as well; contact me on
[Zulip](https://bytecodealliance.zulipchat.com/#narrow/stream/349267-wasi-threads) to discuss more!
Note that the benchmarking setup in the repository is intentionally rough (e.g., `time`). I hope in
the future to integrate this more carefully into the
[Sightglass](https://github.com/bytecodealliance/sightglass/) benchmark suite.

## Future

This blog post demonstrates how standalone WebAssembly engines can now use wasi-threads to spawn
threads &mdash; with the associated performance improvements that brings. But work is not finished:
these are early days for wasi-threads and there are still issues to work through. Read through the
[specification](https://github.com/WebAssembly/wasi-threads) and file issues there or feel free to
create a [Zulip](https://bytecodealliance.zulipchat.com/#narrow/stream/349267-wasi-threads) thread
to discuss with the various contributors. Remember that wasi-threads, as a new WASI proposal, is
still experimental &mdash; do not expect strong stability in the ABI, especially as WASI transitions
to the component model.

We are watching and coordinating wasi-threads with the component model transition. wasi-threads, in
an attempt to maintain as much compatibility with browser WebAssembly as possible, is designed to
match the "instance per thread" model &mdash; each new thread is instantiated separately with only
shared memory to connect the parallel execution. The component model uses instances to isolate
subcomponents. If a subcomponent were to spawn a thread, it could no longer instantiate a single
module into a thread (should it instantiate a sub-tree of modules?!). Also, we are working through
how to express wasi-threads in WIT. We expect to continue discussing these issues in the future.

In the meantime, we need to understand how wasi-threads will be used. Please experiment with
wasi-threads and provide feedback! Note that Wasmtime is not the only standalone WebAssembly engine
implementing wasi-threads; you may also be interested in trying out the examples above on
[WAMR](https://github.com/bytecodealliance/wasm-micro-runtime). If you are interested in
contributing, please contact one of us; a good start might be to look at the open thread-related
[issues](https://github.com/bytecodealliance/wasmtime/issues?q=is%3Aissue+is%3Aopen+threads+label%3Awasm-proposal%3Athreads).

Finally, I want to give a a special thanks to Alexandru Ene, Marcin Kolny, Takashi Yamamoto for all
of the joint work on the wasi-threads specification. To Sam Clegg and Dan Gohman, thank you for all
of the toolchain help on `wasi-libc` and `wasi-sdk`. And to Alex Crichton, thank you for all of the
in-depth help making Wasmtime threads-friendly.
