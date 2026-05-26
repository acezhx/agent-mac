# Runtime 打包方案

## 目标

AgentMac 第一版需要把 Node.js 和 Pi 打包进 macOS app 内，使用户不需要单独安装 Pi。

本文定义开发环境路径、app bundle 路径、Application Support 路径、运行时启动规则和打包
注意事项。

## 目录分层

### app bundle

app bundle 只存放只读运行时文件：

```text
AgentMac.app/
└─ Contents/
   └─ Resources/
      └─ Runtime/
         ├─ node/
         │  └─ bin/
         │     └─ node
         ├─ pi/
         │  └─ node_modules/
         └─ host/
            └─ runtime-host.js
```

规则：

- app bundle 内文件视为只读。
- 不把用户创建的 Agent、knowledge、skills、tools 写入 app bundle。
- 不把 logs、sessions、cache 写入 app bundle。

### Application Support

可变用户数据写入：

```text
~/Library/Application Support/AgentMac/
├─ agents/
├─ library/
├─ sessions/
├─ logs/
├─ cache/
└─ settings.yaml
```

## 开发环境路径

开发阶段可以允许使用本地 runtime 路径，方便调试：

```text
AgentMac/RuntimeHost/
```

建议支持两种模式：

```text
bundled:
  使用 app bundle 内 Runtime。

development:
  使用仓库内 RuntimeHost 和本机 Node。
```

`settings.yaml` 中可以保存：

```yaml
runtime:
  useBundledRuntime: true
```

开发调试时可以通过 Xcode scheme 环境变量覆盖：

```text
AGENTMAC_RUNTIME_MODE=development
AGENTMAC_RUNTIME_HOST_PATH=/path/to/runtime-host.js
AGENTMAC_NODE_PATH=/path/to/node
```

runtime 模式优先级：

```text
1. Xcode scheme 或进程环境变量。
2. Application Support 中的 settings.yaml。
3. 默认 bundled runtime。
```

当 `AGENTMAC_RUNTIME_MODE=development` 时，必须同时提供可用的 Runtime Host 路径和 Node
路径，或让 `RuntimeBridge` 返回明确配置错误。

## RuntimeBridge 启动规则

`RuntimeBridge` 启动 Runtime Host 时应：

1. 解析 Node 可执行文件路径。
2. 解析 Runtime Host 入口文件路径。
3. 设置工作目录。
4. 设置必要环境变量。
5. 配置 stdin/stdout/stderr pipe。
6. 启动进程。
7. 先发送 `ping` 验证 runtime 可用。

建议环境变量：

```text
AGENTMAC_APP_SUPPORT_DIR
AGENTMAC_LOG_DIR
AGENTMAC_RUNTIME_MODE
```

不要通过环境变量传递长期保存的密钥。后续需要密钥时，应由 macOS Keychain 管理。

## Runtime Host 工作目录

第一版建议 Runtime Host 工作目录使用 Application Support：

```text
~/Library/Application Support/AgentMac/
```

具体 session 的 workspace 由 `startSession` command 显式传入。

## 日志

Runtime Host 的 stderr 应由 Swift 收集，并写入：

```text
~/Library/Application Support/AgentMac/logs/runtime-host.log
```

第一版可以简单追加写入。日志轮转后置。

Swift 侧错误也可以写入：

```text
~/Library/Application Support/AgentMac/logs/app.log
```

## Node 和 Pi 打包

第一版打包目标：

- app 内存在可执行 Node。
- app 内存在 Runtime Host 脚本。
- app 内存在 Pi runtime 依赖。
- Swift 可以从 bundle 定位这些文件。
- 干净机器上不依赖用户全局安装 Pi。

需要注意：

- Node 可执行文件必须有执行权限。
- 如果包含 native `.node` 模块，签名和公证时需要一并处理。
- app sandbox 和工具执行能力可能冲突。第一版优先面向 Developer ID 分发，不先承诺 Mac
  App Store。
- Runtime Host 不应自修改 app bundle 内文件。

## 首次启动

首次启动 App 时：

1. `FileStore` 初始化 Application Support 目录。
2. 创建 `settings.yaml`。
3. 创建 `agents/`、`library/`、`sessions/`、`logs/`。
4. 不自动覆盖用户已有文件。
5. 可以创建一个示例 Agent，但该能力可后置。

## 验证步骤

开发阶段验证：

```text
1. 从 Xcode 启动 App。
2. RuntimeBridge 使用 development runtime。
3. 发送 ping，收到 pong。
4. 启动固定 Pi coding agent。
5. 从 macOS UI 发送消息并收到流式输出。
```

打包阶段验证：

```text
1. 清理本机全局 Pi 或避免依赖全局 Pi。
2. 使用 app bundle 内 Node 和 Pi。
3. 启动 App。
4. 发送 ping，收到 pong。
5. 跑通固定 Pi coding agent chat session。
6. 确认可变文件只写入 Application Support。
```

## 第一版不做

- 不做 runtime 自动更新。
- 不做在线下载 Node 或 Pi。
- 不做多版本 runtime 切换 UI。
- 不做日志轮转。
- 不做 Mac App Store sandbox 适配承诺。
