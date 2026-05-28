# AgentMac 开发计划

## 目标

第一版开发目标是跑通一个完整的本地闭环：

1. App 内置 Node.js 和 Pi。
2. SwiftUI 可以启动 Node Runtime Host。
3. Node Runtime Host 可以启动固定的 Pi coding agent。
4. 用户可以从 macOS UI 发送消息。
5. assistant 回复可以流式显示在 UI 中。
6. Agent/Resource 管理和工具审批闭环已补入第一版；可配置 Agent 会话和资源选择仍后续接入。

第一阶段不做数据库、资源版本管理、发布回滚、向量索引和团队同步。

## 模块开发顺序

```text
FileStore
-> ResourceLibrary
-> AgentLibrary
-> RuntimeHost
-> RuntimeBridge
-> Session
-> AppShell
-> Approval
-> 集成打磨
```

`Approval` 已作为后置模块补入。基础 chat session 阶段曾先保留审批扩展点；当前第一版已支持
工具审批请求展示、allow/deny 回传和默认谨慎策略。

## 前置契约文档

- [项目目标与规范](project-goals-and-standards.md)
- [技术设计](technical-design.md)
- [文件格式与 Schema](schemas-and-file-formats.md)
- [Runtime 通信协议](runtime-protocol.md)
- [Runtime 打包方案](runtime-packaging.md)
- [测试策略](testing-strategy.md)

## 模块明细计划

- [FileStore](module-plans/filestore.md)
- [ResourceLibrary](module-plans/resourcelibrary.md)
- [AgentLibrary](module-plans/agentlibrary.md)
- [RuntimeHost](module-plans/runtimehost.md)
- [RuntimeBridge](module-plans/runtimebridge.md)
- [Session](module-plans/session.md)
- [AppShell](module-plans/appshell.md)
- [Approval](module-plans/approval.md)

## 阶段 1：FileStore

目标：建立稳定的本地文件读写基础。

开发内容：

- 创建 Application Support 根目录。
- 创建 `agents/`、`library/`、`sessions/`、`settings.yaml` 所需路径。
- 实现文本文件读写。
- 实现 YAML 文件读写。
- 实现目录扫描。
- 实现安全路径解析，避免路径逃逸。

验收标准：

- 可以在临时目录中初始化完整数据目录结构。
- 可以读写文本文件和 YAML 文件。
- 扫描目录时能列出 Agent 和资源库条目。
- 传入越界路径时返回错误，不访问目标文件。

## 阶段 2：ResourceLibrary

目标：维护共享 knowledge、skills、tools。

开发内容：

- 列出 `library/knowledge/` 下的 Markdown 或纯文本 knowledge。
- 创建和编辑 knowledge 文件。
- 列出 `library/skills/` 下的 skill 目录。
- 校验 skill 目录至少包含 `SKILL.md`。
- 创建和编辑 `SKILL.md`。
- 列出 `library/tools/` 下的 tool 目录。
- 校验 tool 目录包含 `tool.yaml`，且 `tool.yaml.entry` 指向的入口文件存在。
- 创建和编辑 `tool.yaml` 和入口文件。

验收标准：

- `.md` knowledge 能被识别。
- 包含 `SKILL.md` 的目录能被识别为 skill。
- 缺失 `SKILL.md` 的 skill 目录会校验失败。
- 包含 `tool.yaml` 且入口文件存在的目录能被识别为 tool。
- 缺失 `tool.yaml` 的 tool 目录会校验失败。
- `tool.yaml.entry` 指向的入口文件不存在时会校验失败。

## 阶段 3：AgentLibrary

目标：维护 Agent 定义，并生成运行时需要的配置。

开发内容：

- 创建 Agent 目录。
- 创建初始 `agent.yaml`。
- 创建 Agent 私有的 `system.md`。
- 加载 Agent。
- 保存 Agent 基本信息、模型配置、权限配置。
- 保存 Agent 选择的 knowledge、skills、tools。
- 校验 Agent 引用的资源是否存在。
- 生成 `ResolvedAgentConfig`。

验收标准：

- 创建 Agent 后会生成 `agent.yaml` 和 `system.md`。
- 缺失 `system.md` 时校验失败。
- 引用不存在的 knowledge、skill 或 tool 时校验失败。
- 合法 Agent 可以解析出绝对路径形式的运行时配置。

## 阶段 4：RuntimeHost

目标：实现 Node 侧最小运行时桥接，并接入固定 Pi coding agent。

开发内容：

- 创建 Node Runtime Host 入口。
- 支持 JSONL 输入输出。
- 支持 `ping` 命令。
- 支持 `startSession` 命令。
- 支持 `sendMessage` 命令。
- 先返回模拟 streaming event，验证协议。
- 接入固定 Pi coding agent 模式。
- 固定 Pi coding agent 模式不读取用户 `agent.yaml`，只用于验证基础 chat session 主链路。
- 将 Pi events 转成 App 侧稳定事件格式。

验收标准：

- 可以从命令行启动 Runtime Host。
- 输入 `ping` 后返回 `pong`。
- 输入 `startSession` 后返回 session started 事件。
- 输入 `sendMessage` 后能收到流式 assistant 输出事件。
- 固定 Pi coding agent 可以在 Runtime Host 内正常启动。
- 固定 Pi coding agent 模式不依赖用户创建 Agent。

## 阶段 5：RuntimeBridge

目标：实现 Swift 侧与 Node Runtime Host 的进程通信。

