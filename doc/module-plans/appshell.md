# AppShell 模块开发计划

## 模块目标

`AppShell` 负责 macOS 应用的可见界面和导航。它把 Agent 管理、资源管理、会话页面串起来，
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

### TCA Feature 架构

- 创建根 `AppFeature`，管理应用级导航和当前选择状态。
- 为 Agent 管理、资源管理、会话页面创建子 Feature。
- 通过 TCA dependency 调用 `AgentLibrary`、`ResourceLibrary` 和 `Session` 服务。
- SwiftUI View 只渲染 Store 状态并发送 action。
- 异步加载、保存、启动会话和处理错误放在 reducer effect 中。

### 应用外壳

- 根视图。
- 主导航。
- Agent 管理入口。
- 资源管理入口。
- 会话入口。
- 基础错误展示。

### Agent 管理 UI

- Agent 列表。
- 创建 Agent。
- 选择 Agent。
- 编辑 Agent 名称。
- 编辑模型配置。
- 编辑 system prompt。
- 保存 Agent。

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

### 审批 UI 占位

- 第一阶段不做完整审批。
- 遇到默认拒绝的工具审批请求时，可以显示 unsupported/denied 提示。
- 完整 `Approval` 模块实现后再补审批弹窗或面板。

## Checklist

- [ ] 创建 `AgentMac/AppShell/` 目录。
- [ ] 创建根 `AppFeature`。
- [ ] 配置 TCA dependencies。
- [ ] 实现根视图。
- [ ] 实现主导航。
- [ ] 创建 Agent 管理 Feature。
- [ ] 实现 Agent 列表。
- [ ] 实现 Agent 创建表单。
- [ ] 实现 Agent 编辑页。
- [ ] 实现 system prompt 编辑器。
- [ ] 实现资源选择控件。
- [ ] 创建资源管理 Feature。
- [ ] 实现 knowledge 列表和编辑入口。
- [ ] 实现 skill 列表和编辑入口。
- [ ] 实现 tool 列表和编辑入口。
- [ ] 创建会话 Feature。
- [ ] 实现会话页面。
- [ ] 实现消息输入。
- [ ] 实现流式输出展示。
- [ ] 实现基础错误提示。
- [ ] 手工验证固定 Pi coding agent chat session。

## 验收标准

- UI 状态、用户操作和异步 effect 由 TCA Feature 管理。
- SwiftUI View 不直接调用 `FileStore`、`ResourceLibrary`、`AgentLibrary` 或 `RuntimeBridge`。
- 用户可以从 UI 创建 Agent。
- 用户可以编辑 Agent 的 system prompt。
- 用户可以选择 knowledge、skills、tools。
- 用户可以保存 Agent，并重新打开看到相同配置。
- 用户可以选择 Agent 启动会话。
- 用户可以发送一条消息。
- assistant 回复可以流式显示。
- runtime 失败时 UI 有明确错误提示。
- 工具审批请求在第一阶段不会让 UI 卡死。

## 第一版不做

- 不做复杂视觉设计。
- 不做多窗口高级管理。
- 不做 raw YAML 编辑器。
- 不做 Agent 导入导出。
- 不做完整审批 UI，等 `Approval` 阶段实现。
