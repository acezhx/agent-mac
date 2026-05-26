import Foundation
import Testing
@testable import AgentMac

/// `AgentLibrary` 模块的行为测试集合。
///
/// 所有测试都使用临时 app data 根目录，避免读取或写入真实 Application Support 数据。
struct AgentLibraryTests {
    /// 验证创建 Agent 会生成 `agent.yaml` 和私有 `system.md`，并能通过列表和加载入口读取。
    @Test func createAgentWritesManifestSystemPromptAndListsSummary() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createAgent(id: "ecommerce", name: "电商运营助手", systemPrompt: "你是运营助手。")

        #expect(try store.fileExists(at: "agents/ecommerce/agent.yaml"))
        #expect(try store.fileExists(at: "agents/ecommerce/system.md"))
        #expect(try store.readTextFile(at: "agents/ecommerce/system.md") == "你是运营助手。")

        let loaded = try library.loadAgent(id: "ecommerce")
        let summaries = try library.listAgents()

        #expect(loaded.manifest.id == "ecommerce")
        #expect(loaded.manifest.name == "电商运营助手")
        #expect(loaded.manifest.model == .default)
        #expect(loaded.manifest.permissions == .default)
        #expect(loaded.systemPrompt == "你是运营助手。")
        #expect(summaries == [AgentSummary(id: "ecommerce", name: "电商运营助手", model: .default)])
    }

    /// 验证保存 Agent 后重新加载会保留基础信息、模型配置、权限配置和资源选择。
    @Test func saveAgentPersistsManifestResourcesAndSystemPrompt() throws {
        let (library, _, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        var agent = try library.createAgent(id: "support-bot", name: "Support")
        agent.manifest.name = "客服助手"
        agent.manifest.model = ModelConfig(provider: "openai", name: "gpt-5")
        agent.manifest.knowledge = ["../../library/knowledge/refund.md"]
        agent.manifest.skills = ["../../library/skills/report-writing"]
        agent.manifest.tools = ["../../library/tools/ticket-search"]
        agent.manifest.permissions = PermissionConfig(bash: .deny, edit: .ask, network: .allow)
        agent.systemPrompt = "请严格遵守退款政策。"

        try library.saveAgent(agent)
        let loaded = try library.loadAgent(id: "support-bot")

        #expect(loaded == agent)
    }

    /// 验证保存 Agent 不允许通过修改 manifest ID 隐式写入另一个 Agent 目录。
    @Test func saveAgentRejectsManifestIDChanges() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        var agent = try library.createAgent(id: "support-bot", name: "Support")
        agent.manifest.id = "renamed-bot"

        do {
            try library.saveAgent(agent)
            Issue.record("Expected manifest ID changes to be rejected.")
        } catch let AgentValidationError.manifestIDMismatch(directoryID, manifestID) {
            #expect(directoryID == "support-bot")
            #expect(manifestID == "renamed-bot")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(try store.fileExists(at: "agents/support-bot/agent.yaml"))
        #expect(try !store.directoryExists(at: "agents/renamed-bot"))
    }

    /// 验证写入 `agent.yaml` 的双引号标量会转义换行、Tab、引号和反斜杠，并可重新加载。
    @Test func saveAgentRoundTripsEscapedYAMLScalars() throws {
        let (library, _, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        var agent = try library.createAgent(id: "escaped-agent", name: "Initial")
        agent.manifest.name = "客服 \"助手\"\n二线"
        agent.manifest.model = ModelConfig(provider: "open\\ai", name: "gpt\t5\r\ncodex")
        agent.manifest.systemPrompt = "prompts/system\nquote\".md"
        agent.manifest.knowledge = ["../../library/knowledge/refund\\policy.md", "../../library/knowledge/line\nbreak.md"]
        agent.manifest.skills = ["../../library/skills/report\\writing"]
        agent.manifest.tools = ["../../library/tools/ticket\"search"]
        agent.systemPrompt = "系统提示内容"

        try library.saveAgent(agent)
        let loaded = try library.loadAgent(id: "escaped-agent")

        #expect(loaded == agent)
    }

    /// 验证非法 Agent ID 和重复 ID 会返回明确错误。
    @Test func createAgentRejectsInvalidAndDuplicateIDs() throws {
        let (library, _, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        do {
            try library.createAgent(id: "BadAgent", name: "Bad")
            Issue.record("Expected invalid agent ID to be rejected.")
        } catch let AgentValidationError.invalidAgentID(id) {
            #expect(id == "BadAgent")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        try library.createAgent(id: "valid-agent", name: "Valid")
        do {
            try library.createAgent(id: "valid-agent", name: "Valid Again")
            Issue.record("Expected duplicate agent ID to be rejected.")
        } catch let AgentLibraryError.duplicateAgentID(id) {
            #expect(id == "valid-agent")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证缺失 Agent 目录或缺失 `agent.yaml` 时会返回结构化校验错误。
    @Test func validationReportsMissingAgentDirectoryAndManifest() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        #expect(try library.validateAgent(id: "missing-agent").errors == [
            .missingAgentDirectory(agentID: "missing-agent"),
        ])

        try store.writeTextFile("", to: "agents/no-manifest/system.md")

        #expect(try library.validateAgent(id: "no-manifest").errors == [
            .missingManifest(agentID: "no-manifest"),
        ])
    }

    /// 验证 manifest 中的 Agent ID 必须与目录名一致。
    @Test func validationReportsManifestIDMismatch() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try store.writeTextFile(
            """
            id: other-agent
            name: Mismatch

            model:
              provider: openai
              name: gpt-5-codex

            systemPrompt: system.md
            """,
            to: "agents/expected-agent/agent.yaml"
        )
        try store.writeTextFile("", to: "agents/expected-agent/system.md")

        #expect(try library.validateAgent(id: "expected-agent").errors == [
            .manifestIDMismatch(directoryID: "expected-agent", manifestID: "other-agent"),
        ])
    }

    /// 验证空模型名称会被校验为无效 manifest 字段。
    @Test func validationReportsEmptyModelName() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try store.writeTextFile(
            """
            id: empty-model
            name: Empty Model

            model:
              provider: openai
              name: ""

            systemPrompt: system.md
            """,
            to: "agents/empty-model/agent.yaml"
        )
        try store.writeTextFile("", to: "agents/empty-model/system.md")

        #expect(try library.validateAgent(id: "empty-model").errors == [
            .emptyModelName(agentID: "empty-model"),
        ])
    }

    /// 验证缺少必填 manifest 字段时不会被默认值静默补齐。
    @Test func validationReportsMissingRequiredManifestFields() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try store.writeTextFile(
            """
            id: missing-provider
            name: Missing Provider

            model:
              name: gpt-5-codex

            systemPrompt: system.md
            """,
            to: "agents/missing-provider/agent.yaml"
        )
        try store.writeTextFile("", to: "agents/missing-provider/system.md")

        try store.writeTextFile(
            """
            id: missing-prompt
            name: Missing Prompt

            model:
              provider: openai
              name: gpt-5-codex
            """,
            to: "agents/missing-prompt/agent.yaml"
        )

        #expect(try library.validateAgent(id: "missing-provider").errors == [
            .invalidManifest(agentID: "missing-provider", reason: "Missing required field: model.provider"),
        ])
        #expect(try library.validateAgent(id: "missing-prompt").errors == [
            .invalidManifest(agentID: "missing-prompt", reason: "Missing required field: systemPrompt"),
        ])
    }

    /// 验证缺失 `system.md` 时校验失败，且不会把空 system prompt 视为错误。
    @Test func validationReportsMissingSystemPromptFile() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createAgent(id: "empty-prompt", name: "Empty", systemPrompt: "")
        #expect(try library.validateAgent(id: "empty-prompt").isValid)

        try FileManager.default.removeItem(at: try store.resolveAppDataPath("agents/empty-prompt/system.md"))

        let status = try library.validateAgent(id: "empty-prompt")

        #expect(status.errors == [.missingSystemPrompt(agentID: "empty-prompt", path: "system.md")])
    }

    /// 验证 system prompt 路径必须留在当前 Agent 目录中。
    @Test func saveRejectsEscapingSystemPromptPath() throws {
        let (library, _, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        var agent = try library.createAgent(id: "prompt-agent", name: "Prompt")
        agent.manifest.systemPrompt = "../system.md"

        do {
            try library.saveAgent(agent)
            Issue.record("Expected escaping system prompt path to be rejected.")
        } catch let AgentValidationError.invalidSystemPromptPath(agentID, path, reason) {
            #expect(agentID == "prompt-agent")
            #expect(path == "../system.md")
            #expect(reason.contains("inside the agent directory"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证缺失 knowledge、skill、tool 和 tool 入口文件时会返回对应校验错误。
    @Test func validationReportsMissingSelectedResources() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createAgent(id: "ops-agent", name: "Ops")
        try store.writeTextFile("notes", to: "library/skills/broken-skill/notes.md")
        try store.writeTextFile(
            """
            id: broken-tool
            name: Broken Tool
            runtime: node
            entry: index.js
            """,
            to: "library/tools/broken-tool/tool.yaml"
        )

        var agent = try library.loadAgent(id: "ops-agent")
        agent.manifest.knowledge = ["../../library/knowledge/missing.md"]
        agent.manifest.skills = ["../../library/skills/broken-skill"]
        agent.manifest.tools = ["../../library/tools/missing-tool", "../../library/tools/broken-tool"]
        try library.saveAgent(agent)

        let status = try library.validateAgent(id: "ops-agent")

        #expect(status.errors == [
            .missingKnowledgeFile(agentID: "ops-agent", path: "../../library/knowledge/missing.md"),
            .missingSkillManifest(agentID: "ops-agent", path: "../../library/skills/broken-skill"),
            .missingToolDirectory(agentID: "ops-agent", path: "../../library/tools/missing-tool"),
            .missingToolEntryFile(agentID: "ops-agent", path: "../../library/tools/broken-tool", entry: "index.js"),
        ])
    }

    /// 验证 tool 目录缺失 `tool.yaml`、缺失 entry 或 `tool.yaml.entry` 逃逸当前目录时会校验失败。
    @Test func validationReportsInvalidToolStructure() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createAgent(id: "tool-agent", name: "Tool")
        try store.writeTextFile("entry", to: "library/tools/no-manifest/index.js")
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
            id: escaping-tool
            name: Escaping Tool
            runtime: node
            entry: ../outside.js
            """,
            to: "library/tools/escaping-tool/tool.yaml"
        )
        try store.writeTextFile("outside", to: "library/tools/outside.js")

        var agent = try library.loadAgent(id: "tool-agent")
        agent.manifest.tools = [
            "../../library/tools/no-manifest",
            "../../library/tools/no-entry",
            "../../library/tools/escaping-tool",
        ]
        try library.saveAgent(agent)

        let status = try library.validateAgent(id: "tool-agent")

        #expect(status.errors == [
            .missingToolManifest(agentID: "tool-agent", path: "../../library/tools/no-manifest"),
            .missingToolEntry(agentID: "tool-agent", path: "../../library/tools/no-entry"),
            .invalidToolEntry(
                agentID: "tool-agent",
                path: "../../library/tools/escaping-tool",
                entry: "../outside.js",
                reason: "Entry must stay inside the tool directory."
            ),
        ])
    }

    /// 验证非法权限值会作为 Agent 校验错误返回。
    @Test func validationReportsInvalidPermissions() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try store.writeTextFile(
            """
            id: unsafe-agent
            name: Unsafe

            model:
              provider: openai
              name: gpt-5-codex

            systemPrompt: system.md

            knowledge:
              - /tmp/outside.md

            permissions:
              bash: maybe
              edit: ask
              network: deny
            """,
            to: "agents/unsafe-agent/agent.yaml"
        )
        try store.writeTextFile("", to: "agents/unsafe-agent/system.md")

        let status = try library.validateAgent(id: "unsafe-agent")

        #expect(status.errors == [.invalidPermission(agentID: "unsafe-agent", field: "bash", value: "maybe")])
    }

    /// 验证绝对资源路径会作为路径安全错误返回。
    @Test func validationReportsInvalidResourcePath() throws {
        let (library, _, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createAgent(id: "path-agent", name: "Path")
        var agent = try library.loadAgent(id: "path-agent")
        agent.manifest.knowledge = ["/tmp/outside.md"]

        do {
            try library.saveAgent(agent)
            Issue.record("Expected unsafe resource path to be rejected before saving.")
        } catch let AgentValidationError.invalidResourcePath(agentID, kind, path, reason) {
            #expect(agentID == "path-agent")
            #expect(kind == .knowledge)
            #expect(path == "/tmp/outside.md")
            #expect(reason.contains("relative"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证合法 Agent 可以生成包含绝对路径的 `ResolvedAgentConfig`。
    @Test func resolvedConfigUsesAbsolutePathsForRuntime() throws {
        let (library, store, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createAgent(id: "runtime-agent", name: "Runtime", systemPrompt: "运行时提示")
        try store.writeTextFile("退款规则", to: "library/knowledge/refund.md")
        try store.writeTextFile("# Report\n", to: "library/skills/report-writing/SKILL.md")
        try store.writeTextFile(
            """
            id: ticket-search
            name: Ticket Search
            runtime: node
            entry: index.js
            """,
            to: "library/tools/ticket-search/tool.yaml"
        )
        try store.writeTextFile("export default async function run() {}\n", to: "library/tools/ticket-search/index.js")

        var agent = try library.loadAgent(id: "runtime-agent")
        agent.manifest.knowledge = ["../../library/knowledge/refund.md"]
        agent.manifest.skills = ["../../library/skills/report-writing"]
        agent.manifest.tools = ["../../library/tools/ticket-search"]
        agent.manifest.permissions = PermissionConfig(bash: .deny, edit: .ask, network: .allow)
        try library.saveAgent(agent)

        let workspace = root.appending(path: "workspace", directoryHint: .isDirectory)
        let config = try library.resolvedAgentConfig(for: "runtime-agent", workspaceDirectory: workspace)

        #expect(config.id == "runtime-agent")
        #expect(config.name == "Runtime")
        #expect(config.model == .default)
        #expect(config.permissions == PermissionConfig(bash: .deny, edit: .ask, network: .allow))
        #expect(config.systemPromptPath == root.appending(path: "agents/runtime-agent/system.md").path)
        #expect(config.knowledgePaths == [root.appending(path: "library/knowledge/refund.md").path])
        #expect(config.skillPaths == [root.appending(path: "library/skills/report-writing").path])
        #expect(config.toolPaths == [root.appending(path: "library/tools/ticket-search").path])
        #expect(config.workspacePath == workspace.path)
    }

    /// 验证无效 Agent 生成运行时配置时会返回完整校验错误。
    @Test func resolvedConfigRejectsInvalidAgent() throws {
        let (library, _, root) = try makeLibrary()
        defer { removeTemporaryRoot(root) }

        try library.createAgent(id: "invalid-runtime", name: "Invalid")
        var agent = try library.loadAgent(id: "invalid-runtime")
        agent.manifest.knowledge = ["../../library/knowledge/missing.md"]
        try library.saveAgent(agent)

        do {
            _ = try library.resolvedAgentConfig(for: "invalid-runtime", workspaceDirectory: root)
            Issue.record("Expected invalid Agent to be rejected before resolving runtime config.")
        } catch let AgentLibraryError.validationFailed(agentID, errors) {
            #expect(agentID == "invalid-runtime")
            #expect(errors == [.missingKnowledgeFile(agentID: "invalid-runtime", path: "../../library/knowledge/missing.md")])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 创建测试用 AgentLibrary。
    ///
    /// - Returns: Agent 服务、底层 FileStore 和测试结束后需要删除的临时根目录。
    private func makeLibrary() throws -> (AgentLibrary, FileStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AgentMac-AgentLibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = FileStore(rootDirectory: root)
        try store.initialize()
        return (AgentLibrary(fileStore: store), store, root)
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
