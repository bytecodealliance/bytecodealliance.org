---
title: "Using WebAssembly from .NET with Wasmtime"
author: "Peter Huene"
github_name: peterhuene
---

[Wasmtime](https://github.com/bytecodealliance/wasmtime/), the WebAssembly runtime from the [Bytecode Alliance](https://bytecodealliance.org/articles/announcing-the-bytecode-alliance), recently added an early preview of an API for [.NET Core](https://docs.microsoft.com/en-us/dotnet/core), Microsoft's free, open-source, and cross-platform application runtime. This API enables developers to programmatically load and execute WebAssembly code directly from their .NET programs.

.NET Core is already a cross-platform runtime, so why should .NET developers pay any attention to WebAssembly?

There are several reasons to be excited about WebAssembly if you're a .NET developer, such as sharing the same executable code across platforms, being able to securely isolate untrusted code, and having a seamless interop experience with the upcoming WebAssembly interface types proposal.

### Share more code across platforms

.NET assemblies can already be built for cross-platform use, but using a *native library* (for example, a library written in C or Rust) can be difficult because it requires native interop and distributing a platform-specific build of the library for each supported platform.

However, if the native library were compiled to WebAssembly, the same WebAssembly module could be used across many different platforms and programming environments, including .NET; this would simplify the distribution of the library and the applications that depend on it.

### Securely isolate untrusted code

The .NET Framework attempted to sandbox untrusted code with technologies such as *Code Access Security* and *Application Domains*, but ultimately these failed to properly isolate untrusted code. As a result, Microsoft deprecated their use for sandboxing and ultimately removed them from .NET Core.

Have you ever wanted to load untrusted plugins in your application but couldn't figure out a way to prevent the plugin from invoking arbitrary system calls or from directly reading your process' memory? You can do this with WebAssembly because it was designed for the web, an environment where untrusted code executes every time you visit a website.

A WebAssembly module can only call the external functions it explicitly imports from a host environment, and may only access a region of memory given to it by the host. We can leverage this design to sandbox code in a .NET program too!

### Improved interoperability with interface types

The [WebAssembly interface types proposal](https://hacks.mozilla.org/2019/08/webassembly-interface-types/) introduces a way for WebAssembly to better integrate with programming languages by reducing the amount of glue code that is necessary to pass more complex types back and forth between the hosting application and a WebAssembly module.

When support for interface types is eventually implemented by the Wasmtime for .NET API, it will enable a seamless experience for exchanging complex types between WebAssembly and .NET.

## Diving into using WebAssembly from .NET

In this article we'll dive into using a Rust library compiled to WebAssembly from .NET with the Wasmtime for .NET API, so it will help to be a little familiar with the C# programming language to follow along.

The API described here is fairly low-level. That means that there is quite a bit of glue code required for conceptually simple operations, such as passing or receiving a string value.

In the future we'll also provide a higher-level API based on [WebAssembly interface types](https://hacks.mozilla.org/2019/08/webassembly-interface-types/) which will significantly reduce the code required for the same operations. Using that API will enable interacting with a WebAssembly module from .NET as easily as you would a .NET assembly.

Note also that the API is still under active development and will change in backwards-incompatible ways. We're aiming to stabilize it as we stabilize Wasmtime itself.

If you're reading this and you aren't a .NET developer, that's okay! Check out the [Wasmtime Demos](https://github.com/bytecodealliance/wasmtime-demos) repository for corresponding implementations for Python, Node.js, and Rust too!

## Creating the WebAssembly module

We'll start by building a Rust library that can be used to render [Markdown](https://commonmark.org/) to HTML. However, instead of compiling the Rust library for your processor architecture, we'll be compiling it to WebAssembly so we can use it from .NET.

You don't need to be familiar with the [Rust programming language](https://www.rust-lang.org/) to follow along, but it will help to have a Rust toolchain installed if you want to build the WebAssembly module. See the homepage for [Rustup](https://rustup.rs/) for an easy way to install a Rust toolchain.

Additionally, we're going to use [cargo-wasi](https://github.com/bytecodealliance/cargo-wasi), a command that bootstraps everything we need for Rust to target WebAssembly:

```
cargo install cargo-wasi
```

Next, clone the Wasmtime Demos repository:

```
git clone https://github.com/bytecodealliance/wasmtime-demos.git
cd wasmtime-demos
```

This repository includes the `markdown` directory that contains a Rust library. The library wraps a well-known Rust crate that can render Markdown as HTML. (*Note for .NET developers: a crate is like a NuGet package, in a way*).

Let's build the `markdown` WebAssembly module using `cargo-wasi`:

```
cd markdown
cargo wasi build --release
```

There should now be a `markdown.wasm` file in the `target/wasm32-wasi/release` directory.

If you're curious about the Rust implementation, open `src/lib.rs`; it contains the following:

```rust
use pulldown_cmark::{html, Parser};
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub fn render(input: &str) -> String {
    let parser = Parser::new(input);
    let mut html_output = String::new();
    html::push_html(&mut html_output, parser);
    return html_output;
}
```

The Rust library is exporting only a single function, `render`, that takes a string (the Markdown) as input and returns a string (the rendered HTML). All of the code required to parse Markdown and translate it to HTML is provided by the [pulldown-cmark](https://github.com/raphlinus/pulldown-cmark) crate.

Let's step back and simply appreciate what is about to happen here. We're taking a popular Rust crate, wrapping it with a few lines of code that exposes the functionality as a WebAssembly function, and then compiling it to a WebAssembly module that we can load from .NET regardless of the platform we're running on. How cool is that?!

### Peeking under the hood of a WebAssembly module

Now that we have the WebAssembly module we're going to use, what does it need from a host to function and what functionality does it offer the host?

To figure that out, let's disassemble the module to a textual representation using the `wasm2wat` tool from the [WebAssembly Binary Toolkit](https://github.com/WebAssembly/wabt) to a file called `markdown.wat`:

```
wasm2wat markdown.wasm --enable-multi-value > markdown.wat
```

*Note: the `--enable-multi-value` option enables support for functions that return multiple values and is required to disassemble the `markdown` module.*

#### What the module needs from a host

The module's imports define what the host should provide for the module to work.

Here are the imports for the `markdown` module:

```wasm
(import "wasi_unstable" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
(import "wasi_unstable" "random_get" (func $random_get (param i32 i32) (result i32)))
```

This tells us that the module will need two functions from the host: `fd_write` and `random_get`. These are actually [WebAssembly System Interface](https://github.com/WebAssembly/WASI) (WASI) functions that have well-defined behavior: `fd_write` is used to write data to a file descriptor and `random_get` will fill a buffer with random data.

Shortly we'll implement these functions for a .NET host, but it is important to understand that **this module can *only* call these functions from the host**; the host gets to decide how, and even if, the functions are implemented.

#### What the module offers a host

The module's exports define what functionality it offers the host.

Here are the exports for the `markdown` module:

```wasm
(export "memory" (memory 0))
(export "render" (func $render_multivalue_shim))
(export "__wbindgen_malloc" (func $__wbindgen_malloc))
(export "__wbindgen_realloc" (func $__wbindgen_realloc))
(export "__wbindgen_free" (func $__wbindgen_free))

...

(func $render_multivalue_shim (param i32 i32) (result i32 i32) ...)
(func $__wbindgen_malloc (param i32) (result i32) ...)
(func $__wbindgen_realloc (param i32 i32 i32) (result i32) ...)
(func $__wbindgen_free (param i32 i32) ...)
```

First, the module is exporting a *memory*. A WebAssembly memory is the linear address space accessible to the module; **it will be the only region of memory the module can read from or write to**. As the module cannot access any other region of the host's address space directly, the exported memory is where the host will exchange data with the WebAssembly module.

Second, the module exports the `render` function we implemented in Rust. But wait a second, why does it have two parameters and return two values when the Rust implementation only has one parameter and one return value?

In Rust, both a string slice (`&str`) and an owned string (`String`) are represented as an address and length (in bytes) pair when compiled to WebAssembly. Thus, the WebAssembly version of the Rust function takes an address-length pair for the markdown input string and returns an address-length pair for the rendered HTML string. Here, addresses are represented as integer offsets into the exported memory.

Note that since the Rust code returns a `String`, which is an *owned* type, the caller of `render` will be responsible for freeing the returned memory containing the rendered string.

During the implementation of the .NET host we'll discuss the rest of the exports.

## Creating the .NET project

We will need a [.NET Core SDK](https://dotnet.microsoft.com/download) to create a .NET Core project, so make sure you have a **3.0 or later** SDK installed.

Start by creating a directory for the project:

```
mkdir WasmtimeDemo
cd WasmtimeDemo
```

Next, create a new .NET Core console project:

```
dotnet new console
```

Finally, add a reference to the [Wasmtime NuGet package](https://www.nuget.org/packages/Wasmtime):

```
dotnet add package wasmtime --version 0.8.0-preview2
```

That's it! Now we're ready to use the Wasmtime for .NET API to load and execute the `markdown` WebAssembly module.

## Importing .NET code from WebAssembly

Importing .NET functions from WebAssembly is as simple as implementing the [`IHost`](https://peterhuene.github.io/wasmtime.net/api/Wasmtime.IHost.html) interface in .NET. This only requires a public [`Instance`](https://peterhuene.github.io/wasmtime.net/api/Wasmtime.Instance.html) property that will represent the WebAssembly module instance the host is bound to.

The [`Import`](https://peterhuene.github.io/wasmtime.net/api/Wasmtime.ImportAttribute.html) attribute is then used to mark functions and fields as imports to a WebAssembly module.

As we discussed earlier, the module requires two imports from the host: `fd_write` and `random_get`, so let's create implementations for those functions.

Create a file named `Host.cs` in the project directory and add the following content:

```csharp
using System.Security.Cryptography;
using Wasmtime;

namespace WasmtimeDemo
{
    class Host : IHost
    {
        // These are from the current WASI proposal.
        const int WASI_ERRNO_NOTSUP = 58;
        const int WASI_ERRNO_SUCCESS = 0;

        public Instance Instance { get; set; }

        [Import("fd_write", Module = "wasi_unstable")]
        public int WriteFile(int fd, int iovs, int iovs_len, int nwritten)
        {
            return WASI_ERRNO_NOTSUP;
        }

        [Import("random_get", Module = "wasi_unstable")]
        public int GetRandomBytes(int buf, int buf_len)
        {
            _random.GetBytes(Instance.Externs.Memories[0].Span.Slice(buf, buf_len));
            return WASI_ERRNO_SUCCESS;
        }

        private RNGCryptoServiceProvider _random = new RNGCryptoServiceProvider();
    }
}
```

The `fd_write` implementation simply returns an error indicating the operation isn't supported. It is used by the module for writing errors to <code>stderr</code>, which will not happen for this example.

The `random_get` implementation fills the requested buffer with random bytes. It slices the [`Span`](https://peterhuene.github.io/wasmtime.net/api/Wasmtime.Memory.html#Wasmtime_Memory_Span) representing the entire exported memory of the module so that the .NET implementation can write *directly* to the requested buffer without having to perform any intermediate copies. The `random_get` function is being called by the implementation of `HashMap` from Rust's standard library.

That's all it takes to expose .NET functions to the WebAssembly module with the Wasmtime for .NET API.

However, before we can load the WebAssembly module and use it from .NET, we need to discuss how a string gets passed from the .NET host as a parameter to the `render` function.

## Being a good host

Based on the exports of the module, we know it exports a *memory*. From the host's perspective, think of a WebAssembly module's exported memory as being granted access to the address space of a foreign process, even though the module *shares* the same process of the host itself.

If you randomly write data to a foreign address space, Bad Things Happen&#x2122; because it's quite easy to corrupt the state of the other program and cause undefined behavior, such as a crash or the total protonic reversal of the universe. So how can a host pass data to the WebAssembly module in a safe manner?

Internally the Rust program uses a *memory allocator* to manage its memory. So, for .NET to be a good host to the WebAssembly module, it must also use the *same* memory allocator when allocating and freeing memory accessible to the WebAssembly module.

Thankfully, [wasm-bindgen](https://rustwasm.github.io/docs/wasm-bindgen), used by the Rust program to export itself as WebAssembly, also exported two functions for that purpose: `__wbindgen_malloc` and `__wbindgen_free`. These two functions are essentially `malloc` and `free` from C, except `__wbindgen_free` needs the size of the previous allocation in addition to the memory address.

With this in mind, let us write a simple wrapper for these exported functions in C# so we can easily allocate and free memory accessible to the WebAssembly module.

Create a file named `Allocator.cs` in the project directory and add the following content:

```csharp
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using Wasmtime.Externs;

namespace WasmtimeDemo
{
    class Allocator
    {
        public Allocator(ExternMemory memory, IReadOnlyList<ExternFunction> functions)
        {
            _memory = memory ??
                throw new ArgumentNullException(nameof(memory));

            _malloc = functions
                .Where(f => f.Name == "__wbindgen_malloc")
                .SingleOrDefault() ??
                    throw new ArgumentException("Unable to resolve malloc function.");

            _free = functions
                .Where(f => f.Name == "__wbindgen_free")
                .SingleOrDefault() ??
                    throw new ArgumentException("Unable to resolve free function.");
        }

        public int Allocate(int length)
        {
            return (int)_malloc.Invoke(length);
        }

        public (int Address, int Length) AllocateString(string str)
        {
            var length = Encoding.UTF8.GetByteCount(str);

            int addr = Allocate(length);

            _memory.WriteString(addr, str);

            return (addr, length);
        }

        public void Free(int address, int length)
        {
            _free.Invoke(address, length);
        }

        private ExternMemory _memory;
        private ExternFunction _malloc;
        private ExternFunction _free;
    }
}
```

This code looks complicated, but all it is doing is finding the needed exported functions by name from the module and wrapping them with an easier to use interface.

We'll use this helper `Allocator` class to allocate the input string to the exported `render` function.

Now we're ready to render some Markdown.

## Rendering the Markdown

Open `Program.cs` in the project directory and replace it with the following content:

```csharp
using System;
using System.Linq;
using Wasmtime;

namespace WasmtimeDemo
{
    class Program
    {
        const string MarkdownSource = 
            "# Hello, `.NET`! Welcome to **WebAssembly** with [Wasmtime](https://wasmtime.dev)!";

        static void Main()
        {
            using var engine = new Engine();

            using var store = engine.CreateStore();

            using var module = store.CreateModule("markdown.wasm");

            using var instance = module.Instantiate(new Host());

            var memory = instance.Externs.Memories.SingleOrDefault() ??
                throw new InvalidOperationException("Module must export a memory.");

            var allocator = new Allocator(memory, instance.Externs.Functions);

            (var inputAddress, var inputLength) = allocator.AllocateString(MarkdownSource);

            try
            {
                object[] results = (instance as dynamic).render(inputAddress, inputLength);

                var outputAddress = (int)results[0];
                var outputLength = (int)results[1];

                try
                {
                    Console.WriteLine(memory.ReadString(outputAddress, outputLength));
                }
                finally
                {
                    allocator.Free(outputAddress, outputLength);
                }
            }
            finally
            {
                allocator.Free(inputAddress, inputLength);
            }
        }
    }
}
```

Let's walk through what the code doing. Step-by-step, it:

1. Creates an [`Engine`](https://peterhuene.github.io/wasmtime.net/api/Wasmtime.Engine.html). The engine represents the Wasmtime runtime itself. The runtime is what enables loading and executing WebAssembly modules from .NET.
2. Then it creates a [`Store`](https://peterhuene.github.io/wasmtime.net/api/Wasmtime.Store.html). A store is where all WebAssembly objects, such as modules and their instantiations, are kept. There can be multiple stores in an engine, but their associated objects cannot interact with one another.
3. Next it creates a [`Module`](https://peterhuene.github.io/wasmtime.net/api/Wasmtime.Module.html) from the `markdown.wasm` file on disk. A `Module` represents the data of the WebAssembly module itself, such as what it imports and exports. A module can have one or more *instantiations*. An instantiation is the *runtime* representation of a WebAssembly module. It compiles the module's *WebAssembly* instructions to instructions of the *current CPU architecture*, allocates the memory accessible to the module, and binds imports from the host.
4. It instantiates the module using an instance of the `Host` class we implemented earlier, binding the .NET functions as imports.
5. Finds the memory exported by the module.
6. Creates an allocator and then allocates a string for the Markdown source we want to render.
7. Invokes the `render` function with the input string by casting the instance to `dynamic`. This is a C# feature that enables dynamic binding of functions at runtime; think of it simply as a shortcut to searching for the exported `render` function and invoking it.
8. Outputs the rendered HTML by reading the returned string from the exported memory of the WebAssembly module.
9. Finally, it frees both the input string it allocated and the returned string that the Rust program gave us to own.

That's it for the implementation; onwards to actually running the code!

## Running the .NET program

Before we can run the program, we need to copy `markdown.wasm` to the project directory, as this is where we'll run the program from. You can find the `markdown.wasm` file in the `target/wasm32-wasi/release` directory from where you built it.

From the `Program.cs` source above, we see that the program hard-coded some Markdown to render:

```markdown
# Hello, `.NET`! Welcome to **WebAssembly** with [Wasmtime](https://wasmtime.dev)!
```

Run the program to render it as HTML:

```
dotnet run
```

If everything went according to plan, this should be the result:

```html
<h1>Hello, <code>.NET</code>! Welcome to <strong>WebAssembly</strong> with <a href="https://wasmtime.dev">Wasmtime</a>!</h1>
```

## What's next for Wasmtime for .NET?

That was a surprisingly large amount of C# code that was necessary to implement this demo, wasn't it?

There are two major features we have planned that will help simplify this:

* **Exposing Wasmtime's WASI implementation to .NET (and other languages)**

  In our implementation of `Host` above, we had to manually implement `fd_write` and `random_get`, which are WASI functions.

  Wasmtime itself has a WASI implementation, but currently it isn't accessible to the .NET API.

  Once the .NET API can access and configure the WASI implementation of Wasmtime, there will no longer be a need for .NET hosts to provide their own implementation of WASI functions.

* **Implementing interface types for .NET**

  As discussed earlier, WebAssembly interface types enable a more idiomatic integration of WebAssembly with a hosting programming language.

  Once the .NET API implements the interface types proposal, there shouldn't be a need to create an `Allocator` class like the one we implemented.

  Instead, functions that use types like `string` should simply work without having to write any glue code in .NET.

The hope, then, is that this is what it might look like in the future to implement this demo from .NET:

```csharp
using System;
using Wasmtime;

namespace WasmtimeDemo
{
    interface Markdown
    {
        string Render(string input);
    }

    class Program
    {
        const string MarkdownSource =
            "# Hello, `.NET`! Welcome to **WebAssembly** with [Wasmtime](https://wasmtime.dev)!";

        static void Main()
        {
            using var markdown = Module.Load<Markdown>("markdown.wasm");

            Console.WriteLine(markdown.Render(MarkdownSource));
        }
    }
}
```

I think we can all agree that looks so much better!

## That's a wrap!

This is the exciting beginning of using WebAssembly outside of the web browser from many different programming environments, including Microsoft's .NET platform.

If you're a .NET developer, we hope you'll join us on this journey!

*The .NET demo code from this article can be found in the [Wasmtime Demos repository](https://github.com/bytecodealliance/wasmtime-demos/tree/master/dotnet).*
