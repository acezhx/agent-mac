import ComposableArchitecture
import Foundation

/// Agent 管理页面 Feature。
///
/// 该 Feature 只管理 Agent 列表、创建表单和编辑表单的 UI 状态。Agent 文件读写通过
/// `AppAgentClient` 注入，底层 `AgentLibrary` 不依赖 TCA。
@Reducer
struct AgentFeature {
    /// Agent 管理页面状态。
    @ObservableState
    struct State: Equatable {
        /// Agent 摘要列表。
        var agents: [AgentSummary]

        /// 当前选中的 Agent ID。
        var selectedAgentID: String?

        /// 当前加载到编辑区的 Agent。
        var selectedAgent: Agent?

        /// 创建表单中的 Agent ID。
        var newAgentID: String

        /// 创建表单中的 Agent 展示名称。
        var newAgentName: String

        /// 编辑表单中的 Agent 展示名称。
        var editorName: String

        /// 编辑表单中的模型提供方。
        var editorModelProvider: String

        /// 编辑表单中的模型名称。
        var editorModelName: String

        /// 编辑表单中的 system prompt。
        var editorSystemPrompt: String

        /// 最近一次操作错误。
        var errorMessage: String?

        /// 是否正在加载列表。
        var isLoadingList: Bool

        /// 是否正在加载选中 Agent。
        var isLoadingAgent: Bool

        /// 是否正在创建 Agent。
        var isCreatingAgent: Bool

        /// 是否正在保存 Agent。
        var isSavingAgent: Bool

        /// 创建 Agent 管理页面状态。
        init() {
            self.agents = []
            self.selectedAgentID = nil
            self.selectedAgent = nil
            self.newAgentID = ""
            self.newAgentName = ""
            self.editorName = ""
            self.editorModelProvider = ""
            self.editorModelName = ""
            self.editorSystemPrompt = ""
            self.errorMessage = nil
            self.isLoadingList = false
            self.isLoadingAgent = false
            self.isCreatingAgent = false
            self.isSavingAgent = false
        }

        /// 是否有 Agent 操作正在运行。
        var hasOperationInFlight: Bool {
            isLoadingList || isLoadingAgent || isCreatingAgent || isSavingAgent
        }

