import Foundation

/// Session 使用的 RuntimeBridge 边界。
///
/// 该协议只暴露 Session 需要的固定 coding agent session 能力，便于单元测试使用 mock，
/// 同时避免 Session 了解 RuntimeBridge 的进程管理细节。
nonisolated protocol SessionRuntimeBridging: AnyObject {
    /// 启动固定 Pi coding agent session。
    ///
    /// - Parameters:
    ///   - workspacePath: 会话工作目录。
    ///   - timeout: 等待 Runtime Host event 的秒数。
    /// - Returns: Runtime Host session id。
    func startSession(workspacePath: String?, timeout: TimeInterval) throws -> String

    /// 发送用户消息并按 Runtime Host event 更新调用方。
    ///
    /// - Parameters:
    ///   - sessionId: Runtime Host session id。
    ///   - content: 用户消息文本。
    ///   - timeout: 等待本轮消息完成的秒数。
    ///   - onEvent: 每收到一条 Runtime Host event 时调用。
    /// - Returns: 本轮 Runtime Host events。
    @discardableResult
    func sendMessage(
        sessionId: String,
        content: String,
        timeout: TimeInterval,
        onEvent: ((RuntimeEvent) throws -> Void)?
    ) throws -> [RuntimeEvent]

    /// 中断 Runtime Host session。
    ///
    /// - Parameters:
    ///   - sessionId: Runtime Host session id。
    ///   - timeout: 等待 sessionAborted 的秒数。
    /// - Returns: Runtime Host 返回的 event。
    @discardableResult
    func abortSession(sessionId: String, timeout: TimeInterval) throws -> RuntimeEvent
}

nonisolated extension RuntimeBridge: SessionRuntimeBridging {}

