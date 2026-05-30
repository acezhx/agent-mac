import Foundation
import Testing
@testable import AgentMac

/// Session 模块的状态流转和消息合并测试。
///
/// 测试使用 mock RuntimeBridge 和临时 FileStore，不启动 Node Runtime Host，也不依赖 UI。
struct SessionTests {
    /// 验证新建 session 初始状态为 idle。
    @Test func newSessionStartsIdle() throws {
        let (session, _, root, _) = try makeSession()
        defer { removeTemporaryRoot(root) }

        #expect(session.state == .idle)
        #expect(session.runtimeSessionID == nil)
        #expect(session.messages.isEmpty)
    }

    /// 验证 start 会启动 fixed coding agent runtime session，并写入 session record。
    @Test func startCreatesRuntimeSessionAndPersistsRecord() throws {
        let (session, store, root, runtime) = try makeSession()
        defer { removeTemporaryRoot(root) }

        try session.start()

        #expect(session.state == .running)
        #expect(session.runtimeSessionID == "ses_mock")
        #expect(runtime.startedAgentConfigs.map(\.id) == ["support-agent"])
        #expect(runtime.startedAgentConfigs.map(\.workspacePath) == [root.appending(path: "workspace", directoryHint: .isDirectory).path])

        let record = try readRecord(store: store, path: session.recordRelativePath)
        #expect(record["state"] as? String == "running")
        #expect(record["runtimeSessionID"] as? String == "ses_mock")
        #expect(record["agentID"] as? String == "support-agent")
    }

