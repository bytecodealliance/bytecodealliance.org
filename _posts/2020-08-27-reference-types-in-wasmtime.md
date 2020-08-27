---
title: "WebAssembly Reference Types in Wasmtime"
author: "Nick Fitzgerald"
github_name: fitzgen
---

A few week ago, I finished implementing support for [the WebAssembly reference
types proposal][proposal] in Wasmtime. [Wasmtime] is a standalone,
outside-the-Web WebAssembly runtime, and the reference types proposal is
WebAssembly's first foray beyond simple integers and floating point numbers,
into the exciting world of garbage-collected references. This article will
explain what the reference types proposal enables, what it leaves for future
proposals, and how it is implemented in Wasmtime.

## What are Reference Types?

Without the reference types proposal, WebAssembly can only manipulate simple
integer and floating point values. It can't take or return references to the
host's objects like, for example, a DOM node on a Web page or an open connection
on a server. There are workarounds: for example, you can store the host objects
in a side table and refere to them by index, but this adds an extra indirection
and implementing the side table requires cooperating glue code on the host
side. That glue code, in particular, is annoying because it is outside of the
Wasm sandbox, diluting Wasm's safety guarantees, and it is host-specific. If you
want to use your Wasm module on the Web, in a Rust host, and in a Python host,
you'll need three separate glue code implementations. This makes WebAssembly
less attractive as a universal binary format.

With the reference types proposal, you don't need glue code to interact with
host references. The proposal has three main parts:

1. A new `externref` type, representing an opaque, unforgable reference to a
   host object.

2. An extension to WebAssembly tables, allowing them to hold `externref`s in
   addition to function references.

3. New instructions for manipulating tables and their entries.

With these new capabilities, Wasm modules can talk about host references
directly, rather than requiring external glue code running in the host.

`externref`s play nice with WebAssembly's sandboxing properties:

* They are *opaque*: a Wasm module cannot observe an `externref` value's bit
  pattern. Passing a reference to a host object into a Wasm module doesn't
  reveal any information about the host's address space and the layout of host
  objects within it.

* They are *unforgable*: a Wasm module can't create a fake host reference out of
  thin air. It can only return either a reference you already gave it or the
  null reference. It *cannot* pretend like the integer value `0x1bad2bad` is a
  valid host reference, return it to you, and trick you into dereferencing this
  invalid pointer.

## Example

Here's a Wasm module that exports a `hello` function which takes, as an
`externref` parameter, a reference to an open file and writes "Hello, Reference
Types!" to the file. This module imports the `write` syscall from a hypothetical
future version of [WASI][wasi], the WebAssembly System Interface, that leverages
reference types.

```lisp
;; hello.wat

(module
  ;; Import the write syscall from a hypothetical (and
  ;; simplified) future version of WASI.
  ;;
  ;; It takes a host reference to an open file, an address
  ;; in memory, and byte length and then writes
  ;; `memory[address..(address+length)]` to the file.
  (import "future-wasi" "write"
    (func $write (param externref i32 i32) (result i32)))

  ;; Define a memory that is one page in size (64KiB).
  (memory (export "memory") 1)

  ;; At offset 0x42 in the memory, define our data string.
  (data (i32.const 0x42) "Hello, Reference Types!\n")

  ;; Define a function that writes our hello string to a
  ;; given open file handle.
  (func (export "hello") (param externref)
    (call $write
      ;; The open file handle we were given.
      (local.get 0)
      ;; The address of our string in memory.
      (i32.const 0x42)
      ;; The length of our string in memory.
      (i32.const 24))
    ;; Ignore the return code.
    drop))
```

This Wasm module will run in *any* WebAssembly environment where WASI is
available.<sup id="back-ref-wasi-available"><a
href="#foot-ref-wasi-available">0</a></sup> We don't need glue code that is
maintaining a side table, mapping host references to indices.

### Python

For example, we can run `hello.wat` from [a Python host
environment][wasmtime-py] without any glue code:

```python
from wasmtime import *
import future_wasi

# Initial configuration, enabling reference types.
config = Config()
config.wasm_reference_types = True
engine = Engine(config)
store = Store(engine)

# Compile our `hello.wat` module.
module = Module.from_file(engine, "./hello.wat")

# Create an instance of the module and give it access
# to our `future-wasi.write` polyfill.
instance = Instance(store,
                    module,
                    [future_wasi.write(store)])

# Finally, open a file for writing and pass it into
# our Wasm instance's `hello` function!
with open("hello.txt", "wb") as open_file:
    instance.exports["hello"](open_file)
```

### Rust

And we can run the exact same `hello.wat` from a Rust host and without any
Rust-specific bindings or glue:

```rust
use anyhow::Result;
use std::{cell::RefCell, fs};
use wasmtime::*;

mod future_wasi;

fn main() -> Result<()> {
    // Initial configuration, enabling reference types.
    let mut config = Config::new();
    config.wasm_reference_types(true);
    let engine = Engine::new(&config);
    let store = Store::new(&engine);

    // Compile our `hello.wat` module.
    let module = Module::from_file(
        &engine,
        "./hello.wat",
    )?;

    // Create an instance of the module and give it
    // access to our `future-wasi.write` polyfill.
    let instance = Instance::new(&store, &module, &[
        future_wasi::write(&store).into(),
    ])?;

    // Get the instance's `hello` function export.
    let hello = instance
        .get_func("hello")
        .ok_or(anyhow::format_err!(
            "failed to find `hello` function export"
        ))?
        .get1::<Option<ExternRef>, ()>()?;

    // Open a file for writing and pass it into our Wasm
    // instance's `hello` function.
    let file = ExternRef::new(RefCell::new(
        fs::File::create("hello.txt")?,
    ));
    hello(Some(file))?;

    Ok(())
}
```

Running `hello.wat` &mdash; once again, without module-specific glue code
&mdash; is just as easy in [.NET][wasmtime-dotnet] and [Go][wasmtime-go] host
environments, and is left as an exercise for the reader ;)

### On the Web

Unlike the other host environments we've considered, WASI isn't natively
implemented on the Web. There's nothing stopping us, however, from polyfilling
WASI APIs with a little bit of JavaScript and a couple DOM methods! This is
still an improvement because there is overall less module-specific glue
code. Once one person has written the polyfills, everyone's Wasm modules can
reuse them.

There are many different things an "open file" could be modeled by on the
Web. For this demo, we'll use a DOM node: writing to it will append text
nodes. This works well because we know our module is only writing text data. If
we were working with binary data, we would choose another polyfilling approach,
like in-memory array buffers backing the file data.

Here is the JavaScript code to run our `hello.wat` module and polyfill our
`future-wasi.write` function:

```js
// The DOM node we will use as an "open file".
const output = document.getElementById("output");

async function main() {
  // Define the imports we are giving to the Wasm
  // module: our `future-wasi.write` polyfill.
  const imports = {
    "future-wasi": {
      write(domNode, address, length) {
        // Get `memory[address..address + length]`.
        const memory = new Uint8Array(
          instance.exports.memory.buffer
        );
        const data = memory.subarray(
          address,
          address + length
        );

        // Convert it into a string.
        const decoder = new TextDecoder("utf-8");
        const text = decoder.decode(data);

        // Finally, append it to the given DOM node that
        // is our "open file".
        const textNode = document.createTextNode(text);
        domNode.appendChild(textNode);
      }
    }
  };

  // Fetch and instantiate our Wasm module.
  const response = await fetch("./hello.wasm");
  const wasmBytes = await response.arrayBuffer();
  const { instance } = await WebAssembly.instantiate(
    wasmBytes,
    imports
  );

  // Call its exported `hello` function with a DOM node.
  instance.exports.hello(output);

  // Every time the button is clicked, call the exported
  // `hello` function again.
  const button = document.getElementById("call-hello");
  button.removeAttribute("disabled");
  button.addEventListener("click", () => {
    instance.exports.hello(output);
  });
}

main().catch(e => {
  output.textContent = `${e}\n\nStack:\n${e.stack}`;
});
```

