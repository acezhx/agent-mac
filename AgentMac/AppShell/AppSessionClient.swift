import ComposableArchitecture
import Foundation

/// AppShell 通过 TCA dependency 使用的 chat session 边界。
///
/// 该类型把 `ChatSessionManager`、`ChatSession` 和 `RuntimeBridge` 包装成 Feature 可注入的操作，
/// 避免 SwiftUI View 直接持有底层服务对象。第一版只暴露固定 Pi coding agent 会话所需能力。
nonisolated struct AppSessionClient: Sendable {
    /// 创建固定 Pi coding agent 的本地 chat session。
    var createSession: @Sendable (_ workspacePath: String) async throws -> ChatSessionSnapshot

    /// 启动 Runtime Host session。
    var startSession: @Sendable () async throws -> Void

    /// 发送用户消息。
    var sendMessage: @Sendable (_ content: String) async throws -> Void

    /// 中断当前 Runtime Host session。
    var abortSession: @Sendable () async throws -> Void

    /// 重置当前本地 session。
    var resetSession: @Sendable () async throws -> Void

    /// 提交当前工具审批决策。
    var resolveToolApproval: @Sendable (_ toolCallID: String, _ decision: ToolApprovalDecision) async throws -> Void

    /// 订阅当前 chat session 的快照变化。
    var snapshots: @Sendable () async throws -> AsyncStream<ChatSessionSnapshot>
}

/// AppShell dependency 对 UI 暴露的结构化错误。
nonisolated struct AppSessionClientError: Error, Equatable, Sendable {
    /// 可直接用于 UI 展示或测试断言的错误信息。
    let message: String

    /// 创建 AppShell 错误。
    ///
    /// - Parameter message: 错误信息。
    init(_ message: String) {
        self.message = message
    }

    /// 从底层错误创建 AppShell 错误。
    ///
    /// - Parameter error: 底层服务错误。
    init(_ error: Error) {
        if let error = error as? AppSessionClientError {
            self.message = error.message
        } else if let runtimeBridgeError = error as? RuntimeBridgeError {
            self.message = Self.message(for: runtimeBridgeError)
        } else if let sessionError = error as? SessionError {
            self.message = Self.message(for: sessionError)
        } else if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            self.message = description
        } else {
            self.message = error.localizedDescription
        }
    }

    private static func message(for error: RuntimeBridgeError) -> String {
        switch error {
        case .bundleResourceDirectoryUnavailable:
            return "AgentMac could not locate bundled app resources. Rebuild the app and verify the Runtime folder is copied into the app bundle."
        case let .nodeExecutableUnavailable(path):
            return "Node runtime is missing or is not executable at \(path). Rebuild AgentMac with bundled Runtime resources, or select development runtime with AGENTMAC_NODE_PATH pointing to a valid Node executable."
        case let .runtimeHostScriptUnavailable(path):
            return "Runtime Host is missing at \(path). Rebuild AgentMac and verify Runtime/host/runtime-host.js is copied into the app bundle."
        case let .piRuntimeUnavailable(path):
            return "Pi runtime is missing at \(path). Run scripts/update-vendored-runtime.mjs, then rebuild AgentMac so Runtime/pi is copied into the app bundle."
        case .processAlreadyRunning:
            return "Runtime Host is already running."
        case .processNotRunning:
            return "Runtime Host is not running. Start the session again."
        case let .processExited(status, stderr):
            let stderr = trimmed(stderr)
            let details = stderr.isEmpty ? "" : " Last stderr: \(truncated(stderr))"
            return "Runtime Host exited before it was ready (status \(status)).\(details) \(runtimeLogHint)"
        case let .eventReadTimeout(seconds):
            return "Runtime Host did not respond within \(formatted(seconds)) seconds. \(runtimeLogHint)"
        case .commandEncodeFailed, .commandWriteFailed, .eventDecodeFailed, .runtimeError, .unexpectedEvent:
            return "Runtime Host communication failed. \(error.localizedDescription) \(runtimeLogHint)"
        }
    }

    private static func message(for error: SessionError) -> String {
        switch error {
        case let .runtimeFailed(code, message, _):
            if message.localizedCaseInsensitiveContains("Pi module entry not found") {
                return "Pi runtime could not be loaded. Rebuild AgentMac with bundled Runtime/pi resources. Details: \(message)"
            }
            if code == "model_failed" {
                return "Pi model or authentication configuration failed. Check ~/Library/Application Support/AgentMac/Pi/settings.json and auth.json. Details: \(message)"
            }
            return "Runtime session failed with \(code). \(message) \(runtimeLogHint)"
        case let .bridgeFailed(message):
            return "Runtime bridge failed. \(message)"
        default:
            return error.localizedDescription
        }
    }

    private static let runtimeLogHint = "Check ~/Library/Application Support/AgentMac/logs/runtime-host.log for details."

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncated(_ text: String, limit: Int = 600) -> String {
        guard text.count > limit else {
            return text
        }
        return "\(text.prefix(limit))..."
    }

    private static func formatted(_ value: TimeInterval) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return String(rounded)
    }
}

