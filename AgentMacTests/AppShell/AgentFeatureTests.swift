import ComposableArchitecture
import Foundation
import Testing
@testable import AgentMac

/// AppShell Agent Feature 的状态流转测试。
///
/// 测试只注入 mock dependency，不访问真实 Application Support。
@MainActor
struct AgentFeatureTests {
    /// 验证加载 Agent 列表会保存摘要。
    @Test func loadAgentsStoresSummaries() async {
        let summaries = [
            AgentSummary(id: "coding-agent", name: "Coding", model: .default),
        ]
        let resourceOptions = AgentResourceOptions(
            knowledge: [
                makeResourceSummary(kind: .knowledge, id: "refund.md", name: "refund", path: "library/knowledge/refund.md"),
            ],
            skills: [
                makeResourceSummary(kind: .skill, id: "report-writing", name: "Report Writing", path: "library/skills/report-writing"),
            ],
            tools: [
                makeResourceSummary(kind: .tool, id: "ticket-search", name: "Ticket Search", path: "library/tools/ticket-search"),
            ]
        )
        let settings = AppSettings(agent: AgentAppSettings(allowedModelProviders: ["openai", "deepseek"]))
        #expect(resourceOptions.knowledge[0].agentManifestReference == "../../library/knowledge/refund.md")
        #expect(resourceOptions.skills[0].agentManifestReference == "../../library/skills/report-writing")
        #expect(resourceOptions.tools[0].agentManifestReference == "../../library/tools/ticket-search")
        let store = TestStore(initialState: AgentFeature.State()) {
            AgentFeature()
        } withDependencies: {
            $0.appAgentClient = makeClient(
                listAgents: {
                    summaries
                }
            )
            $0.appResourceClient = makeResourceClient(options: resourceOptions)
            $0.appSettingsClient = makeSettingsClient(settings: settings)
        }

        await store.send(.task) {
            $0.isLoadingList = true
            $0.isLoadingResources = true
            $0.isLoadingSettings = true
            $0.errorMessage = nil
        }
        await store.receive(.loadAgentsSucceeded(summaries)) {
            $0.isLoadingList = false
            $0.agents = summaries
        }
        await store.receive(.loadResourceOptionsSucceeded(resourceOptions)) {
            $0.isLoadingResources = false
            $0.availableKnowledge = resourceOptions.knowledge
            $0.availableSkills = resourceOptions.skills
            $0.availableTools = resourceOptions.tools
        }
        await store.receive(.loadSettingsSucceeded(settings)) {
            $0.isLoadingSettings = false
            $0.allowedModelProviders = ["openai", "deepseek"]
        }
    }

    /// 验证选择 Agent 会加载编辑区并同步已选择资源。
    @Test func selectingAgentLoadsEditorFields() async {
        var agent = makeAgent(
            id: "coding-agent",
            name: "Coding",
            model: ModelConfig(provider: "deepseek", name: "deepseek-v4-flash"),
            systemPrompt: "You are a coding agent."
        )
        agent.manifest.knowledge = ["../../library/knowledge/refund.md"]
        agent.manifest.skills = ["../../library/skills/report-writing"]
        agent.manifest.tools = ["../../library/tools/ticket-search"]
        let loadedAgent = agent
        let store = TestStore(initialState: AgentFeature.State()) {
            AgentFeature()
        } withDependencies: {
            $0.appAgentClient = makeClient(
                loadAgent: { id in
                    #expect(id == "coding-agent")
                    return loadedAgent
                }
            )
        }

        await store.send(.agentSelected("coding-agent")) {
            $0.selectedAgentID = "coding-agent"
            $0.errorMessage = nil
            $0.isLoadingAgent = true
        }
        await store.receive(.loadAgentSucceeded(loadedAgent)) {
            $0.isLoadingAgent = false
            $0.selectedAgent = loadedAgent
            $0.selectedAgentID = "coding-agent"
            $0.editorName = "Coding"
            $0.editorModelProvider = "deepseek"
            $0.editorModelName = "deepseek-v4-flash"
            $0.editorSystemPrompt = "You are a coding agent."
            $0.editorKnowledgeReferences = ["../../library/knowledge/refund.md"]
            $0.editorSkillReferences = ["../../library/skills/report-writing"]
            $0.editorToolReferences = ["../../library/tools/ticket-search"]
        }
    }

