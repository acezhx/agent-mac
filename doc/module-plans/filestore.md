# FileStore 模块开发计划

## 模块目标

`FileStore` 是 Swift 侧唯一理解 Application Support 磁盘布局的模块。它提供稳定、可测试、
可复用的文件读写能力，供 `ResourceLibrary`、`AgentLibrary`、`Session` 等上层模块使用。

## 依赖关系

```text
FileStore
  -> no project modules
```

`FileStore` 不依赖其他项目模块，也不理解 Pi、SwiftUI、Agent 业务语义。

## 需要开发的功能

### 数据目录管理

- 获取 AgentMac 的 Application Support 根目录。
- 支持测试环境传入自定义根目录。
- 初始化基础目录：
  - `agents/`
  - `library/`
  - `library/knowledge/`
  - `library/skills/`
  - `library/tools/`
  - `sessions/`
- 初始化 `settings.yaml`，如果文件不存在则创建默认文件。

### 文件读写

- 读取 UTF-8 文本文件。
- 写入 UTF-8 文本文件。
- 覆盖写入文件。
- 创建父目录。
- 检查文件是否存在。
- 检查路径是文件还是目录。

### YAML 读写

- 提供 YAML 文件读取入口。
- 提供 YAML 文件写入入口。
- 第一版可以先使用轻量封装，具体 YAML 编解码由调用方提供。

### 目录扫描

- 列出指定目录下的一级子目录。
- 列出指定目录下指定扩展名文件。
- 过滤隐藏文件和 `.DS_Store`。
- 返回稳定排序结果。

### 安全路径解析

- 将相对路径解析到 app 数据根目录下。
- 拒绝路径逃逸，例如 `../` 指向根目录之外。
- 拒绝空路径和非法路径。
- 提供清晰错误信息。

### 错误类型

- 定义 `FileStoreError`。
- 覆盖：
  - 路径非法。
  - 文件不存在。
  - 目录不存在。
  - 读失败。
  - 写失败。
  - YAML 读写失败。

## Checklist

- [x] 创建 `AgentMac/FileStore/` 目录。
- [x] 定义 `AppDataLayout`。
- [x] 定义 `FileStoreError`。
- [x] 实现 Application Support 根目录解析。
- [x] 实现测试用 root path 注入。
- [x] 实现初始化目录结构。
- [x] 实现 `settings.yaml` 默认创建。
- [x] 实现文本读取。
- [x] 实现文本写入。
- [x] 实现文件存在检查。
- [x] 实现目录存在检查。
- [x] 实现一级子目录扫描。
- [x] 实现指定扩展名文件扫描。
- [x] 实现隐藏文件过滤。
- [x] 实现安全路径解析。
- [x] 编写 FileStore 单元测试。

## 验收标准

- 在临时目录中调用初始化后，会创建完整数据目录结构。
- 重复初始化不会破坏已有文件。
- 可以读写 UTF-8 文本文件。
- 写文件时能自动创建父目录。
- 扫描 `agents/` 时能返回稳定排序的 Agent 目录列表。
- 扫描 `library/knowledge/` 时能过滤 `.DS_Store` 和隐藏文件。
- 传入 `../../outside.txt` 这类越界路径时返回错误。
- 缺失文件读取会返回可诊断错误。
- 单元测试可以在不依赖真实 Application Support 的情况下运行。

## 第一版不做

- 不做数据库。
- 不做文件版本管理。
- 不做文件监听。
- 不做 iCloud 同步。
- 不做并发写冲突处理。
