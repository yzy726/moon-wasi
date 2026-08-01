# 兼容性说明

## 支持矩阵

| 项目 | 0.1 支持状态 |
| --- | --- |
| MoonBit `wasm` 后端 | 支持 |
| WASI Preview 1 / `wasi_snapshot_preview1` | 支持 |
| Wasmtime 47 | 已验证 |
| Linux + Wasmtime | CI 目标 |
| Windows + Wasmtime | 已验证；符号链接受宿主权限影响 |
| MoonBit `js`、`wasm-gc`、`native` | 不支持 |
| WASI Preview 2/3 component model | 不支持 |
| 浏览器内无 WASI polyfill 的 wasm | 不支持 |

底层 ABI 依赖锁定为 `peter-jerry-ye/wasi@0.25.0`。MoonBit 和 Wasmtime 都在快速演进，
升级工具链或运行时时应执行完整的 `bash scripts/test-wasi.sh`。

## 宿主差异

- 目录与文件必须通过运行时 preopen 显式授予；不同运行时的命令行参数可能不同；
- Windows 创建符号链接通常需要开发者模式、管理员权限或宿主的相应支持；集成测试会
  明确记录因 `Perm`/`Notsup` 导致的跳过；
- `fd_datasync`、`fd_sync` 和 rename 的持久化保证受宿主文件系统实现约束；
- 时钟精度是请求值，宿主可以提供较低精度；
- `poll_oneoff` 的可用 descriptor rights 由宿主决定。

## 版本策略

在 `0.x` 阶段，公开 API 仍可能随 MoonBit 和 WASI 生态调整。每次可见变化都应先运行
`moon info` 并审查所有 `pkg.generated.mbti` 差异，再记录到 `CHANGELOG.md`。