        /// 是否可以创建 Agent。
        var canCreateAgent: Bool {
            !hasOperationInFlight
                && !newAgentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !newAgentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// 是否可以保存当前 Agent。
        var canSaveAgent: Bool {
            selectedAgent != nil
                && !hasOperationInFlight
                && !editorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !editorModelProvider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !editorModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// 当前编辑区标题。
        var editorTitle: String {
            guard let selectedAgent else {
                return "No Agent"
            }

            let name = editorName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? selectedAgent.id : name
        }

        /// 清空编辑区。
        mutating func clearEditor() {
            selectedAgent = nil
            editorName = ""
            editorModelProvider = ""
            editorModelName = ""
            editorSystemPrompt = ""
        }

        /// 用 Agent 填充编辑区。
        ///
        /// - Parameter agent: 已加载或已保存的 Agent。
        mutating func populateEditor(with agent: Agent) {
            selectedAgent = agent
            selectedAgentID = agent.id
            editorName = agent.manifest.name
            editorModelProvider = agent.manifest.model.provider
            editorModelName = agent.manifest.model.name
            editorSystemPrompt = agent.systemPrompt
        }

        /// 生成可保存的 Agent 编辑模型。
        ///
        /// - Returns: 当前编辑区对应的 Agent；没有选中 Agent 时返回 `nil`。
        func editedAgent() -> Agent? {
            guard var agent = selectedAgent else {
                return nil
            }

            agent.manifest.name = editorName
            agent.manifest.model = ModelConfig(
                provider: editorModelProvider,
                name: editorModelName
            )
            agent.systemPrompt = editorSystemPrompt
            return agent
        }

        /// 插入或替换 Agent 摘要，并按 ID 稳定排序。
        ///
        /// - Parameter summary: 要同步到列表中的 Agent 摘要。
        mutating func upsertSummary(_ summary: AgentSummary) {
            agents.removeAll { $0.id == summary.id }
            agents.append(summary)
            agents.sort { $0.id < $1.id }
        }
    }

    /// Agent 管理页面 action。
    enum Action: Equatable {
        /// 页面进入时加载 Agent 列表。
        case task

        /// 用户点击刷新列表。
        case refreshButtonTapped

        /// Agent 列表加载成功。
        case loadAgentsSucceeded([AgentSummary])

        /// Agent 列表加载失败。
        case loadAgentsFailed(AppAgentClientError)

        /// 用户选择 Agent。
        case agentSelected(String?)

        /// Agent 加载成功。
        case loadAgentSucceeded(Agent)

        /// Agent 加载失败。
        case loadAgentFailed(AppAgentClientError)

        /// 创建表单 Agent ID 变化。
        case newAgentIDChanged(String)

        /// 创建表单 Agent 展示名称变化。
        case newAgentNameChanged(String)

        /// 用户点击创建 Agent。
        case createAgentButtonTapped

        /// Agent 创建成功。
        case createAgentSucceeded(Agent)

        /// Agent 创建失败。
        case createAgentFailed(AppAgentClientError)

        /// 编辑表单 Agent 展示名称变化。
        case editorNameChanged(String)

        /// 编辑表单模型提供方变化。
        case editorModelProviderChanged(String)

        /// 编辑表单模型名称变化。
        case editorModelNameChanged(String)

        /// 编辑表单 system prompt 变化。
        case editorSystemPromptChanged(String)

        /// 用户点击保存 Agent。
        case saveAgentButtonTapped

        /// Agent 保存成功。
        case saveAgentSucceeded(Agent)

        /// Agent 保存失败。
        case saveAgentFailed(AppAgentClientError)
    }

    private nonisolated enum CancelID: Hashable {
        case list
        case selectedAgent
    }

    /// Agent 管理页面 reducer。
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task, .refreshButtonTapped:
                state.isLoadingList = true
                state.errorMessage = nil
                return loadAgentsEffect()

            case let .loadAgentsSucceeded(agents):
                state.isLoadingList = false
                state.agents = agents
                if let selectedAgentID = state.selectedAgentID,
                   !agents.contains(where: { $0.id == selectedAgentID }) {
                    state.selectedAgentID = nil
                    state.clearEditor()
                }
                return .none

            case let .loadAgentsFailed(error):
                state.isLoadingList = false
                state.errorMessage = error.message
                return .none

            case let .agentSelected(id):
                state.selectedAgentID = id
                state.errorMessage = nil
                guard let id else {
                    state.isLoadingAgent = false
                    state.clearEditor()
                    return .cancel(id: CancelID.selectedAgent)
                }

                state.isLoadingAgent = true
                state.clearEditor()
                state.selectedAgentID = id
                return loadAgentEffect(id: id)

            case let .loadAgentSucceeded(agent):
                state.isLoadingAgent = false
                state.populateEditor(with: agent)
                return .none

            case let .loadAgentFailed(error):
                state.isLoadingAgent = false
                state.errorMessage = error.message
                return .none

            case let .newAgentIDChanged(id):
                state.newAgentID = id
                return .none

            case let .newAgentNameChanged(name):
                state.newAgentName = name
                return .none

            case .createAgentButtonTapped:
                guard state.canCreateAgent else {
                    return .none
                }
                state.isCreatingAgent = true
                state.errorMessage = nil
                let id = state.newAgentID.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = state.newAgentName.trimmingCharacters(in: .whitespacesAndNewlines)
                @Dependency(AppAgentClient.self) var appAgentClient
                return .run { send in
                    do {
                        let agent = try await appAgentClient.createAgent(id, name)
                        await send(.createAgentSucceeded(agent))
                    } catch {
                        await send(.createAgentFailed(AppAgentClientError(error)))
                    }
                }

            case let .createAgentSucceeded(agent):
                state.isCreatingAgent = false
                state.newAgentID = ""
                state.newAgentName = ""
                state.upsertSummary(agent.summary)
                state.populateEditor(with: agent)
                state.errorMessage = nil
                return .none

            case let .createAgentFailed(error):
                state.isCreatingAgent = false
                state.errorMessage = error.message
                return .none

            case let .editorNameChanged(name):
                state.editorName = name
                return .none

            case let .editorModelProviderChanged(provider):
                state.editorModelProvider = provider
                return .none

            case let .editorModelNameChanged(name):
                state.editorModelName = name
                return .none

            case let .editorSystemPromptChanged(systemPrompt):
                state.editorSystemPrompt = systemPrompt
                return .none

            case .saveAgentButtonTapped:
                guard state.canSaveAgent, let agent = state.editedAgent() else {
                    return .none
                }
                state.isSavingAgent = true
                state.errorMessage = nil
                @Dependency(AppAgentClient.self) var appAgentClient
                return .run { send in
                    do {
                        let savedAgent = try await appAgentClient.saveAgent(agent)
                        await send(.saveAgentSucceeded(savedAgent))
                    } catch {
                        await send(.saveAgentFailed(AppAgentClientError(error)))
                    }
                }

            case let .saveAgentSucceeded(agent):
                state.isSavingAgent = false
                state.upsertSummary(agent.summary)
                state.populateEditor(with: agent)
                state.errorMessage = nil
                return .none

            case let .saveAgentFailed(error):
                state.isSavingAgent = false
                state.errorMessage = error.message
                return .none
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
        .cancellable(id: CancelID.list, cancelInFlight: true)
    }

    private func loadAgentEffect(id: String) -> Effect<Action> {
        @Dependency(AppAgentClient.self) var appAgentClient
        return .run { send in
            do {
                let agent = try await appAgentClient.loadAgent(id)
                await send(.loadAgentSucceeded(agent))
            } catch {
                await send(.loadAgentFailed(AppAgentClientError(error)))
            }
        }
        .cancellable(id: CancelID.selectedAgent, cancelInFlight: true)
    }
}
