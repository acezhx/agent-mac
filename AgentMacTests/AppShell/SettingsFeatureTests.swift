import ComposableArchitecture
import Testing
@testable import AgentMac

/// AppShell Settings Feature 的状态流转测试。
@MainActor
struct SettingsFeatureTests {
    /// 验证加载设置会同步 provider allowlist 和凭据状态。
    @Test func loadSettingsStoresProvidersAndCredentialStatuses() async {
        let settings = AppSettings(agent: AgentAppSettings(allowedModelProviders: ["openai", "deepseek"]))
        let statuses = [
            ProviderCredentialStatus(providerID: "deepseek", hasAPIKey: true, hasOAuth: false),
            ProviderCredentialStatus(providerID: "openai-codex", hasAPIKey: false, hasOAuth: true),
        ]
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.appSettingsClient = AppSettingsClient(
                loadSettings: { settings },
                saveSettings: { $0 }
            )
            $0.appProviderAuthClient = AppProviderAuthClient(
                loadCredentialStatuses: { providerIDs in
                    #expect(providerIDs.contains("deepseek"))
                    return statuses
                },
                saveAPIKey: { _, _ in
                    Issue.record("load test should not save API keys.")
                    return ProviderCredentialStatus(providerID: "unused", hasAPIKey: false, hasOAuth: false)
                },
                removeCredential: { _ in
                    Issue.record("load test should not remove credentials.")
                    return ProviderCredentialStatus(providerID: "unused", hasAPIKey: false, hasOAuth: false)
                }
            )
        }

        await store.send(.task) {
            $0.isLoading = true
            $0.isLoadingCredentials = true
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        await store.receive(.loadSettingsSucceeded(settings)) {
            $0.isLoading = false
            $0.settings = settings
            $0.allowedModelProviders = ["openai", "deepseek"]
            $0.errorMessage = nil
        }
        await store.receive(.loadCredentialStatusesSucceeded(statuses)) {
            $0.isLoadingCredentials = false
            $0.credentialStatuses = statuses
        }
    }

