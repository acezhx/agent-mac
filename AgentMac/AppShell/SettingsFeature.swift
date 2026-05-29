import ComposableArchitecture
import Foundation

/// Provider API Key 表单状态。
nonisolated struct ProviderAPIKeyForm: Equatable, Identifiable, Sendable {
    /// 要连接的 provider。
    var provider: ModelProviderDefinition

    /// SwiftUI sheet 使用的稳定 ID。
    var id: String {
        provider.id
    }
}

/// Settings 页面 Feature。
///
/// 该 Feature 只管理 app 级设置和 provider 授权的 UI 状态。设置文件和 Pi auth 文件读写通过
/// TCA dependency 注入。
@Reducer
struct SettingsFeature {
    /// Settings 页面状态。
    @ObservableState
    struct State: Equatable {
        /// 当前加载的完整设置，用于保存未在 UI 中编辑的字段。
        var settings: AppSettings

        /// Agent 允许使用的模型 provider。
        var allowedModelProviders: [String]

        /// Provider 凭据状态。
        var credentialStatuses: [ProviderCredentialStatus]

        /// 当前展示的 API Key 输入表单。
        var apiKeyForm: ProviderAPIKeyForm?

        /// API Key 输入框内容。
        var apiKeyInput: String

        /// 最近一次操作错误。
        var errorMessage: String?

        /// 最近一次操作成功提示。
        var successMessage: String?

        /// 是否正在加载设置。
        var isLoading: Bool

        /// 是否正在加载 provider 凭据状态。
        var isLoadingCredentials: Bool

        /// 是否正在保存设置。
        var isSaving: Bool

        /// 是否正在保存 API Key。
        var isSavingAPIKey: Bool

        /// 是否正在执行 OAuth 登录。
        var isLoggingInOAuth: Bool

        /// 当前正在执行 OAuth 登录的 provider ID。
        var loggingInOAuthProviderID: String?

        /// 是否正在删除 provider 凭据。
        var isRemovingCredential: Bool

        /// 创建 Settings 页面状态。
        init() {
            self.settings = .default
            self.allowedModelProviders = AppSettings.defaultAllowedModelProviders
            self.credentialStatuses = []
            self.apiKeyForm = nil
            self.apiKeyInput = ""
            self.errorMessage = nil
            self.successMessage = nil
            self.isLoading = false
            self.isLoadingCredentials = false
            self.isSaving = false
            self.isSavingAPIKey = false
            self.isLoggingInOAuth = false
            self.loggingInOAuthProviderID = nil
            self.isRemovingCredential = false
        }

        /// 是否有设置操作正在运行。
        var hasOperationInFlight: Bool {
            isLoading || isLoadingCredentials || isSaving || isSavingAPIKey || isLoggingInOAuth || isRemovingCredential
        }

        /// 是否可以保存当前 API Key 表单。
        var canSaveAPIKey: Bool {
            apiKeyForm != nil
                && !hasOperationInFlight
                && !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// 用设置模型填充 UI 状态。
        ///
        /// - Parameter settings: 应用设置。
        mutating func populate(with settings: AppSettings) {
            self.settings = settings
            self.allowedModelProviders = settings.agent.allowedModelProviders
        }

        /// 用 provider 凭据状态填充 UI 状态。
        ///
        /// - Parameter statuses: 当前 Pi auth 文件中的凭据状态。
        mutating func populateCredentialStatuses(_ statuses: [ProviderCredentialStatus]) {
            credentialStatuses = statuses
        }

        /// 生成添加 provider 后的设置模型。
        ///
        /// - Parameter providerID: 要允许 Agent 使用的 provider。
        /// - Returns: 待保存的应用设置。
        func settingsAllowingProvider(_ providerID: String) -> AppSettings {
            var edited = settings
            var providers = allowedModelProviders
            if !providers.contains(providerID) {
                providers.append(providerID)
            }
            edited.agent.allowedModelProviders = providers
            return edited
        }

        /// 生成移除 provider 后的设置模型。
        ///
        /// - Parameter providerID: 要从 Agent 可用 provider 列表移除的 provider。
        /// - Returns: 待保存的应用设置。
        func settingsRemovingProvider(_ providerID: String) -> AppSettings {
            var edited = settings
            edited.agent.allowedModelProviders = allowedModelProviders.filter { $0 != providerID }
            return edited
        }

        /// 查询 provider 凭据状态。
        ///
        /// - Parameter providerID: Pi provider ID。
        /// - Returns: 已加载状态；没有状态时返回未连接。
        func credentialStatus(for providerID: String) -> ProviderCredentialStatus {
            credentialStatuses.first { $0.providerID == providerID }
                ?? ProviderCredentialStatus(providerID: providerID, hasAPIKey: false, hasOAuth: false)
        }

        /// 插入或替换 provider 凭据状态。
        ///
        /// - Parameter status: 最新状态。
        mutating func upsertCredentialStatus(_ status: ProviderCredentialStatus) {
            credentialStatuses.removeAll { $0.providerID == status.providerID }
            credentialStatuses.append(status)
        }
    }

