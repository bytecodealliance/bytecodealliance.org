;; A minimal implementation of the `get-random` import used by `random-sum.wat`.
;; It isn't actually random: every call just returns the same fixed value.
(component
  (core module $Random
    ;; Return the result of an async function.
    (import "" "task.return" (func $task.return (param $result i64)))

    ;; Core Wasm entry point for `get-random`. Since it's lifted with the
    ;; stackful async ABI, the result is passed to `task.return` rather than
    ;; being returned as a core Wasm result.
    (func (export "get-random")
      (call $task.return (i64.const 4)))  ;; chosen by fair dice roll
  )

  ;; Lower the `task.return` canonical builtin to a core Wasm function.
  (canon task.return (result u64) (core func $task.return))

  (core instance $random (instantiate $Random (with "" (instance
    (export "task.return" (func $task.return))
  ))))

  ;; Export `get-random` as an async function using the stackful ABI.
  (func (export "get-random") async (result u64)
    (canon lift (core func $random "get-random") async))
)
