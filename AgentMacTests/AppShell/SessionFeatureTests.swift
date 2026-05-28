import ComposableArchitecture
import Foundation
import Testing
@testable import AgentMac

/// AppShell 会话 Feature 的状态流转测试。
///
/// 测试只注入 mock `AppSessionClient`，不启动 Runtime Host，也不访问真实 Application Support。
@MainActor
struct SessionFeatureTests {
    /// 验证创建 session 会保存快照并启动快照订阅。
    @Test func createSessionStoresSnapshot() async {
        let snapshot = makeSnapshot()
        let stream = AsyncStream<ChatSessionSnapshot> { continuation in
            continuation.finish()
        }
        let store = TestStore(initialState: SessionFeature.State(workspacePath: "/tmp/workspace")) {
            SessionFeature()
        } withDependencies: {
            $0.appSessionClient = AppSessionClient(
                createSession: { workspacePath in
                    #expect(workspacePath == "/tmp/workspace")
                    return snapshot
                },
                startSession: {},
                sendMessage: { _ in },
                abortSession: {},
                resetSession: {},
                resolveToolApproval: { _, _ in },
                snapshots: { stream }
            )
        }

        await store.send(.createSessionButtonTapped) {
            $0.isCreatingSession = true
            $0.errorMessage = nil
        }
        await store.receive(.createSessionSucceeded(snapshot)) {
            $0.isCreatingSession = false
            $0.snapshot = snapshot
            $0.errorMessage = nil
        }
        await store.finish()
    }

    /// 验证第一阶段已有当前 session 时不会创建第二个 session。
    @Test func createSessionIsIgnoredWhenSnapshotExists() async {
        let snapshot = makeSnapshot()
        let newSnapshot = makeSnapshot(runtimeSessionID: "ses_should_not_create")
        let recorder = Recorder()
        var state = SessionFeature.State(workspacePath: "/tmp/workspace")
        state.snapshot = snapshot
        let store = TestStore(initialState: state) {
            SessionFeature()
        } withDependencies: {
            $0.appSessionClient = makeClient(
                createSession: { _ in
                    recorder.didCreate = true
                    return newSnapshot
                }
            )
        }

        await store.send(.createSessionButtonTapped)

        #expect(!recorder.didCreate)
        await store.finish()
    }

    /// 验证创建 session 失败时清理进行中标记并展示错误。
    @Test func createSessionFailureClearsFlagAndStoresError() async {
        let error = AppSessionClientError("create failed")
        let store = TestStore(initialState: SessionFeature.State(workspacePath: "/tmp/workspace")) {
            SessionFeature()
        } withDependencies: {
            $0.appSessionClient = makeClient(
                createSession: { _ in
                    throw error
                }
            )
        }

        await store.send(.createSessionButtonTapped) {
            $0.isCreatingSession = true
            $0.errorMessage = nil
        }
        await store.receive(.createSessionFailed(error)) {
            $0.isCreatingSession = false
            $0.errorMessage = "create failed"
        }
        await store.finish()
    }

    /// 验证启动 Runtime session 的成功路径。
    @Test func startSessionClearsStartingFlag() async {
        let snapshot = makeSnapshot()
        let recorder = Recorder()
        let store = TestStore(initialState: SessionFeature.State(workspacePath: "/tmp/workspace")) {
            SessionFeature()
        } withDependencies: {
            $0.appSessionClient = AppSessionClient(
                createSession: { _ in snapshot },
                startSession: {
                    recorder.didStart = true
                },
                sendMessage: { _ in },
                abortSession: {},
                resetSession: {},
                resolveToolApproval: { _, _ in },
                snapshots: { AsyncStream { $0.finish() } }
            )
        }
        await store.send(.snapshotUpdated(snapshot)) {
            $0.snapshot = snapshot
        }

        await store.send(.startSessionButtonTapped) {
            $0.isStartingSession = true
            $0.errorMessage = nil
        }
        await store.receive(.startSessionSucceeded) {
            $0.isStartingSession = false
        }

        #expect(recorder.didStart)
    }

