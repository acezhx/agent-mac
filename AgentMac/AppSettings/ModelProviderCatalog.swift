import Foundation

/// 模型 provider 的授权方式。
nonisolated enum ModelProviderAuthorizationKind: String, Equatable, Sendable {
    /// API Key 授权。
    case apiKey

    /// OAuth 或订阅账号授权。
    case oauth
}

/// AgentMac 支持展示和连接的模型 provider 定义。
nonisolated struct ModelProviderDefinition: Equatable, Identifiable, Sendable {
    /// Pi provider ID。
    var id: String

    /// UI 展示名称。
    var name: String

    /// UI 辅助说明。
    var subtitle: String

    /// 该 provider 支持的授权方式。
    var authorizationKinds: [ModelProviderAuthorizationKind]

    /// Pi 识别的 API Key 环境变量名。
    var apiKeyEnvironmentVariable: String?

    /// 是否支持 API Key 授权。
    var supportsAPIKey: Bool {
        authorizationKinds.contains(.apiKey)
    }

    /// 是否支持 OAuth 或订阅授权。
    var supportsOAuth: Bool {
        authorizationKinds.contains(.oauth)
    }
}

/// 当前内置 Pi 版本下 AgentMac 明确支持的模型 provider 目录。
nonisolated enum ModelProviderCatalog {
    /// API Key 和 OAuth/订阅授权 provider。
    static let providers: [ModelProviderDefinition] = [
        ModelProviderDefinition(
            id: "anthropic",
            name: "Anthropic",
            subtitle: "使用 Claude Pro/Max 或 API Key 连接",
            authorizationKinds: [.apiKey, .oauth],
            apiKeyEnvironmentVariable: "ANTHROPIC_API_KEY"
        ),
        ModelProviderDefinition(
            id: "deepseek",
            name: "DeepSeek",
            subtitle: "使用 DeepSeek API Key 连接",
            authorizationKinds: [.apiKey],
            apiKeyEnvironmentVariable: "DEEPSEEK_API_KEY"
        ),
        ModelProviderDefinition(
            id: "google",
            name: "Google Gemini",
            subtitle: "使用 Gemini API Key 连接",
            authorizationKinds: [.apiKey],
            apiKeyEnvironmentVariable: "GEMINI_API_KEY"
        ),
        ModelProviderDefinition(
            id: "kimi-coding",
            name: "Kimi For Coding",
            subtitle: "使用 Kimi API Key 连接",
            authorizationKinds: [.apiKey],
            apiKeyEnvironmentVariable: "KIMI_API_KEY"
        ),
        ModelProviderDefinition(
            id: "minimax",
            name: "MiniMax",
            subtitle: "使用 MiniMax API Key 连接",
            authorizationKinds: [.apiKey],
            apiKeyEnvironmentVariable: "MINIMAX_API_KEY"
        ),
        ModelProviderDefinition(
            id: "minimax-cn",
            name: "MiniMax China",
            subtitle: "使用 MiniMax 中国区 API Key 连接",
            authorizationKinds: [.apiKey],
            apiKeyEnvironmentVariable: "MINIMAX_CN_API_KEY"
        ),
        ModelProviderDefinition(
            id: "moonshotai",
            name: "Moonshot AI",
            subtitle: "使用 Moonshot API Key 连接",
            authorizationKinds: [.apiKey],
            apiKeyEnvironmentVariable: "MOONSHOT_API_KEY"
        ),
        ModelProviderDefinition(
            id: "moonshotai-cn",
            name: "Moonshot AI China",
            subtitle: "使用 Moonshot 中国区 API Key 连接",
            authorizationKinds: [.apiKey],
            apiKeyEnvironmentVariable: "MOONSHOT_API_KEY"
        ),
        ModelProviderDefinition(
            id: "openai-codex",
            name: "OpenAI Codex",
            subtitle: "使用 ChatGPT Plus/Pro 订阅连接",
            authorizationKinds: [.oauth],
            apiKeyEnvironmentVariable: nil
        ),
        ModelProviderDefinition(
            id: "xai",
            name: "xAI",
            subtitle: "使用 xAI API Key 连接",
            authorizationKinds: [.apiKey],
            apiKeyEnvironmentVariable: "XAI_API_KEY"
        ),
        ModelProviderDefinition(
            id: "xiaomi",
            name: "Xiaomi MiMo",
            subtitle: "使用 Xiaomi API Key 连接",
            authorizationKinds: [.apiKey],
            apiKeyEnvironmentVariable: "XIAOMI_API_KEY"
        ),
        ModelProviderDefinition(
            id: "xiaomi-token-plan-ams",
            name: "Xiaomi Token Plan AMS",
            subtitle: "使用 Xiaomi Amsterdam token plan API Key 连接",
            authorizationKinds: [.apiKey],
            apiKeyEnvironmentVariable: "XIAOMI_TOKEN_PLAN_AMS_API_KEY"
        ),
        ModelProviderDefinition(
            id: "xiaomi-token-plan-cn",
            name: "Xiaomi Token Plan CN",
            subtitle: "使用 Xiaomi 中国区 token plan API Key 连接",
            authorizationKinds: [.apiKey],
            apiKeyEnvironmentVariable: "XIAOMI_TOKEN_PLAN_CN_API_KEY"
        ),
        ModelProviderDefinition(
            id: "xiaomi-token-plan-sgp",
            name: "Xiaomi Token Plan SGP",
            subtitle: "使用 Xiaomi Singapore token plan API Key 连接",
            authorizationKinds: [.apiKey],
            apiKeyEnvironmentVariable: "XIAOMI_TOKEN_PLAN_SGP_API_KEY"
        ),
    ]

    /// 当前已接入浏览器 OAuth 登录流程的 provider ID。
    static let oauthLoginProviderIDs: Set<String> = ["anthropic", "openai-codex"]

    /// 按 ID 查找 provider。
    ///
    /// - Parameter id: Pi provider ID。
    /// - Returns: provider 定义；未知 ID 返回 `nil`。
    static func provider(id: String) -> ModelProviderDefinition? {
        providers.first { $0.id == id }
    }

    /// 查询 provider 是否支持从 Settings 页面发起 OAuth 登录。
    ///
    /// - Parameter id: Pi provider ID。
    /// - Returns: 当前 UI 是否允许直接启动该 provider 的 OAuth 登录流程。
    static func supportsOAuthLogin(id: String) -> Bool {
        oauthLoginProviderIDs.contains(id)
    }
}
