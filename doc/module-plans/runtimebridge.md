# RuntimeBridge 模块开发计划

## 模块目标

`RuntimeBridge` 负责 Swift 侧与 Node Runtime Host 的进程通信。它启动 Runtime Host，发送
JSONL commands，读取 JSONL events，并把它们映射成 Swift 类型。

## 依赖关系

```text
RuntimeBridge
  -> RuntimeHost process
```

`RuntimeBridge` 不编辑资源，不理解 UI，也不包含 Pi SDK 代码。第一版直接通过显式配置定位
Node 和 Runtime Host；后续接入 Session/AgentLibrary 时再由上层传入已解析的 runtime 配置。

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
- `listModelCatalog`
- `startSession`
- `sendMessage`
- `abortSession`
- `approveToolCall`

### 错误处理

- Node 不存在。
- Runtime Host 脚本不存在。
- app bundle 中的 Pi runtime 入口不存在。
- 进程启动失败。
- 写入 stdin 失败。
- stdout 解析失败。
- Runtime Host 返回 error event。

## Checklist

- [x] 创建 `AgentMac/RuntimeBridge/` 目录。
- [x] 定义 `RuntimeCommand`。
- [x] 定义 `RuntimeEvent`。
- [x] 定义 `RuntimeBridgeError`。
- [x] 实现 runtime 路径配置。
- [x] 校验 app bundle 内 Pi runtime 入口。
- [x] 实现进程启动。
- [x] 实现进程停止。
- [x] 实现 stderr 日志收集。
- [x] 实现 JSONL command 写入。
- [x] 实现 JSONL event 读取。
- [x] 实现 `ping`。
- [x] 实现 `listModelCatalog`。
- [x] 实现 `startSession`。
- [x] 实现 `sendMessage`。
- [x] 实现 `abortSession`。
- [x] 编写 RuntimeBridge 单元测试或集成测试。

## 当前实现

- `RuntimeBridgeConfiguration` 支持显式路径和 app bundle 内 `Contents/Resources/Runtime` 路径；
  bundled 配置会同时预校验 Node、Runtime Host 和 Pi module entry。
- `RuntimeBridge` 负责启动 vendored Node、运行 Runtime Host、维护 stdin/stdout/stderr pipe，并可将
  Runtime Host stderr 追加写入 `logs/runtime-host.log`。
- `RuntimeCommand`、`RuntimeEvent`、`RuntimeJSONValue` 描述 JSONL command/event envelope。
- `RuntimeBridgeError` 覆盖配置缺失、Pi runtime 缺失、进程状态、写入失败、event 解析失败、
  Runtime Host error event 和进程异常退出。
- `ping`、`listModelCatalog`、`startSession`、`sendMessage`、`abortSession` 已按第一版 Runtime
  协议实现。
- `sendMessage` 支持可选 event 回调，上层 `Session` 可在收集完整 events 的同时逐条处理
  `assistantDelta`、`runtimeActivity` 和 `messageCompleted`；`timeout` 表示等待下一条 event 的空闲
  秒数，不包含用户审批耗时。
- 第一版不并发发送多个 command；调用方应串行调用 RuntimeBridge API。

## 验证方法

```text
node --test AgentMac/RuntimeHost/runtime-host.test.mjs
xcodebuild test -scheme AgentMac -destination 'platform=macOS' -only-testing:AgentMacTests
```

## 验收标准

- Swift 可以启动 Runtime Host。
- Swift 可以发送 `ping` 并收到 `pong`。
- Swift 可以发送 `listModelCatalog` 并收到模型清单。
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
