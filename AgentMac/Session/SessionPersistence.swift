import Foundation

/// Session 错误的稳定磁盘结构。
///
/// `SessionError` 是运行时领域错误；该结构只负责把错误写入 JSON，并在恢复时还原成可展示、
/// 可比较的 `SessionError`。
nonisolated struct ChatSessionErrorRecord: Codable, Equatable, Sendable {
    /// 错误类型。
    let type: String

    /// Runtime 错误码或辅助错误码。
    let code: String?

    /// 面向诊断的错误文本。
    let message: String

    /// Runtime 错误是否可恢复。
    let recoverable: Bool?

    /// 持久化错误涉及的 app data 相对路径。
    let path: String?

    /// 持久化错误的底层原因。
    let reason: String?

    /// 未识别 Runtime event 的名称。
    let eventName: String?

    /// 从领域错误创建磁盘结构。
    ///
    /// - Parameter error: Session 领域错误。
    init(error: SessionError) {
        switch error {
        case .runtimeSessionMissing:
            self.type = "runtimeSessionMissing"
            self.code = nil
            self.message = error.localizedDescription
            self.recoverable = nil
            self.path = nil
            self.reason = nil
            self.eventName = nil
        case .runtimeSessionDetached:
            self.type = "runtimeSessionDetached"
            self.code = nil
            self.message = error.localizedDescription
            self.recoverable = nil
            self.path = nil
            self.reason = nil
            self.eventName = nil
        case let .runtimeSessionAlreadyStarted(sessionId):
            self.type = "runtimeSessionAlreadyStarted"
            self.code = sessionId
            self.message = error.localizedDescription
            self.recoverable = nil
            self.path = nil
            self.reason = nil
            self.eventName = nil
        case .messageAlreadyInFlight:
            self.type = "messageAlreadyInFlight"
            self.code = nil
            self.message = error.localizedDescription
            self.recoverable = nil
            self.path = nil
            self.reason = nil
            self.eventName = nil
        case let .sessionRequiresReset(state):
            self.type = "sessionRequiresReset"
            self.code = state
            self.message = error.localizedDescription
            self.recoverable = nil
            self.path = nil
            self.reason = nil
            self.eventName = nil
        case let .runtimeFailed(code, message, recoverable):
            self.type = "runtimeFailed"
            self.code = code
            self.message = message
            self.recoverable = recoverable
            self.path = nil
            self.reason = nil
            self.eventName = nil
        case let .bridgeFailed(message):
            self.type = "bridgeFailed"
            self.code = nil
            self.message = message
            self.recoverable = nil
            self.path = nil
            self.reason = nil
            self.eventName = nil
        case let .unexpectedRuntimeEvent(name):
            self.type = "unexpectedRuntimeEvent"
            self.code = nil
            self.message = error.localizedDescription
            self.recoverable = nil
            self.path = nil
            self.reason = nil
            self.eventName = name
        case let .persistenceFailed(path, reason):
            self.type = "persistenceFailed"
            self.code = nil
            self.message = error.localizedDescription
            self.recoverable = nil
            self.path = path
            self.reason = reason
            self.eventName = nil
        }
    }

    /// 恢复为 Session 领域错误。
    var sessionError: SessionError {
        switch type {
        case "runtimeSessionMissing":
            .runtimeSessionMissing
        case "runtimeSessionDetached":
            .runtimeSessionDetached
        case "runtimeSessionAlreadyStarted":
            .runtimeSessionAlreadyStarted(sessionId: code ?? "unknown")
        case "messageAlreadyInFlight":
            .messageAlreadyInFlight
        case "sessionRequiresReset":
            .sessionRequiresReset(state: code ?? "unknown")
        case "runtimeFailed":
            .runtimeFailed(code: code ?? "runtime_failed", message: message, recoverable: recoverable ?? false)
        case "unexpectedRuntimeEvent":
            .unexpectedRuntimeEvent(name: eventName ?? "unknown")
        case "persistenceFailed":
            .persistenceFailed(path: path ?? "sessions", reason: reason ?? message)
        case "bridgeFailed":
            .bridgeFailed(message: message)
        default:
            .bridgeFailed(message: message)
        }
    }
}

