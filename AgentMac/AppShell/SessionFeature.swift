import ComposableArchitecture
import Foundation

/// Agent 会话工作台 Feature。
///
/// 该 Feature 只管理 UI 状态和 effect 编排。会话创建、RuntimeHost 启动、消息发送和快照订阅都通过
/// `AppSessionClient` 注入，底层服务不依赖 TCA。
@Reducer
struct SessionFeature {
    /// 会话页面状态。
    @ObservableState
    struct State: Equatable {
        /// 可用于创建会话的 Agent 摘要列表。
        var agents: [AgentSummary]

        /// 新建 session 时选择的 Agent ID。
        var selectedAgentID: String

        /// 当前 workspace 路径输入。
        var workspacePath: String

        /// 当前显示 session 创建时使用的 Agent ID。
        var currentSessionAgentID: String?

        /// 当前显示 session 创建时使用的 workspace 路径。
        var currentSessionWorkspacePath: String?

        /// 当前 session 快照。
        var snapshot: ChatSessionSnapshot?

        /// 消息输入框内容。
        var messageText: String

        /// 等待 Runtime session 启动完成后发送的首条消息。
        var pendingInitialMessage: String?

        /// 最近一次操作错误。
        var errorMessage: String?

        /// 是否正在创建 session。
        var isCreatingSession: Bool

        /// 是否已经加载过 Agent 列表。
        var hasLoadedAgents: Bool

        /// 是否正在加载 Agent 列表。
        var isLoadingAgents: Bool

        /// 是否正在启动 Runtime session。
        var isStartingSession: Bool

        /// 是否正在发送消息。
        var isSendingMessage: Bool

        /// 是否正在取消当前这一轮消息。
        var isCancellingTurn: Bool

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
            self.agents = []
            self.selectedAgentID = DefaultCodingAgentTemplate.id
            self.workspacePath = workspacePath
            self.currentSessionAgentID = nil
            self.currentSessionWorkspacePath = nil
            self.snapshot = nil
            self.messageText = ""
            self.pendingInitialMessage = nil
            self.errorMessage = nil
            self.isCreatingSession = false
            self.hasLoadedAgents = false
            self.isLoadingAgents = false
            self.isStartingSession = false
            self.isSendingMessage = false
            self.isCancellingTurn = false
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
                || isLoadingAgents
                || isStartingSession
                || isSendingMessage
                || isCancellingTurn
                || isAbortingSession
                || isResettingSession
                || isResolvingToolApproval
        }

        /// 当前等待用户确认的工具审批请求。
        var pendingToolApprovalRequest: ToolApprovalRequest? {
            snapshot?.pendingToolApprovalRequest
        }

        /// Agent Picker 展示的稳定选项。
        var agentPickerOptions: [AgentSummary] {
            var options = agents
            if !options.contains(where: { $0.id == Self.defaultAgentSummary.id }) {
                options.insert(Self.defaultAgentSummary, at: 0)
            }
            if !selectedAgentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !options.contains(where: { $0.id == selectedAgentID }) {
                options.append(
                    AgentSummary(
                        id: selectedAgentID,
                        name: "\(selectedAgentID) (unavailable)",
                        model: .default
                    )
                )
            }
            return options
        }

        /// 当前选择的 Agent 展示名。
        var selectedAgentName: String {
            agentName(for: selectedAgentID)
        }

        /// 当前显示 session 的 Agent 展示名。
        var currentSessionAgentName: String {
            agentName(for: currentSessionAgentID ?? selectedAgentID)
        }

        /// 新建 session 使用的 workspace 展示名。
        var selectedWorkspaceName: String {
            workspaceName(for: workspacePath)
        }

        /// 当前显示 session 的 workspace 展示名。
        var currentSessionWorkspaceName: String {
            workspaceName(for: currentSessionWorkspacePath ?? workspacePath)
        }

        /// 新建 session 使用的 workspace 说明。
        var selectedWorkspaceDetail: String {
            workspaceDetail(for: workspacePath)
        }

        /// 当前显示 session 的 workspace 说明。
        var currentSessionWorkspaceDetail: String {
            workspaceDetail(for: currentSessionWorkspacePath ?? workspacePath)
        }