    /// 验证已启动的 session 不会重复启动新的 Runtime Host session。
    @Test func startRejectsDuplicateRuntimeSession() throws {
        let (session, _, root, runtime) = try makeSession()
        defer { removeTemporaryRoot(root) }

        try session.start()

        do {
            try session.start()
            Issue.record("Expected duplicate start to be rejected.")
        } catch let SessionError.runtimeSessionAlreadyStarted(sessionID) {
            #expect(sessionID == "ses_mock")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(session.state == .running)
        #expect(runtime.startedAgentConfigs.count == 1)
    }

    /// 验证用户消息会追加，assistant delta 会合并成一条完成的 assistant 消息。
    @Test func sendUserMessageMergesAssistantDeltasAndCompletes() throws {
        let runtime = MockSessionRuntime()
        runtime.sendEvents = [
            runtimeEvent(name: "assistantDelta", payload: .object(["text": .string("你")])),
            runtimeEvent(name: "assistantDelta", payload: .object(["text": .string("好")])),
            runtimeEvent(name: "messageCompleted"),
        ]
        let (session, store, root, _) = try makeSession(runtime: runtime)
        defer { removeTemporaryRoot(root) }

        try session.start()
        try session.sendUserMessage("ping")

        #expect(session.state == .idle)
        #expect(session.messages.map(\.role) == [.user, .assistant])
        #expect(session.messages[0].content == "ping")
        #expect(session.messages[1].content == "你好")
        #expect(session.messages[1].isStreaming == false)
        #expect(runtime.sentMessages.count == 1)
        #expect(runtime.sentMessages.first?.0 == "ses_mock")
        #expect(runtime.sentMessages.first?.1 == "ping")

        let record = try readRecord(store: store, path: session.recordRelativePath)
        #expect(record["state"] as? String == "idle")
        #expect(record["messageCount"] as? Int == 2)

        let messages = try #require(record["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "user")
        #expect(messages[0]["content"] as? String == "ping")
        #expect(messages[1]["role"] as? String == "assistant")
        #expect(messages[1]["content"] as? String == "你好")
        #expect(messages[1]["isStreaming"] as? Bool == false)
    }

    /// 验证未知非 error Runtime event 会被忽略，不会让 session 失败。
    @Test func sendUserMessageIgnoresUnknownRuntimeEvents() throws {
        var logMessages: [String] = []
        let runtime = MockSessionRuntime()
        runtime.sendEvents = [
            runtimeEvent(name: "assistantDelta", payload: .object(["text": .string("hello")])),
            runtimeEvent(name: "progressUpdated", payload: .object(["percent": .number(0.5)])),
            runtimeEvent(name: "assistantDelta", payload: .object(["text": .string(" world")])),
            runtimeEvent(name: "messageCompleted"),
        ]
        let (session, _, root, _) = try makeSession(runtime: runtime) { message in
            logMessages.append(message)
        }
        defer { removeTemporaryRoot(root) }

        try session.start()
        try session.sendUserMessage("ping")

        #expect(session.state == .idle)
        #expect(session.messages.map(\.role) == [.user, .assistant])
        #expect(session.messages[1].content == "hello world")
        #expect(session.messages[1].isStreaming == false)
        #expect(logMessages.count == 1)
        #expect(logMessages[0].contains("progressUpdated"))
        #expect(logMessages[0].contains(session.id.uuidString.lowercased()))
    }

    /// 验证 RuntimeHost 活动心跳是已知事件，不会创建消息或写入未知事件日志。
    @Test func sendUserMessageIgnoresRuntimeActivityWithoutLogging() throws {
        var logMessages: [String] = []
        let runtime = MockSessionRuntime()
        runtime.sendEvents = [
            runtimeEvent(name: "runtimeActivity", payload: .object(["piEventType": .string("tool_execution_start")])),
            runtimeEvent(name: "assistantDelta", payload: .object(["text": .string("done")])),
            runtimeEvent(name: "messageCompleted"),
        ]
        let (session, _, root, _) = try makeSession(runtime: runtime) { message in
            logMessages.append(message)
        }
        defer { removeTemporaryRoot(root) }

        try session.start()
        try session.sendUserMessage("ping")

        #expect(session.state == .idle)
        #expect(session.messages.map(\.role) == [.user, .assistant])
        #expect(session.messages[1].content == "done")
        #expect(logMessages.isEmpty)
    }

    /// 验证上一轮消息未完成时不会接受新的用户消息。
    @Test func sendUserMessageRejectsMessageAlreadyInFlight() throws {
        let runtime = MockSessionRuntime()
        runtime.sendEvents = [
            runtimeEvent(name: "assistantDelta", payload: .object(["text": .string("partial")])),
        ]
        let (session, store, root, _) = try makeSession(runtime: runtime)
        defer { removeTemporaryRoot(root) }

        try session.start()
        try session.sendUserMessage("first")

        do {
            try session.sendUserMessage("second")
            Issue.record("Expected in-flight message to be rejected.")
        } catch SessionError.messageAlreadyInFlight {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(session.state == .running)
        #expect(session.messages.map(\.role) == [.user, .assistant])
        #expect(session.messages[0].content == "first")
        #expect(session.messages[1].content == "partial")
        #expect(session.messages[1].isStreaming)
        #expect(runtime.sentMessages.count == 1)

        let record = try readRecord(store: store, path: session.recordRelativePath)
        #expect(record["state"] as? String == "running")
        #expect(record["messageCount"] as? Int == 2)
    }

    /// 验证取消当前轮会保留 Runtime session，并允许后续继续发送。
    @Test func turnCancelledKeepsRuntimeSessionReusable() throws {
        let runtime = MockSessionRuntime()
        runtime.sendEvents = [
            runtimeEvent(name: "assistantDelta", payload: .object(["text": .string("partial")])),
            runtimeEvent(name: "turnCancelled", payload: .object(["cancelled": .bool(true)])),
        ]
        let (session, store, root, _) = try makeSession(runtime: runtime)
        defer { removeTemporaryRoot(root) }

        try session.start()
        try session.sendUserMessage("stop")

        #expect(session.state == .idle)
        #expect(session.runtimeSessionID == "ses_mock")
        #expect(session.messages.map(\.role) == [.user, .assistant])
        #expect(session.messages[1].content == "partial")
        #expect(session.messages[1].isStreaming == false)

        runtime.sendEvents = [
            runtimeEvent(name: "assistantDelta", payload: .object(["text": .string("next")])),
            runtimeEvent(name: "messageCompleted"),
        ]
        try session.sendUserMessage("again")

        #expect(session.state == .idle)
        #expect(session.runtimeSessionID == "ses_mock")
        #expect(runtime.sentMessages.map { $0.1 } == ["stop", "again"])
        #expect(session.messages.map(\.content) == ["stop", "partial", "again", "next"])

        let record = try readRecord(store: store, path: session.recordRelativePath)
        #expect(record["state"] as? String == "idle")
        #expect(record["runtimeSessionID"] as? String == "ses_mock")
    }

    /// 验证 cancelCurrentTurn 调用 RuntimeBridge cancelTurn，不进入 aborted 终态。
    @Test func cancelCurrentTurnCallsRuntimeCancelAndReturnsToIdle() throws {
        let runtime = MockSessionRuntime()
        runtime.sendEvents = [
            runtimeEvent(name: "assistantDelta", payload: .object(["text": .string("partial")])),
        ]
        let (session, _, root, _) = try makeSession(runtime: runtime)
        defer { removeTemporaryRoot(root) }

        try session.start()
        try session.sendUserMessage("stop")
        try session.cancelCurrentTurn()

        #expect(runtime.cancelledTurnSessionIDs == ["ses_mock"])
        #expect(runtime.abortedSessionIDs.isEmpty)
        #expect(session.state == .idle)
        #expect(session.runtimeSessionID == "ses_mock")
        #expect(session.messages[1].isStreaming == false)
    }

    /// 验证 RuntimeBridge 错误会让 session 进入 failed，并保留诊断消息。
    @Test func runtimeErrorMovesSessionToFailed() throws {
        let runtime = MockSessionRuntime()
        runtime.sendError = RuntimeBridgeError.runtimeError(
            code: "runtime_failed",
            message: "Session failed.",
            recoverable: true,
            details: nil
        )
        let (session, _, root, _) = try makeSession(runtime: runtime)
        defer { removeTemporaryRoot(root) }

        try session.start()

        do {
            try session.sendUserMessage("boom")
            Issue.record("Expected runtime error to fail the session.")
        } catch let SessionError.runtimeFailed(code, message, recoverable) {
            #expect(code == "runtime_failed")
            #expect(message == "Session failed.")
            #expect(recoverable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(session.state == .failed(.runtimeFailed(code: "runtime_failed", message: "Session failed.", recoverable: true)))
        #expect(session.messages.last?.role == .diagnostic)
        #expect(session.messages.last?.content.contains("runtime_failed") == true)
    }

    /// 验证 RuntimeBridge error details.reason 会进入 session 错误消息，便于 UI 显示模型失败原因。
    @Test func runtimeErrorDetailsReasonIsSurfaced() throws {
        let runtime = MockSessionRuntime()
        runtime.sendError = RuntimeBridgeError.runtimeError(
            code: "model_failed",
            message: "Pi session failed to process the message.",
            recoverable: true,
            details: .object(["reason": .string("No API key found for the selected model.")])
        )
        let (session, _, root, _) = try makeSession(runtime: runtime)
        defer { removeTemporaryRoot(root) }

        try session.start()

        do {
            try session.sendUserMessage("boom")
            Issue.record("Expected runtime error to fail the session.")
        } catch let SessionError.runtimeFailed(code, message, recoverable) {
            #expect(code == "model_failed")
            #expect(message == "Pi session failed to process the message.\nNo API key found for the selected model.")
            #expect(recoverable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(session.messages.last?.content.contains("No API key found for the selected model.") == true)
    }

    /// 验证 failed 状态需要 reset 后才能继续发送消息。
    @Test func sendUserMessageRequiresResetAfterFailure() throws {
        let runtime = MockSessionRuntime()
        runtime.sendError = RuntimeBridgeError.runtimeError(
            code: "runtime_failed",
            message: "Session failed.",
            recoverable: true,
            details: nil
        )
        let (session, _, root, _) = try makeSession(runtime: runtime)
        defer { removeTemporaryRoot(root) }

        try session.start()
        do {
            try session.sendUserMessage("boom")
            Issue.record("Expected runtime error to fail the session.")
        } catch let SessionError.runtimeFailed(code, message, recoverable) {
            #expect(code == "runtime_failed")
            #expect(message == "Session failed.")
            #expect(recoverable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        runtime.sendError = nil

        do {
            try session.sendUserMessage("again")
            Issue.record("Expected failed session to require reset.")
        } catch let SessionError.sessionRequiresReset(state) {
            #expect(state == "failed")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(runtime.sentMessages.count == 1)
        #expect(session.messages.filter { $0.role == .user }.map(\.content) == ["boom"])
    }

    /// 验证 abort 会进入 aborted，并清空 Runtime Host session id。
    @Test func abortMovesSessionToAborted() throws {
        let (session, store, root, runtime) = try makeSession()
        defer { removeTemporaryRoot(root) }

        try session.start()
        try session.abort()

        #expect(session.state == .aborted)
        #expect(session.runtimeSessionID == nil)
        #expect(runtime.abortedSessionIDs == ["ses_mock"])

        let record = try readRecord(store: store, path: session.recordRelativePath)
        #expect(record["state"] as? String == "aborted")
    }

    /// 验证 aborted 状态需要 reset 后才能重新启动或发送消息。
    @Test func abortedSessionRequiresResetBeforeReuse() throws {
        let (session, _, root, runtime) = try makeSession()
        defer { removeTemporaryRoot(root) }

        try session.start()
        try session.abort()

        do {
            try session.sendUserMessage("again")
            Issue.record("Expected aborted session to reject send.")
        } catch let SessionError.sessionRequiresReset(state) {
            #expect(state == "aborted")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            try session.start()
            Issue.record("Expected aborted session to reject start.")
        } catch let SessionError.sessionRequiresReset(state) {
            #expect(state == "aborted")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        try session.reset()
        try session.start()

        #expect(runtime.sentMessages.isEmpty)
        #expect(runtime.startedAgentConfigs.count == 2)
        #expect(session.state == .running)
    }

    /// 验证 reset 持久化失败会抛错，并保留原内存状态。
    @Test func resetThrowsAndKeepsStateWhenPersistenceFails() throws {
        let (session, _, root, _) = try makeSession()
        defer { removeTemporaryRoot(root) }

        try session.start()
        try session.abort()

        let sessionsURL = root.appending(path: "sessions", directoryHint: .isDirectory)
        try FileManager.default.removeItem(at: sessionsURL)
        try "blocked".write(to: sessionsURL, atomically: true, encoding: .utf8)

        do {
            try session.reset()
            Issue.record("Expected reset persistence failure.")
        } catch let SessionError.persistenceFailed(path, reason) {
            #expect(path == session.recordRelativePath)
            #expect(!reason.isEmpty)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(session.state == .aborted)
        #expect(session.runtimeSessionID == nil)
    }

    /// 验证 sessionAborted 后迟到的 Runtime events 不会覆盖 aborted 终态。
    @Test func lateRuntimeEventsAfterAbortAreIgnored() throws {
        let runtime = MockSessionRuntime()
        runtime.sendEvents = [
            runtimeEvent(name: "assistantDelta", payload: .object(["text": .string("partial")])),
            runtimeEvent(name: "sessionAborted"),
            runtimeEvent(name: "assistantDelta", payload: .object(["text": .string("late")])),
            runtimeEvent(name: "messageCompleted"),
            runtimeEvent(
                name: "toolApprovalRequested",
                payload: .object([
                    "toolCallId": .string("tool_001"),
                    "toolName": .string("bash"),
                ])
            ),
        ]
        let (session, _, root, _) = try makeSession(runtime: runtime)
        defer { removeTemporaryRoot(root) }

        try session.start()
        try session.sendUserMessage("stop")

        #expect(session.state == .aborted)
        #expect(session.runtimeSessionID == nil)
        #expect(session.toolApprovalDecisions.isEmpty)
        #expect(session.messages.map(\.role) == [.user, .assistant])
        #expect(session.messages[1].content == "partial")
        #expect(session.messages[1].isStreaming == false)
    }

    /// 验证工具审批请求会走默认 denied 决策并回传 Runtime Host，不会让消息发送崩溃。
    @Test func toolApprovalRequestUsesDefaultDeniedDecision() throws {
        let runtime = MockSessionRuntime()
        runtime.sendEvents = [
            runtimeEvent(
                name: "toolApprovalRequested",
                payload: .object([
                    "toolCallId": .string("tool_001"),
                    "toolName": .string("bash"),
                    "risk": .string("shell"),
                    "summary": .string("Run shell command"),
                ])
            ),
            runtimeEvent(name: "assistantDelta", payload: .object(["text": .string("done")])),
            runtimeEvent(name: "messageCompleted"),
        ]
        let (session, _, root, _) = try makeSession(runtime: runtime)
        defer { removeTemporaryRoot(root) }

        try session.start()
        try session.sendUserMessage("需要工具")

        #expect(session.state == .idle)
        #expect(session.toolApprovalDecisions == [
            .denied(reason: "Tool approval was denied because no interactive approval handler is configured."),
        ])
        #expect(runtime.approvedToolCalls == [
            .init(
                sessionID: "ses_mock",
                toolCallID: "tool_001",
                decision: .denied(
                    reason: "Tool approval was denied because no interactive approval handler is configured."
                )
            ),
        ])
        #expect(session.messages.contains { $0.role == .diagnostic && $0.content.contains("bash") })
        #expect(session.messages.last?.role == .assistant)
        #expect(session.messages.last?.content == "done")
    }

    /// 验证工具诊断消息切分 assistant 输出后，完成事件会清理所有 streaming 标记。
    @Test func messageCompletedClearsStreamingAssistantSplitByToolDiagnostics() throws {
        let runtime = MockSessionRuntime()
        runtime.sendEvents = [
            runtimeEvent(
                name: "assistantDelta",
                payload: .object(["text": .string("现在让我看看各章节的具体内容结构：")])
            ),
            runtimeEvent(
                name: "toolApprovalRequested",
                payload: .object([
                    "toolCallId": .string("tool_001"),
                    "toolName": .string("read"),
                    "risk": .string("read"),
                    "summary": .string("Read project files"),
                ])
            ),
            runtimeEvent(name: "assistantDelta", payload: .object(["text": .string("项目整体分析")])),
            runtimeEvent(name: "messageCompleted"),
        ]
        let (session, _, root, _) = try makeSession(runtime: runtime)
        defer { removeTemporaryRoot(root) }

        try session.start()
        try session.sendUserMessage("分析下当前的项目")

        #expect(session.state == .idle)
        #expect(session.messages.map(\.role) == [.user, .assistant, .diagnostic, .assistant])
        #expect(session.messages[1].content == "现在让我看看各章节的具体内容结构：")
        #expect(session.messages[3].content == "项目整体分析")
        #expect(session.messages.filter(\.isStreaming).isEmpty)
    }

    /// 验证默认策略会自动批准非删除文件的 bash 请求，不进入交互式审批。
    @Test func safeBashToolApprovalIsAllowedByDefault() throws {
        let runtime = MockSessionRuntime()
        runtime.sendEvents = [
            runtimeEvent(
                name: "toolApprovalRequested",
                payload: .object([
                    "toolCallId": .string("tool_001"),
                    "toolName": .string("bash"),
                    "risk": .string("shell"),
                    "summary": .string("Run shell command"),
                    "details": .object([
                        "command": .string("find . -name '*.md'"),
                    ]),
                ])
            ),
            runtimeEvent(name: "assistantDelta", payload: .object(["text": .string("done")])),
            runtimeEvent(name: "messageCompleted"),
        ]
        let (session, _, root, _) = try makeSession(runtime: runtime)
        defer { removeTemporaryRoot(root) }

        try session.start()
        try session.sendUserMessage("需要工具")

        #expect(session.pendingToolApprovalRequest == nil)
        #expect(session.toolApprovalDecisions == [
            .allowed(reason: "Allowed by default bash policy."),
        ])
        #expect(runtime.approvedToolCalls == [
            .init(
                sessionID: "ses_mock",
                toolCallID: "tool_001",
                decision: .allowed(reason: "Allowed by default bash policy.")
            ),
        ])
    }

