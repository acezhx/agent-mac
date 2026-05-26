import Foundation

/// 共享资源库的文件型应用服务。
///
/// `ResourceLibrary` 只依赖 `FileStore`，负责 knowledge、skills、tools 的创建、
/// 读取、保存、列表和最小结构校验。它不依赖 SwiftUI、Session、RuntimeBridge 或
/// RuntimeHost，也不负责 Agent 配置组合。
nonisolated struct ResourceLibrary {
    /// 支持的 knowledge 文件扩展名。
    static let knowledgeExtensions: Set<String> = ["md", "txt"]

    /// 共享 knowledge 文件目录。
    static let knowledgeDirectory = "library/knowledge"

    /// 共享 skill 目录集合。
    static let skillsDirectory = "library/skills"

    /// 共享 tool 目录集合。
    static let toolsDirectory = "library/tools"

    /// 所有文件访问都委托给 FileStore。
    let fileStore: FileStore

    /// 创建共享资源库服务。
    ///
    /// - Parameter fileStore: 已指向当前 app data 根目录的文件服务。
    init(fileStore: FileStore) {
        self.fileStore = fileStore
    }

    /// 要求资源 ID 满足项目 ID 规则。
    ///
    /// - Parameters:
    ///   - id: 资源 ID。
    ///   - kind: 资源类型。
    /// - Throws: ID 非法时抛出校验错误。
    func requireValidResourceID(_ id: String, kind: ResourceKind) throws {
        if let error = resourceIDValidationError(id, kind: kind) {
            throw error
        }
    }

    /// 生成资源 ID 校验错误。
    ///
    /// - Parameters:
    ///   - id: 资源 ID。
    ///   - kind: 资源类型。
    /// - Returns: ID 合法时返回 `nil`，否则返回校验错误。
    func resourceIDValidationError(_ id: String, kind: ResourceKind) -> ResourceValidationError? {
        guard (2...64).contains(id.count),
              id.first != "-",
              id.last != "-"
        else {
            return .invalidResourceID(kind: kind, id: id)
        }

        let isValid = id.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return value == 45 || (48...57).contains(value) || (97...122).contains(value)
        }
        return isValid ? nil : .invalidResourceID(kind: kind, id: id)
    }

    /// 构造 knowledge 文件路径。
    ///
    /// - Parameter fileName: knowledge 文件名。
    /// - Returns: app data 相对路径。
    func knowledgePath(fileName: String) -> String {
        "\(Self.knowledgeDirectory)/\(fileName)"
    }

    /// 构造 skill 目录路径。
    ///
    /// - Parameter id: skill ID。
    /// - Returns: app data 相对路径。
    func skillDirectoryPath(id: String) -> String {
        "\(Self.skillsDirectory)/\(id)"
    }

    /// 构造 skill manifest 路径。
    ///
    /// - Parameter id: skill ID。
    /// - Returns: app data 相对路径。
    func skillManifestPath(id: String) -> String {
        "\(skillDirectoryPath(id: id))/SKILL.md"
    }

    /// 构造 tool 目录路径。
    ///
    /// - Parameter id: tool ID。
    /// - Returns: app data 相对路径。
    func toolDirectoryPath(id: String) -> String {
        "\(Self.toolsDirectory)/\(id)"
    }

    /// 构造 tool manifest 路径。
    ///
    /// - Parameter id: tool ID。
    /// - Returns: app data 相对路径。
    func toolManifestPath(id: String) -> String {
        "\(toolDirectoryPath(id: id))/tool.yaml"
    }
}
