# 架构说明

`Ag108/moon-wasi` 是 `peter-jerry-ye/wasi` 之上的 capability-aware WASI Preview 1
便利层。底层依赖负责 ABI 映射，本项目负责安全路径、上下文错误、描述符生命周期、
可靠文件操作和常用系统能力。

## 分层

```text
应用 / examples / integration
             |
        +----+----+
        |         |
       fs        sys
        |         |
      path      root
        |         |
        +----+----+
             |
    peter-jerry-ye/wasi
             |
      WASI Preview 1 host
```

- 根包 `Ag108/moon-wasi`：定义 `Operation`、`WasiError` 和 errno 转换；
- `path`：定义不依赖宿主的 `GuestPath` 值对象和词法路径操作；
- `fs`：解析预开放目录，拥有并关闭文件描述符，提供文件/目录高层操作；
- `sys`：封装进程输入输出、时钟、随机数与 `poll_oneoff`；
- `integration/*`：在真实 WASI 宿主中验证 ABI 和权限行为。

`fs` 依赖根包与 `path`，`sys` 只依赖根包，根包不反向依赖它们。该方向避免包循环，
也让路径测试无需启动 WASI 宿主。

## 路径与 capability

WASI 文件系统调用以预开放目录的 descriptor 和相对路径工作。`GuestPath` 在进入 `fs`
前完成词法规范化：移除 `.` 与重复 `/`，折叠安全的 `..`，并拒绝绝对路径、反斜杠、
NUL 和越过 capability 根的父级跳转。它不会把 guest 路径转换成宿主路径，也不会扩大
运行时授予的 rights。

`resolve` 使用底层依赖查找覆盖该 guest 路径的预开放 descriptor，再把相对部分交给
WASI。最终权限仍由运行时的 preopen 与 rights 决定。

## I/O 与资源生命周期

`File` 表示一个拥有所有权的 descriptor。低层 `read_all` 与 `write_all` 明确处理部分
读写；高层函数使用失败清理保证关闭自建 descriptor。调用者直接使用 `open` 时负责
恰好关闭一次文件。

目录列表在返回前使用 Unicode 字符串词法顺序排序，`walk` 在此基础上执行稳定的
深度优先遍历。因此测试输出和构建工具结果不依赖宿主 `readdir` 顺序。

## 原子写入

`atomic_write` 在目标文件的同一目录生成随机临时名，以 `create_new` 防止碰撞，写完后
执行完整 `fd_sync`。默认通过 `path_rename` 替换目标；`replace=false` 则用硬链接原子
发布一个尚不存在的目标，再移除临时名字。任何失败都会尽力删除临时文件。同目录策略
避免跨文件系统 rename；Preview 1 无可移植父目录 fsync，因此最终掉电语义仍由宿主
文件系统决定。

## 错误模型

所有宿主错误转换成：

```text
WasiFailure(operation, optional_guest_path, errno)
```

调用前校验失败转换成：

```text
InvalidInput(operation, explanation)
```

这样既能保留用于分支处理的 `Errno`，又能通过 `message()` 生成包含操作与路径的日志。

## 测试策略

- `*_test.mbt`：路径规范化和稳定、纯函数语义；
- `integration/fs`：真实文件、目录、metadata、seek、copy、link 和 atomic write；
- `integration/sys`：参数、环境、preopen、clock、random 和 descriptor poll；
- `scripts/test-wasi.sh`：本地与 CI 共用的唯一端到端入口。

MoonBit wasm 测试宿主未实例化所有路径类 WASI import，因此会访问文件系统的测试被
编译为普通 wasm 可执行程序，再由 Wasmtime 运行。
