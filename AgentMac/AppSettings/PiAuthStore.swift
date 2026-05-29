import Foundation

/// Pi `auth.json` 中单个 provider 的授权状态摘要。
nonisolated struct ProviderCredentialStatus: Equatable, Identifiable, Sendable {
    /// Pi provider ID。
    var providerID: String

    /// 是否存在 API Key 凭据。
    var hasAPIKey: Bool

    /// 是否存在 OAuth/订阅凭据。
    var hasOAuth: Bool

    /// SwiftUI 列表使用的稳定 ID。
    var id: String {
        providerID
    }

    /// 是否已经配置任一凭据。
    var isConnected: Bool {
        hasAPIKey || hasOAuth
    }
}

/// Pi `auth.json` 读写边界。
///
/// 该类型只维护 Pi 标准认证文件中的 provider 凭据摘要和 API Key 条目。OAuth 条目会被保留，
/// 但第一版不创建或刷新 OAuth token。
nonisolated struct PiAuthStore {
    /// Pi 认证文件相对 app data 的路径。
    static let authPath = "Pi/auth.json"

    /// 文件服务。
    let fileStore: FileStore

    /// 创建 Pi 认证存储。
    ///
    /// - Parameter fileStore: app data 根目录对应的文件服务。
    init(fileStore: FileStore) {
        self.fileStore = fileStore
    }

    /// 读取指定 provider 的凭据状态。
    ///
    /// - Parameter providerIDs: 要查询的 Pi provider ID。
    /// - Returns: 与输入顺序一致的凭据状态。
    /// - Throws: 文件读取或 JSON 解析失败时抛出 FileStore 错误。
    func credentialStatuses(for providerIDs: [String]) throws -> [ProviderCredentialStatus] {
        let data = try loadAuthData()
        return providerIDs.map { status(for: $0, in: data) }
    }

    /// 保存 provider 的 API Key。
    ///
    /// - Parameters:
    ///   - providerID: Pi provider ID。
    ///   - apiKey: 用户输入的 API Key。
    /// - Returns: 保存后的 provider 凭据状态。
    /// - Throws: API Key 为空、文件读取或写入失败时抛出错误。
    @discardableResult
    func saveAPIKey(providerID: String, apiKey: String) throws -> ProviderCredentialStatus {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw PiAuthStoreError.emptyAPIKey
        }

        var data = try loadAuthData()
        data[providerID] = .object([
            "type": .string("api_key"),
            "key": .string(trimmedKey),
        ])
        try saveAuthData(data)
        return status(for: providerID, in: data)
    }

    /// 删除 provider 的已保存凭据。
    ///
    /// - Parameter providerID: Pi provider ID。
    /// - Returns: 删除后的 provider 凭据状态。
    /// - Throws: 文件读取或写入失败时抛出错误。
    @discardableResult
    func removeCredential(providerID: String) throws -> ProviderCredentialStatus {
        var data = try loadAuthData()
        data.removeValue(forKey: providerID)
        try saveAuthData(data)
        return status(for: providerID, in: data)
    }

    private func status(for providerID: String, in data: [String: JSONValue]) -> ProviderCredentialStatus {
        let credential = data[providerID]?.objectValue
        let type = credential?["type"]?.stringValue
        return ProviderCredentialStatus(
            providerID: providerID,
            hasAPIKey: type == "api_key",
            hasOAuth: type == "oauth"
        )
    }

    private func loadAuthData() throws -> [String: JSONValue] {
        guard try fileStore.fileExists(at: Self.authPath) else {
            return [:]
        }

        let text = try fileStore.readTextFile(at: Self.authPath)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: JSONValue].self, from: Data(trimmed.utf8))
        } catch {
            throw FileStoreError.readFailed(path: Self.authPath, reason: error.localizedDescription)
        }
    }

    private func saveAuthData(_ data: [String: JSONValue]) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encoded = try encoder.encode(data)
            guard let text = String(data: encoded, encoding: .utf8) else {
                throw PiAuthStoreError.invalidJSONEncoding
            }
            try fileStore.writeTextFile(text + "\n", to: Self.authPath)
            try setOwnerReadWritePermission()
        } catch let error as FileStoreError {
            throw error
        } catch {
            throw FileStoreError.writeFailed(path: Self.authPath, reason: error.localizedDescription)
        }
    }

    private func setOwnerReadWritePermission() throws {
        let url = try fileStore.resolveAppDataPath(Self.authPath)
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw FileStoreError.writeFailed(path: Self.authPath, reason: error.localizedDescription)
        }
    }
}

/// Pi auth 文件读写错误。
nonisolated enum PiAuthStoreError: Error, Equatable {
    /// API Key 为空。
    case emptyAPIKey

    /// JSON 编码结果不是 UTF-8 文本。
    case invalidJSONEncoding
}

extension PiAuthStoreError: LocalizedError {
    /// 面向 UI 或 FileStore 错误包装的描述。
    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            "API Key cannot be empty."
        case .invalidJSONEncoding:
            "Unable to encode auth.json as UTF-8 JSON."
        }
    }
}

/// 保留 Pi auth.json 中未知字段的 JSON 值。
nonisolated enum JSONValue: Codable, Equatable, Sendable {
    /// 字符串。
    case string(String)

    /// 整数。
    case int(Int)

    /// 浮点数。
    case double(Double)

    /// 布尔值。
    case bool(Bool)

    /// 对象。
    case object([String: JSONValue])

    /// 数组。
    case array([JSONValue])

    /// null。
    case null

    /// 对象值。
    var objectValue: [String: JSONValue]? {
        if case let .object(value) = self {
            return value
        }
        return nil
    }

    /// 字符串值。
    var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    /// 解码 JSON 值。
    ///
    /// - Parameter decoder: Foundation decoder。
    /// - Throws: JSON 结构无法匹配受支持值时抛出解码错误。
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    /// 编码 JSON 值。
    ///
    /// - Parameter encoder: Foundation encoder。
    /// - Throws: 底层编码失败时抛出错误。
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
