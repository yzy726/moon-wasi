#!/usr/bin/env bash
set -euo pipefail

moon info
moon fmt
moon check --deny-warn
moon test --target wasm
moon build --target wasm --release integration/fs
moon build --target wasm --release integration/sys
moon build --target wasm --release cmd/main
moon build --target wasm --release examples/tree
moon build --target wasm --release examples/atomic-config

wasmtime run --dir .::. _build/wasm/release/build/integration/fs/fs.wasm
wasmtime run --dir .::. --env MOON_WASI_TEST=ready \
  _build/wasm/release/build/integration/sys/sys.wasm
