# 测试策略

## 目标

本文定义 AgentMac 第一版的测试分层、模块验收方式和关键手工验证流程。

测试目标：

- 每个模块完成时都有明确验收点。
- 底层文件和配置逻辑优先用自动化测试覆盖。
- RuntimeHost 和 RuntimeBridge 用协议级集成测试覆盖。
- macOS UI 先用手工验收，稳定后再补 UI 自动化。

## 测试分层

### Swift 单元测试

适用模块：

- `FileStore`
- `AppSettings`
- `ResourceLibrary`
- `AgentLibrary`
- `Session`
- `Approval`

重点覆盖：

- 文件路径解析。
- 配置读写。
- app 级设置默认值和 provider 白名单保存。
- 资源校验。
- Agent 校验。
- Session 状态流转。
- Approval 策略判断。

### Node RuntimeHost 测试

适用模块：

- `RuntimeHost`

重点覆盖：

- JSONL 输入输出。
- `ping`。
- `listModelCatalog` 模型清单。
- `startSession`。
- `sendMessage` mock streaming。
- `loginOAuthProvider` 调用 Pi `AuthStorage.login` 并转发浏览器授权事件。
- 错误事件。
- 固定 Pi coding agent 启动。

### Swift-Node 集成测试

适用模块：

- `RuntimeBridge`
- `Session`

重点覆盖：

- Swift 启动 Runtime Host。
- Swift 发送 command。
- Swift 接收 event。
- Runtime Host 异常退出。
- 流式输出合并。
- 模型清单 command 往返。

### 手工 UI 验收

适用模块：

- `AppShell`
- 端到端流程

重点覆盖：

- 创建 Agent。
- 编辑自定义 Agent 的 system prompt。
- 创建和编辑 Resource。
- 为自定义 Agent 选择资源。
- 启动 session。
- 发送消息。
- 显示流式 assistant 输出。
- 工具审批请求展示 UI。
- 审批 UI 批准/拒绝并回传 Runtime Host。

## 推荐测试命令

Swift 测试：

```text
xcodebuild test -scheme AgentMac -destination 'platform=macOS'
```

如果后续拆出 Swift Package，可增加：

```text
swift test
```

RuntimeHost 命令行测试：

```text
node --test AgentMac/RuntimeHost/runtime-host.test.mjs
```

手工协议调试：

```text
node AgentMac/RuntimeHost/runtime-host.js
```

输入示例：

```json
{"type":"command","id":"cmd_001","name":"ping","payload":{}}
```

期望输出：

```json
{"type":"event","id":"evt_001","replyTo":"cmd_001","name":"pong","payload":{}}
```

## 模块验收策略

### FileStore

必须自动化覆盖：

- 临时目录初始化。
- 文本读写。
- YAML 文件读写入口。
- 目录扫描。
- 隐藏文件过滤。
- 路径逃逸拒绝。
- 外部目录复制到 app 数据目录时保留子目录，并拒绝覆盖已有目标。
- 目录删除会移除整棵子树，并拒绝把普通文件当目录删除。

验收命令：

```text
xcodebuild test -scheme AgentMac -destination 'platform=macOS'
```

### AppSettings

必须自动化覆盖：

- 旧版最小 `settings.yaml` 解码时补齐默认 Agent provider 白名单。
- `settings.yaml` 编解码能保留 Agent provider 白名单。
- `AppSettingsStore` 通过 `FileStore` 加载和保存设置。
- `PiAuthStore` 按 Pi `auth.json` 格式保存 API Key 凭据。
- `PiAuthStore` 写入和删除单个 provider 凭据时保留其它 provider 的 OAuth 或未知凭据字段。
- `PiAuthStore` 能把 OAuth 凭据识别为已连接状态，并在删除其它 provider 时保留该条目。

依赖：使用测试临时目录，不使用真实 Application Support。

### ResourceLibrary

必须自动化覆盖：

