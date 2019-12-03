---
title: "Multi-Value All The Wasm!"
author: "Nick Fitzgerald"
github_name: fitzgen
---

[Multi-value][] is a proposed extension to core WebAssembly that enables functions to return many values, among other things. It is also a pre-requisite for [Wasm interface types][interface-types].

I've been adding multi-value support *all* over the place recently:

* I added multi-value support to all the various crates in the Rust and WebAssembly toolchain, so that Rust projects can compile down to Wasm code that uses multi-value features.

* I added multi-value support to Wasmtime, the WebAssembly runtime built on top of the Cranelift code generator, so that it can run Wasm code that uses multi-value features.

Now, as my multi-value efforts are wrapping up, it seems like a good time to reflect on the experience and write up everything that's been required to get all this support in all these places.

## Wait — What is Multi-Value Wasm?

In core WebAssembly, there are a couple of arity restrictions on the language:

* functions can only return either zero or one value, and
* instruction sequences like `block`s, `if`s, and `loop`s cannot consume any stack values, and may only produce zero or one resulting stack value.

[The multi-value proposal][multi-value] is an extension to the WebAssembly standard that lifts these arity restrictions. Under the new multi-value Wasm rules:

* functions can return an arbitrary number of values, and
* instruction sequences can consume and produce an arbitrary number of stack values.

The following snippets are only valid under the new rules introduced in the multi-value Wasm proposal:

```scheme
;; A function that takes an `i64` and returns
;; three `i32`s.
(func (param i64) (result i32 i32 i32)
  ...)

;; A loop that consumes an `i32` stack value
;; at the start of each iteration.
loop (param i32)
  ...
end

;; A block that produces two `i32` stack values.
block (result i32 i32)
  ...
end
```

The multi-value proposal is currently at phase 3 of [the WebAssembly standardization process][wasm-standards-process].

### But Why Should I Care?

#### Code Size

There are a few scenarios where compilers are forced to jump through hoops when producing multiple stack values for core Wasm. Workarounds include introducing temporary local variables, and using `local.get` and `local.set` instructions, because the arity restrictions on blocks mean that the values *cannot* be left on the stack.

Consider a scenario where we are computing two stack values: the pointer to a string in linear memory, and its length. Furthermore, imagine we are choosing between two different strings (which therefore have different pointer-and-length pairs) based on some condition. But whichever string we choose, we're going to process the string in the same fashion, so we just want to push the pointer-and-length pair for our chosen string onto the stack, and control flow can join afterwards.

With multi-value, we can do this in a straightforward fashion:

```scheme
call $compute_condition
if (result i32 i32)
    call $get_first_string_pointer
    call $get_first_string_length
else
    call $get_second_string_pointer
    call $get_second_string_length
end
```

This encoding is also compact: only sixteen bytes!

When we're targeting core Wasm, and multi-value isn't available, we're forced to pursue alternative, more convoluted forms. We can smuggle the stack values out of each `if` and `else` arm via temporary local values:

```scheme
;; Introduce a pair of locals to hold the values
;; across the instruction sequence boundary.
(local $string i32)
(local $length i32)

call $compute_condition
if
    call $get_first_string_pointer
    local.set $string
    call $get_first_string_length
    local.set $length
else
    call $get_second_string_pointer
    local.set $string
    call $get_second_string_length
    local.set $length
end

;; Restore the values onto the stack, from their
;; temporaries.
local.get $string
local.get $length
```

This encoding requires 30 bytes, an overhead of fourteen bytes more than the ideal multi-value version. And if we were computing three values instead of two, there would be even more overhead, and the same is true for four values, etc... The additional overhead is proportional to how many values we're producing in the `if` and `else` arms.

We can actually go a little smaller than that &mdash; still with core Wasm &mdash; by jumping through a different hoop. We can split this into two `if ... else ... end` blocks and duplicate the condition check to avoid introducing temporaries for each of the computed values themselves:

```scheme
;; Introduce a local for the condition, so that
;; we only re-check it, and don't recompute it.
(local $condition i32)

;; Compute and save the condition.
call $compute_condition
local.set $condition

;; Compute the first stack value.
local.get $condition
if (result i32)
    call $get_first_string_pointer
else
    call $get_second_string_pointer
end

;; Compute the second stack value.
local.get $condition
if (result i32)
    call $get_first_string_length
else
    call $get_second_string_length
end
```

This gets us down to 28 bytes. Two fewer than the last version, but still an overhead of twelve bytes compared to the multi-value encoding. And the overhead is still proportional to how many values we're computing.

There's no way around it: we need multi-value to get the most compact code here.

#### New Instructions

The multi-value proposal opens up the possibility for new instructions that produce multiple values:

* An `i32.divmod` instruction of type `[i32 i32] -> [i32 i32]` that takes a numerator and divisor and produces *both* their quotient and remainder.

* Arithmetic operations with an additional carry result. These could be used to better implement big ints, overflow checks, and saturating arithmetic.

#### Returning Small Structs More Efficiently

Returning multiple values from functions will allow us to more efficiently return small structures like Rust's `Result`s. Without multi-value returns, these relatively small structs that still don't fit in a single Wasm value type get placed in linear memory temporarily. With multi-value returns, the values don't escape to linear memory, and instead stay on the stack. This can be more efficient, since Wasm stack values are generally more amenable to optimization than loads and stores from linear memory.

#### Interface Types

Shrinking code size is great, and new instructions would be fancy, but here's what I'm really excited about: [WebAssembly interface types][interface-types]. Interface types used to be called "host bindings," and they are the key to unlocking:

