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

    /// 删除 provider 已保存凭据。
    var removeCredential: @Sendable (_ providerID: String) async throws -> ProviderCredentialStatus
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
}
