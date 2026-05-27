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
  - `startSession`
  - `sendMessage`
  - `abortSession`
- 第一阶段命令字段保持最小。

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
- 自定义 tools 默认不启用。
- 接收用户消息。
- 转发 assistant streaming output。
- 转发 session completed 或 failed。
- 当前实现使用 Pi `createAgentSession`、内存 session manager 和 `noTools: "all"`。
- RuntimeHost 显式禁用 Pi extensions、skills、prompt templates、themes 和项目 context files。
- Pi 可变配置目录默认写入 `~/Library/Application Support/AgentMac/Pi`，也可由
  `AGENTMAC_PI_AGENT_DIR` 覆盖。

### 审批扩展点

- 如果 Pi/runtime 返回工具审批请求，第一阶段返回 denied/unsupported。
- 保留 approval request event 格式。
- 不阻塞基础 chat session。

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
- [x] 实现 mock `startSession`。
- [x] 实现 mock `sendMessage` streaming。
- [x] 实现 `abortSession` 占位。
- [x] 接入固定 Pi coding agent。
- [x] 支持 `fixedCodingAgent` session mode。
- [x] 将 Pi events 转为稳定 event。
- [x] 实现默认审批拒绝。
- [x] 实现协议错误处理。
- [x] 编写 RuntimeHost 命令行验证脚本或测试。

## 验收标准

- 命令行启动 Runtime Host 后进程保持运行。
- 输入 `ping` command 后输出 `pong` event。
- 输入非法 JSON 后输出 protocol error，进程不崩溃。
- 输入未知 command 后输出 unsupported command。
- mock 模式下 `sendMessage` 能输出多个 delta 和一个 completed。
- 接入 Pi 后，固定 Pi coding agent 能成功启动。
- 固定 Pi coding agent 能对用户消息产生流式回复。
- 固定 Pi coding agent 模式不读取用户 `agent.yaml`。
- 遇到需要审批的工具请求时返回 denied/unsupported。

## 第一版不做

- 不加载任意自定义 tool。
- 不做完整审批流程。
- 不做 Agent 编辑和资源维护。
- 不做长期 session 存储。
- 不做 runtime 自动更新。
