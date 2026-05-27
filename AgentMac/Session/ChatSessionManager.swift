import Foundation

/// Session 模块解析 Agent 运行配置所需的边界。
///
/// `AgentLibrary` 已经实现同签名方法，Session 管理层通过该协议依赖已校验的
/// `ResolvedAgentConfig`，不直接读取或解析 Agent manifest。
nonisolated protocol SessionAgentConfigResolving {
    /// 生成运行时需要的 Agent 配置。
    ///
    /// - Parameters:
    ///   - id: Agent ID。
    ///   - workspaceDirectory: 会话工作区目录。
    /// - Returns: 已校验并解析成绝对路径的 Agent 配置。
    func resolvedAgentConfig(for id: String, workspaceDirectory: URL) throws -> ResolvedAgentConfig
}

extension AgentLibrary: SessionAgentConfigResolving {}

/// ChatSession 管理层。
///
/// 该类型负责创建、缓存、恢复、列出和删除 session。它不接 UI，不实现审批流程，也不绕过
/// `ChatSession` 直接操作 Runtime。
nonisolated final class ChatSessionManager: @unchecked Sendable {
    /// 已加载的 session 实例。
    private var sessions: [UUID: ChatSession]

    private let fileStore: FileStore
    private let sessionStore: SessionStore
    private let agentConfigResolver: any SessionAgentConfigResolving
    private let runtimeBridge: any SessionRuntimeBridging
    private let approvalHandler: any ToolApprovalHandling
    private let idProvider: () -> UUID
    private let messageIDProvider: () -> UUID
    private let dateProvider: () -> Date

    /// 创建 ChatSession 管理层。
    ///
    /// - Parameters:
    ///   - fileStore: Application Support 文件服务。
    ///   - agentConfigResolver: Agent 运行配置解析边界。
    ///   - runtimeBridge: Runtime Host 桥接层。
    ///   - approvalHandler: 工具审批处理器，默认使用第一阶段拒绝策略。
    ///   - idProvider: session id 生成器。
    ///   - messageIDProvider: message id 生成器。
    ///   - dateProvider: 时间生成器。
    init(
        fileStore: FileStore,
        agentConfigResolver: any SessionAgentConfigResolving,
        runtimeBridge: any SessionRuntimeBridging,
        approvalHandler: any ToolApprovalHandling = DefaultToolApprovalHandler(),
        idProvider: @escaping () -> UUID = { UUID() },
        messageIDProvider: @escaping () -> UUID = { UUID() },
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        self.sessions = [:]
        self.fileStore = fileStore
        self.sessionStore = SessionStore(fileStore: fileStore)
        self.agentConfigResolver = agentConfigResolver
        self.runtimeBridge = runtimeBridge
        self.approvalHandler = approvalHandler
        self.idProvider = idProvider
        self.messageIDProvider = messageIDProvider
        self.dateProvider = dateProvider
    }

    /// 基于 Agent ID 和 workspace 创建新的 ChatSession。
    ///
    /// - Parameters:
    ///   - agentID: Agent ID。
    ///   - workspaceDirectory: 会话工作区目录。
    /// - Returns: 新建并已写入初始 record 的 ChatSession。
    /// - Throws: Agent 配置解析或 session record 写入失败。
    func createSession(agentID: String, workspaceDirectory: URL) throws -> ChatSession {
        let agentConfig = try agentConfigResolver.resolvedAgentConfig(
            for: agentID,
            workspaceDirectory: workspaceDirectory
        )
        return try createSession(agentConfig: agentConfig)
    }

    /// 基于已解析 Agent 配置创建新的 ChatSession。
    ///
    /// - Parameter agentConfig: 已校验并解析成绝对路径的 Agent 配置。
    /// - Returns: 新建并已写入初始 record 的 ChatSession。
    /// - Throws: session record 写入失败。
    func createSession(agentConfig: ResolvedAgentConfig) throws -> ChatSession {
        let session = ChatSession(
            agentConfig: agentConfig,
            fileStore: fileStore,
            runtimeBridge: runtimeBridge,
            approvalHandler: approvalHandler,
            id: idProvider(),
            idProvider: messageIDProvider,
            dateProvider: dateProvider
        )
        try session.persist()
        sessions[session.id] = session
        return session
    }

    /// 加载并恢复指定 ChatSession。
    ///
    /// 恢复时会基于 record 中的 Agent ID 和 workspace 重新解析 `ResolvedAgentConfig`。旧的 Runtime
    /// session id 不会重新附着；如果磁盘状态仍是 running，会恢复为 failed。
    ///
    /// - Parameter id: 本地 session id。
    /// - Returns: 已恢复并缓存的 ChatSession。
    /// - Throws: record 读取、Agent 配置解析或恢复后 record 写入失败。
    func loadSession(id: UUID) throws -> ChatSession {
        if let session = sessions[id] {
            return session
        }

        let record = try sessionStore.load(id: id)
        let workspaceDirectory = URL(fileURLWithPath: record.workspacePath, isDirectory: true)
        let agentConfig = try agentConfigResolver.resolvedAgentConfig(
            for: record.agentID,
            workspaceDirectory: workspaceDirectory
        )
        let session = ChatSession(
            restoring: record,
            agentConfig: agentConfig,
            fileStore: fileStore,
            runtimeBridge: runtimeBridge,
            approvalHandler: approvalHandler,
            idProvider: messageIDProvider,
            dateProvider: dateProvider
        )
        try session.persist()
        sessions[id] = session
        return session
    }

    /// 返回已加载的 ChatSession。
    ///
    /// - Parameter id: 本地 session id。
    /// - Returns: 已加载实例；未加载时返回 nil。
    func cachedSession(id: UUID) -> ChatSession? {
        sessions[id]
    }

    /// 加载 session 摘要列表。
    ///
    /// - Returns: session 摘要列表。
    /// - Throws: 目录扫描、读取或解码失败。
    func listSessionSummaries() throws -> [ChatSessionSummary] {
        try sessionStore.listSummaries()
    }

    /// 删除指定 session。
    ///
    /// 删除只移除本地缓存和磁盘 record；若该 session 仍有运行中的 Runtime，需要调用方先执行
    /// `ChatSession.abort()`。
    ///
    /// - Parameter id: 本地 session id。
    /// - Throws: 文件不存在或删除失败。
    func deleteSession(id: UUID) throws {
        try sessionStore.delete(id: id)
        sessions[id] = nil
    }
}
