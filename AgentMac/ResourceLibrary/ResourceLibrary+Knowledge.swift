import Foundation

nonisolated extension ResourceLibrary {
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

    /// 保存 knowledge 文件内容，并在需要时改名。
    ///
    /// 当 `newFileName` 与当前文件名不同时，该方法会写入新文件并删除旧文件；目标文件已存在时不会覆盖。
    ///
    /// - Parameters:
    ///   - contents: 要写入的 UTF-8 文本内容。
    ///   - fileName: 当前 `library/knowledge/` 下的一级文件名。
    ///   - newFileName: 新的 `library/knowledge/` 下一级文件名，必须使用 `.md` 或 `.txt`。
    /// - Returns: 保存后的 knowledge 资源描述。
    /// - Throws: 文件名非法、源文件不存在、目标文件已存在或写入失败。
    @discardableResult
    func saveKnowledgeFile(_ contents: String, named fileName: String, renamingTo newFileName: String) throws -> KnowledgeResource {
        try validateKnowledgeFileName(fileName)
        try validateKnowledgeFileName(newFileName)

        guard fileName != newFileName else {
            return try saveKnowledgeFile(contents, named: fileName)
        }

        let currentPath = knowledgePath(fileName: fileName)
        let newPath = knowledgePath(fileName: newFileName)
        guard try fileStore.fileExists(at: currentPath) else {
            throw FileStoreError.fileNotFound(path: currentPath)
        }
        guard try !fileStore.fileExists(at: newPath) else {
            throw ResourceValidationError.duplicateKnowledgeFileName(fileName: newFileName)
        }

        try fileStore.writeTextFile(contents, to: newPath)
        try fileStore.deleteFile(at: currentPath)
        return makeKnowledgeResource(fileName: newFileName)
    }

    /// 删除 knowledge 文件。
    ///
    /// - Parameter fileName: `library/knowledge/` 下的一级文件名。
    /// - Throws: 文件名非法、文件不存在或删除失败。
    func deleteKnowledgeFile(named fileName: String) throws {
        try validateKnowledgeFileName(fileName)
        try fileStore.deleteFile(at: knowledgePath(fileName: fileName))
    }

    /// 根据文件名构造 knowledge 资源描述。
    ///
    /// - Parameter fileName: `library/knowledge/` 下的文件名。
    /// - Returns: knowledge 资源描述。
    private func makeKnowledgeResource(fileName: String) -> KnowledgeResource {
        KnowledgeResource(
            id: fileName,
            name: (fileName as NSString).deletingPathExtension,
            path: knowledgePath(fileName: fileName),
            validation: ResourceValidationStatus()
        )
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
}
