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