        /// 左侧项目列表当前可展示的项目路径。
        var sidebarProjectPath: String? {
            let path = (currentSessionWorkspacePath ?? workspacePath)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        }

        /// 左侧项目列表当前可展示的项目名称。
        var sidebarProjectName: String {
            guard let sidebarProjectPath else {
                return ""
            }
            return workspaceName(for: sidebarProjectPath)
        }

        /// 左侧项目列表当前可展示的项目说明。
        var sidebarProjectDetail: String {
            sidebarProjectPath ?? ""
        }

        /// 是否正在展示 session 启动 composer。
        var isPreparingSession: Bool {
            snapshot == nil
        }

        /// 是否可以编辑新建 session 的配置。
        var canEditSessionSetup: Bool {
            snapshot == nil && !hasOperationInFlight
        }

        /// 是否可以创建新的本地 session。
        var canCreateSession: Bool {
            snapshot == nil
                && !hasOperationInFlight
                && !selectedAgentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// 是否可以通过新建 session composer 提交首条消息。
        var canSubmitInitialMessage: Bool {
            canCreateSession
                && !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// 是否可以关闭当前可见 session 并回到启动 composer。
        var canPrepareNewSession: Bool {
            guard let snapshot, !hasOperationInFlight else {
                return false
            }
            switch snapshot.state {
            case .idle, .failed, .aborted:
                return true
            case .running:
                return false
            }
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

        /// 是否可以取消当前这一轮消息。
        var canCancelCurrentTurn: Bool {
            guard snapshot?.runtimeSessionID != nil, !isCancellingTurn else {
                return false
            }
            return isSendingMessage
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
            if isCancellingTurn {
                return "Stopping"
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
                return "Select a project folder and agent for a new session."
            }

            if isStartingSession {
                return "Starting Runtime Host session."
            }
            if isAbortingSession {
                return "Stopping current run."
            }
            if isResettingSession {
                return "Resetting local session."
            }
            if let pendingToolApprovalRequest {
                return "\(pendingToolApprovalRequest.toolName): \(pendingToolApprovalRequest.summary)"
            }

            switch snapshot.state {
            case .idle:
                return snapshot.runtimeSessionID == nil
                    ? "Runtime session is not started. Create a new session to retry."
                    : "Runtime session is ready for the next message."
            case .running:
                return snapshot.runtimeSessionID == nil
                    ? "Starting Runtime Host session."
                    : "Runtime session is active."
            case let .failed(error):
                return error.localizedDescription
            case .aborted:
                return "Runtime session was stopped. Start a new session before continuing."
            }
        }

        /// 新建 session 页面标题。
        var sessionPromptTitle: String {
            let workspace = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !workspace.isEmpty else {
                return "我们该做什么?"
            }
            return "我们应该在\(selectedWorkspaceName)中做些什么?"
        }

        /// 新建 session 的 workspace 按钮标题。
        var workspacePickerTitle: String {
            let workspace = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !workspace.isEmpty else {
                return "进入项目工作"
            }
            return selectedWorkspaceName
        }

        private static let defaultAgentSummary = AgentSummary(
            id: DefaultCodingAgentTemplate.id,
            name: DefaultCodingAgentTemplate.name,
            model: .default
        )

        private func agentName(for id: String) -> String {
            if id == DefaultCodingAgentTemplate.id {
                return DefaultCodingAgentTemplate.name
            }
            return agents.first(where: { $0.id == id })?.name ?? id
        }

        private func workspaceName(for path: String) -> String {
            let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPath.isEmpty else {
                return "No Project"
            }
            let lastPathComponent = URL(fileURLWithPath: trimmedPath, isDirectory: true).lastPathComponent
            return lastPathComponent.isEmpty ? trimmedPath : lastPathComponent
        }

        private func workspaceDetail(for path: String) -> String {
            let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedPath.isEmpty ? "No project selected" : trimmedPath
        }
    }

    /// 会话页面 action。
    enum Action: Equatable, Sendable {
        /// 页面进入时加载新建 session 所需数据。
        case task

        /// 用户点击刷新 Agent 列表。
        case refreshAgentsButtonTapped

        /// Agent 列表加载成功。
        case loadAgentsSucceeded([AgentSummary])

        /// Agent 列表加载失败。
        case loadAgentsFailed(AppAgentClientError)

        /// 新建 session Agent 选择变化。
        case agentSelected(String)

        /// workspace 输入变化。
        case workspacePathChanged(String)

        /// 消息输入变化。
        case messageTextChanged(String)

        /// 用户点击创建 session。
        case createSessionButtonTapped

        /// 用户从新建 session composer 提交首条消息。
        case submitInitialMessageButtonTapped

        /// 用户从当前 session 回到启动 composer。
        case prepareNewSessionButtonTapped

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

        /// 用户点击取消当前轮消息。
        case cancelTurnButtonTapped

        /// 取消当前轮消息成功。
        case cancelTurnSucceeded

        /// 取消当前轮消息失败。
        case cancelTurnFailed(AppSessionClientError)

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
        case agents
        case snapshots
    }

    /// 会话页面 reducer。
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                guard !state.hasLoadedAgents, !state.isLoadingAgents else {
                    return .none
                }
                state.isLoadingAgents = true
                state.errorMessage = nil
                return loadAgentsEffect()

            case .refreshAgentsButtonTapped:
                state.isLoadingAgents = true
                state.errorMessage = nil
                return loadAgentsEffect()

            case let .loadAgentsSucceeded(agents):
                state.isLoadingAgents = false
                state.hasLoadedAgents = true
                state.agents = agents
                if !agents.contains(where: { $0.id == state.selectedAgentID }) {
                    if agents.contains(where: { $0.id == DefaultCodingAgentTemplate.id }) {
                        state.selectedAgentID = DefaultCodingAgentTemplate.id
                    } else if let firstAgent = agents.first {
                        state.selectedAgentID = firstAgent.id
                    } else {
                        state.selectedAgentID = DefaultCodingAgentTemplate.id
                    }
                }
                return .none

            case let .loadAgentsFailed(error):
                state.isLoadingAgents = false
                state.hasLoadedAgents = false
                state.errorMessage = error.message
                return .none

            case let .agentSelected(agentID):
                state.selectedAgentID = agentID
                return .none

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
                let workspacePath = resolvedWorkspacePathForSession(state.workspacePath)
                state.workspacePath = workspacePath
                state.isCreatingSession = true
                state.errorMessage = nil
                return createSessionEffect(
                    agentID: state.selectedAgentID,
                    workspacePath: workspacePath
                )

            case .submitInitialMessageButtonTapped:
                guard state.canSubmitInitialMessage else {
                    return .none
                }
                let workspacePath = resolvedWorkspacePathForSession(state.workspacePath)
                state.workspacePath = workspacePath
                state.pendingInitialMessage = state.messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                state.messageText = ""
                state.isCreatingSession = true
                state.errorMessage = nil
                return createSessionEffect(
                    agentID: state.selectedAgentID,
                    workspacePath: workspacePath
                )

            case .prepareNewSessionButtonTapped:
                guard state.canPrepareNewSession else {
                    return .none
                }
                state.snapshot = nil
                state.currentSessionAgentID = nil
                state.currentSessionWorkspacePath = nil
                state.messageText = ""
                state.pendingInitialMessage = nil
                state.errorMessage = nil
                state.submittedToolApprovalIDs = []
                state.isResolvingToolApproval = false
                return .cancel(id: CancelID.snapshots)

            case let .createSessionSucceeded(snapshot):
                state.isCreatingSession = false
                state.snapshot = snapshot
                state.currentSessionAgentID = state.selectedAgentID
                state.currentSessionWorkspacePath = state.workspacePath
                state.errorMessage = nil
                guard state.canStartSession else {
                    return observeSnapshotsEffect()
                }
                state.isStartingSession = true
                return .merge(
                    observeSnapshotsEffect(),
                    startSessionEffect()
                )

            case let .createSessionFailed(error):
                state.isCreatingSession = false
                if let pendingInitialMessage = state.pendingInitialMessage {
                    state.messageText = pendingInitialMessage
                    state.pendingInitialMessage = nil
                }
                state.errorMessage = error.message
                return .none

            case .startSessionButtonTapped:
                guard state.canStartSession else {
                    return .none
                }
                state.isStartingSession = true
                state.errorMessage = nil
                return startSessionEffect()

            case .startSessionSucceeded:
                state.isStartingSession = false
                return sendPendingInitialMessageIfReady(state: &state)

            case let .startSessionFailed(error):
                state.isStartingSession = false
                if let pendingInitialMessage = state.pendingInitialMessage {
                    state.messageText = pendingInitialMessage
                    state.pendingInitialMessage = nil
                }
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
                return sendMessageEffect(content)

            case .sendMessageSucceeded:
                state.isSendingMessage = false
                state.isCancellingTurn = false
                return .none

            case let .sendMessageFailed(error):
                state.isSendingMessage = false
                state.isCancellingTurn = false
                state.errorMessage = error.message
                return .none

            case .cancelTurnButtonTapped:
                guard state.canCancelCurrentTurn else {
                    return .none
                }
                state.isCancellingTurn = true
                state.errorMessage = nil
                @Dependency(AppSessionClient.self) var appSessionClient
                return .run { send in
                    do {
                        try await appSessionClient.cancelTurn()
                        await send(.cancelTurnSucceeded)
                    } catch {
                        await send(.cancelTurnFailed(AppSessionClientError(error)))
                    }
                }

            case .cancelTurnSucceeded:
                state.isCancellingTurn = false
                return .none

            case let .cancelTurnFailed(error):
                state.isCancellingTurn = false
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
                if case .idle = snapshot.state {
                    state.isCancellingTurn = false
                }
                if case let .failed(error) = snapshot.state {
                    state.errorMessage = error.localizedDescription
                }
                return sendPendingInitialMessageIfReady(state: &state)

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

    private func createSessionEffect(agentID: String, workspacePath: String) -> Effect<Action> {
        @Dependency(AppSessionClient.self) var appSessionClient
        return .run { send in
            do {
                let snapshot = try await appSessionClient.createSession(agentID, workspacePath)
                await send(.createSessionSucceeded(snapshot))
            } catch {
                await send(.createSessionFailed(AppSessionClientError(error)))
            }
        }
    }

    private func resolvedWorkspacePathForSession(_ path: String) -> String {
        AppDefaultWorkspaceDirectory.resolvedURL(from: path).path
    }

    private func sendPendingInitialMessageIfReady(state: inout State) -> Effect<Action> {
        guard let content = state.pendingInitialMessage,
              let snapshot = state.snapshot,
              snapshot.runtimeSessionID != nil,
              !state.isCreatingSession,
              !state.isStartingSession,
              !state.isSendingMessage
        else {
            return .none
        }

        switch snapshot.state {
        case .idle, .running:
            state.pendingInitialMessage = nil
            state.isSendingMessage = true
            state.errorMessage = nil
            return sendMessageEffect(content)
        case .failed, .aborted:
            state.messageText = content
            state.pendingInitialMessage = nil
            return .none
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

    private func startSessionEffect() -> Effect<Action> {
        @Dependency(AppSessionClient.self) var appSessionClient
        return .run { send in
            do {
                try await appSessionClient.startSession()
                await send(.startSessionSucceeded)
            } catch {
                await send(.startSessionFailed(AppSessionClientError(error)))
            }
        }
    }

    private func sendMessageEffect(_ content: String) -> Effect<Action> {
        @Dependency(AppSessionClient.self) var appSessionClient
        return .run { send in
            do {
                try await appSessionClient.sendMessage(content)
                await send(.sendMessageSucceeded)
            } catch {
                await send(.sendMessageFailed(AppSessionClientError(error)))
            }
        }
    }

    private func loadAgentsEffect() -> Effect<Action> {
        @Dependency(AppAgentClient.self) var appAgentClient
        return .run { send in
            do {
                let agents = try await appAgentClient.listAgents()
                await send(.loadAgentsSucceeded(agents))
            } catch {
                await send(.loadAgentsFailed(AppAgentClientError(error)))
            }
        }
        .cancellable(id: CancelID.agents, cancelInFlight: true)
    }
}
