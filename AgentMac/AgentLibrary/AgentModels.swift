import Foundation

/// Agent 权限策略。
///
/// 该值只表示 `agent.yaml` 中保存的用户意图。运行时由 `ApprovalService` 和 `Session`
/// 解释为自动批准、请求用户确认或拒绝。
nonisolated enum PermissionDecision: String, Equatable, CaseIterable {
    /// 允许对应类型的请求。
    case allow

    /// 请求执行前需要用户确认。
    case ask

    /// 拒绝对应类型的请求。
    case deny
}

/// Agent 使用的模型配置。
nonisolated struct ModelConfig: Equatable, Sendable {
    /// 第一版创建 Agent 时使用的默认模型配置。
    static let `default` = ModelConfig(provider: "openai", name: "gpt-5-codex")

    /// 模型提供方，例如 `openai`。
    var provider: String

    /// 模型名称，例如 `gpt-5-codex`。
    var name: String

    /// 创建模型配置。
    ///
    /// - Parameters:
    ///   - provider: 模型提供方。
    ///   - name: 模型名称。
    init(provider: String, name: String) {
        self.provider = provider
        self.name = name
    }
}

/// Agent 保存的权限配置。
nonisolated struct PermissionConfig: Equatable {
    /// 第一版 Agent 的默认权限配置。
    static let `default` = PermissionConfig()

    /// shell 命令权限策略。
    var bash: PermissionDecision

    /// 文件编辑权限策略。
    var edit: PermissionDecision

    /// 网络访问权限策略。
    var network: PermissionDecision

    /// 创建权限配置。
    ///
    /// - Parameters:
    ///   - bash: shell 命令权限策略。
    ///   - edit: 文件编辑权限策略。
    ///   - network: 网络访问权限策略。
    init(
        bash: PermissionDecision = .ask,
        edit: PermissionDecision = .ask,
        network: PermissionDecision = .ask
    ) {
        self.bash = bash
        self.edit = edit
        self.network = network
    }
}

/// `agent.yaml` 的领域模型。
///
/// 该结构保存持久化配置中的相对路径。运行时需要的绝对路径由
/// `AgentLibrary.resolvedAgentConfig(for:workspaceDirectory:)` 生成，不写回 `agent.yaml`。
nonisolated struct AgentManifest: Equatable, Identifiable {
    /// Agent ID，必须与 `agents/<id>/` 目录名一致。
    var id: String

    /// UI 展示名称。
    var name: String

    /// 模型配置。
    var model: ModelConfig

    /// Agent 私有 system prompt 文件路径，相对于 Agent 目录。
    var systemPrompt: String

    /// 已选择的 knowledge 文件路径列表，相对于 Agent 目录。
    var knowledge: [String]

    /// 已选择的 skill 目录路径列表，相对于 Agent 目录。
    var skills: [String]

    /// 已选择的 tool 目录路径列表，相对于 Agent 目录。
    var tools: [String]

    /// Agent 保存的权限配置。
    var permissions: PermissionConfig

    /// 创建 Agent manifest。
    ///
    /// - Parameters:
    ///   - id: Agent ID。
    ///   - name: UI 展示名称。
    ///   - model: 模型配置。
    ///   - systemPrompt: system prompt 文件路径，相对于 Agent 目录。
    ///   - knowledge: knowledge 文件路径列表，相对于 Agent 目录。
    ///   - skills: skill 目录路径列表，相对于 Agent 目录。
    ///   - tools: tool 目录路径列表，相对于 Agent 目录。
    ///   - permissions: 权限配置。
    init(
        id: String,
        name: String,
        model: ModelConfig = .default,
        systemPrompt: String = "system.md",
        knowledge: [String] = [],
        skills: [String] = [],
        tools: [String] = [],
        permissions: PermissionConfig = .default
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.systemPrompt = systemPrompt
        self.knowledge = knowledge
        self.skills = skills
        self.tools = tools
        self.permissions = permissions
    }
}

/// Agent 列表页需要的摘要信息。
nonisolated struct AgentSummary: Equatable, Identifiable, Sendable {
    /// Agent ID。
    let id: String

    /// UI 展示名称。
    let name: String

    /// 模型配置。
    let model: ModelConfig
}

