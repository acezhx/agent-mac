# AppShell 模块开发计划

## 模块目标

`AppShell` 负责 macOS 应用的可见界面和导航。它把 Agent 使用工作台、Agent 管理、资源管理串起来，
但不直接处理底层文件读写和 Runtime Host 细节。

`AppShell` 是第一版 TCA 架构的主要落地点。它负责组织根 Feature，并把 Agent 管理、资源管理、
会话和后续审批页面拆成可组合的子 Feature。

## 依赖关系

```text
AppShell
  -> AgentLibrary
  -> ResourceLibrary
  -> Session
```

实现完整审批后再增加：

```text
AppShell
  -> Approval
```

## 需要开发的功能

### 第一阶段最小竖切

当前阶段先不实现完整 Agent/Resource/Approval UI，只跑通固定 Pi coding agent 的 chat session：

- 根 `AppFeature` / `AppView` 承载单一会话页面。
- `SessionFeature` 管理 workspace 输入、session snapshot、消息输入、运行中标记和错误展示。
- `AppSessionClient` 作为 TCA dependency 边界，内部组合既有 `ChatSessionManager`、`ChatSession`
  和 `RuntimeBridge` 服务；底层模块不依赖 TCA。
- UI 可创建固定 coding agent session、启动 Runtime Host session、发送消息、展示 snapshot 中的
  用户/assistant/diagnostic 消息变化。
- UI 展示 idle/running/failed/aborted 以及 create/start/send/abort/reset 的进行中状态。
- 第一阶段会话页只维护一个当前固定 session；创建后 `New Session` 和 workspace 输入禁用，
  `Reset` 只重置当前 session 以便继续复用。
- 第一阶段不做 Agent 选择、资源选择、复杂权限 UI 或完整审批流程。

### TCA Feature 架构

- 创建根 `AppFeature`，管理应用级会话工作台状态；Agent 和 Resource 管理由独立窗口承载。
- 为 Agent 管理、资源管理、会话页面创建子 Feature。
- 通过 TCA dependency 调用 `AgentLibrary`、`ResourceLibrary` 和 `Session` 服务。
- SwiftUI View 只渲染 Store 状态并发送 action。
- 异步加载、保存、启动会话和处理错误放在 reducer effect 中。

### 应用外壳

- 根视图。
- 面向 Agent 使用场景的会话工作台。
- Agent Library 窗口入口。
- Resource Library 窗口入口。
- 基础错误展示。

### Agent 管理 UI

- Agent 列表。
- 创建 Agent。
- 选择 Agent。
- 编辑 Agent 名称。
- 编辑模型配置。
- 编辑 system prompt。
- 保存 Agent。

当前最小链路先支持 Agent 列表、创建表单、选择 Agent、编辑名称、编辑模型 provider/name、
编辑私有 system prompt 和保存。资源选择控件后续接 `ResourceLibrary` 后再补；在此之前保存
Agent 时必须保留已有 knowledge、skills、tools 和权限配置。

### 资源选择 UI

- 展示可选 knowledge。
- 展示可选 skills。
- 展示可选 tools。
- 在 Agent 编辑页选择资源。
- 保存资源选择。

### 资源管理 UI

- knowledge 列表。
- knowledge 编辑器。
- skills 列表。
- `SKILL.md` 编辑器。
- tools 列表。
- `tool.yaml` 和入口文件编辑入口。

### 会话 UI

- 选择 Agent。
- 选择 workspace。
- 消息列表。
- 消息输入框。
- 发送按钮。
- 流式 assistant 输出。
- 运行状态展示。
- 失败状态展示。

### 审批 UI

- 通过 Session snapshot 中的 pending 工具审批请求展示确认面板。
- 支持 Allow 和 Deny。
- 用户关闭确认面板时按 Deny 处理。
- 通过 `AppSessionClient` 提交决策，不让 SwiftUI View 直接调用 Session 或 RuntimeBridge。

## Checklist

- [x] 创建 `AgentMac/AppShell/` 目录。
- [x] 创建根 `AppFeature`。
- [x] 配置 TCA dependencies。
- [x] 实现根视图。
- [x] 实现会话工作台和管理窗口入口。
- [x] 创建 Agent 管理 Feature。
- [x] 实现 Agent 列表。
- [x] 实现 Agent 创建表单。
- [x] 实现 Agent 编辑页。
- [x] 实现 system prompt 编辑器。
- [ ] 实现资源选择控件。
- [x] 创建资源管理 Feature。
- [x] 实现 knowledge 列表和编辑入口。
- [x] 实现 skill 列表和编辑入口。
- [x] 实现 tool 列表和编辑入口。
- [x] 创建会话 Feature。
- [x] 实现会话页面。
- [x] 实现消息输入。
- [x] 实现流式输出展示。
- [x] 实现基础错误提示。
- [x] 添加 AppShell reducer/state 测试。
- [x] 手工验证固定 Pi coding agent chat session。

## Agent 管理进展

2026-05-27 已接入 Agent 管理最小链路：

- 当前主窗口通过 toolbar 打开独立的 Agent Library 窗口，主窗口自身保持为会话工作台。
- `AgentFeature` 负责 Agent 列表、创建表单、选中加载、编辑和保存状态。
- `AppAgentClient` 作为 TCA dependency 边界，内部调用现有 `AgentLibrary`；SwiftUI View 不直接
  持有 `AgentLibrary` 或 `FileStore`。
- Agent 编辑页当前支持名称、模型 provider/name 和 system prompt。
- 资源选择 UI 尚未实现；保存当前 Agent 时保留已有 knowledge、skills、tools 和权限配置。