    /// 验证删除文件的 bash 工具审批会暂停消息流程，直到 UI 处理器提交 allow 决策。
    @Test func toolApprovalRequestWaitsForInteractiveDecision() async throws {
        let approvalHandler = InteractiveToolApprovalHandler()
        let runtime = MockSessionRuntime()
        runtime.sendEvents = [
            runtimeEvent(
                name: "toolApprovalRequested",
                payload: .object([
                    "toolCallId": .string("tool_001"),
                    "toolName": .string("bash"),
                    "risk": .string("shell"),
                    "summary": .string("Run shell command"),
                    "details": .object([
                        "command": .string("rm -rf build"),
                    ]),
                ])
            ),
            runtimeEvent(name: "assistantDelta", payload: .object(["text": .string("done")])),
            runtimeEvent(name: "messageCompleted"),
        ]
        let (session, _, root, _) = try makeSession(runtime: runtime, approvalHandler: approvalHandler)
        defer { removeTemporaryRoot(root) }

        try session.start()
        let sendTask = Task.detached {
            try session.sendUserMessage("需要工具")
        }

        do {
            try await waitUntil { session.pendingToolApprovalRequest != nil }

            let pendingRequest = try #require(session.pendingToolApprovalRequest)
            #expect(pendingRequest.toolCallID == "tool_001")
            #expect(pendingRequest.toolName == "bash")
            #expect(pendingRequest.details == [
                .init(key: "command", value: "rm -rf build"),
            ])
            #expect(runtime.approvedToolCalls.isEmpty)

