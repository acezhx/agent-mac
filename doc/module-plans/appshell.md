# AppShell 模块开发计划

## 模块目标

`AppShell` 负责 macOS 应用的可见界面和导航。它把 Agent 使用工作台、Agent 管理、资源管理串起来，
但不直接处理底层文件读写和 Runtime Host 细节。

`AppShell` 是第一版 TCA 架构的主要落地点。它负责组织根 Feature，并把 Agent 管理、资源管理、
会话、设置和审批页面拆成可组合的子 Feature。

## 依赖关系

```text
AppShell
  -> AgentLibrary
  -> ResourceLibrary
  -> AppSettings
  -> Session
AppShell
  -> Approval
```

## 需要开发的功能

### 第一阶段最小竖切

初始竖切先不实现完整 Agent/Resource/Approval UI，只跑通固定 Pi coding agent 的 chat session：

- 根 `AppFeature` / `AppView` 承载单一会话页面。
- `SessionFeature` 管理 workspace 输入、session snapshot、消息输入、运行中标记和错误展示。
- `AppSessionClient` 作为 TCA dependency 边界，内部组合既有 `ChatSessionManager`、`ChatSession`
  和 `RuntimeBridge` 服务；底层模块不依赖 TCA。
- UI 可创建固定 coding agent session、启动 Runtime Host session、发送消息、展示 snapshot 中的
  用户/assistant/diagnostic 消息变化。
- UI 展示 idle/running/failed/aborted 以及 create/start/send/abort/reset 的进行中状态。
- 第一阶段会话页只维护一个当前固定 session；创建后 `New Session` 和 workspace 输入禁用，
  `Reset` 只重置当前 session 以便继续复用。
- 初始竖切不做 Agent 选择、资源选择、复杂权限 UI 或完整审批流程；当前已补上 Agent/Resource
  管理、Agent 编辑页资源选择和工具审批 UI，仍未接入可配置 Agent session。

### TCA Feature 架构

- 创建根 `AppFeature`，管理应用级会话工作台状态；Agent 和 Resource 管理由独立窗口承载。
- 为 Agent 管理、资源管理、Settings、会话页面创建子 Feature。
- 通过 TCA dependency 调用 `AgentLibrary`、`ResourceLibrary`、`AppSettings` 和 `Session` 服务。
- SwiftUI View 只渲染 Store 状态并发送 action。
- 异步加载、保存、启动会话和处理错误放在 reducer effect 中。

### SwiftUI Perception 使用规范

AppShell 使用 TCA store 驱动 SwiftUI 页面。凡是 SwiftUI View 读取 `StoreOf<...>` 中的
perceptible state，都必须让读取发生在 `WithPerceptionTracking` 覆盖范围内。这里的“读取”包括
直接属性、绑定派生属性以及会继续访问 state 的计算属性，例如 `hasOperationInFlight`、
`canSave...`、`canCreate...` 这类组合状态。否则切换 Agent、刷新资源或打开 Settings 时会出现
`Perceptible state ... was accessed from a view but is not being tracked` 运行时告警。

具体规范：

- 每个持有 `@Perception.Bindable var store: StoreOf<...>` 的 SwiftUI View，`body` 必须以
  `WithPerceptionTracking { ... }` 包住实际内容。
- 从 `body` 拆出去的计算型子视图如果读取 store state，也必须在子视图入口再次使用
  `WithPerceptionTracking`，不要只依赖父级 `body` 的包裹。
- `ForEach`、`List` 行内容、`GeometryReader`、`ScrollViewReader`、`sheet`、`popover`、
  `confirmationDialog`、`alert`、`toolbar`、`overlay`、`background` 等带 ViewBuilder 的闭包里，
  只要读取 store state 或调用会读取 state 的计算属性，都必须在该闭包内部再包一层
  `WithPerceptionTracking`。
- 列表行、表格行和可复用子组件优先接收普通值，例如 `isOperationInFlight: Bool`、
  `isSelected: Bool`、`status: ...`。在已追踪的父视图里读取 store state，再把值传下去；
  不要让纯展示行直接持有 store。
- 如果闭包只需要发送 action，不需要读取 state，可以直接捕获 store 并调用 `store.send(...)`；
  一旦同一个闭包还读取 state，就按上一条规则处理。
