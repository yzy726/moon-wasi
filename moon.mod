// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "Ag108/moon-wasi"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/Ag108/moon-wasi"

license = "Apache-2.0"

keywords = [ "wasi", "wasm", "filesystem", "capability", "cli" ]

preferred_target = "wasm"

description = "Capability-aware WASI Preview 1 utilities for MoonBit"

import {
  "peter-jerry-ye/wasi@0.25.0",
}

options(
  exclude: [ "AGENTS.md" ],
)