    /// 验证创建 Agent 会清空创建表单、选中新 Agent 并更新列表。
    @Test func createAgentSelectsNewAgentAndUpdatesList() async {
        let agent = makeAgent(id: "coding-agent", name: "Coding")
        let recorder = Recorder()
        var state = AgentFeature.State()
        state.newAgentID = "  coding-agent  "
        state.newAgentName = "  Coding  "
        let store = TestStore(initialState: state) {
            AgentFeature()
        } withDependencies: {
            $0.appAgentClient = makeClient(
                createAgent: { id, name in
                    recorder.createdAgents.append((id, name))
                    return agent
                }
            )
        }

        await store.send(.createAgentButtonTapped) {
            $0.isCreatingAgent = true
            $0.errorMessage = nil
        }
        await store.receive(.createAgentSucceeded(agent)) {
            $0.isCreatingAgent = false
            $0.newAgentID = ""
            $0.newAgentName = ""
            $0.agents = [agent.summary]
            $0.selectedAgent = agent
            $0.selectedAgentID = "coding-agent"
            $0.editorName = "Coding"
            $0.editorModelProvider = "openai"
            $0.editorModelName = "gpt-5-codex"
            $0.editorSystemPrompt = ""
            $0.errorMessage = nil
        }

        #expect(recorder.createdAgents.count == 1)
        #expect(recorder.createdAgents.first?.0 == "coding-agent")
        #expect(recorder.createdAgents.first?.1 == "Coding")
    }

    /// 验证勾选和取消勾选资源会更新编辑状态。
    @Test func resourceSelectionChangesUpdateEditorState() async {
        let agent = makeAgent(id: "support-agent", name: "Support")
        var state = AgentFeature.State()
        state.populateEditor(with: agent)
        let store = TestStore(initialState: state) {
            AgentFeature()
        } withDependencies: {
            $0.appAgentClient = makeClient()
            $0.appResourceClient = makeResourceClient()
        }

        await store.send(.resourceSelectionChanged(
            kind: .knowledge,
            reference: "../../library/knowledge/refund.md",
            isSelected: true
        )) {
            $0.editorKnowledgeReferences = ["../../library/knowledge/refund.md"]
        }
        await store.send(.resourceSelectionChanged(
            kind: .skill,
            reference: "../../library/skills/report-writing",
            isSelected: true
        )) {
            $0.editorSkillReferences = ["../../library/skills/report-writing"]
        }
        await store.send(.resourceSelectionChanged(
            kind: .skill,
            reference: "../../library/skills/report-writing",
            isSelected: false
        )) {
            $0.editorSkillReferences = []
        }
        await store.send(.resourceSelectionChanged(
            kind: .tool,
            reference: "../../library/tools/ticket-search",
            isSelected: true
        )) {
            $0.editorToolReferences = ["../../library/tools/ticket-search"]
        }
    }

