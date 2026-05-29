# AppSettings 模块开发计划

## 模块目标

`AppSettings` 负责 app 级 `settings.yaml` 的模型、轻量 YAML 编解码和读写边界，也维护 Settings
页面使用的 Pi provider 目录和 `Pi/auth.json` API Key 写入边界。它让上层功能可以读取和保存跨
Agent 共享的应用设置，同时保持 SwiftUI/TCA 和底层文件服务解耦。

## 依赖关系

```text
AppSettings
  -> FileStore
```

`AppSettings` 不依赖 `AppShell`、`AgentLibrary`、`ResourceLibrary`、`Session` 或 `RuntimeHost`。

## 需要开发的功能

### 设置模型

- 定义 `AppSettings`。
- 定义 `RuntimeSettings`。
- 定义 `AgentAppSettings`。
- 提供缺失字段时可用的默认值。

### settings.yaml 编解码

- 解析当前 `settings.yaml` 支持的一层标量、二级映射和字符串数组。
- 编码当前 app 级设置。
- 兼容旧版最小 settings 文件。
- 对无效字段类型返回可诊断错误。

### 设置存储

- 通过 `FileStore` 读取 `settings.yaml`。
- 通过 `FileStore` 保存 `settings.yaml`。
- 保存前规范化 Agent model provider 列表，移除空值和重复项。

### Provider 授权

- 定义 AgentMac 支持展示的 Pi provider 目录。
- 区分 API Key 授权和 OAuth/订阅授权。
- 读取 `Pi/auth.json` 中指定 provider 的凭据状态。
- 写入或删除 API Key 凭据，并保留其它 provider 的未知凭据字段。

## 当前字段

- `appDataVersion`
- `lastWorkspace`
- `runtime.useBundledRuntime`
- `agent.allowedModelProviders`

`agent.allowedModelProviders` 是 Agent 编辑页可选择的模型 provider 白名单。具体模型名仍保存在
每个 Agent 的 `agent.yaml` 中。

`Pi/auth.json` 是 Pi coding agent 自身读取的授权文件。Settings 页面保存 API Key 后会写入
`{"type":"api_key","key":"..."}` 条目，并同步更新 `agent.allowedModelProviders`。

## 非目标

- 不实现 OAuth/订阅授权创建和刷新。
- 不把模型 API key 写入 `settings.yaml`。
- 不保存 Agent 自身定义。
- 不解析或生成 `agent.yaml`。
- 不控制 RuntimeHost session mode。
- 不持有 SwiftUI/TCA 状态。

## Checklist

- [x] 创建 `AgentMac/AppSettings/` 目录。
- [x] 定义 app 级设置模型。
- [x] 实现 settings YAML 编解码。
- [x] 实现 `AppSettingsStore`。
- [x] 定义 provider 目录和 Pi auth API Key 存储边界。
- [x] 编写 AppSettings 单元测试。

## 验收标准

- 默认 `settings.yaml` 可以解码为可用设置。
- 旧版最小 `settings.yaml` 会补齐默认 Agent provider 白名单。
- 保存设置后可以重新读回相同的 provider 白名单。
- API Key 凭据可以按 Pi `auth.json` 格式保存、读取状态和删除，并保留其它 provider 凭据。
- `AppShell` 通过 TCA dependency 访问设置，不直接读写 `FileStore`。
