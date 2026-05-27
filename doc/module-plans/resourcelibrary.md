# ResourceLibrary 模块开发计划

## 模块目标

`ResourceLibrary` 负责维护共享 knowledge、skills、tools。它让这些资源可以脱离具体 Agent
独立创建、编辑、校验和选择。

## 依赖关系

```text
ResourceLibrary
  -> FileStore
```

`ResourceLibrary` 通过 `FileStore` 访问文件系统，不直接处理底层路径安全细节。

## 当前文件划分

当前实现仍属于主 macOS app target 内的 `AgentMac/ResourceLibrary/` 文件夹，不是独立
package 或独立 Xcode target。文件按资源类型拆分：

- `ResourceModels.swift`：定义 `ResourceKind`、资源校验错误、校验结果和
  `KnowledgeResource`、`SkillResource`、`ToolResource`。
- `ResourceLibrary.swift`：定义 `ResourceLibrary` 服务入口、共享目录常量、资源 ID 校验和
  路径构造 helper。
- `ResourceLibrary+Knowledge.swift`：维护 knowledge 文件的列表、创建、读取、保存和文件名校验。
- `ResourceLibrary+Skill.swift`：维护 skill 目录、`SKILL.md` 读写、删除和最小结构校验。
- `ResourceLibrary+Tool.swift`：维护 tool 目录、`tool.yaml`、入口文件读写和最小结构校验。

拆分后的文件边界只用于降低单文件复杂度，不改变模块依赖关系。`ResourceLibrary` 仍然只通过
`FileStore` 访问磁盘，不依赖 Agent、Session、Runtime 或 UI。

## 需要开发的功能

### Knowledge 管理

- 列出 `library/knowledge/` 下的 knowledge 文件。
- 支持 Markdown 文件。
- 支持纯文本文件。
- 创建 knowledge 文件。
- 读取 knowledge 内容。
- 保存 knowledge 内容。
- 保存 knowledge 时支持改名，改名会保留当前 `.md` 或 `.txt` 扩展名。
- 删除 knowledge 文件。
- 导入本地 Markdown 或文本文件可以后置到 UI 阶段。

### Skill 管理

- 列出 `library/skills/` 下的 skill 目录。
- 校验 skill 目录至少包含 `SKILL.md`。
- 创建 skill 目录。
- 创建初始 `SKILL.md`。
- 导入已有 skill 目录，要求源目录顶层包含 `SKILL.md`，并完整复制目录内容。
- 删除已有 skill 目录及其全部内容。
- 读取 `SKILL.md`。
- 保存 `SKILL.md`。
- 从 `SKILL.md` 顶部 YAML frontmatter 的 `name` 字段读取 skill 展示名，缺失时回退到目录 ID。
- 支持 `references/` 目录存在。
- 导入时保留 `references/`、`scripts/`、`assets/` 等已有子目录；`ResourceLibrary` 只校验最小结构，
  不解释这些目录的内容。
- 第一版只做最小结构校验，不做完整 skill 规范校验。

### Tool 管理

- 列出 `library/tools/` 下的 tool 目录。
- 校验 tool 目录包含 `tool.yaml`，且 `tool.yaml.entry` 指向的入口文件存在。
- 创建 tool 目录。
- 创建初始 `tool.yaml`。
- 删除已有 tool 目录及其全部内容。
- 读取 `tool.yaml`。
- 保存 `tool.yaml`。
- 读取入口文件内容。
- 保存入口文件内容。
- 支持默认入口文件 `index.js`。
- 第一版只校验文件存在，不执行 tool。

### 资源模型

- 定义 `KnowledgeResource`。
- 定义 `SkillResource`。
- 定义 `ToolResource`。
- 定义 `ResourceKind`。
- 定义 `ResourceValidationError`。
- 每个资源至少包含：
  - id
  - name
  - kind
  - path
  - validation status

## Checklist

- [x] 创建 `AgentMac/ResourceLibrary/` 目录。
- [x] 定义 knowledge 资源模型。
- [x] 定义 skill 资源模型。
- [x] 定义 tool 资源模型。
- [x] 定义资源校验错误。
- [x] 实现 knowledge 列表。
- [x] 实现 knowledge 创建。
- [x] 实现 knowledge 读取和保存。
- [x] 实现 knowledge 改名保存。
- [x] 实现 knowledge 删除。
- [x] 实现 skill 列表。
- [x] 实现 skill 创建。
- [x] 实现已有 skill 目录导入。
- [x] 实现 skill 删除。
- [x] 实现 `SKILL.md` 读取和保存。
- [x] 实现 skill 最小结构校验。
- [x] 实现 tool 列表。
- [x] 实现 tool 创建。
- [x] 实现 tool 删除。
- [x] 实现 `tool.yaml` 读取和保存。
- [x] 实现 tool 入口文件读取和保存。
- [x] 实现 tool 最小结构校验。
- [x] 编写 ResourceLibrary 单元测试。

## 验收标准

- `library/knowledge/example.md` 能被识别为 knowledge。
- `.DS_Store` 和隐藏文件不会被识别为 knowledge。
- 可以创建新的 knowledge Markdown 文件并保存内容。
- 可以修改 knowledge 名称，保存后旧文件被新文件替换且内容保留。
- 可以删除已有 knowledge 文件，删除后列表不再返回该 knowledge。
- 包含 `SKILL.md` 的目录能被识别为有效 skill。
- 缺少 `SKILL.md` 的 skill 目录会返回校验错误。
- 可以创建新的 skill 目录和初始 `SKILL.md`。
- 可以导入已有 skill 目录，导入后共享库中包含原目录的 `SKILL.md` 和子目录内容。
- 可以删除已有 skill 目录，删除后列表不再返回该 skill。
- 修改 `SKILL.md` 的 `name` 后，skill 列表展示名会随保存后的内容更新。
- 包含 `tool.yaml` 且入口文件存在的目录能被识别为有效 tool。
- 缺少 `tool.yaml` 的 tool 目录会返回校验错误。
- `tool.yaml.entry` 指向的入口文件不存在时会返回校验错误。
- 可以创建新的 tool 目录、`tool.yaml` 和默认入口文件。
- 可以删除已有 tool 目录，删除后列表不再返回该 tool。
- 所有资源列表返回稳定排序。

## 第一版不做

- 不执行 tools。
- 不做完整 `SKILL.md` frontmatter 校验。
- 不做 tool schema 深度校验。
- 不做资源版本管理。
- 不做资源标签和搜索。
