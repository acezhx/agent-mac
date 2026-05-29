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
- Runtime Host 启用 Pi 内建 `read`、`bash`、`edit`、`write` 工具。
- Runtime Host 不加载外部 Pi extensions、skills、prompt templates、themes 和项目 context files。
- Pi 内建工具调用通过 Runtime Host 内联 extension 在执行前触发 `toolApprovalRequested`；
  Swift 回传 `approved` 后继续执行，回传 `denied` 后由 Pi 收到被阻断的工具结果。
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

### listModelCatalog

读取 Runtime Host 暴露的 Pi 模型清单，用于 Agent 编辑页按 provider 选择模型。该命令只返回
RuntimeHost/Pi 当前模型注册表中的精简元数据，不读取用户 `agent.yaml`，也不写入任何设置文件。

Command：

```json
{
  "type": "command",
  "id": "cmd_models_001",
  "name": "listModelCatalog",
  "payload": {
    "providerIDs": ["openai", "deepseek"]
  }
}
```

`providerIDs` 为空数组或缺失时表示返回 Runtime Host 可读取到的全部 provider。

Event：

```json
{
  "type": "event",
  "id": "evt_models_001",
  "replyTo": "cmd_models_001",
  "name": "modelCatalogListed",
  "payload": {
    "models": [
      {
        "providerID": "openai",
        "id": "gpt-5-codex",
        "name": "GPT-5 Codex",
        "supportsReasoning": true,
        "supportedThinkingLevels": ["off", "minimal", "low", "medium", "high"]
      }
    ]
  }
}
```

当前 UI 只使用 `providerID`、`id` 和 `name` 选择并持久化 `model.provider` / `model.name`。
`supportsReasoning` 和 `supportedThinkingLevels` 先作为后续智能级别设置的元数据保留，不写入
Agent 配置。

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

### loginOAuthProvider

通过 Pi `AuthStorage.login` 启动 provider OAuth/订阅授权。当前 Settings 页面只会发送
`anthropic` 和 `openai-codex`。

Command：

```json
{
  "type": "command",
  "id": "cmd_oauth_001",
  "name": "loginOAuthProvider",
  "payload": {
    "providerID": "anthropic"
  }
}
```

Events：

```json
{"type":"event","id":"evt_oauth_001","replyTo":"cmd_oauth_001","name":"oauthAuthorizationRequested","payload":{"providerID":"anthropic","url":"https://...","instructions":"Complete login in your browser."}}
{"type":"event","id":"evt_oauth_002","replyTo":"cmd_oauth_001","name":"oauthProgressUpdated","payload":{"providerID":"anthropic","message":"Exchanging authorization code for tokens..."}}
{"type":"event","id":"evt_oauth_003","replyTo":"cmd_oauth_001","name":"oauthLoginCompleted","payload":{"providerID":"anthropic"}}
```

`oauthAuthorizationRequested.payload.url` 必须由 Swift 用系统浏览器打开。Runtime Host 会等待 Pi
OAuth callback server 完成并由 Pi 写入 `auth.json`；失败时返回 `oauth_failed` error event。

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

返回工具审批决策。Runtime Host 收到 `toolApprovalRequested` 后会等待该 command，再继续当前
`sendMessage` 流程。

Command：

```json
{
  "type": "command",
  "id": "cmd_005",
  "name": "approveToolCall",
  "payload": {
    "sessionId": "ses_001",
    "toolCallId": "tool_001",
    "decision": "approved",
    "reason": "Approved by user."
  }
}
```

`decision` 只允许：

- `approved`
- `denied`

Event：

```json
{
  "type": "event",
  "id": "evt_007",
  "replyTo": "cmd_005",
  "sessionId": "ses_001",
  "name": "toolApprovalResolved",
  "payload": {
    "toolCallId": "tool_001",
    "decision": "approved"
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

### runtimeActivity

表示 Runtime Host 在本轮 `sendMessage` 中仍有非文本进度，例如 Pi toolcall 流、工具执行开始、
工具执行更新或工具执行结束。该事件用于让 Swift 侧延长空闲等待，不应创建用户可见消息。

Payload：

```json
{
  "piEventType": "tool_execution_start",
  "toolCallId": "tool_001",
  "toolName": "bash"
}
```

### oauthAuthorizationRequested

表示 Runtime Host 已从 Pi OAuth provider 取得浏览器授权 URL。Swift 应打开 `url`，并继续等待同一个
`replyTo` 的后续 OAuth event。

Payload：

```json
{
  "providerID": "anthropic",
  "url": "https://claude.ai/oauth/authorize?...",
  "instructions": "Complete login in your browser."
}
```

### oauthProgressUpdated

表示 OAuth 登录流程仍在运行。该事件用于 UI 进度和保持 Swift 侧等待，不代表凭据已保存。

Payload：

```json
{
  "providerID": "anthropic",
  "message": "Exchanging authorization code for tokens..."
}
```

### oauthDeviceCodeRequested

表示 OAuth provider 请求设备码授权。当前 `anthropic` 和 `openai-codex` 不使用该路径；Swift 第一版可
忽略或只记录该事件。

Payload：

```json
{
  "providerID": "github-copilot",
  "url": "https://...",
  "userCode": "ABCD-EFGH"
}
```

### oauthLoginCompleted

表示 Pi `AuthStorage.login` 已完成并写入 provider OAuth 凭据。Swift 收到后应重新读取
`Pi/auth.json` 的 provider 状态。

Payload：

```json
{
  "providerID": "anthropic"
}
```

### modelCatalogListed

表示 Runtime Host 已返回模型清单。Swift 可用 `providerID` 过滤当前 Settings 白名单内的模型。

Payload：

```json
{
  "models": [
    {
      "providerID": "deepseek",
      "id": "deepseek-v4-flash",
      "name": "DeepSeek V4 Flash",
      "supportsReasoning": true,
      "supportedThinkingLevels": ["off", "high", "xhigh"]
    }
  ]
}
```

### toolApprovalRequested

表示 runtime 请求工具审批。Swift Session 应根据 Agent 权限策略自动 allow/deny，或通过
AppShell 展示 UI 等待用户选择，然后用 `approveToolCall` 将 `approved` 或 `denied` 回传
Runtime Host。

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

### toolApprovalResolved

表示 Runtime Host 已收到工具审批决策。

Payload：

```json
{
  "toolCallId": "tool_001",
  "decision": "approved"
}
```

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
missing_tool_approval
oauth_failed
internal_error
```

## 第一版审批策略

- Runtime Host 发出 `toolApprovalRequested` 后等待 Swift 回传 `approveToolCall`。
- Runtime Host 在 toolcall 流和工具执行阶段发出 `runtimeActivity` 心跳，避免没有 assistant 文本时
  被 Swift 侧误判为空闲超时。
- Agent 权限为 `allow` 时，Swift Session 自动回传 `approved`。
- Agent 权限为 `deny` 时，Swift Session 自动回传 `denied`。
- Agent 权限为 `ask` 时，AppShell 展示确认 UI；用户关闭审批 UI 按 `denied` 处理。
- Runtime Host 只接收审批结果；工具执行仍留在 runtime 内部，不下沉到 Swift。
- 当前权限模型没有独立 read 项；Pi `read` 工具按文件类风险进入现有 edit 权限策略。

## 兼容性规则

- 新增 event 不应破坏旧 Swift 客户端。
- Swift 遇到未知 event 应记录日志并忽略，除非 event 是 `error`。
- Runtime Host 遇到未知 command 应返回 `unsupported_command`。
- 不要把 Pi 内部原始事件直接暴露给 Swift UI。
