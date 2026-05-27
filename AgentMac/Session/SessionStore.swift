import Foundation

/// Session 磁盘记录服务。
///
/// `SessionStore` 只理解 `sessions/<session-id>.json` 的文件格式和列表规则，所有实际文件访问仍
/// 委托给 `FileStore`。它不启动 Runtime，也不解析 Agent manifest。
nonisolated struct SessionStore {
    /// Session 记录目录。
    static let sessionsDirectory = "sessions"

    /// 所有文件访问都委托给 FileStore。
    private let fileStore: FileStore

    /// 创建 SessionStore。
    ///
    /// - Parameter fileStore: 已指向当前 app data 根目录的文件服务。
    init(fileStore: FileStore) {
        self.fileStore = fileStore
    }

    /// 构造指定 session 的 app data 相对路径。
    ///
    /// - Parameter id: 本地 session id。
    /// - Returns: `sessions/<session-id>.json`。
    static func relativePath(for id: UUID) -> String {
        "\(sessionsDirectory)/\(id.uuidString.lowercased()).json"
    }

    /// 构造指定 session 的 app data 相对路径。
    ///
    /// - Parameter id: 本地 session id。
    /// - Returns: `sessions/<session-id>.json`。
    func relativePath(for id: UUID) -> String {
        Self.relativePath(for: id)
    }

    /// 保存完整 session record。
    ///
    /// - Parameter record: 要保存的完整 record。
    /// - Throws: 编码或写入失败时抛出 `SessionError.persistenceFailed`。
    func save(_ record: ChatSessionRecord) throws {
        let path = relativePath(for: record.id)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(record)
            guard let text = String(data: data, encoding: .utf8) else {
                throw SessionError.persistenceFailed(path: path, reason: "Encoded record is not UTF-8.")
            }
            try fileStore.writeTextFile(text + "\n", to: path)
        } catch let error as SessionError {
            throw error
        } catch {
            throw persistenceError(path: path, error: error)
        }
    }

    /// 加载完整 session record。
    ///
    /// - Parameter id: 本地 session id。
    /// - Returns: 完整 session record。
    /// - Throws: 读取或解码失败时抛出 `SessionError.persistenceFailed`。
    func load(id: UUID) throws -> ChatSessionRecord {
        try load(relativePath: relativePath(for: id))
    }

    /// 加载 session 摘要列表。
    ///
    /// 列表按 `updatedAt` 倒序排序，同一时间按 session id 稳定排序。任一 record 损坏时会抛出
    /// 错误，避免静默隐藏用户数据问题。
    ///
    /// - Returns: session 摘要列表。
    /// - Throws: 目录扫描、读取或解码失败时抛出 `SessionError.persistenceFailed`。
    func listSummaries() throws -> [ChatSessionSummary] {
        do {
            return try fileStore
                .listFiles(at: Self.sessionsDirectory, matchingExtensions: ["json"])
                .map { try load(relativePath: "\(Self.sessionsDirectory)/\($0.lastPathComponent)") }
                .map(ChatSessionSummary.init(record:))
                .sorted { lhs, rhs in
                    if lhs.updatedAt != rhs.updatedAt {
                        return lhs.updatedAt > rhs.updatedAt
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
        } catch let error as SessionError {
            throw error
        } catch {
            throw persistenceError(path: Self.sessionsDirectory, error: error)
        }
    }

    /// 删除指定 session record。
    ///
    /// - Parameter id: 本地 session id。
    /// - Throws: 文件不存在或删除失败时抛出 `SessionError.persistenceFailed`。
    func delete(id: UUID) throws {
        let path = relativePath(for: id)
        do {
            try fileStore.deleteFile(at: path)
        } catch {
            throw persistenceError(path: path, error: error)
        }
    }

    /// 从相对路径加载 session record。
    ///
    /// - Parameter relativePath: app data 相对路径。
    /// - Returns: 完整 session record。
    private func load(relativePath: String) throws -> ChatSessionRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let text = try fileStore.readTextFile(at: relativePath)
            return try decoder.decode(ChatSessionRecord.self, from: Data(text.utf8))
        } catch let error as SessionError {
            throw error
        } catch {
            throw persistenceError(path: relativePath, error: error)
        }
    }

    /// 将底层错误包装为 Session 持久化错误。
    ///
    /// - Parameters:
    ///   - path: app data 相对路径。
    ///   - error: 底层错误。
    /// - Returns: Session 持久化错误。
    private func persistenceError(path: String, error: Error) -> SessionError {
        .persistenceFailed(path: path, reason: error.localizedDescription)
    }
}
