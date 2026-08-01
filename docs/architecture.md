# Architecture

`Ag108/moon-wasi` is a capability-aware convenience layer over WASI Preview 1.
It deliberately leaves the ABI bindings to `peter-jerry-ye/wasi` and focuses on
safe paths, contextual errors, reliable file-system operations, and small
system utilities for MoonBit command-line programs.

## Package boundaries

- `Ag108/moon-wasi` owns contextual errors and process-level WASI utilities.
- `Ag108/moon-wasi/path` owns validated guest paths and lexical operations.
- `Ag108/moon-wasi/fs` owns preopen discovery, files, directories, metadata,
  traversal, copying, and atomic writes.

Dependencies point only inward: `fs` may depend on the root and `path`
packages, while the root package never depends on `fs`. This prevents package
cycles and keeps error handling reusable.

## Compatibility target

Version 0.1 targets the MoonBit linear-memory `wasm` backend and WASI Preview 1.
Preview 2/3, networking, and a general async runtime are outside the initial
scope. The low-level dependency is pinned because its inline-Wasm helpers are
sensitive to MoonBit ABI changes.

## Public API principles

1. Accept validated guest paths at capability-sensitive boundaries.
2. Attach operation and path context to every surfaced WASI error.
3. Close owned descriptors on every success and failure path.
4. Make partial reads and writes explicit internally and complete them in
   high-level helpers.
5. Keep deterministic logic separately testable without a WASI host.