/// 完整 ChatSession 磁盘记录。
///
/// 该结构是 `sessions/<session-id>.json` 的稳定 schema，保存恢复 session 需要的本地状态和完整
/// 消息历史。它不承诺保存或恢复 Runtime Host 进程内状态。
nonisolated struct ChatSessionRecord: Codable, Equatable, Identifiable, Sendable {
    /// 当前 JSON schema 版本。
    static let currentSchemaVersion = 1

    /// 本地 session id。
    let id: UUID

    /// Schema 版本。
    let schemaVersion: Int

    /// Runtime Host session id，仅用于诊断；冷启动恢复时不会重新附着。
    let runtimeSessionID: String?

    /// Agent ID。
    let agentID: String

    /// Agent 展示名称。
    let agentName: String

    /// 会话工作区绝对路径。
    let workspacePath: String

    /// 持久化状态名。
    let state: String

    /// 结构化错误。
    let error: ChatSessionErrorRecord?

    /// 面向列表或诊断的错误文本。
    let errorMessage: String?

    /// 创建时间。
    let createdAt: Date

    /// 最近更新时间。
    let updatedAt: Date

    /// 消息数量摘要。
    let messageCount: Int

    /// 完整消息历史。
    let messages: [ChatMessage]

    /// 已作出的工具审批决策。
    let toolApprovals: [ToolApprovalDecision]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case runtimeSessionID
        case agentID
        case agentName
        case workspacePath
        case state
        case error
        case errorMessage
        case createdAt
        case updatedAt
        case messageCount
        case messages
        case toolApprovals
    }

    /// 创建完整 session 磁盘记录。
    ///
    /// - Parameters:
    ///   - id: 本地 session id。
    ///   - runtimeSessionID: Runtime Host session id。
    ///   - agentID: Agent ID。
    ///   - agentName: Agent 展示名称。
    ///   - workspacePath: 会话工作区绝对路径。
    ///   - state: 当前 session 状态。
    ///   - createdAt: 创建时间。
    ///   - updatedAt: 最近更新时间。
    ///   - messages: 完整消息历史。
    ///   - toolApprovals: 工具审批决策。
    init(
        id: UUID,
        runtimeSessionID: String?,
        agentID: String,
        agentName: String,
        workspacePath: String,
        state: SessionState,
        createdAt: Date,
        updatedAt: Date,
        messages: [ChatMessage],
        toolApprovals: [ToolApprovalDecision]
    ) {
        self.id = id
        self.schemaVersion = Self.currentSchemaVersion
        self.runtimeSessionID = runtimeSessionID
        self.agentID = agentID
        self.agentName = agentName
        self.workspacePath = workspacePath
        self.state = state.persistenceName
        self.error = state.failureError.map(ChatSessionErrorRecord.init(error:))
        self.errorMessage = state.failureError?.localizedDescription
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messages.count
        self.messages = messages
        self.toolApprovals = toolApprovals
    }

    /// 从 JSON 解码并兼容旧的基础 session record。
    ///
    /// - Parameter decoder: JSON decoder。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let idString = try container.decode(String.self, forKey: .id)
        guard let id = UUID(uuidString: idString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Invalid session id: \(idString)."
            )
        }

        let state = try container.decode(String.self, forKey: .state)
        guard Self.validStateNames.contains(state) else {
            throw DecodingError.dataCorruptedError(
                forKey: .state,
                in: container,
                debugDescription: "Unknown session state: \(state)."
            )
        }

        let messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        let errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        let decodedError = try container.decodeIfPresent(ChatSessionErrorRecord.self, forKey: .error)

        self.id = id
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        self.runtimeSessionID = try container.decodeIfPresent(String.self, forKey: .runtimeSessionID)
        self.agentID = try container.decode(String.self, forKey: .agentID)
        self.agentName = try container.decode(String.self, forKey: .agentName)
        self.workspacePath = try container.decode(String.self, forKey: .workspacePath)
        self.state = state
        if let decodedError {
            self.error = decodedError
        } else if state == "failed", let errorMessage {
            self.error = ChatSessionErrorRecord(error: .bridgeFailed(message: errorMessage))
        } else {
            self.error = nil
        }
        self.errorMessage = errorMessage ?? self.error?.sessionError.localizedDescription
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount) ?? messages.count
        self.messages = messages
        self.toolApprovals = try container.decodeIfPresent([ToolApprovalDecision].self, forKey: .toolApprovals) ?? []
    }

    /// 编码为稳定 JSON 结构。
    ///
    /// - Parameter encoder: JSON encoder。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(runtimeSessionID, forKey: .runtimeSessionID)
        try container.encode(agentID, forKey: .agentID)
        try container.encode(agentName, forKey: .agentName)
        try container.encode(workspacePath, forKey: .workspacePath)
        try container.encode(state, forKey: .state)
        try container.encode(error, forKey: .error)
        try container.encode(errorMessage, forKey: .errorMessage)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(messageCount, forKey: .messageCount)
        try container.encode(messages, forKey: .messages)
        try container.encode(toolApprovals, forKey: .toolApprovals)
    }

    /// 按磁盘状态还原领域状态。
    var sessionState: SessionState {
        switch state {
        case "idle":
            .idle
        case "running":
            .running
        case "failed":
            .failed(error?.sessionError ?? .bridgeFailed(message: errorMessage ?? "Session failed."))
        case "aborted":
            .aborted
        default:
            .failed(.bridgeFailed(message: "Unknown persisted session state: \(state)."))
        }
    }

    private static let validStateNames: Set<String> = ["idle", "running", "failed", "aborted"]
}

/// Session 列表使用的摘要模型。
nonisolated struct ChatSessionSummary: Equatable, Identifiable, Sendable {
    /// 本地 session id。
    let id: UUID

    /// Agent ID。
    let agentID: String

    /// Agent 展示名称。
    let agentName: String

    /// 会话工作区绝对路径。
    let workspacePath: String

    /// 当前持久化状态。
    let state: SessionState

    /// 错误文本。
    let errorMessage: String?

    /// 创建时间。
    let createdAt: Date

    /// 最近更新时间。
    let updatedAt: Date

    /// 消息数量摘要。
    let messageCount: Int

    /// 从完整 record 创建摘要。
    ///
    /// - Parameter record: 完整 session 磁盘记录。
    init(record: ChatSessionRecord) {
        self.id = record.id
        self.agentID = record.agentID
        self.agentName = record.agentName
        self.workspacePath = record.workspacePath
        self.state = record.sessionState
        self.errorMessage = record.errorMessage
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.messageCount = record.messageCount
    }
}

private extension SessionState {
    /// failed 状态中的错误。
    nonisolated var failureError: SessionError? {
        if case let .failed(error) = self {
            return error
        }
        return nil
    }
}
