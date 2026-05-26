import Foundation

/// 共享资源的类型。
///
/// `ResourceLibrary` 第一版只维护 knowledge、skill 和 tool 三类文件型资源。
nonisolated enum ResourceKind: String, Equatable {
    /// Markdown 或纯文本 knowledge 文件。
    case knowledge

    /// 符合 Agent Skills 目录约定的 skill 目录。
    case skill

    /// 包含 `tool.yaml` 和入口文件的 tool 目录。
    case tool
}

/// 资源最小结构校验失败的原因。
///
/// 这些错误描述 ResourceLibrary 负责的本地文件结构问题，不包含 Agent 组合、
/// Runtime 执行或 UI 展示规则。
nonisolated enum ResourceValidationError: Error, Equatable {
    /// knowledge 文件名为空、隐藏、包含路径分隔符或包含非法字符。
    case invalidKnowledgeFileName(fileName: String, reason: String)

    /// knowledge 文件扩展名不是第一版支持的 `.md` 或 `.txt`。
    case unsupportedKnowledgeFileExtension(fileName: String)

    /// skill 或 tool 的目录名不满足资源 ID 规则。
    case invalidResourceID(kind: ResourceKind, id: String)

    /// 指定的资源目录不存在。
    case missingResourceDirectory(kind: ResourceKind, id: String)

    /// skill 目录缺少 `SKILL.md`。
    case missingSkillManifest(skillID: String)

    /// tool 创建时传入了空展示名称。
    case emptyToolName(toolID: String)

    /// tool 目录缺少 `tool.yaml`。
    case missingToolManifest(toolID: String)

    /// `tool.yaml` 缺少顶层 `entry` 字段，或该字段为空。
    case missingToolEntry(toolID: String)

    /// `tool.yaml.entry` 不是位于当前 tool 目录内的合法相对路径。
    case invalidToolEntry(toolID: String, entry: String, reason: String)

    /// `tool.yaml.entry` 指向的入口文件不存在。
    case missingToolEntryFile(toolID: String, entry: String)
}

extension ResourceValidationError: LocalizedError {
    /// 面向日志和测试诊断的错误描述。
    var errorDescription: String? {
        switch self {
        case let .invalidKnowledgeFileName(fileName, reason):
            "Invalid knowledge file name '\(fileName)': \(reason)"
        case let .unsupportedKnowledgeFileExtension(fileName):
            "Unsupported knowledge file extension: \(fileName)"
        case let .invalidResourceID(kind, id):
            "Invalid \(kind.rawValue) resource id: \(id)"
        case let .missingResourceDirectory(kind, id):
            "Missing \(kind.rawValue) resource directory: \(id)"
        case let .missingSkillManifest(skillID):
            "Missing SKILL.md for skill: \(skillID)"
        case let .emptyToolName(toolID):
            "Tool name cannot be empty: \(toolID)"
        case let .missingToolManifest(toolID):
            "Missing tool.yaml for tool: \(toolID)"
        case let .missingToolEntry(toolID):
            "Missing tool.yaml entry for tool: \(toolID)"
        case let .invalidToolEntry(toolID, entry, reason):
            "Invalid tool entry '\(entry)' for tool \(toolID): \(reason)"
        case let .missingToolEntryFile(toolID, entry):
            "Missing tool entry file '\(entry)' for tool: \(toolID)"
        }
    }
}

/// 资源结构校验结果。
///
/// `errors` 为空表示资源满足 ResourceLibrary 第一版的最小结构约束。
nonisolated struct ResourceValidationStatus: Equatable {
    /// 校验发现的结构问题。
    let errors: [ResourceValidationError]

    /// 资源是否通过最小结构校验。
    var isValid: Bool {
        errors.isEmpty
    }

    /// 创建一个校验结果。
    ///
    /// - Parameter errors: 校验发现的结构问题，默认为空。
    init(errors: [ResourceValidationError] = []) {
        self.errors = errors
    }
}