            approvalHandler.submit(.allowed(reason: "Approved by test."), for: "tool_001")
            try await sendTask.value
        } catch {
            approvalHandler.submit(.denied(reason: "Test cleanup."), for: "tool_001")
            _ = try? await sendTask.value
            throw error
        }

        #expect(session.pendingToolApprovalRequest == nil)
        #expect(session.toolApprovalDecisions == [
            .allowed(reason: "Approved by test."),
        ])
        #expect(runtime.approvedToolCalls == [
            .init(
                sessionID: "ses_mock",
                toolCallID: "tool_001",
                decision: .allowed(reason: "Approved by test.")
            ),
        ])
        #expect(session.state == .idle)
        #expect(session.messages.last?.role == .assistant)
        #expect(session.messages.last?.content == "done")
    }

    /// 验证 SessionStore 能兼容旧版无消息历史的基础 record。
    @Test func sessionStoreLoadsLegacyRecordWithoutMessages() throws {
        let root = temporaryRoot()
        let store = FileStore(rootDirectory: root)
        defer { removeTemporaryRoot(root) }
        try store.initialize()

        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        try store.writeTextFile(
            """
            {
              "agentID": "support-agent",
              "agentName": "Support Agent",
              "createdAt": "1970-01-01T00:00:01Z",
              "errorMessage": null,
              "id": "\(id.uuidString.lowercased())",
              "messageCount": 2,
              "runtimeSessionID": "ses_legacy",
              "state": "idle",
              "updatedAt": "1970-01-01T00:00:02Z",
              "workspacePath": "\(root.appending(path: "workspace", directoryHint: .isDirectory).path)"
            }
            """,
            to: SessionStore.relativePath(for: id)
        )

        let record = try SessionStore(fileStore: store).load(id: id)

        #expect(record.schemaVersion == 0)
        #expect(record.messageCount == 2)
        #expect(record.messages.isEmpty)
        #expect(record.sessionState == .idle)
    }

    /// 验证管理层可以创建、缓存、列出和删除 session record。
    @Test func managerCreatesListsCachesAndDeletesSessions() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        let (manager, store, root, _, resolver) = try makeManager(idProvider: { id })
        defer { removeTemporaryRoot(root) }
        let workspace = root.appending(path: "workspace", directoryHint: .isDirectory)

        let session = try manager.createSession(agentID: "support-agent", workspaceDirectory: workspace)

        #expect(session.id == id)
        #expect(try store.fileExists(at: session.recordRelativePath))
        #expect(resolver.requests.count == 1)
        #expect(resolver.requests[0].0 == "support-agent")
        #expect(resolver.requests[0].1 == workspace.path)

        let summaries = try manager.listSessionSummaries()
        #expect(summaries.count == 1)
        #expect(summaries[0].id == id)
        #expect(summaries[0].state == .idle)
        #expect(summaries[0].messageCount == 0)

        let cached = try manager.loadSession(id: id)
        #expect(cached === session)

        try manager.deleteSession(id: id)
        #expect(manager.cachedSession(id: id) == nil)
        #expect(try !store.fileExists(at: session.recordRelativePath))
    }

    /// 验证管理层能恢复完整消息、失败状态和临时审批决策。
    @Test func managerRestoresCompleteMessagesFailedStateAndApprovals() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000030")!
        let messageID = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
        let assistantID = UUID(uuidString: "00000000-0000-0000-0000-000000000032")!
        let (manager, store, root, _, _) = try makeManager()
        defer { removeTemporaryRoot(root) }
        let workspace = root.appending(path: "workspace", directoryHint: .isDirectory)
        let error = SessionError.runtimeFailed(code: "runtime_failed", message: "Session failed.", recoverable: true)
        let messages = [
            ChatMessage(id: messageID, role: .user, content: "ping", createdAt: Date(timeIntervalSince1970: 2)),
            ChatMessage(id: assistantID, role: .assistant, content: "pong", createdAt: Date(timeIntervalSince1970: 3)),
        ]
        let record = ChatSessionRecord(
            id: id,
            runtimeSessionID: "ses_old",
            agentID: "support-agent",
            agentName: "Support Agent",
            workspacePath: workspace.path,
            state: .failed(error),
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 4),
            messages: messages,
            toolApprovals: [.unsupported(reason: "Tool approval is not supported yet.")]
        )
        try SessionStore(fileStore: store).save(record)

        let restored = try manager.loadSession(id: id)

        #expect(restored.id == id)
        #expect(restored.runtimeSessionID == nil)
        #expect(restored.state == .failed(error))
        #expect(restored.messages == messages)
        #expect(restored.toolApprovalDecisions == [.unsupported(reason: "Tool approval is not supported yet.")])
    }

    /// 验证冷启动恢复 running record 时不会复用旧 Runtime session。
    @Test func managerRestoresRunningRecordAsDetachedFailure() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000040")!
        let streamingID = UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
        let diagnosticID = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
        let (manager, store, root, _, _) = try makeManager(
            messageIDProvider: { diagnosticID },
            dateProvider: { Date(timeIntervalSince1970: 9) }
        )
        defer { removeTemporaryRoot(root) }
        let workspace = root.appending(path: "workspace", directoryHint: .isDirectory)
        let record = ChatSessionRecord(
            id: id,
            runtimeSessionID: "ses_old",
            agentID: "support-agent",
            agentName: "Support Agent",
            workspacePath: workspace.path,
            state: .running,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 4),
            messages: [
                ChatMessage(
                    id: streamingID,
                    role: .assistant,
                    content: "partial",
                    createdAt: Date(timeIntervalSince1970: 3),
                    isStreaming: true
                ),
            ],
            toolApprovals: []
        )
        try SessionStore(fileStore: store).save(record)

        let restored = try manager.loadSession(id: id)

        #expect(restored.runtimeSessionID == nil)
        #expect(restored.state == .failed(.runtimeSessionDetached))
        #expect(restored.messages.count == 2)
        #expect(restored.messages[0].isStreaming == false)
        #expect(restored.messages[1].id == diagnosticID)
        #expect(restored.messages[1].role == .diagnostic)

        let normalized = try SessionStore(fileStore: store).load(id: id)
        #expect(normalized.runtimeSessionID == nil)
        #expect(normalized.sessionState == .failed(.runtimeSessionDetached))
        #expect(normalized.messages.count == 2)
    }

    /// 创建测试用 ChatSession。
    ///
    /// - Parameters:
    ///   - runtime: mock RuntimeBridge。
    ///   - approvalHandler: 工具审批处理器。
    ///   - id: 本地 session id。
    ///   - logHandler: Session 内部诊断日志处理器。
    /// - Returns: ChatSession、FileStore、临时根目录和 mock RuntimeBridge。
    private func makeSession(
        runtime: MockSessionRuntime = MockSessionRuntime(),
        approvalHandler: any ToolApprovalHandling = DefaultToolApprovalHandler(),
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        logHandler: @escaping (String) -> Void = { _ in }
    ) throws -> (ChatSession, FileStore, URL, MockSessionRuntime) {
        let root = temporaryRoot()
        let store = FileStore(rootDirectory: root)
        try store.initialize()

        let config = ResolvedAgentConfig(
            id: "support-agent",
            name: "Support Agent",
            model: .default,
            systemPromptPath: root.appending(path: "agents/support-agent/system.md", directoryHint: .notDirectory).path,
            knowledgePaths: [],
            skillPaths: [],
            toolPaths: [],
            permissions: .default,
            workspacePath: root.appending(path: "workspace", directoryHint: .isDirectory).path
        )

        let session = ChatSession(
            agentConfig: config,
            fileStore: store,
            runtimeBridge: runtime,
            approvalHandler: approvalHandler,
            id: id,
            dateProvider: { Date(timeIntervalSince1970: 1) },
            logHandler: logHandler
        )

        return (session, store, root, runtime)
    }

    /// 创建测试用 ChatSessionManager。
    ///
    /// - Parameters:
    ///   - runtime: mock RuntimeBridge。
    ///   - idProvider: session id 生成器。
    ///   - messageIDProvider: message id 生成器。
    ///   - dateProvider: 时间生成器。
    /// - Returns: ChatSessionManager、FileStore、临时根目录、mock RuntimeBridge 和 mock Agent 解析器。
    private func makeManager(
        runtime: MockSessionRuntime = MockSessionRuntime(),
        idProvider: @escaping () -> UUID = { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! },
        messageIDProvider: @escaping () -> UUID = { UUID() },
        dateProvider: @escaping () -> Date = { Date(timeIntervalSince1970: 1) }
    ) throws -> (ChatSessionManager, FileStore, URL, MockSessionRuntime, MockAgentConfigResolver) {
        let root = temporaryRoot()
        let store = FileStore(rootDirectory: root)
        try store.initialize()
        let resolver = MockAgentConfigResolver(root: root)
        let manager = ChatSessionManager(
            fileStore: store,
            agentConfigResolver: resolver,
            runtimeBridge: runtime,
            idProvider: idProvider,
            messageIDProvider: messageIDProvider,
            dateProvider: dateProvider
        )
        return (manager, store, root, runtime, resolver)
    }

    /// 读取并解析 session record。
    ///
    /// - Parameters:
    ///   - store: FileStore。
    ///   - path: app data 相对路径。
    /// - Returns: JSON 字典。
    private func readRecord(store: FileStore, path: String) throws -> [String: Any] {
        let text = try store.readTextFile(at: path)
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try #require(object as? [String: Any])
    }

    /// 创建 RuntimeEvent。
    ///
    /// - Parameters:
    ///   - name: event 名称。
    ///   - payload: event payload。
    /// - Returns: RuntimeEvent。
    private func runtimeEvent(name: String, payload: RuntimeJSONValue? = .object([:])) -> RuntimeEvent {
        RuntimeEvent(
            type: "event",
            id: "evt_\(name)",
            replyTo: "cmd_mock",
            sessionId: "ses_mock",
            name: name,
            payload: payload
        )
    }

    /// 创建测试临时目录 URL。
    ///
    /// - Returns: 尚未创建的临时目录 URL。
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "AgentMac-SessionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// 删除测试创建的临时根目录。
    ///
    /// - Parameter root: 待删除目录。
    private func removeTemporaryRoot(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    /// 等待异步条件满足。
    ///
    /// - Parameter condition: 每轮轮询时检查的条件。
    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() {
                return
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        throw SessionTestError.conditionTimeout
    }
}

