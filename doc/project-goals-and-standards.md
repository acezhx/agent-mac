# AgentMac 项目目标与规范

## 项目目标

AgentMac 是一个基于 Pi agent 框架构建的 macOS 桌面应用。它的目标是提供一个本地的、
可配置的 Agent 工作台，用于支持不同业务场景。

应用需要做到：

- 将 Node.js 和 Pi 打包进 macOS 应用内，用户不需要单独安装 Pi。
- 支持用户创建和维护多个业务 Agent。
- 每个 Agent 可以拥有自己的 system prompt、模型配置、权限配置和资源组合。
- knowledge、skills、tools 可以独立维护，并在创建或编辑 Agent 时进行组合。
- 第一版保持足够简单，除非确实需要，否则不引入数据库化管理、版本管理等复杂能力。

## 产品范围

### 第一版范围

第一版需要支持：

- 创建和编辑 Agent。
- 编辑 Agent 私有的 system prompt。
- 管理共享 knowledge 文件。
- 管理共享 skill 目录。
- 管理共享 tool 目录。
- 在编辑 Agent 时选择 knowledge、skills、tools。
- 从 macOS 应用内运行基于 Pi 的 Agent 会话。
- 展示流式 assistant 输出。
- 基础 chat session 跑通后，再增加高风险工具执行前的用户确认。
- 将可变用户数据存储在 Application Support 目录下。

### 第一版不做

在简单模型被证明不够之前，不做以下能力：

- 用数据库管理 Agent 或资源定义。
- prompt 或资源版本管理。
- 草稿、发布、上线流程。
- 回滚流程。
- Agent 市场。
- 复杂资源继承。
- knowledge 向量索引。
- 团队同步。
- 云端后端。

## 核心产品决策

### SwiftUI 应用架构采用 TCA

macOS UI 和应用级状态编排采用 The Composable Architecture（TCA）。

规范：

- `AppShell` 以及 Agent 管理、资源管理、会话、审批等可见功能优先按 TCA Feature 组织。
- SwiftUI View 只负责渲染状态和发送 action，不直接承载业务流程或长生命周期副作用。
- Reducer 负责 UI 状态转移、用户 action 处理和 effect 编排。
- 文件访问、Agent 读写、资源管理、runtime 通信等能力保留在对应服务模块，通过 TCA
  dependency 注入到 Feature。
- SwiftUI View 读取 TCA perceptible store 状态时必须遵守 AppShell 的 Perception 追踪规范，
  避免在逃逸 ViewBuilder 闭包、sheet、列表行或绑定派生处绕过 `WithPerceptionTracking`。
- `FileStore`、`ResourceLibrary`、`AgentLibrary`、`RuntimeBridge` 等底层模块不因为项目采用
  TCA 就直接依赖 TCA。

TCA 是 UI 和应用编排架构，不是所有数据结构和底层服务的统一基类。

### 内置 Node 和 Pi

应用需要包含内置的 Node.js runtime 和 Pi runtime。

Swift 不重新实现 agent runtime。职责边界是：

- SwiftUI 负责 macOS UI、资源编辑器、会话界面和权限确认。
- 内置的 Node Runtime Host 负责 Pi 集成。
- Pi 负责 agent 执行、模型交互、工具执行、skills 加载和流式事件。

### Agent 配置优先使用文件

Agent 配置和可复用资源优先使用文件维护。

在当前产品范围内，不使用数据库管理：

- Agent 定义。
- system prompt。
- knowledge 文件。
- skills。
- tool 源码。

后续如果需要，可以为会话历史、应用 UI 状态、日志、搜索索引或其他运行时记录引入
数据库。第一版 Agent 和资源管理不依赖数据库。

### 一个 Agent 一个目录

每个 Agent 在 Application Support 下拥有独立目录。

每个 Agent 拥有：

- `agent.yaml`
- `system.md`
- 模型配置。
- 权限配置。
- 已选择的 knowledge、skills、tools。

system prompt 不是共享库资源。它随 Agent 创建，并在 Agent 编辑器里维护。

### 共享资源独立维护

knowledge、skills、tools 作为共享资源库独立维护。

Agent 通过选择已有资源进行组合。默认不复制共享资源。

## 资源归属规则

### Agent 私有资源

这些内容属于每个 Agent 目录：

- `agent.yaml`
- `system.md`
- Agent 模型配置
- Agent 权限配置
- 已选择的 knowledge、skills、tools 列表

### 共享资源

这些内容属于共享资源库：

- knowledge 文件
- skill 目录
- tool 目录

共享资源应该可以脱离具体 Agent 独立编辑。

## 应用功能

### Agent 管理

MVP：

- 展示 Agent 列表。
- 创建 Agent。
- 编辑 Agent 名称和模型。
- 编辑 Agent 的 system prompt。
- 选择 knowledge 文件。
- 选择 skills。
- 选择 tools。
- 配置基础权限。
- 启动测试会话。

### 资源管理

MVP：

- 管理 knowledge 文件。
- 管理 skills。
- 管理 tools。
- 保持资源独立于 Agent。
- 让 Agent 通过选择来组合已有资源。

### 会话界面

MVP：

- 选择 Agent。
- 选择 workspace。
- 启动会话。
- 发送消息。
- 展示流式输出。
- 展示工具活动。
- 基础 chat session 阶段可以先默认拒绝需要审批的工具请求。
- 基础 chat session 跑通后，增加高风险工具执行前的用户确认。
- 将会话文件存储在 `sessions/` 下。

## 安全与权限规范

工具执行是安全边界。

应用应该：

- 默认使用谨慎权限。
- 基础 chat session 阶段默认拒绝需要审批的工具请求。
- 完整审批模块实现后，在高风险工具执行前请求确认。
- 将 shell 命令、文件编辑、网络访问、密钥访问视为敏感操作。
- 在 macOS UI 中清楚展示用户确认流程。
- 避免从 SwiftUI view 中直接执行工具。
- 将可变用户数据放在只读 app bundle 之外。

## 简化原则

优先使用满足当前需求的最简单模型。

不要提前增加：

- 文件配置尚未不足时的数据库。
- 用户尚未需要历史时的版本管理。
- 没有分发流程前的发布工作流。
- 简单资源选择尚未变痛苦前的复杂继承。
- 基础 knowledge 加载尚未不足前的向量索引。

第一个成功里程碑是：一个完整打包的 macOS 应用，可以在用户不单独安装 Pi 的情况下，
基于文件型 Agent 配置运行 Pi-backed Agent。
