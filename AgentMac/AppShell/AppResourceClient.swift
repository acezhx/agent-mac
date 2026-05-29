import ComposableArchitecture
import Foundation

/// AppShell Resource 管理页面使用的资源类型。
nonisolated enum AppResourceKind: String, CaseIterable, Equatable, Hashable, Sendable {
    /// 共享 knowledge 文件。
    case knowledge

    /// 共享 skill 目录。
    case skill

    /// 共享 tool 目录。
    case tool

    /// UI 展示标题。
    var title: String {
        switch self {
        case .knowledge:
            "Knowledge"
        case .skill:
            "Skills"
        case .tool:
            "Tools"
        }
    }

    /// 单个资源展示名称。
    var itemTitle: String {
        switch self {
        case .knowledge:
            "Knowledge"
        case .skill:
            "Skill"
        case .tool:
            "Tool"
        }
    }

    /// SF Symbol 图标名称。
    var systemImage: String {
        switch self {
        case .knowledge:
            "doc.text"
        case .skill:
            "wand.and.stars"
        case .tool:
            "hammer"
        }
    }

    /// 主编辑器标题。
    var primaryEditorTitle: String {
        switch self {
        case .knowledge:
            "Contents"
        case .skill:
            "SKILL.md"
        case .tool:
            "tool.yaml"
        }
    }

}

/// AppShell Resource 列表中展示的资源摘要。
nonisolated struct AppResourceSummary: Equatable, Identifiable, Sendable {
    /// Resource 类型。
    let kind: AppResourceKind

    /// Resource ID。
    let id: String

    /// UI 展示名称。
    var name: String

    /// Resource 相对路径。
    let path: String

    /// 辅助展示文本。
    let detail: String

    /// 校验错误文本。
    let validationMessages: [String]

    /// Resource 是否通过最小结构校验。
    var isValid: Bool {
        validationMessages.isEmpty
    }

    /// 写入 `agent.yaml` 时使用的共享资源引用路径。
    ///
    /// `ResourceLibrary` 对 UI 暴露 app data 相对路径，Agent manifest 持久化时需要保存为相对
    /// `agents/<agent-id>/agent.yaml` 所在目录的路径。
    var agentManifestReference: String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPath.hasPrefix("../") {
            return trimmedPath
        }
        return "../../\(trimmedPath)"
    }
}

