import ComposableArchitecture
import Foundation

/// AppShell 首次启动初始化边界。
///
/// 该 dependency 只负责应用启动时必须完成的本地数据目录初始化和默认数据种子，避免根 Feature
/// 直接持有 `FileStore` 或理解 Application Support 布局细节。
nonisolated struct AppStartupClient: Sendable {
    /// 初始化 Application Support 数据目录。
    var initializeAppData: @Sendable () async throws -> Void
}

/// 应用首次初始化时写入的默认 coding Agent。
nonisolated enum DefaultCodingAgentTemplate {
    /// 默认 Pi coding agent 的持久化 ID。
    static let id = "coding-agent"

    /// 默认 Pi coding agent 的展示名称。
    static let name = "Pi Coding Agent"

    /// 默认 Pi coding agent 的 system prompt。
    ///
    /// 该 Agent 的提示词和工具权限由 Pi coding agent 自身提供，AgentMac 只持久化模型配置。
    static let systemPrompt = ""
}

/// AppShell 启动初始化对 UI 暴露的结构化错误。
nonisolated struct AppStartupClientError: Error, Equatable, Sendable {
    /// 可直接用于 UI 展示或测试断言的错误信息。
    let message: String

    /// 创建启动初始化错误。
    ///
    /// - Parameter message: 错误信息。
    init(_ message: String) {
        self.message = message
    }

    /// 从底层错误创建启动初始化错误。
    ///
    /// - Parameter error: 底层服务错误。
    init(_ error: Error) {
        if let error = error as? AppStartupClientError {
            self.message = error.message
        } else if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            self.message = "Unable to initialize AgentMac data directory. \(description)"
        } else {
            self.message = "Unable to initialize AgentMac data directory. \(error.localizedDescription)"
        }
    }
}

extension AppStartupClientError: LocalizedError {
    /// 面向 UI 的错误描述。
    var errorDescription: String? {
        message
    }
}

extension AppStartupClient: DependencyKey {
    /// App 运行时使用的真实 dependency。
    static let liveValue = AppStartupClient(
        initializeAppData: {
            let fileStore = try FileStore()
            try AppStartupClient.initializeAppData(fileStore: fileStore)
        }
    )

    /// 测试默认值；具体测试应显式注入 mock。
    static let testValue = AppStartupClient(
        initializeAppData: {
            throw AppStartupClientError("AppStartupClient.initializeAppData is not implemented for this test.")
        }
    )
}

extension AppStartupClient {
    /// 初始化 app data 并确保默认 coding Agent 存在。
    ///
    /// - Parameter fileStore: 当前 app data 根目录对应的文件服务。
    nonisolated static func initializeAppData(fileStore: FileStore) throws {
        try fileStore.initialize()
        try seedDefaultCodingAgentIfNeeded(fileStore: fileStore)
    }

    private nonisolated static func seedDefaultCodingAgentIfNeeded(fileStore: FileStore) throws {
        guard try !fileStore.directoryExists(at: "agents/\(DefaultCodingAgentTemplate.id)") else {
            return
        }

        let agentLibrary = AgentLibrary(fileStore: fileStore)
        try agentLibrary.createAgent(
            id: DefaultCodingAgentTemplate.id,
            name: DefaultCodingAgentTemplate.name,
            systemPrompt: DefaultCodingAgentTemplate.systemPrompt
        )
    }
}

extension DependencyValues {
    /// AppShell 启动初始化 dependency。
    var appStartupClient: AppStartupClient {
        get { self[AppStartupClient.self] }
        set { self[AppStartupClient.self] = newValue }
    }
}