* direct, optimized access to the browser's DOM methods on the Web,
* "shared-nothing linking" of WebAssembly modules, and
* defining language-neutral interfaces, like [WASI][].

For all three use cases, we might want to return a string from a callee Wasm module. The caller that is consuming this string might be a Web browser, or it might be another Wasm module, or it might be a WASI-compatible Wasm runtime. In any case, a natural way to return the string is as two `i32`s:

1. a pointer to the start of the string in linear memory, and
2. the byte length of the string.

The interface adapter can then lift that pair of `i32`s into an abstract string type, and then lower it into the caller's concrete string representation on the other side. Interface types are designed such that in most cases, this lifting and lowering can be optimized into a quick memory copy from the callee's linear memory to the caller's.

But before the interface adapters can do that lifting and lowering, they need access to the pointer and length pair, which means the callee Wasm function needs to return two values, which means we need multi-value Wasm for interface types.

## All The Implementing!

Now that we know what multi-value Wasm is, and why it's exciting, I'll recount the tale of implementing support for it all over the place. I started with implementing multi-value support in the Rust and WebAssembly toolchain, and then I added support to the Wasmtime runtime, and the Cranelift code generator it's built on top of.

### Rust and WebAssembly Toolchain

What falls under the Rust and Wasm toolchain umbrella? It is a superset of the general Rust toolchain:

* `cargo`: Manages builds and dependencies.
* `rustc`: Compiles Rust sources into code.
* LLVM: Used by `rustc` under the covers to optimize and generate code.

And then additionally, when targeting Wasm, we also use a few more moving parts:

* `wasm-bindgen`: Part library and part Wasm post-processor, `wasm-bindgen` generates bindings for consuming and producing interfaces defined with interface types (and much more!)
* `walrus`: A library for transforming and rewriting WebAssembly modules, used by `wasm-bindgen`'s post-processor.
* `wasmparser`: An event-style parser for WebAssembly binaries, used by `walrus`.

Here's a summary of the toolchain's pipeline, showing the inputs and outputs between tools:

<a href="{{ site.baseurl }}/articles/img/rust-wasm-toolchain.svg"><img src="{{ site.baseurl }}/articles/img/rust-wasm-toolchain.svg" alt="A diagram showing the pipeline of the Rust and Wasm toolchain." width="1088" height="143" class="alignleft size-full wp-image-34027"  role="img" /></a>

My goal is to unlock interface types with multi-value functions. For now, I haven't been focusing on code size wins from generating multi-value blocks. For my purposes, I only need to introduce multi-value functions at the edges of the Wasm module that talk to interface adapters; I don't need to make all function bodies use the optimal multi-value instruction sequence constructs. Therefore, I decided to have `wasm-bindgen`'s post-processor rewrite certain functions to use multi-value returns, rather than add support in LLVM.<sup id="back-llvm-multi-value">[0](#foot-note-llvm-multi-value)</sup> With this approach I only needed to add support to the following tools:

* <del>`cargo`</del>
* <del>`rustc`</del>
* <del>LLVM</del>
* `wasm-bindgen`
* `walrus`
* `wasmparser`

#### `wasmparser`

[`wasmparser` is an event-style parser for WebAssembly binaries.][wasmparser] It may seem strange that adding toolchain support for *generating* multi-value Wasm began with *parsing* multi-value Wasm. But it is necessary to make testing easy and painless, and we needed it eventually for Wasmtime anyways, which also uses `wasmparser`.

In core Wasm, the optional value type result of a `block`, `loop`, or `if` is encoded directly in the instruction:

* a `0x40` byte means there is no result
* a `0x7f` byte means there is a single `i32` result
* a `0x7e` byte means there is a single `i64` result
* etc...

With multi-value Wasm, there are not only zero or one resulting value types, there are also parameter types. Blocks can have the same set of types that functions can have. Functions already de-duplicate their types in the "Type" section of a Wasm binary and reference them via index. With multi-value, blocks do that now as well. But how does this co-exist with non-multi-value block types?

The index is encoded as a signed variable-length integer, using [the LEB128 encoding][leb128]. If we interpret non-multi-value blocks' optional result value type as a signed LEB128, we get:

* `-64` (the smallest number that can be encoded as a single byte with signed LEB128) means there is no result
* `-1` means there is a single `i32` result
* `-2` means there is a single `i64` result
* etc..

They're all negative, leaving the positive numbers to be interpreted as indices into the "Type" section for multi-value blocks! A nice little encoding trick and bit of foresight from the WebAssembly standards folks.

Adding support for parsing these was straightforward, but `wasmparser` also supports validating the Wasm as it parses it. Adding validation support was a little bit more involved.

`wasmparser`'s validation implementation is similar to [the validation algorithm presented in the appendix of the WebAssembly spec][appendix-validation]: it abstractly interprets the Wasm instructions, maintaining a stack of types, rather than a stack of values. If any operation uses operands of the wrong type &mdash; for example the stack has an `f32` at its top when we are executing an `i32.add` instruction, and therefore expect two `i32`s on top of the stack &mdash; then validation fails. If there are no type errors, then it succeeds. There are some complications when dealing with stack-polymorphic instructions, like `drop`, but they don't really interact with multi-value.

Whenever `wasmparser` encounters a `block`, `loop`, or `if` instruction, it pushes an associated control frame, that keeps track of how deep in the stack instructions within this block can access. Before multi-value, the limit was always the length of the stack upon entering the block, because blocks didn't take any values from the stack. With multi-value, this limit becomes `stack.len() - block.num_params()`. When exiting a block, `wasmparser` pops the associated control frame. It check that the top `n` types on the stack match the block's result types, and that the stack's length is `frame.depth + n`. Before multi-value, `n` was always either `0` or `1`, but now it can be any non-negative integer.