/// AppShell Resource 编辑区使用的文档模型。
nonisolated struct AppResourceDocument: Equatable, Identifiable, Sendable {
    /// Resource 类型。
    let kind: AppResourceKind

    /// Resource ID。
    let id: String

    /// UI 展示名称。
    var name: String

    /// Resource 相对路径。
    let path: String

    /// 主编辑内容。knowledge 为文件内容，skill 为 `SKILL.md`，tool 为 `tool.yaml`。
    var primaryContent: String

    /// tool 入口文件内容；非 tool 资源为 `nil`。
    var secondaryContent: String?

    /// 校验错误文本。
    let validationMessages: [String]

    /// 当前文档对应的列表摘要。
    var summary: AppResourceSummary {
        AppResourceSummary(
            kind: kind,
            id: id,
            name: name,
            path: path,
            detail: detail,
            validationMessages: validationMessages
        )
    }

    /// 列表辅助展示文本。
    var detail: String {
        switch kind {
        case .knowledge, .skill:
            path
        case .tool:
            "entry: \(toolEntryDescription)"
        }
    }

    /// tool 入口展示文本。
    private var toolEntryDescription: String {
        guard let entry = topLevelScalar(named: "entry", in: primaryContent),
              !entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return "missing"
        }
        return entry
    }

    /// 解析 YAML 顶层字符串标量。
    ///
    /// 第一版只用于展示 tool 入口，不作为持久化校验来源。
    ///
    /// - Parameters:
    ///   - name: 顶层字段名。
    ///   - yaml: YAML 文本。
    /// - Returns: 字段值；不存在时返回 `nil`。
    private func topLevelScalar(named name: String, in yaml: String) -> String? {
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let rawLine = String(line)
            guard let firstCharacter = rawLine.first, !firstCharacter.isWhitespace else {
                continue
            }

            let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#"), trimmedLine.hasPrefix("\(name):") else {
                continue
            }

            let rawValue = String(trimmedLine.dropFirst(name.count + 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if rawValue.hasPrefix("\""), rawValue.hasSuffix("\""), rawValue.count >= 2 {
                return String(rawValue.dropFirst().dropLast())
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
            }
            if rawValue.hasPrefix("'"), rawValue.hasSuffix("'"), rawValue.count >= 2 {
                return String(rawValue.dropFirst().dropLast())
                    .replacingOccurrences(of: "''", with: "'")
            }
            if let commentStart = rawValue.firstIndex(of: "#") {
                return String(rawValue[..<commentStart]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return rawValue
        }

        return nil
    }
}

/// AppShell 通过 TCA dependency 使用的 Resource 管理边界。
///
/// 该类型把 `ResourceLibrary` 包装成 Feature 可注入的操作，避免 SwiftUI View 直接持有底层服务对象。
nonisolated struct AppResourceClient: Sendable {
    /// 加载指定类型资源摘要列表。
    var listResources: @Sendable (_ kind: AppResourceKind) async throws -> [AppResourceSummary]

    /// 加载单个资源编辑文档。
    var loadResource: @Sendable (_ kind: AppResourceKind, _ id: String) async throws -> AppResourceDocument

    /// 创建资源。
    var createResource: @Sendable (
        _ kind: AppResourceKind,
        _ id: String,
        _ name: String
    ) async throws -> AppResourceDocument

    /// 导入已有 skill 目录。
    var importSkillDirectory: @Sendable (_ sourceDirectoryPath: String) async throws -> AppResourceDocument

    /// 保存资源编辑文档。
    var saveResource: @Sendable (_ document: AppResourceDocument) async throws -> AppResourceDocument

    /// 删除资源。
    var deleteResource: @Sendable (_ kind: AppResourceKind, _ id: String) async throws -> Void

    /// 基于已有 knowledge ID 生成一个未占用的新文件名。
    ///
    /// 第一版使用稳定的 `knowledge.md`、`knowledge-2.md`、`knowledge-3.md` 命名序列，避免 UI
    /// 侧暴露文件名或要求用户手动处理重复 ID。已有 `.txt` 文件的同名 stem 也会避开，避免列表展示重名。
    ///
    /// - Parameter existingIDs: 已存在的 knowledge ID 列表。
    /// - Returns: 未被占用的新 knowledge 文件名。
    static func makeUniqueKnowledgeFileName(existingIDs: [String]) -> String {
        let existingIDs = Set(existingIDs.map { $0.lowercased() })
        let existingStems = Set(existingIDs.map { ($0 as NSString).deletingPathExtension })
        let baseName = "knowledge"

        var suffix: Int?
        while true {
            let stem = suffix.map { "\(baseName)-\($0)" } ?? baseName
            let candidate = "\(stem).md"
            if !existingIDs.contains(candidate), !existingStems.contains(stem) {
                return candidate
            }
            suffix = (suffix ?? 1) + 1
        }
    }

    /// 根据用户编辑的 knowledge 展示名称生成文件名，并保留当前文件扩展名。
    ///
    /// - Parameters:
    ///   - displayName: 用户在 UI 中编辑的 knowledge 名称。
    ///   - currentFileName: 当前 knowledge 文件名，用于保留 `.md` 或 `.txt` 扩展名。
    /// - Returns: 可传给 `ResourceLibrary` 校验和保存的新文件名。
    /// - Throws: 名称为空时抛出 UI 可展示错误。
    static func makeKnowledgeFileName(displayName: String, currentFileName: String) throws -> String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw AppResourceClientError("Knowledge name cannot be empty.")
        }

        let typedExtension = (trimmedName as NSString).pathExtension.lowercased()
        let stem = ResourceLibrary.knowledgeExtensions.contains(typedExtension)
            ? (trimmedName as NSString).deletingPathExtension
            : trimmedName
        let currentExtension = (currentFileName as NSString).pathExtension.lowercased()
        let fileExtension = ResourceLibrary.knowledgeExtensions.contains(currentExtension)
            ? currentExtension
            : "md"
        return "\(stem).\(fileExtension)"
    }

    /// 基于已有 skill ID 生成一个未占用的新 ID。
    ///
    /// 第一版使用稳定的 `skill`、`skill-2`、`skill-3` 命名序列，避免 UI 侧要求用户手动处理重复 ID。
    ///
    /// - Parameter existingIDs: 已存在的 skill ID 列表。
    /// - Returns: 未被占用的新 skill ID。
    static func makeUniqueSkillID(existingIDs: [String]) -> String {
        makeUniqueSkillID(preferredBaseID: "skill", existingIDs: existingIDs)
    }

    /// 基于首选名称和已有 skill ID 生成一个未占用的新 ID。
    ///
    /// - Parameters:
    ///   - preferredBaseID: 首选基础 ID，通常来自导入目录名。
    ///   - existingIDs: 已存在的 skill ID 列表。
    /// - Returns: 未被占用的新 skill ID。
    static func makeUniqueSkillID(preferredBaseID: String, existingIDs: [String]) -> String {
        let existingIDs = Set(existingIDs)
        let baseID = makeSkillIDBase(from: preferredBaseID)
        guard existingIDs.contains(baseID) else {
            return baseID
        }

        var suffix = 2
        var candidate = suffixedResourceID(baseID: baseID, suffix: suffix, fallback: "skill")
        while existingIDs.contains(candidate) {
            suffix += 1
            candidate = suffixedResourceID(baseID: baseID, suffix: suffix, fallback: "skill")
        }
        return candidate
    }

    /// 将任意目录名转换成符合项目规则的 skill ID 基础名。
    ///
    /// - Parameter rawName: 用户选择的源目录名。
    /// - Returns: 小写、短横线分隔、长度合法的 skill ID 基础名。
    static func makeSkillIDBase(from rawName: String) -> String {
        makeDirectoryResourceIDBase(from: rawName, fallback: "skill")
    }

    /// 基于已有 tool ID 生成一个未占用的新 ID。
    ///
    /// 第一版使用稳定的 `tool`、`tool-2`、`tool-3` 命名序列，避免 UI 侧要求用户手动处理重复 ID。
    /// tool 的展示名称由用户在 `tool.yaml` 的 `name` 字段中维护。
    ///
    /// - Parameter existingIDs: 已存在的 tool ID 列表。
    /// - Returns: 未被占用的新 tool ID。
    static func makeUniqueToolID(existingIDs: [String]) -> String {
        let existingIDs = Set(existingIDs)
        let baseID = "tool"
        guard existingIDs.contains(baseID) else {
            return baseID
        }

        var suffix = 2
        var candidate = suffixedResourceID(baseID: baseID, suffix: suffix, fallback: "tool")
        while existingIDs.contains(candidate) {
            suffix += 1
            candidate = suffixedResourceID(baseID: baseID, suffix: suffix, fallback: "tool")
        }
        return candidate
    }

    private static func makeDirectoryResourceIDBase(from rawName: String, fallback: String) -> String {
        var characters: [Character] = []
        var previousWasHyphen = false
        for scalar in rawName.lowercased().unicodeScalars {
            let isAllowed = scalar.value == 45 || (48...57).contains(scalar.value) || (97...122).contains(scalar.value)
            if isAllowed {
                let character = Character(scalar)
                if character == "-" {
                    if !previousWasHyphen {
                        characters.append(character)
                    }
                    previousWasHyphen = true
                } else {
                    characters.append(character)
                    previousWasHyphen = false
                }
            } else if !previousWasHyphen {
                characters.append("-")
                previousWasHyphen = true
            }
        }

        let trimmed = String(characters)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let limited = String(trimmed.prefix(64))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return limited.count >= 2 ? limited : fallback
    }

    private static func suffixedResourceID(baseID: String, suffix: Int, fallback: String) -> String {
        let suffixText = "-\(suffix)"
        let maxBaseLength = max(2, 64 - suffixText.count)
        let limitedBase = String(baseID.prefix(maxBaseLength))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let safeBase = limitedBase.count >= 2 ? limitedBase : fallback
        return "\(safeBase)\(suffixText)"
    }
}

