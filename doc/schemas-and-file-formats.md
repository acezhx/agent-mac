# 文件格式与 Schema

## 目标

本文定义 AgentMac 第一版使用的文件格式和路径规则。实现 `FileStore`、`ResourceLibrary`、
`AgentLibrary`、`RuntimeHost` 前应先遵守这些约定。

第一版采用文件优先设计，不使用数据库管理 Agent 或资源定义。

## 通用规则

### 编码

- 所有文本配置文件使用 UTF-8。
- YAML 文件使用 `.yaml` 后缀。
- Markdown 文件使用 `.md` 后缀。
- 第一版不支持二进制 knowledge 解析，PDF、Word 等格式后置。

### ID 规则

Agent、tool、skill 等目录型资源 ID 应满足：

```text
^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$
```

规则：

- 只使用小写字母、数字和连字符。
- 长度 2 到 64。
- 不能以连字符开头或结尾。
- 不能包含路径分隔符。
- 不能使用 `.`、`..`、空字符串。

### 路径规则

- `agent.yaml` 中的资源路径相对于该 `agent.yaml` 所在目录解析。
- 路径可以引用 Agent 目录内文件，也可以引用 `../../library/...` 下的共享资源。
- 路径解析后必须落在 AgentMac 的 Application Support 根目录内。
- 禁止解析到 Application Support 之外。
- 禁止使用绝对路径作为持久化配置值。
- Runtime 使用前可以生成包含绝对路径的 `ResolvedAgentConfig`，但不要把绝对路径写回
  `agent.yaml`。

示例：

```yaml
knowledge:
  - ../../library/knowledge/refund-policy.md
skills:
  - ../../library/skills/report-writing
tools:
  - ../../library/tools/ticket-search
```

## 用户数据目录

第一版用户数据布局：

```text
~/Library/Application Support/AgentMac/
├─ agents/
│  └─ <agent-id>/
│     ├─ agent.yaml
│     └─ system.md
├─ library/
│  ├─ knowledge/
│  ├─ skills/
│  └─ tools/
├─ sessions/
└─ settings.yaml
```

## agent.yaml

`agent.yaml` 是 Agent 的主配置文件。它位于：

```text
agents/<agent-id>/agent.yaml
```

### 示例

```yaml
id: ecommerce
name: 电商运营助手

model:
  provider: openai
  name: gpt-5-codex

systemPrompt: system.md

knowledge:
  - ../../library/knowledge/refund-policy.md
  - ../../library/knowledge/order-rules.md

skills:
  - ../../library/skills/report-writing

tools:
  - ../../library/tools/ticket-search

permissions:
  bash: ask
  edit: ask
  network: ask
```

### 字段

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---:|---|---|
| `id` | string | 是 | 无 | Agent ID，必须与目录名一致。 |
| `name` | string | 是 | 无 | UI 展示名称。 |
| `model.provider` | string | 是 | `openai` | 模型提供方。 |
| `model.name` | string | 是 | 无 | 模型名称。 |
| `systemPrompt` | string | 是 | `system.md` | Agent 私有 system prompt 文件。 |
| `knowledge` | string[] | 否 | `[]` | knowledge 文件路径列表。 |
| `skills` | string[] | 否 | `[]` | skill 目录路径列表。 |
| `tools` | string[] | 否 | `[]` | tool 目录路径列表。 |
| `permissions.bash` | enum | 否 | `ask` | shell 命令策略。 |
| `permissions.edit` | enum | 否 | `ask` | 文件编辑策略。 |
| `permissions.network` | enum | 否 | `ask` | 网络访问策略。 |

权限枚举：

```text
allow
ask
deny
```

第一版 `Approval` 接入后，`allow` 自动批准、`deny` 自动拒绝；`ask` 默认允许 Pi 内建
`read`、`edit`、`write` 文件类请求和不匹配常见文件删除语义的 `bash` shell 请求，其余请求通过 AppShell UI 等待用户确认。

### 校验规则

- `id` 必须合法，并与所在目录名一致。
- `name` 不能为空。
- `systemPrompt` 必须存在。
- `knowledge` 中每个路径必须存在且是文件。
- `skills` 中每个路径必须存在且是目录，并包含 `SKILL.md`。
- `tools` 中每个路径必须存在且是目录，并包含 `tool.yaml`。
- 权限值必须是 `allow`、`ask`、`deny` 之一。

## system.md

