import ComposableArchitecture
import Foundation

/// AppShell 通过 TCA dependency 使用的 Agent 管理边界。
///
/// 该类型把 `AgentLibrary` 包装成 Feature 可注入的操作，避免 SwiftUI View 直接持有底层服务对象。
nonisolated struct AppAgentClient: Sendable {
    /// 加载 Agent 摘要列表。
    var listAgents: @Sendable () async throws -> [AgentSummary]

    /// 加载单个 Agent 编辑模型。
    var loadAgent: @Sendable (_ id: String) async throws -> Agent

    /// 创建 Agent。
    var createAgent: @Sendable (_ id: String, _ name: String) async throws -> Agent

    /// 保存 Agent 编辑模型。
    var saveAgent: @Sendable (_ agent: Agent) async throws -> Agent
}

/// AppShell dependency 对 Agent UI 暴露的结构化错误。
nonisolated struct AppAgentClientError: Error, Equatable, Sendable {
    /// 可直接用于 UI 展示或测试断言的错误信息。
    let message: String

    /// 创建 Agent UI 错误。
    ///
    /// - Parameter message: 错误信息。
    init(_ message: String) {
        self.message = message
    }

    /// 从底层错误创建 Agent UI 错误。
    ///
    /// - Parameter error: 底层服务错误。
    init(_ error: Error) {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            self.message = description
        } else {
            self.message = error.localizedDescription
        }
    }
}

extension AppAgentClientError: LocalizedError {
    /// 面向 UI 的错误描述。
    var errorDescription: String? {
        message
    }
}

extension AppAgentClient: DependencyKey {
    /// App 运行时使用的真实 dependency。
    static let liveValue: AppAgentClient = {
        let controller = LiveAgentLibraryController()
        return AppAgentClient(
            listAgents: {
                try await controller.listAgents()
            },
            loadAgent: { id in
                try await controller.loadAgent(id: id)
            },
            createAgent: { id, name in
                try await controller.createAgent(id: id, name: name)
            },
            saveAgent: { agent in
                try await controller.saveAgent(agent)
            }
        )
    }()

    /// 测试默认值；具体测试应显式注入 mock。
    static let testValue = AppAgentClient(
        listAgents: {
            throw AppAgentClientError("AppAgentClient.listAgents is not implemented for this test.")
        },
        loadAgent: { _ in
            throw AppAgentClientError("AppAgentClient.loadAgent is not implemented for this test.")
        },
        createAgent: { _, _ in
            throw AppAgentClientError("AppAgentClient.createAgent is not implemented for this test.")
        },
        saveAgent: { _ in
            throw AppAgentClientError("AppAgentClient.saveAgent is not implemented for this test.")
        }
    )
}

extension DependencyValues {
    /// AppShell Agent 管理 dependency。
    var appAgentClient: AppAgentClient {
        get { self[AppAgentClient.self] }
        set { self[AppAgentClient.self] = newValue }
    }
}

/// AppShell live dependency 使用的 AgentLibrary 控制器。
///
/// 该 actor 只负责初始化 Application Support 文件服务并持有 `AgentLibrary` 实例，不把 TCA 下沉到
/// AgentLibrary。
private actor LiveAgentLibraryController {
    private var library: AgentLibrary?

    /// 加载 Agent 摘要列表。
    func listAgents() throws -> [AgentSummary] {
        try agentLibrary().listAgents()
    }

    /// 加载单个 Agent。
    ///
    /// - Parameter id: Agent ID。
    /// - Returns: Agent 编辑模型。
    func loadAgent(id: String) throws -> Agent {
        try agentLibrary().loadAgent(id: id)
    }

    /// 创建 Agent。
    ///
    /// - Parameters:
    ///   - id: Agent ID。
    ///   - name: Agent 展示名称。
    /// - Returns: 创建后的 Agent 编辑模型。
    func createAgent(id: String, name: String) throws -> Agent {
        try agentLibrary().createAgent(id: id, name: name)
    }

    /// 保存 Agent。
    ///
    /// - Parameter agent: Agent 编辑模型。
    /// - Returns: 保存后的 Agent 编辑模型。
    func saveAgent(_ agent: Agent) throws -> Agent {
        try agentLibrary().saveAgent(agent)
    }

    private func agentLibrary() throws -> AgentLibrary {
        if let library {
            return library
        }

        let fileStore = try FileStore()
        try fileStore.initialize()
        let library = AgentLibrary(fileStore: fileStore)
        self.library = library
        return library
    }
}
