import Foundation

nonisolated extension ResourceLibrary {
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
    ///   - skillMarkdown: 初始 `SKILL.md` 内容；为 `nil` 时写入包含默认 `name` 的基础模板。
    /// - Returns: 创建后的 skill 资源描述。
    /// - Throws: ID 非法或写入失败。
    @discardableResult
    func createSkill(id: String, skillMarkdown: String? = nil) throws -> SkillResource {
        try requireValidResourceID(id, kind: .skill)
        try fileStore.writeTextFile(skillMarkdown ?? makeInitialSkillMarkdown(id: id), to: skillManifestPath(id: id))
        return try makeSkillResource(id: id)
    }

    /// 导入已有 skill 目录。
    ///
    /// 源目录必须是一个包含顶层 `SKILL.md` 的目录。导入会复制整个目录树到
    /// `library/skills/<id>/`，包括 `references/`、`scripts/`、`assets/` 等附属文件。
    ///
    /// - Parameters:
    ///   - sourceDirectoryURL: 用户选择的已有 skill 目录。
    ///   - id: 导入后使用的 skill 目录 ID，必须满足项目 ID 规则且不应与已有目录冲突。
    /// - Returns: 导入后的 skill 资源描述。
    /// - Throws: 源目录不合法、ID 非法、目标已存在或复制失败时抛出错误。
    @discardableResult
    func importSkill(from sourceDirectoryURL: URL, id: String) throws -> SkillResource {
        try requireValidResourceID(id, kind: .skill)
        try requireValidSkillImportSource(sourceDirectoryURL)
        try fileStore.copyDirectory(from: sourceDirectoryURL, to: skillDirectoryPath(id: id))
        return try makeSkillResource(id: id)
    }

    /// 删除已有 skill 目录及其全部内容。
    ///
    /// - Parameter id: skill 目录 ID。
    /// - Throws: ID 非法、目录不存在或删除失败时抛出错误。
    func deleteSkill(id: String) throws {
        try requireValidResourceID(id, kind: .skill)
        try fileStore.deleteDirectory(at: skillDirectoryPath(id: id))
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

    /// 保存 skill 的 `SKILL.md` 内容，并可同步重命名 skill 目录。
    ///
    /// - Parameters:
    ///   - markdown: 要写入的 UTF-8 文本内容。
    ///   - id: skill 目录 ID。
    ///   - newID: 保存后使用的新 skill 目录 ID；为 `nil` 时保持原目录 ID。
    /// - Returns: 保存后的 skill 资源描述。
    /// - Throws: ID 非法、写入失败、目标目录已存在或移动失败。
    @discardableResult
    func saveSkillMarkdown(_ markdown: String, id: String, renamingTo newID: String? = nil) throws -> SkillResource {
        try requireValidResourceID(id, kind: .skill)
        let targetID = newID ?? id
        try requireValidResourceID(targetID, kind: .skill)

        if targetID != id {
            try fileStore.moveDirectory(from: skillDirectoryPath(id: id), to: skillDirectoryPath(id: targetID))
            do {
                try fileStore.writeTextFile(markdown, to: skillManifestPath(id: targetID))
            } catch {
                try? fileStore.moveDirectory(from: skillDirectoryPath(id: targetID), to: skillDirectoryPath(id: id))
                throw error
            }
        } else {
            try fileStore.writeTextFile(markdown, to: skillManifestPath(id: id))
        }
        return try makeSkillResource(id: targetID)
    }

    /// 校验 skill 目录的最小结构。
    ///
    /// 第一版校验目录 ID、目录存在性和 `SKILL.md` 存在性，不做完整 frontmatter 规范校验。
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

    /// 根据目录 ID 构造 skill 资源描述。
    ///
    /// - Parameter id: skill 目录 ID。
    /// - Returns: skill 资源描述。
    /// - Throws: `validateSkill(id:)` 抛出的错误。
    private func makeSkillResource(id: String) throws -> SkillResource {
        let markdown = try readExistingSkillMarkdownIfPresent(id: id)
        return SkillResource(
            id: id,
            name: skillDisplayName(from: markdown, fallback: id),
            path: skillDirectoryPath(id: id),
            validation: try validateSkill(id: id)
        )
    }

    /// 读取已存在的 `SKILL.md`。
    ///
    /// - Parameter id: skill 目录 ID。
    /// - Returns: `SKILL.md` 文本；文件不存在时返回 `nil`。
    /// - Throws: 文件存在但读取失败时抛出 `FileStore` 错误。
    private func readExistingSkillMarkdownIfPresent(id: String) throws -> String? {
        guard try fileStore.fileExists(at: skillManifestPath(id: id)) else {
            return nil
        }
        return try fileStore.readTextFile(at: skillManifestPath(id: id))
    }

    /// 校验外部 skill 导入源。
    ///
    /// - Parameter sourceDirectoryURL: 用户选择的已有 skill 目录。
    /// - Throws: 源路径不是目录或缺少顶层 `SKILL.md` 时抛出 `invalidSkillImportSource`。
    private func requireValidSkillImportSource(_ sourceDirectoryURL: URL) throws {
        let source = sourceDirectoryURL.standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ResourceValidationError.invalidSkillImportSource(
                path: source.path,
                reason: "Source must be a directory."
            )
        }

        let skillMarkdownURL = source.appendingPathComponent("SKILL.md", isDirectory: false)
        var isSkillMarkdownDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: skillMarkdownURL.path, isDirectory: &isSkillMarkdownDirectory),
              !isSkillMarkdownDirectory.boolValue
        else {
            throw ResourceValidationError.invalidSkillImportSource(
                path: source.path,
                reason: "Source directory must contain SKILL.md."
            )
        }
    }

    /// 构造初始 `SKILL.md` 文本。
    ///
    /// - Parameter id: skill ID。
    /// - Returns: 包含可编辑 `name` 字段的 Markdown 文本。
    private func makeInitialSkillMarkdown(id: String) -> String {
        """
        ---
        name: "\(escapedDoubleQuotedYAMLScalar(id))"
        description: ""
        ---
        """
    }

    /// 从 `SKILL.md` frontmatter 中解析展示名称。
    ///
    /// - Parameters:
    ///   - markdown: 可选 `SKILL.md` 文本。
    ///   - fallback: frontmatter 缺失或 `name` 为空时使用的名称。
    /// - Returns: skill 展示名称。
    private func skillDisplayName(from markdown: String?, fallback: String) -> String {
        guard let name = markdown.flatMap({ skillFrontmatterName(from: $0) }),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return fallback
        }
        return name
    }

    /// 解析 `SKILL.md` 顶部 YAML frontmatter 的 `name` 字段。
    ///
    /// 该解析器只覆盖 Agent Skills 当前需要的简单字符串标量，不尝试实现完整 YAML。
    ///
    /// - Parameter markdown: `SKILL.md` 文本。
    /// - Returns: frontmatter 中的 `name`；缺失或 frontmatter 不完整时返回 `nil`。
    private func skillFrontmatterName(from markdown: String) -> String? {
        let normalizedMarkdown = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalizedMarkdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              firstLine == "---"
        else {
            return nil
        }

        var parsedName: String?
        lines.removeFirst()
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine == "---" || trimmedLine == "..." {
                return parsedName
            }
            guard let firstCharacter = line.first, !firstCharacter.isWhitespace else {
                continue
            }
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#"), trimmedLine.hasPrefix("name:") else {
                continue
            }

            let rawValue = String(trimmedLine.dropFirst("name:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            parsedName = unquotedYAMLScalar(rawValue)
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