`system.md` 是 Agent 私有 system prompt。

位置：

```text
agents/<agent-id>/system.md
```

规则：

- 随 Agent 创建。
- 由 Agent 编辑页维护。
- 不放入共享资源库。
- 第一版允许为空，但 UI 应提示用户补充。

## Session Record

Session 记录保存为 JSON 文件，位于：

```text
sessions/<session-id>.json
```

第一版保存本地恢复需要的 session 元数据、完整消息历史、结构化错误和临时工具审批决策。
`runtimeSessionID` 只用于诊断；应用冷启动恢复时不会重新附着旧 Runtime Host session。
如果磁盘状态仍是 `running`，恢复时应降级为 `failed` 并关闭 streaming 消息。

### 示例

```json
{
  "agentID": "support-agent",
  "agentName": "Support Agent",
  "createdAt": "2026-05-27T03:00:00Z",
  "error": null,
  "errorMessage": null,
  "id": "00000000-0000-0000-0000-000000000001",
  "messageCount": 2,
  "messages": [
    {
      "content": "你好",
      "createdAt": "2026-05-27T03:00:01Z",
      "id": "00000000-0000-0000-0000-000000000002",
      "isStreaming": false,
      "role": "user"
    },
    {
      "content": "你好，有什么可以帮你？",
      "createdAt": "2026-05-27T03:00:02Z",
      "id": "00000000-0000-0000-0000-000000000003",
      "isStreaming": false,
      "role": "assistant"
    }
  ],
  "runtimeSessionID": "ses_001",
  "schemaVersion": 1,
  "state": "idle",
  "toolApprovals": [],
  "updatedAt": "2026-05-27T03:00:05Z",
  "workspacePath": "/Users/me/Project/demo"
}
```

### 字段

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `schemaVersion` | integer | 是 | Session record schema 版本，当前为 `1`；旧 record 缺失时按 `0` 读取。 |
| `id` | string | 是 | Swift 侧生成的本地 session id。 |
| `runtimeSessionID` | string/null | 否 | Runtime Host session id；已中断或重置后可为空。 |
| `agentID` | string | 是 | 传入 Session 的 `ResolvedAgentConfig.id`。 |
| `agentName` | string | 是 | 传入 Session 的 `ResolvedAgentConfig.name`。 |
| `workspacePath` | string | 是 | 会话工作区绝对路径。 |
| `state` | enum | 是 | `idle`、`running`、`failed` 或 `aborted`。 |
| `error` | object/null | 否 | failed 状态下的结构化错误。 |
| `errorMessage` | string/null | 否 | failed 状态下的诊断信息。 |
| `createdAt` | ISO-8601 string | 是 | 本地 session 创建时间。 |
| `updatedAt` | ISO-8601 string | 是 | 最近一次状态、消息或诊断更新时间。 |
| `messageCount` | integer | 是 | `messages` 数量摘要；旧 record 没有 `messages` 时保留旧值。 |
| `messages` | object[] | 否 | 完整消息历史；旧 record 缺失时按空数组读取。 |
| `toolApprovals` | object[] | 否 | 工具审批决策记录；当前支持 allowed、denied，并兼容旧的 unsupported。 |

`messages` 字段：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `id` | string | 是 | Swift 侧生成的本地 message id。 |
| `role` | enum | 是 | `user`、`assistant` 或 `diagnostic`。 |
| `content` | string | 是 | 消息文本内容。 |
| `createdAt` | ISO-8601 string | 是 | 消息创建时间。 |
| `isStreaming` | boolean | 是 | assistant 消息是否仍在接收流式 delta；冷恢复时会归一化为 false。 |

`error` 字段：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `type` | string | 是 | `runtimeSessionMissing`、`runtimeSessionDetached`、`runtimeSessionAlreadyStarted`、`messageAlreadyInFlight`、`sessionRequiresReset`、`runtimeFailed`、`bridgeFailed`、`unexpectedRuntimeEvent` 或 `persistenceFailed`。 |
| `message` | string | 是 | 诊断文本。 |
| `code` | string/null | 否 | Runtime 错误码。 |
| `recoverable` | boolean/null | 否 | Runtime 错误是否可恢复。 |
| `path` | string/null | 否 | 持久化错误涉及的 app data 相对路径。 |
| `reason` | string/null | 否 | 持久化错误底层原因。 |
| `eventName` | string/null | 否 | 未识别 Runtime event 的名称。 |

