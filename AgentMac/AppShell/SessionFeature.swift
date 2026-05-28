import ComposableArchitecture
import Foundation

/// 固定 Pi coding agent 会话页面 Feature。
///
/// 该 Feature 只管理 UI 状态和 effect 编排。会话创建、RuntimeHost 启动、消息发送和快照订阅都通过
/// `AppSessionClient` 注入，底层服务不依赖 TCA。
@Reducer
struct SessionFeature {
    /// 会话页面状态。
    @ObservableState
    struct State: Equatable {
        /// 当前 workspace 路径输入。
        var workspacePath: String

        /// 当前 session 快照。
        var snapshot: ChatSessionSnapshot?

        /// 消息输入框内容。
        var messageText: String

        /// 最近一次操作错误。
        var errorMessage: String?

        /// 是否正在创建 session。
        var isCreatingSession: Bool

        /// 是否正在启动 Runtime session。
        var isStartingSession: Bool

        /// 是否正在发送消息。
        var isSendingMessage: Bool

        /// 是否正在中断 session。
        var isAbortingSession: Bool

        /// 是否正在重置 session。
        var isResettingSession: Bool

        /// 是否正在提交工具审批决策。
        var isResolvingToolApproval: Bool

        /// 已由 UI 提交、但快照尚未清空的工具调用 id。
        var submittedToolApprovalIDs: Set<String>

        /// 创建会话页面状态。
        ///
        /// - Parameter workspacePath: 默认 workspace 路径。
        init(workspacePath: String = "") {
            self.workspacePath = workspacePath
            self.snapshot = nil
            self.messageText = ""
            self.errorMessage = nil
            self.isCreatingSession = false
            self.isStartingSession = false
            self.isSendingMessage = false
            self.isAbortingSession = false
            self.isResettingSession = false
            self.isResolvingToolApproval = false
            self.submittedToolApprovalIDs = []
        }

        /// 当前消息列表。
        var messages: [ChatMessage] {
            snapshot?.messages ?? []
        }

        /// 是否有会话相关操作正在运行。
        var hasOperationInFlight: Bool {
            isCreatingSession
                || isStartingSession
                || isSendingMessage
                || isAbortingSession
                || isResettingSession
                || isResolvingToolApproval
        }

        /// 当前等待用户确认的工具审批请求。
        var pendingToolApprovalRequest: ToolApprovalRequest? {
            snapshot?.pendingToolApprovalRequest
        }

        /// 是否可以创建新的本地 session。
        var canCreateSession: Bool {
            snapshot == nil && !hasOperationInFlight
        }

        /// 是否可以启动 Runtime session。
        var canStartSession: Bool {
            guard let snapshot, snapshot.runtimeSessionID == nil, !hasOperationInFlight else {
                return false
            }

            switch snapshot.state {
            case .idle:
                return true
            case .running, .failed, .aborted:
                return false
            }
        }

        /// 是否可以发送用户消息。
        var canSendMessage: Bool {
            guard let snapshot, snapshot.runtimeSessionID != nil, !hasOperationInFlight else {
                return false
            }
            guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }

            switch snapshot.state {
            case .idle, .running:
                return true
            case .failed, .aborted:
                return false
            }
        }

        /// 是否可以中断当前 Runtime session。
        var canAbortSession: Bool {
            guard let snapshot, snapshot.runtimeSessionID != nil, !hasOperationInFlight else {
                return false
            }

            switch snapshot.state {
            case .idle, .running:
                return true
            case .failed, .aborted:
                return false
            }
        }

        /// 是否可以重置当前本地 session。
        var canResetSession: Bool {
            snapshot != nil && !hasOperationInFlight
        }

        /// 状态标题。
        var statusTitle: String {
            if isCreatingSession {
                return "Creating"
            }
            if isStartingSession {
                return "Starting"
            }
            if pendingToolApprovalRequest != nil {
                return "Awaiting Approval"
            }
            if isSendingMessage {
                return "Streaming"
            }
            if isAbortingSession {
                return "Aborting"
            }
            if isResettingSession {
                return "Resetting"
            }
            guard let snapshot else {
                return "No Session"
            }

            switch snapshot.state {
            case .idle:
                return snapshot.runtimeSessionID == nil ? "Ready" : "Idle"
            case .running:
                return "Running"
            case .failed:
                return "Failed"
            case .aborted:
                return "Aborted"
            }
        }

