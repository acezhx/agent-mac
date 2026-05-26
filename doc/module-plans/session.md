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
- 状态变化应可被 UI 观察。

### 消息模型

- 定义用户消息。
- 定义 assistant 消息。
- 支持 streaming delta 合并到当前 assistant 消息。
- 支持错误消息或诊断信息。

### 会话启动

- 接收 `ResolvedAgentConfig`。
- 接收 workspace。
- 调用 RuntimeBridge `startSession`。
- 保存 session 基础元数据。

### 消息发送

- 将用户输入追加到消息列表。
- 调用 RuntimeBridge `sendMessage`。
- 接收 streaming delta。
- 在 completed 后结束本轮 running 状态。

### 错误和中断

- runtime error 进入 failed。
- 用户 abort 进入 aborted。
- 支持重置到 idle。

### 审批扩展点

- 定义 `ToolApprovalRequest` 和 `ToolApprovalDecision` 的临时边界类型。
- 第一阶段默认返回 denied/unsupported。
- 不让审批请求导致 session 崩溃。

## Checklist

- [ ] 创建 `AgentMac/Session/` 目录。
- [ ] 定义 `ChatSession`。
- [ ] 定义 `ChatMessage`。
- [ ] 定义 `SessionState`。
- [ ] 定义 `SessionError`。
- [ ] 定义临时 `ToolApprovalRequest`。
- [ ] 定义临时 `ToolApprovalDecision`。
- [ ] 实现创建 session。
- [ ] 实现启动 session。
- [ ] 实现发送用户消息。
- [ ] 实现 assistant delta 合并。
- [ ] 实现 completed 状态处理。
- [ ] 实现 failed 状态处理。
- [ ] 实现 abort。
- [ ] 实现默认审批拒绝。
- [ ] 实现基础 session 记录保存。
- [ ] 编写 Session 单元测试。

## 验收标准

- 新建 session 初始状态为 idle。
- 启动 session 后状态进入 running。
- 用户消息能追加到消息列表。
- assistant delta 能合并成一条正在生成的 assistant 消息。
- completed event 后状态回到 idle。
- runtime error 后状态进入 failed，并保留错误信息。
- abort 后状态进入 aborted。
- 工具审批请求会得到默认 denied/unsupported，不会导致崩溃。
- 可以保存基础 session 记录到 `sessions/`。

## 第一版不做

- 不做完整审批 UI。
- 不做复杂会话恢复。
- 不做多会话并发调度。
- 不做消息搜索。
- 不做会话导出。