You can view a live demo of this code in the iframe below. It should work in
Firefox 79+, or any other browser that supports reference types (at the time of
writing, Chrome has support for an older version of the reference types proposal
behind the `--experimental-wasm-anyref` flag, and Safari has in-progress support
behind the `JSC_useWebAssemblyReferences` flag.)

<p><iframe src="/articles/demos/reference-types-in-wasmtime/index.html" style="width:100%"></iframe></p>

## What Comes After the Reference Types Proposal?

The in-progress [WebAssembly type imports proposal][type-imports] builds on
reference types to let you distinguish between different kinds of host objects:
database connections and open files would be separate types. Or, on the Web,
Wasm would distinguish JavaScript `Promise`s from DOM nodes. It also adds
references that point to types defined by other Wasm modules, not just host
objects.

WASI will want to adopt unforgable reference types for file handles, as the
examples above suggest, instead of using integers. It might make sense for WASI
to wait for type imports, however, so it can use separate types for, say, an
open file and a source of entropy. This is a decision for the WASI subgroup of
the WebAssembly Community Group. Either way, when WASI does make this switch, it
will continue to support integer file descriptors, but implemented inside the
Wasm sandbox as indices into an `externref` Wasm table.

The [interface types] and [module linking] proposals promise to remove even more
glue code and bindings. The interface types proposal lets Wasm modules exchange
rich, structured types with each other or with the host. It translates between
interface types and core Wasm types, while keeping modules encapsulated from
each other. For example, a module can exchange in-memory strings and arrays
without exporting the whole memory or exposing allocator methods, both of which
are currently required without interface types. The module linking proposal
makes modules and instances first class values, allowing them to be defined,
imported, exported, and instantiated within other WebAssembly modules. This
functionality previously relied on the host's cooperation, requiring a snippet
of JavaScript to fetch and instantiate modules, hooking up their imports and
exports.

Even further in the future, full support for [garbage-collected objects in
WebAssembly][gc-proposal] will come eventually.

## Implementation Details

Now we'll dive into the details of Wasmtime's reference types implementation.

With `externref`s, the host gives Wasm limited access to host objects, but the
host also needs to know when Wasm is finished with those objects, so it can
clean them up. That clean up might involve closing a file handle or simply
deallocating memory. Statically running clean up routines once Wasm returns to
the host is attractive, but unfortunately flawed: Wasm can persist an
`externref` into a table or global so that it outlives the function call. We do
not, therefore, know ahead of time whether Wasm is still holding references to
host objects or not. We require a dynamic method for determining which objects
are still in use and which are not. This typically involves either reference
counting or a tracing collector or [a combination of the two][unified-gc].

This is all to say that implementing the reference types proposal introduced a
garbage collector in Wasmtime.

Much of WebAssembly's value rests on its predictable performance and minimal
nondeterminism. Garbage collectors are infamous for their unpredictable pauses,
and, if they support finalizers or weak references, nondeterministic
behavior. Implementing a collector to support reference types required
reconciling these contradictions as much as possible, while also balancing
implementation complexity.

The design we settled upon is a deferred reference counting collector, with
[Cranelift], Wasmtime's just-in-time (JIT) compiler, producing stack maps for
precisely identifying roots inside of Wasm frames. This approach balances
predictable latency with throughput. It is more complex than conservative stack
scanning, but avoids the nondeterminism inherent in that approach. It also has
the desirable property that if a Wasm module doesn't use reference types, then
it can't trigger garbage collection and the runtime will not impose any other
related overhead.

We chose reference counting over tracing garbage collection for a few
reasons. First, it lends itself to short and predictable GC pauses. Second,
adding reference counting to a runtime that wasn't built from the ground up with
a garbage collector in mind is easier than adding a tracing collector.

