#!/usr/bin/env bash
set -euo pipefail

MOON_WASI_WASMTIME="${MOON_WASI_WASMTIME:-wasmtime}"

moon info
moon fmt
moon check --deny-warn
moon test --target wasm
moon build --target wasm --release integration/fs
moon build --target wasm --release integration/sys
moon build --target wasm --release cmd/main
moon build --target wasm --release examples/tree
moon build --target wasm --release examples/atomic-config

"$MOON_WASI_WASMTIME" run --dir .::. \
  _build/wasm/release/build/integration/fs/fs.wasm
"$MOON_WASI_WASMTIME" run --dir .::. --env MOON_WASI_TEST=ready \
  _build/wasm/release/build/integration/sys/sys.wasm