## Knowledge 文件

第一版 knowledge 是共享 Markdown 或纯文本文件。

位置：

```text
library/knowledge/<name>.md
library/knowledge/<name>.txt
```

规则：

- 文件名应稳定、可读。
- 隐藏文件和 `.DS_Store` 不作为 knowledge。
- 第一版不定义额外 manifest。
- 第一版不支持 PDF、Word、网页抓取和向量索引。

## Skill 目录

第一版 skill 使用 Agent Skills 目录约定。

位置：

```text
library/skills/<skill-id>/
├─ SKILL.md
└─ references/
```

最小规则：

- 目录名必须符合 ID 规则。
- 必须包含 `SKILL.md`。
- UI 展示名优先使用 `SKILL.md` 顶部 YAML frontmatter 的 `name` 字段；缺失或为空时回退到目录 ID。
- 修改 `SKILL.md` 中的 `name` 只改变展示名，不重命名目录 ID。
- UI 导入已有 skill 目录时，源目录顶层必须包含 `SKILL.md`。导入后目录会被复制到
  `library/skills/<skill-id>/`，`<skill-id>` 由 UI 根据源目录名生成并保证不与现有 skill 冲突。
- `references/` 可选。
- `references/`、`scripts/`、`assets/` 等子目录在导入时会原样保留。
- 第一版只做最小结构校验，不做完整 frontmatter 规范校验。

## tool.yaml

tool 是共享工具目录。第一版只做配置和文件维护，不默认执行高风险工具。

位置：

```text
library/tools/<tool-id>/
├─ tool.yaml
└─ index.js
```

### 示例

```yaml
id: ticket-search
name: 工单搜索
runtime: node
entry: index.js

permissions:
  network: ask
  secrets:
    - JIRA_API_TOKEN
```

### 字段

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---:|---|---|
| `id` | string | 是 | 无 | Tool ID，必须与目录名一致。 |
| `name` | string | 是 | 无 | UI 展示名称。 |
| `runtime` | string | 是 | `node` | 第一版只支持 `node`。 |
| `entry` | string | 是 | `index.js` | tool 入口文件。 |
| `permissions.network` | enum | 否 | `ask` | 网络权限。 |
| `permissions.secrets` | string[] | 否 | `[]` | 需要的密钥名称。 |

### ResourceLibrary 最小校验

`ResourceLibrary` 阶段只维护共享 tool 文件，不执行 tool，也不做完整 schema 深度校验。
它负责的最小结构校验为：

- 目录名必须符合 ID 规则。
- tool 目录必须包含 `tool.yaml`。
- `tool.yaml` 必须包含顶层 `entry` 字段。
- `entry` 必须是位于当前 tool 目录内的相对路径。
- `entry` 指向的入口文件必须存在且是文件。

### 后续消费校验

Agent 或 Runtime 消费 tool 配置前还应校验：

- `id` 必须合法，并与所在目录名一致。
- `name` 不能为空。
- `runtime` 第一版必须是 `node`。
- `permissions.network` 必须是 `allow`、`ask`、`deny` 之一。
- 第一版不验证 tool 运行结果。

## settings.yaml

`settings.yaml` 保存 app 级设置，不保存 Agent 定义。

位置：

```text
~/Library/Application Support/AgentMac/settings.yaml
```

### 示例

```yaml
appDataVersion: 1
lastWorkspace: null
runtime:
  useBundledRuntime: true
```

### 字段

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---:|---|---|
| `appDataVersion` | integer | 是 | `1` | 用户数据布局版本。 |
| `lastWorkspace` | string/null | 否 | `null` | 上次选择的 workspace。 |
| `runtime.useBundledRuntime` | bool | 否 | `true` | 是否使用 app 内置 runtime。 |

运行时模式可以被 Xcode scheme 或进程环境变量覆盖。优先级见
`doc/runtime-packaging.md`，不要把开发机专用路径写入 `settings.yaml`。

## ResolvedAgentConfig

`ResolvedAgentConfig` 是运行时临时结构，不写入磁盘配置。

它应包含：

- Agent ID。
- Agent 名称。
- model 配置。
- system prompt 绝对路径。
- knowledge 绝对路径列表。
- skills 绝对路径列表。
- tools 绝对路径列表。
- permissions 配置。
- workspace 绝对路径。

它由 `AgentLibrary` 生成，传给 `Session` 和 `RuntimeBridge` 使用。