/// Session 测试内部错误。
private enum SessionTestError: Error {
    /// 等待条件超时。
    case conditionTimeout
}

/// Session 测试使用的 RuntimeBridge mock。
private final class MockSessionRuntime: SessionRuntimeBridging {
    /// 工具审批回传记录。
    struct ApprovedToolCall: Equatable {
        /// Runtime Host session id。
        let sessionID: String

        /// Runtime Host 工具调用 id。
        let toolCallID: String

        /// 回传决策。
        let decision: ToolApprovalDecision
    }

    /// startSession 返回的 Runtime Host session id。
    var startResult = "ses_mock"

    /// startSession 抛出的错误。
    var startError: Error?

    /// sendMessage 期间回放的 Runtime Host events。
    var sendEvents: [RuntimeEvent] = [
        RuntimeEvent(
            type: "event",
            id: "evt_completed",
            replyTo: "cmd_mock",
            sessionId: "ses_mock",
            name: "messageCompleted",
            payload: .object([:])
        ),
    ]

    /// sendMessage 抛出的错误。
    var sendError: Error?

    /// abortSession 抛出的错误。
    var abortError: Error?

    /// cancelTurn 抛出的错误。
    var cancelTurnError: Error?

    /// startSession 收到的 Agent 运行配置。
    private(set) var startedAgentConfigs: [ResolvedAgentConfig] = []