/// Agent 编辑模型。
///
/// 该结构把 `agent.yaml` manifest 与私有 `system.md` 文本组合在一起，供后续 UI 或服务层保存。
nonisolated struct Agent: Equatable, Identifiable {
    /// Agent 所属目录 ID。
    ///
    /// 该值在加载或创建 Agent 时确定。保存时 `manifest.id` 必须与它一致，避免编辑模型通过修改
    /// manifest ID 隐式写入另一个 Agent 目录。
    let id: String

    /// 持久化 manifest。
    var manifest: AgentManifest

    /// Agent 私有 system prompt 文本。
    var systemPrompt: String

    /// Agent 列表摘要。
    var summary: AgentSummary {
        AgentSummary(id: id, name: manifest.name, model: manifest.model)
    }

    /// 创建 Agent 编辑模型。
    ///
    /// - Parameters:
    ///   - manifest: 持久化 manifest。
    ///   - systemPrompt: Agent 私有 system prompt 文本。
    init(manifest: AgentManifest, systemPrompt: String) {
        self.id = manifest.id
        self.manifest = manifest
        self.systemPrompt = systemPrompt
    }

    /// 创建绑定到指定目录 ID 的 Agent 编辑模型。
    ///
    /// - Parameters:
    ///   - id: Agent 所属目录 ID。
    ///   - manifest: 持久化 manifest。
    ///   - systemPrompt: Agent 私有 system prompt 文本。
    init(id: String, manifest: AgentManifest, systemPrompt: String) {
        self.id = id
        self.manifest = manifest
        self.systemPrompt = systemPrompt
    }
}

/// Runtime Host 启动 Agent session 时使用的 Agent 形态。
nonisolated enum AgentRuntimeMode: String, Equatable {
    /// 使用 Pi 内置 coding agent 配置，只允许 AgentMac 额外传入显式选择的 skills。
    case fixedCodingAgent

    /// 使用 AgentLibrary 已解析的自定义 Agent 配置。
    case resolved
}

/// Runtime 启动会话前使用的 Agent 配置。
///
/// 所有文件路径都是绝对路径。该结构是运行时临时结构，不应写回 `agent.yaml`。
nonisolated struct ResolvedAgentConfig: Equatable {
    /// Runtime Host 启动 session 时采用的 Agent 形态。
    let runtimeMode: AgentRuntimeMode

    /// Agent ID。
    let id: String

    /// Agent 展示名称。
    let name: String

    /// 模型配置。
    let model: ModelConfig

    /// system prompt 文件绝对路径。
    let systemPromptPath: String

    /// knowledge 文件绝对路径列表。
    let knowledgePaths: [String]

    /// skill 目录绝对路径列表。
    let skillPaths: [String]

    /// tool 目录绝对路径列表。
    let toolPaths: [String]

    /// Agent 权限配置。
    let permissions: PermissionConfig

    /// 会话工作区绝对路径。
    let workspacePath: String

    /// 创建运行时 Agent 配置。
    ///
    /// - Parameters:
    ///   - runtimeMode: Runtime Host 启动 session 时采用的 Agent 形态。
    ///   - id: Agent ID。
    ///   - name: Agent 展示名称。
    ///   - model: 模型配置。
    ///   - systemPromptPath: system prompt 文件绝对路径。
    ///   - knowledgePaths: knowledge 文件绝对路径列表。
    ///   - skillPaths: skill 目录绝对路径列表。
    ///   - toolPaths: tool 目录绝对路径列表。
    ///   - permissions: Agent 权限配置。
    ///   - workspacePath: 会话工作区绝对路径。
    init(
        runtimeMode: AgentRuntimeMode = .resolved,
        id: String,
        name: String,
        model: ModelConfig,
        systemPromptPath: String,
        knowledgePaths: [String],
        skillPaths: [String],
        toolPaths: [String],
        permissions: PermissionConfig,
        workspacePath: String
    ) {
        self.runtimeMode = runtimeMode
        self.id = id
        self.name = name
        self.model = model
        self.systemPromptPath = systemPromptPath
        self.knowledgePaths = knowledgePaths
        self.skillPaths = skillPaths
        self.toolPaths = toolPaths
        self.permissions = permissions
        self.workspacePath = workspacePath
    }
}
