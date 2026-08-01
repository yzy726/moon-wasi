# MoonBit WASI 增强库

一个面向 MoonBit 命令行程序的 capability-aware WASI Preview 1 增强库，提供安全路径、
可靠文件系统操作、原子写入和常用系统能力。

`Ag108/moon-wasi` 建立在 `peter-jerry-ye/wasi` 的底层 ABI 绑定之上，目标后端为
MoonBit `wasm`，当前版本为 `0.1.0`。本项目是原创增强库，不是其他语言项目的移植。

## 特性

- 🛡️ **安全路径**：`GuestPath` 规范化 guest 相对路径，拒绝绝对路径、NUL、反斜杠和
  越过 capability 根的父级跳转
- 📁 **增强文件系统**：支持完整读写、追加、seek/tell、metadata、目录遍历、复制、
  rename、硬链接和符号链接
- ⚛️ **原子写入**：使用同目录 exclusive 临时文件、完整同步和 rename，失败时自动清理
- 🔒 **Capability 模型**：只访问 WASI 运行时显式预开放的目录，不接触或推导宿主路径
- 🧭 **确定性遍历**：分页读取大目录，并以稳定词法顺序返回目录项和深度优先遍历结果
- 🧰 **系统能力**：封装参数、环境变量、stdio、时钟、睡眠、安全随机数和 descriptor poll
- 🧩 **上下文错误**：统一保留操作名、guest 路径和原始 WASI `Errno`
- ✅ **端到端验证**：同时提供 MoonBit 单元测试和真实 Wasmtime 集成测试

## Demo

诊断程序可以显示 WASI 宿主授予的进程和系统能力：

```text
MoonBit WASI diagnostics
arguments: ["main.wasm"]
environment entries: 0
preopens: [{ guest_path: ".", fd: 3 }]
monotonic nanoseconds: 594900
random sample: <Bytes: [...]>
```

原子写入与目录树示例：

```text
wrote target/moon-wasi-example/demo.txt: enabled=true

target/moon-wasi-example
  demo.txt
```

## 快速开始

### 安装依赖

确保已经安装：

- [MoonBit](https://www.moonbitlang.com/) 工具链
- 支持 `wasi_snapshot_preview1` 的运行时，示例使用
  [Wasmtime](https://wasmtime.dev/)

从源码开发本仓库：

```bash
moon install
moon check --deny-warn
```

从 mooncakes.io 安装：

```bash
moon add Ag108/moon-wasi
```

### 配置包

在应用包的 `moon.pkg` 中按需导入：

```moonbit nocheck
import {
  "Ag108/moon-wasi/fs" @wasi_fs,
  "Ag108/moon-wasi/path",
  "Ag108/moon-wasi/sys" @wasi_sys,
  "moonbitlang/core/debug",
}

pkgtype(kind: "executable")
supported_targets = "wasm"
```

### 运行项目

构建并运行原子配置示例：

```bash
moon build --target wasm --release examples/atomic-config
wasmtime run --dir .::. \
  _build/wasm/release/build/examples/atomic-config/atomic-config.wasm \
  target/moon-wasi-example/config.txt "enabled=true"
```

运行系统能力诊断：

```bash
moon build --target wasm --release cmd/main
wasmtime run --dir .::. _build/wasm/release/build/cmd/main/main.wasm
```

输出确定性目录树：

```bash
moon build --target wasm --release examples/tree
wasmtime run --dir .::. \
  _build/wasm/release/build/examples/tree/tree.wasm target
```

### 使用方法

1. 使用 `GuestPath::new` 验证来自参数、环境变量或配置的 guest 路径
2. 使用 `create_dir_all` 创建父目录
3. 调用 `read_text`、`write_text`、`copy_tree` 或 `atomic_write_text` 等高层 API
4. 捕获 `WasiError`，记录操作、guest 路径和底层 errno
5. 启动 wasm 时只预开放应用实际需要的宿主目录

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
      @wasi_sys.eprint("failed: \{@debug.to_string(error)}\n") catch {
        _ => ()
      }
      @wasi_sys.exit(1)
    }
  }
}
```

## 技术架构

### 核心依赖库

| 库名 | 版本 | 用途 |
| --- | --- | --- |
| `peter-jerry-ye/wasi` | 0.25.0 | 提供 WASI Preview 1 ABI、类型和 syscall 绑定 |

本项目不重复维护 ABI 常量和内联 Wasm，而是在底层绑定上实现应用级安全语义。

### 包结构

| 包 | 用途 |
| --- | --- |
| `Ag108/moon-wasi` | `WasiError`、`Operation` 和通用错误上下文 |
| `Ag108/moon-wasi/path` | `GuestPath` 验证、规范化、join、parent 和包含关系 |
| `Ag108/moon-wasi/fs` | 文件、目录、metadata、遍历、复制、链接和原子写入 |
| `Ag108/moon-wasi/sys` | 进程信息、stdio、时钟、随机数和 poll |

### 实现原理

1. **路径验证**：在进入 capability 敏感 API 前完成纯词法规范化和越界检查
2. **Capability 解析**：将 guest 路径解析为预开放 descriptor 与相对路径
3. **可靠 I/O**：循环处理部分读写，并在高层操作的成功和失败路径关闭自建 descriptor
4. **目录遍历**：通过 `fd_readdir` cookie 分页读取，再按名称稳定排序
5. **复制保护**：使用 device/inode 识别硬链接别名，避免把文件复制到自身导致截断
6. **原子发布**：先写入 exclusive 临时文件并同步，再 rename；无覆盖创建使用硬链接
7. **系统封装**：将 process、clock、random 和 `poll_oneoff` 转换为 MoonBit 类型与错误

### 错误和资源所有权

宿主错误使用 `WasiFailure(operation, path, errno)`，调用前校验错误使用
`InvalidInput(operation, reason)`。`message()` 可生成适合命令行日志的说明。

`fs.open` 返回拥有 descriptor 的 `File`，调用者必须恰好调用一次 `close()`。
`read_text`、`write_text`、`copy_file` 等高层 API 会自动关闭它们创建的 descriptor。

`exists` 是将所有不可访问状态折叠为 `false` 的便利接口；需要区分“不存在”和宿主
错误时应使用 `try_exists`。

## 配置

### 目录 Capability

文件系统能力由运行时授予，而不是在 MoonBit 代码中申请：

```bash
# 将当前宿主目录映射为 guest 的相对根目录“.”
wasmtime run --dir .::. app.wasm