/// 共享 knowledge 文件的资源描述。
nonisolated struct KnowledgeResource: Equatable, Identifiable {
    /// knowledge ID，使用完整文件名，避免同名不同扩展名的文件互相冲突。
    let id: String

    /// UI 可展示名称，第一版来自文件名去掉扩展名后的部分。
    let name: String

    /// 资源类型。
    var kind: ResourceKind { .knowledge }

    /// 相对于 app data 根目录的文件路径。
    let path: String

    /// knowledge 文件的结构校验结果。
    let validation: ResourceValidationStatus
}

/// 共享 skill 目录的资源描述。
nonisolated struct SkillResource: Equatable, Identifiable {
    /// skill ID，来自 `library/skills/<skill-id>` 目录名。
    let id: String

    /// UI 可展示名称，第一版与 `id` 保持一致。
    let name: String

    /// 资源类型。
    var kind: ResourceKind { .skill }

    /// 相对于 app data 根目录的目录路径。
    let path: String

    /// skill 目录的最小结构校验结果。
    let validation: ResourceValidationStatus
}

/// 共享 tool 目录的资源描述。
nonisolated struct ToolResource: Equatable, Identifiable {
    /// tool ID，来自 `library/tools/<tool-id>` 目录名。
    let id: String

    /// UI 可展示名称，优先来自 `tool.yaml` 的顶层 `name` 字段。
    let name: String

    /// 资源类型。
    var kind: ResourceKind { .tool }

    /// 相对于 app data 根目录的目录路径。
    let path: String

    /// `tool.yaml` 中声明的入口文件路径；缺失或无法读取时为 `nil`。
    let entry: String?

    /// tool 目录的最小结构校验结果。
    let validation: ResourceValidationStatus
}

