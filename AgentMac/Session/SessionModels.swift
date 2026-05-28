import Foundation

/// Session 当前生命周期状态。
nonisolated enum SessionState: Equatable, Sendable {
    /// 尚未运行，或上一轮 assistant 输出已经完成。
    case idle

    /// Runtime session 已启动，或当前正在处理一轮用户消息。
    case running

    /// Runtime、持久化或协议处理失败。
    case failed(SessionError)

    /// 用户已中断当前 runtime session。
    case aborted

    /// 用于持久化 session record 的稳定状态名。
    var persistenceName: String {
        switch self {
        case .idle:
            "idle"
        case .running:
            "running"
        case .failed:
            "failed"
        case .aborted:
            "aborted"
        }
    }
}

/// Session 模块对上层暴露的结构化错误。
nonisolated enum SessionError: Error, Equatable, Sendable {
    /// 发送消息或中断前尚未取得 Runtime Host session id。
    case runtimeSessionMissing

    /// 从磁盘恢复时发现旧 runtime session 已不可重新附着。
    case runtimeSessionDetached

    /// Runtime session 已经启动，不能重复启动。
    case runtimeSessionAlreadyStarted(sessionId: String)

    /// 当前已有一轮用户消息正在等待 Runtime Host 完成。
    case messageAlreadyInFlight

    /// 当前状态需要先 reset，不能直接执行新的生命周期操作。
    case sessionRequiresReset(state: String)

    /// Runtime Host 返回 error event。
    case runtimeFailed(code: String, message: String, recoverable: Bool)

    /// RuntimeBridge 进程或协议调用失败。
    case bridgeFailed(message: String)

    /// 旧记录或严格协议处理中的未知 Runtime Host 事件。
    case unexpectedRuntimeEvent(name: String)

    /// session record 读写失败。
    case persistenceFailed(path: String, reason: String)
}

extension SessionError: LocalizedError {
    /// 面向日志和 UI 诊断的错误描述。
    var errorDescription: String? {
        switch self {
        case .runtimeSessionMissing:
            "Runtime session has not been started."
        case .runtimeSessionDetached:
            "Runtime session was not attached after restore."
        case let .runtimeSessionAlreadyStarted(sessionId):
            "Runtime session is already started: \(sessionId)"
        case .messageAlreadyInFlight:
            "A user message is already in flight."
        case let .sessionRequiresReset(state):
            "Session in state '\(state)' must be reset before this operation."
        case let .runtimeFailed(code, message, _):
            "Runtime failed with \(code): \(message)"
        case let .bridgeFailed(message):
            "Runtime bridge failed: \(message)"
        case let .unexpectedRuntimeEvent(name):
            "Unexpected runtime event: \(name)"
        case let .persistenceFailed(path, reason):
            "Failed to persist session record '\(path)': \(reason)"
        }
    }
}

/// Chat 消息模型。
nonisolated struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    /// Chat 消息角色。
    nonisolated enum Role: String, Codable, Equatable, Sendable {
        /// 用户输入。
        case user

        /// assistant 回复。
        case assistant

        /// Session 生成的错误或诊断信息。
        case diagnostic
    }

    /// 本地消息 id。
    let id: UUID

    /// 消息角色。
    let role: Role

    /// 消息文本内容。
    var content: String

    /// 消息创建时间。
    let createdAt: Date

    /// assistant 消息是否仍在接收流式 delta。
    var isStreaming: Bool

    /// 创建 Chat 消息。
    ///
    /// - Parameters:
    ///   - id: 本地消息 id。
    ///   - role: 消息角色。
    ///   - content: 消息文本内容。
    ///   - createdAt: 消息创建时间。
    ///   - isStreaming: assistant 消息是否仍在接收流式 delta。
    init(
        id: UUID,
        role: Role,
        content: String,
        createdAt: Date,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.isStreaming = isStreaming
    }
}

/// ChatSession 可被上层 Feature 观察的值类型快照。
nonisolated struct ChatSessionSnapshot: Equatable, Sendable {
    /// 本地 session id。
    let id: UUID

    /// Runtime Host session id。
    let runtimeSessionID: String?

    /// 当前生命周期状态。
    let state: SessionState

    /// 当前消息列表。
    let messages: [ChatMessage]

    /// 当前等待用户确认的工具审批请求。
    let pendingToolApprovalRequest: ToolApprovalRequest?

    /// 最近更新时间。
    let updatedAt: Date
}