    /// Settings 页面 action。
    enum Action: Equatable {
        /// 页面进入时触发。
        case task

        /// 用户点击刷新。
        case refreshButtonTapped

        /// 设置加载成功。
        case loadSettingsSucceeded(AppSettings)

        /// 设置加载失败。
        case loadSettingsFailed(AppSettingsClientError)

        /// Provider 凭据状态加载成功。
        case loadCredentialStatusesSucceeded([ProviderCredentialStatus])

        /// Provider 凭据状态加载失败。
        case loadCredentialStatusesFailed(AppProviderAuthClientError)

        /// 用户点击连接 provider。
        case connectProviderButtonTapped(String)

        /// API Key 输入变化。
        case apiKeyInputChanged(String)

        /// API Key 表单关闭。
        case apiKeyFormDismissed

        /// 用户点击保存 API Key。
        case saveAPIKeyButtonTapped

        /// API Key 保存成功。
        case saveAPIKeySucceeded(ProviderCredentialStatus, AppSettings)

        /// API Key 保存失败。
        case saveAPIKeyFailed(AppProviderAuthClientError)

        /// 用户点击 OAuth/订阅授权连接 provider。
        case loginOAuthProviderButtonTapped(String)

        /// OAuth/订阅授权登录成功。
        case loginOAuthSucceeded(ProviderCredentialStatus, AppSettings)

        /// OAuth/订阅授权登录失败。
        case loginOAuthFailed(AppProviderAuthClientError)

        /// 用户点击断开 provider。
        case disconnectProviderButtonTapped(String)

        /// Provider 凭据删除成功。
        case removeCredentialSucceeded(ProviderCredentialStatus, AppSettings)

        /// Provider 凭据删除失败。
        case removeCredentialFailed(AppProviderAuthClientError)
    }

    private nonisolated enum CancelID: Hashable {
        case load
    }

    /// Settings 页面 reducer。
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task, .refreshButtonTapped:
                state.isLoading = true
                state.isLoadingCredentials = true
                state.errorMessage = nil
                state.successMessage = nil
                return loadPageDataEffect()

            case let .loadSettingsSucceeded(settings):
                state.isLoading = false
                state.populate(with: settings)
                return .none

            case let .loadSettingsFailed(error):
                state.isLoading = false
                state.errorMessage = error.message
                return .none

            case let .loadCredentialStatusesSucceeded(statuses):
                state.isLoadingCredentials = false
                state.populateCredentialStatuses(statuses)
                return .none

            case let .loadCredentialStatusesFailed(error):
                state.isLoadingCredentials = false
                state.errorMessage = error.message
                return .none

            case let .connectProviderButtonTapped(providerID):
                guard !state.hasOperationInFlight,
                      let provider = ModelProviderCatalog.provider(id: providerID),
                      provider.supportsAPIKey
                else {
                    return .none
                }
                state.apiKeyForm = ProviderAPIKeyForm(provider: provider)
                state.apiKeyInput = ""
                state.errorMessage = nil
                state.successMessage = nil
                return .none

            case let .apiKeyInputChanged(apiKey):
                state.apiKeyInput = apiKey
                return .none

            case .apiKeyFormDismissed:
                state.apiKeyForm = nil
                state.apiKeyInput = ""
                state.errorMessage = nil
                return .none

            case .saveAPIKeyButtonTapped:
                guard state.canSaveAPIKey,
                      let form = state.apiKeyForm
                else {
                    return .none
                }
                state.isSavingAPIKey = true
                state.errorMessage = nil
                state.successMessage = nil
                let providerID = form.provider.id
                let apiKey = state.apiKeyInput
                let previousSettings = state.settings
                let settings = state.settingsAllowingProvider(providerID)
                @Dependency(AppSettingsClient.self) var appSettingsClient
                @Dependency(AppProviderAuthClient.self) var appProviderAuthClient
                return .run { send in
                    do {
                        let savedSettings = try await appSettingsClient.saveSettings(settings)
                        do {
                            let status = try await appProviderAuthClient.saveAPIKey(providerID, apiKey)
                            await send(.saveAPIKeySucceeded(status, savedSettings))
                        } catch {
                            _ = try? await appSettingsClient.saveSettings(previousSettings)
                            await send(.saveAPIKeyFailed(AppProviderAuthClientError(error)))
                        }
                    } catch {
                        await send(.saveAPIKeyFailed(AppProviderAuthClientError(error)))
                    }
                }

