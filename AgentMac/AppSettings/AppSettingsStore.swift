import Foundation

/// 应用级设置文件读写边界。
///
/// 该类型只负责通过 `FileStore` 读写 `settings.yaml`，不持有 UI 状态，也不解释 Agent 运行行为。
nonisolated struct AppSettingsStore {
    /// settings 文件相对 app data 的路径。
    static let settingsPath = "settings.yaml"

    /// 文件服务。
    let fileStore: FileStore

    /// 创建设置存储。
    ///
    /// - Parameter fileStore: app data 根目录对应的文件服务。
    init(fileStore: FileStore) {
        self.fileStore = fileStore
    }

    /// 加载应用设置。
    ///
    /// - Returns: 当前 settings.yaml 对应的设置模型。
    /// - Throws: 文件读取或 YAML 解码失败时抛出结构化错误。
    func loadSettings() throws -> AppSettings {
        try fileStore.readYAMLFile(at: Self.settingsPath) { text in
            try AppSettingsYAMLCodec.decode(text)
        }
    }

    /// 保存应用设置。
    ///
    /// - Parameter settings: 要写入 settings.yaml 的设置。
    /// - Returns: 规范化后写入磁盘的设置。
    /// - Throws: YAML 编码或文件写入失败时抛出结构化错误。
    @discardableResult
    func saveSettings(_ settings: AppSettings) throws -> AppSettings {
        var normalizedSettings = settings
        normalizedSettings.agent.allowedModelProviders = AgentAppSettings.normalizedProviders(
            settings.agent.allowedModelProviders
        )
        try fileStore.writeYAMLFile(normalizedSettings, to: Self.settingsPath) { settings in
            AppSettingsYAMLCodec.encode(settings)
        }
        return normalizedSettings
    }
}