# 同时传入环境变量
wasmtime run --dir .::. --env APP_MODE=production app.wasm
```

建议只预开放应用需要的最小目录。`GuestPath` 只表示相对 guest 路径，因此 0.1 版本建议
将主要 preopen 映射为 `.`。

### 测试运行时

测试脚本默认从 `PATH` 查找 `wasmtime`。需要指定其他位置时：

```bash
MOON_WASI_WASMTIME=/path/to/wasmtime bash scripts/test-wasi.sh
```

## 开发

### 项目结构

```text
.
├── cmd/main/                 # WASI 系统能力诊断程序
├── path/                     # 安全 guest 路径
├── fs/                       # 文件系统增强层
├── sys/                      # 进程与系统能力
├── integration/fs/           # Wasmtime 文件系统集成测试
├── integration/sys/          # Wasmtime 系统能力集成测试
├── examples/tree/            # 确定性目录树示例
├── examples/atomic-config/   # 原子配置写入示例
├── docs/                     # 架构与兼容性说明
├── scripts/test-wasi.sh      # 本地与 CI 共用的验收入口
├── moon.mod                  # 模块元数据和依赖
└── README.mbt.md
```

### 代码特点

- **块式组织**：MoonBit block 使用 `///|` 分隔，方便独立审查和重构
- **类型安全**：公开文件系统边界接受 `GuestPath`，而不是未经验证的宿主字符串
- **稳定输出**：目录结果不依赖宿主 `readdir` 顺序
- **失败清理**：descriptor 和原子临时文件覆盖成功与异常退出路径
- **显式策略**：目录复制不隐式跟随符号链接，避免循环和 capability 意外
- **接口审计**：提交生成的 `.mbti` 文件，用于追踪所有公开 API 变化

### 测试

运行完整验收：

```bash
bash scripts/test-wasi.sh
```

脚本会运行接口生成、格式化、严格检查、单元测试、全部 release 构建，以及
`integration/fs` 和 `integration/sys` 两个真实 Wasmtime 集成程序。

也可以分开运行：

```bash
moon info
moon fmt
moon check --deny-warn
moon test --target wasm
moon package --frozen --list
```

MoonBit wasm 单元测试宿主没有实例化全部路径类 WASI import，因此纯逻辑由
`moon test` 验证，真实文件系统调用由独立 wasm 集成程序验证。

## 兼容性

| 项目 | 0.1 支持状态 |
| --- | --- |
| MoonBit `wasm` 后端 | 支持 |
| WASI Preview 1 / `wasi_snapshot_preview1` | 支持 |
| Wasmtime 47 | 已验证 |
| Windows + Wasmtime | 已验证；符号链接受宿主权限影响 |
| MoonBit `js`、`wasm-gc`、`native` | 不支持 |
| WASI Preview 2/3 component model | 不支持 |

已知限制：

- 不提供网络、通用异步运行时、Preview 2/3 或宿主路径访问
- `atomic_write` 无法通过 Preview 1 可移植地同步父目录，掉电语义受宿主文件系统影响
- `atomic_write(..., replace=false)` 依赖宿主授予 `path_link` capability
- `copy_tree` 不会隐式复制或跟随符号链接
- Windows 创建符号链接可能需要开发者模式、管理员权限或额外宿主支持

## 项目文档

- [项目方案](PROJECT_PROPOSAL.md)
- [架构说明](docs/architecture.md)
- [安全说明](SECURITY.md)
- [兼容性说明](docs/compatibility.md)
- [变更记录](CHANGELOG.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)
- [AI 辅助开发说明](AI_USAGE.md)

## 许可证

Apache-2.0 License，完整文本见 [LICENSE](LICENSE)。

## 贡献

欢迎提交 Issue 和 Pull Request。提交前请运行 `bash scripts/test-wasi.sh`，并阅读
[贡献指南](CONTRIBUTING.md)。
