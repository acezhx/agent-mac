import Foundation

/// RuntimeBridge JSON payload 中可稳定编码和解码的 JSON 值。
///
/// 该类型只服务 Swift 与 Node Runtime Host 的私有协议，不承载业务模型语义。
nonisolated enum RuntimeJSONValue: Codable, Equatable, Sendable {
    /// JSON null。
    case null

    /// JSON boolean。
    case bool(Bool)

    /// JSON number。
    case number(Double)

    /// JSON string。
    case string(String)

    /// JSON array。
    case array([RuntimeJSONValue])

    /// JSON object。
    case object([String: RuntimeJSONValue])

    /// 从任意 JSON 值解码。
    ///
    /// - Parameter decoder: Swift decoder。
    /// - Throws: 输入不是受支持 JSON 类型时抛出解码错误。
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([RuntimeJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: RuntimeJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    /// 编码为 JSON 值。
    ///
    /// - Parameter encoder: Swift encoder。
    /// - Throws: 底层编码失败时抛出错误。
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    /// 当值为 string 时返回其内容。
    var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    /// 当值为 bool 时返回其内容。
    var boolValue: Bool? {
        if case let .bool(value) = self {
            return value
        }
        return nil
    }

    /// 当值为 object 时返回指定字段。
    ///
    /// - Parameter key: object 字段名。
    /// - Returns: 字段值；当前值不是 object 或字段不存在时返回 nil。
    subscript(key: String) -> RuntimeJSONValue? {
        if case let .object(value) = self {
            return value[key]
        }
        return nil
    }
}

/// 发往 Runtime Host 的 command envelope。
nonisolated struct RuntimeCommand: Codable, Equatable, Sendable {
    /// command envelope 类型，固定为 `command`。
    let type: String

    /// Swift 侧生成的 command id。
    let id: String

    /// Runtime Host command 名称。
    let name: String

    /// command payload。
    let payload: RuntimeJSONValue?

    /// 创建 Runtime Host command。
    ///
    /// - Parameters:
    ///   - id: Swift 侧生成的 command id。
    ///   - name: Runtime Host command 名称。
    ///   - payload: command payload，默认为空 object。
    init(id: String, name: String, payload: RuntimeJSONValue? = .object([:])) {
        self.type = "command"
        self.id = id
        self.name = name
        self.payload = payload
    }
}

/// Runtime Host 输出的 event envelope。
nonisolated struct RuntimeEvent: Codable, Equatable, Sendable {
    /// event envelope 类型，固定为 `event`。
    let type: String

    /// Runtime Host 生成的 event id。
    let id: String

    /// 对应 command id。Runtime Host 对协议级错误可能返回 null。
    let replyTo: String?

    /// session 相关事件携带的 session id。
    let sessionId: String?

    /// Runtime Host event 名称。
    let name: String

    /// event payload。
    let payload: RuntimeJSONValue?
}

/// RuntimeBridge 路径和进程环境配置。
nonisolated struct RuntimeBridgeConfiguration: Equatable, Sendable {
    /// Node 可执行文件路径。
    let nodeExecutableURL: URL

    /// Runtime Host JavaScript 入口路径。
    let runtimeHostScriptURL: URL

    /// Runtime Host 进程工作目录。
    let workingDirectoryURL: URL

    /// 传给 Runtime Host 的额外环境变量。
    let environment: [String: String]

    /// 创建 RuntimeBridge 配置。
    ///
    /// - Parameters:
    ///   - nodeExecutableURL: Node 可执行文件路径。
    ///   - runtimeHostScriptURL: Runtime Host JavaScript 入口路径。
    ///   - workingDirectoryURL: Runtime Host 工作目录。
    ///   - environment: 额外环境变量；会覆盖当前进程同名环境变量。
    init(
        nodeExecutableURL: URL,
        runtimeHostScriptURL: URL,
        workingDirectoryURL: URL,
        environment: [String: String] = [:]
    ) {
        self.nodeExecutableURL = nodeExecutableURL.standardizedFileURL
        self.runtimeHostScriptURL = runtimeHostScriptURL.standardizedFileURL
        self.workingDirectoryURL = workingDirectoryURL.standardizedFileURL
        self.environment = environment
    }

    /// 生成 app bundle 内置 runtime 配置。
    ///
    /// - Parameters:
    ///   - bundle: 包含 `Contents/Resources/Runtime` 的 app bundle。
    ///   - workingDirectoryURL: Runtime Host 工作目录，通常是 Application Support 根目录。
    ///   - environment: 额外环境变量。
    /// - Returns: 指向 bundle 内 Node 和 Runtime Host 的配置。
    /// - Throws: bundle 没有 resources URL 时抛出 RuntimeBridgeError。
    static func bundled(
        bundle: Bundle = .main,
        workingDirectoryURL: URL,
        environment: [String: String] = [:]
    ) throws -> RuntimeBridgeConfiguration {
        guard let resourcesURL = bundle.resourceURL else {
            throw RuntimeBridgeError.bundleResourceDirectoryUnavailable
        }

        let runtimeRoot = resourcesURL.appendingPathComponent("Runtime", isDirectory: true)
        return RuntimeBridgeConfiguration(
            nodeExecutableURL: runtimeRoot.appendingPathComponent("node/bin/node", isDirectory: false),
            runtimeHostScriptURL: runtimeRoot.appendingPathComponent("host/runtime-host.js", isDirectory: false),
            workingDirectoryURL: workingDirectoryURL,
            environment: environment
        )
    }

    /// 校验 RuntimeBridge 启动所需的本地文件。
    ///
    /// - Parameter fileManager: 文件系统访问对象。
    /// - Throws: Node 不存在、不可执行或 Runtime Host 入口不存在时抛出 RuntimeBridgeError。
    func validate(fileManager: FileManager = .default) throws {
        guard fileManager.isExecutableFile(atPath: nodeExecutableURL.path) else {
            throw RuntimeBridgeError.nodeExecutableUnavailable(path: nodeExecutableURL.path)
        }
        guard fileManager.fileExists(atPath: runtimeHostScriptURL.path) else {
            throw RuntimeBridgeError.runtimeHostScriptUnavailable(path: runtimeHostScriptURL.path)
        }
    }
}

/// RuntimeBridge 进程和协议层错误。
nonisolated enum RuntimeBridgeError: Error, Equatable, Sendable {
    /// app bundle resources URL 不可用。
    case bundleResourceDirectoryUnavailable

    /// Node 可执行文件不存在或不可执行。
    case nodeExecutableUnavailable(path: String)

    /// Runtime Host 脚本不存在。
    case runtimeHostScriptUnavailable(path: String)

    /// Runtime Host 进程已经启动。
    case processAlreadyRunning

    /// Runtime Host 进程尚未启动。
    case processNotRunning

    /// Runtime Host 进程已经退出。
    case processExited(status: Int32, stderr: String)

    /// 等待 event 超时。
    case eventReadTimeout(seconds: TimeInterval)

    /// command 编码失败。
    case commandEncodeFailed(reason: String)

    /// command 写入 stdin 失败。
    case commandWriteFailed(reason: String)

    /// stdout 输出的 JSONL event 无法解析。
    case eventDecodeFailed(line: String, reason: String)

    /// Runtime Host 返回 error event。
    case runtimeError(code: String, message: String, recoverable: Bool, details: RuntimeJSONValue?)

    /// 收到的 event 与当前 command 期望不匹配。
    case unexpectedEvent(name: String, replyTo: String?)
}

extension RuntimeBridgeError: LocalizedError {
    /// 面向日志和 UI 诊断的错误描述。
    var errorDescription: String? {
        switch self {
        case .bundleResourceDirectoryUnavailable:
            "Bundle resource directory is unavailable."
        case let .nodeExecutableUnavailable(path):
            "Node executable is unavailable: \(path)"
        case let .runtimeHostScriptUnavailable(path):
            "Runtime Host script is unavailable: \(path)"
        case .processAlreadyRunning:
            "Runtime Host process is already running."
        case .processNotRunning:
            "Runtime Host process is not running."
        case let .processExited(status, stderr):
            "Runtime Host process exited with status \(status): \(stderr)"
        case let .eventReadTimeout(seconds):
            "Timed out waiting for Runtime Host event after \(seconds) seconds."
        case let .commandEncodeFailed(reason):
            "Failed to encode Runtime Host command: \(reason)"
        case let .commandWriteFailed(reason):
            "Failed to write Runtime Host command: \(reason)"
        case let .eventDecodeFailed(line, reason):
            "Failed to decode Runtime Host event '\(line)': \(reason)"
        case let .runtimeError(code, message, _, _):
            "Runtime Host returned error \(code): \(message)"
        case let .unexpectedEvent(name, replyTo):
            "Unexpected Runtime Host event '\(name)' for command \(replyTo ?? "nil")."
        }
    }
}

/// Swift 侧 Runtime Host 进程桥接层。
///
/// `RuntimeBridge` 只负责本地进程、stdin/stdout JSONL 和稳定 Swift 类型映射。它不解析 Agent
/// 文件，不包含 Pi SDK 代码，也不直接处理 UI 或 Approval。
nonisolated final class RuntimeBridge: @unchecked Sendable {
    /// RuntimeHost 启动配置。
    let configuration: RuntimeBridgeConfiguration

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let stateQueue = DispatchQueue(label: "cn.himo.AgentMac.RuntimeBridge.state")
    private var eventSemaphore = DispatchSemaphore(value: 0)

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = Data()
    private var eventResults: [Result<RuntimeEvent, RuntimeBridgeError>] = []
    private var stderrText = ""
    private var nextCommandNumber = 1
    private var runGeneration = UUID()

    /// 创建 RuntimeBridge。
    ///
    /// - Parameters:
    ///   - configuration: RuntimeHost 启动配置。
    ///   - fileManager: 文件系统访问对象，默认使用 `.default`。
    init(configuration: RuntimeBridgeConfiguration, fileManager: FileManager = .default) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    deinit {
        stop()
    }

    /// 启动 Runtime Host 进程。
    ///
    /// - Throws: 配置无效、进程重复启动或 `Process.run()` 失败时抛出错误。
    func start() throws {
        try configuration.validate(fileManager: fileManager)
        let alreadyRunning = stateQueue.sync {
            self.process?.isRunning == true
        }
        if alreadyRunning {
            throw RuntimeBridgeError.processAlreadyRunning
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let runGeneration = UUID()

        process.executableURL = configuration.nodeExecutableURL
        process.arguments = [configuration.runtimeHostScriptURL.path]
        process.currentDirectoryURL = configuration.workingDirectoryURL
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = ProcessInfo.processInfo.environment.merging(configuration.environment) { _, new in new }

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                return
            }
            self?.appendStdoutData(data, generation: runGeneration)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                return
            }
            self?.appendStderrData(data, generation: runGeneration)
        }
        process.terminationHandler = { [weak self] process in
            self?.appendProcessExited(status: process.terminationStatus, generation: runGeneration)
        }

        stateQueue.sync {
            self.process = process
            self.stdinPipe = stdinPipe
            self.stdoutPipe = stdoutPipe
            self.stderrPipe = stderrPipe
            self.stdoutBuffer = Data()
            self.eventResults = []
            self.stderrText = ""
            self.eventSemaphore = DispatchSemaphore(value: 0)
            self.runGeneration = runGeneration
        }

        do {
            try process.run()
        } catch {
            cleanupProcessHandlers()
            stateQueue.sync {
                self.process = nil
                self.stdinPipe = nil
                self.stdoutPipe = nil
                self.stderrPipe = nil
                self.stdoutBuffer = Data()
                self.eventResults = []
                self.eventSemaphore = DispatchSemaphore(value: 0)
                self.runGeneration = UUID()
            }
            throw RuntimeBridgeError.processExited(status: process.terminationStatus, stderr: error.localizedDescription)
        }
    }

    /// 停止 Runtime Host 进程并释放 pipe handler。
    ///
    /// 该方法幂等；进程未启动时直接返回。
    func stop() {
        let snapshot = stateQueue.sync {
            (process, stdinPipe, stdoutPipe, stderrPipe)
        }

        cleanupProcessHandlers()
        try? snapshot.1?.fileHandleForWriting.close()
        if let process = snapshot.0, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try? snapshot.2?.fileHandleForReading.close()
        try? snapshot.3?.fileHandleForReading.close()

        stateQueue.sync {
            self.process = nil
            self.stdinPipe = nil
            self.stdoutPipe = nil
            self.stderrPipe = nil
            self.stdoutBuffer = Data()
            self.eventResults = []
            self.eventSemaphore = DispatchSemaphore(value: 0)
            self.runGeneration = UUID()
        }
    }

    /// 发送 `ping` command 并等待 `pong`。
    ///
    /// - Parameter timeout: 等待 Runtime Host event 的秒数。
    /// - Returns: Runtime Host 返回的 `pong` event。
    /// - Throws: 进程未启动、写入失败、超时或收到 error event 时抛出错误。
    @discardableResult
    func ping(timeout: TimeInterval = 5) throws -> RuntimeEvent {
        let command = RuntimeCommand(id: nextCommandID(), name: "ping")
        try send(command)
        let event = try readMatchingEvent(replyTo: command.id, timeout: timeout)
        guard event.name == "pong" else {
            throw RuntimeBridgeError.unexpectedEvent(name: event.name, replyTo: event.replyTo)
        }
        return event
    }

    /// 启动固定 Pi coding agent session。
    ///
    /// - Parameters:
    ///   - workspacePath: 传给 Runtime Host 的工作目录，nil 时由 Runtime Host 使用默认值。
    ///   - timeout: 等待 sessionStarted 的秒数。
    /// - Returns: Runtime Host session id。
    /// - Throws: 进程未启动、写入失败、超时或 Runtime Host 返回 error event 时抛出错误。
    func startSession(workspacePath: String? = nil, timeout: TimeInterval = 5) throws -> String {
        var payload: [String: RuntimeJSONValue] = [
            "agent": .object(["mode": .string("fixedCodingAgent")]),
        ]
        if let workspacePath {
            payload["workspacePath"] = .string(workspacePath)
        }

        let command = RuntimeCommand(id: nextCommandID(), name: "startSession", payload: .object(payload))
        try send(command)
        let event = try readMatchingEvent(replyTo: command.id, timeout: timeout)
        guard event.name == "sessionStarted", let sessionId = event.sessionId else {
            throw RuntimeBridgeError.unexpectedEvent(name: event.name, replyTo: event.replyTo)
        }
        return sessionId
    }

    /// 发送用户消息，并收集直到 `messageCompleted` 的流式事件。
    ///
    /// - Parameters:
    ///   - sessionId: Runtime Host session id。
    ///   - content: 用户文本消息。
    ///   - timeout: 等待本轮消息完成的秒数。
    /// - Returns: 本轮 command 对应的 Runtime Host events，包含 assistant delta 和 completed。
    /// - Throws: 进程未启动、写入失败、超时或 Runtime Host 返回 error event 时抛出错误。
    func sendMessage(sessionId: String, content: String, timeout: TimeInterval = 10) throws -> [RuntimeEvent] {
        let command = RuntimeCommand(
            id: nextCommandID(),
            name: "sendMessage",
            payload: .object([
                "sessionId": .string(sessionId),
                "message": .object([
                    "role": .string("user"),
                    "content": .string(content),
                ]),
            ])
        )
        try send(command)

        var events: [RuntimeEvent] = []
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let event = try readMatchingEvent(replyTo: command.id, deadline: deadline)
            events.append(event)
            if event.name == "messageCompleted" {
                return events
            }
        }
    }

    /// 中断并移除 Runtime Host session。
    ///
    /// - Parameters:
    ///   - sessionId: Runtime Host session id。
    ///   - timeout: 等待 sessionAborted 的秒数。
    /// - Returns: Runtime Host 返回的 `sessionAborted` event。
    /// - Throws: 进程未启动、写入失败、超时或 Runtime Host 返回 error event 时抛出错误。
    @discardableResult
    func abortSession(sessionId: String, timeout: TimeInterval = 5) throws -> RuntimeEvent {
        let command = RuntimeCommand(
            id: nextCommandID(),
            name: "abortSession",
            payload: .object(["sessionId": .string(sessionId)])
        )
        try send(command)
        let event = try readMatchingEvent(replyTo: command.id, timeout: timeout)
        guard event.name == "sessionAborted" else {
            throw RuntimeBridgeError.unexpectedEvent(name: event.name, replyTo: event.replyTo)
        }
        return event
    }

    /// 写入任意 Runtime Host command。
    ///
    /// - Parameter command: 已构造的 command envelope。
    /// - Throws: 进程未启动、command 编码失败或 stdin 写入失败时抛出错误。
    func send(_ command: RuntimeCommand) throws {
        let input = try stateQueue.sync {
            guard process?.isRunning == true, let handle = stdinPipe?.fileHandleForWriting else {
                throw RuntimeBridgeError.processNotRunning
            }
            return handle
        }

        var data: Data
        do {
            data = try encoder.encode(command)
            data.append(0x0A)
        } catch {
            throw RuntimeBridgeError.commandEncodeFailed(reason: error.localizedDescription)
        }

        do {
            try input.write(contentsOf: data)
        } catch {
            throw RuntimeBridgeError.commandWriteFailed(reason: error.localizedDescription)
        }
    }

    /// 读取下一条 Runtime Host event。
    ///
    /// - Parameter timeout: 等待 event 的秒数。
    /// - Returns: 解码后的 Runtime Host event。
    /// - Throws: 超时、stdout JSON 解码失败或进程异常退出时抛出错误。
    func readEvent(timeout: TimeInterval = 5) throws -> RuntimeEvent {
        let semaphore = stateQueue.sync {
            eventSemaphore
        }
        let waitResult = semaphore.wait(timeout: .now() + timeout)
        guard waitResult == .success else {
            throw RuntimeBridgeError.eventReadTimeout(seconds: timeout)
        }
        return try stateQueue.sync {
            guard !eventResults.isEmpty else {
                throw RuntimeBridgeError.eventReadTimeout(seconds: 0)
            }
            return try eventResults.removeFirst().get()
        }
    }

    /// 返回当前已收集的 stderr 文本。
    ///
    /// - Returns: Runtime Host stderr 日志片段。
    func stderrLog() -> String {
        stateQueue.sync {
            stderrText
        }
    }

    /// 生成递增 command id。
    ///
    /// - Returns: command id。
    private func nextCommandID() -> String {
        stateQueue.sync {
            let numberText = String(nextCommandNumber)
            let padding = String(repeating: "0", count: max(0, 3 - numberText.count))
            let id = "cmd_\(padding)\(numberText)"
            nextCommandNumber += 1
            return id
        }
    }

    /// 等待指定 command 的下一条 event。
    ///
    /// - Parameters:
    ///   - replyTo: command id。
    ///   - timeout: 总等待秒数。
    /// - Returns: 匹配 command id 的 event。
    /// - Throws: 超时、stdout 解析失败、进程退出或 Runtime Host 返回 error event 时抛出错误。
    private func readMatchingEvent(replyTo: String, timeout: TimeInterval) throws -> RuntimeEvent {
        try readMatchingEvent(replyTo: replyTo, deadline: Date().addingTimeInterval(timeout))
    }

    /// 等待指定 command 的下一条 event。
    ///
    /// - Parameters:
    ///   - replyTo: command id。
    ///   - deadline: 总等待截止时间。
    /// - Returns: 匹配 command id 的 event。
    /// - Throws: 超时、stdout 解析失败、进程退出或 Runtime Host 返回 error event 时抛出错误。
    private func readMatchingEvent(replyTo: String, deadline: Date) throws -> RuntimeEvent {
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                throw RuntimeBridgeError.eventReadTimeout(seconds: 0)
            }

            let event = try readEvent(timeout: remaining)
            if let runtimeError = runtimeError(from: event), (event.replyTo == replyTo || event.replyTo == nil) {
                throw runtimeError
            }
            if event.replyTo == replyTo {
                return event
            }
        }
    }

    /// 将 Runtime Host error event 映射为 Swift 错误。
    ///
    /// - Parameter event: Runtime Host event。
    /// - Returns: 如果 event 是 error 则返回 RuntimeBridgeError，否则返回 nil。
    private func runtimeError(from event: RuntimeEvent) -> RuntimeBridgeError? {
        guard event.name == "error", let payload = event.payload else {
            return nil
        }

        return RuntimeBridgeError.runtimeError(
            code: payload["code"]?.stringValue ?? "runtime_failed",
            message: payload["message"]?.stringValue ?? "Runtime Host error.",
            recoverable: payload["recoverable"]?.boolValue ?? true,
            details: payload["details"]
        )
    }

    /// 追加 stdout 数据并按 JSONL 解码为 event。
    ///
    /// - Parameter data: stdout pipe 读取的数据。
    private func appendStdoutData(_ data: Data, generation: UUID) {
        stateQueue.async {
            guard self.runGeneration == generation else {
                return
            }
            self.stdoutBuffer.append(data)
            while let newlineRange = self.stdoutBuffer.range(of: Data([0x0A])) {
                let lineData = self.stdoutBuffer.subdata(in: self.stdoutBuffer.startIndex..<newlineRange.lowerBound)
                self.stdoutBuffer.removeSubrange(self.stdoutBuffer.startIndex..<newlineRange.upperBound)
                guard !lineData.isEmpty else {
                    continue
                }
                let line = String(data: lineData, encoding: .utf8) ?? ""
                do {
                    let event = try self.decoder.decode(RuntimeEvent.self, from: lineData)
                    self.eventResults.append(.success(event))
                } catch {
                    self.eventResults.append(.failure(.eventDecodeFailed(line: line, reason: error.localizedDescription)))
                }
                self.eventSemaphore.signal()
            }
        }
    }

    /// 追加 stderr 日志。
    ///
    /// - Parameter data: stderr pipe 读取的数据。
    private func appendStderrData(_ data: Data, generation: UUID) {
        stateQueue.async {
            guard self.runGeneration == generation else {
                return
            }
            self.stderrText += String(data: data, encoding: .utf8) ?? ""
        }
    }

    /// 记录进程退出，并唤醒等待中的 event reader。
    ///
    /// - Parameter status: Runtime Host 退出状态码。
    private func appendProcessExited(status: Int32, generation: UUID) {
        stateQueue.async {
            guard self.runGeneration == generation else {
                return
            }
            self.eventResults.append(.failure(.processExited(status: status, stderr: self.stderrText)))
            self.eventSemaphore.signal()
        }
    }

    /// 清理 pipe 和 process handler。
    private func cleanupProcessHandlers() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
    }
}
