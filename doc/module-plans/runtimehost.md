# RuntimeHost 模块开发计划

## 模块目标

`RuntimeHost` 是 Node 侧运行时桥接层。它通过 JSONL 与 Swift 通信，负责加载 Pi、启动固定
Pi coding agent，并把 Pi events 转成 App 侧稳定事件格式。

## 依赖关系

```text
RuntimeHost
  -> Pi runtime
```

`RuntimeHost` 不拥有 macOS UI，也不成为 Agent 定义的事实来源。

## 需要开发的功能

### Node 入口

- 创建 Runtime Host 入口文件。
- 从 stdin 按行读取 JSONL command。
- 向 stdout 按行写入 JSONL event。
- stderr 输出诊断日志。
- 支持进程正常退出。

### JSONL 协议

- 定义 command envelope。
- 定义 event envelope。
- 支持 request id 或 command id。
- 支持错误事件。
- 支持基础命令：
  - `ping`
  - `listModelCatalog`
  - `startSession`
  - `sendMessage`
  - `abortSession`
- 第一阶段命令字段保持最小。

### 模型清单

- 支持 `listModelCatalog` command。
- mock 模式返回稳定模型清单，供 RuntimeHost/RuntimeBridge 和 AppShell reducer 测试使用。
- Pi 模式从 `@earendil-works/pi-ai/dist/models.js` 读取 provider、model 和 supported thinking levels。
- `listModelCatalog` 只返回模型摘要，不写入 `agent.yaml`、`settings.yaml` 或 `auth.json`。

### Mock 流式事件

- 在接入 Pi 前先支持模拟 streaming。
- `sendMessage` 返回多个 delta event。
- 最后返回 completed event。
- 接入 Pi 后 mock 仅作为测试模式保留，通过 `AGENTMAC_RUNTIMEHOST_USE_MOCK_PI=1` 显式启用。

### 固定 Pi coding agent

- 加载 bundled Pi runtime。
- 支持 `startSession.payload.agent.mode = fixedCodingAgent`。
- 使用 Runtime Host 内置的 Pi coding agent 默认配置启动 session。
- 不读取用户 `agent.yaml`。
- 不加载用户选择的 knowledge、skills、tools。
- 启用 Pi 内建 `read`、`bash`、`edit`、`write` 工具。
- 自定义 tools 默认不启用。
- 接收用户消息。
- 转发 assistant streaming output。
- 转发 toolcall 和工具执行阶段的 `runtimeActivity` 心跳。
- 转发 session completed 或 failed。
- 当前实现使用 Pi `createAgentSession`、内存 session manager 和显式 `tools` 列表。
- RuntimeHost 显式禁用外部 Pi extensions、skills、prompt templates、themes 和项目 context files。
- Pi 可变配置目录默认写入 `~/Library/Application Support/AgentMac/Pi`，也可由
  `AGENTMAC_PI_AGENT_DIR` 覆盖。

### 审批扩展点

- RuntimeHost 通过内联 Pi extension 在 `tool_call` 执行前输出 `toolApprovalRequested`。
- 支持 `approveToolCall` command，接收 approved/denied 决策。
- RuntimeHost 只接收决策；approved 时继续 Pi runtime 流程，denied 时向 Pi 返回阻断结果，
  不把工具执行下沉到 Swift。
- toolcall 流和工具执行开始/更新/结束会输出 `runtimeActivity`，作为 Swift 侧空闲等待心跳。

### 错误与日志

- JSON 解析失败返回 protocol error。
- 未知命令返回 unsupported command。
- Pi 启动失败返回 runtime error。
- 所有错误包含可诊断 message。

## Checklist

- [x] 创建 `AgentMac/RuntimeHost/` 或 runtime host 源码目录。
- [x] 实现 stdin JSONL reader。
- [x] 实现 stdout JSONL writer。
- [x] 定义 command/event envelope。
- [x] 实现 `ping`。
- [x] 实现 `listModelCatalog` 模型清单 command。
- [x] 实现 mock `startSession`。
- [x] 实现 mock `sendMessage` streaming。
- [x] 实现 `abortSession` 占位。
- [x] 接入固定 Pi coding agent。
- [x] 支持 `fixedCodingAgent` session mode。
- [x] 将 Pi events 转为稳定 event。
- [x] 实现工具审批请求和决策回传协议。
- [x] 实现协议错误处理。
- [x] 编写 RuntimeHost 命令行验证脚本或测试。

## 验收标准

- 命令行启动 Runtime Host 后进程保持运行。
- 输入 `ping` command 后输出 `pong` event。
- 输入 `listModelCatalog` command 后输出 provider 过滤后的 `modelCatalogListed` event。
- 输入非法 JSON 后输出 protocol error，进程不崩溃。
- 输入未知 command 后输出 unsupported command。
- mock 模式下 `sendMessage` 能输出多个 delta 和一个 completed。
- 接入 Pi 后，固定 Pi coding agent 能成功启动。
- 固定 Pi coding agent 能对用户消息产生流式回复。
- 固定 Pi coding agent 模式不读取用户 `agent.yaml`。
- 遇到需要审批的工具请求时发出 `toolApprovalRequested`，并能接收 approved/denied 决策。

## 第一版不做

- 不加载任意自定义 tool。
- 不做 Agent 编辑和资源维护。
- 不做长期 session 存储。
- 不做 runtime 自动更新。