- knowledge 识别。
- skill 最小结构校验。
- skill 目录导入。
- skill 目录删除。
- knowledge 改名保存和删除。
- tool 最小结构校验。
- 资源列表稳定排序。

依赖：使用测试临时目录，不使用真实 Application Support。

### AgentLibrary

必须自动化覆盖：

- Agent 创建。
- `agent.yaml` 生成。
- `system.md` 生成。
- Agent 加载和保存。
- 缺失资源校验失败。
- `ResolvedAgentConfig` 绝对路径生成。

### RuntimeHost

必须覆盖：

- `ping` 返回 `pong`。
- `listModelCatalog` 在 mock 模式和 vendored Pi 可用时返回 provider 过滤后的模型清单。
- 非法 JSON 返回 `invalid_json`。
- 未知 command 返回 `unsupported_command`。
- mock `sendMessage` 返回多个 delta 和 completed。
- 固定 Pi coding agent 可以启动。
- 固定 Pi coding agent 启用 Pi 内建 `read`、`bash`、`edit`、`write` 工具，工具调用会在执行前进入
  Runtime Host 审批 hook。
- Runtime Host 会把 toolcall 和工具执行阶段的非文本进度转成 `runtimeActivity`。
- Runtime Host 的 `loginOAuthProvider` 只接受当前支持的 `anthropic` 和 `openai-codex`，并把 Pi OAuth
  授权 URL 转成 `oauthAuthorizationRequested`。
- vendored Node/Pi 存在时，faux provider 集成测试可以覆盖固定 Pi coding agent 的流式输出。

固定 Pi coding agent 是 Runtime Host 的临时 session mode，用于验证 SwiftUI ->
RuntimeBridge -> RuntimeHost -> Pi 主链路。该模式不读取用户 `agent.yaml`。真实 Pi 会话可能
依赖模型凭据；没有凭据时，至少保留 mock streaming 自动化测试，并在最终验收中手工验证真实
Pi 会话。

### RuntimeBridge

必须覆盖：

- 进程启动。
- `ping` 往返。
- `listModelCatalog` 往返。
- `startSession` 和 `sendMessage` 流式输出。
- `abortSession` 清理。
- event 解析。
- Runtime Host error event 映射。
- Runtime Host 退出后的错误处理。
- stderr 日志收集。
- `runtimeActivity` 会延长 `sendMessage` 的空闲等待，不会被误判为 Runtime Host 无响应。
- 用户审批等待时间不消耗外层 `sendMessage` 的空闲等待窗口。

### Session

必须覆盖：

- idle -> running -> idle。
- running -> failed。
- running -> aborted。
- 用户消息追加。
- assistant delta 合并。
- 重复 start、未完成 send 再 send、failed/aborted 后 send 的边界错误。
- abort 后迟到 event 不覆盖 aborted 状态。
- tool approval request 记录决策并通过 RuntimeBridge 回传。

### AppShell

第一阶段固定 coding agent 会话竖切需要 reducer/state 自动化测试，UI 视觉测试暂缓。

必须自动化覆盖：

- 创建 session 成功后保存 `ChatSessionSnapshot` 并启动快照订阅 effect。
- 根 AppFeature 启动时初始化 Application Support 数据目录，且成功后不重复初始化。
- 启动初始化会在缺失时创建表示内置 Pi coding agent 的默认 `coding-agent`，且不会覆盖用户已有的同 ID Agent。
  默认 `coding-agent` 的编辑保存只覆盖模型配置。
