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
