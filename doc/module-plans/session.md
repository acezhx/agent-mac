# Session 模块开发计划

## 模块目标

`Session` 负责一次 Agent 对话的生命周期编排。它接收已校验的 `ResolvedAgentConfig`，调用
`RuntimeBridge` 启动 runtime，发送消息，接收流式输出，并维护会话状态。

## 依赖关系

```text
Session
  -> AgentLibrary
  -> FileStore
  -> RuntimeBridge
```

第一阶段不依赖完整 `Approval`。遇到工具审批请求时使用默认拒绝策略。

## 需要开发的功能

### Session 状态

- 定义 `SessionState`：
  - idle
  - running
  - failed
  - aborted
- 后续增加 waitingForApproval。
- 状态变化应可被 AppShell 的 TCA Feature 观察或订阅。

### 消息模型

- 定义用户消息。
- 定义 assistant 消息。
- 支持 streaming delta 合并到当前 assistant 消息。
- 支持错误消息或诊断信息。

### 会话启动

- 接收 `ResolvedAgentConfig`。
- 接收 workspace。
- 调用 RuntimeBridge `startSession`。
- 保存 session 完整 record。

### 持久化与恢复

- 保存完整消息历史。
- 保存结构化错误和临时工具审批决策。
- 支持读取旧版基础 record，缺失消息历史时按空列表恢复。
- 冷启动恢复不重新附着旧 Runtime Host session。
- 恢复到 running 的旧 record 时降级为 failed，并关闭 streaming 消息。

### Session 管理

- 创建新的 `ChatSession` 并写入初始 record。
- 基于 session id 加载和缓存 `ChatSession`。
- 列出 session 摘要。
- 删除 session record。

### 消息发送

- 将用户输入追加到消息列表。
- 调用 RuntimeBridge `sendMessage`。
- 接收 streaming delta。
- 在 completed 后结束本轮 running 状态。
- 上一轮消息未完成时不做队列调度，直接返回结构化错误。

### 错误和中断

- runtime error 进入 failed。
- 用户 abort 进入 aborted。
- abort 后忽略迟到的非终态 Runtime events。
- failed/aborted 状态继续发送或启动前需要显式 reset。
- 支持重置到 idle。

### 审批扩展点

- 定义 `ToolApprovalRequest` 和 `ToolApprovalDecision` 的临时边界类型。
- 第一阶段默认返回 denied/unsupported。
- 不让审批请求导致 session 崩溃。

## Checklist

- [x] 创建 `AgentMac/Session/` 目录。
- [x] 定义 `ChatSession`。
- [x] 定义 `ChatMessage`。
- [x] 定义 `SessionState`。
- [x] 定义 `SessionError`。
- [x] 定义临时 `ToolApprovalRequest`。
- [x] 定义临时 `ToolApprovalDecision`。
- [x] 实现创建 session。
- [x] 实现启动 session。
- [x] 实现发送用户消息。
- [x] 实现 assistant delta 合并。
- [x] 实现 completed 状态处理。
- [x] 实现 failed 状态处理。
- [x] 实现 abort。
- [x] 实现生命周期边界错误。
- [x] 实现 abort 后迟到 event 处理。
- [x] 实现默认审批拒绝。
- [x] 实现 session 记录保存。
- [x] 实现完整 session record。
- [x] 实现 `SessionStore`。
- [x] 实现冷启动恢复策略。
- [x] 实现 `ChatSessionManager`。
- [x] 编写 Session 单元测试。

## 当前实现

- `ChatSession` 接收 `ResolvedAgentConfig`、`FileStore` 和 `RuntimeBridge` 边界协议，当前按协议启动
  `fixedCodingAgent` session，并把 workspace 传给 Runtime Host。
- `ChatSessionSnapshot` 通过 `AsyncStream` 暴露状态和消息快照，供后续 AppShell/TCA 订阅。
- `ChatMessage` 支持 user、assistant 和 diagnostic 三类消息；assistant delta 会合并到当前 streaming
  assistant 消息，`messageCompleted` 后结束 streaming 并回到 idle。
- RuntimeBridge error 会映射为 `SessionError`，session 进入 failed 并追加 diagnostic 消息。
- `abort()` 会调用 RuntimeBridge `abortSession`，收到 `sessionAborted` 后进入 aborted 并清空 runtime
  session id。
- `start()` 不会重复创建 Runtime Host session；failed 或 aborted 状态必须先 `reset()` 再复用。
- `sendUserMessage()` 不做队列调度；上一轮消息未完成、failed 或 aborted 状态会返回结构化
  `SessionError`，不会追加新的用户消息。
- `sessionAborted` 后迟到的 Runtime events 会被忽略，避免 aborted 终态被后续 delta 或 completed 覆盖。
- 未知非 error Runtime events 按 Runtime 协议记录日志并忽略，避免新增 event 破坏旧 Session。
- `reset()` 会写入重置后的完整 record；持久化失败时抛出结构化错误，并保留原内存状态。
- 临时 `ToolApprovalRequest`、`ToolApprovalDecision` 和 `ToolApprovalHandling` 保留 Approval 扩展点；
  默认实现返回 unsupported，并写入 diagnostic，不接 UI。
- 完整 session record 保存为 `sessions/<session-id>.json`，包含 session 元数据、消息历史、结构化错误和临时
  工具审批决策，并兼容旧版无 `messages` 的基础 record。
- `SessionStore` 负责 record 的 JSON 编解码、列表摘要和删除。
- `ChatSessionManager` 负责创建、缓存、恢复、列出和删除 session；恢复时通过 Agent 配置解析边界重新取得
  `ResolvedAgentConfig`，不会直接解析 Agent manifest。
- 冷启动恢复会清空旧 `runtimeSessionID`；如果磁盘状态仍为 running，会转为 failed，并追加
  `runtimeSessionDetached` 诊断消息。

## 验证方法

```text
xcodebuild test -scheme AgentMac -destination 'platform=macOS' -only-testing:AgentMacTests/SessionTests
xcodebuild test -scheme AgentMac -destination 'platform=macOS' -only-testing:AgentMacTests/FileStoreTests
xcodebuild test -scheme AgentMac -destination 'platform=macOS' -only-testing:AgentMacTests/RuntimeBridgeTests
```

## 验收标准

- 新建 session 初始状态为 idle。
- 启动 session 后状态进入 running。
- 用户消息能追加到消息列表。
- assistant delta 能合并成一条正在生成的 assistant 消息。
- completed event 后状态回到 idle。
- runtime error 后状态进入 failed，并保留错误信息。
- abort 后状态进入 aborted。
- 已启动的 session 重复 start 会返回结构化错误，不会再次调用 RuntimeBridge。
- 上一轮消息未完成时再次 send 会返回结构化错误，不会追加新消息。
- failed/aborted 状态继续 send 会返回结构化错误，调用方需要显式 reset。
- abort 后迟到的 assistant delta、completed 和工具审批 event 不会覆盖 aborted 状态。
- 工具审批请求会得到默认 denied/unsupported，不会导致崩溃。
- 可以保存完整 session 记录到 `sessions/`。
- 可以恢复完整消息历史、失败状态和临时审批决策。
- 可以通过管理层创建、缓存、列出和删除 session。
- 冷恢复 running record 时不会复用旧 Runtime session。

## 第一版不做

- 不做完整审批 UI。
- 不做 Runtime Host 进程级 resume/reattach。
- 不做多会话并发调度策略。
- 不做消息搜索。
- 不做会话导出。