Excavating exactly what it is that makes reference counting easier to add
post-facto is a worthwhile exercise, because this has implications for the whole
runtime and for any application intending to embed it. Tracing collectors
identify all live objects, starting from known-live roots, and then any object
that wasn't found to be live is, by definition, no longer in use, and is
therefore safe to reclaim. Reference counting collectors start from known-dead
roots, find all the dead objects reachable only from those roots, and then
reclaim these known-dead objects. Consider what happens, with each type of
collector, if an object `A` fails to reveal to the collector that it is
referencing another object `B`. In a tracing collector, if no other object is
referencing `B`, then collector will conclude that `B` is not live and that it
is safe to reclaim `B`. But now `A` can use `B` after it has been reclaimed,
leading to use-after-free memory unsafety. On the other hand, with a reference
counting collector, if `A` does not reveal that it has the only reference that
is keeping `B` alive, then `B`'s reference count will not be decremented, then
the collector never reclaims `B` and the object is permanently leaked. While
leaking `B` is not ideal, a leak is much safer than a dangling
pointer. Reference counting collectors are easier to add to an existing runtime,
and make embedding that runtime in larger applications easier, because they have
a better failure mode than tracing collectors do. By default, reference counting
collectors safely leak, while tracing collectors unsafely allow use-after-free.

### Deferred Reference Counting

In normal reference counting, each time a new reference to an object is created,
the object's reference count is incremented, and each time a reference to the
object is dropped, its reference count is decremented. When the reference count
reaches zero, the object is deallocated. In [deferred reference counting], these
increments and decrements are not performed immediately, but are deferred until
a later time and then processed together in bulk. This assuages one of reference
counting's biggest weaknesses, the overhead of frequently modifying reference
counts, by trading prompt deallocation for better throughput.

With naïve reference counting, every single `local.get` and `local.set`
WebAssembly instruction operating on a reference type needs to manipulate
reference counts. This leads to many increments and decrements, most of which
are redundant. It also requires code (known as [landing pads]) for decrementing
the reference counts of the `externref`s inside each frame during stack
unwinding &mdash; which can happen, for example, because of an out-of-bounds
heap access trap.

By using deferred reference counting for `externref`s inside of Wasm frames, we
don't increment or decrement the reference counts at all, unless a reference
escapes a call's stack frame by being stored into a table or global.
Additionally, we don't need to generate landing pads for unwinding because
deferred reference counting can already tolerate slack between when a reference
to an object is created or dropped and when the object's reference count is
adjusted to reflect that.

Wasmtime implements deferred reference counting by maintaining an
over-approximation of the set of `externref`s held alive by Wasm stack
frames. We call this the `VMExternRefActivationsTable`. When we pass an
`externref` into Wasm, we insert it into the table. We do not update the table
as Wasm runs, so as execution drops references, the table becomes an
over-approximation of the set of `externref`s actually present on the stack.

Garbage collection is then composed of two phases. In the first phase, we walk
the stack, building a set of `externref`s currently held alive by Wasm stack
frames. This is the precise set that the `VMExternRefActivationsTable`
approximates. The second phase reconciles the difference between the
over-approximation and the precise set, decrementing the reference count for
each object that is in the over-approximation but not in the precise set. At the
end of this phase, we reset the `VMExternRefActivationsTable` to the new precise
set.

If we are not careful with how we schedule the deferred processing of reference
counts, we risk introducing nondeterminism. Using a timer-based GC schedule, for
example, means that we are at the whims of the operating system's thread
scheduler and a vast variety of other factors that perturb how much we have
executed in a given amount of time. Instead, we trigger GC whenever the
`VMExternRefActivationsTable` reaches capacity, or whenever GC is explicitly
requested by the embedder application. As long as the embedder triggers GC
deterministically, we maintain deterministic GC scheduling, and execution
remains deterministic even in the face of finalizers.

