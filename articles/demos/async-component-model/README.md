# Running the `random-sum` example

This directory contains the two components from the
[async Component Model post](../../../_posts/2026-12-01-async-component-model.md):

- `random-sum.wat`: the example from the post. It imports
  `get-random: async func() -> u64` and exports
  `random-sum: async func() -> u64`.
- `random.wat`: a (not very random) implementation of `get-random` that always
  returns `4`.

Composing the two components and invoking `random-sum` should print `8`.

## Prerequisites

- [`wasm-tools`](https://github.com/bytecodealliance/wasm-tools)
- [`wac`](https://github.com/bytecodealliance/wac)
- [`wasmtime`](https://github.com/bytecodealliance/wasmtime)

```sh
cargo install --locked wasm-tools wac-cli wasmtime-cli
```

## Steps

1. Convert both text files to binary components:

   ```sh
   wasm-tools parse random-sum.wat -o random-sum.wasm
   wasm-tools parse random.wat -o random.wasm
   ```

2. Compose them into a single component. `wac plug` connects the `get-random`
   export of `random.wasm` to the matching `get-random` import of
   `random-sum.wasm`:

   ```sh
   wac plug random-sum.wasm --plug random.wasm -o composed.wasm
   ```

3. Run `random-sum`. The async Component Model is still behind feature flags in
   Wasmtime, so they have to be turned on: `component-model-async` for async
   lifting/lowering and `component-model-async-stackful` because both
   components use the stackful ABI (`async` with no `callback`).

   ```sh
   wasmtime run \
     -W component-model-async,component-model-async-stackful \
     --invoke 'random-sum()' \
     composed.wasm
   ```

   This should print:

   ```
   8
   ```
