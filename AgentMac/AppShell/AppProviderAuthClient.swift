import AppKit
import ComposableArchitecture
import Foundation

/// AppShell Settings 页面使用的模型 provider 授权 dependency。
///
/// live 实现内部调用 `PiAuthStore`，SwiftUI View 和 reducer 只通过该 dependency 访问 Pi 认证文件。
nonisolated struct AppProviderAuthClient: Sendable {
    /// 加载 provider 凭据状态。
    var loadCredentialStatuses: @Sendable (_ providerIDs: [String]) async throws -> [ProviderCredentialStatus]

    /// 保存 provider API Key。
    var saveAPIKey: @Sendable (_ providerID: String, _ apiKey: String) async throws -> ProviderCredentialStatus

    /// 通过 OAuth/订阅账号登录 provider。
    var loginOAuth: @Sendable (_ providerID: String) async throws -> ProviderCredentialStatus

    /// 删除 provider 已保存凭据。
    var removeCredential: @Sendable (_ providerID: String) async throws -> ProviderCredentialStatus

    /// 创建 provider 授权 dependency。
    ///
    /// - Parameters:
    ///   - loadCredentialStatuses: 加载 provider 凭据状态的操作。
    ///   - saveAPIKey: 保存 provider API Key 的操作。
    ///   - loginOAuth: 执行 provider OAuth 登录的操作；未注入时抛出测试错误。
    ///   - removeCredential: 删除 provider 凭据的操作。
    init(
        loadCredentialStatuses: @escaping @Sendable (_ providerIDs: [String]) async throws -> [ProviderCredentialStatus],
        saveAPIKey: @escaping @Sendable (_ providerID: String, _ apiKey: String) async throws -> ProviderCredentialStatus,
        loginOAuth: @escaping @Sendable (_ providerID: String) async throws -> ProviderCredentialStatus = { _ in
            throw AppProviderAuthClientError("AppProviderAuthClient.loginOAuth is not implemented for this test.")
        },
        removeCredential: @escaping @Sendable (_ providerID: String) async throws -> ProviderCredentialStatus
    ) {
        self.loadCredentialStatuses = loadCredentialStatuses
        self.saveAPIKey = saveAPIKey
        self.loginOAuth = loginOAuth
        self.removeCredential = removeCredential
    }
}

/// AppShell provider 授权操作对 UI 暴露的结构化错误。
nonisolated struct AppProviderAuthClientError: Error, Equatable, Sendable {
    /// 可直接用于 UI 展示或测试断言的错误信息。
    let message: String

    /// 创建授权错误。
    ///
    /// - Parameter message: 错误信息。
    init(_ message: String) {
        self.message = message
    }

    /// 从任意错误创建授权错误。
    ///
    /// - Parameter error: 底层错误。
    init(_ error: Error) {
        if let error = error as? AppProviderAuthClientError {
            self = error
        } else if error is RuntimeBridgeError || error is SessionError {
            self.message = AppSessionClientError(error).message
        } else if let localizedDescription = error as? LocalizedError,
                  let description = localizedDescription.errorDescription {
            self.message = description
        } else {
            self.message = error.localizedDescription
        }
    }
}

extension AppProviderAuthClient: DependencyKey {
    /// live provider 授权 dependency。
    static let liveValue = AppProviderAuthClient(
        loadCredentialStatuses: { providerIDs in
            try await LiveProviderAuthController.shared.loadCredentialStatuses(for: providerIDs)
        },
        saveAPIKey: { providerID, apiKey in
            try await LiveProviderAuthController.shared.saveAPIKey(providerID: providerID, apiKey: apiKey)
        },
        loginOAuth: { providerID in
            try await LiveProviderAuthController.shared.loginOAuth(providerID: providerID)
        },
        removeCredential: { providerID in
            try await LiveProviderAuthController.shared.removeCredential(providerID: providerID)
        }
    )

    /// 测试默认值；未显式注入时抛错，避免测试意外访问真实 Application Support。
    static let testValue = AppProviderAuthClient(
        loadCredentialStatuses: { _ in
            throw AppProviderAuthClientError("AppProviderAuthClient.loadCredentialStatuses is not implemented for this test.")
        },
        saveAPIKey: { _, _ in
            throw AppProviderAuthClientError("AppProviderAuthClient.saveAPIKey is not implemented for this test.")
        },
        loginOAuth: { _ in
            throw AppProviderAuthClientError("AppProviderAuthClient.loginOAuth is not implemented for this test.")
        },
        removeCredential: { _ in
            throw AppProviderAuthClientError("AppProviderAuthClient.removeCredential is not implemented for this test.")
        }
    )
}

