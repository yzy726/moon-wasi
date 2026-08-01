# 贡献指南

感谢改进 `moon-wasi`。请让每次变更聚焦一个可审查目标，并在提交信息中说明用户可见
行为。公开 API 变更应同时更新文档、测试和 `CHANGELOG.md`。

## 开发环境

安装 MoonBit、Wasmtime 与 Bash，然后在仓库根目录运行：

```bash
moon install
bash scripts/test-wasi.sh
```

提交前至少确认：

```bash
moon info
moon fmt
moon check --deny-warn
moon test --target wasm
git diff --check
git status --short
```

`moon info` 生成的 `.mbti` 文件需要随公开接口变化一起提交。如果它们发生变化，请逐项
确认是预期 API，而不是意外暴露的字段或函数。

## 代码约定

- MoonBit block 之间使用 `///|`；
- capability 敏感的文件系统 API 接受 `GuestPath`；
- 传播宿主错误时保留 `Operation`、guest 路径和原始 `Errno`；
- 获取 descriptor 的代码必须覆盖成功与异常退出的关闭路径；
- 稳定值优先用断言测试，复杂结构输出才使用 snapshot；
- 新增真实 WASI syscall 时同时扩展 `integration/fs` 或 `integration/sys`。

## 兼容性

不要假设某个 POSIX 扩展在所有 WASI 宿主存在。宿主差异需要文档化，并尽可能返回带
上下文的错误，而不是静默降级。详见 `docs/compatibility.md`。
