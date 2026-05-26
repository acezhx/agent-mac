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
}
