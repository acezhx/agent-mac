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

    /// 验证 skill 可以创建、读取、保存，并且列表会按 ID 稳定排序。
    @Test func skillCreateReadSaveAndList() throws {
        let (library, _, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createSkill(id: "report-writing", skillMarkdown: "# Report\n")
        try library.createSkill(id: "data-cleanup", skillMarkdown: "# Cleanup\n")
        try library.saveSkillMarkdown("# Report v2\n", id: "report-writing")

        let skills = try library.listSkills()

        #expect(try library.readSkillMarkdown(id: "report-writing") == "# Report v2\n")
        #expect(skills.map(\.id) == ["data-cleanup", "report-writing"])
        #expect(skills.allSatisfy { $0.validation.isValid })
        #expect(skills.map(\.kind) == [.skill, .skill])
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

    /// 删除测试创建的临时根目录。
    ///
    /// 清理失败不应影响测试断言，因此这里忽略删除错误。
    ///
    /// - Parameter root: `makeLibrary()` 返回的临时根目录。
    private func removeTemporaryRoot(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }
}
