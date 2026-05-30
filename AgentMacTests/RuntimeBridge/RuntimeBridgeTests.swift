import Foundation
import Testing
@testable import AgentMac

/// RuntimeBridge 模块的进程和 JSONL 协议测试。
///
/// 测试使用仓库内 RuntimeHost 脚本和 vendored Node，不依赖 UI，也不接真实模型凭据。
struct RuntimeBridgeTests {
    /// 验证 Swift 可以启动 Runtime Host 并完成 ping/pong 往返。
    @Test func pingRoundTripsThroughRuntimeHost() throws {
        let (bridge, root) = try makeBridge()
        defer {
            bridge.stop()
            removeTemporaryRoot(root)
        }

        try bridge.start()
        let event = try bridge.ping()

        #expect(event.name == "pong")
        #expect(event.replyTo == "cmd_001")
    }

    /// 验证测试宿主 app bundle 内的 Runtime 结构可被 RuntimeBridge 定位并启动。
    @Test func bundledRuntimeFromAppBundleStartsWithoutDevelopmentMode() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let configuration = try RuntimeBridgeConfiguration.bundled(
            bundle: .main,
            workingDirectoryURL: root,
            environment: [
                "AGENTMAC_RUNTIMEHOST_USE_MOCK_PI": "1",
                "AGENTMAC_PI_AGENT_DIR": root.appending(path: "Pi", directoryHint: .isDirectory).path,
            ]
        )

        #expect(configuration.nodeExecutableURL.path.contains("AgentMac.app/Contents/Resources/Runtime/node/bin/node"))
        #expect(configuration.runtimeHostScriptURL.path.contains("AgentMac.app/Contents/Resources/Runtime/host/runtime-host.js"))
        #expect(configuration.workingDirectoryURL == root.standardizedFileURL)
        try configuration.validate()