## 资源管理进展

2026-05-27 已接入 Resource 管理最小链路：

- 当前主窗口通过 toolbar 打开独立的 Resource Library 窗口，主窗口自身保持为会话工作台。
- `ResourceFeature` 负责 Resource 类型切换、列表加载、创建表单、选中加载、编辑和保存状态。
- `AppResourceClient` 作为 TCA dependency 边界，内部调用现有 `ResourceLibrary`；SwiftUI View
  不直接持有 `ResourceLibrary` 或 `FileStore`。
- Resources 页面当前支持 knowledge 文件、skill `SKILL.md`、tool `tool.yaml` 和入口文件的
  列表、创建、选择、纯文本编辑和保存；Knowledge 编辑区支持改名、保存成功提示和删除当前选中
  knowledge，Skills 和 Tools 编辑区支持删除当前选中的资源。
- 创建 knowledge、skill 和 tool 时由 `AppResourceClient` 自动生成未占用 ID，创建表单不暴露 ID
  输入；knowledge 使用 `knowledge.md`、`knowledge-2.md`、`knowledge-3.md`，skill 使用 `skill`、
  `skill-2`、`skill-3`，tool 使用 `tool`、`tool-2`、`tool-3`。tool 的展示名称和其他配置一起在
  `tool.yaml` 中编辑。
- Skills 页面支持导入已有 skill 目录。导入时通过系统目录选择面板选择包含 `SKILL.md` 的目录，
  `AppResourceClient` 根据源目录名生成未占用 skill ID，并把整个目录复制到共享 skills 库。
- skill 列表和编辑标题优先显示 `SKILL.md` 顶部 YAML frontmatter 的 `name` 字段；用户编辑并保存
  `name` 后，展示名会跟随保存结果更新，目录 ID 不变。
- 当前不做资源版本管理、语法高亮和 Agent 编辑页内的资源选择控件；
  Agent 资源选择仍是下一步。

## 手工验证记录

2026-05-27 已从 macOS UI 跑通固定 Pi coding agent chat session：创建 session、启动 Runtime
Host、发送消息并收到 assistant 回复。当前验证使用 Pi 的本地配置目录：

```text
~/Library/Application Support/AgentMac/Pi/settings.json
~/Library/Application Support/AgentMac/Pi/auth.json
```

该目录由 Runtime Host 通过 `AGENTMAC_PI_AGENT_DIR` 传给 Pi。第一阶段允许本地调试时临时在
`auth.json` 中写入模型 key；这是为了跑通真实 Pi 主链路，后续应改为 Keychain 或正式设置 UI，
不要把 key 提交到仓库。

## 验收标准

### 第一阶段最小竖切验收

- UI 状态、用户操作和异步 effect 由 TCA Feature 管理。
- SwiftUI View 不直接调用 `FileStore`、`ResourceLibrary`、`AgentLibrary` 或 `RuntimeBridge`。
- Feature 通过 `AppSessionClient` 这个 TCA dependency 调用固定 session 能力。
- 用户可以创建固定 coding agent session。
- 用户可以启动 Runtime Host session。
- 用户可以发送一条消息。
- assistant 回复可以通过 `ChatSessionSnapshot` 的消息变化显示。
- running、failed、aborted 和基础操作进行中状态在 UI 中可见。
- abort/reset 有最小可用路径。
- 工具审批请求能展示确认 UI，用户 allow/deny 后通过 AppSessionClient 回传。

### 后续完整 AppShell 验收

- UI 状态、用户操作和异步 effect 由 TCA Feature 管理。
- SwiftUI View 不直接调用 `FileStore`、`ResourceLibrary`、`AgentLibrary` 或 `RuntimeBridge`。
- 主窗口默认面向 Agent 使用场景展示会话工作台，Agent 和 Resource 管理通过独立管理窗口打开。
- 管理入口可以打开 Agent Library 和 Resource Library 窗口，窗口关闭后不影响当前会话状态。
- 用户可以从 UI 创建 Agent。
- 用户可以编辑 Agent 的 system prompt。
- 用户可以选择 knowledge、skills、tools。
- 用户可以直接创建 tool，Tool ID 由 AppShell 自动生成且不在创建表单暴露。
- 用户可以在 `tool.yaml` 中修改 tool 的 `name` 和其他配置。
- 用户可以从已有目录导入 skill，导入后列表出现该 skill，并选中进入 `SKILL.md` 编辑状态。
- 用户可以修改 knowledge 名称，保存后列表和编辑区同步到新名称，并显示保存成功提示。
- 用户可以删除当前选中的 knowledge，删除后列表和编辑区同步清理。
- 用户可以删除当前选中的 skill，删除后列表和编辑区同步清理。
- 用户可以删除当前选中的 tool，删除后列表和编辑区同步清理。
- 用户可以保存 Agent，并重新打开看到相同配置。
- 用户可以选择 Agent 启动会话。
- 用户可以发送一条消息。
- assistant 回复可以流式显示。
- runtime 失败时 UI 有明确错误提示。
- 工具审批请求在第一阶段不会让 UI 卡死。

## 第一版不做

- 不做复杂视觉设计。
- 不做复杂多窗口高级管理；第一版只提供固定的 Agent Library 和 Resource Library 管理窗口。
- 不做结构化 YAML 表单或高级语法高亮；tool `tool.yaml` 第一版采用纯文本编辑。
- 不做 Agent 导入导出。
- 不做完整审批 UI，等 `Approval` 阶段实现。
