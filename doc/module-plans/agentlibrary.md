# AgentLibrary 模块开发计划

## 模块目标

`AgentLibrary` 负责 Agent 定义的创建、加载、保存、校验和解析。它把 Agent 私有配置与共享
knowledge、skills、tools 组合成运行时可用的 `ResolvedAgentConfig`。

## 依赖关系

```text
AgentLibrary
  -> FileStore
  -> ResourceLibrary
```

`AgentLibrary` 使用 `FileStore` 读写 Agent 文件，并按 `ResourceLibrary` 的最小结构规则校验
共享资源引用。
`ResolvedAgentConfig` 中的文件路径和 workspace 路径只作为运行时临时配置输出，不写回
`agent.yaml`。

## 需要开发的功能

### Agent 创建

- 根据用户输入创建 Agent ID。
- 校验 Agent ID 路径安全。
- 创建 `agents/<agent-id>/` 目录。
- 创建 `agent.yaml`。
- 创建 Agent 私有 `system.md`。
- 写入默认模型配置。
- 写入默认权限配置。

### Agent 加载

- 扫描 `agents/` 目录。
- 加载每个 Agent 的 `agent.yaml`。
- 读取 Agent 私有 `system.md`。
- 返回 Agent 摘要列表。
- 返回完整 Agent 编辑模型。

### Agent 保存

- 保存 Agent 名称。
- 保存模型配置。
- 保存权限配置。
- 保存 selected knowledge。
- 保存 selected skills。
- 保存 selected tools。
- 保存 `system.md` 内容。
- 保存已有 Agent 时不允许通过修改 `id` 隐式重命名或复制 Agent。

### Agent 校验

- 校验 `agent.yaml` 存在。
- 校验 `system.md` 存在。
- 校验 system prompt 非空可以后置，第一版允许为空但 UI 提示。
- 校验 selected knowledge 文件存在。
- 校验 selected skill 目录存在且包含 `SKILL.md`。
- 校验 selected tool 目录存在且包含 `tool.yaml`。
- 校验 selected tool 的 `tool.yaml.entry` 指向的入口文件存在。
- 校验权限配置合法。

### Runtime 配置解析

- 将相对路径解析成绝对路径。
- 生成 `ResolvedAgentConfig`。
- `ResolvedAgentConfig` 包含：
  - Agent ID。
  - Agent 名称。
  - system prompt 绝对路径。
  - selected knowledge 绝对路径。
  - selected skills 绝对路径。
  - selected tools 绝对路径。
  - model 配置。
  - permissions 配置。
  - workspace 绝对路径。

## Checklist

- [x] 创建 `AgentMac/AgentLibrary/` 目录。
- [x] 定义 `AgentManifest`。
- [x] 定义 `ModelConfig`。
- [x] 定义 `PermissionConfig`。
- [x] 定义 `ResolvedAgentConfig`。
- [x] 定义 `AgentValidationError`。
- [x] 实现 Agent ID 校验。
- [x] 实现 Agent 创建。
- [x] 实现默认 `agent.yaml` 生成。
- [x] 实现默认 `system.md` 生成。
- [x] 实现 Agent 列表加载。
- [x] 实现单个 Agent 加载。
- [x] 实现 Agent 保存。
- [x] 实现 system prompt 读取和保存。
- [x] 实现 selected resources 保存。
- [x] 实现 Agent 校验。
- [x] 实现 `ResolvedAgentConfig` 生成。
- [x] 编写 AgentLibrary 单元测试。

## 验收标准

- 创建 Agent 后生成 `agents/<id>/agent.yaml` 和 `agents/<id>/system.md`。
- 非法 Agent ID 会创建失败。
- 重复 Agent ID 会创建失败或返回明确错误。
- Agent 列表能读取已有 Agent。
- 保存 Agent 后重新加载内容一致。
- 缺失 `system.md` 时校验失败。
- 引用不存在的 knowledge 时校验失败。
- 引用缺失 `SKILL.md` 的 skill 时校验失败。
- 引用缺失 `tool.yaml` 的 tool 时校验失败。
- 引用入口文件不存在的 tool 时校验失败。
- 合法 Agent 能生成包含绝对路径的 `ResolvedAgentConfig`。

## 第一版不做

- 不做 Agent 版本管理。
- 不做 Agent 重命名。
- 不做 Agent 复制和导入导出。
- 不做 raw YAML 高级编辑器。
- 不做 Agent 图标和颜色。
- 不做权限策略深度执行，第一版只保存和基础校验。
