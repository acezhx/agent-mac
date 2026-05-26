# RuntimeBridge 模块开发计划

## 模块目标

`RuntimeBridge` 负责 Swift 侧与 Node Runtime Host 的进程通信。它启动 Runtime Host，发送
JSONL commands，读取 JSONL events，并把它们映射成 Swift 类型。

## 依赖关系

```text
RuntimeBridge
  -> AgentLibrary
  -> RuntimeHost process
```

`RuntimeBridge` 不编辑资源，不理解 UI，也不包含 Pi SDK 代码。

## 需要开发的功能

### Runtime 定位

- 定位内置 Node 可执行文件。
- 定位 Runtime Host 脚本。
- 支持开发环境下使用本地 runtime 路径。
- 支持 app bundle 内 runtime 路径。

### 进程管理

- 启动 Runtime Host 进程。
- 配置 stdin/stdout/stderr pipe。
- 停止 Runtime Host 进程。
- 处理进程异常退出。
- 防止重复启动未释放的进程。

### JSONL 通信

- 发送 command。
- 读取 event。
- 支持流式读取多行 event。
- 处理 event JSON 解析失败。
- 将 Runtime Host event 映射成 Swift 类型。

### Command API

- `ping`
- `startSession`
- `sendMessage`
- `abortSession`
- 后续支持 approval response。

### 错误处理

- Node 不存在。
- Runtime Host 脚本不存在。
- 进程启动失败。
- 写入 stdin 失败。
- stdout 解析失败。
- Runtime Host 返回 error event。

## Checklist

- [ ] 创建 `AgentMac/RuntimeBridge/` 目录。
- [ ] 定义 `RuntimeCommand`。
- [ ] 定义 `RuntimeEvent`。
- [ ] 定义 `RuntimeBridgeError`。
- [ ] 实现 runtime 路径配置。
- [ ] 实现进程启动。
- [ ] 实现进程停止。
- [ ] 实现 stderr 日志收集。
- [ ] 实现 JSONL command 写入。
- [ ] 实现 JSONL event 读取。
- [ ] 实现 `ping`。
- [ ] 实现 `startSession`。
- [ ] 实现 `sendMessage`。
- [ ] 实现 `abortSession`。
- [ ] 编写 RuntimeBridge 单元测试或集成测试。

## 验收标准

- Swift 可以启动 Runtime Host。
- Swift 可以发送 `ping` 并收到 `pong`。
- Swift 可以发送 `startSession` 并收到 started event。
- Swift 可以发送 `sendMessage` 并收到流式 delta。
- Runtime Host 异常退出时 Swift 能收到明确错误。
- JSON event 解析失败时不会导致 app 崩溃。
- 停止 session 或退出页面时能清理 Runtime Host 进程。

## 第一版不做

- 不直接执行工具。
- 不解析 `SKILL.md`。
- 不管理 Agent 文件。
- 不实现完整审批 UI。
- 不支持多个 Runtime Host 进程池。