/// AppShell dependency 对 Resource UI 暴露的结构化错误。
nonisolated struct AppResourceClientError: Error, Equatable, Sendable {
    /// 可直接用于 UI 展示或测试断言的错误信息。
    let message: String

    /// 创建 Resource UI 错误。
    ///
    /// - Parameter message: 错误信息。
    init(_ message: String) {
        self.message = message
    }

    /// 从底层错误创建 Resource UI 错误。
    ///
    /// - Parameter error: 底层服务错误。
    init(_ error: Error) {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            self.message = description
        } else {
            self.message = error.localizedDescription
        }
    }
}

extension AppResourceClientError: LocalizedError {
    /// 面向 UI 的错误描述。
    var errorDescription: String? {
        message
    }
}

extension AppResourceClient: DependencyKey {
    /// App 运行时使用的真实 dependency。
    static let liveValue: AppResourceClient = {
        let controller = LiveResourceLibraryController()
        return AppResourceClient(
            listResources: { kind in
                try await controller.listResources(kind: kind)
            },
            loadResource: { kind, id in
                try await controller.loadResource(kind: kind, id: id)
            },
            createResource: { kind, id, name in
                try await controller.createResource(kind: kind, id: id, name: name)
            },
            importSkillDirectory: { sourceDirectoryPath in
                try await controller.importSkillDirectory(sourceDirectoryPath)
            },
            saveResource: { document in
                try await controller.saveResource(document)
            },
            deleteResource: { kind, id in
                try await controller.deleteResource(kind: kind, id: id)
            }
        )
    }()