    /// 验证保存 Agent 时提交当前资源选择，且保留 system prompt、模型和权限配置。
    @Test func saveAgentSubmitsCurrentResourcesAndPreservesPromptModelAndPermissions() async {
        var agent = makeAgent(
            id: "support-agent",
            name: "Support",
            model: ModelConfig(provider: "openai", name: "gpt-5-codex"),
            systemPrompt: "Initial"
        )
        agent.manifest.knowledge = ["../../library/knowledge/refund.md"]
        agent.manifest.skills = ["../../library/skills/report-writing"]
        agent.manifest.tools = ["../../library/tools/ticket-search"]
        agent.manifest.permissions = PermissionConfig(bash: .deny, edit: .ask, network: .allow)

        var savedAgent = agent
        savedAgent.manifest.name = "Support Pro"
        savedAgent.manifest.model = ModelConfig(provider: "deepseek", name: "deepseek-v4-flash")
        savedAgent.manifest.knowledge = [
            "../../library/knowledge/refund.md",
            "../../library/knowledge/order-rules.md",
        ]
        savedAgent.manifest.skills = []
        savedAgent.manifest.tools = ["../../library/tools/order-lookup"]
        savedAgent.systemPrompt = "Updated"
        let savedAgentResult = savedAgent

        let recorder = Recorder()
        var state = AgentFeature.State()
        state.populateEditor(with: agent)
        state.editorName = "Support Pro"
        state.editorModelProvider = "deepseek"
        state.editorModelName = "deepseek-v4-flash"
        state.editorSystemPrompt = "Updated"
        state.allowedModelProviders = ["openai", "deepseek"]
        let store = TestStore(initialState: state) {
            AgentFeature()
        } withDependencies: {
            $0.appAgentClient = makeClient(
                saveAgent: { agent in
                    recorder.savedAgents.append(agent)
                    return savedAgentResult
                }
            )
        }

        await store.send(.resourceSelectionChanged(
            kind: .knowledge,
            reference: "../../library/knowledge/order-rules.md",
            isSelected: true
        )) {
            $0.editorKnowledgeReferences = [
                "../../library/knowledge/refund.md",
                "../../library/knowledge/order-rules.md",
            ]
        }
        await store.send(.resourceSelectionChanged(
            kind: .skill,
            reference: "../../library/skills/report-writing",
            isSelected: false
        )) {
            $0.editorSkillReferences = []
        }
        await store.send(.resourceSelectionChanged(
            kind: .tool,
            reference: "../../library/tools/ticket-search",
            isSelected: false
        )) {
            $0.editorToolReferences = []
        }
        await store.send(.resourceSelectionChanged(
            kind: .tool,
            reference: "../../library/tools/order-lookup",
            isSelected: true
        )) {
            $0.editorToolReferences = ["../../library/tools/order-lookup"]
        }
        await store.send(.saveAgentButtonTapped) {
            $0.isSavingAgent = true
            $0.errorMessage = nil
        }
        await store.receive(.saveAgentSucceeded(savedAgent)) {
            $0.isSavingAgent = false
            $0.agents = [savedAgent.summary]
            $0.selectedAgent = savedAgent
            $0.selectedAgentID = "support-agent"
            $0.editorName = "Support Pro"
            $0.editorModelProvider = "deepseek"
            $0.editorModelName = "deepseek-v4-flash"
            $0.editorSystemPrompt = "Updated"
            $0.editorKnowledgeReferences = savedAgent.manifest.knowledge
            $0.editorSkillReferences = savedAgent.manifest.skills
            $0.editorToolReferences = savedAgent.manifest.tools
            $0.errorMessage = nil
        }

        #expect(recorder.savedAgents.count == 1)
        #expect(recorder.savedAgents[0].manifest.knowledge == savedAgent.manifest.knowledge)
        #expect(recorder.savedAgents[0].manifest.skills == savedAgent.manifest.skills)
        #expect(recorder.savedAgents[0].manifest.tools == savedAgent.manifest.tools)
        #expect(recorder.savedAgents[0].systemPrompt == "Updated")
        #expect(recorder.savedAgents[0].manifest.model == ModelConfig(provider: "deepseek", name: "deepseek-v4-flash"))
        #expect(recorder.savedAgents[0].manifest.permissions == agent.manifest.permissions)
    }