    /// 验证凭据加载成功不会覆盖设置加载失败的错误。
    @Test func credentialLoadSuccessDoesNotHideSettingsLoadFailure() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.appSettingsClient = AppSettingsClient(
                loadSettings: {
                    throw AppSettingsClientError("settings failed")
                },
                saveSettings: { $0 }
            )
            $0.appProviderAuthClient = AppProviderAuthClient(
                loadCredentialStatuses: { _ in [] },
                saveAPIKey: { _, _ in
                    Issue.record("load failure test should not save API keys.")
                    return ProviderCredentialStatus(providerID: "unused", hasAPIKey: false, hasOAuth: false)
                },
                removeCredential: { _ in
                    Issue.record("load failure test should not remove credentials.")
                    return ProviderCredentialStatus(providerID: "unused", hasAPIKey: false, hasOAuth: false)
                }
            )
        }

        await store.send(.task) {
            $0.isLoading = true
            $0.isLoadingCredentials = true
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        await store.receive(.loadSettingsFailed(AppSettingsClientError("settings failed"))) {
            $0.isLoading = false
            $0.errorMessage = "settings failed"
        }
        await store.receive(.loadCredentialStatusesSucceeded([])) {
            $0.isLoadingCredentials = false
            $0.credentialStatuses = []
        }
    }

    /// 验证连接 API Key 会写入凭据并把 provider 加入 allowlist。
    @Test func saveAPIKeyConnectsProviderAndAllowsProvider() async {
        let recorder = SettingsRecorder()
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.appSettingsClient = AppSettingsClient(
                loadSettings: { .default },
                saveSettings: { settings in
                    recorder.savedSettings.append(settings)
                    return settings
                }
            )
            $0.appProviderAuthClient = AppProviderAuthClient(
                loadCredentialStatuses: { _ in [] },
                saveAPIKey: { providerID, apiKey in
                    recorder.savedAPIKeys.append((providerID, apiKey))
                    return ProviderCredentialStatus(providerID: providerID, hasAPIKey: true, hasOAuth: false)
                },
                removeCredential: { _ in
                    Issue.record("connect test should not remove credentials.")
                    return ProviderCredentialStatus(providerID: "unused", hasAPIKey: false, hasOAuth: false)
                }
            )
        }

        await store.send(.connectProviderButtonTapped("deepseek")) {
            $0.apiKeyForm = ProviderAPIKeyForm(provider: ModelProviderCatalog.provider(id: "deepseek")!)
            $0.apiKeyInput = ""
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        await store.send(.apiKeyInputChanged("  sk-deepseek  ")) {
            $0.apiKeyInput = "  sk-deepseek  "
        }
        await store.send(.saveAPIKeyButtonTapped) {
            $0.isSavingAPIKey = true
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        let savedStatus = ProviderCredentialStatus(providerID: "deepseek", hasAPIKey: true, hasOAuth: false)
        let savedSettings = AppSettings(agent: AgentAppSettings(allowedModelProviders: ["openai", "deepseek"]))
        await store.receive(.saveAPIKeySucceeded(savedStatus, savedSettings)) {
            $0.isSavingAPIKey = false
            $0.apiKeyForm = nil
            $0.apiKeyInput = ""
            $0.settings = savedSettings
            $0.allowedModelProviders = ["openai", "deepseek"]
            $0.credentialStatuses = [savedStatus]
            $0.errorMessage = nil
            $0.successMessage = "deepseek connected."
        }

        #expect(recorder.savedAPIKeys.count == 1)
        #expect(recorder.savedAPIKeys.first?.providerID == "deepseek")
        #expect(recorder.savedAPIKeys.first?.apiKey == "  sk-deepseek  ")
        #expect(recorder.savedSettings.map(\.agent.allowedModelProviders) == [["openai", "deepseek"]])
    }

    /// 验证设置保存失败时不会写入 API Key 凭据。
    @Test func saveAPIKeyDoesNotWriteCredentialWhenSettingsSaveFails() async {
        let recorder = SettingsRecorder()
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.appSettingsClient = AppSettingsClient(
                loadSettings: { .default },
                saveSettings: { settings in
                    recorder.savedSettings.append(settings)
                    throw AppProviderAuthClientError("settings failed")
                }
            )
            $0.appProviderAuthClient = AppProviderAuthClient(
                loadCredentialStatuses: { _ in [] },
                saveAPIKey: { _, _ in
                    Issue.record("settings failure should not save API keys.")
                    return ProviderCredentialStatus(providerID: "unused", hasAPIKey: false, hasOAuth: false)
                },
                removeCredential: { _ in
                    Issue.record("settings failure should not remove credentials.")
                    return ProviderCredentialStatus(providerID: "unused", hasAPIKey: false, hasOAuth: false)
                }
            )
        }

        await store.send(.connectProviderButtonTapped("deepseek")) {
            $0.apiKeyForm = ProviderAPIKeyForm(provider: ModelProviderCatalog.provider(id: "deepseek")!)
            $0.apiKeyInput = ""
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        await store.send(.apiKeyInputChanged("sk-deepseek")) {
            $0.apiKeyInput = "sk-deepseek"
        }
        await store.send(.saveAPIKeyButtonTapped) {
            $0.isSavingAPIKey = true
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        await store.receive(.saveAPIKeyFailed(AppProviderAuthClientError("settings failed"))) {
            $0.isSavingAPIKey = false
            $0.errorMessage = "settings failed"
        }

        #expect(recorder.savedAPIKeys.isEmpty)
        #expect(recorder.savedSettings.map(\.agent.allowedModelProviders) == [["openai", "deepseek"]])
    }

    /// 验证 API Key 写入失败时会回滚已保存的 allowlist。
    @Test func saveAPIKeyRollsBackSettingsWhenCredentialSaveFails() async {
        let recorder = SettingsRecorder()
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.appSettingsClient = AppSettingsClient(
                loadSettings: { .default },
                saveSettings: { settings in
                    recorder.savedSettings.append(settings)
                    return settings
                }
            )
            $0.appProviderAuthClient = AppProviderAuthClient(
                loadCredentialStatuses: { _ in [] },
                saveAPIKey: { providerID, apiKey in
                    recorder.savedAPIKeys.append((providerID, apiKey))
                    throw AppProviderAuthClientError("auth failed")
                },
                removeCredential: { _ in
                    Issue.record("credential failure rollback should not remove credentials.")
                    return ProviderCredentialStatus(providerID: "unused", hasAPIKey: false, hasOAuth: false)
                }
            )
        }

        await store.send(.connectProviderButtonTapped("deepseek")) {
            $0.apiKeyForm = ProviderAPIKeyForm(provider: ModelProviderCatalog.provider(id: "deepseek")!)
            $0.apiKeyInput = ""
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        await store.send(.apiKeyInputChanged("sk-deepseek")) {
            $0.apiKeyInput = "sk-deepseek"
        }
        await store.send(.saveAPIKeyButtonTapped) {
            $0.isSavingAPIKey = true
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        await store.receive(.saveAPIKeyFailed(AppProviderAuthClientError("auth failed"))) {
            $0.isSavingAPIKey = false
            $0.errorMessage = "auth failed"
        }

        #expect(recorder.savedAPIKeys.first?.providerID == "deepseek")
        #expect(recorder.savedSettings.map(\.agent.allowedModelProviders) == [
            ["openai", "deepseek"],
            ["openai"],
        ])
    }

    /// 验证断开 provider 会删除凭据并从 allowlist 移除。
    @Test func disconnectProviderRemovesCredentialAndProvider() async {
        let recorder = SettingsRecorder()
        let initialSettings = AppSettings(agent: AgentAppSettings(allowedModelProviders: ["openai", "deepseek"]))
        var initialState = SettingsFeature.State()
        initialState.populate(with: initialSettings)
        initialState.credentialStatuses = [
            ProviderCredentialStatus(providerID: "deepseek", hasAPIKey: true, hasOAuth: false),
        ]

        let store = TestStore(initialState: initialState) {
            SettingsFeature()
        } withDependencies: {
            $0.appSettingsClient = AppSettingsClient(
                loadSettings: { initialSettings },
                saveSettings: { settings in
                    recorder.savedSettings.append(settings)
                    return settings
                }
            )
            $0.appProviderAuthClient = AppProviderAuthClient(
                loadCredentialStatuses: { _ in [] },
                saveAPIKey: { _, _ in
                    Issue.record("disconnect test should not save API keys.")
                    return ProviderCredentialStatus(providerID: "unused", hasAPIKey: false, hasOAuth: false)
                },
                removeCredential: { providerID in
                    recorder.removedProviderIDs.append(providerID)
                    return ProviderCredentialStatus(providerID: providerID, hasAPIKey: false, hasOAuth: false)
                }
            )
        }

        await store.send(.disconnectProviderButtonTapped("deepseek")) {
            $0.isRemovingCredential = true
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        let removedStatus = ProviderCredentialStatus(providerID: "deepseek", hasAPIKey: false, hasOAuth: false)
        let savedSettings = AppSettings(agent: AgentAppSettings(allowedModelProviders: ["openai"]))
        await store.receive(.removeCredentialSucceeded(removedStatus, savedSettings)) {
            $0.isRemovingCredential = false
            $0.settings = savedSettings
            $0.allowedModelProviders = ["openai"]
            $0.credentialStatuses = [removedStatus]
            $0.errorMessage = nil
            $0.successMessage = "deepseek disconnected."
        }

        #expect(recorder.removedProviderIDs == ["deepseek"])
        #expect(recorder.savedSettings.map(\.agent.allowedModelProviders) == [["openai"]])
    }

    /// 验证设置保存失败时不会删除 provider 凭据。
    @Test func disconnectProviderDoesNotRemoveCredentialWhenSettingsSaveFails() async {
        let recorder = SettingsRecorder()
        let initialSettings = AppSettings(agent: AgentAppSettings(allowedModelProviders: ["openai", "deepseek"]))
        var initialState = SettingsFeature.State()
        initialState.populate(with: initialSettings)
        initialState.credentialStatuses = [
            ProviderCredentialStatus(providerID: "deepseek", hasAPIKey: true, hasOAuth: false),
        ]

        let store = TestStore(initialState: initialState) {
            SettingsFeature()
        } withDependencies: {
            $0.appSettingsClient = AppSettingsClient(
                loadSettings: { initialSettings },
                saveSettings: { settings in
                    recorder.savedSettings.append(settings)
                    throw AppProviderAuthClientError("settings failed")
                }
            )
            $0.appProviderAuthClient = AppProviderAuthClient(
                loadCredentialStatuses: { _ in [] },
                saveAPIKey: { _, _ in
                    Issue.record("disconnect settings failure should not save API keys.")
                    return ProviderCredentialStatus(providerID: "unused", hasAPIKey: false, hasOAuth: false)
                },
                removeCredential: { providerID in
                    recorder.removedProviderIDs.append(providerID)
                    return ProviderCredentialStatus(providerID: providerID, hasAPIKey: false, hasOAuth: false)
                }
            )
        }

        await store.send(.disconnectProviderButtonTapped("deepseek")) {
            $0.isRemovingCredential = true
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        await store.receive(.removeCredentialFailed(AppProviderAuthClientError("settings failed"))) {
            $0.isRemovingCredential = false
            $0.errorMessage = "settings failed"
        }

        #expect(recorder.removedProviderIDs.isEmpty)
        #expect(recorder.savedSettings.map(\.agent.allowedModelProviders) == [["openai"]])
    }

    /// 验证凭据删除失败时会回滚已保存的 allowlist。
    @Test func disconnectProviderRollsBackSettingsWhenCredentialRemoveFails() async {
        let recorder = SettingsRecorder()
        let initialSettings = AppSettings(agent: AgentAppSettings(allowedModelProviders: ["openai", "deepseek"]))
        var initialState = SettingsFeature.State()
        initialState.populate(with: initialSettings)
        initialState.credentialStatuses = [
            ProviderCredentialStatus(providerID: "deepseek", hasAPIKey: true, hasOAuth: false),
        ]

        let store = TestStore(initialState: initialState) {
            SettingsFeature()
        } withDependencies: {
            $0.appSettingsClient = AppSettingsClient(
                loadSettings: { initialSettings },
                saveSettings: { settings in
                    recorder.savedSettings.append(settings)
                    return settings
                }
            )
            $0.appProviderAuthClient = AppProviderAuthClient(
                loadCredentialStatuses: { _ in [] },
                saveAPIKey: { _, _ in
                    Issue.record("disconnect rollback should not save API keys.")
                    return ProviderCredentialStatus(providerID: "unused", hasAPIKey: false, hasOAuth: false)
                },
                removeCredential: { providerID in
                    recorder.removedProviderIDs.append(providerID)
                    throw AppProviderAuthClientError("remove failed")
                }
            )
        }

        await store.send(.disconnectProviderButtonTapped("deepseek")) {
            $0.isRemovingCredential = true
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        await store.receive(.removeCredentialFailed(AppProviderAuthClientError("remove failed"))) {
            $0.isRemovingCredential = false
            $0.errorMessage = "remove failed"
        }

        #expect(recorder.removedProviderIDs == ["deepseek"])
        #expect(recorder.savedSettings.map(\.agent.allowedModelProviders) == [
            ["openai"],
            ["openai", "deepseek"],
        ])
    }
}

private final class SettingsRecorder: @unchecked Sendable {
    /// 保存收到的设置。
    var savedSettings: [AppSettings] = []

    /// 保存收到的 API Key。
    var savedAPIKeys: [(providerID: String, apiKey: String)] = []

    /// 删除收到的 provider ID。
    var removedProviderIDs: [String] = []
}