The final bit of validation that is impacted by multi-value is when an `if` needs to have an `else` or not. In core Wasm, if the `if` does not produce a resulting value on the stack, it doesn't need an `else` arm since the whole `if`'s typing is `[] -> []` which is also the typing for a no-op. With multi-value this is generalized to any `if` where the inputs and outputs are the same types: `[t*] -> [t*]`. Easy to implement, but also very easy to overlook (like I originally did!)

Multi-value support was added to `wasmparser` in these pull requests:

* [#103: Initial multi-value support](https://github.com/bytecodealliance/wasmparser/pull/103)
* [#135: Allow `[t*] -> [t*]`-typed `if` blocks with no `else`](https://github.com/bytecodealliance/wasmparser/pull/135)

#### `walrus`

[`walrus` is a WebAssembly to WebAssembly transformation library.][walrus] We use it to generate glue code in `wasm-bindgen` and to polyfill WebAssembly features.

`walrus` constructs its own intermediate representation (IR) for WebAssembly. Similar to how `wasmparser` validates Wasm instructions, `walrus` also abstractly interprets the instructions while building up its IR. This meant that adding support for constructing multi-value IR to `walrus` was very similar to adding multi-value validation support to `wasmparser`. In fact, `walrus` also validates the Wasm while it is constructing its IR.

But multi-value has big implications for the IR itself. Before multi-value, you could view Wasm's stack-based instructions as a post-order encoding of an expression tree.

Consider the expression `(a + b) * (c - d)`. As an expression tree, it looks like this:

```text
     *
    / \
   /   \
  +     -
 / \   / \
a   b c   d
```

A post-order traversal of a tree is where a node is visited after its children. A post-order traversal of our example expression tree would be:

```text
a b + c d - *
```

Assume that `a`, `b`, `c`, and `d` are Wasm locals of type `i32`, with the values `9`, `7`, `5`, and `3` respectively. We can convert this post-order directly into a sequence of Wasm instructions that build up their results on the Wasm stack:

```scheme
;; Instructions ;; Stack
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
local.get $a    ;; [9]
local.get $b    ;; [9, 7]
i32.add         ;; [16]
local.get $c    ;; [16, 5]
local.get $d    ;; [16, 5, 3]
i32.sub         ;; [16, 2]
i32.mul         ;; [32]
```

This correspondence between trees and Wasm stack instructions made using a tree-like IR in `walrus`, where nodes are instructions and a node's children are the instructions that produce the parent's input values, very natural.<sup id="back-stack-and-tree-correspondence">[1](#foot-stack-and-tree-correspondence)</sup> Our IR used to look something like this:

```rust
pub enum Expr {
    // A `local.get` instruction.
    LocalGet(LocalId),

    // An `i32.add` instruction.
    I32Add(ExprId, ExprId),

    // Etc...
}
```

But multi-value threw a wrench in this tree-like representation: now that an instruction can produce multiple values, when we have a `parent⟶child` edge in the tree, how do we know *which* of the child's resulting values the parent wants to use? And also, if two different parents are each using one of the two values an instruction generates, we fundamentally don't have a tree anymore, we have a <a href="https://en.wikipedia.org/wiki/Directed_acyclic_graph" rel="noopener noreferrer" target="_blank">directed, acyclic graph (DAG)</a>.

We considered generalizing our tree representation into a DAG, and labeling edges with *n* to represent using the *n<sup>th</sup>* resulting value of an instruction. We weighed the complexity of implementing this representation against what our current use cases in `wasm-bindgen` demand, along with any future use cases we could think of. Ultimately, we decided it wasn't worth the effort, since we don't need that level of detail for any of the transformations or manipulations that `wasm-bindgen` performs, or that we foresee it doing in the future.

Instead, we decided that within a block, representing instructions as a simple list is good enough for our use cases, so now our IR looks something like this:

```rust
pub struct Block(Vec<Instr>);

pub enum Instr {
    // A `local.get` instruction.
    LocalGet(LocalId),

    // An `i32.add` instruction. Note that its
    // children are left implicit now.
    I32Add,

    // Etc...
}
```

Additionally, it turns out it is faster to construct and traverse this list-based representation, so switching representations in `walrus` also gave `wasm-bindgen` a nice little speed up.

The `walrus` support for multi-value was implemented in these pull requests:

* [#114: Switch `walrus` from a tree to a list IR](https://github.com/rustwasm/walrus/pull/114)
* [#124: Multi-value! And even more fuzzing!](https://github.com/rustwasm/walrus/pull/124)

#### `wasm-bindgen`

[`wasm-bindgen` facilitates high-level interactions between Wasm modules and their host.][wasm-bindgen] Often that host is a Web browser and its DOM methods, or some user-written JavaScript. Other times it is an outside-the-Web Wasm runtime, like Wasmtime, using WASI and interface types. `wasm-bindgen` acts as a polyfill for the interface types proposal, plus some extra batteries included for a powerful user experience.

One of `wasm-bindgen`'s responsibilities is translating the return value of a Wasm function into something that the host caller can understand. When using interface types directly with Wasmtime, this means generating interface adapters that lift the concrete Wasm return values into abstract interface types. When the caller is some JavaScript code on the Web, it means generating some JavaScript code to convert the Wasm values into JavaScript values.

Let's take a look at some Rust functions and the Wasm they get compiled down into.

First, consider when we are returning a single integer from a Rust function:

```rust
// random.rs

#[no_mangle]
pub extern "C" fn get_random_int() -> i32 {
    // Chosen by fair dice roll.
    4
}
```

And here is the disassembly of that Rust code compiled to Wasm:

```scheme
;; random.wasm

(func $get_random_int (result i32)
  i32.const 4
)
```

The resulting Wasm function's signature is effectively identical to the Rust function's signature. No surprises here. It is easy for `wasm-bindgen` to translate the resulting Wasm value to whatever is needed because `wasm-bindgen` has direct access to it; it's right there.

Now let's look at returning compound structures from Rust that don't fit in a single Wasm value:

```rust
// pair.rs

#[no_mangle]
pub extern "C" fn make_pair(a: i32, b: i32) -> [i32; 2] {
    [a, b]
}
```

And here is the disassembly of this new Rust code compiled to Wasm:

```scheme
;; pair.wasm

(func $make_pair (param i32 i32 i32)
  local.get 0
  local.get 2
  i32.store offset=4
  local.get 0
  local.get 1
  i32.store
)
```

The signature for the `make_pair` function in `pair.wasm` doesn't look like its corresponding signature in `pair.rs`! It has three parameters instead of two, and it isn't returning *any* values, let alone a pair.

What's happening is that LLVM doesn't support multi-value yet so it can't return two `i32`s directly from the function. Instead, callers pass in a "struct return" pointer to some space that they've reserved for the return value, and `make_pair` will write its return value through that struct return pointer into the reserved space. By convention, LLVM uses the first parameter as the struct return pointer, so the second Wasm parameter is our original `a` parameter in Rust and the third Wasm parameter is our original `b` parameter in Rust. We can see that the Wasm function is writing the `b` field first, and then the `a` field second.

How is space reserved for the struct return? Distinct from the Wasm standard's stack that instructions push values to and pop values from, LLVM emits code to maintain a "shadow stack" in linear memory. There is a global dedicated as the stack pointer, and always points to the top of the stack. Non-leaf functions that need some scratch space of their own will decrement the stack pointer to allocate some space on entry (since the stack grows down, and its "top" of the stack is its lowest address) and will increment it to deallocate that space on exit. Leaf functions that don't call any other function can skip incrementing and decrementing this stack pointer, which is exactly why we didn't see `make_pair` messing with the stack pointer.

To verify that callers are allocating space for the return struct in the shadow stack, let's create a function that calls `make_pair` and then inspect its disassembly:

```rust
// pair.rs

#[no_mangle]
pub extern "C" fn make_default_pair() -> [i32; 2] {
    make_pair(42, 1337)
}
```

I've annotated `default_make_pair`'s disassembly below to make it clear how the shadow stack pointer is manipulated to create space for return values and how the pointer to that space is passed to `make_pair`:

```scheme
;; pair.wasm

(func $make_default_pair (param i32)
  (local i32)

  ;; Reserve 16 bytes of space in the shadow
  ;; stack. We only need 8 bytes, but LLVM keeps
  ;; the stack pointer 16-byte aligned. Global 0
  ;; is the stack pointer.
  global.get 0
  i32.const 16
  i32.sub
  local.tee 1
  global.set 0

  ;; Get a pointer to the last 8 bytes of our
  ;; shadow stack space. This is our struct
  ;; return pointer argument, where the result
  ;; of `make_pair` will be written to.
  local.get 1
  i32.const 8
  i32.add

  ;; Call `make_pair` with the struct return
  ;; pointer and our default values.
  i32.const 42
  i32.const 1337
  call $make_pair

  ;; Copy the resulting pair into our own struct
  ;; return pointer's space. LLVM optimized this
  ;; into a single `i64` load and store, instead
  ;; of two `i32` load and stores.
  local.get 0
  local.get 1
  i64.load offset=8
  i64.store align=4

  ;; Restore the stack pointer to the original
  ;; value it had upon entering this function,
  ;; deallocating our shadow stack frame.
  local.get 1
  i32.const 16
  i32.add
  global.set 0
  end
)
```

When the caller is JavaScript, `wasm-bindgen` can use its knowledge of these calling conventions to generate JavaScript glue code that allocates shadow stack space, calls the function with the struct return pointer argument, reads the values out of linear memory, and finally deallocates the shadow stack space before converting the Wasm values into some JavaScript value.

But when using interface types directly, rather than polyfilling them, we can't rely on generating glue code that has access to the Wasm module's linear memory. First, the memory might not be exported. Second, the only glue code we have is interface adapters, not arbitrary JavaScript code. We want those values as proper return values, rather than through a side channel.

So I wrote a `walrus` transform in `wasm-bindgen` that converts functions that use a struct return pointer parameter without any actual Wasm return values, into multi-value functions that don't take a struct return pointer parameter but return multiple resulting Wasm values instead. This transform is essentially a "reverse polyfill" for multi-value functions.

```scheme
;; Before.
;;
;; First parameter is a struct return pointer. No
;; return values, as they are stored through the
;; struct return pointer.
(func $make_pair (param i32 i32 i32)
  ;; ...
)

;; After.
;;
;; No more struct return pointer parameter. Return
;; values are actual Wasm results.
(func $make_pair (param i32 i32) (result i32 i32)
  ;; ...
)
```

The transform is only applied to exported functions that take a struct return pointer parameter, and rather than rewriting the source function in place, the transform leaves it unmodified but removes it from the Wasm module's exports list. It generates a new function that replaces the old one in the Wasm module's exports list. This new function allocates shadow stack space for the return value, calls the original function, reads the values out of the shadow stack onto the Wasm value stack, and finally deallocates the shadow stack space before returning.

For our running `make_pair` example, the transform produces an exported wrapper function like this:

```scheme
;; pair.wasm

(func $new_make_pair (param i32 i32) (result i32 i32)
  ;; Our struct return pointer that points to the
  ;; scratch space we are allocating on the shadow
  ;; stack for calling `$make_pair`.
  (local i32)

  ;; Allocate space on the shadow stack for the
  ;; result.
  global.get $shadow_stack_pointer
  i32.const 8
  i32.sub
  local.tee 2
  global.set $shadow_stack_pointer

  ;; Call the original `$make_pair` with our
  ;; allocated shadow stack space for its
  ;; results.
  local.get 2
  local.get 0
  local.get 1
  call $make_pair

  ;; Read the return values out of the shadow
  ;; stack and place them onto the Wasm stack.
  local.get 2
  i32.load
  local.get 2
  i32.load offset=4

  ;; Finally, restore the shadow stack pointer.
  local.get 2
  i32.const 8
  i32.add
  global.set $shadow_stack_pointer
)
```

With this transform in place, `wasm-bindgen` can now generate multi-value function exports along with associated interface adapters that lift the concrete Wasm return values into abstract interface types.

The multi-value support and transform were implemented in `wasm-bindgen` in these pull requests:

* [#1764: Introduce a multi-value transform](https://github.com/rustwasm/wasm-bindgen/pull/1764)
* [#1805: Always use multi-value when targeting interface types](https://github.com/rustwasm/wasm-bindgen/pull/1805)
* [#1839: Update binding metadata after multi-value transform](https://github.com/rustwasm/wasm-bindgen/pull/1839)

### Wasmtime and Cranelift

Ok, so at this point, we can generate multi-value Wasm binaries with the Rust and Wasm toolchain &mdash; woo! But now we need to be able to run these binaries.

Enter [Wasmtime][], the WebAssembly runtime built on top of [the Cranelift code generator][cranelift]. Wasmtime translates WebAssembly into Cranelift's IR with the `cranelift-wasm` crate, and then Cranelift compiles the IR down to native machine code.

<a href="img/wasmtime-and-cranelift.svg"><img src="img/wasmtime-and-cranelift.svg" alt="Pipeline from a Wasm binary through Wasmtime and Cranelift to native code" width="887" height="169" class="alignleft size-full wp-image-34026"  role="img" /></a>

Implementing multi-value Wasm support in Wasmtime and Cranelift roughly involved two steps:

1. Translating multi-value Wasm into Cranelift IR
2. Supporting arbitrary numbers of return values in Cranelift

#### Translating Multi-Value Wasm into Cranelift IR

Cranelift has its own intermediate representation that it manipulates, optimizes, and legalizes before generating machine code for the target architecture. In order for Cranelift to compile some code, you need to translate whatever you're working with into Cranelift's IR. In our case, that means translating Wasm into Cranelift's IR. This process is analogous to `rustc` converting its mid-level intermediate representation (MIR) to LLVM's IR.<sup id="back-cranelift-backend-for-rustc">[2](#foot-cranelift-backend-for-rustc)</sup>

Cranelift's IR is made up of (extended) basic blocks<sup id="back-extended-basic-blocks">[3](#foot-extended-basic-blocks)</sup> containing code in [single, static-assignment form (SSA)][ssa]. SSA, as the name implies, means that variables can only be assigned to when defined, and can't ever be re-assigned:

```clif
;; `42 + 1337` in Cranelift IR
v0 = iconst.32 42
v1 = iconst.32 1337
v2 = iadd v0, v1
```

When translating to SSA form, most re-assignments to a variable `x` can be handled by defining a fresh `x1` and replacing subsequent uses of `x` with `x1`, and then turning the next re-assignment into `x2`, etc. But that doesn't work for points where control flow joins, such as the block following the consequent and alternative arms of an `if`/`else`.

Consider this Rust code, and how we might translate it into SSA:

```rust
let x;
if some_condition() {
    // This version of `x` becomes `x0` when
    // translated to SSA.
    x = foo();
} else {
    // This version of `x` becomes `x1` when
    // translated to SSA.
    x = bar();
}
// Does this use `x0` or `x1`??
do_stuff(x);
```

Should the `do_stuff` call at the bottom use `x0` or `x1` when translated into SSA? Neither!

SSA uses Φ (phi) functions to handle these cases. A phi function takes a number of mutually exclusive, control flow-dependent parameters and returns the one that was defined where control flow came from. In our example we would have `x2 = Φ(x0, x1)`, and if `some_condition()` was true then `x2` would get its value from `x0`. Otherwise, `x2` would get its value from `x1`.

If SSA and phi functions are new to you and you're feeling confused, don't worry! It was confusing for me too when I first learned about this stuff. But Cranelift IR doesn't use phi functions per se, it has something that I think is more intuitive: blocks can have formal parameters.

Translating our example to Cranelift IR, we get this:

```clif
;; Head of the `if`/`else`.
ebb0:
    v0 = call some_condition()
    brnz v0, ebb1
    jump ebb2

;; Consequent.
ebb1:
    v1 = call foo()
    jump ebb3(v1)

;; Alternative.
ebb2:
    v2 = call bar()
    jump ebb3(v2)

;; Code following the `if`/`else`.
ebb3(v3: i32):
    call do_stuff(v3)
```

Note that `ebb3` takes a parameter for the control flow-dependent value that we should pass to `do_stuff`! And the jumps in `ebb1` and `ebb2` pass their locally-defined values "into" `ebb3`! This is equivalent to phi functions, but I find it much more intuitive.

Anyways, translating WebAssembly code into Cranelift IR happens in the `cranelift-wasm` crate. It uses `wasmparser` to decode the given blob of Wasm and validate it, and then constructs Cranelift IR via (you guessed it!) abstract interpretation. As `cranelift-wasm` interprets Wasm instructions, rather than pushing and popping Wasm values, it maintains a stack of Cranelift IR SSA values. As `cranelift-wasm` enters and exits Wasm control frames, it creates Cranelift IR basic blocks.

This process is fairly similar to `walrus`'s IR construction, which was pretty similar to `wasmparser`'s validation, and the whole thing felt pretty familiar by now. There were just a couple tricky bits.

The first tricky bit was remembering to add parameters (phi functions) to the first basic block for a Wasm `loop`'s body, representing its Wasm stack parameters. This is necessary, because control flow joins from two places at the top of the loop body: from where we were when we first entered the loop, and from the bottom of the loop when we finish an iteration and are starting another. In terms of the abstract interpretation, this means you need to pop off the particular SSA values you have on the stack at the start of the loop, construct SSA values for the loop's parameters, and then push those onto the stack instead. I originally overlooked this, resulting in a fair bit of head scratching and debugging mis-translated IR. Whoops!

Second, `cranelift-wasm` will track reachability during translation, and if some Wasm code is unreachable, we don't even bother constructing Cranelift IR for it. But that boundary between unreachable and reachable code, and when one transitions to the other, can be a bit subtle. You can be in an unreachable state, fall through the current block into the following block, and become reachable once again. Throw in `if`s with `else`s, and `if`s without `else`s, and unconditional branches, and early returns, and it is easy for bugs to sneak in. And in the process of adding multi-value Wasm support, bugs did, in fact, sneak in. This time involving an `if` that was initially reachable, and whose consequent arm also ends reachable, but whose alternative arm ends *un*reachable. Given that, should the block following the consequent and alternative be reachable? Yes, but we were incorrectly computing that it shouldn't be.

To fix this bug, I refactored how `cranelift-wasm` computes reachablity of code following an `if`. It now correctly determines that the following block is reachable if the head of the `if` is reachable and any of the following are true:

* The consequent or alternative end reachable, in which case they will continue to the following block.
* The consequent or alternative do an early branch (potentially a conditional branch) to the following block, and that branch is reachable.
* There is no alternative, so if the `if`'s condition is false, we go directly to the following block.

To be sure that we are handling all these edge cases correctly, I added tests enumerating every combination of reachability of an `if`'s arms as well as early branches. Phew!

Finally, this bug first manifested itself in a 39 KiB Wasm file, and figuring out what was going on was made so much easier thanks to tools like [`wasm-reduce`][wasm-reduce] (a tool that is part of [binaryen][]) and [`creduce`][creduce] (working on the WAT disassembly, rather than the binary Wasm). I forget which one I used this time, but I've successfully used both to turn big, complicated Wasm test cases into small, isolated test cases that highlight the bug at hand. These tools are real life savers so it is worth broadcasting their existence just in case anyone doesn't know about them!

Translating multi-value Wasm into Cranelift IR happened in these pull requests:

* [#1049: Translate multi-value Wasm into Cranelift IR](https://github.com/CraneStation/cranelift/pull/1049)
* [#1110: Correctly jump to the destination block at the end of the consequent](https://github.com/CraneStation/cranelift/pull/1110)
* [#1143: Fix reachability tracking for `if`s](https://github.com/CraneStation/cranelift/pull/1143)

#### Supporting Many Return Values in Cranelift

Cranelift IR *the language* supports returning arbitrarily many values from a function, but Cranelift *the implementation* only supported returning as many values as there are available registers in the calling convention that the function is using. For example, with the System V calling convention, you could return up to three pointer-sized values, and with the Windows fastcall calling convention, you could only return a single pointer-sized value.

So the question was:

> How to return more values than can fit in registers?

This should trigger some deja vu: when compiling to Wasm, how was LLVM returning structures larger than could fit in a single Wasm value? Struct return pointer parameters! This is nothing new, and in fact its use is dictated by certain calling conventions, we just hadn't implemented support for it in Cranelift yet. So that's what I set out to do.

When Cranelift is given some initial IR, the IR is generally portable and machine independent. As the IR moves through Cranelift, eventually it reaches a legalization phase where instructions that don't have a direct mapping to an machine code instruction in the target architecture are replaced with ones that do. For example, on 32-bit x86, Cranelift legalizes 64-bit arithmetic by expanding it into a series of 32-bit operations. During this process, we also legalize function signatures: passing a value that is larger than can fit in a register may need to be split into multiple parameters, each of which can fit in registers, for example. Signature legalization also assigns locations to formal parameters based on the function's calling convention: this parameter should be in this register, and that parameter should be at this stack offset, etc.

My plan for implementing arbitrary numbers of return values via struct return pointer parameters was to hook into Cranelift's legalization phase during signature legalization, legalizing `return` instructions, and legalizing `call` instructions.

When legalizing signatures, we need to determine whether a struct return pointer is required, and if so, update the signature to reflect that.

```clif
;; Before legalization.
fn() -> i64, i64, i64, i64 fast

;; After legalization.
fn (v0: i64 sret [%rdi]) -> i64 sret [%rax] fast
```

Here, `fast` means the signature is using our internal, unstable "fast" calling convention. The `sret` is an annotation for a parameter or return value, in this case documenting that it is being used as a struct return pointer. The `%rdi` and `%rax` are the registers assigned to the parameter and return value by the calling convention.<sup id="back-locations-and-intel-syntax">[4](#foot-locations-and-intel-syntax)</sup>

After legalization, we've added the struct return pointer parameter, but we also removed the old returns, and we also return the struct return pointer parameter as well. Returning the struct return pointer is mandated by the System V ABI's calling conventions, but we currently do the same thing for our internal, unstable calling convention as well.

After signatures are legalized, we need to legalize `call` and `return` instructions as well, so that they match the new, legalized signatures. Let's turn our attention to the latter first.

Legalizing a `return` instruction removes the return values from the `return` instruction itself, and creates a series of preceding `store` instructions that write the return values through the struct return pointer. Here's an example that is returning four `i32` values:

```scheme
;; Before legalization.
ebb0:
    ;; ...
    return v0, v1, v2, v3

;; After legalization.
ebb0(v4: i64):
    ;; ...
    store notrap aligned v0, v4
    store notrap aligned v1, v4+4
    store notrap aligned v2, v4+8
    store notrap aligned v3, v4+12
    return v4
```

The new `v4` value is the struct return pointer parameter. The `notrap` annotation on the `store` instruction is saying that this store can't trigger a trap. It is the caller's responsibility to give us a valid struct return pointer that is pointing to enough space to fit all of our return values. The `aligned` annotation is similar, saying that the pointer we are storing through is properly four-byte aligned for an `i32`. Again, the responsibility is on the caller to ensure the struct return pointer has at least the maximum alignment required by the return values' types. The `+4`, `+8`, and `+12` are static immediates that specify an offset to be added to the actual `v4` operand to compute the destination address for the store.

Legalizing a `call` instruction has comparatively more responsibilities than legalizing a `return` instruction. Yes, it involves adding the struct return pointer argument to the `call` instruction itself, and then loading the values out of the struct return space after the callee returns to us. But it additionally must allocate the space for the struct return in the caller function's stack frame, and it must ensure that the size and alignment invariants that the callee and its `return` instructions rely on are upheld.

Let's take a look at an example of some caller function calling a callee function that returns four `i32`s:

```scheme
;; Before legalization.
function %caller() {
    fn0 = colocated %callee() -> i32, i32, i32, i32

ebb0:
    v0, v1, v2, v3 = call fn0()
    return
}

;; After legalization.
function %caller() {
    ss0 = sret_slot 16
    sig0 = (i64 sret [%rdi]) -> i64 sret [%rax] fast
    fn0 = colocated %callee sig0

ebb0:
    v4 = stack_addr.i64 ss0
    v5 = call fn0(v4)
    v6 = load.i32 notrap aligned v5
    v0 -> v6
    v7 = load.i32 notrap aligned v5+4
    v1 -> v7
    v8 = load.i32 notrap aligned v5+8
    v2 -> v8
    v9 = load.i32 notrap aligned v5+12
    v3 -> v9
    return
}
```

The `ss0 = sret_slot 16` is a sixteen byte stack slot that we created for the struct return space. It is also aligned to sixteen bytes, which is greater than necessary in this case, since we only need four byte alignment for the `i32`s. Similar to the `store`s in the legalized `return`, the `load`s in the legalized `call` are also annotated with `notrap` and `aligned`. `v0 -> v6` establishes that `v0` is another name for `v6`, and we don't have to eagerly rewrite all the following uses of `v0` into uses of `v6` (even though there don't happen to be any in this particular example).

With signature, `call`, and `return` legalization that all understand when and how to use struct return pointers, we now have full support for arbitrarily many multi-value returns in Cranelift and Wasmtime. This support was implemented in these pull requests:

* [#1147: Support many multi-value returns with struct return pointers](https://github.com/bytecodealliance/cranelift/pull/1147)
* [#1213: `legalize_signatures`: Optimistically try and assign register locations to return values; backtrack to use struct-return pointer parameter](https://github.com/CraneStation/cranelift/pull/1213)

## Putting It All Together

Finally, let's put everything together and create a multi-value Wasm binary with the Rust and Wasm toolchain and then run it in Wasmtime!

First, let's create a new library crate with `cargo`:

```shell
$ cargo new --lib hello-multi-value
     Created library `hello-multi-value` package
$ cd hello-multi-value/
```

We're going to use `wasm-bindgen` to return a string from our Wasm function, so lets add it as a dependency. Additionally, we're going to create a Wasm library, rather than an executable, so specify that this is a "cdylib":

```toml
# Cargo.toml

[lib]
crate-type = ["cdylib"]

[dependencies]
wasm-bindgen = "0.2.54"
```

Let's fill out `src/lib.rs` with our string-returning function:

```rust
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub fn hello(name: &str) -> String {
    format!("Hello, {}!", name)
}
```

We can build our Wasm library with [`cargo wasi`][cargo-wasi]:

```shell
$ cargo wasi build --release
```

This will automatically build a Wasm file for the `wasm32-wasi` target and then run `wasm-bindgen`'s post-processor to add interface types and introduce multi-value. We can verify this with the `wasm-objdump` tool from [WABT][wabt]:

```shell
$ wasm-objdump -x \
    target/wasm32-wasi/release/hello_multi_value.wasm
hello_multi_value.wasm: file format wasm 0x1

Section Details:

Type[14]:
...
 - type[6] (i32, i32) -> (i32, i32)
...

Function[151]:
...
 - func[93] sig=6 <hello multivalue shim>
...

Export[5]:
 - func[93] <hello multivalue shim> -> "hello"
...
```

We can see that the `<hello multivalue shim>` function is exported as `"hello"` and that it has the multi-value type `(i32, i32) -> (i32, i32)`. This shim function is indeed the one introduced by our multi-value transform we added to `wasm-bindgen` to wrap the original `<hello>` function and turn its struct return pointer into multi-value.

Finally, we can load this Wasm library into Wasmtime, which will use Cranelift to just-in-time (JIT) compile it to machine code, and then invoke the `hello` export with the string `"multi-value Wasm"`:

```shell
$ wasmtime \
    target/wasm32-wasi/release/hello_multi_value.wasm \
    --invoke hello "multi-value Wasm"
Hello, multi-value Wasm!
```

It works!!

## Conclusion

The Rust and WebAssembly toolchain now supports generating Wasm binaries that make use of the multi-value proposal, and Cranelift and Wasmtime can compile and run multi-value Wasm binaries. This has been &mdash; I hope! &mdash; an interesting tale of implementing a Wasm feature through the whole vertical ecosystem, start to finish.

Lastly, and definitely not leastly, I'd like to thank [Dan Gohman](https://github.com/sunfishcode), [Benjamin Bouvier](https://blog.benj.me/), [Alex Crichton](https://github.com/alexcrichton), [Yury Delendik](https://github.com/yurydelendik), [@bjorn3](https://github.com/bjorn3), and [@iximeow](https://github.com/iximeow) for providing reviews and implementation suggestions for different pieces of this journey at various stages. Additionally, thanks again to Alex and Dan, and to [Lin Clark](https://twitter.com/linclark/) and [Till Schneidereit](https://twitter.com/tschneidereit) for all providing feedback on early drafts of this piece.

--------------------------------------------------------------------------------

<small><sup id="foot-note-llvm-multi-value">0</sup> Additionally, [Thomas Lively](https://github.com/tlively) and some other folks are already working on adding multi-value Wasm support directly to LLVM, so that is definitely coming in the future, and it made sense for me to focus my attention elsewhere. [&#x21a9;](#back-llvm-multi-value)</small>

<small><sup id="foot-stack-and-tree-correspondence">1</sup> There are some "stack-y" forms that don't quite directly map to a tree. For example, you can insert stack-neutral, side-effectual instruction sequences in the middle of any part of the post-order encoding of an expression tree. Here is a `call` that produces some value, followed by a `drop` of that value, inserted into the middle of the post-order encoding of `1 + 2`:</small>

```scheme
;; Instructions ;; Stack
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
i32.const 1     ;; [1]
call $foo       ;; [1, $result_of_foo]
drop            ;; [1]
i32.const 2     ;; [1, 2]
i32.add         ;; [3]
```

<small>These stack-y forms can be represented by introducing blocks that don't also introduce labels for control flow branches. You can think of them as sort of similar to Common Lisp's `progn` and `prog0` forms or Scheme's `(begin ...)` [&#x21a9;](#back-stack-and-tree-correspondence)</small>

<small><sup id="foot-cranelift-backend-for-rustc">2</sup> Fun fact: there is also ongoing work to make Cranelift a viable alternative backend for `rustc`!  See the [goals write up](https://github.com/bytecodealliance/cranelift/blob/master/rustc.md) and the [`bjorn3/rustc_codegen_cranelift`](https://github.com/bjorn3/rustc_codegen_cranelift) repo for details. [&#x21a9;](#back-cranelift-backend-for-rustc)</small>

<small><sup id="foot-extended-basic-blocks">3</sup> Originally, Cranelift was designed to use extended basic blocks, rather than regular basic blocks.  Both can only be entered at their head, but basic blocks additionally can only exit at their tail, while extended basic blocks can have conditional exits from the block in their middle. The idea is that extended basic blocks more directly match machine code which falls through untaken conditional branches to continue executing the next instruction. However, Cranelift is in the process of switching over to regular basic blocks, and removing support for extended basic blocks. The reasoning is that all its optimization passes end up essentially constructing and keeping track of basic blocks anyways, which added complexity, and the extended basic blocks weren't ultimately carrying their weight.  [&#x21a9;](#back-extended-basic-blocks)</small>

<small><sup id="foot-locations-and-intel-syntax">4</sup> Semi-confusingly, the square brackets are just the syntax that Cranelift decided to use to surround parameter locations, and they do *not* represent dereferencing the way they would in Intel-flavored assembly syntax.  [&#x21a9;](#back-locations-and-intel-syntax)</small>

[multi-value]: https://github.com/WebAssembly/multi-value
[wasm-standards-process]: https://github.com/WebAssembly/meetings/blob/master/process/phases.md
[interface-types]: https://github.com/WebAssembly/interface-types/
[WASI]: https://wasi.dev/
[walrus]: https://github.com/rustwasm/walrus
[wasmparser]: https://github.com/bytecodealliance/wasmparser
[wasm-bindgen]: https://github.com/rustwasm/wasm-bindgen
[wasmtime]: https://wasmtime.dev/
[cranelift]: https://github.com/bytecodealliance/cranelift
[wasm-reduce]: https://github.com/WebAssembly/binaryen/blob/d2550891e41ad0215b1cae46fa711bc1e264166a/src/tools/wasm-reduce.cpp
[creduce]: http://embed.cs.utah.edu/creduce/
[binaryen]: https://github.com/WebAssembly/binaryen
[ssa]: https://en.wikipedia.org/wiki/Static_single_assignment_form
[wabt]: https://github.com/WebAssembly/wabt
[cargo-wasi]: https://github.com/bytecodealliance/cargo-wasi/
[leb128]: https://en.wikipedia.org/wiki/LEB128
[appendix-validation]: https://webassembly.github.io/spec/core/appendix/algorithm.html