- 由 perceptible state 派生的 SwiftUI binding 必须使用 `@Perception.Bindable` 和
  `$store.field.sending(\.action)`。如果 sheet 或弹窗需要持有展示状态，优先使用本地 `@State`
  镜像展示项，再在 sheet 内容中单独 `WithPerceptionTracking`。
- `Picker` 的 `selection` 必须始终能在内容里找到对应 `.tag(...)`。当当前值为空、被 Settings
  白名单移除或模型清单暂未加载时，要显式提供占位或 unavailable 选项，不能让 selection 指向没有
  tag 的值。对于切换 Agent、刷新列表或加载清单期间会被 reducer 临时清空为 `""` 的 selection，
  空占位 tag 应作为稳定选项保留，而不是只在当前值已经为空时才临时加入。
- 新增或改动 AppShell SwiftUI 页面时，验证范围至少包含相关 Feature 测试和一次
  `xcodebuild test -scheme AgentMac -destination 'platform=macOS'`；如果改动是纯文档，可以只做
  文档一致性检查。

### 应用外壳

- 根视图。
- 面向 Agent 使用场景的会话工作台。
- Agent Library 窗口入口。
- Resource Library 窗口入口。
- Settings 窗口入口。
- 基础错误展示。

### Agent 管理 UI

- Agent 列表。
- 创建 Agent。
- 选择 Agent。
- 编辑 Agent 名称。
- 编辑模型配置。
- 编辑自定义 Agent 的 system prompt。
- 保存 Agent。

当前最小链路支持 Agent 列表、创建表单、选择 Agent、编辑名称、按 Settings 白名单选择模型 provider、
按 RuntimeHost/Pi 模型清单选择模型 name、编辑自定义 Agent 的私有 system prompt、选择
knowledge/skills/tools 和保存。Agent 编辑页通过 `AppResourceClient` 加载共享资源列表，保存时把
选择结果写入 Agent manifest，并继续保留权限配置。默认 `coding-agent` 表示内置 Pi coding agent，
只允许编辑模型配置。

### Settings UI

- 展示支持的模型 provider。
- 以单列表展示 provider，并按 provider 能力提供 API Key 或 OAuth/订阅连接入口。
- 通过 API Key 表单连接 provider。
- 通过浏览器 OAuth 连接 `anthropic` 和 `openai-codex` 订阅授权。
- 断开已连接 provider。
- 保存 API Key 到 Pi `auth.json`，并同步 app 级 `settings.yaml` 白名单。

当前 Settings 页面通过 `AppSettingsClient` 加载和保存 `settings.yaml`，通过
`AppProviderAuthClient` 读写 Pi `auth.json` 的 API Key 凭据，并通过 RuntimeHost/Pi `AuthStorage`
执行 `anthropic` 和 `openai-codex` OAuth 登录；Agent 编辑页通过 `AppSettingsClient` 加载 provider
白名单，并通过 `AppModelCatalogClient` 从 RuntimeHost/Pi 读取模型清单，只允许选择白名单 provider
下的模型。RuntimeHost 已返回模型的 supported thinking levels，但当前 UI 暂不持久化智能级别设置。

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
- [x] 实现资源选择控件。
- [x] 创建资源管理 Feature。
- [x] 实现 knowledge 列表和编辑入口。
- [x] 实现 skill 列表和编辑入口。
- [x] 实现 tool 列表和编辑入口。
- [x] 创建会话 Feature。
- [x] 实现会话页面。
- [x] 实现消息输入。
- [x] 实现流式输出展示。
- [x] 实现基础错误提示。
- [x] 启动时初始化 Application Support 数据目录。
- [x] 增加常见 Runtime 启动错误提示。
- [x] 添加 AppShell reducer/state 测试。
- [x] 手工验证固定 Pi coding agent chat session。

## Agent 管理进展

2026-05-27 已接入 Agent 管理最小链路；2026-05-29 已补上 Agent 编辑页资源选择：

- 当前主窗口通过 toolbar 打开独立的 Agent Library、Resource Library 和 Settings 窗口，主窗口自身保持为会话工作台。
- `AgentFeature` 负责 Agent 列表、创建表单、选中加载、编辑和保存状态。
- `AppAgentClient` 作为 TCA dependency 边界，内部调用现有 `AgentLibrary`；SwiftUI View 不直接
  持有 `AgentLibrary` 或 `FileStore`。
