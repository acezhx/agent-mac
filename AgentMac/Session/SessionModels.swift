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

    /// 最近更新时间。
    let updatedAt: Date
}

/// 临时工具审批请求边界类型。
///
/// 完整 Approval 模块实现前，该类型只用于让 Session 能识别审批请求并应用默认拒绝策略。
nonisolated struct ToolApprovalRequest: Equatable, Sendable {
    /// Runtime Host 工具调用 id。
    let toolCallID: String

    /// 工具名称。
    let toolName: String

    /// Runtime Host 上报的风险类别。
    let risk: String?

    /// 工具调用摘要。
    let summary: String?

    /// 工具调用诊断详情。
    let details: RuntimeJSONValue?

    /// 从 Runtime Host event 解析工具审批请求。
    ///
    /// - Parameter event: Runtime Host event。
    init?(event: RuntimeEvent) {
        guard event.name == "toolApprovalRequested", let payload = event.payload else {
            return nil
        }

        self.toolCallID = payload["toolCallId"]?.stringValue ?? event.id
        self.toolName = payload["toolName"]?.stringValue ?? "unknown"
        self.risk = payload["risk"]?.stringValue
        self.summary = payload["summary"]?.stringValue
        self.details = payload["details"]
    }
}

/// 临时工具审批决策。
nonisolated enum ToolApprovalDecision: Codable, Equatable, Sendable {
    /// 明确拒绝工具请求。
    case denied(reason: String)

    /// 当前阶段不支持完整审批流程。
    case unsupported(reason: String)

    /// 决策原因。
    var reason: String {
        switch self {
        case let .denied(reason), let .unsupported(reason):
            reason
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case reason
    }

    /// 从稳定 JSON 结构解码工具审批决策。
    ///
    /// - Parameter decoder: JSON decoder。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let reason = try container.decode(String.self, forKey: .reason)

        switch type {
        case "denied":
            self = .denied(reason: reason)
        case "unsupported":
            self = .unsupported(reason: reason)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown tool approval decision type: \(type)."
            )
        }
    }

    /// 编码为稳定 JSON 结构。
    ///
    /// - Parameter encoder: JSON encoder。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .denied(reason):
            try container.encode("denied", forKey: .type)
            try container.encode(reason, forKey: .reason)
        case let .unsupported(reason):
            try container.encode("unsupported", forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }
}

/// 工具审批处理边界。
///
/// 第一阶段使用默认拒绝实现；后续 Approval 模块可以替换该协议实现。
nonisolated protocol ToolApprovalHandling {
    /// 处理工具审批请求。
    ///
    /// - Parameter request: Runtime Host 上报的工具审批请求。
    /// - Returns: 审批决策。
    func handle(_ request: ToolApprovalRequest) -> ToolApprovalDecision
}

/// 第一阶段工具审批默认处理器。
nonisolated struct DefaultToolApprovalHandler: ToolApprovalHandling {
    /// 创建默认拒绝处理器。
    init() {}

    /// 默认返回 unsupported，避免未实现的审批流程导致 Session 崩溃。
    ///
    /// - Parameter request: Runtime Host 上报的工具审批请求。
    /// - Returns: unsupported 决策。
    func handle(_ request: ToolApprovalRequest) -> ToolApprovalDecision {
        .unsupported(reason: "Tool approval is not supported yet.")
    }
}
