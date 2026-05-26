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

第一阶段 `Approval` 未实现时，`ask` 按 `deny/unsupported` 处理。

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
- `references/` 可选。
- `scripts/`、`assets/` 可后续增加。
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