        let piModulesURL = configuration.runtimeHostScriptURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "pi/node_modules/@earendil-works", directoryHint: .isDirectory)
        #expect(FileManager.default.fileExists(atPath: piModulesURL.path))

        let bridge = RuntimeBridge(configuration: configuration)
        defer { bridge.stop() }

        try bridge.start()
        let event = try bridge.ping()
        let sessionId = try bridge.startSession(workspacePath: root.path)

        #expect(event.name == "pong")
        #expect(sessionId == "ses_001")
    }

    /// 验证配置校验会在 Swift 侧提前报告缺失的 Pi runtime。
    @Test func configurationValidationReportsMissingPiRuntime() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let missingPiEntry = root.appending(path: "missing-pi/dist/index.js", directoryHint: .notDirectory)
        let configuration = RuntimeBridgeConfiguration(
            nodeExecutableURL: try vendoredNodeURL(),
            runtimeHostScriptURL: repoRoot.appending(path: "AgentMac/RuntimeHost/runtime-host.js", directoryHint: .notDirectory),
            piModuleEntryURL: missingPiEntry,
            workingDirectoryURL: root
        )

        do {
            try configuration.validate()
            Issue.record("Expected missing Pi runtime to be rejected.")
        } catch let RuntimeBridgeError.piRuntimeUnavailable(path) {
            #expect(path == missingPiEntry.standardizedFileURL.path)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证 RuntimeBridge 能通过 mock RuntimeHost 跑通 session、消息流和 abort。
    @Test func fixedCodingAgentMockSessionStreamsAndAborts() throws {
        let (bridge, root) = try makeBridge()
        defer {
            bridge.stop()
            removeTemporaryRoot(root)
        }

        try bridge.start()
        let sessionId = try bridge.startSession(workspacePath: root.path)
        let events = try bridge.sendMessage(sessionId: sessionId, content: "你好")
        let assistantText = events
            .filter { $0.name == "assistantDelta" }
            .compactMap { $0.payload?["text"]?.stringValue }
            .joined()
        let aborted = try bridge.abortSession(sessionId: sessionId)

        #expect(sessionId == "ses_001")
        #expect(assistantText == "RuntimeHost mock 已收到：你好。")
        #expect(events.last?.name == "messageCompleted")
        #expect(aborted.name == "sessionAborted")
    }

    /// 验证 RuntimeBridge 可以发送 cancelTurn 并读取 turnCancelled event。
    @Test func cancelTurnRoundTripsThroughRuntimeHost() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let script = root.appending(path: "cancel-turn.js", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        const readline = require('node:readline');
        const rl = readline.createInterface({ input: process.stdin });
        rl.on('line', (line) => {
          const command = JSON.parse(line);
          if (command.name === 'cancelTurn' && command.payload.sessionId === 'ses_001') {
            process.stdout.write(JSON.stringify({
              type: 'event',
              id: 'evt_cancelled',
              replyTo: command.id,
              sessionId: 'ses_001',
              name: 'turnCancelled',
              payload: { cancelled: true }
            }) + '\\n');
          }
        });
        setInterval(() => {}, 10000);
        """.write(to: script, atomically: true, encoding: .utf8)

        let bridge = RuntimeBridge(configuration: try makeConfiguration(root: root, hostScriptURL: script))
        defer { bridge.stop() }

        try bridge.start()
        let event = try bridge.cancelTurn(sessionId: "ses_001")

        #expect(event.name == "turnCancelled")
        #expect(event.sessionId == "ses_001")
        #expect(event.payload?["cancelled"]?.boolValue == true)
    }

    /// 验证 sendMessage 和 cancelTurn 并发写入 Runtime Host stdin 时仍保持完整 JSONL。
    @Test func concurrentSendMessageAndCancelTurnWriteValidJSONLines() async throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let script = root.appending(path: "concurrent-send-cancel.js", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        const readline = require('node:readline');
        const rl = readline.createInterface({ input: process.stdin });
        let activeReplyTo = null;
        let eventNumber = 1;

        function writeEvent(replyTo, name, payload) {
          process.stdout.write(JSON.stringify({
            type: 'event',
            id: `evt_${eventNumber++}`,
            replyTo,
            sessionId: 'ses_001',
            name,
            payload,
          }) + '\\n');
        }

        rl.on('line', (line) => {
          let command;
          try {
            command = JSON.parse(line);
          } catch (error) {
            process.stdout.write(JSON.stringify({
              type: 'event',
              id: `evt_${eventNumber++}`,
              replyTo: null,
              name: 'error',
              payload: {
                code: 'invalid_json',
                message: error.message,
                recoverable: true,
              },
            }) + '\\n');
            return;
          }

          if (command.name === 'sendMessage') {
            activeReplyTo = command.id;
            setTimeout(() => {
              if (activeReplyTo === command.id) {
                writeEvent(command.id, 'messageCompleted', {});
                activeReplyTo = null;
              }
            }, 250);
          } else if (command.name === 'cancelTurn') {
            if (activeReplyTo) {
              writeEvent(activeReplyTo, 'turnCancelled', { cancelled: true });
              activeReplyTo = null;
            }
            writeEvent(command.id, 'turnCancelled', { cancelled: true });
          }
        });
        setInterval(() => {}, 10000);
        """.write(to: script, atomically: true, encoding: .utf8)

        let bridge = RuntimeBridge(configuration: try makeConfiguration(root: root, hostScriptURL: script))
        defer { bridge.stop() }

        try bridge.start()
        let largeContent = String(repeating: "x", count: 1_000_000)
        let sendTask = Task.detached {
            try bridge.sendMessage(sessionId: "ses_001", content: largeContent, timeout: 5)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        let cancelEvent = try bridge.cancelTurn(sessionId: "ses_001", timeout: 5)
        let sendEvents = try await sendTask.value

        #expect(cancelEvent.name == "turnCancelled")
        #expect(cancelEvent.payload?["cancelled"]?.boolValue == true)
        #expect(sendEvents.last?.name == "turnCancelled")
    }

    /// 验证 RuntimeBridge 会把默认 coding agent 的显式 skill paths 编码到 fixedCodingAgent payload。
    @Test func fixedCodingAgentStartEncodesSelectedSkills() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let script = root.appending(path: "validate-fixed-agent.js", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let skillPath = root.appending(path: "library/skills/coding", directoryHint: .isDirectory).path
        try """
        const readline = require('node:readline');
        const rl = readline.createInterface({ input: process.stdin });
        rl.on('line', (line) => {
          const command = JSON.parse(line);
          const agent = command.payload.agent;
          const valid = agent.mode === 'fixedCodingAgent'
            && agent.skillPaths.length === 1
            && agent.skillPaths[0] === '\(skillPath)';
          process.stdout.write(JSON.stringify({
            type: 'event',
            id: 'evt_001',
            replyTo: command.id,
            sessionId: valid ? 'ses_001' : undefined,
            name: valid ? 'sessionStarted' : 'error',
            payload: valid ? {} : { code: 'invalid_test_payload', message: JSON.stringify(command.payload), recoverable: true }
          }) + '\\n');
        });
        setInterval(() => {}, 10000);
        """.write(to: script, atomically: true, encoding: .utf8)

        let bridge = RuntimeBridge(configuration: try makeConfiguration(root: root, hostScriptURL: script))
        defer { bridge.stop() }

        try bridge.start()
        let sessionId = try bridge.startSession(agentConfig: ResolvedAgentConfig(
            runtimeMode: .fixedCodingAgent,
            id: "coding-agent",
            name: "Pi Coding Agent",
            model: .default,
            systemPromptPath: "",
            knowledgePaths: [],
            skillPaths: [skillPath],
            toolPaths: [],
            permissions: .default,
            workspacePath: root.path
        ))

        #expect(sessionId == "ses_001")
    }

    /// 验证 RuntimeBridge 会把自定义 Agent 编码为 resolved payload。
    @Test func resolvedAgentStartEncodesResolvedPayload() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let script = root.appending(path: "validate-resolved-agent.js", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let systemPromptPath = root.appending(path: "agents/support/system.md", directoryHint: .notDirectory).path
        let knowledgePath = root.appending(path: "library/knowledge/refund.md", directoryHint: .notDirectory).path
        let skillPath = root.appending(path: "library/skills/support", directoryHint: .isDirectory).path
        try """
        const readline = require('node:readline');
        const rl = readline.createInterface({ input: process.stdin });
        rl.on('line', (line) => {
          const command = JSON.parse(line);
          const agent = command.payload.agent;
          const valid = agent.mode === 'resolved'
            && agent.id === 'support-agent'
            && agent.model.provider === 'deepseek'
            && agent.model.name === 'deepseek-v4-flash'
            && agent.systemPromptPath === '\(systemPromptPath)'
            && agent.knowledgePaths[0] === '\(knowledgePath)'
            && agent.skillPaths[0] === '\(skillPath)'
            && agent.permissions.bash === 'deny'
            && command.payload.workspacePath === '\(root.path)';
          process.stdout.write(JSON.stringify({
            type: 'event',
            id: 'evt_001',
            replyTo: command.id,
            sessionId: valid ? 'ses_001' : undefined,
            name: valid ? 'sessionStarted' : 'error',
            payload: valid ? {} : { code: 'invalid_test_payload', message: JSON.stringify(command.payload), recoverable: true }
          }) + '\\n');
        });
        setInterval(() => {}, 10000);
        """.write(to: script, atomically: true, encoding: .utf8)

        let bridge = RuntimeBridge(configuration: try makeConfiguration(root: root, hostScriptURL: script))
        defer { bridge.stop() }

        try bridge.start()
        let sessionId = try bridge.startSession(agentConfig: ResolvedAgentConfig(
            id: "support-agent",
            name: "Support",
            model: ModelConfig(provider: "deepseek", name: "deepseek-v4-flash"),
            systemPromptPath: systemPromptPath,
            knowledgePaths: [knowledgePath],
            skillPaths: [skillPath],
            toolPaths: [],
            permissions: PermissionConfig(bash: .deny, edit: .ask, network: .allow),
            workspacePath: root.path
        ))

        #expect(sessionId == "ses_001")
    }

    /// 验证 RuntimeBridge 可以读取 Runtime Host 模型清单事件。
    @Test func modelCatalogRoundTripsThroughRuntimeHost() throws {
        let (bridge, root) = try makeBridge()
        defer {
            bridge.stop()
            removeTemporaryRoot(root)
        }

        try bridge.start()
        let event = try bridge.listModelCatalog(providerIDs: ["deepseek"])

        #expect(event.name == "modelCatalogListed")
        guard case let .array(models)? = event.payload?["models"],
              case let .object(model)? = models.first
        else {
            Issue.record("Expected model catalog payload.")
            return
        }
        #expect(model["providerID"]?.stringValue == "deepseek")
        #expect(model["id"]?.stringValue == "deepseek-v4-flash")
    }

    /// 验证 RuntimeBridge 能把工具审批决策回传 Runtime Host，并让当前消息完成。
    @Test func approveToolCallRoundTripsThroughRuntimeHost() throws {
        let (bridge, root) = try makeBridge(environment: ["AGENTMAC_RUNTIMEHOST_MOCK_TOOL_APPROVAL": "1"])
        defer {
            bridge.stop()
            removeTemporaryRoot(root)
        }

        try bridge.start()
        let sessionId = try bridge.startSession(workspacePath: root.path)
        let events = try bridge.sendMessage(
            sessionId: sessionId,
            content: "ls -la",
            onEvent: { event in
                if event.name == "toolApprovalRequested" {
                    let toolCallID = try #require(event.payload?["toolCallId"]?.stringValue)
                    let approvalEvent = try bridge.approveToolCall(
                        sessionId: sessionId,
                        toolCallID: toolCallID,
                        decision: .allowed(reason: "Approved in test.")
                    )
                    #expect(approvalEvent.name == "toolApprovalResolved")
                    #expect(approvalEvent.payload?["decision"]?.stringValue == "approved")
                }
            }
        )

        #expect(events.map(\.name).contains("toolApprovalRequested"))
        #expect(events.last?.name == "messageCompleted")
    }

    /// 验证嵌套 approveToolCall 读到外层 sendMessage event 时不会丢弃外层 event。
    @Test func nestedApprovalPreservesOuterSendEvents() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let script = root.appending(path: "nested-approval-events.js", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        const readline = require('node:readline');
        const rl = readline.createInterface({ input: process.stdin });
        let nextEventNumber = 1;
        let activeSendReplyTo = null;

        function writeEvent(replyTo, sessionId, name, payload = {}) {
          process.stdout.write(JSON.stringify({
            type: 'event',
            id: `evt_${String(nextEventNumber++).padStart(3, '0')}`,
            replyTo,
            sessionId,
            name,
            payload
          }) + '\\n');
        }

        rl.on('line', (line) => {
          const command = JSON.parse(line);
          if (command.name === 'startSession') {
            writeEvent(command.id, 'ses_001', 'sessionStarted', {});
          } else if (command.name === 'sendMessage') {
            activeSendReplyTo = command.id;
            writeEvent(command.id, 'ses_001', 'toolApprovalRequested', {
              toolCallId: 'tool_001',
              toolName: 'bash',
              risk: 'shell',
              summary: 'Run shell command'
            });
          } else if (command.name === 'approveToolCall') {
            writeEvent(activeSendReplyTo, 'ses_001', 'assistantDelta', { text: 'after approval' });
            writeEvent(activeSendReplyTo, 'ses_001', 'messageCompleted', {});
            writeEvent(command.id, 'ses_001', 'toolApprovalResolved', {
              toolCallId: 'tool_001',
              decision: command.payload.decision
            });
          }
        });

        setInterval(() => {}, 10000);
        """.write(to: script, atomically: true, encoding: .utf8)

        let bridge = RuntimeBridge(configuration: try makeConfiguration(root: root, hostScriptURL: script))
        defer { bridge.stop() }

        try bridge.start()
        let sessionId = try bridge.startSession(workspacePath: root.path)
        let events = try bridge.sendMessage(
            sessionId: sessionId,
            content: "ls -la",
            onEvent: { event in
                if event.name == "toolApprovalRequested" {
                    _ = try bridge.approveToolCall(
                        sessionId: sessionId,
                        toolCallID: "tool_001",
                        decision: .allowed(reason: "Approved in test.")
                    )
                }
            }
        )

        #expect(events.map(\.name) == ["toolApprovalRequested", "assistantDelta", "messageCompleted"])
        #expect(events[1].payload?["text"]?.stringValue == "after approval")
    }

    /// 验证等待用户审批的时间不会消耗外层 sendMessage 的 Runtime Host event 等待时间。
    @Test func approvalWaitTimeDoesNotConsumeSendMessageTimeout() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let script = root.appending(path: "approval-wait-time.js", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        const readline = require('node:readline');
        const rl = readline.createInterface({ input: process.stdin });
        let nextEventNumber = 1;
        let activeSendReplyTo = null;

        function writeEvent(replyTo, sessionId, name, payload = {}) {
          process.stdout.write(JSON.stringify({
            type: 'event',
            id: `evt_${String(nextEventNumber++).padStart(3, '0')}`,
            replyTo,
            sessionId,
            name,
            payload
          }) + '\\n');
        }

        rl.on('line', (line) => {
          const command = JSON.parse(line);
          if (command.name === 'startSession') {
            writeEvent(command.id, 'ses_001', 'sessionStarted', {});
          } else if (command.name === 'sendMessage') {
            activeSendReplyTo = command.id;
            writeEvent(command.id, 'ses_001', 'toolApprovalRequested', {
              toolCallId: 'tool_001',
              toolName: 'bash',
              risk: 'shell',
              summary: 'Run shell command'
            });
          } else if (command.name === 'approveToolCall') {
            writeEvent(command.id, 'ses_001', 'toolApprovalResolved', {
              toolCallId: 'tool_001',
              decision: command.payload.decision
            });
            setTimeout(() => {
              writeEvent(activeSendReplyTo, 'ses_001', 'assistantDelta', { text: 'after approval' });
              writeEvent(activeSendReplyTo, 'ses_001', 'messageCompleted', {});
            }, 50);
          }
        });

        setInterval(() => {}, 10000);
        """.write(to: script, atomically: true, encoding: .utf8)

        let bridge = RuntimeBridge(configuration: try makeConfiguration(root: root, hostScriptURL: script))
        defer { bridge.stop() }

        try bridge.start()
        let sessionId = try bridge.startSession(workspacePath: root.path)
        let events = try bridge.sendMessage(
            sessionId: sessionId,
            content: "ls -la",
            timeout: 0.2,
            onEvent: { event in
                if event.name == "toolApprovalRequested" {
                    Thread.sleep(forTimeInterval: 0.3)
                    _ = try bridge.approveToolCall(
                        sessionId: sessionId,
                        toolCallID: "tool_001",
                        decision: .allowed(reason: "Approved in test."),
                        timeout: 1
                    )
                }
            }
        )

        #expect(events.map(\.name) == ["toolApprovalRequested", "assistantDelta", "messageCompleted"])
    }

    /// 验证 runtimeActivity 可作为 Runtime Host 仍在工作的心跳，避免工具阶段被误判为空闲超时。
    @Test func runtimeActivityExtendsSendMessageIdleTimeout() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let script = root.appending(path: "runtime-activity-timeout.js", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        const readline = require('node:readline');
        const rl = readline.createInterface({ input: process.stdin });
        let nextEventNumber = 1;

        function writeEvent(replyTo, sessionId, name, payload = {}) {
          process.stdout.write(JSON.stringify({
            type: 'event',
            id: `evt_${String(nextEventNumber++).padStart(3, '0')}`,
            replyTo,
            sessionId,
            name,
            payload
          }) + '\\n');
        }

        rl.on('line', (line) => {
          const command = JSON.parse(line);
          if (command.name === 'startSession') {
            writeEvent(command.id, 'ses_001', 'sessionStarted', {});
          } else if (command.name === 'sendMessage') {
            writeEvent(command.id, 'ses_001', 'runtimeActivity', { piEventType: 'tool_execution_start' });
            setTimeout(() => {
              writeEvent(command.id, 'ses_001', 'runtimeActivity', { piEventType: 'tool_execution_update' });
            }, 100);
            setTimeout(() => {
              writeEvent(command.id, 'ses_001', 'assistantDelta', { text: 'done' });
              writeEvent(command.id, 'ses_001', 'messageCompleted', {});
            }, 250);
          }
        });

        setInterval(() => {}, 10000);
        """.write(to: script, atomically: true, encoding: .utf8)

        let bridge = RuntimeBridge(configuration: try makeConfiguration(root: root, hostScriptURL: script))
        defer { bridge.stop() }

        try bridge.start()
        let sessionId = try bridge.startSession(workspacePath: root.path)
        let events = try bridge.sendMessage(
            sessionId: sessionId,
            content: "long running tool",
            timeout: 0.2
        )

        #expect(events.map(\.name) == [
            "runtimeActivity",
            "runtimeActivity",
            "assistantDelta",
            "messageCompleted",
        ])
    }

    /// 验证 stdout 中的非法 JSONL event 会被映射为结构化解析错误。
    @Test func invalidRuntimeEventJSONReportsDecodeError() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let script = root.appending(path: "invalid-event.js", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "process.stdout.write('not json\\n');\n".write(to: script, atomically: true, encoding: .utf8)

        let bridge = RuntimeBridge(configuration: try makeConfiguration(root: root, hostScriptURL: script))
        defer { bridge.stop() }

        try bridge.start()
        do {
            _ = try bridge.readEvent()
            Issue.record("Expected invalid JSON event to be rejected.")
        } catch let RuntimeBridgeError.eventDecodeFailed(line, _) {
            #expect(line == "not json")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证 Runtime Host 异常退出时会带出退出码和 stderr 日志。
    @Test func processExitReportsStatusAndStderr() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let script = root.appending(path: "exit.js", directoryHint: .notDirectory)
        let logFile = root.appending(path: "logs/runtime-host.log", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "console.error('runtime boom'); process.exit(7);\n".write(to: script, atomically: true, encoding: .utf8)

        let bridge = RuntimeBridge(
            configuration: try makeConfiguration(root: root, hostScriptURL: script, stderrLogFileURL: logFile)
        )
        defer { bridge.stop() }

        try bridge.start()
        do {
            _ = try bridge.readEvent()
            Issue.record("Expected process exit to be reported.")
        } catch let RuntimeBridgeError.processExited(status, stderr) {
            #expect(status == 7)
            #expect(stderr.contains("runtime boom"))
            #expect(bridge.stderrLog().contains("runtime boom"))
            #expect(try String(contentsOf: logFile, encoding: .utf8).contains("runtime boom"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证 stop 会隔离上一轮未读取 event，避免重启后消费过期 signal。
    @Test func stopClearsUnconsumedEventsBeforeRestart() throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let script = root.appending(path: "one-shot-event.js", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        const fs = require('node:fs');
        const path = require('node:path');
        const marker = path.join(process.cwd(), 'already-sent');
        if (!fs.existsSync(marker)) {
          fs.writeFileSync(marker, '1');
          process.stdout.write(JSON.stringify({
            type: 'event',
            id: 'evt_old',
            replyTo: 'cmd_old',
            name: 'old',
            payload: {}
          }) + '\\n');
        }
        setTimeout(() => {}, 10000);
        """.write(to: script, atomically: true, encoding: .utf8)

        let bridge = RuntimeBridge(configuration: try makeConfiguration(root: root, hostScriptURL: script))
        defer { bridge.stop() }

        try bridge.start()
        Thread.sleep(forTimeInterval: 1.0)
        bridge.stop()

        try bridge.start()
        do {
            _ = try bridge.readEvent(timeout: 0.2)
            Issue.record("Expected restarted bridge to ignore the previous run's unconsumed event.")
        } catch RuntimeBridgeError.eventReadTimeout {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证 Runtime Host error event 会映射为 RuntimeBridgeError.runtimeError。
    @Test func runtimeErrorEventMapsToBridgeError() throws {
        let (bridge, root) = try makeBridge()
        defer {
            bridge.stop()
            removeTemporaryRoot(root)
        }

        try bridge.start()
        do {
            _ = try bridge.sendMessage(sessionId: "missing-session", content: "hello")
            Issue.record("Expected runtime error event to throw.")
        } catch let RuntimeBridgeError.runtimeError(code, message, recoverable, _) {
            #expect(code == "missing_session")
            #expect(message.contains("Session not found"))
            #expect(recoverable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 创建指向仓库 RuntimeHost 的测试 RuntimeBridge。
    ///
    /// - Returns: RuntimeBridge 和测试结束后需要删除的临时根目录。
    private func makeBridge(environment: [String: String] = [:]) throws -> (RuntimeBridge, URL) {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configuration = try makeConfiguration(
            root: root,
            hostScriptURL: repoRoot.appending(path: "AgentMac/RuntimeHost/runtime-host.js", directoryHint: .notDirectory),
            environment: [
                "AGENTMAC_RUNTIMEHOST_USE_MOCK_PI": "1",
                "AGENTMAC_PI_AGENT_DIR": root.appending(path: "Pi", directoryHint: .isDirectory).path,
            ].merging(environment) { _, new in new }
        )
        return (RuntimeBridge(configuration: configuration), root)
    }

    /// 创建测试 RuntimeBridge 配置。
    ///
    /// - Parameters:
    ///   - root: Runtime Host 工作目录。
    ///   - hostScriptURL: Runtime Host 脚本路径。
    ///   - environment: 额外环境变量。
    /// - Returns: RuntimeBridge 配置。
    private func makeConfiguration(
        root: URL,
        hostScriptURL: URL,
        environment: [String: String] = [:],
        stderrLogFileURL: URL? = nil
    ) throws -> RuntimeBridgeConfiguration {
        RuntimeBridgeConfiguration(
            nodeExecutableURL: try vendoredNodeURL(),
            runtimeHostScriptURL: hostScriptURL,
            workingDirectoryURL: root,
            environment: environment,
            stderrLogFileURL: stderrLogFileURL
        )
    }

    /// 仓库根目录。
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// vendored Node 路径。
    ///
    /// - Returns: 可执行 Node URL。
    /// - Throws: 本地 runtime 尚未准备好时抛出测试错误。
    private func vendoredNodeURL() throws -> URL {
        let url = repoRoot.appending(path: "Vendor/Runtime/darwin-arm64/node/bin/node", directoryHint: .notDirectory)
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw RuntimeBridgeTestError.missingVendoredNode(path: url.path)
        }
        return url
    }

    /// 创建测试临时目录 URL。
    ///
    /// - Returns: 尚未创建的临时目录 URL。
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "AgentMac-RuntimeBridgeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// 删除测试创建的临时根目录。
    ///
    /// - Parameter root: 待删除目录。
    private func removeTemporaryRoot(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }
}

/// RuntimeBridge 测试环境错误。
private enum RuntimeBridgeTestError: Error {
    /// 本地 vendored Node 不存在。
    case missingVendoredNode(path: String)
}
