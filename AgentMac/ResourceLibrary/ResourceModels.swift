import Foundation

/// 共享资源的类型。
///
/// `ResourceLibrary` 第一版只维护 knowledge、skill 和 tool 三类文件型资源。
nonisolated enum ResourceKind: String, Equatable {
    /// Markdown 或纯文本 knowledge 文件。
    case knowledge

    /// 符合 Agent Skills 目录约定的 skill 目录。
    case skill

    /// 包含 `tool.yaml` 和入口文件的 tool 目录。
    case tool
}

/// 资源最小结构校验失败的原因。
///
/// 这些错误描述 ResourceLibrary 负责的本地文件结构问题，不包含 Agent 组合、
/// Runtime 执行或 UI 展示规则。
nonisolated enum ResourceValidationError: Error, Equatable {
    /// knowledge 文件名为空、隐藏、包含路径分隔符或包含非法字符。
    case invalidKnowledgeFileName(fileName: String, reason: String)

    /// knowledge 文件扩展名不是第一版支持的 `.md` 或 `.txt`。
    case unsupportedKnowledgeFileExtension(fileName: String)

    /// knowledge 改名时目标文件名已经存在。
    case duplicateKnowledgeFileName(fileName: String)

    /// skill 或 tool 的目录名不满足资源 ID 规则。
    case invalidResourceID(kind: ResourceKind, id: String)

    /// 指定的资源目录不存在。
    case missingResourceDirectory(kind: ResourceKind, id: String)

    /// skill 目录缺少 `SKILL.md`。
    case missingSkillManifest(skillID: String)

    /// tool 创建时传入了空展示名称。
    case emptyToolName(toolID: String)

    /// tool 目录缺少 `tool.yaml`。
    case missingToolManifest(toolID: String)

    /// skill 导入源目录不满足最小结构要求。
    case invalidSkillImportSource(path: String, reason: String)

    /// `tool.yaml` 缺少顶层 `entry` 字段，或该字段为空。
    case missingToolEntry(toolID: String)

    /// `tool.yaml.entry` 不是位于当前 tool 目录内的合法相对路径。
    case invalidToolEntry(toolID: String, entry: String, reason: String)

    /// `tool.yaml.entry` 指向的入口文件不存在。
    case missingToolEntryFile(toolID: String, entry: String)
}

nonisolated extension ResourceValidationError: LocalizedError {
    /// 面向日志和测试诊断的错误描述。
    var errorDescription: String? {
        switch self {
        case let .invalidKnowledgeFileName(fileName, reason):
            "Invalid knowledge file name '\(fileName)': \(reason)"
        case let .unsupportedKnowledgeFileExtension(fileName):
            "Unsupported knowledge file extension: \(fileName)"
        case let .duplicateKnowledgeFileName(fileName):
            "Knowledge file already exists: \(fileName)"
        case let .invalidResourceID(kind, id):
            "Invalid \(kind.rawValue) resource id: \(id)"
        case let .missingResourceDirectory(kind, id):
            "Missing \(kind.rawValue) resource directory: \(id)"
        case let .missingSkillManifest(skillID):
            "Missing SKILL.md for skill: \(skillID)"
        case let .emptyToolName(toolID):
            "Tool name cannot be empty: \(toolID)"
        case let .missingToolManifest(toolID):
            "Missing tool.yaml for tool: \(toolID)"
        case let .invalidSkillImportSource(path, reason):
            "Invalid skill import source '\(path)': \(reason)"
        case let .missingToolEntry(toolID):
            "Missing tool.yaml entry for tool: \(toolID)"
        case let .invalidToolEntry(toolID, entry, reason):
            "Invalid tool entry '\(entry)' for tool \(toolID): \(reason)"
        case let .missingToolEntryFile(toolID, entry):
            "Missing tool entry file '\(entry)' for tool: \(toolID)"
        }
    }
}

/// 资源结构校验结果。
///
/// `errors` 为空表示资源满足 ResourceLibrary 第一版的最小结构约束。
nonisolated struct ResourceValidationStatus: Equatable {
    /// 校验发现的结构问题。
    let errors: [ResourceValidationError]

    /// 资源是否通过最小结构校验。
    var isValid: Bool {
        errors.isEmpty
    }

    /// 创建一个校验结果。
    ///
    /// - Parameter errors: 校验发现的结构问题，默认为空。
    init(errors: [ResourceValidationError] = []) {
        self.errors = errors
    }
}

/// 共享 knowledge 文件的资源描述。
nonisolated struct KnowledgeResource: Equatable, Identifiable {
    /// knowledge ID，使用完整文件名，避免同名不同扩展名的文件互相冲突。
    let id: String

    /// UI 可展示名称，第一版来自文件名去掉扩展名后的部分。
    let name: String

    /// 资源类型。
    var kind: ResourceKind { .knowledge }

    /// 相对于 app data 根目录的文件路径。
    let path: String

    /// knowledge 文件的结构校验结果。
    let validation: ResourceValidationStatus
}

/// 共享 skill 目录的资源描述。
nonisolated struct SkillResource: Equatable, Identifiable {
    /// skill ID，来自 `library/skills/<skill-id>` 目录名。
    let id: String

    /// UI 可展示名称，优先来自 `SKILL.md` frontmatter 的 `name` 字段，缺失时回退到 `id`。
    let name: String

    /// 资源类型。
    var kind: ResourceKind { .skill }

    /// 相对于 app data 根目录的目录路径。
    let path: String

    /// skill 目录的最小结构校验结果。
    let validation: ResourceValidationStatus
}

/// 共享 tool 目录的资源描述。
nonisolated struct ToolResource: Equatable, Identifiable {
    /// tool ID，来自 `library/tools/<tool-id>` 目录名。
    let id: String

    /// UI 可展示名称，优先来自 `tool.yaml` 的顶层 `name` 字段。
    let name: String

    /// 资源类型。
    var kind: ResourceKind { .tool }

    /// 相对于 app data 根目录的目录路径。
    let path: String

    /// `tool.yaml` 中声明的入口文件路径；缺失或无法读取时为 `nil`。
    let entry: String?

    /// tool 目录的最小结构校验结果。
    let validation: ResourceValidationStatus
}