    /// 验证保存默认 Pi coding agent 时只提交模型配置，并恢复 Pi 自身管理的字段默认值。
    @Test func saveDefaultCodingAgentSubmitsOnlyModelAndPiDefaults() async {
        var agent = makeAgent(
            id: DefaultCodingAgentTemplate.id,
            name: "Custom Coding",
            model: ModelConfig(provider: "openai", name: "gpt-5-codex"),
            systemPrompt: "Custom prompt"
        )
        agent.manifest.knowledge = ["../../library/knowledge/refund.md"]
        agent.manifest.skills = ["../../library/skills/report-writing"]
        agent.manifest.tools = ["../../library/tools/ticket-search"]
        agent.manifest.permissions = PermissionConfig(bash: .allow, edit: .deny, network: .allow)

        var expectedSavedAgent = agent
        expectedSavedAgent.manifest.name = DefaultCodingAgentTemplate.name
        expectedSavedAgent.manifest.model = ModelConfig(provider: "deepseek", name: "deepseek-v4-flash")
        expectedSavedAgent.manifest.knowledge = []
        expectedSavedAgent.manifest.skills = []
        expectedSavedAgent.manifest.tools = []
        expectedSavedAgent.manifest.permissions = .default
        expectedSavedAgent.systemPrompt = DefaultCodingAgentTemplate.systemPrompt

        let recorder = Recorder()
        var state = AgentFeature.State()
        state.populateEditor(with: agent)
        state.editorName = ""
        state.editorModelProvider = "deepseek"
        state.editorModelName = "deepseek-v4-flash"
        state.editorSystemPrompt = "Hidden prompt edit"
        state.editorKnowledgeReferences = ["../../library/knowledge/order-rules.md"]
        state.editorSkillReferences = ["../../library/skills/hidden-skill"]
        state.editorToolReferences = ["../../library/tools/hidden-tool"]
        state.allowedModelProviders = ["openai", "deepseek"]
        let store = TestStore(initialState: state) {
            AgentFeature()
        } withDependencies: {
            $0.appAgentClient = makeClient(
                saveAgent: { agent in
                    recorder.savedAgents.append(agent)
                    return agent
                }
            )
        }

        await store.send(.saveAgentButtonTapped) {
            $0.isSavingAgent = true
            $0.errorMessage = nil
        }
        await store.receive(.saveAgentSucceeded(expectedSavedAgent)) {
            $0.isSavingAgent = false
            $0.agents = [expectedSavedAgent.summary]
            $0.selectedAgent = expectedSavedAgent
            $0.selectedAgentID = DefaultCodingAgentTemplate.id
            $0.editorName = DefaultCodingAgentTemplate.name
            $0.editorModelProvider = "deepseek"
            $0.editorModelName = "deepseek-v4-flash"
            $0.editorSystemPrompt = DefaultCodingAgentTemplate.systemPrompt
            $0.editorKnowledgeReferences = []
            $0.editorSkillReferences = []
            $0.editorToolReferences = []
            $0.errorMessage = nil
        }

        #expect(recorder.savedAgents == [expectedSavedAgent])
    }

    /// 验证创建失败时清理进行中标记并展示错误。
    @Test func createAgentFailureClearsFlagAndStoresError() async {
        let error = AppAgentClientError("create failed")
        var state = AgentFeature.State()
        state.newAgentID = "coding-agent"
        state.newAgentName = "Coding"
        let store = TestStore(initialState: state) {
            AgentFeature()
        } withDependencies: {
            $0.appAgentClient = makeClient(
                createAgent: { _, _ in
                    throw error
                }
            )
        }

        await store.send(.createAgentButtonTapped) {
            $0.isCreatingAgent = true
            $0.errorMessage = nil
        }
        await store.receive(.createAgentFailed(error)) {
            $0.isCreatingAgent = false
            $0.errorMessage = "create failed"
        }
    }

    /// 验证保存失败时清理进行中标记并展示错误。
    @Test func saveAgentFailureClearsFlagAndStoresError() async {
        let agent = makeAgent(id: "coding-agent", name: "Coding")
        let error = AppAgentClientError("save failed")
        var state = AgentFeature.State()
        state.populateEditor(with: agent)
        let store = TestStore(initialState: state) {
            AgentFeature()
        } withDependencies: {
            $0.appAgentClient = makeClient(
                saveAgent: { _ in
                    throw error
                }
            )
        }

        await store.send(.saveAgentButtonTapped) {
            $0.isSavingAgent = true
            $0.errorMessage = nil
        }
        await store.receive(.saveAgentFailed(error)) {
            $0.isSavingAgent = false
            $0.errorMessage = "save failed"
        }
    }

