import ComposableArchitecture
import Foundation
import Testing
@testable import AgentMac

/// AppShell Agent Feature 的状态流转测试。
///
/// 测试只注入 mock `AppAgentClient`，不访问真实 Application Support。
@MainActor
struct AgentFeatureTests {
    /// 验证加载 Agent 列表会保存摘要。
    @Test func loadAgentsStoresSummaries() async {
        let summaries = [
            AgentSummary(id: "coding-agent", name: "Coding", model: .default),
        ]
        let store = TestStore(initialState: AgentFeature.State()) {
            AgentFeature()
        } withDependencies: {
            $0.appAgentClient = makeClient(
                listAgents: {
                    summaries
                }
            )
        }

        await store.send(.task) {
            $0.isLoadingList = true
            $0.errorMessage = nil
        }
        await store.receive(.loadAgentsSucceeded(summaries)) {
            $0.isLoadingList = false
            $0.agents = summaries
        }
    }

    /// 验证选择 Agent 会加载编辑区。
    @Test func selectingAgentLoadsEditorFields() async {
        let agent = makeAgent(
            id: "coding-agent",
            name: "Coding",
            model: ModelConfig(provider: "deepseek", name: "deepseek-v4-flash"),
            systemPrompt: "You are a coding agent."
        )
        let store = TestStore(initialState: AgentFeature.State()) {
            AgentFeature()
        } withDependencies: {
            $0.appAgentClient = makeClient(
                loadAgent: { id in
                    #expect(id == "coding-agent")
                    return agent
                }
            )
        }

        await store.send(.agentSelected("coding-agent")) {
            $0.selectedAgentID = "coding-agent"
            $0.errorMessage = nil
            $0.isLoadingAgent = true
        }
        await store.receive(.loadAgentSucceeded(agent)) {
            $0.isLoadingAgent = false
            $0.selectedAgent = agent
            $0.selectedAgentID = "coding-agent"
            $0.editorName = "Coding"
            $0.editorModelProvider = "deepseek"
            $0.editorModelName = "deepseek-v4-flash"
            $0.editorSystemPrompt = "You are a coding agent."
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

    /// 验证保存 Agent 时保留当前 UI 尚未暴露的资源选择和权限配置。
    @Test func saveAgentPreservesResourcesAndPermissions() async {
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
        savedAgent.systemPrompt = "Updated"
        let savedAgentResult = savedAgent

        let recorder = Recorder()
        var state = AgentFeature.State()
        state.populateEditor(with: agent)
        state.editorName = "Support Pro"
        state.editorModelProvider = "deepseek"
        state.editorModelName = "deepseek-v4-flash"
        state.editorSystemPrompt = "Updated"
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
            $0.errorMessage = nil
        }

        #expect(recorder.savedAgents.count == 1)
        #expect(recorder.savedAgents[0].manifest.knowledge == agent.manifest.knowledge)
        #expect(recorder.savedAgents[0].manifest.skills == agent.manifest.skills)
        #expect(recorder.savedAgents[0].manifest.tools == agent.manifest.tools)
        #expect(recorder.savedAgents[0].manifest.permissions == agent.manifest.permissions)
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