It is worth noting that outside of Wasm frames, in native VM code implemented in
Rust, we use regular, non-deferred reference counting: cloning increments the
count and dropping decrements it. However, Rust's moves and borrows let us avoid
some of the associated overhead. Moving an `externref` transfers ownership
without affecting the reference count. Borrowing an `externref` lets us safely
use the value without incrementing its reference count, or at least delays the
increment until the borrowed reference is cloned.

### Stack Maps

For the collector to find the GC roots within a stack frame it requires that the
compiler emit *stack maps*. A stack map records which words in a stack frame
contain live `externref`s at each point in the function where GC may occur. The
stacks maps, taken together, logically record a table of the form:

<style>
table.padded th {
  text-align: left;
}
table.padded td, table.padded th {
  padding: 0.5em;
}
table.padded tbody tr:nth-child(odd) {
  background-color: hsl(320, 10%, 97.5%);
}
table.monospace-cells td {
  font-family: monospace;
}
</style>
<p><table class="padded monospace-cells">
  <thead>
    <tr>
      <th>Instruction Address</th>
      <th>Offsets of Live GC References</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>0x12345678</td>
      <td>2, 6, 12</td>
    </tr>
    <tr>
      <td>0x1234abcd</td>
      <td>2, 6</td>
    </tr>
    <tr>
      <td>...</td>
      <td>...</td>
    </tr>
  </tbody>
</table></p>

The offsets denoting where live references are stored within a stack frame are
relative to the frame's stack pointer and are expressed in units of words. Since
garbage collection can only occur at certain points within a function, the table
is sparse and only has entries for instruction addresses where GC is possible.

Because offsets of live GC references are relative to the stack pointer, and
because stack frames grow down from higher addresses to lower addresses, to get
a pointer to a live reference at offset `x` within a stack frame, the collector
adds `x` to the frame's stack pointer. For example, to calculate the pointer to
the live GC reference inside "frame 1" below, the collector would compute
`frame_1_sp + x`:

```
          Stack
        +-------------------+
        | Frame 0           |
        |                   |
   |    |                   |
   |    +-------------------+ <--- Frame 0's SP
   |    | Frame 1           |
 Grows  |                   |
 down   |                   |
   |    | Live GC reference | --+--
   |    |                   |   |
   |    |                   |   |
   V    |                   |   x = offset of live GC ref
        |                   |   |
        |                   |   |
        +-------------------+ --+--  <--- Frame 1's SP
        | Frame 2           |
        | ...               |
```

Each individual stack map is associated with just one instruction address within
a compiled Wasm function, contains the size of the stack frame, and represents
the stack frame as a bitmap. There is one bit per word in the stack frame; if
the bit is set, then the word contains a live GC reference.

The actual stack walking functionality is provided by [the `backtrace`
crate][backtrace-rs], which wraps [`libunwind`][libunwind] on unix-like
platforms and [DbgHelp] on Windows. To assist in stack walking, Cranelift emits
the platform's unwind information: [`.eh_frame`][eh_frame] on unix-like
platforms and [structured exception handling][seh] for Windows.

### Inline Fast Paths for GC Barriers

Despite our deferred reference counting scheme, compiled Wasm code must
occasionally manipulate reference counts and run snippets of code called GC
barriers. By running GC barriers, the program coordinates with the collector,
helping it keep track of objects.

Because of our deferred reference counting, Wasmtime does not need barriers for
references that stay within a Wasm function's scope, but barriers are still
needed whenever a reference enters or escapes the function's scope. Recall that
a reference can escape the scope when written into a global or table. It can,
similarly, enter a Wasm call's scope when read from a global or
table. Therefore, reading and writing to globals and tables requires barriers.

The barriers for writing a reference into a table slot and a global are similar
so, for simplicity, I'll just refer to tables from now on. These write barriers
are responsible for ensuring that:

1. The new object's reference count is incremented now that the table is holding
   a reference to it.

2. The table element's prior value, if any, has its reference count decremented.