/// 共享资源库的文件型应用服务。
///
/// `ResourceLibrary` 只依赖 `FileStore`，负责 knowledge、skills、tools 的创建、
/// 读取、保存、列表和最小结构校验。它不依赖 SwiftUI、Session、RuntimeBridge 或
/// RuntimeHost，也不负责 Agent 配置组合。
nonisolated struct ResourceLibrary {
    /// 支持的 knowledge 文件扩展名。
    private static let knowledgeExtensions: Set<String> = ["md", "txt"]

    /// 共享 knowledge 文件目录。
    private static let knowledgeDirectory = "library/knowledge"

    /// 共享 skill 目录集合。
    private static let skillsDirectory = "library/skills"

    /// 共享 tool 目录集合。
    private static let toolsDirectory = "library/tools"

    /// 所有文件访问都委托给 FileStore。
    private let fileStore: FileStore

    /// 创建共享资源库服务。
    ///
    /// - Parameter fileStore: 已指向当前 app data 根目录的文件服务。
    init(fileStore: FileStore) {
        self.fileStore = fileStore
    }

    /// 列出共享 knowledge 文件。
    ///
    /// 只返回 `library/knowledge/` 下一级可见 `.md` 和 `.txt` 文件，结果按文件名稳定排序。
    ///
    /// - Returns: knowledge 资源描述列表。
    /// - Throws: `FileStore` 目录扫描错误。
    func listKnowledge() throws -> [KnowledgeResource] {
        try fileStore
            .listFiles(at: Self.knowledgeDirectory, matchingExtensions: Self.knowledgeExtensions)
            .map { makeKnowledgeResource(fileName: $0.lastPathComponent) }
    }

    /// 创建 knowledge 文件。
    ///
    /// - Parameters:
    ///   - fileName: `library/knowledge/` 下的一级文件名，必须使用 `.md` 或 `.txt`。
    ///   - contents: 初始文本内容。
    /// - Returns: 创建后的 knowledge 资源描述。
    /// - Throws: 文件名非法、扩展名不支持或写入失败。
    @discardableResult
    func createKnowledgeFile(named fileName: String, contents: String = "") throws -> KnowledgeResource {
        try validateKnowledgeFileName(fileName)
        try fileStore.writeTextFile(contents, to: knowledgePath(fileName: fileName))
        return makeKnowledgeResource(fileName: fileName)
    }

    /// 读取 knowledge 文件内容。
    ///
    /// - Parameter fileName: `library/knowledge/` 下的一级文件名。
    /// - Returns: UTF-8 文本内容。
    /// - Throws: 文件名非法、扩展名不支持或读取失败。
    func readKnowledgeFile(named fileName: String) throws -> String {
        try validateKnowledgeFileName(fileName)
        return try fileStore.readTextFile(at: knowledgePath(fileName: fileName))
    }

    /// 保存 knowledge 文件内容。
    ///
    /// - Parameters:
    ///   - contents: 要写入的 UTF-8 文本内容。
    ///   - fileName: `library/knowledge/` 下的一级文件名。
    /// - Returns: 保存后的 knowledge 资源描述。
    /// - Throws: 文件名非法、扩展名不支持或写入失败。
    @discardableResult
    func saveKnowledgeFile(_ contents: String, named fileName: String) throws -> KnowledgeResource {
        try validateKnowledgeFileName(fileName)
        try fileStore.writeTextFile(contents, to: knowledgePath(fileName: fileName))
        return makeKnowledgeResource(fileName: fileName)
    }

    /// 列出共享 skill 目录。
    ///
    /// 返回 `library/skills/` 下一级可见目录，并为每个目录附带最小结构校验结果。
    ///
    /// - Returns: skill 资源描述列表。
    /// - Throws: `FileStore` 目录扫描或读取错误。
    func listSkills() throws -> [SkillResource] {
        try fileStore
            .listDirectories(at: Self.skillsDirectory)
            .map { try makeSkillResource(id: $0.lastPathComponent) }
    }

    /// 创建 skill 目录和初始 `SKILL.md`。
    ///
    /// - Parameters:
    ///   - id: skill 目录 ID，必须满足项目 ID 规则。
    ///   - skillMarkdown: 初始 `SKILL.md` 内容。
    /// - Returns: 创建后的 skill 资源描述。
    /// - Throws: ID 非法或写入失败。
    @discardableResult
    func createSkill(id: String, skillMarkdown: String = "") throws -> SkillResource {
        try requireValidResourceID(id, kind: .skill)
        try fileStore.writeTextFile(skillMarkdown, to: skillManifestPath(id: id))
        return try makeSkillResource(id: id)
    }

    /// 读取 skill 的 `SKILL.md` 内容。
    ///
    /// - Parameter id: skill 目录 ID。
    /// - Returns: `SKILL.md` 的 UTF-8 文本内容。
    /// - Throws: ID 非法或读取失败。
    func readSkillMarkdown(id: String) throws -> String {
        try requireValidResourceID(id, kind: .skill)
        return try fileStore.readTextFile(at: skillManifestPath(id: id))
    }

    /// 保存 skill 的 `SKILL.md` 内容。
    ///
    /// - Parameters:
    ///   - markdown: 要写入的 UTF-8 文本内容。
    ///   - id: skill 目录 ID。
    /// - Returns: 保存后的 skill 资源描述。
    /// - Throws: ID 非法或写入失败。
    @discardableResult
    func saveSkillMarkdown(_ markdown: String, id: String) throws -> SkillResource {
        try requireValidResourceID(id, kind: .skill)
        try fileStore.writeTextFile(markdown, to: skillManifestPath(id: id))
        return try makeSkillResource(id: id)
    }

    /// 校验 skill 目录的最小结构。
    ///
    /// 第一版校验目录 ID、目录存在性和 `SKILL.md` 存在性，不解析 skill frontmatter。
    ///
    /// - Parameter id: skill 目录 ID。
    /// - Returns: 最小结构校验结果。
    /// - Throws: `FileStore` 路径或存在性检查错误。
    func validateSkill(id: String) throws -> ResourceValidationStatus {
        if let error = resourceIDValidationError(id, kind: .skill) {
            return ResourceValidationStatus(errors: [error])
        }

        guard try fileStore.directoryExists(at: skillDirectoryPath(id: id)) else {
            return ResourceValidationStatus(errors: [.missingResourceDirectory(kind: .skill, id: id)])
        }

        guard try fileStore.fileExists(at: skillManifestPath(id: id)) else {
            return ResourceValidationStatus(errors: [.missingSkillManifest(skillID: id)])
        }

        return ResourceValidationStatus()
    }

    /// 列出共享 tool 目录。
    ///
    /// 返回 `library/tools/` 下一级可见目录，并为每个目录附带最小结构校验结果。
    ///
    /// - Returns: tool 资源描述列表。
    /// - Throws: `FileStore` 目录扫描或读取错误。
    func listTools() throws -> [ToolResource] {
        try fileStore
            .listDirectories(at: Self.toolsDirectory)
            .map { try makeToolResource(id: $0.lastPathComponent) }
    }

    /// 创建 tool 目录、初始 `tool.yaml` 和入口文件。
    ///
    /// - Parameters:
    ///   - id: tool 目录 ID，必须满足项目 ID 规则。
    ///   - name: tool 展示名称，写入 `tool.yaml`。
    ///   - entryFileName: 入口文件相对路径，默认 `index.js`，必须留在当前 tool 目录内。
    ///   - entryContents: 初始入口文件内容。
    /// - Returns: 创建后的 tool 资源描述。
    /// - Throws: ID、名称或入口路径非法，或文件写入失败。
    @discardableResult
    func createTool(
        id: String,
        name: String,
        entryFileName: String = "index.js",
        entryContents: String = ""
    ) throws -> ToolResource {
        try requireValidResourceID(id, kind: .tool)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ResourceValidationError.emptyToolName(toolID: id)
        }

        let entryPath = try toolEntryRelativePath(toolID: id, entry: entryFileName)
        try fileStore.writeYAMLFile(makeInitialToolManifest(id: id, name: name, entry: entryFileName), to: toolManifestPath(id: id)) {
            $0
        }
        try fileStore.writeTextFile(entryContents, to: entryPath)
        return try makeToolResource(id: id)
    }

    /// 读取 tool 的 `tool.yaml` 内容。
    ///
    /// - Parameter id: tool 目录 ID。
    /// - Returns: `tool.yaml` 的 UTF-8 文本内容。
    /// - Throws: ID 非法或读取失败。
    func readToolManifest(id: String) throws -> String {
        try requireValidResourceID(id, kind: .tool)
        return try fileStore.readYAMLFile(at: toolManifestPath(id: id)) { $0 }
    }

    /// 保存 tool 的 `tool.yaml` 内容。
    ///
    /// 保存后不会自动创建新的入口文件；调用方可以根据返回资源的校验结果决定是否继续补齐入口文件。
    ///
    /// - Parameters:
    ///   - yaml: 要写入的 YAML 文本。
    ///   - id: tool 目录 ID。
    /// - Returns: 保存后的 tool 资源描述。
    /// - Throws: ID 非法或写入失败。
    @discardableResult
    func saveToolManifest(_ yaml: String, id: String) throws -> ToolResource {
        try requireValidResourceID(id, kind: .tool)
        try fileStore.writeYAMLFile(yaml, to: toolManifestPath(id: id)) { $0 }
        return try makeToolResource(id: id)
    }

    /// 读取 `tool.yaml.entry` 指向的入口文件内容。
    ///
    /// - Parameter id: tool 目录 ID。
    /// - Returns: 入口文件的 UTF-8 文本内容。
    /// - Throws: ID 非法、manifest 缺失、entry 非法或读取失败。
    func readToolEntry(id: String) throws -> String {
        try requireValidResourceID(id, kind: .tool)
        return try fileStore.readTextFile(at: requiredToolEntryRelativePath(toolID: id))
    }

    /// 保存 `tool.yaml.entry` 指向的入口文件内容。
    ///
    /// - Parameters:
    ///   - contents: 要写入的 UTF-8 文本内容。
    ///   - id: tool 目录 ID。
    /// - Returns: 保存后的 tool 资源描述。
    /// - Throws: ID 非法、manifest 缺失、entry 非法或写入失败。
    @discardableResult
    func saveToolEntry(_ contents: String, id: String) throws -> ToolResource {
        try requireValidResourceID(id, kind: .tool)
        try fileStore.writeTextFile(contents, to: requiredToolEntryRelativePath(toolID: id))
        return try makeToolResource(id: id)
    }

    /// 校验 tool 目录的最小结构。
    ///
    /// 第一版校验目录 ID、目录存在性、`tool.yaml` 存在性、顶层 `entry` 字段和入口文件存在性。
    ///
    /// - Parameter id: tool 目录 ID。
    /// - Returns: 最小结构校验结果。
    /// - Throws: `FileStore` 路径、读取或存在性检查错误。
    func validateTool(id: String) throws -> ResourceValidationStatus {
        if let error = resourceIDValidationError(id, kind: .tool) {
            return ResourceValidationStatus(errors: [error])
        }

        guard try fileStore.directoryExists(at: toolDirectoryPath(id: id)) else {
            return ResourceValidationStatus(errors: [.missingResourceDirectory(kind: .tool, id: id)])
        }
        guard try fileStore.fileExists(at: toolManifestPath(id: id)) else {
            return ResourceValidationStatus(errors: [.missingToolManifest(toolID: id)])
        }

        let manifest = try fileStore.readYAMLFile(at: toolManifestPath(id: id)) { $0 }
        guard let entry = topLevelScalar(named: "entry", in: manifest), !entry.isEmpty else {
            return ResourceValidationStatus(errors: [.missingToolEntry(toolID: id)])
        }

        do {
            let entryPath = try toolEntryRelativePath(toolID: id, entry: entry)
            guard try fileStore.fileExists(at: entryPath) else {
                return ResourceValidationStatus(errors: [.missingToolEntryFile(toolID: id, entry: entry)])
            }
            return ResourceValidationStatus()
        } catch let error as ResourceValidationError {
            return ResourceValidationStatus(errors: [error])
        }
    }

    /// 根据文件名构造 knowledge 资源描述。
    ///
    /// - Parameter fileName: `library/knowledge/` 下的文件名。
    /// - Returns: knowledge 资源描述。
    private func makeKnowledgeResource(fileName: String) -> KnowledgeResource {
        return KnowledgeResource(
            id: fileName,
            name: (fileName as NSString).deletingPathExtension,
            path: knowledgePath(fileName: fileName),
            validation: ResourceValidationStatus()
        )
    }

    /// 根据目录 ID 构造 skill 资源描述。
    ///
    /// - Parameter id: skill 目录 ID。
    /// - Returns: skill 资源描述。
    /// - Throws: `validateSkill(id:)` 抛出的错误。
    private func makeSkillResource(id: String) throws -> SkillResource {
        SkillResource(
            id: id,
            name: id,
            path: skillDirectoryPath(id: id),
            validation: try validateSkill(id: id)
        )
    }

    /// 根据目录 ID 构造 tool 资源描述。
    ///
    /// - Parameter id: tool 目录 ID。
    /// - Returns: tool 资源描述。
    /// - Throws: `validateTool(id:)` 或 manifest 读取抛出的错误。
    private func makeToolResource(id: String) throws -> ToolResource {
        let manifest = try readExistingToolManifestIfPresent(id: id)
        return ToolResource(
            id: id,
            name: toolDisplayName(from: manifest, fallback: id),
            path: toolDirectoryPath(id: id),
            entry: manifest.flatMap { topLevelScalar(named: "entry", in: $0) },
            validation: try validateTool(id: id)
        )
    }

    /// 读取已存在的 `tool.yaml`。
    ///
    /// - Parameter id: tool 目录 ID。
    /// - Returns: manifest 文本；文件不存在时返回 `nil`。
    /// - Throws: 文件存在但读取失败时抛出 `FileStore` 错误。
    private func readExistingToolManifestIfPresent(id: String) throws -> String? {
        guard try fileStore.fileExists(at: toolManifestPath(id: id)) else {
            return nil
        }
        return try fileStore.readYAMLFile(at: toolManifestPath(id: id)) { $0 }
    }

    /// 构造初始 `tool.yaml` 文本。
    ///
    /// - Parameters:
    ///   - id: tool ID。
    ///   - name: tool 展示名称。
    ///   - entry: 入口文件相对路径。
    /// - Returns: YAML 文本。
    private func makeInitialToolManifest(id: String, name: String, entry: String) -> String {
        """
        id: \(id)
        name: "\(escapedDoubleQuotedYAMLScalar(name))"
        runtime: node
        entry: "\(escapedDoubleQuotedYAMLScalar(entry))"

        permissions:
          network: ask
          secrets: []
        """
    }

    /// 从 `tool.yaml` 中解析展示名称。
    ///
    /// - Parameters:
    ///   - manifest: 可选 manifest 文本。
    ///   - fallback: manifest 缺失或未声明名称时使用的名称。
    /// - Returns: tool 展示名称。
    private func toolDisplayName(from manifest: String?, fallback: String) -> String {
        guard let name = manifest.flatMap({ topLevelScalar(named: "name", in: $0) }),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return fallback
        }
        return name
    }

    /// 从 `tool.yaml` 中读取必需的入口文件相对路径。
    ///
    /// - Parameter toolID: tool 目录 ID。
    /// - Returns: 相对于 app data 根目录的入口文件路径。
    /// - Throws: manifest 缺失、entry 缺失或 entry 非法时抛出错误。
    private func requiredToolEntryRelativePath(toolID: String) throws -> String {
        let manifest = try fileStore.readYAMLFile(at: toolManifestPath(id: toolID)) { $0 }
        guard let entry = topLevelScalar(named: "entry", in: manifest), !entry.isEmpty else {
            throw ResourceValidationError.missingToolEntry(toolID: toolID)
        }
        return try toolEntryRelativePath(toolID: toolID, entry: entry)
    }

    /// 将 `tool.yaml.entry` 转成安全的 app data 相对路径。
    ///
    /// - Parameters:
    ///   - toolID: tool 目录 ID。
    ///   - entry: manifest 中声明的入口文件相对路径。
    /// - Returns: 相对于 app data 根目录的入口文件路径。
    /// - Throws: entry 为空、绝对路径或解析后逃逸当前 tool 目录时抛出校验错误。
    private func toolEntryRelativePath(toolID: String, entry: String) throws -> String {
        let trimmedEntry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEntry.isEmpty else {
            throw ResourceValidationError.missingToolEntry(toolID: toolID)
        }
        guard !trimmedEntry.contains("\0") else {
            throw ResourceValidationError.invalidToolEntry(
                toolID: toolID,
                entry: entry,
                reason: "Entry cannot contain null bytes."
            )
        }
        guard !(trimmedEntry as NSString).isAbsolutePath else {
            throw ResourceValidationError.invalidToolEntry(
                toolID: toolID,
                entry: entry,
                reason: "Entry must be relative to the tool directory."
            )
        }

        let toolDirectory = toolDirectoryPath(id: toolID)
        let entryPath = "\(toolDirectory)/\(trimmedEntry)"

        do {
            let toolURL = try fileStore.resolveAppDataPath(toolDirectory)
            let entryURL = try fileStore.resolveAppDataPath(entryPath)
            guard entryURL.path == toolURL.path || entryURL.path.hasPrefix(toolURL.path + "/") else {
                throw ResourceValidationError.invalidToolEntry(
                    toolID: toolID,
                    entry: entry,
                    reason: "Entry must stay inside the tool directory."
                )
            }
        } catch let error as ResourceValidationError {
            throw error
        } catch {
            throw ResourceValidationError.invalidToolEntry(
                toolID: toolID,
                entry: entry,
                reason: error.localizedDescription
            )
        }

        return entryPath
    }

    /// 校验 knowledge 文件名。
    ///
    /// - Parameter fileName: `library/knowledge/` 下的一级文件名。
    /// - Throws: 文件名非法或扩展名不受支持时抛出校验错误。
    private func validateKnowledgeFileName(_ fileName: String) throws {
        let trimmedName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ResourceValidationError.invalidKnowledgeFileName(fileName: fileName, reason: "File name cannot be empty.")
        }
        guard trimmedName == fileName else {
            throw ResourceValidationError.invalidKnowledgeFileName(fileName: fileName, reason: "File name cannot have surrounding whitespace.")
        }
        guard !fileName.contains("\0") else {
            throw ResourceValidationError.invalidKnowledgeFileName(fileName: fileName, reason: "File name cannot contain null bytes.")
        }
        guard !fileName.contains("/") else {
            throw ResourceValidationError.invalidKnowledgeFileName(fileName: fileName, reason: "File name cannot contain path separators.")
        }
        guard fileName != ".", fileName != "..", !fileName.hasPrefix(".") else {
            throw ResourceValidationError.invalidKnowledgeFileName(fileName: fileName, reason: "File name cannot be hidden or reserved.")
        }

        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        guard Self.knowledgeExtensions.contains(fileExtension) else {
            throw ResourceValidationError.unsupportedKnowledgeFileExtension(fileName: fileName)
        }
    }

    /// 要求资源 ID 满足项目 ID 规则。
    ///
    /// - Parameters:
    ///   - id: 资源 ID。
    ///   - kind: 资源类型。
    /// - Throws: ID 非法时抛出校验错误。
    private func requireValidResourceID(_ id: String, kind: ResourceKind) throws {
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
    private func resourceIDValidationError(_ id: String, kind: ResourceKind) -> ResourceValidationError? {
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
    private func knowledgePath(fileName: String) -> String {
        "\(Self.knowledgeDirectory)/\(fileName)"
    }

    /// 构造 skill 目录路径。
    ///
    /// - Parameter id: skill ID。
    /// - Returns: app data 相对路径。
    private func skillDirectoryPath(id: String) -> String {
        "\(Self.skillsDirectory)/\(id)"
    }

    /// 构造 skill manifest 路径。
    ///
    /// - Parameter id: skill ID。
    /// - Returns: app data 相对路径。
    private func skillManifestPath(id: String) -> String {
        "\(skillDirectoryPath(id: id))/SKILL.md"
    }

    /// 构造 tool 目录路径。
    ///
    /// - Parameter id: tool ID。
    /// - Returns: app data 相对路径。
    private func toolDirectoryPath(id: String) -> String {
        "\(Self.toolsDirectory)/\(id)"
    }

    /// 构造 tool manifest 路径。
    ///
    /// - Parameter id: tool ID。
    /// - Returns: app data 相对路径。
    private func toolManifestPath(id: String) -> String {
        "\(toolDirectoryPath(id: id))/tool.yaml"
    }

    /// 解析 YAML 顶层字符串标量。
    ///
    /// 第一版只用于读取 ResourceLibrary 需要的 `tool.yaml.name` 和 `tool.yaml.entry`。
    /// 该解析器不尝试覆盖完整 YAML 语法。
    ///
    /// - Parameters:
    ///   - name: 顶层字段名。
    ///   - yaml: YAML 文本。
    /// - Returns: 解析出的标量值；字段缺失或不是顶层字段时返回 `nil`。
    private func topLevelScalar(named name: String, in yaml: String) -> String? {
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let rawLine = String(line)
            guard let firstCharacter = rawLine.first, !firstCharacter.isWhitespace else {
                continue
            }

            let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else {
                continue
            }
            guard trimmedLine.hasPrefix("\(name):") else {
                continue
            }

            let rawValue = String(trimmedLine.dropFirst(name.count + 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return unquotedYAMLScalar(rawValue)
        }

        return nil
    }

    /// 去掉 YAML 简单标量的引号。
    ///
    /// - Parameter value: 字段冒号后的原始文本。
    /// - Returns: 去除外层引号和简单注释后的标量值。
    private func unquotedYAMLScalar(_ value: String) -> String {
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            return String(value.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
            return String(value.dropFirst().dropLast())
                .replacingOccurrences(of: "''", with: "'")
        }

        if let commentStart = value.firstIndex(of: "#") {
            return String(value[..<commentStart]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    /// 转义 YAML 双引号标量中的特殊字符。
    ///
    /// - Parameter value: 原始标量值。
    /// - Returns: 可放入双引号内的标量文本。
    private func escapedDoubleQuotedYAMLScalar(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
