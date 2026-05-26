import Foundation

nonisolated extension ResourceLibrary {
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
