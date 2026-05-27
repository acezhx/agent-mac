import Testing
@testable import AgentMac

/// AppShell Resource dependency 辅助逻辑测试。
struct AppResourceClientTests {
    /// 验证自动 knowledge 文件名会避开已有 ID 和同名展示 stem。
    @Test func uniqueKnowledgeFileNameUsesFirstAvailableGeneratedID() {
        #expect(AppResourceClient.makeUniqueKnowledgeFileName(existingIDs: []) == "knowledge.md")
        #expect(AppResourceClient.makeUniqueKnowledgeFileName(existingIDs: ["knowledge.md"]) == "knowledge-2.md")
        #expect(AppResourceClient.makeUniqueKnowledgeFileName(existingIDs: ["knowledge.md", "knowledge-2.md"]) == "knowledge-3.md")
        #expect(AppResourceClient.makeUniqueKnowledgeFileName(existingIDs: ["knowledge.txt"]) == "knowledge-2.md")
        #expect(AppResourceClient.makeUniqueKnowledgeFileName(existingIDs: ["Knowledge.md"]) == "knowledge-2.md")
    }

    /// 验证 knowledge 展示名会转换为保留当前扩展名的新文件名。
    @Test func knowledgeDisplayNameUsesCurrentFileExtension() throws {
        #expect(try AppResourceClient.makeKnowledgeFileName(displayName: "Refund Policy", currentFileName: "refund.md") == "Refund Policy.md")
        #expect(try AppResourceClient.makeKnowledgeFileName(displayName: "Refund Policy.md", currentFileName: "refund.txt") == "Refund Policy.txt")

        do {
            _ = try AppResourceClient.makeKnowledgeFileName(displayName: "   ", currentFileName: "refund.md")
            Issue.record("Expected empty knowledge name to be rejected.")
        } catch let error as AppResourceClientError {
            #expect(error.message == "Knowledge name cannot be empty.")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证自动 skill ID 会避开已有 ID。
    @Test func uniqueSkillIDUsesFirstAvailableGeneratedID() {
        #expect(AppResourceClient.makeUniqueSkillID(existingIDs: []) == "skill")
        #expect(AppResourceClient.makeUniqueSkillID(existingIDs: ["skill"]) == "skill-2")
        #expect(AppResourceClient.makeUniqueSkillID(existingIDs: ["skill", "skill-2"]) == "skill-3")
        #expect(AppResourceClient.makeUniqueSkillID(existingIDs: ["skill", "skill-3"]) == "skill-2")
    }

    /// 验证导入时会从目录名生成合法且不重复的 skill ID。
    @Test func uniqueSkillIDUsesImportedDirectoryNameWhenAvailable() {
        #expect(AppResourceClient.makeSkillIDBase(from: "Report Writing") == "report-writing")
        #expect(AppResourceClient.makeSkillIDBase(from: "报告写作") == "skill")
        #expect(
            AppResourceClient.makeUniqueSkillID(
                preferredBaseID: "Report Writing",
                existingIDs: ["report-writing"]
            ) == "report-writing-2"
        )
    }

    /// 验证自动 tool ID 会避开已有 ID。
    @Test func uniqueToolIDUsesFirstAvailableGeneratedID() {
        #expect(AppResourceClient.makeUniqueToolID(existingIDs: []) == "tool")
        #expect(AppResourceClient.makeUniqueToolID(existingIDs: ["tool"]) == "tool-2")
        #expect(AppResourceClient.makeUniqueToolID(existingIDs: ["tool", "tool-2"]) == "tool-3")
        #expect(AppResourceClient.makeUniqueToolID(existingIDs: ["tool", "tool-3"]) == "tool-2")
    }
}