    /// sendMessage 收到的消息。
    private(set) var sentMessages: [(String, String)] = []

    /// abortSession 收到的 session ids。
    private(set) var abortedSessionIDs: [String] = []

    /// cancelTurn 收到的 session ids。
    private(set) var cancelledTurnSessionIDs: [String] = []

    /// approveToolCall 收到的回传记录。
    private(set) var approvedToolCalls: [ApprovedToolCall] = []

    /// 启动 mock Runtime Host session。
    ///
    /// - Parameters:
    ///   - agentConfig: 已解析的 Agent 运行配置。
    ///   - timeout: 等待秒数。
    /// - Returns: mock session id。
    func startSession(agentConfig: ResolvedAgentConfig, timeout: TimeInterval) throws -> String {
        if let startError {
            throw startError
        }

        startedAgentConfigs.append(agentConfig)
        return startResult
    }

    /// 回放 mock Runtime Host events。
    ///
    /// - Parameters:
    ///   - sessionId: Runtime Host session id。
    ///   - content: 用户消息文本。
    ///   - timeout: 等待秒数。
    ///   - onEvent: event 回调。
    /// - Returns: 回放的 events。
    @discardableResult
    func sendMessage(
        sessionId: String,
        content: String,
        timeout: TimeInterval,
        onEvent: ((RuntimeEvent) throws -> Void)?
    ) throws -> [RuntimeEvent] {
        sentMessages.append((sessionId, content))

        if let sendError {
            throw sendError
        }

        for event in sendEvents {
            try onEvent?(event)
        }
        return sendEvents
    }

