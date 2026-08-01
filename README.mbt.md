# moon-wasi

`Ag108/moon-wasi` 是面向 MoonBit 命令行程序的 WASI Preview 1 增强库。它建立在
`peter-jerry-ye/wasi` 的底层 ABI 绑定之上，补充安全的 guest 路径、带上下文的错误、
可靠的文件与目录操作、原子写入，以及进程、时钟、随机数和描述符轮询等高层能力。

> English summary: capability-aware, ergonomic WASI Preview 1 utilities for
> MoonBit CLI applications, with deterministic filesystem operations and
> contextual error handling.

当前版本：`0.1.0`。目标后端是 MoonBit `wasm`，运行环境需提供
`wasi_snapshot_preview1`。

## 为什么需要这个库

底层 WASI 接口适合精确控制 ABI，但应用通常还需要处理部分读写、文件描述符回收、
路径穿越、递归目录、稳定遍历顺序和错误上下文。`moon-wasi` 将这些重复且容易出错的
工作封装为 MoonBit API，同时保留 WASI 的 capability 模型：程序只能访问宿主显式
预开放的目录。

主要能力：

- `GuestPath`：规范化 `/` 分隔的 guest 相对路径，拒绝绝对路径、NUL、反斜杠和越界
  的 `..`；
- 文件 API：完整读写、追加、seek/tell、metadata、显式数据或完整同步；
- 目录 API：递归创建/删除、稳定排序的读取与深度优先遍历、文件和目录树复制；
- 链接与移动：rename、硬链接、符号链接及 readlink；
- 原子替换：同目录临时文件、完整同步、rename 和失败清理；
- 系统 API：参数、环境变量、预开放目录、stdio、时钟、睡眠、安全随机数和 poll；
- 统一错误：保留操作名、guest 路径和原始 WASI `Errno`。

## 安装

需要近期 MoonBit 工具链，以及可运行 WASI Preview 1 模块的运行时（示例使用
[Wasmtime](https://wasmtime.dev/)）。`0.1.0` 发布到 mooncakes.io 后可执行：

```bash
moon add Ag108/moon-wasi
```

从源码开发本仓库时执行：

```bash
moon install
moon check --deny-warn
```

应用包的 `moon.pkg` 可按需导入：

```moonbit nocheck
import {
  "Ag108/moon-wasi/fs" @wasi_fs,
  "Ag108/moon-wasi/path",
  "Ag108/moon-wasi/sys" @wasi_sys,
}

pkgtype(kind: "executable")
supported_targets = "wasm"
```

## 快速示例

下面的程序安全地创建父目录并原子更新 UTF-8 配置：

```moonbit nocheck
///|
fn main {
  try {
    let path = @path.GuestPath::new("state/config.txt")
    match path.parent() {
      Some(parent) => @wasi_fs.create_dir_all(parent)
      None => ()
    }
    @wasi_fs.atomic_write_text(path, "enabled=true\n")
    @wasi_sys.print(@wasi_fs.read_text(path))
  } catch {
    error => {
      @wasi_sys.eprint("failed: \{error.message()}\n") catch {
        _ => ()
      }
      @wasi_sys.exit(1)
    }
  }
}
```

仓库内已提供同类可执行示例。构建并在 Wasmtime 中运行：

```bash
moon build --target wasm --release examples/atomic-config
wasmtime run --dir .::. \
  _build/wasm/release/build/examples/atomic-config/atomic-config.wasm \
  target/moon-wasi-example/config.txt "enabled=true"
```

`--dir .::.` 将当前宿主目录预开放为 guest 的 `.`。不授予该能力时，文件系统调用会
按 WASI 设计失败；库不会尝试绕过运行时沙箱。

另外两个示例：

```bash
# 参数、环境、预开放目录、时钟和随机数诊断
moon build --target wasm --release cmd/main
wasmtime run --dir .::. _build/wasm/release/build/cmd/main/main.wasm

# 确定性目录树（可在命令末尾传入 guest 路径）
moon build --target wasm --release examples/tree
wasmtime run --dir .::. \
  _build/wasm/release/build/examples/tree/tree.wasm target
```

## 包结构

| 包 | 用途 |
| --- | --- |
| `Ag108/moon-wasi` | `WasiError`、`Operation` 和通用错误上下文 |
| `Ag108/moon-wasi/path` | `GuestPath` 验证、规范化、join/parent/包含关系 |
| `Ag108/moon-wasi/fs` | 文件、目录、遍历、复制、链接和原子写入 |
| `Ag108/moon-wasi/sys` | 进程信息、stdio、时钟、随机数和 poll |

生成的 `pkg.generated.mbti` 文件是各包完整的公开接口索引。设计取舍见
[架构说明](docs/architecture.md)，运行时差异见[兼容性说明](docs/compatibility.md)，
安全边界见[安全说明](SECURITY.md)。

## 错误处理与资源所有权

所有可能失败的高层操作都抛出 `WasiError`。`WasiFailure` 保留原始
`peter-jerry-ye/wasi.Errno`，`InvalidInput` 表示在调用宿主前发现的无效状态。
可以通过 `message()` 获得适合日志记录的上下文文本。

`fs.open` 返回拥有描述符的 `File`，调用者必须恰好调用一次 `close()`。`read_text`、
`write_text`、`copy_file` 等高层函数会在成功和失败路径中自动关闭它们拥有的描述符。

## 测试

纯逻辑测试由 MoonBit 测试运行器执行，真实 WASI 行为由独立 wasm 程序在 Wasmtime
中验证：

```bash
bash scripts/test-wasi.sh
```

该命令依次运行接口生成、格式化、严格检查、单元测试、全部示例构建，并执行文件系统
与系统集成测试。也可分开运行：

```bash
moon info
moon fmt
moon check --deny-warn
moon test --target wasm
```

MoonBit 自带的 wasm 单元测试宿主目前没有实例化全部路径类 WASI import，因此真实
文件系统测试采用 `integration/fs` 和 `integration/sys` 两个可执行包。

## 范围与限制

- 只支持 WASI Preview 1 与 MoonBit 线性内存 `wasm` 后端；
- 不提供网络、异步运行时、Preview 2/3 component model 或宿主路径访问；
- `atomic_write` 保证同一预开放文件系统内的临时文件同步后 rename，但 Preview 1
  没有可移植的父目录同步接口；掉电一致性仍受宿主文件系统影响；
- 复制目录树不会隐式跟随符号链接，避免越过调用者预期的目录边界；
- Windows 宿主创建符号链接可能需要开发者模式或额外权限。

## 项目资料

- [项目方案](PROJECT_PROPOSAL.md)
- [贡献指南](CONTRIBUTING.md)
- [变更记录](CHANGELOG.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)

本项目采用 [Apache-2.0](LICENSE) 许可证。
