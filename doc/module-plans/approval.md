# Approval 模块开发计划

## 模块目标

`Approval` 在基础 chat session 跑通后实现。它负责工具请求的权限判断和用户确认，确保高风险
操作在 macOS UI 中可见、可拒绝、可追踪。

## 依赖关系

实现前：

```text
Approval
  -> not implemented
```

实现后：

```text
AppShell
  -> Approval

Session
  -> Approval

Approval
  -> AgentLibrary
```

## 需要开发的功能

### 审批请求模型

- 定义 `ToolApprovalRequest`。
- 定义 `ToolApprovalDecision`。
- 定义 `ApprovalService`。
- 定义请求来源和风险类型。
- 支持请求详情展示。

### 权限策略解释

- 读取 Agent 的权限配置。
- 支持 allow。
- 支持 ask。
- 支持 deny。
- 按 tool 类型判断：
  - shell
  - edit
  - write
  - network
  - secrets

### UI 交互

- 通过 AppShell 的 TCA Feature 接入审批 UI。
- 展示审批请求。
- 展示命令或工具名称。
- 展示目标路径或网络目标。
- 展示风险说明。
- 支持批准。
- 支持拒绝。
- 支持记住本次会话可以后置。

### Runtime 回传

- 将 approved 返回 Runtime Host。
- 将 denied 返回 Runtime Host。
- 用户关闭弹窗时按 denied 处理。
- 记录审批结果用于诊断。

## Checklist

- [x] 创建 `AgentMac/Approval/` 目录。
- [x] 从 Session/RuntimeBridge 迁移临时审批类型。
- [x] 定义 `ToolApprovalRequest`。
- [x] 定义 `ToolApprovalDecision`。
- [x] 在 `ApprovalService` 中实现权限策略解释逻辑。
- [x] 实现 `ApprovalService`。
- [x] 支持 allow/ask/deny。
- [x] 支持 shell 请求。
- [x] 支持 edit/write 请求。
- [x] 支持 network 请求。
- [x] 支持 secrets 请求。
- [x] 实现审批 UI。
- [x] 通过 AppShell/TCA 接入审批 UI。
- [x] 将审批结果回传 Session。
- [x] 将审批结果回传 Runtime Host。
- [x] 编写 Approval 单元测试。
- [ ] 手工验证批准和拒绝路径。

## 验收标准

- runtime 返回工具审批请求时，UI 能展示请求详情。
- 审批 UI 状态、用户选择和异步回传由 TCA Feature 管理。
- 权限为 allow 时可以自动批准低风险请求。
- 权限为 ask 时 UI 会等待用户选择。
- 权限为 deny 时会直接拒绝。
- 用户批准后 Runtime Host 收到 approved。
- 用户拒绝后 Runtime Host 收到 denied。
- 用户关闭审批 UI 时按 denied 处理。
- shell、edit、network 至少各有一个测试覆盖。
- 默认策略保持谨慎，不自动执行高风险工具。

## 第一版不做

- 不做长期记住审批。
- 不做团队策略管理。
- 不做复杂规则 DSL。
- 不做跨 Agent 的全局审批策略。
- 不做审计报表。