            case let .saveAPIKeySucceeded(status, settings):
                state.isSavingAPIKey = false
                state.apiKeyForm = nil
                state.apiKeyInput = ""
                state.populate(with: settings)
                state.upsertCredentialStatus(status)
                state.errorMessage = nil
                state.successMessage = "\(status.providerID) connected."
                return .none

            case let .saveAPIKeyFailed(error):
                state.isSavingAPIKey = false
                state.errorMessage = error.message
                return .none

            case let .loginOAuthProviderButtonTapped(providerID):
                guard !state.hasOperationInFlight,
                      let provider = ModelProviderCatalog.provider(id: providerID),
                      provider.supportsOAuth,
                      ModelProviderCatalog.supportsOAuthLogin(id: providerID)
                else {
                    return .none
                }
                state.isLoggingInOAuth = true
                state.loggingInOAuthProviderID = providerID
                state.errorMessage = nil
                state.successMessage = nil
                let previousSettings = state.settings
                let settings = state.settingsAllowingProvider(providerID)
                @Dependency(AppSettingsClient.self) var appSettingsClient
                @Dependency(AppProviderAuthClient.self) var appProviderAuthClient
                return .run { send in
                    do {
                        let savedSettings = try await appSettingsClient.saveSettings(settings)
                        do {
                            let status = try await appProviderAuthClient.loginOAuth(providerID)
                            await send(.loginOAuthSucceeded(status, savedSettings))
                        } catch {
                            _ = try? await appSettingsClient.saveSettings(previousSettings)
                            await send(.loginOAuthFailed(AppProviderAuthClientError(error)))
                        }
                    } catch {
                        await send(.loginOAuthFailed(AppProviderAuthClientError(error)))
                    }
                }

            case let .loginOAuthSucceeded(status, settings):
                state.isLoggingInOAuth = false
                state.loggingInOAuthProviderID = nil
                state.populate(with: settings)
                state.upsertCredentialStatus(status)
                state.errorMessage = nil
                state.successMessage = "\(status.providerID) connected."
                return .none

            case let .loginOAuthFailed(error):
                state.isLoggingInOAuth = false
                state.loggingInOAuthProviderID = nil
                state.errorMessage = error.message
                return .none

            case let .disconnectProviderButtonTapped(providerID):
                guard !state.hasOperationInFlight else {
                    return .none
                }
                state.isRemovingCredential = true
                state.errorMessage = nil
                state.successMessage = nil
                let previousSettings = state.settings
                let settings = state.settingsRemovingProvider(providerID)
                @Dependency(AppSettingsClient.self) var appSettingsClient
                @Dependency(AppProviderAuthClient.self) var appProviderAuthClient
                return .run { send in
                    do {
                        let savedSettings = try await appSettingsClient.saveSettings(settings)
                        do {
                            let status = try await appProviderAuthClient.removeCredential(providerID)
                            await send(.removeCredentialSucceeded(status, savedSettings))
                        } catch {
                            _ = try? await appSettingsClient.saveSettings(previousSettings)
                            await send(.removeCredentialFailed(AppProviderAuthClientError(error)))
                        }
                    } catch {
                        await send(.removeCredentialFailed(AppProviderAuthClientError(error)))
                    }
                }

            case let .removeCredentialSucceeded(status, settings):
                state.isRemovingCredential = false
                state.populate(with: settings)
                state.upsertCredentialStatus(status)
                state.errorMessage = nil
                state.successMessage = "\(status.providerID) disconnected."
                return .none

            case let .removeCredentialFailed(error):
                state.isRemovingCredential = false
                state.errorMessage = error.message
                return .none
            }
        }
    }

    private func loadPageDataEffect() -> Effect<Action> {
        @Dependency(AppSettingsClient.self) var appSettingsClient
        @Dependency(AppProviderAuthClient.self) var appProviderAuthClient
        return .run { send in
            do {
                let settings = try await appSettingsClient.loadSettings()
                await send(.loadSettingsSucceeded(settings))
            } catch {
                await send(.loadSettingsFailed(AppSettingsClientError(error)))
            }

            do {
                let statuses = try await appProviderAuthClient.loadCredentialStatuses(
                    ModelProviderCatalog.providers.map(\.id)
                )
                await send(.loadCredentialStatusesSucceeded(statuses))
            } catch {
                await send(.loadCredentialStatusesFailed(AppProviderAuthClientError(error)))
            }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }
}