/// 一次 Agent 对话的生命周期编排服务。
///
/// `ChatSession` 接收已经由 `AgentLibrary` 解析和校验过的 `ResolvedAgentConfig`，但当前阶段按
/// Runtime 协议只启动 `fixedCodingAgent` session。它负责维护消息、状态、默认审批拒绝策略，
/// 并通过 `SessionStore` 保存完整 session record。
nonisolated final class ChatSession: @unchecked Sendable {
    /// 本地 session id。
    let id: UUID

    /// session record 的 app data 相对路径。
    var recordRelativePath: String {
        SessionStore.relativePath(for: id)
    }

    /// Runtime Host session id。
    private(set) var runtimeSessionID: String?

    /// 当前生命周期状态。
    private(set) var state: SessionState

    /// 当前消息列表。
    private(set) var messages: [ChatMessage]

    /// 当前工具审批决策列表。
    private(set) var toolApprovalDecisions: [ToolApprovalDecision]

    /// 当前是否已有一轮用户消息正在等待 Runtime Host 完成。
    private var isMessageInFlight: Bool

    /// 创建时间。
    let createdAt: Date

    /// 最近更新时间。
    private(set) var updatedAt: Date

    private let agentConfig: ResolvedAgentConfig
    private let sessionStore: SessionStore
    private let runtimeBridge: any SessionRuntimeBridging
    private let approvalHandler: any ToolApprovalHandling
    private let idProvider: () -> UUID
    private let dateProvider: () -> Date
    /// Session 内部诊断日志处理器。
    private let logHandler: (String) -> Void
    /// 保护快照订阅表，避免订阅取消和快照发送并发修改同一个字典。
    private let snapshotContinuationLock = NSLock()
    private var snapshotContinuations: [UUID: AsyncStream<ChatSessionSnapshot>.Continuation]

    /// 创建 ChatSession。
    ///
    /// - Parameters:
    ///   - agentConfig: 已解析的 Agent 配置。当前阶段只使用其中的 workspace 和基础元数据。
    ///   - fileStore: Application Support 文件服务。
    ///   - runtimeBridge: Runtime Host 桥接层。
    ///   - approvalHandler: 工具审批处理器，默认使用第一阶段拒绝策略。
    ///   - id: 本地 session id。
    ///   - idProvider: 消息 id 生成器。
    ///   - dateProvider: 时间生成器。
    ///   - logHandler: Session 内部诊断日志处理器。
    init(
        agentConfig: ResolvedAgentConfig,
        fileStore: FileStore,
        runtimeBridge: any SessionRuntimeBridging,
        approvalHandler: any ToolApprovalHandling = DefaultToolApprovalHandler(),
        id: UUID = UUID(),
        idProvider: @escaping () -> UUID = { UUID() },
        dateProvider: @escaping () -> Date = { Date() },
        logHandler: @escaping (String) -> Void = { message in
            NSLog("%@", message)
        }
    ) {
        let now = dateProvider()
        self.id = id
        self.runtimeSessionID = nil
        self.state = .idle
        self.messages = []
        self.toolApprovalDecisions = []
        self.isMessageInFlight = false
        self.createdAt = now
        self.updatedAt = now
        self.agentConfig = agentConfig
        self.sessionStore = SessionStore(fileStore: fileStore)
        self.runtimeBridge = runtimeBridge
        self.approvalHandler = approvalHandler
        self.idProvider = idProvider
        self.dateProvider = dateProvider
        self.logHandler = logHandler
        self.snapshotContinuations = [:]
    }

    /// 从完整 session record 恢复 ChatSession。
    ///
    /// Runtime Host 不支持重新附着旧 session，因此恢复后会清空 `runtimeSessionID`。若磁盘状态仍为
    /// running，会转为 failed 并追加一条诊断消息，避免上层误以为旧 runtime 仍在运行。
    ///
    /// - Parameters:
    ///   - record: 完整 session 磁盘记录。
    ///   - agentConfig: 当前 AgentLibrary 重新解析后的 Agent 配置。
    ///   - fileStore: Application Support 文件服务。
    ///   - runtimeBridge: Runtime Host 桥接层。
    ///   - approvalHandler: 工具审批处理器，默认使用第一阶段拒绝策略。
    ///   - idProvider: 消息 id 生成器。
    ///   - dateProvider: 时间生成器。
    ///   - logHandler: Session 内部诊断日志处理器。
    init(
        restoring record: ChatSessionRecord,
        agentConfig: ResolvedAgentConfig,
        fileStore: FileStore,
        runtimeBridge: any SessionRuntimeBridging,
        approvalHandler: any ToolApprovalHandling = DefaultToolApprovalHandler(),
        idProvider: @escaping () -> UUID = { UUID() },
        dateProvider: @escaping () -> Date = { Date() },
        logHandler: @escaping (String) -> Void = { message in
            NSLog("%@", message)
        }
    ) {
        self.id = record.id
        self.runtimeSessionID = nil
        self.agentConfig = agentConfig
        self.sessionStore = SessionStore(fileStore: fileStore)
        self.runtimeBridge = runtimeBridge
        self.approvalHandler = approvalHandler
        self.idProvider = idProvider
        self.dateProvider = dateProvider
        self.logHandler = logHandler
        self.snapshotContinuations = [:]
        self.createdAt = record.createdAt
        self.toolApprovalDecisions = record.toolApprovals
        self.isMessageInFlight = false
        self.messages = record.messages.map { message in
            var restored = message
            restored.isStreaming = false
            return restored
        }

        if record.state == "running" {
            let error = SessionError.runtimeSessionDetached
            let now = dateProvider()
            self.state = .failed(error)
            self.updatedAt = now
            self.messages.append(ChatMessage(
                id: idProvider(),
                role: .diagnostic,
                content: error.localizedDescription,
                createdAt: now
            ))
        } else {
            self.state = record.sessionState
            self.updatedAt = record.updatedAt
        }
    }

    /// 当前 session 快照。
    var snapshot: ChatSessionSnapshot {
        ChatSessionSnapshot(
            id: id,
            runtimeSessionID: runtimeSessionID,
            state: state,
            messages: messages,
            updatedAt: updatedAt
        )
    }

    /// 创建 session 快照流。
    ///
    /// TCA Feature 后续可以订阅该流，把 Session 状态变化转成 feature action。
    ///
    /// - Returns: 从当前快照开始的状态变化流。
    func snapshots() -> AsyncStream<ChatSessionSnapshot> {
        AsyncStream { continuation in
            let token = UUID()
            addSnapshotContinuation(continuation, token: token)
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                self?.removeSnapshotContinuation(token)
            }
        }
    }

    /// 启动固定 Pi coding agent session。
    ///
    /// - Throws: RuntimeBridge 或 session record 持久化失败时抛出 `SessionError`。
    func start() throws {
        try validateCanStart()

        state = .running
        touchAndEmit()

        do {
            runtimeSessionID = try runtimeBridge.startSession(
                workspacePath: agentConfig.workspacePath,
                timeout: 5
            )
            touch()
            try persistRecord()
            emitSnapshot()
        } catch {
            let sessionError = sessionError(from: error)
            fail(with: sessionError)
            throw sessionError
        }
    }

    /// 发送用户消息并合并 assistant delta。
    ///
    /// - Parameter content: 用户消息文本。
    /// - Throws: RuntimeBridge、协议处理或 session record 持久化失败时抛出 `SessionError`。
    func sendUserMessage(_ content: String) throws {
        try validateCanSendUserMessage()

        guard let runtimeSessionID else {
            let error = SessionError.runtimeSessionMissing
            fail(with: error)
            throw error
        }

        messages.append(makeMessage(role: .user, content: content))
        isMessageInFlight = true
        state = .running
        touch()

        do {
            try persistRecord()
            emitSnapshot()
            try runtimeBridge.sendMessage(
                sessionId: runtimeSessionID,
                content: content,
                timeout: 10,
                onEvent: { [self] event in
                    try handleRuntimeEvent(event)
                }
            )
        } catch {
            let sessionError = sessionError(from: error)
            fail(with: sessionError)
            throw sessionError
        }
    }

    /// 中断当前 runtime session。
    ///
    /// - Throws: RuntimeBridge 或 session record 持久化失败时抛出 `SessionError`。
    func abort() throws {
        guard let runtimeSessionID else {
            try markAborted()
            return
        }

        do {
            let event = try runtimeBridge.abortSession(sessionId: runtimeSessionID, timeout: 5)
            try handleRuntimeEvent(event)
        } catch {
            let sessionError = sessionError(from: error)
            fail(with: sessionError)
            throw sessionError
        }
    }

    /// 重置本地 session 状态。
    ///
    /// 该方法不向 Runtime Host 发送 abort；调用方需要停止 runtime 时应先调用 `abort()`。
    ///
    /// - Throws: session record 持久化失败时抛出 `SessionError.persistenceFailed`，并保留原内存状态。
    func reset() throws {
        let previousRuntimeSessionID = runtimeSessionID
        let previousState = state
        let previousMessages = messages
        let previousToolApprovalDecisions = toolApprovalDecisions
        let previousIsMessageInFlight = isMessageInFlight
        let previousUpdatedAt = updatedAt

        runtimeSessionID = nil
        state = .idle
        messages = []
        toolApprovalDecisions = []
        isMessageInFlight = false
        touch()

        do {
            try persistRecord()
        } catch {
            runtimeSessionID = previousRuntimeSessionID
            state = previousState
            messages = previousMessages
            toolApprovalDecisions = previousToolApprovalDecisions
            isMessageInFlight = previousIsMessageInFlight
            updatedAt = previousUpdatedAt
            throw error
        }

        emitSnapshot()
    }

    /// 保存当前 session record。
    ///
    /// `ChatSessionManager` 在新建或恢复 session 后使用该入口写入当前快照；运行中状态变化仍由
    /// `ChatSession` 自己在对应方法内保存。
    ///
    /// - Throws: 编码或写入失败时抛出 `SessionError.persistenceFailed`。
    func persist() throws {
        try persistRecord()
    }

    /// 应用单条 Runtime Host event。
    ///
    /// - Parameter event: Runtime Host event。
    /// - Throws: session record 持久化失败时抛出 `SessionError`。
    private func handleRuntimeEvent(_ event: RuntimeEvent) throws {
        if shouldIgnoreLateRuntimeEvent() {
            return
        }

        switch event.name {
        case "assistantDelta":
            appendAssistantDelta(event.payload?["text"]?.stringValue ?? "")
            try persistRecord()
            emitSnapshot()
        case "messageCompleted":
            finishStreamingAssistantMessage()
            isMessageInFlight = false
            state = .idle
            touch()
            try persistRecord()
            emitSnapshot()
        case "sessionAborted":
            try markAborted()
        case "toolApprovalRequested":
            handleToolApprovalRequest(event)
            try persistRecord()
            emitSnapshot()
        default:
            logUnknownRuntimeEvent(event)
            return
        }
    }

    /// 记录并忽略未知 Runtime Host event。
    ///
    /// - Parameter event: Runtime Host event。
    private func logUnknownRuntimeEvent(_ event: RuntimeEvent) {
        logHandler("Ignored unknown Runtime event '\(event.name)' for session \(id.uuidString.lowercased()).")
    }

    /// 校验是否允许启动新的 Runtime Host session。
    ///
    /// - Throws: 当前生命周期状态不允许启动时抛出 `SessionError`。
    private func validateCanStart() throws {
        switch state {
        case .failed, .aborted:
            throw SessionError.sessionRequiresReset(state: state.persistenceName)
        case .idle, .running:
            break
        }

        if let runtimeSessionID {
            throw SessionError.runtimeSessionAlreadyStarted(sessionId: runtimeSessionID)
        }

        if state == .running {
            throw SessionError.sessionRequiresReset(state: state.persistenceName)
        }
    }

    /// 校验是否允许发送新的用户消息。
    ///
    /// - Throws: 当前生命周期状态不允许发送时抛出 `SessionError`。
    private func validateCanSendUserMessage() throws {
        switch state {
        case .failed, .aborted:
            throw SessionError.sessionRequiresReset(state: state.persistenceName)
        case .idle, .running:
            break
        }

        if isMessageInFlight {
            throw SessionError.messageAlreadyInFlight
        }
    }

    /// 判断是否应忽略 abort 后迟到的 Runtime Host event。
    ///
    /// - Returns: 已进入 aborted 后返回 true，保持 aborted 为终态直到调用方 reset。
    private func shouldIgnoreLateRuntimeEvent() -> Bool {
        if state == .aborted {
            return true
        }
        return false
    }

    /// 使用默认审批策略处理工具审批请求。
    ///
    /// - Parameter event: Runtime Host event。
    private func handleToolApprovalRequest(_ event: RuntimeEvent) {
        guard let request = ToolApprovalRequest(event: event) else {
            return
        }

        let decision = approvalHandler.handle(request)
        toolApprovalDecisions.append(decision)
        messages.append(makeMessage(
            role: .diagnostic,
            content: "工具审批暂不支持，已默认拒绝：\(request.toolName)。\(decision.reason)"
        ))
        touch()
    }

    /// 追加或合并 assistant 流式文本。
    ///
    /// - Parameter text: assistant delta 文本。
    private func appendAssistantDelta(_ text: String) {
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == .assistant,
           messages[lastIndex].isStreaming {
            messages[lastIndex].content += text
        } else {
            messages.append(makeMessage(role: .assistant, content: text, isStreaming: true))
        }
        touch()
    }

    /// 结束当前 streaming assistant 消息。
    private func finishStreamingAssistantMessage() {
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == .assistant,
           messages[lastIndex].isStreaming {
            messages[lastIndex].isStreaming = false
        }
    }

    /// 标记 session 已中断。
    ///
    /// - Throws: session record 持久化失败时抛出 `SessionError`。
    private func markAborted() throws {
        finishStreamingAssistantMessage()
        runtimeSessionID = nil
        state = .aborted
        isMessageInFlight = false
        touch()
        try persistRecord()
        emitSnapshot()
    }

    /// 标记 session 失败，并尽力写入失败 record。
    ///
    /// - Parameter error: Session 错误。
    private func fail(with error: SessionError) {
        finishStreamingAssistantMessage()
        isMessageInFlight = false
        state = .failed(error)
        messages.append(makeMessage(role: .diagnostic, content: error.localizedDescription))
        touch()
        try? persistRecord()
        emitSnapshot()
    }

    /// 创建 ChatMessage。
    ///
    /// - Parameters:
    ///   - role: 消息角色。
    ///   - content: 消息文本内容。
    ///   - isStreaming: assistant 消息是否仍在接收流式 delta。
    /// - Returns: ChatMessage。
    private func makeMessage(role: ChatMessage.Role, content: String, isStreaming: Bool = false) -> ChatMessage {
        ChatMessage(
            id: idProvider(),
            role: role,
            content: content,
            createdAt: dateProvider(),
            isStreaming: isStreaming
        )
    }

    /// 更新时间并发出快照。
    private func touchAndEmit() {
        touch()
        emitSnapshot()
    }

    /// 更新时间。
    private func touch() {
        updatedAt = dateProvider()
    }

    /// 向所有订阅者发送当前快照。
    private func emitSnapshot() {
        let snapshot = snapshot
        let continuations = snapshotContinuationsSnapshot()
        for continuation in continuations {
            continuation.yield(snapshot)
        }
    }

    /// 注册一个快照订阅。
    ///
    /// - Parameters:
    ///   - continuation: `AsyncStream` continuation。
    ///   - token: 当前订阅的唯一 token。
    private func addSnapshotContinuation(
        _ continuation: AsyncStream<ChatSessionSnapshot>.Continuation,
        token: UUID
    ) {
        snapshotContinuationLock.lock()
        snapshotContinuations[token] = continuation
        snapshotContinuationLock.unlock()
    }

    /// 移除一个快照订阅。
    ///
    /// `AsyncStream` 的 termination 回调可能不在创建 stream 的调用栈上执行，因此这里必须和发送快照
    /// 共用同一把锁。
    ///
    /// - Parameter token: 当前订阅的唯一 token。
    private func removeSnapshotContinuation(_ token: UUID) {
        snapshotContinuationLock.lock()
        snapshotContinuations[token] = nil
        snapshotContinuationLock.unlock()
    }

    /// 复制当前快照订阅列表。
    ///
    /// - Returns: 可在锁外安全遍历的 continuation 列表。
    private func snapshotContinuationsSnapshot() -> [AsyncStream<ChatSessionSnapshot>.Continuation] {
        snapshotContinuationLock.lock()
        let continuations = Array(snapshotContinuations.values)
        snapshotContinuationLock.unlock()
        return continuations
    }

    /// 保存完整 session record。
    ///
    /// - Throws: 编码或写入失败时抛出 `SessionError.persistenceFailed`。
    private func persistRecord() throws {
        let record = ChatSessionRecord(
            id: id,
            runtimeSessionID: runtimeSessionID,
            agentID: agentConfig.id,
            agentName: agentConfig.name,
            workspacePath: agentConfig.workspacePath,
            state: state,
            createdAt: createdAt,
            updatedAt: updatedAt,
            messages: messages,
            toolApprovals: toolApprovalDecisions
        )

        do {
            try sessionStore.save(record)
        } catch let error as SessionError {
            throw error
        } catch {
            throw SessionError.persistenceFailed(path: recordRelativePath, reason: error.localizedDescription)
        }
    }

    /// 将底层错误映射为 SessionError。
    ///
    /// - Parameter error: 底层错误。
    /// - Returns: SessionError。
    private func sessionError(from error: Error) -> SessionError {
        if let error = error as? SessionError {
            return error
        }

        if let error = error as? RuntimeBridgeError {
            switch error {
            case let .runtimeError(code, message, recoverable, details):
                return .runtimeFailed(
                    code: code,
                    message: runtimeErrorMessage(message, details: details),
                    recoverable: recoverable
                )
            default:
                return .bridgeFailed(message: error.localizedDescription)
            }
        }

        return .bridgeFailed(message: error.localizedDescription)
    }

    /// 合并 Runtime Host error 的面向用户消息和诊断原因。
    ///
    /// - Parameters:
    ///   - message: Runtime Host 返回的稳定错误消息。
    ///   - details: Runtime Host 附带的诊断详情。
    /// - Returns: 包含具体原因的错误消息；没有原因时返回原始消息。
    private func runtimeErrorMessage(_ message: String, details: RuntimeJSONValue?) -> String {
        guard let reason = details?["reason"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reason.isEmpty,
              reason != message
        else {
            return message
        }
        return "\(message)\n\(reason)"
    }
}
