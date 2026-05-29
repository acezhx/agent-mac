import ComposableArchitecture
import Foundation
import Testing
@testable import AgentMac

/// AppShell 根 Feature 的启动初始化测试。
@MainActor
struct AppFeatureTests {
    /// 验证根视图进入时会初始化本地数据目录，且成功后不会重复初始化。
    @Test func taskInitializesAppDataOnce() async {
        let recorder = StartupRecorder()
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.appStartupClient = AppStartupClient(
                initializeAppData: {
                    recorder.initializeCount += 1
                }
            )
        }

        await store.send(.task)
        await store.receive(.appDataInitializationSucceeded) {
            $0.hasInitializedAppData = true
            $0.startupErrorMessage = nil
        }
        await store.send(.task)

        #expect(recorder.initializeCount == 1)
        await store.finish()
    }

    /// 验证启动初始化失败时会保存面向 UI 的错误信息。
    @Test func startupFailureStoresErrorMessage() async {
        let error = AppStartupClientError("startup failed")
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.appStartupClient = AppStartupClient(
                initializeAppData: {
                    throw error
                }
            )
        }

        await store.send(.task)
        await store.receive(.appDataInitializationFailed(error)) {
            $0.hasInitializedAppData = false
            $0.startupErrorMessage = "startup failed"
        }
        await store.finish()
    }

    /// 验证启动初始化会创建默认 coding Agent。
    @Test func startupClientSeedsDefaultCodingAgent() throws {
        let (fileStore, root) = try makeFileStore()
        defer { removeTemporaryRoot(root) }

        try AppStartupClient.initializeAppData(fileStore: fileStore)

        let agent = try AgentLibrary(fileStore: fileStore)
            .loadAgent(id: DefaultCodingAgentTemplate.id)

        #expect(agent.id == "coding-agent")
        #expect(agent.manifest.name == "Pi Coding Agent")
        #expect(agent.manifest.model == .default)
        #expect(agent.manifest.systemPrompt == "system.md")
        #expect(agent.manifest.knowledge == [])
        #expect(agent.manifest.skills == [])
        #expect(agent.manifest.tools == [])
        #expect(agent.manifest.permissions == .default)
        #expect(agent.systemPrompt == DefaultCodingAgentTemplate.systemPrompt)
    }

    /// 验证已有默认 coding Agent 时启动初始化不会覆盖用户修改。
    @Test func startupClientDoesNotOverwriteExistingCodingAgent() throws {
        let (fileStore, root) = try makeFileStore()
        defer { removeTemporaryRoot(root) }

        let agentLibrary = AgentLibrary(fileStore: fileStore)
        try fileStore.initialize()
        var existingAgent = try agentLibrary.createAgent(
            id: DefaultCodingAgentTemplate.id,
            name: "Custom Coding",
            systemPrompt: "Custom prompt"
        )
        existingAgent.manifest.model = ModelConfig(provider: "local", name: "custom-model")
        existingAgent.manifest.permissions = PermissionConfig(bash: .deny, edit: .ask, network: .deny)
        try agentLibrary.saveAgent(existingAgent)

        try AppStartupClient.initializeAppData(fileStore: fileStore)

        let loadedAgent = try agentLibrary.loadAgent(id: DefaultCodingAgentTemplate.id)
        #expect(loadedAgent == existingAgent)
    }

    private func makeFileStore() throws -> (FileStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AgentMac-AppStartupClientTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (FileStore(rootDirectory: root), root)
    }

    private func removeTemporaryRoot(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }
}

/// `@Sendable` mock closure 中记录启动初始化调用次数的容器。
private final class StartupRecorder: @unchecked Sendable {
    /// 初始化调用次数。
    var initializeCount = 0
}
