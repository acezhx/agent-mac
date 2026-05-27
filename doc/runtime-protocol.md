# Runtime 通信协议

## 目标

本文定义 Swift App 与 Node Runtime Host 之间的第一版 JSONL 通信协议。`RuntimeHost` 和
`RuntimeBridge` 必须同时遵守该协议。

协议目标：

- 简单。
- 可流式传输。
- 易于调试。
- 与 Pi 内部事件解耦。
- 支持后续工具审批扩展。

## 传输方式

第一版使用 stdin/stdout JSONL：

- Swift 通过 Runtime Host stdin 写入 command。
- Runtime Host 通过 stdout 写出 event。
- Runtime Host 通过 stderr 写诊断日志。
- 每一行都是一个完整 JSON object。
- JSON object 之间使用 `\n` 分隔。
- 不在 stdout 输出非 JSON 内容。

## Command Envelope

Swift 发送的 command 使用统一 envelope。

```json
{
  "type": "command",
  "id": "cmd_001",
  "name": "ping",
  "payload": {}
}
```

字段：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `type` | string | 是 | 固定为 `command`。 |
| `id` | string | 是 | command id，由 Swift 生成。 |
| `name` | string | 是 | command 名称。 |
| `payload` | object | 否 | command 参数。 |

## Event Envelope

Runtime Host 输出的 event 使用统一 envelope。

```json
{
  "type": "event",
  "id": "evt_001",
  "replyTo": "cmd_001",
  "name": "pong",
  "payload": {}
}
```

字段：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `type` | string | 是 | 固定为 `event`。 |
| `id` | string | 是 | event id，由 Runtime Host 生成。 |
| `replyTo` | string/null | 否 | 对应 command id。流式事件可复用同一个 `replyTo`。 |
| `sessionId` | string | 否 | session 相关事件携带。 |
| `name` | string | 是 | event 名称。 |
| `payload` | object | 否 | event 内容。 |

## Error Event

错误统一使用 `error` event。

```json
{
  "type": "event",
  "id": "evt_error_001",
  "replyTo": "cmd_001",
  "name": "error",
  "payload": {
    "code": "unsupported_command",
    "message": "Unsupported command: unknown",
    "recoverable": true
  }
}
```

字段：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `code` | string | 是 | 机器可读错误码。 |
| `message` | string | 是 | 人类可读错误信息。 |
| `recoverable` | bool | 是 | 是否可继续使用当前 Runtime Host。 |
| `details` | object | 否 | 诊断信息。 |

## Session Agent Modes

`startSession.payload.agent` 第一版支持两种形态：

```text
fixedCodingAgent:
  基础 chat session 阶段使用。Runtime Host 使用内置 Pi coding agent 配置启动 session，
  不读取用户 agent.yaml，也不加载用户选择的 knowledge、skills、tools。

resolved:
  可配置 Agent 阶段使用。Swift 侧 `AgentLibrary` 先生成 ResolvedAgentConfig，再传给
  Runtime Host。
```

固定 Pi coding agent 的规则：

- 只用于验证 SwiftUI -> RuntimeBridge -> RuntimeHost -> Pi 主链路。
- 使用 bundled Pi runtime。
- Runtime Host 以 `noTools: "all"` 启动 Pi session，自定义 tools 和 Pi 内建工具都不启用。
- Runtime Host 不加载 Pi extensions、skills、prompt templates、themes 和项目 context files。
- 需要模型凭据时，由 Swift 启动 Runtime Host 时通过安全方式提供；第一版测试可以使用
  mock streaming 替代真实模型调用。

## Commands

### ping

用于验证 Runtime Host 是否可用。

Command：

```json
{"type":"command","id":"cmd_001","name":"ping","payload":{}}
```

Event：

```json
{"type":"event","id":"evt_001","replyTo":"cmd_001","name":"pong","payload":{}}
```

### startSession

启动一个 session。

Command：

