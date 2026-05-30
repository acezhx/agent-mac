import ComposableArchitecture
import Foundation

/// Agent 编辑页可选择的共享资源列表。
nonisolated struct AgentResourceOptions: Equatable, Sendable {
    /// 可选择的 knowledge 文件。
    var knowledge: [AppResourceSummary]

    /// 可选择的 skill 目录。
    var skills: [AppResourceSummary]

    /// 可选择的 tool 目录。
    var tools: [AppResourceSummary]

    /// 空资源列表。
    static let empty = AgentResourceOptions(knowledge: [], skills: [], tools: [])
}

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

        /// Agent 编辑页可选择的 knowledge 文件。
        var availableKnowledge: [AppResourceSummary]

        /// Agent 编辑页可选择的 skill 目录。
        var availableSkills: [AppResourceSummary]

        /// Agent 编辑页可选择的 tool 目录。
        var availableTools: [AppResourceSummary]

        /// Agent 允许使用的模型 provider。
        var allowedModelProviders: [String]

        /// Agent 编辑页可选择的模型清单。
        var availableModels: [AppModelSummary]

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

        /// 编辑表单中已选择的 knowledge 引用路径。
        var editorKnowledgeReferences: [String]

        /// 编辑表单中已选择的 skill 引用路径。
        var editorSkillReferences: [String]

        /// 编辑表单中已选择的 tool 引用路径。
        var editorToolReferences: [String]

        /// 最近一次操作错误。
        var errorMessage: String?

        /// 是否正在加载列表。
        var isLoadingList: Bool

        /// 是否正在加载可选资源列表。
        var isLoadingResources: Bool

        /// 是否正在加载应用设置。
        var isLoadingSettings: Bool

        /// 是否正在加载模型清单。
        var isLoadingModelCatalog: Bool

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
            self.availableKnowledge = []
            self.availableSkills = []
            self.availableTools = []
            self.allowedModelProviders = AppSettings.defaultAllowedModelProviders
            self.availableModels = []
            self.newAgentID = ""
            self.newAgentName = ""
            self.editorName = ""
            self.editorModelProvider = ""
            self.editorModelName = ""
            self.editorSystemPrompt = ""
            self.editorKnowledgeReferences = []
            self.editorSkillReferences = []
            self.editorToolReferences = []
            self.errorMessage = nil
            self.isLoadingList = false
            self.isLoadingResources = false
            self.isLoadingSettings = false
            self.isLoadingModelCatalog = false
            self.isLoadingAgent = false
            self.isCreatingAgent = false
            self.isSavingAgent = false
        }

        /// 是否有 Agent 操作正在运行。
        var hasOperationInFlight: Bool {
            isLoadingList
                || isLoadingResources
                || isLoadingSettings
                || isLoadingModelCatalog
                || isLoadingAgent
                || isCreatingAgent
                || isSavingAgent
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
                && (isEditingDefaultCodingAgent
                    || (!editorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && isEditorModelProviderAllowed
                        && !editorModelProvider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && isEditorModelNameAvailable))
        }

        /// 当前编辑区模型 provider 是否在应用设置允许列表中。
        var isEditorModelProviderAllowed: Bool {
            let provider = editorModelProvider.trimmingCharacters(in: .whitespacesAndNewlines)
            return !provider.isEmpty && allowedModelProviders.contains(provider)
        }

        /// 当前模型 provider Picker 展示的选项，包含已保存但不在 Settings 白名单中的 provider。
        var editorModelProviderPickerOptions: [String] {
            let provider = editorModelProvider.trimmingCharacters(in: .whitespacesAndNewlines)
            var options = [""]
            if !provider.isEmpty, !allowedModelProviders.contains(provider) {
                options.append(provider)
            }
            for allowedProvider in allowedModelProviders where !options.contains(allowedProvider) {
                options.append(allowedProvider)
            }
            return options
        }

        /// 当前编辑区模型名称是否存在于已加载模型清单中。
        var isEditorModelNameAvailable: Bool {
            let modelName = editorModelName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modelName.isEmpty else {
                return false
            }

            let options = editorModelOptions
            return options.isEmpty || options.contains { $0.modelID == modelName }
        }

        /// 当前 provider 下可选择的模型。
        var editorModelOptions: [AppModelSummary] {
            modelOptions(for: editorModelProvider)
        }

        /// 当前模型 Picker 展示的选项，包含已保存但已不在清单中的模型。
        var editorModelPickerOptions: [AppModelSummary] {
            let options = editorModelOptions
            let modelName = editorModelName.trimmingCharacters(in: .whitespacesAndNewlines)
            let placeholder = AppModelSummary(
                providerID: editorModelProvider,
                modelID: "",
                displayName: "Select model",
                supportsReasoning: false,
                supportedThinkingLevels: []
            )
            guard !modelName.isEmpty else {
                guard !options.isEmpty else {
                    return []
                }
                return [placeholder] + options
            }

            guard !options.contains(where: { $0.modelID == modelName }) else {
                return [placeholder] + options
            }

            return [
                placeholder,
                AppModelSummary(
                    providerID: editorModelProvider,
                    modelID: modelName,
                    displayName: "\(modelName) (unavailable)",
                    supportsReasoning: false,
                    supportedThinkingLevels: []
                ),
            ] + options
        }

        /// 当前编辑对象是否为内置 Pi coding agent。
        var isEditingDefaultCodingAgent: Bool {
            selectedAgent?.id == DefaultCodingAgentTemplate.id
        }

        /// 当前编辑区标题。
        var editorTitle: String {
            guard let selectedAgent else {
                return "No Agent"
            }

            if isEditingDefaultCodingAgent {
                return DefaultCodingAgentTemplate.name
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
            editorKnowledgeReferences = []
            editorSkillReferences = []
            editorToolReferences = []
        }

        /// 返回指定 provider 下的模型选项。
        ///
        /// - Parameter providerID: Pi provider ID。
        /// - Returns: provider 对应的模型摘要列表。
        func modelOptions(for providerID: String) -> [AppModelSummary] {
            let trimmedProviderID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
            return availableModels.filter { $0.providerID == trimmedProviderID }
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
            editorKnowledgeReferences = agent.manifest.knowledge
            editorSkillReferences = agent.manifest.skills
            editorToolReferences = agent.manifest.tools
        }

        /// 用共享资源列表填充编辑页可选资源。
        ///
        /// - Parameter options: 资源库当前已有的共享资源列表。
        mutating func populateResourceOptions(with options: AgentResourceOptions) {
            availableKnowledge = options.knowledge
            availableSkills = options.skills
            availableTools = options.tools
        }

        /// 用应用设置填充 Agent 编辑页使用的配置项。
        ///
        /// - Parameter settings: 应用设置。
        mutating func populateSettings(_ settings: AppSettings) {
            allowedModelProviders = settings.agent.allowedModelProviders
        }

        /// 用模型清单填充 Agent 编辑页使用的配置项。
        ///
        /// - Parameter models: RuntimeHost/Pi 返回的模型摘要。
        mutating func populateModelCatalog(_ models: [AppModelSummary]) {
            availableModels = models
            if editorModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let firstModel = editorModelOptions.first {
                editorModelName = firstModel.modelID
            }
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

            if agent.id == DefaultCodingAgentTemplate.id {
                agent.manifest.name = DefaultCodingAgentTemplate.name
                agent.manifest.model = .default
                agent.manifest.knowledge = []
                agent.manifest.skills = editorSkillReferences
                agent.manifest.tools = []
                agent.manifest.permissions = .default
                agent.systemPrompt = DefaultCodingAgentTemplate.systemPrompt
                return agent
            }

            agent.manifest.knowledge = editorKnowledgeReferences
            agent.manifest.skills = editorSkillReferences
            agent.manifest.tools = editorToolReferences
            agent.systemPrompt = editorSystemPrompt
            return agent
        }

        /// 更新指定资源引用的选择状态。
        ///
        /// - Parameters:
        ///   - kind: 资源类型。
        ///   - reference: 写入 `agent.yaml` 的资源引用路径。
        ///   - isSelected: 是否选中。
        mutating func setResourceSelection(kind: AppResourceKind, reference: String, isSelected: Bool) {
            let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedReference.isEmpty else {
                return
            }

            switch kind {
            case .knowledge:
                Self.setReference(trimmedReference, isSelected: isSelected, in: &editorKnowledgeReferences)
            case .skill:
                Self.setReference(trimmedReference, isSelected: isSelected, in: &editorSkillReferences)
            case .tool:
                Self.setReference(trimmedReference, isSelected: isSelected, in: &editorToolReferences)
            }
        }

        /// 插入或替换 Agent 摘要，并按 ID 稳定排序。
        ///
        /// - Parameter summary: 要同步到列表中的 Agent 摘要。
        mutating func upsertSummary(_ summary: AgentSummary) {
            agents.removeAll { $0.id == summary.id }
            agents.append(summary)
            agents.sort { $0.id < $1.id }
        }

        private static func setReference(_ reference: String, isSelected: Bool, in references: inout [String]) {
            if isSelected {
                if !references.contains(reference) {
                    references.append(reference)
                }
            } else {
                references.removeAll { $0 == reference }
            }
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

        /// 可选资源列表加载成功。
        case loadResourceOptionsSucceeded(AgentResourceOptions)

        /// 可选资源列表加载失败。
        case loadResourceOptionsFailed(AppResourceClientError)

        /// 应用设置加载成功。
        case loadSettingsSucceeded(AppSettings)

        /// 应用设置加载失败。
        case loadSettingsFailed(AppSettingsClientError)

        /// 模型清单加载成功。
        case loadModelCatalogSucceeded([AppModelSummary])

        /// 模型清单加载失败。
        case loadModelCatalogFailed(AppModelCatalogClientError)

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

        /// 编辑表单资源选择变化。
        case resourceSelectionChanged(kind: AppResourceKind, reference: String, isSelected: Bool)

        /// 用户点击保存 Agent。
        case saveAgentButtonTapped

        /// Agent 保存成功。
        case saveAgentSucceeded(Agent)

        /// Agent 保存失败。
        case saveAgentFailed(AppAgentClientError)
    }

    private nonisolated enum CancelID: Hashable {
        case pageData
        case modelCatalog
        case selectedAgent
    }

    /// Agent 管理页面 reducer。
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task, .refreshButtonTapped:
                state.isLoadingList = true
                state.isLoadingResources = true
                state.isLoadingSettings = true
                state.isLoadingModelCatalog = true
                state.errorMessage = nil
                return loadPageDataEffect()

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

            case let .loadResourceOptionsSucceeded(options):
                state.isLoadingResources = false
                state.populateResourceOptions(with: options)
                return .none

            case let .loadResourceOptionsFailed(error):
                state.isLoadingResources = false
                state.errorMessage = error.message
                return .none

            case let .loadSettingsSucceeded(settings):
                state.isLoadingSettings = false
                state.populateSettings(settings)
                return loadModelCatalogEffect(providerIDs: settings.agent.allowedModelProviders)

            case let .loadSettingsFailed(error):
                state.isLoadingSettings = false
                state.isLoadingModelCatalog = false
                state.errorMessage = error.message
                return .none

            case let .loadModelCatalogSucceeded(models):
                state.isLoadingModelCatalog = false
                state.populateModelCatalog(models)
                return .none

            case let .loadModelCatalogFailed(error):
                state.isLoadingModelCatalog = false
                state.availableModels = []
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
                if let firstModel = state.editorModelOptions.first {
                    state.editorModelName = firstModel.modelID
                } else {
                    state.editorModelName = ""
                }
                return .none

            case let .editorModelNameChanged(name):
                state.editorModelName = name
                return .none

            case let .editorSystemPromptChanged(systemPrompt):
                state.editorSystemPrompt = systemPrompt
                return .none

            case let .resourceSelectionChanged(kind, reference, isSelected):
                state.setResourceSelection(kind: kind, reference: reference, isSelected: isSelected)
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

    private func loadPageDataEffect() -> Effect<Action> {
        @Dependency(AppAgentClient.self) var appAgentClient
        @Dependency(AppResourceClient.self) var appResourceClient
        @Dependency(AppSettingsClient.self) var appSettingsClient
        return .run { send in
            do {
                let agents = try await appAgentClient.listAgents()
                await send(.loadAgentsSucceeded(agents))
            } catch {
                await send(.loadAgentsFailed(AppAgentClientError(error)))
            }

            do {
                let options = AgentResourceOptions(
                    knowledge: try await appResourceClient.listResources(.knowledge),
                    skills: try await appResourceClient.listResources(.skill),
                    tools: try await appResourceClient.listResources(.tool)
                )
                await send(.loadResourceOptionsSucceeded(options))
            } catch {
                await send(.loadResourceOptionsFailed(AppResourceClientError(error)))
            }

            do {
                let settings = try await appSettingsClient.loadSettings()
                await send(.loadSettingsSucceeded(settings))
            } catch {
                await send(.loadSettingsFailed(AppSettingsClientError(error)))
            }
        }
        .cancellable(id: CancelID.pageData, cancelInFlight: true)
    }

    private func loadModelCatalogEffect(providerIDs: [String]) -> Effect<Action> {
        @Dependency(AppModelCatalogClient.self) var appModelCatalogClient
        return .run { send in
            do {
                let models = try await appModelCatalogClient.loadModels(providerIDs)
                await send(.loadModelCatalogSucceeded(models))
            } catch {
                await send(.loadModelCatalogFailed(AppModelCatalogClientError(error)))
            }
        }
        .cancellable(id: CancelID.modelCatalog, cancelInFlight: true)
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
