import Foundation
import Testing
@testable import AgentMac

/// Approval 模块的权限策略和交互处理器测试。
struct ApprovalTests {
    /// 验证 shell 风险读取 bash 权限，并在 allow 时自动批准。
    @Test func shellRiskUsesBashPermission() {
        let service = ApprovalService()
        let request = makeRequest(risk: .shell)
        let evaluation = service.evaluate(
            request,
            permissions: PermissionConfig(bash: .allow, edit: .deny, network: .deny)
        )

        #expect(evaluation == .resolved(.allowed(reason: "Allowed by agent permission policy.")))
    }

    /// 验证 edit/write 风险读取 edit 权限，并在 deny 时自动拒绝。
    @Test func editAndWriteRiskUseEditPermission() {
        let service = ApprovalService()
        let permissions = PermissionConfig(bash: .allow, edit: .deny, network: .allow)

        #expect(service.evaluate(makeRequest(risk: .edit), permissions: permissions) == .resolved(
            .denied(reason: "Denied by agent permission policy.")
        ))
        #expect(service.evaluate(makeRequest(risk: .write), permissions: permissions) == .resolved(
            .denied(reason: "Denied by agent permission policy.")
        ))
    }

    /// 验证 network 风险读取 network 权限，并在 ask 时等待用户确认。
    @Test func networkRiskUsesNetworkPermission() {
        let service = ApprovalService()
        let request = makeRequest(risk: .network)
        let evaluation = service.evaluate(
            request,
            permissions: PermissionConfig(bash: .deny, edit: .deny, network: .ask)
        )

        #expect(evaluation == .requiresUserDecision)
    }

    /// 验证默认 ask 策略下 Pi 内建 read/edit/write 自动允许。
    @Test func builtInFileToolsAreAllowedByDefaultWhenPermissionAsks() {
        let service = ApprovalService()
        let permissions = PermissionConfig.default

        #expect(service.evaluate(
            makeRequest(toolName: "read", risk: .edit, details: [.init(key: "path", value: "README.md")]),
            permissions: permissions
        ) == .resolved(.allowed(reason: "Allowed by default built-in tool policy.")))
        #expect(service.evaluate(
            makeRequest(toolName: "edit", risk: .edit, details: [.init(key: "path", value: "App.swift")]),
            permissions: permissions
        ) == .resolved(.allowed(reason: "Allowed by default built-in tool policy.")))
        #expect(service.evaluate(
            makeRequest(toolName: "write", risk: .write, details: [.init(key: "path", value: "App.swift")]),
            permissions: permissions
        ) == .resolved(.allowed(reason: "Allowed by default built-in tool policy.")))
    }

    /// 验证默认 ask 策略下非删除文件的 bash 自动允许。
    @Test func nonDeletingBashCommandsAreAllowedByDefaultWhenPermissionAsks() {
        let service = ApprovalService()

        #expect(service.evaluate(
            makeRequest(toolName: "bash", risk: .shell, details: [.init(key: "command", value: "find . -name '*.md'")]),
            permissions: .default
        ) == .resolved(.allowed(reason: "Allowed by default bash policy.")))
    }

    /// 验证默认 ask 策略下删除文件的 bash 仍需要用户确认。
    @Test func deletingBashCommandsStillRequireUserDecisionWhenPermissionAsks() {
        let service = ApprovalService()
        let deletingCommands = [
            "rm -rf build",
            "/bin/rm README.md",
            "git rm README.md",
            "find . -name '*.tmp' -delete",
            "find . -name '*.tmp' -exec /bin/rm {} \\;",
        ]

        for command in deletingCommands {
            #expect(service.evaluate(
                makeRequest(toolName: "bash", risk: .shell, details: [.init(key: "command", value: command)]),
                permissions: .default
            ) == .requiresUserDecision)
        }
    }

    /// 验证 secrets 和 unknown 风险默认拒绝，避免没有明确策略时自动执行。
    @Test func secretsAndUnknownRiskDefaultToDeny() {
        let service = ApprovalService()
        let permissions = PermissionConfig(bash: .allow, edit: .allow, network: .allow)

        #expect(service.evaluate(makeRequest(risk: .secrets), permissions: permissions) == .resolved(
            .denied(reason: "Denied by agent permission policy.")
        ))
        #expect(service.evaluate(makeRequest(risk: .unknown), permissions: permissions) == .resolved(
            .denied(reason: "Denied by agent permission policy.")
        ))
    }

    /// 验证交互式处理器会等待 UI 提交决策。
    @Test func interactiveHandlerWaitsForSubmittedDecision() async {
        let handler = InteractiveToolApprovalHandler()
        let request = makeRequest(risk: .shell)

        let task = Task.detached {
            handler.handle(request)
        }
        try? await Task.sleep(for: .milliseconds(20))
        handler.submit(.allowed(reason: "Approved in test."), for: request.toolCallID)

        let decision = await task.value
        #expect(decision == .allowed(reason: "Approved in test."))
    }

    private func makeRequest(
        toolName: String = "bash",
        risk: ToolApprovalRisk,
        details: [ToolApprovalRequest.DetailField] = [.init(key: "command", value: "ls -la")]
    ) -> ToolApprovalRequest {
        ToolApprovalRequest(
            toolCallID: "tool_001",
            toolName: toolName,
            risk: risk,
            summary: "Run shell command",
            details: details
        )
    }
}