extension AppSessionClientError: LocalizedError {
    /// 面向 UI 的错误描述。
    var errorDescription: String? {
        message
    }
}

extension AppSessionClient: DependencyKey {
    /// App 运行时使用的真实 dependency。
    static let liveValue: AppSessionClient = {
        let approvalHandler = InteractiveToolApprovalHandler()
        let controller = LiveAppSessionController(approvalHandler: approvalHandler)
        return AppSessionClient(
            createSession: { workspacePath in
                try await controller.createSession(workspacePath: workspacePath)
            },
            startSession: {
                try await controller.startSession()
            },
            sendMessage: { content in
                try await controller.sendMessage(content)
            },
            abortSession: {
                try await controller.abortSession()
            },
            resetSession: {
                try await controller.resetSession()
            },
            resolveToolApproval: { toolCallID, decision in
                approvalHandler.submit(decision, for: toolCallID)
            },
            snapshots: {
                try await controller.snapshots()
            }
        )
    }()

    /// 测试默认值；具体测试应显式注入 mock。
    static let testValue = AppSessionClient(
        createSession: { _ in
            throw AppSessionClientError("AppSessionClient.createSession is not implemented for this test.")
        },
        startSession: {
            throw AppSessionClientError("AppSessionClient.startSession is not implemented for this test.")
        },
        sendMessage: { _ in
            throw AppSessionClientError("AppSessionClient.sendMessage is not implemented for this test.")
        },
        abortSession: {
            throw AppSessionClientError("AppSessionClient.abortSession is not implemented for this test.")
        },
        resetSession: {
            throw AppSessionClientError("AppSessionClient.resetSession is not implemented for this test.")
        },
        resolveToolApproval: { _, _ in
            throw AppSessionClientError("AppSessionClient.resolveToolApproval is not implemented for this test.")
        },
        snapshots: {
            AsyncStream { continuation in
                continuation.finish()
            }
        }
    )
}

extension DependencyValues {
    /// AppShell chat session dependency。
    var appSessionClient: AppSessionClient {
        get { self[AppSessionClient.self] }
        set { self[AppSessionClient.self] = newValue }
    }
}