- 启动初始化失败时展示错误。
- Runtime 常见启动错误映射为包含修复方向的 UI 提示。
- 第一阶段已有当前 session 时不会再次创建本地 session。
- 启动 Runtime session 的进行中标记和成功清理。
- 发送消息时裁剪空白、清空输入并调用 dependency。
- failed snapshot 同步为 UI 错误信息。
- abort/reset action 调用 dependency 并清理进行中标记。
- create/start/send/abort/reset 失败时清理对应进行中标记并展示错误。
- 快照订阅失败时展示错误。
- Agent 列表加载后保存摘要。
- 选择 Agent 后加载编辑区字段，并同步已选择的 knowledge、skills、tools。
- Agent 编辑页加载 ResourceLibrary 中可选的 knowledge、skills、tools。
- Agent 编辑页加载 Settings 中的模型 provider 白名单，并只允许保存白名单内的 provider。
- Agent 编辑页加载 RuntimeHost/Pi 模型清单，切换 provider 时选择该 provider 下的模型。
- 模型清单已加载时，Agent 编辑页不保存当前 provider 下不存在的模型 name。
- Agent 编辑页勾选或取消勾选资源时更新当前编辑状态。
- 保存默认 Pi coding agent 时只提交模型配置，并恢复 Pi 自身管理的 system prompt、资源和权限默认值。
- 创建 Agent 后清空创建表单、选中新 Agent 并更新列表。
- 保存 Agent 时提交当前资源选择，并保留 system prompt、模型和权限配置。
- Agent 创建和保存失败时清理对应进行中标记并展示错误。
- Resource 列表按当前类型加载并保存摘要。
- 切换 Resource 类型时清空编辑区并加载新类型列表。
- 选择 Resource 后加载编辑区字段。
- 创建 Resource 后清空创建表单、选中新 Resource 并更新列表。
- 创建 knowledge 时允许 UI 不提供 ID，并由 Resource dependency 生成未占用文件名。
- 保存 knowledge 时提交编辑后的名称，改名成功后替换列表旧项并显示成功提示。
- 删除 knowledge 时移除列表项并清空编辑区。
- 创建 skill 时允许 UI 不提供 ID，并由 Resource dependency 生成未占用 ID。
- 导入 skill 时只在当前 Resource 类型为 skill 时触发，导入成功后更新列表、选中新资源并加载编辑区。
- 导入 skill 的 ID 基于源目录名生成，并避开已有 skill ID。
- skill 展示名从 `SKILL.md` frontmatter 的 `name` 字段读取，缺失时回退到目录 ID。
- 保存 skill 时提交编辑后的 `SKILL.md`，更新展示名但不改变目录 ID。
- 删除 skill 时只在当前 Resource 类型为 skill 且已有选中资源时触发，删除成功后移除列表项并清空编辑区。
- 创建 tool 时允许 UI 不提供 ID 和名称，并由 Resource dependency 生成未占用 ID。
- 删除 tool 时移除列表项并清空编辑区。
- 保存 Resource 时提交编辑区内容；tool 同时提交 `tool.yaml` 和入口文件内容。
- Resource 创建、保存和删除失败时清理对应进行中标记并展示错误。
- Settings 页面加载 Agent provider 白名单和 Pi provider 凭据状态。
- Settings 页面保存 API Key 后写入凭据，并把 provider 加入 Agent provider 白名单。
- Settings 页面完成 `anthropic` 或 `openai-codex` OAuth 登录后把 provider 加入 Agent provider 白名单，
  登录失败时回滚。
- Settings 页面断开 API Key provider 后删除凭据，并从 Agent provider 白名单移除。

当前测试位置：

```text
AgentMacTests/AppShell/AgentFeatureTests.swift
AgentMacTests/AppShell/AppFeatureTests.swift
AgentMacTests/AppShell/AppResourceClientTests.swift
AgentMacTests/AppShell/AppSessionClientTests.swift
AgentMacTests/AppShell/ResourceFeatureTests.swift
AgentMacTests/AppShell/SettingsFeatureTests.swift
AgentMacTests/AppShell/SessionFeatureTests.swift
AgentMacTests/AppSettings/AppSettingsTests.swift
```