3. If the prior element's reference count reaches zero, then its destructor is
   called and memory block deallocated.

There are two subtleties here. First, steps 1 and 2, although they may seem
independent, must be performed in the given order. If their order were reversed,
then if the new object assigned to the table slot and old object currently in
the table slot are the same, we would:

* Decrement the object's reference count from one to zero.

* Run the object's destructor and deallocate it.

* Re-assign a reference to the (now freed) object into the table slot.

* Increment the (now freed) object's reference count.

That's a use-after-free bug! To avoid it, we must always increment the new
object's reference count before decrementing the old object's reference
count. This way if they are the same object then the reference count never
reaches zero.

The second subtlety is that an object's destructor can do pretty much anything,
including touch the table slot we are currently running GC barriers for. If we
encounter this kind of reentrancy, we want the destructor to see the new table
element. We do not want it to see the half-deinitialized object and let it
attempt to resurrect the object.

Most barrier executions operate on non-null references, and most executions
don't decrement a reference count to zero and destroy an object. Therefore, the
JIT emits the reference counting operations inline, and only calls out from Wasm
to VM code when destroying an object:

```rust
inline table_set_barrier(table, index, new_value):
    if new_value is not null:
        new_value->ref_count++

    let old_value = table[index]
    table[index] = new_value

    if old_value is not null:
        old_value->ref_count--
        if old_value->ref_count is zero:
            call out_of_line_destroy(old_value)
```

The other scenario for which Wasmtime requires GC barriers is when Wasm reads a
reference from a table (or global), causing the reference to enter the scope of
the Wasm call. Its responsibility is ensuring that these references are safely
held alive by the `VMExternRefActivationsTable`. The
`VMExternRefActivationsTable` has a simple [bump allocation][bump-downwards]
chunk to support fast insertions from inline JIT code. We maintain a `next`
finger pointing within that bump chunk, and an `end` pointer pointing just after
it. The `next` finger is where we we will insert the next new entry into the
bump chunk, unless `next` is equal to `end` which means that the bump chunk is
at full capacity. When that happens we are forced to call an out-of-line slow
path that will trigger GC to free up space.

```rust
inline table_get_barrier(table, index):
    let elem = table[index]
    if elem is not null:
        let (next, end) = bump region
        if next != end:
            elem->ref_count++
            *next = elem
            next++
        else:
            call out_of_line_insert_and_gc(elem)
    return elem
```

## Conclusion

The reference types proposal is WebAssembly's first expansion beyond simple
integers and floating point numbers, requiring that Wasmtime grow a garbage
collector. It also cuts down on the amount of module-specific and host-specific
glue code. Future proposals, like interface types and module linking, should
completely remove the need for such glue.