extension DependencyValues {
    /// AppShell provider 授权 dependency。
    var appProviderAuthClient: AppProviderAuthClient {
        get { self[AppProviderAuthClient.self] }
        set { self[AppProviderAuthClient.self] = newValue }
    }
}

/// live dependency 使用的 provider 授权控制器。
private actor LiveProviderAuthController {
    /// 共享实例。
    static let shared = LiveProviderAuthController()

    private var store: PiAuthStore?

    /// 加载 provider 凭据状态。
    func loadCredentialStatuses(for providerIDs: [String]) throws -> [ProviderCredentialStatus] {
        try authStore().credentialStatuses(for: providerIDs)
    }

    /// 保存 provider API Key。
    func saveAPIKey(providerID: String, apiKey: String) throws -> ProviderCredentialStatus {
        try authStore().saveAPIKey(providerID: providerID, apiKey: apiKey)
    }

    /// 通过 Pi RuntimeHost 执行 provider OAuth 登录。
    func loginOAuth(providerID: String) async throws -> ProviderCredentialStatus {
        guard ModelProviderCatalog.supportsOAuthLogin(id: providerID) else {
            throw AppProviderAuthClientError("OAuth login currently supports Anthropic and OpenAI Codex only.")
        }

        let store = try authStore()
        let bridge = RuntimeBridge(configuration: try AppRuntimeBridgeConfigurationFactory.make(fileStore: store.fileStore))
        try bridge.start()
        defer {
            bridge.stop()
        }
        _ = try bridge.ping()

        let commandID = "cmd_oauth_\(UUID().uuidString)"
        try bridge.send(RuntimeCommand(
            id: commandID,
            name: "loginOAuthProvider",
            payload: .object(["providerID": .string(providerID)])
        ))

        let deadline = Date().addingTimeInterval(300)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                throw RuntimeBridgeError.eventReadTimeout(seconds: 300)
            }
            let event = try bridge.readEvent(timeout: remaining)
            guard event.replyTo == commandID || event.replyTo == nil else {
                continue
            }
            if let runtimeError = runtimeError(from: event) {
                throw runtimeError
            }

            switch event.name {
            case "oauthAuthorizationRequested":
                try await openOAuthAuthorizationURL(from: event)
            case "oauthLoginCompleted":
                return try statusAfterOAuthLogin(providerID: providerID, store: store)
            case "oauthProgressUpdated", "oauthDeviceCodeRequested":
                continue
            default:
                continue
            }
        }
    }

    /// 删除 provider 已保存凭据。
    func removeCredential(providerID: String) throws -> ProviderCredentialStatus {
        try authStore().removeCredential(providerID: providerID)
    }

    private func authStore() throws -> PiAuthStore {
        if let store {
            return store
        }
        let fileStore = try FileStore()
        try fileStore.initialize()
        let store = PiAuthStore(fileStore: fileStore)
        self.store = store
        return store
    }

    private func openOAuthAuthorizationURL(from event: RuntimeEvent) async throws {
        guard let urlString = event.payload?["url"]?.stringValue,
              let url = URL(string: urlString)
        else {
            throw AppProviderAuthClientError("Runtime Host did not provide a valid OAuth authorization URL.")
        }

        let opened = await MainActor.run {
            NSWorkspace.shared.open(url)
        }
        guard opened else {
            throw AppProviderAuthClientError("AgentMac could not open the OAuth authorization URL in the browser.")
        }
    }

    private func statusAfterOAuthLogin(providerID: String, store: PiAuthStore) throws -> ProviderCredentialStatus {
        let status = try store.credentialStatuses(for: [providerID]).first
            ?? ProviderCredentialStatus(providerID: providerID, hasAPIKey: false, hasOAuth: false)
        guard status.hasOAuth else {
            throw AppProviderAuthClientError("OAuth login completed but no OAuth credential was saved for \(providerID).")
        }
        return status
    }

    private func runtimeError(from event: RuntimeEvent) -> RuntimeBridgeError? {
        guard event.name == "error", let payload = event.payload else {
            return nil
        }

        return RuntimeBridgeError.runtimeError(
            code: payload["code"]?.stringValue ?? "oauth_failed",
            message: payload["message"]?.stringValue ?? "OAuth login failed.",
            recoverable: payload["recoverable"]?.boolValue ?? true,
            details: payload["details"]
        )
    }
}
