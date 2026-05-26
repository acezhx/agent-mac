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
- `ResourceLibrary`
- `AgentLibrary`
- `Session`
- `Approval`

重点覆盖：

- 文件路径解析。
- 配置读写。
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
- `startSession`。
- `sendMessage` mock streaming。
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

### 手工 UI 验收

适用模块：

- `AppShell`
- 端到端流程

重点覆盖：

- 创建 Agent。
- 编辑 system prompt。
- 选择资源。
- 启动 session。
- 发送消息。
- 显示流式 assistant 输出。
- 默认拒绝工具审批请求。
- 后续审批 UI 批准/拒绝。

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

验收命令：

```text
xcodebuild test -scheme AgentMac -destination 'platform=macOS'
```

### ResourceLibrary

必须自动化覆盖：

- knowledge 识别。
- skill 最小结构校验。
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
- 非法 JSON 返回 `invalid_json`。
- 未知 command 返回 `unsupported_command`。
- mock `sendMessage` 返回多个 delta 和 completed。
- 固定 Pi coding agent 可以启动。

固定 Pi coding agent 是 Runtime Host 的临时 session mode，用于验证 SwiftUI ->
RuntimeBridge -> RuntimeHost -> Pi 主链路。该模式不读取用户 `agent.yaml`。真实 Pi 会话可能
依赖模型凭据；没有凭据时，至少保留 mock streaming 自动化测试，并在最终验收中手工验证真实
Pi 会话。

### RuntimeBridge

必须覆盖：

- 进程启动。
- `ping` 往返。
- event 解析。
- Runtime Host 退出后的错误处理。
- stderr 日志收集。

### Session

必须覆盖：

- idle -> running -> idle。
- running -> failed。
- running -> aborted。
- 用户消息追加。
- assistant delta 合并。
- tool approval request 默认拒绝。

### AppShell

第一版以手工验收为主：

- 创建 Agent。
- 编辑 system prompt。
- 选择 resources。
- 启动 session。
- 发送消息。
- 流式展示回复。

稳定后再考虑 UI 自动化。

### Approval

必须自动化覆盖：

- allow 自动批准。
- ask 进入等待用户选择。
- deny 自动拒绝。
- shell/edit/network 请求分类。
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
2. 编辑 system prompt。
3. 选择 knowledge、skills、tools。
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
5. 默认策略不自动执行高风险工具。
```

## CI 和本地执行

第一版不要求完整 CI，但本地提交前应至少运行：

```text
xcodebuild test -scheme AgentMac -destination 'platform=macOS'
```

涉及 RuntimeHost 时，还应运行 RuntimeHost 命令行协议测试。

## 测试数据规则

- 测试使用临时目录。
- 不写入真实 Application Support。
- 不依赖用户本机已有 Agent。
- 不依赖全局安装 Pi，除非该测试明确标记为本地集成测试。
- 不提交真实 API key、token 或本地私有路径。