Thanks to [Alex Crichton](https://github.com/alexcrichton) for reviewing the
bulk of this work, and exposing reference types in the `wasmtime-go` API. Thanks
to [Dan Gohman](https://sunfishcode.github.io/blog/) for reviewing the code that
implements the inline fast paths for GC barriers and the `cranelift-wasm`
interface changes it required. Thanks to [Peter
Huene](https://mobile.twitter.com/peterhuene) for exposing reference types in
`wasmtime-dotnet`. Finally, thanks to [Jim
Blandy](https://www.red-bean.com/jimb/), Dan Gohman, and Alex Crichton for
reading early drafts of this article and providing valuable feedback.

--------------------------------------------------------------------------------

<sup id="foot-ref-wasi-available">0</sup> However, since this is a hypothetical
future version of WASI, we will need to temporarily define our own version of
the `write` syscall. We will, furthermore, need to define this `write` polyfill
once for each host.

<p><details><summary>Python's <code>future-wasi.write</code> polyfill</summary>

{% highlight python %}
from wasmtime import *

def _write_impl(caller, file, address, length):
    # Get the module's memory export.
    memory = caller.get("memory")
    if not isinstance(memory, Memory):
        return -1

    # Check that the range of data to write is in bounds.
    if address + length > memory.data_len:
        return -1

    # Read the data from memory and then write it to the
    # file.
    data = memory.data_ptr[address : address + length]
    try:
        file.write(bytes(data))
        return 0
    except IOError:
        return -1

def write(store):
    return Func(store,
                FuncType([ValType.externref(),
                          ValType.i32(),
                          ValType.i32()],
                         [ValType.i32()]),
                _write_impl,
                access_caller = True)
{% endhighlight %}

</details></p>

<p><details><summary>Rust's <code>future-wasi.write</code> polyfill</summary>

{% highlight rust %}
use std::{cell::RefCell, fs, io::Write};
use wasmtime::*;

fn write_impl(
    caller: Caller,
    file: Option<ExternRef>,
    address: u32,
    len: u32,
) -> i32 {
    // Get the module's exported memory.
    let memory = match caller
        .get_export("memory")
        .and_then(|export| export.into_memory())
    {
        Some(m) => m,
        None => return -1,
    };
    let memory = unsafe { memory.data_unchecked() };

    // Get the slice of data that will be written to
    // the file.
    let start = address as usize;
    let end = start + len as usize;
    let data = match memory.get(start..end) {
        Some(d) => d,
        None => return -1,
    };

    // Downcast the `externref` into an open file.
    let file = match file
        .as_ref()
        .and_then(|file| {
            file.data().downcast_ref::<RefCell<fs::File>>()
        })
    {
        Some(f) => f,
        None => return -1,
    };

    // Finally, write the data to the file!
    let mut file = file.borrow_mut();
    match file.write_all(data) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

pub fn write(store: &Store) -> Func {
    Func::wrap(&store, write_impl)
}
{% endhighlight %}

</details></p>

These polyfills are only required until WASI is updated to leverage reference
types. [&#x21a9;](#back-ref-wasi-available)

[Wasmtime]: https://github.com/bytecodealliance/wasmtime/
[proposal]: https://github.com/WebAssembly/reference-types/blob/master/proposals/reference-types/Overview.md
[wasi]: https://wasi.dev/
[wabt]: https://github.com/WebAssembly/wabt/
[wasmtime-go]: https://github.com/bytecodealliance/wasmtime-go
[wasmtime-dotnet]: https://github.com/bytecodealliance/wasmtime-dotnet/
[wasmtime-py]: https://github.com/bytecodealliance/wasmtime-py/
[type-imports]: https://github.com/WebAssembly/proposal-type-imports/blob/master/proposals/type-imports/Overview.md
[interface types]: https://github.com/WebAssembly/interface-types/blob/master/proposals/interface-types/Explainer.md
[module linking]: https://github.com/WebAssembly/module-linking/blob/master/proposals/module-linking/Explainer.md
[gc-proposal]: https://github.com/WebAssembly/gc/blob/master/proposals/gc/Overview.md
[unified-gc]: https://researcher.watson.ibm.com/researcher/files/us-bacon/Bacon04Unified.pdf
[Cranelift]: https://github.com/bytecodealliance/wasmtime/blob/main/cranelift/README.md
[backtrace-rs]: https://github.com/rust-lang/backtrace-rs
[seh]: https://docs.microsoft.com/en-us/cpp/build/exception-handling-x64?view=vs-2019
[eh_frame]: https://refspecs.linuxfoundation.org/LSB_3.0.0/LSB-Core-generic/LSB-Core-generic/ehframechpt.html
[DbgHelp]: https://docs.microsoft.com/en-us/windows/win32/debug/dbghelp-functions
[libunwind]: https://github.com/libunwind/libunwind
[bump-downwards]: https://fitzgeraldnick.com/2019/11/01/always-bump-downwards.html
[deferred reference counting]: https://www.researchgate.net/publication/200040321_An_Efficient_Incremental_Automatic_Garbage_Collector
[landing pads]: https://itanium-cxx-abi.github.io/cxx-abi/abi-eh.html#defs