/// AppShell live dependency 使用的固定 coding agent session 控制器。
///
/// 该 actor 只负责把现有服务组合成一个当前 UI session，不把 TCA 下沉到 Session 或 RuntimeBridge。
private actor LiveAppSessionController {
    private var storage: LiveStorage?
    private var currentSession: ChatSession?
    private let approvalHandler: InteractiveToolApprovalHandler

    /// 创建 live session 控制器。
    ///
    /// - Parameter approvalHandler: AppShell 提交 UI 决策的交互式审批处理器。
    init(approvalHandler: InteractiveToolApprovalHandler) {
        self.approvalHandler = approvalHandler
    }

    /// 创建固定 coding agent 的本地 session。
    ///
    /// - Parameter workspacePath: UI 传入的工作区路径。
    /// - Returns: 新 session 的当前快照。
    func createSession(workspacePath: String) throws -> ChatSessionSnapshot {
        let storage = try liveStorage()
        let workspaceURL = workspaceURL(from: workspacePath)
        let session = try storage.manager.createSession(
            agentConfig: FixedCodingAgentConfig.resolved(workspaceDirectory: workspaceURL)
        )
        currentSession = session
        return session.snapshot
    }

    /// 启动当前 session 对应的 Runtime Host session。
    func startSession() async throws {
        let storage = try liveStorage()
        try ensureRuntimeStarted(storage)
        let session = try requireCurrentSession()
        try session.start()
    }

    /// 向当前 session 发送用户消息。
    ///
    /// - Parameter content: 用户消息文本。
    func sendMessage(_ content: String) async throws {
        let session = try requireCurrentSession()
        try session.sendUserMessage(content)
    }

    /// 中断当前 Runtime Host session。
    func abortSession() async throws {
        let session = try requireCurrentSession()
        try session.abort()
    }

    /// 重置当前本地 session。
    func resetSession() async throws {
        let session = try requireCurrentSession()
        try session.reset()
    }

    /// 返回当前 session 的快照流。
    ///
    /// - Returns: 当前 session 的 `AsyncStream`。
    func snapshots() throws -> AsyncStream<ChatSessionSnapshot> {
        try requireCurrentSession().snapshots()
    }

    private func liveStorage() throws -> LiveStorage {
        if let storage {
            return storage
        }

        let fileStore = try FileStore()
        try fileStore.initialize()

        let runtimeBridge = RuntimeBridge(
            configuration: try runtimeBridgeConfiguration(fileStore: fileStore)
        )
        let manager = ChatSessionManager(
            fileStore: fileStore,
            agentConfigResolver: FixedCodingAgentResolver(),
            runtimeBridge: runtimeBridge,
            approvalHandler: approvalHandler
        )
        let storage = LiveStorage(
            fileStore: fileStore,
            runtimeBridge: runtimeBridge,
            manager: manager
        )
        self.storage = storage
        return storage
    }

    private func ensureRuntimeStarted(_ storage: LiveStorage) throws {
        guard !storage.runtimeStarted else {
            return
        }

        do {
            try storage.runtimeBridge.start()
            try storage.runtimeBridge.ping()
            storage.runtimeStarted = true
        } catch {
            storage.runtimeBridge.stop()
            throw error
        }
    }

    private func requireCurrentSession() throws -> ChatSession {
        guard let currentSession else {
            throw AppSessionClientError("Create a chat session before using it.")
        }
        return currentSession
    }

    private func workspaceURL(from path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        }
        return URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL
    }

    private func runtimeBridgeConfiguration(fileStore: FileStore) throws -> RuntimeBridgeConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let appSupportURL = fileStore.layout.rootDirectory
        let logDirectoryURL = fileStore.layout.logsDirectory
        let mode = normalizedRuntimeMode(from: environment["AGENTMAC_RUNTIME_MODE"])
        let runtimeEnvironment = [
            "AGENTMAC_APP_SUPPORT_DIR": appSupportURL.path,
            "AGENTMAC_LOG_DIR": logDirectoryURL.path,
            "AGENTMAC_PI_AGENT_DIR": appSupportURL.appendingPathComponent("Pi", isDirectory: true).path,
            "AGENTMAC_RUNTIME_MODE": mode,
        ]

        switch mode {
        case "bundled":
            return try RuntimeBridgeConfiguration.bundled(
                workingDirectoryURL: appSupportURL,
                environment: runtimeEnvironment,
                stderrLogFileURL: logDirectoryURL.appendingPathComponent("runtime-host.log", isDirectory: false)
            )
        case "development":
            guard let nodePath = environment["AGENTMAC_NODE_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !nodePath.isEmpty
            else {
                throw AppSessionClientError("Development runtime is selected but AGENTMAC_NODE_PATH is not set. Remove AGENTMAC_RUNTIME_MODE=development to use bundled runtime, or set AGENTMAC_NODE_PATH to a valid Node executable.")
            }
            guard let hostPath = environment["AGENTMAC_RUNTIME_HOST_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !hostPath.isEmpty
            else {
                throw AppSessionClientError("Development runtime is selected but AGENTMAC_RUNTIME_HOST_PATH is not set. Remove AGENTMAC_RUNTIME_MODE=development to use bundled runtime, or set AGENTMAC_RUNTIME_HOST_PATH to runtime-host.js.")
            }
            return RuntimeBridgeConfiguration(
                nodeExecutableURL: URL(fileURLWithPath: nodePath, isDirectory: false),
                runtimeHostScriptURL: URL(fileURLWithPath: hostPath, isDirectory: false),
                workingDirectoryURL: appSupportURL,
                environment: runtimeEnvironment,
                stderrLogFileURL: logDirectoryURL.appendingPathComponent("runtime-host.log", isDirectory: false)
            )
        default:
            throw AppSessionClientError("Unsupported AGENTMAC_RUNTIME_MODE '\(mode)'. Use 'bundled' for clean app launch or 'development' with explicit Node and Runtime Host paths.")
        }
    }

    private func normalizedRuntimeMode(from rawValue: String?) -> String {
        let mode = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return mode.isEmpty ? "bundled" : mode
    }
}