    /// 中断 mock Runtime Host session。
    ///
    /// - Parameters:
    ///   - sessionId: Runtime Host session id。
    ///   - timeout: 等待秒数。
    /// - Returns: sessionAborted event。
    @discardableResult
    func abortSession(sessionId: String, timeout: TimeInterval) throws -> RuntimeEvent {
        if let abortError {
            throw abortError
        }

        abortedSessionIDs.append(sessionId)
        return RuntimeEvent(
            type: "event",
            id: "evt_aborted",
            replyTo: "cmd_mock",
            sessionId: sessionId,
            name: "sessionAborted",
            payload: .object([:])
        )
    }

    /// 记录取消当前轮请求。
    ///
    /// - Parameters:
    ///   - sessionId: Runtime Host session id。
    ///   - timeout: 等待秒数。
    /// - Returns: turnCancelled event。
    @discardableResult
    func cancelTurn(sessionId: String, timeout: TimeInterval) throws -> RuntimeEvent {
        if let cancelTurnError {
            throw cancelTurnError
        }

        cancelledTurnSessionIDs.append(sessionId)
        return RuntimeEvent(
            type: "event",
            id: "evt_turnCancelled",
            replyTo: "cmd_mock_cancel",
            sessionId: sessionId,
            name: "turnCancelled",
            payload: .object(["cancelled": .bool(true)])
        )
    }

