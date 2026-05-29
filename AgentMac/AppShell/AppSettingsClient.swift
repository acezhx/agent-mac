import ComposableArchitecture
import Foundation

/// AppShell Settings 页面使用的 TCA dependency。
///
/// live 实现内部调用 `AppSettingsStore`，SwiftUI View 和 reducer 只通过该 dependency 访问设置。
nonisolated struct AppSettingsClient: Sendable {
    /// 加载应用设置。
    var loadSettings: @Sendable () async throws -> AppSettings

    /// 保存应用设置。
    var saveSettings: @Sendable (_ settings: AppSettings) async throws -> AppSettings
}

/// AppShell 设置操作对 UI 暴露的结构化错误。
nonisolated struct AppSettingsClientError: Error, Equatable, Sendable {
    /// 可直接用于 UI 展示或测试断言的错误信息。
    let message: String

    /// 创建设置错误。
    ///
    /// - Parameter message: 错误信息。
    init(_ message: String) {
        self.message = message
    }

    /// 从任意错误创建设置错误。
    ///
    /// - Parameter error: 底层错误。
    init(_ error: Error) {
        if let error = error as? AppSettingsClientError {
            self = error
        } else if let localizedDescription = error as? LocalizedError,
                  let description = localizedDescription.errorDescription {
            self.message = description
        } else {
            self.message = error.localizedDescription
        }
    }
}

extension AppSettingsClient: DependencyKey {
    /// live 设置 dependency。
    static let liveValue = AppSettingsClient(
        loadSettings: {
            try await LiveAppSettingsController.shared.loadSettings()
        },
        saveSettings: { settings in
            try await LiveAppSettingsController.shared.saveSettings(settings)
        }
    )

    /// 测试默认值；未显式注入时抛错，避免测试意外访问真实 Application Support。
    static let testValue = AppSettingsClient(
        loadSettings: {
            throw AppSettingsClientError("AppSettingsClient.loadSettings is not implemented for this test.")
        },
        saveSettings: { _ in
            throw AppSettingsClientError("AppSettingsClient.saveSettings is not implemented for this test.")
        }
    )
}

extension DependencyValues {
    /// AppShell 设置 dependency。
    var appSettingsClient: AppSettingsClient {
        get { self[AppSettingsClient.self] }
        set { self[AppSettingsClient.self] = newValue }
    }
}

/// live dependency 使用的设置控制器。
private actor LiveAppSettingsController {
    /// 共享实例。
    static let shared = LiveAppSettingsController()

    private var store: AppSettingsStore?

    /// 加载应用设置。
    func loadSettings() throws -> AppSettings {
        try settingsStore().loadSettings()
    }

    /// 保存应用设置。
    func saveSettings(_ settings: AppSettings) throws -> AppSettings {
        try settingsStore().saveSettings(settings)
    }

    private func settingsStore() throws -> AppSettingsStore {
        if let store {
            return store
        }
        let fileStore = try FileStore()
        try fileStore.initialize()
        let store = AppSettingsStore(fileStore: fileStore)
        self.store = store
        return store
    }
}
