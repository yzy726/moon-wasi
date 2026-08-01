# 变更记录

本项目遵循语义化版本的意图；`0.x` 版本可能包含公开 API 调整。

## 0.1.0 - 未发布

### 新增

- capability-aware `GuestPath` 规范化与路径操作；
- 统一 `WasiError`、操作上下文与原始 WASI errno；
- 文件完整读写、追加、seek/tell、metadata 和同步；
- 目录创建、稳定读取、遍历、复制和递归删除；
- rename、硬链接、符号链接与 readlink；
- 同目录临时文件、完整同步和 rename 组成的原子写入；
- 参数、环境、preopen、stdio、时钟、随机数和 descriptor poll；
- 单元测试、Wasmtime 集成测试、三个示例和 GitHub Actions CI。

### 已知限制

- 仅支持 MoonBit `wasm` 后端与 WASI Preview 1；
- Windows 符号链接创建取决于宿主权限；
- Preview 1 无可移植父目录同步接口。