    /// 验证启动 Runtime session 失败时清理进行中标记并展示错误。
    @Test func startSessionFailureClearsFlagAndStoresError() async {
        let snapshot = makeSnapshot()
        let error = AppSessionClientError("start failed")
        var state = SessionFeature.State(workspacePath: "/tmp/workspace")
        state.snapshot = snapshot
        let store = TestStore(initialState: state) {
            SessionFeature()
        } withDependencies: {
            $0.appSessionClient = makeClient(
                startSession: {
                    throw error
                }
            )
        }

        await store.send(.startSessionButtonTapped) {
            $0.isStartingSession = true
            $0.errorMessage = nil
        }
        await store.receive(.startSessionFailed(error)) {
            $0.isStartingSession = false
            $0.errorMessage = "start failed"
        }
        await store.finish()
    }

    /// 验证发送消息会清空输入并调用 dependency。
    @Test func sendMessageClearsInputAndFinishes() async {
        let snapshot = makeSnapshot(runtimeSessionID: "ses_001", state: .running)
        let recorder = Recorder()
        let store = TestStore(initialState: SessionFeature.State(workspacePath: "/tmp/workspace")) {
            SessionFeature()
        } withDependencies: {
            $0.appSessionClient = AppSessionClient(
                createSession: { _ in snapshot },
                startSession: {},
                sendMessage: { content in
                    recorder.sentMessages.append(content)
                },
                abortSession: {},
                resetSession: {},
                resolveToolApproval: { _, _ in },
                snapshots: { AsyncStream { $0.finish() } }
            )
        }
        await store.send(.snapshotUpdated(snapshot)) {
            $0.snapshot = snapshot
        }
        await store.send(.messageTextChanged("  ping  ")) {
            $0.messageText = "  ping  "
        }

        await store.send(.sendMessageButtonTapped) {
            $0.messageText = ""
            $0.isSendingMessage = true
            $0.errorMessage = nil
        }
        await store.receive(.sendMessageSucceeded) {
            $0.isSendingMessage = false
        }

        #expect(recorder.sentMessages == ["ping"])
    }

    /// 验证发送消息失败时保留清空后的输入状态并展示错误。
    @Test func sendMessageFailureClearsFlagAndStoresError() async {
        let snapshot = makeSnapshot(runtimeSessionID: "ses_001", state: .running)
        let error = AppSessionClientError("send failed")
        let recorder = Recorder()
        var state = SessionFeature.State(workspacePath: "/tmp/workspace")
        state.snapshot = snapshot
        state.messageText = "  ping  "
        let store = TestStore(initialState: state) {
            SessionFeature()
        } withDependencies: {
            $0.appSessionClient = makeClient(
                sendMessage: { content in
                    recorder.sentMessages.append(content)
                    throw error
                }
            )
        }

        await store.send(.sendMessageButtonTapped) {
            $0.messageText = ""
            $0.isSendingMessage = true
            $0.errorMessage = nil
        }
        await store.receive(.sendMessageFailed(error)) {
            $0.isSendingMessage = false
            $0.errorMessage = "send failed"
        }

        #expect(recorder.sentMessages == ["ping"])
        await store.finish()
    }

    /// 验证失败快照会同步 UI 错误信息。
    @Test func failedSnapshotStoresErrorMessage() async {
        let error = SessionError.runtimeFailed(code: "runtime_failed", message: "boom", recoverable: true)
        let snapshot = makeSnapshot(runtimeSessionID: "ses_001", state: .failed(error))
        let store = TestStore(initialState: SessionFeature.State(workspacePath: "/tmp/workspace")) {
            SessionFeature()
        } withDependencies: {
            $0.appSessionClient = AppSessionClient(
                createSession: { _ in snapshot },
                startSession: {},
                sendMessage: { _ in },
                abortSession: {},
                resetSession: {},
                resolveToolApproval: { _, _ in },
                snapshots: { AsyncStream { $0.finish() } }
            )
        }

        await store.send(.snapshotUpdated(snapshot)) {
            $0.snapshot = snapshot
            $0.errorMessage = error.localizedDescription
        }
    }