主窗口 toolbar 打开 Agent Library、Resource Library 和 Settings 独立窗口属于 SwiftUI scene 编排，第一版通过
macOS build 和手工 UI 验收覆盖；窗口内部的业务状态仍由 `AgentFeatureTests` 和
`ResourceFeatureTests`、`SettingsFeatureTests` 覆盖。

手工验收仍覆盖：

- 创建固定 coding agent session。
- 启动 Runtime Host session。
- 发送消息。
- 流式展示回复。
- 展示 failed/aborted 状态。
- abort/reset 最小路径。

2026-05-27 已用真实 Pi 和本地模型配置从 macOS UI 跑通固定 coding agent chat session。
本地调试可把 Pi 配置放在 `~/Library/Application Support/AgentMac/Pi/settings.json` 和
`~/Library/Application Support/AgentMac/Pi/auth.json`；Settings 页面当前会把 API Key 凭据写入
`auth.json`，也会通过 RuntimeHost/Pi `AuthStorage` 为 `anthropic` 和 `openai-codex` 写入 OAuth 凭据。
该文件不应提交到仓库。

Agent 管理、资源管理和 Approval UI 分别补 reducer 测试；必要的 UI 自动化按风险后续增加。
当前 Agent 管理 UI、资源管理 UI 和 Approval 确认路径已有 reducer 测试。

### Approval

必须自动化覆盖：

- allow 自动批准。
- ask 下 Pi 内建 read/edit/write 自动批准。
- ask 下非删除 bash shell 请求自动批准，匹配文件删除语义的 bash 进入等待用户选择。
- deny 自动拒绝。
- shell/edit/write/network 请求分类；Pi `read` 按文件类权限进入现有 edit 策略。
- 关闭审批 UI 按 denied 处理。

## 端到端验收

基础 chat session 验收：

```text
1. 启动 App。
2. RuntimeBridge 启动 Runtime Host。
3. Runtime Host ping 成功。
4. 选择固定 Pi coding agent。
5. 从 UI 输入一条消息。
6. assistant 回复流式显示。
7. session 完成后 UI 回到可输入状态。
```

可配置 Agent 验收：

```text
1. 创建 Agent。
2. 编辑自定义 Agent 的 system prompt。
3. 为自定义 Agent 选择 knowledge、skills、tools。
4. 保存 Agent。
5. 重新打开 Agent，配置保持一致。
6. 使用该 Agent 启动 session。
```

工具审批验收：

```text
1. Runtime Host 发出 toolApprovalRequested。
2. UI 展示审批请求。
3. 用户批准后 runtime 收到 approved。
4. 用户拒绝后 runtime 收到 denied。
5. 默认策略自动执行 read/edit/write 和非删除 bash，但不自动执行匹配文件删除语义的 bash 等高风险工具。
```

## CI 和本地执行

第一版不要求完整 CI，但本地提交前应至少运行：

```text
xcodebuild test -scheme AgentMac -destination 'platform=macOS'
```

默认 `AgentMac` scheme 的 TestAction 只运行 `AgentMacTests`，并关闭测试目标并行执行，保证
app-hosted 单元测试稳定结束。`AgentMacUITests` 不放入默认验证链路，避免 UI 启动和性能测试
反复启动/终止宿主 App 干扰单元测试；需要 UI 验证时单独运行 UI test target 或执行手工 UI 验收。
当前 `AgentMacTests` 仍依赖 app host，因为业务代码还直接位于 `AgentMac` app target；如需彻底改为
非 app-hosted 单元测试，应先把可测试业务代码拆入独立 framework 或 Swift package target。

涉及 RuntimeHost 时，还应运行 RuntimeHost 命令行协议测试。

## 测试数据规则

- 测试使用临时目录。
- 不写入真实 Application Support。
- 不依赖用户本机已有 Agent。
- 不依赖全局安装 Pi，除非该测试明确标记为本地集成测试。
- 不提交真实 API key、token 或本地私有路径。
