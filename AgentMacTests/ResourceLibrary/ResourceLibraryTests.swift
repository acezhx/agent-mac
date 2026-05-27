import Foundation
import Testing
@testable import AgentMac

/// `ResourceLibrary` 模块的行为测试集合。
///
/// 所有测试都使用临时 app data 根目录，通过 `FileStore` 准备测试文件，避免依赖真实用户数据。
struct ResourceLibraryTests {
    /// 验证 knowledge 文件可以创建、读取、保存，并且列表只返回支持的可见文本文件。
    @Test func knowledgeCreateReadSaveAndListSupportedFiles() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createKnowledgeFile(named: "refund.md", contents: "退款规则")
        try library.createKnowledgeFile(named: "refund.txt", contents: "退款文本规则")
        try library.createKnowledgeFile(named: "orders.txt", contents: "订单规则")
        try store.writeTextFile("hidden", to: "library/knowledge/.secret.md")
        try store.writeTextFile("metadata", to: "library/knowledge/.DS_Store")
        try store.writeTextFile("json", to: "library/knowledge/config.json")

        try library.saveKnowledgeFile("新退款规则", named: "refund.md")

        #expect(try library.readKnowledgeFile(named: "refund.md") == "新退款规则")
        #expect(try library.listKnowledge().map(\.path) == [
            "library/knowledge/orders.txt",
            "library/knowledge/refund.md",
            "library/knowledge/refund.txt",
        ])
        #expect(try library.listKnowledge().map(\.id) == ["orders.txt", "refund.md", "refund.txt"])
        #expect(try library.listKnowledge().map(\.name) == ["orders", "refund", "refund"])
        #expect(try library.listKnowledge().allSatisfy { $0.validation.isValid })
    }

    /// 验证 knowledge 可以保存时改名，并删除旧文件。
    @Test func knowledgeSaveCanRenameFile() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createKnowledgeFile(named: "refund.md", contents: "退款规则")
        let resource = try library.saveKnowledgeFile("新退款规则", named: "refund.md", renamingTo: "refund-policy.md")

        #expect(resource.id == "refund-policy.md")
        #expect(resource.name == "refund-policy")
        #expect(try library.readKnowledgeFile(named: "refund-policy.md") == "新退款规则")
        #expect(try !store.fileExists(at: "library/knowledge/refund.md"))
        #expect(try library.listKnowledge().map(\.id) == ["refund-policy.md"])
    }

    /// 验证 knowledge 删除会移除文件和列表项。
    @Test func knowledgeDeleteRemovesFile() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createKnowledgeFile(named: "refund.md", contents: "退款规则")
        try library.deleteKnowledgeFile(named: "refund.md")

        #expect(try !store.fileExists(at: "library/knowledge/refund.md"))
        #expect(try library.listKnowledge().isEmpty)
    }

    /// 验证 knowledge 改名不会覆盖已有目标。
    @Test func knowledgeRenameRejectsDuplicateTarget() throws {
        let (library, _, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createKnowledgeFile(named: "refund.md", contents: "退款规则")
        try library.createKnowledgeFile(named: "refund-policy.md", contents: "旧规则")

        do {
            try library.saveKnowledgeFile("新退款规则", named: "refund.md", renamingTo: "refund-policy.md")
            Issue.record("Expected duplicate knowledge file name to be rejected.")
        } catch let ResourceValidationError.duplicateKnowledgeFileName(fileName) {
            #expect(fileName == "refund-policy.md")
            #expect(try library.readKnowledgeFile(named: "refund.md") == "退款规则")
            #expect(try library.readKnowledgeFile(named: "refund-policy.md") == "旧规则")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证非法 knowledge 文件名和不支持的扩展名会被拒绝。
    @Test func knowledgeRejectsUnsafeNamesAndUnsupportedExtensions() throws {
        let (library, _, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        do {
            try library.createKnowledgeFile(named: "nested/refund.md")
            Issue.record("Expected nested knowledge file name to be rejected.")
        } catch let ResourceValidationError.invalidKnowledgeFileName(fileName, reason) {
            #expect(fileName == "nested/refund.md")
            #expect(reason.contains("path separators"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            try library.createKnowledgeFile(named: "refund.pdf")
            Issue.record("Expected unsupported knowledge extension to be rejected.")
        } catch let ResourceValidationError.unsupportedKnowledgeFileExtension(fileName) {
            #expect(fileName == "refund.pdf")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证 skill 可以创建、读取、保存，并且列表会按 ID 稳定排序、从 `SKILL.md` 读取展示名称。
    @Test func skillCreateReadSaveAndList() throws {
        let (library, _, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createSkill(
            id: "report-writing",
            skillMarkdown: """
            ---
            name: "Report Writing"
            description: ""
            ---
            # Report
            """
        )
        try library.createSkill(id: "data-cleanup", skillMarkdown: "# Cleanup\n")
        try library.createSkill(id: "draft-skill")
        try library.saveSkillMarkdown(
            """
            ---
            name: "Report Writer v2"
            description: ""
            ---
            # Report v2
            """,
            id: "report-writing"
        )

        let skills = try library.listSkills()
        let draftMarkdown = try library.readSkillMarkdown(id: "draft-skill")

        #expect(try library.readSkillMarkdown(id: "report-writing").contains("name: \"Report Writer v2\""))
        #expect(draftMarkdown.contains("name: \"draft-skill\""))
        #expect(skills.map(\.id) == ["data-cleanup", "draft-skill", "report-writing"])
        #expect(skills.map(\.name) == ["data-cleanup", "draft-skill", "Report Writer v2"])
        #expect(skills.allSatisfy { $0.validation.isValid })
        #expect(skills.map(\.kind) == [.skill, .skill, .skill])
    }

    /// 验证保存 skill 时可以同步重命名目录，并保留附属文件。
    @Test func skillSaveCanRenameDirectory() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createSkill(id: "skill")
        try store.writeTextFile("guide", to: "library/skills/skill/references/guide.md")

        let resource = try library.saveSkillMarkdown(
            """
            ---
            name: "Report Writing"
            description: ""
            ---
            # Report
            """,
            id: "skill",
            renamingTo: "report-writing"
        )

        #expect(resource.id == "report-writing")
        #expect(resource.name == "Report Writing")
        #expect(try !store.directoryExists(at: "library/skills/skill"))
        #expect(try store.readTextFile(at: "library/skills/report-writing/SKILL.md").contains("Report Writing"))
        #expect(try store.readTextFile(at: "library/skills/report-writing/references/guide.md") == "guide")
        #expect(try library.listSkills().map(\.id) == ["report-writing"])
    }

    /// 验证 skill 改名目标已存在时不会覆盖原目录的 `SKILL.md`。
    @Test func skillRenameRejectsDuplicateTargetWithoutOverwritingMarkdown() throws {
        let (library, _, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createSkill(id: "skill", skillMarkdown: "# Original\n")
        try library.createSkill(id: "report-writing", skillMarkdown: "# Existing\n")

        do {
            try library.saveSkillMarkdown("# New\n", id: "skill", renamingTo: "report-writing")
            Issue.record("Expected duplicate skill target to be rejected.")
        } catch let FileStoreError.writeFailed(path, reason) {
            #expect(path == "library/skills/report-writing")
            #expect(reason.contains("already exists"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(try library.readSkillMarkdown(id: "skill") == "# Original\n")
        #expect(try library.readSkillMarkdown(id: "report-writing") == "# Existing\n")
    }

    /// 验证可以导入已有 skill 目录，并保留 references 等附属文件。
    @Test func skillImportCopiesExistingDirectoryAndReadsName() throws {
        let (library, store, root) = try makeLibrary()
        let source = FileManager.default.temporaryDirectory
            .appending(path: "Existing Skill \(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            removeTemporaryRoot(root)
            removeTemporaryRoot(source)
        }

        try createDirectory(source.appending(path: "references", directoryHint: .isDirectory))
        try """
        ---
        name: "Existing Skill"
        description: ""
        ---
        """.write(to: source.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        try "guide".write(to: source.appending(path: "references/guide.md"), atomically: true, encoding: .utf8)

        let skill = try library.importSkill(from: source, id: "existing-skill")

        #expect(skill.id == "existing-skill")
        #expect(skill.name == "Existing Skill")
        #expect(try library.readSkillMarkdown(id: "existing-skill").contains("name: \"Existing Skill\""))
        #expect(try store.readTextFile(at: "library/skills/existing-skill/references/guide.md") == "guide")
    }

    /// 验证删除 skill 会移除整个 skill 目录。
    @Test func skillDeleteRemovesDirectoryTree() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createSkill(id: "report-writing")
        try store.writeTextFile("guide", to: "library/skills/report-writing/references/guide.md")
        try library.deleteSkill(id: "report-writing")

        #expect(try !store.directoryExists(at: "library/skills/report-writing"))
        #expect(try library.listSkills().isEmpty)
    }

    /// 验证缺少 `SKILL.md` 的 skill 目录会作为无效资源返回。
    @Test func skillValidationReportsMissingSkillMarkdown() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try store.writeTextFile("notes", to: "library/skills/broken-skill/notes.md")

        let status = try library.validateSkill(id: "broken-skill")
        let skills = try library.listSkills()

        #expect(status.errors == [.missingSkillManifest(skillID: "broken-skill")])
        #expect(skills.map(\.id) == ["broken-skill"])
        #expect(skills.first?.validation.errors == [.missingSkillManifest(skillID: "broken-skill")])
    }

    /// 验证非法 skill ID 在创建入口会被拒绝。
    @Test func skillCreateRejectsInvalidID() throws {
        let (library, _, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        do {
            try library.createSkill(id: "BadSkill")
            Issue.record("Expected invalid skill ID to be rejected.")
        } catch let ResourceValidationError.invalidResourceID(kind, id) {
            #expect(kind == .skill)
            #expect(id == "BadSkill")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证 tool 可以创建、读取和保存 manifest 与入口文件。
    @Test func toolCreateReadSaveAndList() throws {
        let (library, _, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createTool(
            id: "ticket-search",
            name: "工单搜索",
            entryContents: "export default async function run() {}\n"
        )
        try library.saveToolEntry("export default async function run(input) { return input }\n", id: "ticket-search")

        let tools = try library.listTools()
        let manifest = try library.readToolManifest(id: "ticket-search")

        #expect(try library.readToolEntry(id: "ticket-search").contains("return input"))
        #expect(manifest.contains("id: ticket-search"))
        #expect(tools.count == 1)
        #expect(tools.first?.id == "ticket-search")
        #expect(tools.first?.name == "工单搜索")
        #expect(tools.first?.entry == "index.js")
        #expect(tools.first?.validation.isValid == true)
    }

    /// 验证删除 tool 会移除整个 tool 目录。
    @Test func toolDeleteRemovesDirectoryTree() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createTool(id: "ticket-search", name: "Ticket Search")
        try store.writeTextFile("fixture", to: "library/tools/ticket-search/nested/fixture.txt")
        try library.deleteTool(id: "ticket-search")

        #expect(try !store.directoryExists(at: "library/tools/ticket-search"))
        #expect(try library.listTools().isEmpty)
    }

    /// 验证 tool 列表会稳定排序，并识别缺失 `tool.yaml` 的目录。
    @Test func toolListSortsAndReportsMissingManifest() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createTool(id: "valid-tool", name: "Valid")
        try store.writeTextFile("entry", to: "library/tools/no-manifest/index.js")

        let tools = try library.listTools()

        #expect(tools.map(\.id) == ["no-manifest", "valid-tool"])
        #expect(tools.first?.validation.errors == [.missingToolManifest(toolID: "no-manifest")])
        #expect(tools.last?.validation.isValid == true)
    }

    /// 验证 `tool.yaml.entry` 缺失或入口文件缺失时会返回对应校验错误。
    @Test func toolValidationReportsMissingEntryAndMissingEntryFile() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try store.writeTextFile(
            """
            id: no-entry
            name: No Entry
            runtime: node
            """,
            to: "library/tools/no-entry/tool.yaml"
        )
        try store.writeTextFile(
            """
            id: missing-entry-file
            name: Missing Entry
            runtime: node
            entry: index.js
            """,
            to: "library/tools/missing-entry-file/tool.yaml"
        )

        #expect(try library.validateTool(id: "no-entry").errors == [.missingToolEntry(toolID: "no-entry")])
        #expect(try library.validateTool(id: "missing-entry-file").errors == [
            .missingToolEntryFile(toolID: "missing-entry-file", entry: "index.js"),
        ])
    }

    /// 验证 `tool.yaml.entry` 不能逃逸当前 tool 目录。
    @Test func toolValidationRejectsEscapingEntryPath() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try store.writeTextFile(
            """
            id: escaping-tool
            name: Escaping Tool
            runtime: node
            entry: ../outside.js
            """,
            to: "library/tools/escaping-tool/tool.yaml"
        )
        try store.writeTextFile("outside", to: "library/tools/outside.js")

        let status = try library.validateTool(id: "escaping-tool")

        #expect(status.errors == [
            .invalidToolEntry(
                toolID: "escaping-tool",
                entry: "../outside.js",
                reason: "Entry must stay inside the tool directory."
            ),
        ])
    }

    /// 验证 tool 创建入口会拒绝非法 ID、空名称和越界入口。
    @Test func toolCreateRejectsInvalidInputs() throws {
        let (library, _, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        do {
            try library.createTool(id: "BadTool", name: "Bad")
            Issue.record("Expected invalid tool ID to be rejected.")
        } catch let ResourceValidationError.invalidResourceID(kind, id) {
            #expect(kind == .tool)
            #expect(id == "BadTool")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            try library.createTool(id: "empty-name", name: " ")
            Issue.record("Expected empty tool name to be rejected.")
        } catch let ResourceValidationError.emptyToolName(toolID) {
            #expect(toolID == "empty-name")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            try library.createTool(id: "bad-entry", name: "Bad Entry", entryFileName: "../index.js")
            Issue.record("Expected escaping tool entry to be rejected.")
        } catch let ResourceValidationError.invalidToolEntry(toolID, entry, reason) {
            #expect(toolID == "bad-entry")
            #expect(entry == "../index.js")
            #expect(reason.contains("inside the tool directory"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 创建测试用 ResourceLibrary。
    ///
    /// - Returns: 资源库服务、底层 FileStore 和测试结束后需要删除的临时根目录。
    private func makeLibrary() throws -> (ResourceLibrary, FileStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AgentMac-ResourceLibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = FileStore(rootDirectory: root)
        try store.initialize()
        return (ResourceLibrary(fileStore: store), store, root)
    }

    /// 创建测试用目录。
    ///
    /// - Parameter url: 要创建的绝对目录 URL。
    private func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// 删除测试创建的临时根目录。
    ///
    /// 清理失败不应影响测试断言，因此这里忽略删除错误。
    ///
    /// - Parameter root: `makeLibrary()` 返回的临时根目录。
    private func removeTemporaryRoot(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }
}