    /// 测试默认值；具体测试应显式注入 mock。
    static let testValue = AppResourceClient(
        listResources: { _ in
            throw AppResourceClientError("AppResourceClient.listResources is not implemented for this test.")
        },
        loadResource: { _, _ in
            throw AppResourceClientError("AppResourceClient.loadResource is not implemented for this test.")
        },
        createResource: { _, _, _ in
            throw AppResourceClientError("AppResourceClient.createResource is not implemented for this test.")
        },
        importSkillDirectory: { _ in
            throw AppResourceClientError("AppResourceClient.importSkillDirectory is not implemented for this test.")
        },
        saveResource: { _ in
            throw AppResourceClientError("AppResourceClient.saveResource is not implemented for this test.")
        },
        deleteResource: { _, _ in
            throw AppResourceClientError("AppResourceClient.deleteResource is not implemented for this test.")
        }
    )
}

extension DependencyValues {
    /// AppShell Resource 管理 dependency。
    var appResourceClient: AppResourceClient {
        get { self[AppResourceClient.self] }
        set { self[AppResourceClient.self] = newValue }
    }
}

/// AppShell live dependency 使用的 ResourceLibrary 控制器。
///
/// 该 actor 只负责初始化 Application Support 文件服务并持有 `ResourceLibrary` 实例，不把 TCA
/// 下沉到 ResourceLibrary。
private actor LiveResourceLibraryController {
    private var library: ResourceLibrary?

    /// 加载指定类型资源摘要列表。
    ///
    /// - Parameter kind: Resource 类型。
    /// - Returns: 资源摘要列表。
    func listResources(kind: AppResourceKind) throws -> [AppResourceSummary] {
        switch kind {
        case .knowledge:
            return try resourceLibrary().listKnowledge().map(makeSummary)
        case .skill:
            return try resourceLibrary().listSkills().map(makeSummary)
        case .tool:
            return try resourceLibrary().listTools().map(makeSummary)
        }
    }

    /// 加载单个资源编辑文档。
    ///
    /// - Parameters:
    ///   - kind: Resource 类型。
    ///   - id: Resource ID。
    /// - Returns: 编辑文档。
    func loadResource(kind: AppResourceKind, id: String) throws -> AppResourceDocument {
        switch kind {
        case .knowledge:
            let resource = try resourceLibrary()
                .listKnowledge()
                .first { $0.id == id } ?? KnowledgeResource(
                    id: id,
                    name: (id as NSString).deletingPathExtension,
                    path: ResourceLibrary.knowledgeDirectory + "/\(id)",
                    validation: ResourceValidationStatus()
                )
            let contents = try resourceLibrary().readKnowledgeFile(named: id)
            return AppResourceDocument(
                kind: .knowledge,
                id: resource.id,
                name: resource.name,
                path: resource.path,
                primaryContent: contents,
                secondaryContent: nil,
                validationMessages: validationMessages(resource.validation)
            )

        case .skill:
            let resource = try resourceLibrary()
                .listSkills()
                .first { $0.id == id } ?? SkillResource(
                    id: id,
                    name: id,
                    path: ResourceLibrary.skillsDirectory + "/\(id)",
                    validation: try resourceLibrary().validateSkill(id: id)
                )
            let markdown = try resourceLibrary().readSkillMarkdown(id: id)
            return AppResourceDocument(
                kind: .skill,
                id: resource.id,
                name: resource.name,
                path: resource.path,
                primaryContent: markdown,
                secondaryContent: nil,
                validationMessages: validationMessages(resource.validation)
            )

        case .tool:
            let resource = try resourceLibrary()
                .listTools()
                .first { $0.id == id } ?? ToolResource(
                    id: id,
                    name: id,
                    path: ResourceLibrary.toolsDirectory + "/\(id)",
                    entry: nil,
                    validation: try resourceLibrary().validateTool(id: id)
                )
            let manifest = try resourceLibrary().readToolManifest(id: id)
            let entryContents = (try? resourceLibrary().readToolEntry(id: id)) ?? ""
            return AppResourceDocument(
                kind: .tool,
                id: resource.id,
                name: resource.name,
                path: resource.path,
                primaryContent: manifest,
                secondaryContent: entryContents,
                validationMessages: validationMessages(resource.validation)
            )
        }
    }

    /// 创建资源。
    ///
    /// - Parameters:
    ///   - kind: Resource 类型。
    ///   - id: 兼容测试和调用边界的占位参数；当前所有类型都由 AppShell 自动生成 ID。
    ///   - name: 兼容测试和调用边界的占位参数；tool 展示名称由 `tool.yaml` 内容维护。
    /// - Returns: 创建后的编辑文档。
    func createResource(kind: AppResourceKind, id _: String, name _: String) throws -> AppResourceDocument {
        let library = try resourceLibrary()

        switch kind {
        case .knowledge:
            let fileName = AppResourceClient.makeUniqueKnowledgeFileName(existingIDs: try library.listKnowledge().map(\.id))
            try library.createKnowledgeFile(named: fileName)
            return try loadResource(kind: kind, id: fileName)

        case .skill:
            let skillID = AppResourceClient.makeUniqueSkillID(existingIDs: try library.listSkills().map(\.id))
            try library.createSkill(id: skillID)
            return try loadResource(kind: kind, id: skillID)

        case .tool:
            let toolID = AppResourceClient.makeUniqueToolID(existingIDs: try library.listTools().map(\.id))
            try library.createTool(id: toolID, name: toolID)
            return try loadResource(kind: kind, id: toolID)
        }
    }

    /// 导入已有 skill 目录。
    ///
    /// - Parameter sourceDirectoryPath: 用户选择的源目录绝对路径。
    /// - Returns: 导入后的编辑文档。
    func importSkillDirectory(_ sourceDirectoryPath: String) throws -> AppResourceDocument {
        let library = try resourceLibrary()
        let sourceDirectoryURL = URL(fileURLWithPath: sourceDirectoryPath, isDirectory: true)
        let skillID = AppResourceClient.makeUniqueSkillID(
            preferredBaseID: sourceDirectoryURL.lastPathComponent,
            existingIDs: try library.listSkills().map(\.id)
        )
        try library.importSkill(from: sourceDirectoryURL, id: skillID)
        return try loadResource(kind: .skill, id: skillID)
    }

    /// 保存资源编辑文档。
    ///
    /// - Parameter document: Resource 编辑文档。
    /// - Returns: 保存后的编辑文档。
    func saveResource(_ document: AppResourceDocument) throws -> AppResourceDocument {
        switch document.kind {
        case .knowledge:
            let fileName = try AppResourceClient.makeKnowledgeFileName(
                displayName: document.name,
                currentFileName: document.id
            )
            try resourceLibrary().saveKnowledgeFile(document.primaryContent, named: document.id, renamingTo: fileName)
            return try loadResource(kind: document.kind, id: fileName)
        case .skill:
            try resourceLibrary().saveSkillMarkdown(document.primaryContent, id: document.id)
            return try loadResource(kind: document.kind, id: document.id)
        case .tool:
            try resourceLibrary().saveToolManifest(document.primaryContent, id: document.id)
            try resourceLibrary().saveToolEntry(document.secondaryContent ?? "", id: document.id)
        }
        return try loadResource(kind: document.kind, id: document.id)
    }

    /// 删除资源。
    ///
    /// - Parameters:
    ///   - kind: Resource 类型。
    ///   - id: Resource ID。
    func deleteResource(kind: AppResourceKind, id: String) throws {
        switch kind {
        case .knowledge:
            try resourceLibrary().deleteKnowledgeFile(named: id)
        case .skill:
            try resourceLibrary().deleteSkill(id: id)
        case .tool:
            try resourceLibrary().deleteTool(id: id)
        }
    }

    private func resourceLibrary() throws -> ResourceLibrary {
        if let library {
            return library
        }

        let fileStore = try FileStore()
        try fileStore.initialize()
        let library = ResourceLibrary(fileStore: fileStore)
        self.library = library
        return library
    }

    private func makeSummary(_ resource: KnowledgeResource) -> AppResourceSummary {
        AppResourceSummary(
            kind: .knowledge,
            id: resource.id,
            name: resource.name,
            path: resource.path,
            detail: resource.path,
            validationMessages: validationMessages(resource.validation)
        )
    }

    private func makeSummary(_ resource: SkillResource) -> AppResourceSummary {
        AppResourceSummary(
            kind: .skill,
            id: resource.id,
            name: resource.name,
            path: resource.path,
            detail: resource.path,
            validationMessages: validationMessages(resource.validation)
        )
    }

    private func makeSummary(_ resource: ToolResource) -> AppResourceSummary {
        AppResourceSummary(
            kind: .tool,
            id: resource.id,
            name: resource.name,
            path: resource.path,
            detail: resource.entry.map { "entry: \($0)" } ?? resource.path,
            validationMessages: validationMessages(resource.validation)
        )
    }

    private func validationMessages(_ status: ResourceValidationStatus) -> [String] {
        status.errors.map { $0.localizedDescription }
    }
}