/// live AppShell dependency 内部持有的服务实例集合。
private nonisolated final class LiveStorage {
    /// Application Support 文件服务。
    let fileStore: FileStore

    /// Runtime Host 桥接层。
    let runtimeBridge: RuntimeBridge

    /// ChatSession 管理层。
    let manager: ChatSessionManager

    /// Runtime Host 进程是否已经启动并通过 ping 验证。
    var runtimeStarted: Bool

    /// 创建服务实例集合。
    init(fileStore: FileStore, runtimeBridge: RuntimeBridge, manager: ChatSessionManager) {
        self.fileStore = fileStore
        self.runtimeBridge = runtimeBridge
        self.manager = manager
        self.runtimeStarted = false
    }
}

/// 固定 Pi coding agent 的临时配置工厂。
private nonisolated enum FixedCodingAgentConfig {
    /// 旧版固定 coding agent session record 中使用的内部 ID。
    static let legacyID = "fixed-coding-agent"

    /// 固定 Pi coding agent 的内部 ID。
    static let id = DefaultCodingAgentTemplate.id

    /// 固定 Pi coding agent 的展示名称。
    static let name = DefaultCodingAgentTemplate.name

    /// 生成当前阶段使用的 `ResolvedAgentConfig`。
    ///
    /// - Parameter workspaceDirectory: 会话工作区目录。
    /// - Returns: 固定 coding agent 的运行配置。
    static func resolved(workspaceDirectory: URL) -> ResolvedAgentConfig {
        ResolvedAgentConfig(
            id: id,
            name: name,
            model: .default,
            systemPromptPath: "",
            knowledgePaths: [],
            skillPaths: [],
            toolPaths: [],
            permissions: .default,
            workspacePath: workspaceDirectory.standardizedFileURL.path
        )
    }
}

/// Session 恢复路径使用的固定 coding agent 配置解析器。
private nonisolated struct FixedCodingAgentResolver: SessionAgentConfigResolving {
    /// 生成固定 coding agent 的运行配置。
    ///
    /// - Parameters:
    ///   - id: 恢复记录中的 Agent ID；第一阶段只接受固定 ID。
    ///   - workspaceDirectory: 会话工作区目录。
    /// - Returns: 固定 coding agent 的运行配置。
    func resolvedAgentConfig(for id: String, workspaceDirectory: URL) throws -> ResolvedAgentConfig {
        guard id == FixedCodingAgentConfig.id || id == FixedCodingAgentConfig.legacyID else {
            throw AppSessionClientError("Unsupported Pi coding agent id: \(id).")
        }
        return FixedCodingAgentConfig.resolved(workspaceDirectory: workspaceDirectory)
    }
}