    /// 验证用户批准工具审批会通过 AppSessionClient 回传。
    @Test func allowToolApprovalSubmitsDecision() async {
        let request = makePendingApprovalRequest()
        let snapshot = makeSnapshot(
            runtimeSessionID: "ses_001",
            state: .running,
            pendingToolApprovalRequest: request
        )
        let recorder = Recorder()
        var state = SessionFeature.State(workspacePath: "/tmp/workspace")
        state.snapshot = snapshot
        let store = TestStore(initialState: state) {
            SessionFeature()
        } withDependencies: {
            $0.appSessionClient = makeClient(
                resolveToolApproval: { toolCallID, decision in
                    recorder.approvalDecisions.append(.init(toolCallID: toolCallID, decision: decision))
                }
            )
        }

        await store.send(.allowToolApprovalButtonTapped("tool_001")) {
            $0.isResolvingToolApproval = true
            $0.errorMessage = nil
        }
        await store.receive(.resolveToolApprovalSucceeded("tool_001")) {
            $0.isResolvingToolApproval = false
            $0.submittedToolApprovalIDs = ["tool_001"]
        }
        await store.send(.denyToolApprovalButtonTapped("tool_001"))

        #expect(recorder.approvalDecisions == [
            .init(toolCallID: "tool_001", decision: .allowed(reason: "Approved by user.")),
        ])
        await store.finish()
    }

    /// 验证关闭审批 UI 会按 deny 回传。
    @Test func dismissedToolApprovalSubmitsDeniedDecision() async {
        let request = makePendingApprovalRequest()
        let snapshot = makeSnapshot(
            runtimeSessionID: "ses_001",
            state: .running,
            pendingToolApprovalRequest: request
        )
        let recorder = Recorder()
        var state = SessionFeature.State(workspacePath: "/tmp/workspace")
        state.snapshot = snapshot
        let store = TestStore(initialState: state) {
            SessionFeature()
        } withDependencies: {
            $0.appSessionClient = makeClient(
                resolveToolApproval: { toolCallID, decision in
                    recorder.approvalDecisions.append(.init(toolCallID: toolCallID, decision: decision))
                }
            )
        }

        await store.send(.toolApprovalSheetDismissed("tool_001")) {
            $0.isResolvingToolApproval = true
            $0.errorMessage = nil
        }
        await store.receive(.resolveToolApprovalSucceeded("tool_001")) {
            $0.isResolvingToolApproval = false
            $0.submittedToolApprovalIDs = ["tool_001"]
        }

        #expect(recorder.approvalDecisions == [
            .init(toolCallID: "tool_001", decision: .denied(reason: "Approval UI was dismissed.")),
        ])
        await store.finish()
    }

    /// 验证 abort/reset action 会通过 dependency，并清理进行中标记。
    @Test func abortAndResetCallDependency() async {
        let snapshot = makeSnapshot(runtimeSessionID: "ses_001", state: .running)
        let recorder = Recorder()
        let store = TestStore(initialState: SessionFeature.State(workspacePath: "/tmp/workspace")) {
            SessionFeature()
        } withDependencies: {
            $0.appSessionClient = AppSessionClient(
                createSession: { _ in snapshot },
                startSession: {},
                sendMessage: { _ in },
                abortSession: {
                    recorder.didAbort = true
                },
                resetSession: {
                    recorder.didReset = true
                },
                resolveToolApproval: { _, _ in },
                snapshots: { AsyncStream { $0.finish() } }
            )
        }
        await store.send(.snapshotUpdated(snapshot)) {
            $0.snapshot = snapshot
        }

        await store.send(.abortSessionButtonTapped) {
            $0.isAbortingSession = true
            $0.errorMessage = nil
        }
        await store.receive(.abortSessionSucceeded) {
            $0.isAbortingSession = false
        }
        await store.send(.resetSessionButtonTapped) {
            $0.isResettingSession = true
            $0.errorMessage = nil
        }
        await store.receive(.resetSessionSucceeded) {
            $0.isResettingSession = false
        }

        #expect(recorder.didAbort)
        #expect(recorder.didReset)
    }

    /// 验证中断 session 失败时清理进行中标记并展示错误。
    @Test func abortSessionFailureClearsFlagAndStoresError() async {
        let snapshot = makeSnapshot(runtimeSessionID: "ses_001", state: .running)
        let error = AppSessionClientError("abort failed")
        var state = SessionFeature.State(workspacePath: "/tmp/workspace")
        state.snapshot = snapshot
        let store = TestStore(initialState: state) {
            SessionFeature()
        } withDependencies: {
            $0.appSessionClient = makeClient(
                abortSession: {
                    throw error
                }
            )
        }

        await store.send(.abortSessionButtonTapped) {
            $0.isAbortingSession = true
            $0.errorMessage = nil
        }
        await store.receive(.abortSessionFailed(error)) {
            $0.isAbortingSession = false
            $0.errorMessage = "abort failed"
        }
        await store.finish()
    }

    /// 验证重置 session 失败时清理进行中标记并展示错误。
    @Test func resetSessionFailureClearsFlagAndStoresError() async {
        let snapshot = makeSnapshot(runtimeSessionID: "ses_001", state: .aborted)
        let error = AppSessionClientError("reset failed")
        var state = SessionFeature.State(workspacePath: "/tmp/workspace")
        state.snapshot = snapshot
        let store = TestStore(initialState: state) {
            SessionFeature()
        } withDependencies: {
            $0.appSessionClient = makeClient(
                resetSession: {
                    throw error
                }
            )
        }

        await store.send(.resetSessionButtonTapped) {
            $0.isResettingSession = true
            $0.errorMessage = nil
        }
        await store.receive(.resetSessionFailed(error)) {
            $0.isResettingSession = false
            $0.errorMessage = "reset failed"
        }
        await store.finish()
    }

    /// 验证快照订阅失败会展示错误。
    @Test func snapshotObservationFailureStoresError() async {
        let error = AppSessionClientError("snapshot failed")
        let store = TestStore(initialState: SessionFeature.State(workspacePath: "/tmp/workspace")) {
            SessionFeature()
        }

        await store.send(.snapshotObservationFailed(error)) {
            $0.errorMessage = "snapshot failed"
        }
    }

    private func makeClient(
        createSession: @escaping @Sendable (String) async throws -> ChatSessionSnapshot = { _ in
            throw AppSessionClientError("Unexpected createSession call.")
        },
        startSession: @escaping @Sendable () async throws -> Void = {
            throw AppSessionClientError("Unexpected startSession call.")
        },
        sendMessage: @escaping @Sendable (String) async throws -> Void = { _ in
            throw AppSessionClientError("Unexpected sendMessage call.")
        },
        abortSession: @escaping @Sendable () async throws -> Void = {
            throw AppSessionClientError("Unexpected abortSession call.")
        },
        resetSession: @escaping @Sendable () async throws -> Void = {
            throw AppSessionClientError("Unexpected resetSession call.")
        },
        resolveToolApproval: @escaping @Sendable (String, ToolApprovalDecision) async throws -> Void = { _, _ in
            throw AppSessionClientError("Unexpected resolveToolApproval call.")
        },
        snapshots: @escaping @Sendable () async throws -> AsyncStream<ChatSessionSnapshot> = {
            AsyncStream { continuation in
                continuation.finish()
            }
        }
    ) -> AppSessionClient {
        AppSessionClient(
            createSession: createSession,
            startSession: startSession,
            sendMessage: sendMessage,
            abortSession: abortSession,
            resetSession: resetSession,
            resolveToolApproval: resolveToolApproval,
            snapshots: snapshots
        )
    }

    private func makeSnapshot(
        runtimeSessionID: String? = nil,
        state: SessionState = .idle,
        messages: [ChatMessage] = [],
        pendingToolApprovalRequest: ToolApprovalRequest? = nil
    ) -> ChatSessionSnapshot {
        ChatSessionSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            runtimeSessionID: runtimeSessionID,
            state: state,
            messages: messages,
            pendingToolApprovalRequest: pendingToolApprovalRequest,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func makePendingApprovalRequest() -> ToolApprovalRequest {
        ToolApprovalRequest(
            toolCallID: "tool_001",
            toolName: "bash",
            risk: .shell,
            summary: "Run shell command",
            details: [
                .init(key: "command", value: "ls -la"),
            ]
        )
    }
}

/// `@Sendable` mock closures 中记录调用情况的简单容器。
private final class Recorder: @unchecked Sendable {
    /// createSession 是否被调用。
    var didCreate = false

    /// start 是否被调用。
    var didStart = false

    /// sendMessage 收到的消息。
    var sentMessages: [String] = []

    /// abort 是否被调用。
    var didAbort = false

    /// reset 是否被调用。
    var didReset = false

    /// 审批决策提交记录。
    var approvalDecisions: [ApprovalDecisionRecord] = []
}

/// 测试用审批提交记录。
private struct ApprovalDecisionRecord: Equatable {
    /// Runtime Host 工具调用 id。
    let toolCallID: String

    /// 提交的审批决策。
    let decision: ToolApprovalDecision
}
