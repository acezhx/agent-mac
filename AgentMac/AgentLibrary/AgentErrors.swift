import Foundation

/// Agent 校验发现的问题。
nonisolated enum AgentValidationError: Error, Equatable {
    /// Agent ID 不满足项目 ID 规则。
    case invalidAgentID(id: String)

    /// Agent 目录不存在。
    case missingAgentDirectory(agentID: String)

    /// `agent.yaml` 不存在。
    case missingManifest(agentID: String)

    /// `agent.yaml` 内容无法解析为有效 manifest。
    case invalidManifest(agentID: String, reason: String)

    /// manifest 中的 ID 与目录 ID 不一致。
    case manifestIDMismatch(directoryID: String, manifestID: String)

    /// Agent 展示名称为空。
    case emptyAgentName(agentID: String)

    /// 模型提供方为空。
    case emptyModelProvider(agentID: String)

    /// 模型名称为空。
    case emptyModelName(agentID: String)

    /// system prompt 路径不是合法的 Agent 私有相对路径。
    case invalidSystemPromptPath(agentID: String, path: String, reason: String)

    /// system prompt 文件不存在。
    case missingSystemPrompt(agentID: String, path: String)

    /// 资源引用路径非法。
    case invalidResourcePath(agentID: String, kind: ResourceKind, path: String, reason: String)

    /// knowledge 文件不存在。
    case missingKnowledgeFile(agentID: String, path: String)

    /// skill 目录不存在。
    case missingSkillDirectory(agentID: String, path: String)

    /// skill 目录缺少 `SKILL.md`。
    case missingSkillManifest(agentID: String, path: String)

    /// tool 目录不存在。
    case missingToolDirectory(agentID: String, path: String)

    /// tool 目录缺少 `tool.yaml`。
    case missingToolManifest(agentID: String, path: String)

    /// `tool.yaml` 缺少顶层 `entry` 字段。
    case missingToolEntry(agentID: String, path: String)

    /// `tool.yaml.entry` 不是合法的 tool 目录内相对路径。
    case invalidToolEntry(agentID: String, path: String, entry: String, reason: String)

    /// `tool.yaml.entry` 指向的入口文件不存在。
    case missingToolEntryFile(agentID: String, path: String, entry: String)

    /// 权限字段不是 `allow`、`ask` 或 `deny`。
    case invalidPermission(agentID: String, field: String, value: String)
}

extension AgentValidationError: LocalizedError {
    /// 面向日志和测试诊断的错误描述。
    var errorDescription: String? {
        switch self {
        case let .invalidAgentID(id):
            "Invalid agent id: \(id)"
        case let .missingAgentDirectory(agentID):
            "Missing agent directory: \(agentID)"
        case let .missingManifest(agentID):
            "Missing agent.yaml for agent: \(agentID)"
        case let .invalidManifest(agentID, reason):
            "Invalid agent.yaml for agent \(agentID): \(reason)"
        case let .manifestIDMismatch(directoryID, manifestID):
            "Agent id mismatch: directory \(directoryID), manifest \(manifestID)"
        case let .emptyAgentName(agentID):
            "Agent name cannot be empty: \(agentID)"
        case let .emptyModelProvider(agentID):
            "Model provider cannot be empty: \(agentID)"
        case let .emptyModelName(agentID):
            "Model name cannot be empty: \(agentID)"
        case let .invalidSystemPromptPath(agentID, path, reason):
            "Invalid system prompt path '\(path)' for agent \(agentID): \(reason)"
        case let .missingSystemPrompt(agentID, path):
            "Missing system prompt '\(path)' for agent: \(agentID)"
        case let .invalidResourcePath(agentID, kind, path, reason):
            "Invalid \(kind.rawValue) path '\(path)' for agent \(agentID): \(reason)"
        case let .missingKnowledgeFile(agentID, path):
            "Missing knowledge file '\(path)' for agent: \(agentID)"
        case let .missingSkillDirectory(agentID, path):
            "Missing skill directory '\(path)' for agent: \(agentID)"
        case let .missingSkillManifest(agentID, path):
            "Missing SKILL.md in skill '\(path)' for agent: \(agentID)"
        case let .missingToolDirectory(agentID, path):
            "Missing tool directory '\(path)' for agent: \(agentID)"
        case let .missingToolManifest(agentID, path):
            "Missing tool.yaml in tool '\(path)' for agent: \(agentID)"
        case let .missingToolEntry(agentID, path):
            "Missing tool entry in '\(path)' for agent: \(agentID)"
        case let .invalidToolEntry(agentID, path, entry, reason):
            "Invalid tool entry '\(entry)' in '\(path)' for agent \(agentID): \(reason)"
        case let .missingToolEntryFile(agentID, path, entry):
            "Missing tool entry file '\(entry)' in '\(path)' for agent: \(agentID)"
        case let .invalidPermission(agentID, field, value):
            "Invalid permission '\(field): \(value)' for agent: \(agentID)"
        }
    }
}

/// Agent 校验结果。
nonisolated struct AgentValidationStatus: Equatable {
    /// 校验发现的问题。
    let errors: [AgentValidationError]

    /// 是否通过校验。
    var isValid: Bool {
        errors.isEmpty
    }

    /// 创建校验结果。
    ///
    /// - Parameter errors: 校验发现的问题，默认为空。
    init(errors: [AgentValidationError] = []) {
        self.errors = errors
    }
}

/// AgentLibrary 服务级错误。
nonisolated enum AgentLibraryError: Error, Equatable {
    /// 创建 Agent 时目标 ID 已存在。
    case duplicateAgentID(id: String)

    /// 生成运行时配置前校验失败。
    case validationFailed(agentID: String, errors: [AgentValidationError])
}

extension AgentLibraryError: LocalizedError {
    /// 面向日志和测试诊断的错误描述。
    var errorDescription: String? {
        switch self {
        case let .duplicateAgentID(id):
            "Agent already exists: \(id)"
        case let .validationFailed(agentID, errors):
            "Agent validation failed for \(agentID): \(errors.map { $0.localizedDescription }.joined(separator: "; "))"
        }
    }
}

