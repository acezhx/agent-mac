import Foundation
import Testing
@testable import AgentMac

/// AppSettings 模块的 YAML 编解码和持久化测试。
struct AppSettingsTests {
    /// 验证旧版最小 settings.yaml 缺少 Agent 设置时使用默认 provider。
    @Test func decodeMinimalSettingsUsesDefaultAgentProviders() throws {
        let settings = try AppSettingsYAMLCodec.decode("appDataVersion: 1\n")

        #expect(settings.appDataVersion == 1)
        #expect(settings.runtime.useBundledRuntime)
        #expect(settings.agent.allowedModelProviders == ["openai"])
    }

    /// 验证 settings.yaml 可以保存和恢复 Agent provider allowlist。
    @Test func settingsYAMLRoundTripsAllowedModelProviders() throws {
        let settings = AppSettings(
            lastWorkspace: "/tmp/workspace",
            runtime: RuntimeSettings(useBundledRuntime: false),
            agent: AgentAppSettings(allowedModelProviders: ["openai", "deepseek", "openai", " "])
        )

        let yaml = AppSettingsYAMLCodec.encode(settings)
        let decoded = try AppSettingsYAMLCodec.decode(yaml)

        #expect(decoded.appDataVersion == 1)
        #expect(decoded.lastWorkspace == "/tmp/workspace")
        #expect(decoded.runtime.useBundledRuntime == false)
        #expect(decoded.agent.allowedModelProviders == ["openai", "deepseek"])
    }

    /// 验证 AppSettingsStore 通过 FileStore 读写 settings.yaml。
    @Test func settingsStoreLoadsAndSavesSettings() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AgentMac-AppSettingsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileStore = FileStore(rootDirectory: root)
        try fileStore.initialize()
        let store = AppSettingsStore(fileStore: fileStore)

        #expect(try store.loadSettings().agent.allowedModelProviders == ["openai"])

        let saved = try store.saveSettings(AppSettings(
            agent: AgentAppSettings(allowedModelProviders: ["deepseek", "openai"])
        ))

        #expect(saved.agent.allowedModelProviders == ["deepseek", "openai"])
        #expect(try store.loadSettings().agent.allowedModelProviders == ["deepseek", "openai"])
    }

    /// 验证 Settings 页面使用的 provider 清单与当前需要支持的 Pi provider 一致。
    @Test func modelProviderCatalogContainsSupportedProviders() {
        #expect(ModelProviderCatalog.providers.map(\.id) == [
            "anthropic",
            "deepseek",
            "google",
            "kimi-coding",
            "minimax",
            "minimax-cn",
            "moonshotai",
            "moonshotai-cn",
            "openai-codex",
            "xai",
            "xiaomi",
            "xiaomi-token-plan-ams",
            "xiaomi-token-plan-cn",
            "xiaomi-token-plan-sgp",
        ])
        #expect(ModelProviderCatalog.provider(id: "openai-codex")?.supportsAPIKey == false)
        #expect(ModelProviderCatalog.supportsOAuthLogin(id: "anthropic"))
        #expect(ModelProviderCatalog.supportsOAuthLogin(id: "openai-codex"))
        #expect(!ModelProviderCatalog.supportsOAuthLogin(id: "deepseek"))
        #expect(ModelProviderCatalog.provider(id: "deepseek")?.apiKeyEnvironmentVariable == "DEEPSEEK_API_KEY")
    }

    /// 验证 PiAuthStore 会按 Pi auth.json 格式保存 API Key。
    @Test func piAuthStoreSavesAPIKeyCredential() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AgentMac-PiAuthStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileStore = FileStore(rootDirectory: root)
        try fileStore.initialize()
        let store = PiAuthStore(fileStore: fileStore)

        #expect(try store.credentialStatuses(for: ["deepseek"]) == [
            ProviderCredentialStatus(providerID: "deepseek", hasAPIKey: false, hasOAuth: false),
        ])

        let status = try store.saveAPIKey(providerID: "deepseek", apiKey: "  sk-deepseek  ")

        #expect(status == ProviderCredentialStatus(providerID: "deepseek", hasAPIKey: true, hasOAuth: false))
        let authJSON = try fileStore.readTextFile(at: PiAuthStore.authPath)
        #expect(authJSON.contains("\"deepseek\""))
        #expect(authJSON.contains("\"type\" : \"api_key\""))
        #expect(authJSON.contains("\"key\" : \"sk-deepseek\""))
    }

    /// 验证写入 API Key 时会保留其它 OAuth 凭据，删除单个 provider 不影响其它条目。
    @Test func piAuthStorePreservesOtherCredentials() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AgentMac-PiAuthStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileStore = FileStore(rootDirectory: root)
        try fileStore.initialize()
        let store = PiAuthStore(fileStore: fileStore)
        try fileStore.writeTextFile(
            """
            {
              "openai-codex" : {
                "type" : "oauth",
                "access" : "token"
              }
            }
            """,
            to: PiAuthStore.authPath
        )

        try store.saveAPIKey(providerID: "deepseek", apiKey: "sk-deepseek")

        #expect(try store.credentialStatuses(for: ["openai-codex", "deepseek"]) == [
            ProviderCredentialStatus(providerID: "openai-codex", hasAPIKey: false, hasOAuth: true),
            ProviderCredentialStatus(providerID: "deepseek", hasAPIKey: true, hasOAuth: false),
        ])

        let removed = try store.removeCredential(providerID: "deepseek")

        #expect(removed == ProviderCredentialStatus(providerID: "deepseek", hasAPIKey: false, hasOAuth: false))
        #expect(try store.credentialStatuses(for: ["openai-codex", "deepseek"]) == [
            ProviderCredentialStatus(providerID: "openai-codex", hasAPIKey: false, hasOAuth: true),
            ProviderCredentialStatus(providerID: "deepseek", hasAPIKey: false, hasOAuth: false),
        ])
    }
}