        /// 状态详情。
        var statusDetail: String {
            guard let snapshot else {
                return "Create a fixed coding agent session to begin."
            }

            if let pendingToolApprovalRequest {
                return "\(pendingToolApprovalRequest.toolName): \(pendingToolApprovalRequest.summary)"
            }

            switch snapshot.state {
            case .idle:
                return snapshot.runtimeSessionID == nil
                    ? "Local session is ready. Start Runtime Host before sending a message."
                    : "Runtime session is ready for the next message."
            case .running:
                return snapshot.runtimeSessionID == nil
                    ? "Starting Runtime Host session."
                    : "Runtime session is active."
            case let .failed(error):
                return error.localizedDescription
            case .aborted:
                return "Runtime session was aborted. Reset before starting again."
            }
        }
    }

    /// 会话页面 action。
    enum Action: Equatable, Sendable {
        /// workspace 输入变化。
        case workspacePathChanged(String)

        /// 消息输入变化。
        case messageTextChanged(String)

        /// 用户点击创建 session。
        case createSessionButtonTapped

        /// 创建 session 成功。
        case createSessionSucceeded(ChatSessionSnapshot)

        /// 创建 session 失败。
        case createSessionFailed(AppSessionClientError)

        /// 用户点击启动 Runtime session。
        case startSessionButtonTapped

        /// 启动 Runtime session 成功。
        case startSessionSucceeded

        /// 启动 Runtime session 失败。
        case startSessionFailed(AppSessionClientError)

        /// 用户点击发送消息。
        case sendMessageButtonTapped

        /// 发送消息成功。
        case sendMessageSucceeded

        /// 发送消息失败。
        case sendMessageFailed(AppSessionClientError)

        /// 用户点击中断 session。
        case abortSessionButtonTapped

        /// 中断 session 成功。
        case abortSessionSucceeded

        /// 中断 session 失败。
        case abortSessionFailed(AppSessionClientError)

        /// 用户点击重置 session。
        case resetSessionButtonTapped

        /// 重置 session 成功。
        case resetSessionSucceeded

        /// 重置 session 失败。
        case resetSessionFailed(AppSessionClientError)

        /// 收到 Session 快照。
        case snapshotUpdated(ChatSessionSnapshot)

        /// 快照订阅失败。
        case snapshotObservationFailed(AppSessionClientError)

        /// 用户批准工具请求。
        case allowToolApprovalButtonTapped(String)

        /// 用户拒绝工具请求。
        case denyToolApprovalButtonTapped(String)

        /// 审批弹窗关闭但没有显式提交选择。
        case toolApprovalSheetDismissed(String)

        /// 工具审批决策提交成功。
        case resolveToolApprovalSucceeded(String)

        /// 工具审批决策提交失败。
        case resolveToolApprovalFailed(AppSessionClientError)
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case snapshots
    }

    /// 会话页面 reducer。
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .workspacePathChanged(workspacePath):
                state.workspacePath = workspacePath
                return .none

            case let .messageTextChanged(messageText):
                state.messageText = messageText
                return .none

            case .createSessionButtonTapped:
                guard state.canCreateSession else {
                    return .none
                }
                state.isCreatingSession = true
                state.errorMessage = nil
                let workspacePath = state.workspacePath
                @Dependency(AppSessionClient.self) var appSessionClient
                return .run { send in
                    do {
                        let snapshot = try await appSessionClient.createSession(workspacePath)
                        await send(.createSessionSucceeded(snapshot))
                    } catch {
                        await send(.createSessionFailed(AppSessionClientError(error)))
                    }
                }

            case let .createSessionSucceeded(snapshot):
                state.isCreatingSession = false
                state.snapshot = snapshot
                state.errorMessage = nil
                return observeSnapshotsEffect()

            case let .createSessionFailed(error):
                state.isCreatingSession = false
                state.errorMessage = error.message
                return .none

            case .startSessionButtonTapped:
                guard state.canStartSession else {
                    return .none
                }
                state.isStartingSession = true
                state.errorMessage = nil
                @Dependency(AppSessionClient.self) var appSessionClient
                return .run { send in
                    do {
                        try await appSessionClient.startSession()
                        await send(.startSessionSucceeded)
                    } catch {
                        await send(.startSessionFailed(AppSessionClientError(error)))
                    }
                }

            case .startSessionSucceeded:
                state.isStartingSession = false
                return .none

            case let .startSessionFailed(error):
                state.isStartingSession = false
                state.errorMessage = error.message
                return .none

            case .sendMessageButtonTapped:
                guard state.canSendMessage else {
                    return .none
                }
                let content = state.messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                state.messageText = ""
                state.isSendingMessage = true
                state.errorMessage = nil
                @Dependency(AppSessionClient.self) var appSessionClient
                return .run { send in
                    do {
                        try await appSessionClient.sendMessage(content)
                        await send(.sendMessageSucceeded)
                    } catch {
                        await send(.sendMessageFailed(AppSessionClientError(error)))
                    }
                }

            case .sendMessageSucceeded:
                state.isSendingMessage = false
                return .none

            case let .sendMessageFailed(error):
                state.isSendingMessage = false
                state.errorMessage = error.message
                return .none

            case .abortSessionButtonTapped:
                guard state.canAbortSession else {
                    return .none
                }
                state.isAbortingSession = true
                state.errorMessage = nil
                @Dependency(AppSessionClient.self) var appSessionClient
                return .run { send in
                    do {
                        try await appSessionClient.abortSession()
                        await send(.abortSessionSucceeded)
                    } catch {
                        await send(.abortSessionFailed(AppSessionClientError(error)))
                    }
                }

            case .abortSessionSucceeded:
                state.isAbortingSession = false
                return .none

            case let .abortSessionFailed(error):
                state.isAbortingSession = false
                state.errorMessage = error.message
                return .none

            case .resetSessionButtonTapped:
                guard state.canResetSession else {
                    return .none
                }
                state.isResettingSession = true
                state.errorMessage = nil
                @Dependency(AppSessionClient.self) var appSessionClient
                return .run { send in
                    do {
                        try await appSessionClient.resetSession()
                        await send(.resetSessionSucceeded)
                    } catch {
                        await send(.resetSessionFailed(AppSessionClientError(error)))
                    }
                }

            case .resetSessionSucceeded:
                state.isResettingSession = false
                return .none

            case let .resetSessionFailed(error):
                state.isResettingSession = false
                state.errorMessage = error.message
                return .none

            case let .snapshotUpdated(snapshot):
                state.snapshot = snapshot
                if snapshot.pendingToolApprovalRequest == nil {
                    state.submittedToolApprovalIDs.removeAll()
                    state.isResolvingToolApproval = false
                }
                if case let .failed(error) = snapshot.state {
                    state.errorMessage = error.localizedDescription
                }
                return .none

            case let .snapshotObservationFailed(error):
                state.errorMessage = error.message
                return .none

            case let .allowToolApprovalButtonTapped(toolCallID):
                return resolveToolApproval(
                    state: &state,
                    toolCallID: toolCallID,
                    decision: .allowed(reason: "Approved by user.")
                )

            case let .denyToolApprovalButtonTapped(toolCallID):
                return resolveToolApproval(
                    state: &state,
                    toolCallID: toolCallID,
                    decision: .denied(reason: "Denied by user.")
                )

            case let .toolApprovalSheetDismissed(toolCallID):
                guard !state.submittedToolApprovalIDs.contains(toolCallID) else {
                    return .none
                }
                return resolveToolApproval(
                    state: &state,
                    toolCallID: toolCallID,
                    decision: .denied(reason: "Approval UI was dismissed.")
                )

            case let .resolveToolApprovalSucceeded(toolCallID):
                state.isResolvingToolApproval = false
                state.submittedToolApprovalIDs.insert(toolCallID)
                return .none

            case let .resolveToolApprovalFailed(error):
                state.isResolvingToolApproval = false
                state.errorMessage = error.message
                return .none
            }
        }
    }

    private func resolveToolApproval(
        state: inout State,
        toolCallID: String,
        decision: ToolApprovalDecision
    ) -> Effect<Action> {
        guard state.pendingToolApprovalRequest?.toolCallID == toolCallID,
              !state.isResolvingToolApproval,
              !state.submittedToolApprovalIDs.contains(toolCallID)
        else {
            return .none
        }

        state.isResolvingToolApproval = true
        state.errorMessage = nil
        @Dependency(AppSessionClient.self) var appSessionClient
        return .run { send in
            do {
                try await appSessionClient.resolveToolApproval(toolCallID, decision)
                await send(.resolveToolApprovalSucceeded(toolCallID))
            } catch {
                await send(.resolveToolApprovalFailed(AppSessionClientError(error)))
            }
        }
    }

    private func observeSnapshotsEffect() -> Effect<Action> {
        @Dependency(AppSessionClient.self) var appSessionClient
        return .run { send in
            do {
                let snapshots = try await appSessionClient.snapshots()
                for await snapshot in snapshots {
                    await send(.snapshotUpdated(snapshot))
                }
            } catch {
                await send(.snapshotObservationFailed(AppSessionClientError(error)))
            }
        }
        .cancellable(id: CancelID.snapshots, cancelInFlight: true)
    }
}