开发内容：

- 定位内置 Node 可执行文件。
- 定位 Runtime Host 脚本。
- 启动 Runtime Host 进程。
- 向 Runtime Host 写入 JSONL command。
- 从 Runtime Host 读取 JSONL event。
- 将 runtime event 映射成 Swift 类型。
- 处理进程退出、启动失败、协议解析失败。

验收标准：

- Swift 代码可以启动 Runtime Host。
- Swift 代码可以发送 `ping` 并收到 `pong`。
- Swift 代码可以发送 `startSession` 和 `sendMessage`。
- Swift 代码可以接收流式输出事件。
- Runtime Host 异常退出时能返回可诊断错误。

## 阶段 6：Session

目标：编排一次 Agent 会话。

开发内容：

- 定义 session 状态：idle、running、failed、aborted。
- 创建 session。
- 接收 `ResolvedAgentConfig`。
- 调用 RuntimeBridge 启动会话。
- 发送用户消息。
- 追加 assistant 流式输出。
- 保存完整 session 记录并支持冷启动恢复。
- 提供 session 创建、加载、列表和删除管理层。
- 预留工具审批事件扩展点；Approval 模块接入后等待 UI 决策并回传 Runtime Host。

验收标准：

- session 状态可以从 idle 进入 running，再回到 idle。
- 用户消息能追加到消息列表。
- assistant streaming delta 能合并展示。
- runtime error 能让 session 进入 failed。
- 工具审批请求不会导致 session 崩溃，会记录审批结果。

## 阶段 7：AppShell

目标：基于 SwiftUI + TCA 实现第一版最小 UI。

开发内容：

- 创建根 `AppFeature`。
- 将 Agent 管理、资源管理、会话页面拆成 TCA 子 Feature。
- 通过 TCA dependency 接入 `AgentLibrary`、`ResourceLibrary` 和 `Session`。
- App 根视图和导航。
- Agent 列表。
- Agent 创建入口。
- Agent 编辑页。
- system prompt 编辑器。
- knowledge、skills、tools 资源选择。
- 会话页面。
- 消息输入框。
- 流式 assistant 输出展示。
- 基础错误提示。

验收标准：

- UI 状态、用户 action 和异步 effect 由 TCA Feature 管理。
- SwiftUI View 不直接调用底层服务模块。
- 用户可以创建 Agent。
- 用户可以编辑 Agent 的 system prompt。
- 用户可以选择 knowledge、skills、tools。
- 用户可以选择一个 Agent 启动会话。
- 用户可以从 macOS UI 发送消息。
- 固定 Pi coding agent 的回复可以流式显示在 UI 中。

## 阶段 8：Approval

目标：在基础 chat session 跑通后，补上工具审批能力。

开发内容：

- 实现 `ApprovalService`。
- 定义审批请求 UI。
- 审批 UI 通过 AppShell 的 TCA Feature 接入。
- 支持 allow、ask、deny。
- 根据 Agent 权限配置判断工具请求。
- 对 shell、edit、network 等敏感工具请求展示确认。
- 将用户批准或拒绝结果返回 Session 和 Runtime Host。

验收标准：

- runtime 返回工具审批请求时，UI 能展示请求详情。
- 用户批准后，Runtime Host 收到 approved。
- 用户拒绝后，Runtime Host 收到 denied。
- 默认策略仍然保持谨慎，不自动执行高风险工具。

## 阶段 9：集成打磨

目标：让第一版可以作为一个独立 macOS App 运行。

开发内容：

- 将 Node.js 和 Pi runtime 放入 app bundle。
- 修正 app bundle 内 runtime 路径。
- 确保可变数据全部写入 Application Support。
- 增加运行时日志。
- 增加首次启动目录初始化。
- 增加常见错误提示。
- 验证干净环境启动。

验收标准：

- 在未单独安装 Pi 的机器上可以启动 App。
- App 能启动内置 Runtime Host。
- 固定 Pi coding agent 可以从 macOS UI 跑通基础 chat session。
- assistant 回复能流式展示。
- 运行中产生的数据不会写入 app bundle。

## 第一版关键里程碑

### 里程碑 1：文件配置闭环

完成 `FileStore`、`ResourceLibrary`、`AgentLibrary`。

验收：可以通过文件系统创建一个合法 Agent，并解析出运行时需要的配置。

### 里程碑 2：固定 Pi coding agent 闭环

完成 `RuntimeHost`、`RuntimeBridge`、`Session` 的基础能力。

验收：从 macOS UI 发送一条消息，Runtime Host 能启动固定 Pi coding agent，assistant 回复
可以流式显示。

### 里程碑 3：可配置 Agent 闭环

完成 Agent 编辑和资源选择 UI。

验收：用户可以创建 Agent、编辑 system prompt、选择 knowledge/skills/tools，并用该配置
启动会话。

### 里程碑 4：工具审批闭环

完成 `Approval`。

验收：工具请求能在 UI 中等待确认，用户批准或拒绝后 runtime 能继续或停止对应操作。

## 开发原则

- 一个模块一个模块开发，不跳过底层依赖。
- 每个模块完成时都要有可运行或可测试的验收点。
- 先跑通固定 Pi coding agent，再做完整可配置 Agent。
- 先做文件型配置，不引入数据库。
- 基础 chat session 先默认拒绝工具审批请求；Approval 阶段补上 UI 确认和回传闭环。
- 服务层先行，UI 后接入。
