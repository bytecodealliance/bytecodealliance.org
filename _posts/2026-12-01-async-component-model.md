---
title: "The Async Component Model"
author: "Adam Bratschi-Kaye"
date: "2026-12-01"
github_name: "adamrk"
excerpt_separator: <!--end_excerpt-->
---
[WASI 0.3](https://bytecodealliance.org/articles/WASI-0.3) depends on the async features of the Component Model. These powerful new features allow languages to use their own native constructs for concurrency and still interoperate with components implemented in other languages! This post gives an overview of the core notions of the async Component Model and how they tie together to accomplish this goal.

<!--end_excerpt-->

## Background

We assume the reader already has some basic knowledge of the Component Model. For a refresher, see the [Component Model Explainer](https://github.com/WebAssembly/component-model/blob/main/design/mvp/Explainer.md).

## Why does the Component Model need async?

The Component Model is designed to allow Wasm modules compiled from different languages to be packaged together into an executable and call into each other. Most languages have their own preferred method of concurrency, be it async/await, coroutines, green threads, pthreads, etc. Most of these cannot be built on top of core Wasm, and are hard to use across components.

The async Component Model meets two goals:
1. Introduce the platform needed for languages to build their own concurrency primitives when targeting Wasm.
2. Allow async functions to be called across components without either side being aware of how concurrency is implemented on the other side.

Note that the details of the async Component Model will be necessary for language implementers to target it, but application developers shouldn't _need_ to know any of the specifics - the whole point is to write code as you would for a "standard" OS!

## What is introduced?

The Component Model has a notion of component-level functions which are higher level than core Wasm functions. Core Wasm functions can be lifted into component functions, and component functions can be lowered to core Wasm functions. In both cases, the canonical options provided with the lift or lower can configure the translation between the two levels.

The basis of async support is a new `async` effect on _component-level_ function types, as well as an `async` _canonical option_ which can be added when lifting or lowering. The semantics of the `async` function type and `async` canonical options are described in the next two sections.

Waitable sets are introduced to provide a poll-like interface. Various waitable objects can be added to a waitable set and then a function can suspend until something in the waitable set has completed.

Waitables and waitable sets are not passed around directly in core Wasm. Instead, each component instance has a _handle table_ holding these objects (along with resource handles), and core Wasm code refers to them by `i32` indices into that table.

Additionally, new canonical builtins are added for creating, reading from, and writing to streams and futures.

The _cooperative threads_ feature will also add canonical builtins for creating and switching between threads which cooperatively yield to each other.

In summary, the core building blocks of the async Component Model are:

1. `async` component-level functions
2. `async` lift/lower canonical options
3. Waitable sets
4. Streams and futures
5. Cooperative threads

The essence of asynchronous programming is that callees can "block" on I/O and transfer control back to their caller while the system transparently handles resuming the callee when the I/O operation has made progress. Building blocks 1-3 are enough for this, and blocks 4 and 5 are additional features.

The `async` keyword is overloaded to show up in several places, so to be especially clear, the three places are:

 - Component-level functions can have `async` type.
 - Core Wasm functions can be lifted to component-level functions with an `async` canonical option.
 - Component-level functions can be lowered to core Wasm functions with an `async` canonical option.

## How do functions block?

The `async` effect for component-level functions indicates that the function may block. The main way for a function to block is by awaiting a waitable set, which indicates that it wants to be resumed when one of the operations in the waitable set has made progress.

The exact mechanism by which the callee waits on the waitable set is determined by the `async` canonical option - it can be set with or without an additional `callback` option.
- When `callback` is absent, this is a _stackful_ async function which blocks by calling the `waitable-set.wait` canonical builtin on a waitable set. When this happens, the host is responsible for saving the Wasm stack and resuming it when something in the set has made progress. From the perspective of the core Wasm function, `waitable-set.wait` will just return an event code (and write which waitable made progress to memory), but in the meantime control has been passed back to the caller which may have performed other work.
- When `callback` is present, this is a _stackless_ async function which blocks by returning a special `WAIT` exit code indicating that it is waiting on a waitable set (the index of the waitable set is bit packed into the exit code). The `callback` option is accompanied by a core Wasm function which is called by the host when the waitable set has made progress. The `callback` receives (as arguments) the same event information that `waitable-set.wait` returns in the _stackful_ case. Again, control is transferred to the caller when the initial call returns and the caller may perform additional work before the host schedules the `callback` to run. The `callback` is permitted to return with the `WAIT` exit code itself and it will then be called anew by the host when progress has been made in the waitable set.

## What happens when a function blocks?

Each time a component's export is called, a new _task_ is created. When one component calls a second component, we say that the callee's task is a _subtask_ from the caller's perspective.

We've seen how an `async` component-level function is declared and blocks, but when this function is running as a subtask, how does the caller get back control when the subtask blocks? Control is transferred by transforming the callee into a core Wasm function which returns a status code instead of its "actual" result.

When the function is lowered with the `async` keyword, its core Wasm type takes an additional out-parameter pointer argument and its return value is always an `i32`. When the callee blocks, a new subtask entry is created in the handle table of the caller. The caller will see that the core Wasm call has returned with the `i32` containing a bit packed status code along with the handle table index of this subtask. That index can then be added to a waitable set if the caller wants to wait for the call to complete. When the call has completed, the caller can read the result at the out-parameter it passed in.

When an async call blocks and control is transferred back to the caller, the caller can continue running and may choose to initiate more async calls. It can even choose to reenter the callee component by starting a new call to one of its exports.

## Returning

`async` lifted core Wasm functions can't use the core result value as their result - stackless functions use that result for the exit code, and even in the stackful case, we want to allow functions to keep running after they have returned a value (more on that later when we discuss streams and futures).

So instead of using a core result, the `task.return` canonical builtin is called to send a return value to the caller.

## Putting it all together

Here is an example of a component which uses an `async` import `get-random: async func() -> u64` and produces an `async` export `random-sum: async func() -> u64`. `random-sum` will asynchronously call `get-random` twice and return the total.

```scheme
(component
  ;; The host-provided component-level async function which returns a `u64`.
  (import "get-random" (func $get-random async (result u64)))

  ;; Boilerplate setup of a memory for our core instance.
  (core module $Memory (memory (export "mem") 1))
  (core instance $memory (instantiate $Memory))

  (core module $Main
    (import "" "mem" (memory 1))

    ;; The core Wasm lowering of `get-random`. Upon completion, the random u64
    ;; will be written into linear memory at address $retptr. The result is the
    ;; status of the async call (i.e. whether it completed or blocked).
    (import "" "get-random"
      (func $get-random (param $retptr i32) (result i32)))

    ;; Return the result of an async function.
    (import "" "task.return"
      (func $task.return (param $result i64)))

    ;; Adds the waitable (here, a subtask) to the waitable set, first removing
    ;; it from any set it is already in. A $waitable-set of 0 just removes it.
    (import "" "waitable.join"
      (func $waitable.join (param $waitable i32) (param $waitable-set i32)))

    ;; Create a new waitable set and get its index.
    (import "" "waitable-set.new"
      (func $waitable-set.new (result i32)))

    ;; Blocks this task until progress is made by a waitable in the set. Returns
    ;; the event code and writes (waitable index: u32, payload: u32) at $event-ptr.
    (import "" "waitable-set.wait"
      (func $waitable-set.wait (param $waitable-set i32) (param $event-ptr i32)
                               (result i32)))

    ;; Pointer to the top of the heap. Each call to `random-sum` will allocate a
    ;; frame by bumping this pointer. We don't free memory - Wasm will trap when
    ;; the current memory is exceeded.
    (global $heap (mut i32) (i32.const 0))

    ;; Core Wasm entry point for `random-sum`.
    (func (export "random-sum")
      (local $frame i32)
      (local $waitable_set i32)
      (local $i i32)
      (local $ret i32)
      (local $subtask i32)
      (local $sum i64)

      ;; Allocate this task's frame by bumping the heap pointer by 16 bytes and
      ;; store the base address in $frame.
      ;; The frame consists of:
      ;;   +0  u64  result of the current `get-random` call
      ;;   +8  u32  waitable index (written by `waitable-set.wait`)
      ;;   +12 u32  event payload  (written by `waitable-set.wait`)
      (local.set $frame (global.get $heap))
      (global.set $heap (i32.add (local.get $frame) (i32.const 16)))

      ;; Create the waitable set we'll use to block.
      (local.set $waitable_set (call $waitable-set.new))

      ;; Run this loop twice, calling get-random each time.
      (loop $main-loop
        ;; Call $get-random so that the u64 result will eventually be written to
        ;; address $frame+0. The status of the call is stored in $ret.
        (local.set $ret (call $get-random (local.get $frame)))

        ;; The low 4 bits of $ret indicate if the call completed or blocked. A
        ;; value of 2 indicates that the call ran to completion, so we don't
        ;; need to await anything and can skip directly to reading the result
        ;; from $frame+0.
        (if (i32.ne (i32.and (local.get $ret) (i32.const 0xf))
                    (i32.const 2))
          (then
            ;; The call blocked, so we need to wait for it to complete.

            ;; The upper 28 bits of $ret are the index of the subtask associated
            ;; with this call.
            (local.set $subtask (i32.shr_u (local.get $ret) (i32.const 4)))

            ;; Add the subtask index to our waitable set.
            (call $waitable.join (local.get $subtask)
                                 (local.get $waitable_set))

            ;; Wait on the waitable set in a loop until the operation completes.
            (loop $wait
              ;; Pass `waitable-set.wait` the index of our waitable set, along
              ;; with a pointer to $frame+8 where it will write two i32s for its
              ;; event. This event consists of the index for the subtask and
              ;; an enum indicating its new state.
              (call $waitable-set.wait (local.get $waitable_set)
                                       (i32.add (local.get $frame) (i32.const 8)))

              ;; We can ignore the return value of `waitable-set.wait` in this
              ;; case.
              drop

              ;; Check the state enum from the payload for the value 2 which
              ;; indicates that the subtask has completed. The subtask index can
              ;; be ignored because there is only one subtask in the waitable set,
              ;; so we already know which one made progress.
              (br_if $wait (i32.ne (i32.load offset=12 (local.get $frame))
                                   (i32.const 2)))

            ) ;; End of the $wait loop. The subtask has now completed.

            ;; Remove the subtask from our waitable set so that it is empty for
            ;; the next loop. This is done by adding the subtask to waitable set
            ;; 0, which isn't a real waitable set and has the side effect of
            ;; removing the subtask from any waitable sets it is currently in.
            (call $waitable.join (local.get $subtask) (i32.const 0))
          )
        )

        ;; The result of the async call is now at address $frame. Read it and
        ;; add it to the running total.
        (local.set $sum (i64.add (local.get $sum)
                                 (i64.load (local.get $frame))))

        ;; Increment the counter and go back to the beginning of the main loop
        ;; if the counter is < 2.
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br_if $main-loop (i32.lt_u (local.get $i) (i32.const 2)))
      )

      ;; The main loop has completed and we can return the total.
      (call $task.return (local.get $sum)))
  )

  ;; Lower the component-level function $get-random to the core Wasm function
  ;; $get-random'.
  ;; The `async` keyword is needed to indicate that our core Wasm caller will
  ;; take back control when the callee blocks.
  (canon lower (func $get-random) async (memory (core memory $memory "mem"))
    (core func $get-random'))

  ;; Boilerplate lowering the canonical builtins to core Wasm functions.
  (canon task.return (result u64) (core func $task.return))
  (canon waitable.join (core func $waitable.join))
  (canon waitable-set.new (core func $waitable-set.new))
  (canon waitable-set.wait (memory (core memory $memory "mem"))
    (core func $waitable-set.wait))

  ;; Boilerplate to instantiate the core module, importing the lowered
  ;; `get-random` and canonical builtins.
  (core instance $main (instantiate $Main (with "" (instance
    (export "mem" (memory $memory "mem"))
    (export "get-random" (func $get-random'))
    (export "task.return" (func $task.return))
    (export "waitable.join" (func $waitable.join))
    (export "waitable-set.new" (func $waitable-set.new))
    (export "waitable-set.wait" (func $waitable-set.wait))
  ))))

  ;; Export `random-sum` as an async function using the stackful ABI (we include
  ;; the `async` canonical option, but no `callback`).
  (func (export "random-sum") async (result u64)
    (canon lift (core func $main "random-sum") async))
)
```

One useful exercise is transforming `random-sum` to perform both calls to `get-random` concurrently. Try it out!

<details>
<summary>Hint</summary>
This will require putting both subtasks in the waitable set before waiting and then checking the waitable index in the event that `waitable-set.wait` writes, to know which subtask has completed so that it can be removed from the waitable set for the second poll.
</details>

## Function coloring

This model of `async` avoids the classic function coloring problem in the sense that a component can import and call `async` component-level functions without imposing any sort of async requirements on the guest language which is being used to implement the component.

Consider our example above of writing `random-sum: async func() -> u64` on top of `get-random: async func() -> u64`. An implementation of this that doesn't use async would lower `get-random` _without the `async` canonical option_. Then `get-random` can be called as just a regular core Wasm import with a `(result i64)`. The guest could then call that function twice and return the total without considering that the callee may block:

```scheme
  (core module $Main
    (import "" "get-random" (func $get-random (result i64)))
    (func (export "random-sum") (result i64)
      (i64.add (call $get-random) (call $get-random))
    )
  )
```

When `random-sum` is lifted to an `async` component-level function, it can also _omit the `async` canonical option_, which means that concurrent calls to `random-sum` will queue up in the host and run sequentially. It would also be possible to lift `random-sum` to a sync component-level function, but sync functions are not permitted to block, so this would only work if the calls to `get-random` never actually blocked.

So the async Component Model does suffer from function coloring in the sense that, at the component level, any export which calls `async` imports should probably be `async` itself. But this coloring doesn't leak into guest languages because the guest can choose to sync lower the imports and sync lift its export and then provide a purely sync implementation.

## Streams and futures

We've seen how functions can asynchronously return, but further support from the Component Model is needed for asynchronously delivering values. This is where streams and futures come in. The two constructs are essentially the same, except that streams can deliver zero or more values and futures deliver exactly one value. This is enforced by trapping if a second value is sent, or if the future is dropped before a value is sent. Since streams and futures are so similar, the rest of this section will just refer to streams, but everything applies to futures as well.

Streams can be used to pass any Component Model type (or no type at all, as a plain `stream`). They have a readable end and a writable end, which are two different entries in the component's handle table. The host does not perform any buffering of writes: either a read or a write to the stream will block until a matching operation on the opposite end occurs, at which point the host will copy value(s) from one end to the other.

This is what's generally known as _completion based_ I/O: the task is resumed when a pending operation has completed. This is in contrast to _readiness based_ I/O where the task would be resumed when the stream is ready for an operation, and would then need to actually perform the operation. For languages that require readiness based I/O, zero length reads and writes are supported and can be used to wait until the stream is ready.

So how does this integrate with the existing machinery for async functions? The key is that stream read and write ends are waitables just as subtasks are. After a read or write has been started, the stream end can be added to a waitable set and then `waitable-set.wait` will await completion of the operation. Notably, a waitable set can contain a mix of subtasks and stream/future read/write ends - the same mechanism is used for all async operations. In these situations, the return value of `waitable-set.wait` can be read to distinguish which type of waitable made progress (we were able to ignore that in the `random-sum` example because the waitable set only contained subtasks).

One reason an async function might need to continue running after it returns a value is that it needs to interact with a stream. For example, the function can create a stream and use `task.return` to send the readable end as a result. It could then enter a loop that periodically writes values to the writable end.

In WIT interfaces, you'll see only `stream<T>` types. These always refer to the _readable end_ of a stream. This works because there's never a need to pass a writable end in an interface. For example, instead of taking a writable end as an argument, the callee creates the stream and returns the readable end as a result.

## Threads

Each time an export of a component is called, it creates a new task, and that task runs in an implicit initial thread. If multiple concurrent calls to the export are made, there can be multiple threads running concurrently. These threads do _not_ run in parallel and the host _cannot_ preemptively interrupt them. Instead, only one thread runs at a time and the host can only switch to another thread when the current one blocks. A thread can voluntarily yield without waiting on anything with the `thread.yield` canonical builtin.

The cooperative threads feature (denoted by 🧵 in the spec) additionally allows threads to be explicitly created via the `thread.new-indirect` canonical builtin. In this case, each thread is associated with the task within which it was created. There is no distinguished "main" thread: the task is alive as long as any of its threads hasn't exited, and any thread within the task can call `task.return` to return a value to the caller.

Every thread which is not running and hasn't yet completed is in one of the following states:

1. _Waiting_: The thread blocked and is waiting on something in a waitable set to make progress.
2. _Ready_: The thread was in the waiting state, but one of the waitables made progress, so that event can now be delivered to the thread.
3. _Suspended_: Threads created with `thread.new-indirect` start in this state and threads can choose to enter this state by calling `thread.suspend`.

When a thread yields, the host can nondeterministically switch to any thread that is in the ready state. Threads that are suspended can be run when another thread explicitly switches to them via the canonical builtins `thread.suspend-then-resume` or `thread.yield-then-resume`. In those cases, the host must immediately switch to the target thread, which allows languages with green threads to directly control the scheduling within a component.

## Summary

At the start of this post we set out two goals for the async Component Model: give languages a platform to build their own concurrency on, and let async functions be called across components without either side knowing how the other implements concurrency.

The first goal is met by keeping the building blocks small and leaving the policy to the language. For example, a runtime with its own event loop can use the stackless ABI and drive everything from its `callback`, while one that relies on suspending stacks can use the stackful ABI. Languages that expect readiness based I/O can get it from zero length stream operations, and those that prefer completion based I/O can use the read/write primitives directly. Green thread runtimes can take full control of scheduling with the cooperative thread builtins, while `pthread` based ones can let the host handle scheduling.

The second goal is met because each side's choices stay on its own side of the boundary. The component-level function type only says that a call is `async`, but whether the caller lowers it with or without the `async` option, and whether the callee is lifted stackful, stackless or without the `async` option at all, is invisible to the other component. As we saw with function coloring, this even means a guest written entirely in synchronous code can call async imports and still interoperate with components written in fully async languages.

## Further reading

The [Concurrency Explainer](https://github.com/WebAssembly/component-model/blob/main/design/mvp/Concurrency.md) in the Component Model spec goes into much more detail on everything covered in this post. Some particularly relevant sections are:

- Blocking: [Blocking](https://github.com/WebAssembly/component-model/blob/main/design/mvp/Concurrency.md#blocking), [Waitables and Waitable Sets](https://github.com/WebAssembly/component-model/blob/main/design/mvp/Concurrency.md#waitables-and-waitable-sets) and [Async Export ABI](https://github.com/WebAssembly/component-model/blob/main/design/mvp/Concurrency.md#async-export-abi)
- Calling async functions: [Subtasks and Supertasks](https://github.com/WebAssembly/component-model/blob/main/design/mvp/Concurrency.md#subtasks-and-supertasks) and [Async Import ABI](https://github.com/WebAssembly/component-model/blob/main/design/mvp/Concurrency.md#async-import-abi)
- Returning: [Returning](https://github.com/WebAssembly/component-model/blob/main/design/mvp/Concurrency.md#returning)
- Examples: [Stackful ABI example](https://github.com/WebAssembly/component-model/blob/main/design/mvp/Concurrency.md#stackful-abi-example) and [Stackless ABI example](https://github.com/WebAssembly/component-model/blob/main/design/mvp/Concurrency.md#stackless-abi-example)
- Streams and futures: [Streams and Futures](https://github.com/WebAssembly/component-model/blob/main/design/mvp/Concurrency.md#streams-and-futures) and [Stream Readiness](https://github.com/WebAssembly/component-model/blob/main/design/mvp/Concurrency.md#stream-readiness)
- Threads: [Threads and Tasks](https://github.com/WebAssembly/component-model/blob/main/design/mvp/Concurrency.md#threads-and-tasks) and [Thread Built-ins](https://github.com/WebAssembly/component-model/blob/main/design/mvp/Concurrency.md#thread-built-ins)
