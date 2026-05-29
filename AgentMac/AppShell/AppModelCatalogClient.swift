import ComposableArchitecture
import Foundation

/// Agent 编辑页使用的模型摘要。
nonisolated struct AppModelSummary: Equatable, Identifiable, Sendable {
    /// Pi provider ID。
    let providerID: String

    /// Pi model ID。
    let modelID: String

    /// UI 展示名称。
    let displayName: String

    /// 模型是否支持 reasoning/thinking。
    let supportsReasoning: Bool

    /// Pi 支持的 thinking level 列表。
    let supportedThinkingLevels: [String]

    /// 跨 provider 唯一的模型标识。
    var id: String {
        "\(providerID)/\(modelID)"
    }
}

/// AppShell Agent 编辑页使用的模型清单 dependency。
nonisolated struct AppModelCatalogClient: Sendable {
    /// 加载指定 provider 的模型清单。
    var loadModels: @Sendable (_ providerIDs: [String]) async throws -> [AppModelSummary]
}

/// AppShell dependency 对模型清单 UI 暴露的结构化错误。
nonisolated struct AppModelCatalogClientError: Error, Equatable, Sendable {
    /// 可直接用于 UI 展示或测试断言的错误信息。
    let message: String

    /// 创建模型清单错误。
    ///
    /// - Parameter message: 错误信息。
    init(_ message: String) {
        self.message = message
    }

    /// 从底层错误创建模型清单错误。
    ///
    /// - Parameter error: 底层服务错误。
    init(_ error: Error) {
        if let error = error as? AppModelCatalogClientError {
            self.message = error.message
        } else if let runtimeBridgeError = error as? RuntimeBridgeError {
            self.message = runtimeBridgeError.localizedDescription
        } else if let localizedError = error as? LocalizedError,
                  let description = localizedError.errorDescription {
            self.message = description
        } else {
            self.message = error.localizedDescription
        }
    }
}

extension AppModelCatalogClientError: LocalizedError {
    /// 面向 UI 的错误描述。
    var errorDescription: String? {
        message
    }
}

extension AppModelCatalogClient: DependencyKey {
    /// App 运行时使用的真实 dependency。
    static let liveValue: AppModelCatalogClient = {
        let controller = LiveModelCatalogController()
        return AppModelCatalogClient(
            loadModels: { providerIDs in
                try await controller.loadModels(providerIDs: providerIDs)
            }
        )
    }()

    /// 测试默认值；具体测试应显式注入 mock。
    static let testValue = AppModelCatalogClient(
        loadModels: { _ in
            throw AppModelCatalogClientError("AppModelCatalogClient.loadModels is not implemented for this test.")
        }
    )
}

extension DependencyValues {
    /// AppShell 模型清单 dependency。
    var appModelCatalogClient: AppModelCatalogClient {
        get { self[AppModelCatalogClient.self] }
        set { self[AppModelCatalogClient.self] = newValue }
    }
}

/// live dependency 使用的模型清单控制器。
private actor LiveModelCatalogController {
    /// 加载指定 provider 的模型清单。
    ///
    /// - Parameter providerIDs: 需要返回模型的 provider ID。
    /// - Returns: RuntimeHost/Pi 返回的模型摘要。
    func loadModels(providerIDs: [String]) throws -> [AppModelSummary] {
        let fileStore = try FileStore()
        try fileStore.initialize()
        let bridge = RuntimeBridge(configuration: try AppRuntimeBridgeConfigurationFactory.make(fileStore: fileStore))
        try bridge.start()
        defer {
            bridge.stop()
        }
        _ = try bridge.ping()
        let event = try bridge.listModelCatalog(providerIDs: providerIDs)
        return try Self.modelSummaries(from: event)
    }

    private static func modelSummaries(from event: RuntimeEvent) throws -> [AppModelSummary] {
        guard case let .array(modelValues)? = event.payload?["models"] else {
            throw AppModelCatalogClientError("Runtime Host did not return a valid model catalog.")
        }

        return modelValues.compactMap { value in
            guard case let .object(fields) = value,
                  let providerID = fields["providerID"]?.stringValue,
                  let modelID = fields["id"]?.stringValue,
                  !providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }

            let supportedThinkingLevels: [String]
            if case let .array(levelValues)? = fields["supportedThinkingLevels"] {
                supportedThinkingLevels = levelValues.compactMap(\.stringValue)
            } else {
                supportedThinkingLevels = []
            }

            return AppModelSummary(
                providerID: providerID,
                modelID: modelID,
                displayName: fields["name"]?.stringValue ?? modelID,
                supportsReasoning: fields["supportsReasoning"]?.boolValue ?? false,
                supportedThinkingLevels: supportedThinkingLevels
            )
        }
    }
}
