# MoonBit WASI 增强库项目方案

## 项目定位

MoonBit 已能通过底层绑定调用 WASI Preview 1，但应用作者仍需重复实现路径校验、部分
读写、描述符释放、递归文件操作和错误解释。本项目提供一个 capability-aware 的高层
增强库，使 MoonBit CLI/自动化工具可以在不削弱 WASI 沙箱边界的前提下可靠地使用
文件系统和常见系统能力。

目标用户包括 MoonBit CLI 作者、Wasm 插件作者、在线评测/沙箱工具开发者，以及希望
把同一 wasm 程序部署到 Wasmtime 等 Preview 1 宿主的开发者。

## 核心目标

1. 以经过验证的 guest 相对路径作为 capability 敏感 API 的边界；
2. 提供完整读写、metadata、目录遍历、复制、链接、rename 和原子写入；
3. 提供参数、环境、stdio、时钟、随机数和描述符等待等常用系统能力；
4. 将操作、路径和底层 `Errno` 组合成可诊断的统一错误；
5. 用单元测试和真实 Wasmtime 集成测试覆盖纯逻辑与宿主交互；
6. 形成可发布到 mooncakes.io 的模块、文档、示例、许可证和 CI。

非目标包括 Preview 2/3 component model、网络协议栈、通用异步运行时，以及任何绕过
宿主预开放目录的机制。

## 与现有能力的关系

项目复用 `peter-jerry-ye/wasi` 作为 ABI 层，不重复维护 syscall 常量和内联 Wasm
实现。增强层的差异化价值是面向应用的安全语义：规范化路径、上下文错误、完整处理
部分 I/O、确定性目录遍历、失败清理与原子替换。与只覆盖简单读写的便携 IO 抽象相比，
本项目明确面向需要 metadata、rename、链接、walk、copy tree 和同步控制的高级 CLI。

## 架构与交付

模块按 `root -> path -> fs/sys` 的职责划分，依赖只指向内层，公开接口由生成的 `.mbti`
文件审计。交付物包括：

- 四个可独立导入的 MoonBit 包；
- 三个可运行示例；
- 两个真实 WASI 集成程序与纯逻辑测试；
- 中文优先的 README、架构、安全、兼容性和贡献文档；
- GitHub Actions 端到端 CI；
- Apache-2.0 许可证及第三方依赖声明。

## 验收标准

- `moon info && moon fmt` 不产生未提交变更；
- `moon check --deny-warn` 通过；
- `moon test --target wasm` 全部通过；
- release 模式构建所有示例和集成程序；
- Wasmtime 下文件系统、进程、时钟、随机数和 poll 集成测试通过；
- `moon package --frozen` 可生成发布包；
- Git 历史按可审查的功能阶段组织。

## 里程碑

1. 项目骨架、范围与底层依赖；
2. 错误模型和安全路径；
3. capability 文件系统与原子写入；
4. 系统能力；
5. 测试、示例与 CI；
6. 兼容性审计和 mooncakes.io 发布准备。

## AI 辅助开发说明

项目在方案整理、实现草案、文档和测试设计中使用了 AI 辅助。所有纳入仓库的代码均
通过公开接口审查、MoonBit 严格检查、单元测试和真实 Wasmtime 集成测试验证；最终
维护与发布责任由项目作者承担。