    /// 记录工具审批回传。
    ///
    /// - Parameters:
    ///   - sessionId: Runtime Host session id。
    ///   - toolCallID: Runtime Host 工具调用 id。
    ///   - decision: 审批决策。
    ///   - timeout: 等待秒数。
    /// - Returns: toolApprovalResolved event。
    @discardableResult
    func approveToolCall(
        sessionId: String,
        toolCallID: String,
        decision: ToolApprovalDecision,
        timeout: TimeInterval
    ) throws -> RuntimeEvent {
        approvedToolCalls.append(.init(sessionID: sessionId, toolCallID: toolCallID, decision: decision))
        return RuntimeEvent(
            type: "event",
            id: "evt_toolApprovalResolved",
            replyTo: "cmd_mock_approval",
            sessionId: sessionId,
            name: "toolApprovalResolved",
            payload: .object([
                "toolCallId": .string(toolCallID),
                "decision": .string(decision.runtimeDecision),
            ])
        )
    }
}

/// Session 管理层测试使用的 Agent 配置解析器。
private final class MockAgentConfigResolver: SessionAgentConfigResolving {
    /// 收到的解析请求。
    private(set) var requests: [(String, String)] = []

    private let root: URL

    /// 创建 mock 解析器。
    ///
    /// - Parameter root: 测试 app data 根目录。
    init(root: URL) {
        self.root = root
    }

    /// 返回测试用已解析 Agent 配置。
    ///
    /// - Parameters:
    ///   - id: Agent ID。
    ///   - workspaceDirectory: 会话工作区目录。
    /// - Returns: 测试用 Agent 配置。
    func resolvedAgentConfig(for id: String, workspaceDirectory: URL) throws -> ResolvedAgentConfig {
        requests.append((id, workspaceDirectory.standardizedFileURL.path))
        return ResolvedAgentConfig(
            id: id,
            name: "Support Agent",
            model: .default,
            systemPromptPath: root.appending(path: "agents/\(id)/system.md", directoryHint: .notDirectory).path,
            knowledgePaths: [],
            skillPaths: [],
            toolPaths: [],
            permissions: .default,
            workspacePath: workspaceDirectory.standardizedFileURL.path
        )
    }
}