```json
{
  "type": "command",
  "id": "cmd_002",
  "name": "startSession",
  "payload": {
    "agent": {
      "id": "ecommerce",
      "mode": "resolved",
      "name": "电商运营助手",
      "model": {
        "provider": "openai",
        "name": "gpt-5-codex"
      },
      "systemPromptPath": "/.../agents/ecommerce/system.md",
      "knowledgePaths": [],
      "skillPaths": [],
      "toolPaths": [],
      "permissions": {
        "bash": "ask",
        "edit": "ask",
        "network": "ask"
      }
    },
    "workspacePath": "/Users/me/Project/demo"
  }
}
```

Events：

```json
{"type":"event","id":"evt_002","replyTo":"cmd_002","sessionId":"ses_001","name":"sessionStarted","payload":{}}
```

失败时返回 `error` event。

基础 chat session 阶段可以使用固定 Pi coding agent：

```json
{
  "type": "command",
  "id": "cmd_002",
  "name": "startSession",
  "payload": {
    "agent": {
      "mode": "fixedCodingAgent"
    },
    "workspacePath": "/Users/me/Project/demo"
  }
}
```

### sendMessage

向 session 发送用户消息。

Command：

```json
{
  "type": "command",
  "id": "cmd_003",
  "name": "sendMessage",
  "payload": {
    "sessionId": "ses_001",
    "message": {
      "role": "user",
      "content": "你好"
    }
  }
}
```

Events：

```json
{"type":"event","id":"evt_003","replyTo":"cmd_003","sessionId":"ses_001","name":"assistantDelta","payload":{"text":"你好"}}
{"type":"event","id":"evt_004","replyTo":"cmd_003","sessionId":"ses_001","name":"assistantDelta","payload":{"text":"，我可以帮你。"}}
{"type":"event","id":"evt_005","replyTo":"cmd_003","sessionId":"ses_001","name":"messageCompleted","payload":{}}
```

### abortSession

中断正在运行的 session。

Command：

```json
{
  "type": "command",
  "id": "cmd_004",
  "name": "abortSession",
  "payload": {
    "sessionId": "ses_001"
  }
}
```

Event：

```json
{"type":"event","id":"evt_006","replyTo":"cmd_004","sessionId":"ses_001","name":"sessionAborted","payload":{}}
```

### approveToolCall

第一阶段不完整实现。保留协议，用于后续 `Approval` 模块。

Command：

```json
{
  "type": "command",
  "id": "cmd_005",
  "name": "approveToolCall",
  "payload": {
    "sessionId": "ses_001",
    "toolCallId": "tool_001",
    "decision": "denied",
    "reason": "Tool approval is not supported yet."
  }
}
```

## Events

### sessionStarted

表示 session 已创建。

Payload：

```json
{}
```

### assistantDelta

表示 assistant 流式输出片段。

Payload：

```json
{"text":"partial text"}
```

### messageCompleted

表示本轮 assistant 输出完成。

Payload：

```json
{}
```

### toolApprovalRequested

表示 runtime 请求工具审批。第一阶段 RuntimeHost 应默认禁用或拒绝需要审批的工具；如果仍
上报该事件，Swift Session 只记录 denied/unsupported 决策，不把结果回传 RuntimeHost。完整
Approval 阶段再补充等待用户审批和决策回传协议。

Payload：

```json
{
  "toolCallId": "tool_001",
  "toolName": "bash",
  "risk": "shell",
  "summary": "Run shell command",
  "details": {
    "command": "ls -la"
  }
}
```

### sessionAborted

表示 session 已中断。

Payload：

```json
{}
```

### error

表示 command 或 runtime 出错。

Payload 使用本文 Error Event 格式。

## 错误码

第一版错误码：

```text
invalid_json
invalid_command
unsupported_command
missing_session
runtime_start_failed
runtime_failed
model_failed
tool_approval_unsupported
internal_error
```

## 第一阶段审批策略

在 `Approval` 完整实现前：

- Runtime Host 当前不等待审批，也不发起真实工具执行。
- 如果 Pi 返回工具调用或工具执行事件，Runtime Host 直接返回 `tool_approval_unsupported` error。
- UI 不应卡死。

## 兼容性规则

- 新增 event 不应破坏旧 Swift 客户端。
- Swift 遇到未知 event 应记录日志并忽略，除非 event 是 `error`。
- Runtime Host 遇到未知 command 应返回 `unsupported_command`。
- 不要把 Pi 内部原始事件直接暴露给 Swift UI。