    /// 验证 Agent 保存会受 Settings 中允许的 provider 限制。
    @Test func saveAgentRequiresAllowedModelProvider() async {
        let agent = makeAgent(
            id: "support-agent",
            name: "Support",
            model: ModelConfig(provider: "openai", name: "gpt-5-codex")
        )
        var state = AgentFeature.State()
        state.populateEditor(with: agent)
        state.editorModelProvider = "deepseek"
        state.allowedModelProviders = ["openai"]
        let store = TestStore(initialState: state) {
            AgentFeature()
        } withDependencies: {
            $0.appAgentClient = makeClient(
                saveAgent: { _ in
                    Issue.record("Disallowed provider should not be saved.")
                    return agent
                }
            )
        }

        await store.send(.saveAgentButtonTapped)
    }

    private func makeClient(
        listAgents: @escaping @Sendable () async throws -> [AgentSummary] = {
            throw AppAgentClientError("Unexpected listAgents call.")
        },
        loadAgent: @escaping @Sendable (String) async throws -> Agent = { _ in
            throw AppAgentClientError("Unexpected loadAgent call.")
        },
        createAgent: @escaping @Sendable (String, String) async throws -> Agent = { _, _ in
            throw AppAgentClientError("Unexpected createAgent call.")
        },
        saveAgent: @escaping @Sendable (Agent) async throws -> Agent = { _ in
            throw AppAgentClientError("Unexpected saveAgent call.")
        }
    ) -> AppAgentClient {
        AppAgentClient(
            listAgents: listAgents,
            loadAgent: loadAgent,
            createAgent: createAgent,
            saveAgent: saveAgent
        )
    }

    private func makeResourceClient(options: AgentResourceOptions = .empty) -> AppResourceClient {
        AppResourceClient(
            listResources: { kind in
                switch kind {
                case .knowledge:
                    return options.knowledge
                case .skill:
                    return options.skills
                case .tool:
                    return options.tools
                }
            },
            loadResource: { _, _ in
                throw AppResourceClientError("Unexpected loadResource call.")
            },
            createResource: { _, _, _ in
                throw AppResourceClientError("Unexpected createResource call.")
            },
            importSkillDirectory: { _ in
                throw AppResourceClientError("Unexpected importSkillDirectory call.")
            },
            saveResource: { _ in
                throw AppResourceClientError("Unexpected saveResource call.")
            },
            deleteResource: { _, _ in
                throw AppResourceClientError("Unexpected deleteResource call.")
            }
        )
    }

    private func makeResourceSummary(
        kind: AppResourceKind,
        id: String,
        name: String,
        path: String,
        detail: String? = nil,
        validationMessages: [String] = []
    ) -> AppResourceSummary {
        AppResourceSummary(
            kind: kind,
            id: id,
            name: name,
            path: path,
            detail: detail ?? path,
            validationMessages: validationMessages
        )
    }

    private func makeSettingsClient(settings: AppSettings = .default) -> AppSettingsClient {
        AppSettingsClient(
            loadSettings: {
                settings
            },
            saveSettings: { settings in
                settings
            }
        )
    }

    private func makeAgent(
        id: String,
        name: String,
        model: ModelConfig = .default,
        systemPrompt: String = ""
    ) -> Agent {
        Agent(
            manifest: AgentManifest(
                id: id,
                name: name,
                model: model
            ),
            systemPrompt: systemPrompt
        )
    }
}

/// `@Sendable` mock closures 中记录调用情况的简单容器。
private final class Recorder: @unchecked Sendable {
    /// createAgent 收到的参数。
    var createdAgents: [(String, String)] = []

    /// saveAgent 收到的 Agent。
    var savedAgents: [Agent] = []
}