- Agent 编辑页当前支持名称、Settings 白名单内的模型 provider、RuntimeHost/Pi 模型清单中的模型
  name、system prompt 和 knowledge/skills/tools 选择；默认 `coding-agent` 只展示模型 provider/name。
- 资源选择通过 `AppResourceClient` 加载 ResourceLibrary 中已有的 knowledge、skills、tools；勾选后
  保存为相对 `agent.yaml` 的 `../../library/...` 引用，保存当前 Agent 时继续保留权限配置。
- Settings 页面以单列表展示内置 Pi provider；当前实现 API Key 连接、`anthropic` 和
  `openai-codex` OAuth 登录和断开，并通过 `AppProviderAuthClient` 写入 Pi `auth.json`，同时用
  `AppSettingsClient` 同步 Agent 可使用的模型 provider 白名单。

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
- 当前不做资源版本管理、语法高亮和可配置 Agent session 启动；Agent 编辑页资源选择已接入。

## 手工验证记录

2026-05-27 已从 macOS UI 跑通固定 Pi coding agent chat session：创建 session、启动 Runtime
Host、发送消息并收到 assistant 回复。当前验证使用 Pi 的本地配置目录：

```text
~/Library/Application Support/AgentMac/Pi/settings.json
~/Library/Application Support/AgentMac/Pi/auth.json
```

该目录由 Runtime Host 通过 `AGENTMAC_PI_AGENT_DIR` 传给 Pi。Settings 页面当前可以写入 API Key
凭据，并可通过浏览器 OAuth 连接 `anthropic` 和 `openai-codex` 订阅授权；OAuth token 由 Pi
`AuthStorage` 写入并由 Pi 运行时刷新。`auth.json` 不要提交到仓库，后续可迁移到 Keychain 或更完整的
凭据管理。

2026-05-28 阶段 9 集成打磨已让根 `AppFeature.task` 在主窗口启动时通过 `AppStartupClient`
初始化 `FileStore`，创建 Application Support 下的基础目录和 `settings.yaml`。2026-05-29 启动
初始化已补上缺失时创建默认 `coding-agent`，用于表示当前内置 Pi coding agent，并且不会覆盖用户
已有的同 ID Agent。默认 `coding-agent` 的编辑页只展示模型配置；名称、system prompt、资源和权限
按 Pi coding agent 当前运行模式处理，不作为可编辑字段暴露。当前 Runtime Host 固定 Pi session
启用 Pi 内建 `read`、`bash`、`edit`、`write` 工具，并通过现有审批流控制执行；同时关闭外部 Pi
资源加载，因此默认 `coding-agent` 不读取 AgentLibrary 中的资源。启动初始化失败时，
主窗口顶部展示可复制的错误提示；Runtime 缺少 Node、Runtime Host、Pi runtime、进程退出、响应
超时以及常见 Pi 模型/认证问题会通过 `AppSessionClientError` 映射成带修复方向的提示。

## 验收标准

### 第一阶段最小竖切验收

- UI 状态、用户操作和异步 effect 由 TCA Feature 管理。
- SwiftUI View 不直接调用 `FileStore`、`ResourceLibrary`、`AgentLibrary`、`AppSettings` 或 `RuntimeBridge`。
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
- SwiftUI View 不直接调用 `FileStore`、`ResourceLibrary`、`AgentLibrary`、`AppSettings` 或 `RuntimeBridge`。
- 主窗口默认面向 Agent 使用场景展示会话工作台，Agent、Resource 和 Settings 管理通过独立管理窗口打开。
- 管理入口可以打开 Agent Library、Resource Library 和 Settings 窗口，窗口关闭后不影响当前会话状态。
- 用户可以从 UI 创建 Agent。
- 用户可以编辑自定义 Agent 的 system prompt。
- 用户可以在 Settings 中通过 API Key 或 `anthropic` / `openai-codex` OAuth 连接 provider，并在 Agent
  编辑页从同步后的白名单中选择。
- 用户可以为自定义 Agent 选择 knowledge、skills、tools。
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
- 不做复杂多窗口高级管理；第一版只提供固定的 Agent Library、Resource Library 和 Settings 管理窗口。
- 不做结构化 YAML 表单或高级语法高亮；tool `tool.yaml` 第一版采用纯文本编辑。
- 不做 Agent 导入导出。
- 不做长期记住审批、复杂权限规则和审计报表。
