#!/usr/bin/env node

const readline = require("node:readline");
const { existsSync } = require("node:fs");
const { mkdir } = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const { pathToFileURL } = require("node:url");

const PI_MODULE_RELATIVE_PATH = path.join(
  "pi",
  "node_modules",
  "@earendil-works",
  "pi-coding-agent",
  "dist",
  "index.js",
);
const PI_BUILTIN_TOOL_NAMES = Object.freeze(["read", "bash", "edit", "write"]);
const TOOL_DETAIL_PREVIEW_LIMIT = 1000;

/**
 * RuntimeHost 的 JSONL 协议入口。
 *
 * 该类只负责 stdin/stdout 边界，不读取 Agent 配置，不接 UI，也不执行工具。
 */
class RuntimeHost {
  /**
   * @param {{ input: NodeJS.ReadableStream, output: NodeJS.WritableStream, error: NodeJS.WritableStream }} streams
   * RuntimeHost 使用的标准流。
   * @param {{ runtimeMode?: "pi"|"mock" }} [options] 运行模式；测试可显式使用 mock。
   */
  constructor(streams, options = {}) {
    this.input = streams.input;
    this.output = streams.output;
    this.error = streams.error;
    this.runtimeMode = options.runtimeMode ?? (process.env.AGENTMAC_RUNTIMEHOST_USE_MOCK_PI === "1" ? "mock" : "pi");
    this.nextEventNumber = 1;
    this.nextSessionNumber = 1;
    this.nextToolCallNumber = 1;
    this.sessions = new Map();
    this.piRuntime = null;
    this.commandQueue = Promise.resolve();
    this.mockToolApprovalEnabled = process.env.AGENTMAC_RUNTIMEHOST_MOCK_TOOL_APPROVAL === "1";
  }

  /**
   * 启动 JSONL reader，并在 stdin 关闭时允许进程自然退出。
   */
  start() {
    const reader = readline.createInterface({
      input: this.input,
      crlfDelay: Infinity,
      terminal: false,
    });

    reader.on("line", (line) => {
      this.handleLine(line);
    });

    reader.on("close", () => {
      this.log("RuntimeHost input closed.");
    });
  }

  /**
   * 处理一行 JSONL command。
   *
   * @param {string} line stdin 中的一行输入。
   */
  handleLine(line) {
    if (line.trim().length === 0) {
      return;
    }

    let command;
    try {
      command = JSON.parse(line);
    } catch (parseError) {
      this.writeError(null, "invalid_json", "Invalid JSON command.", true, {
        reason: parseError.message,
      });
      return;
    }

    const validationError = this.validateCommand(command);
    if (validationError) {
      this.writeError(command && command.id, "invalid_command", validationError, true);
      return;
    }

    if (command.name === "approveToolCall") {
      void this.handleCommand(command).catch((error) => {
        this.writeError(command.id, "internal_error", "RuntimeHost command failed.", true, {
          reason: formatErrorMessage(error),
        });
      });
      return;
    }

    this.commandQueue = this.commandQueue.then(async () => {
      try {
        await this.handleCommand(command);
      } catch (error) {
        this.writeError(command.id, "internal_error", "RuntimeHost command failed.", true, {
          reason: formatErrorMessage(error),
        });
      }
    });
  }

  /**
   * 执行已校验的 command。
   *
   * @param {{ type: "command", id: string, name: string, payload?: object }} command
   * 已通过 envelope 校验的 command。
   */
  async handleCommand(command) {
    switch (command.name) {
      case "ping":
        this.writeEvent({
          replyTo: command.id,
          name: "pong",
          payload: {},
        });
        break;
      case "startSession":
        await this.startSession(command);
        break;
      case "sendMessage":
        await this.sendMessage(command);
        break;
      case "abortSession":
        await this.abortSession(command);
        break;
      case "approveToolCall":
        await this.approveToolCall(command);
        break;
      default:
        this.writeError(
          command.id,
          "unsupported_command",
          `Unsupported command: ${command.name}`,
          true,
        );
    }
  }

  /**
   * 创建固定 Pi coding agent session。
   *
   * @param {{ id: string, payload?: object }} command startSession command。
   */
  async startSession(command) {
    const payload = command.payload ?? {};
    const agent = payload.agent;
    if (!isPlainObject(agent) || agent.mode !== "fixedCodingAgent") {
      this.writeError(
        command.id,
        "invalid_command",
        'startSession requires payload.agent.mode to be "fixedCodingAgent".',
        true,
      );
      return;
    }

    const sessionId = this.nextSessionId();
    const workspacePath = typeof payload.workspacePath === "string" ? payload.workspacePath : null;
    const session = this.runtimeMode === "mock"
      ? this.createMockSession(sessionId, workspacePath)
      : await this.createPiSession(sessionId, workspacePath);

    this.sessions.set(sessionId, session);

    this.writeEvent({
      replyTo: command.id,
      sessionId,
      name: "sessionStarted",
      payload: {},
    });
  }

  /**
   * 向 session 发送用户消息，并转发 RuntimeHost 稳定事件。
   *
   * @param {{ id: string, payload?: object }} command sendMessage command。
   */
  async sendMessage(command) {
    const payload = command.payload ?? {};
    const sessionId = typeof payload.sessionId === "string" ? payload.sessionId : null;
    if (!sessionId || !this.sessions.has(sessionId)) {
      this.writeError(command.id, "missing_session", "Session not found.", true);
      return;
    }

    const message = payload.message;
    if (
      !isPlainObject(message)
      || message.role !== "user"
      || typeof message.content !== "string"
    ) {
      this.writeError(
        command.id,
        "invalid_command",
        "sendMessage requires payload.message with user role and string content.",
        true,
      );
      return;
    }

    const session = this.sessions.get(sessionId);
    if (session.kind === "mock") {
      await this.sendMockMessage(command.id, session, message.content);
      return;
    }

    if (session.activeReplyTo) {
      this.writeError(command.id, "runtime_failed", "Session is already processing a message.", true);
      return;
    }

    session.activeReplyTo = command.id;
    session.completed = false;
    session.seenTextDelta = false;
    try {
      await session.piSession.sendUserMessage(message.content);
      if (!session.completed) {
        this.writeEvent({
          replyTo: command.id,
          sessionId,
          name: "messageCompleted",
          payload: {},
        });
        session.completed = true;
      }
    } catch (error) {
      if (!session.completed) {
        this.writeError(
          command.id,
          classifyPiError(error),
          "Pi session failed to process the message.",
          true,
          { reason: formatErrorMessage(error) },
        );
      }
    } finally {
      session.activeReplyTo = null;
    }
  }

  /**
   * 中断并移除 session。
   *
   * @param {{ id: string, payload?: object }} command abortSession command。
   */
  async abortSession(command) {
    const payload = command.payload ?? {};
    const sessionId = typeof payload.sessionId === "string" ? payload.sessionId : null;
    if (!sessionId || !this.sessions.has(sessionId)) {
      this.writeError(command.id, "missing_session", "Session not found.", true);
      return;
    }

    const session = this.sessions.get(sessionId);
    if (session.kind === "pi") {
      try {
        await session.piSession.abort();
      } catch (error) {
        this.log(`Pi session abort failed: ${formatErrorMessage(error)}`);
      } finally {
        try {
          this.rejectPendingToolApprovals(session, "Runtime session was aborted.");
          this.disposePiSession(session);
        } finally {
          this.sessions.delete(sessionId);
        }
      }
    } else {
      this.rejectPendingToolApprovals(session, "Runtime session was aborted.");
      this.sessions.delete(sessionId);
    }

    this.writeEvent({
      replyTo: command.id,
      sessionId,
      name: "sessionAborted",
      payload: {},
    });
  }

  /**
   * 创建测试用 mock session。
   *
   * @param {string} sessionId RuntimeHost session id。
   * @param {string|null} workspacePath 工作目录。
   * @returns {object} mock session。
   */
  createMockSession(sessionId, workspacePath) {
    return {
      kind: "mock",
      id: sessionId,
      workspacePath,
      pendingToolApprovals: new Map(),
    };
  }

  /**
   * 创建 Pi SDK session，并启用 AgentMac 支持审批的 Pi 内建工具。
   *
   * @param {string} sessionId RuntimeHost session id。
   * @param {string|null} workspacePath 工作目录。
   * @returns {Promise<object>} RuntimeHost 内部 session 状态。
   */
  async createPiSession(sessionId, workspacePath) {
    const piRuntime = await this.loadPiRuntime();
    const cwd = workspacePath ?? process.cwd();
    const agentDir = process.env.AGENTMAC_PI_AGENT_DIR
      ?? path.join(os.homedir(), "Library", "Application Support", "AgentMac", "Pi");
    await mkdir(agentDir, { recursive: true });

    const testFaux = await this.createTestFauxRuntime(piRuntime);
    const settingsManager = piRuntime.module.SettingsManager.create(cwd, agentDir);
    const resourceLoader = new piRuntime.module.DefaultResourceLoader({
      cwd,
      agentDir,
      settingsManager,
      extensionFactories: [this.createToolApprovalExtensionFactory(sessionId)],
      noExtensions: true,
      noSkills: true,
      noPromptTemplates: true,
      noThemes: true,
      noContextFiles: true,
    });
    await resourceLoader.reload();

    const createOptions = {
      cwd,
      agentDir,
      tools: PI_BUILTIN_TOOL_NAMES,
      settingsManager,
      resourceLoader,
      sessionManager: piRuntime.module.SessionManager.inMemory(cwd),
    };

    if (testFaux) {
      createOptions.authStorage = testFaux.authStorage;
      createOptions.modelRegistry = testFaux.modelRegistry;
      createOptions.model = testFaux.model;
    }

    let result;
    try {
      result = await piRuntime.module.createAgentSession(createOptions);
    } catch (error) {
      if (testFaux?.registration && typeof testFaux.registration.unregister === "function") {
        testFaux.registration.unregister();
      }
      throw error;
    }
    const session = {
      kind: "pi",
      id: sessionId,
      workspacePath,
      piSession: result.session,
      unsubscribe: null,
      testFauxRegistration: testFaux?.registration ?? null,
      activeReplyTo: null,
      completed: false,
      seenTextDelta: false,
      pendingToolApprovals: new Map(),
    };
    session.unsubscribe = result.session.subscribe((event) => {
      this.handlePiEvent(session, event);
    });
    return session;
  }

  /**
   * 创建内联 Pi extension factory，用于在工具执行前等待 Swift 侧审批。
   *
   * @param {string} sessionId RuntimeHost session id。
   * @returns {Function} Pi extension factory。
   */
  createToolApprovalExtensionFactory(sessionId) {
    return (pi) => {
      pi.on("tool_call", async (event) => this.handlePiToolCallApproval(sessionId, event));
    };
  }

  /**
   * 处理 Pi tool_call hook，并将拒绝决策转成 Pi 可理解的 block 结果。
   *
   * @param {string} sessionId RuntimeHost session id。
   * @param {object} event Pi tool_call event。
   * @returns {Promise<object|undefined>} Pi tool_call handler 结果。
   */
  async handlePiToolCallApproval(sessionId, event) {
    const session = this.sessions.get(sessionId);
    if (!session || !session.activeReplyTo) {
      return {
        block: true,
        reason: "Runtime session is not ready for tool approval.",
      };
    }

    const request = this.toolApprovalRequestFromEvent(event);
    const decision = await this.waitForToolApproval(session, session.activeReplyTo, request);
    if (decision.decision === "approved") {
      return undefined;
    }

    return {
      block: true,
      reason: decision.reason || "Tool execution denied.",
    };
  }

  /**
   * 按需加载 Pi SDK 入口。
   *
   * @returns {Promise<{ module: object, entryPath: string }>} Pi SDK 模块和入口路径。
   */
  async loadPiRuntime() {
    if (this.piRuntime) {
      return this.piRuntime;
    }

    const entryPath = resolvePiModuleEntryPath(__dirname);
    const module = await import(pathToFileURL(entryPath).href);
    for (const exportName of ["createAgentSession", "DefaultResourceLoader", "SessionManager", "SettingsManager"]) {
      if (typeof module[exportName] !== "function") {
        throw new Error(`Pi SDK export missing: ${exportName}`);
      }
    }

    this.piRuntime = { module, entryPath };
    return this.piRuntime;
  }

  /**
   * 创建仅供自动化测试使用的 faux provider。
   *
   * @param {{ module: object, entryPath: string }} piRuntime Pi SDK runtime。
   * @returns {Promise<object|null>} faux provider 状态；未启用时返回 null。
   */
  async createTestFauxRuntime(piRuntime) {
    const response = process.env.AGENTMAC_RUNTIMEHOST_TEST_FAUX_RESPONSE;
    if (response === undefined) {
      return null;
    }

    const fauxPath = resolvePiFauxProviderEntryPath(piRuntime.entryPath);
    const faux = await import(pathToFileURL(fauxPath).href);
    const registration = faux.registerFauxProvider({
      api: "agentmac-runtimehost-faux",
      provider: "agentmac-runtimehost-faux",
      tokensPerSecond: 0,
      tokenSize: { min: 1, max: 1 },
    });
    registration.setResponses([faux.fauxAssistantMessage(response)]);

    const model = registration.getModel();
    const authStorage = piRuntime.module.AuthStorage.inMemory();
    authStorage.setRuntimeApiKey(model.provider, "agentmac-runtimehost-test-key");
    const modelRegistry = piRuntime.module.ModelRegistry.inMemory(authStorage);
    return {
      registration,
      authStorage,
      modelRegistry,
      model,
    };
  }

  /**
   * 处理 Pi session event，并映射为 RuntimeHost 稳定事件。
   *
   * @param {object} session RuntimeHost 内部 session 状态。
   * @param {object} event Pi AgentSession event。
   */
  handlePiEvent(session, event) {
    if (!isPlainObject(event)) {
      return;
    }

    if (event.type === "message_update") {
      this.forwardPiMessageUpdate(session, event);
    } else if (event.type === "message_end") {
      this.forwardPiMessageEnd(session, event);
    } else if (String(event.type).startsWith("tool_execution_")) {
      this.forwardPiActivity(session, event);
    }
  }

  /**
   * 转发 Pi assistant text delta。
   *
   * @param {object} session RuntimeHost 内部 session 状态。
   * @param {object} event Pi message_update event。
   */
  forwardPiMessageUpdate(session, event) {
    const replyTo = session.activeReplyTo;
    if (!replyTo || !isPlainObject(event.assistantMessageEvent)) {
      return;
    }

    const assistantEvent = event.assistantMessageEvent;
    if (assistantEvent.type === "text_delta" && typeof assistantEvent.delta === "string") {
      session.seenTextDelta = true;
      this.writeEvent({
        replyTo,
        sessionId: session.id,
        name: "assistantDelta",
        payload: { text: assistantEvent.delta },
      });
    } else if (String(assistantEvent.type).startsWith("toolcall_")) {
      this.forwardPiActivity(session, event);
    }
  }

  /**
   * 转发 Pi 非文本进度事件，避免 Swift 侧在工具调用或工具执行期间误判 RuntimeHost 空闲超时。
   *
   * @param {object} session RuntimeHost 内部 session 状态。
   * @param {object} event Pi event。
   */
  forwardPiActivity(session, event) {
    const replyTo = session.activeReplyTo;
    if (!replyTo) {
      return;
    }

    this.writeEvent({
      replyTo,
      sessionId: session.id,
      name: "runtimeActivity",
      payload: piActivityPayload(event),
    });
  }

  /**
   * 处理 Pi assistant message 结束事件。
   *
   * @param {object} session RuntimeHost 内部 session 状态。
   * @param {object} event Pi message_end event。
   */
  forwardPiMessageEnd(session, event) {
    if (!session.activeReplyTo || !isPlainObject(event.message) || event.message.role !== "assistant") {
      return;
    }

    if (!session.seenTextDelta) {
      const text = extractAssistantText(event.message);
      if (text.length > 0) {
        this.writeEvent({
          replyTo: session.activeReplyTo,
          sessionId: session.id,
          name: "assistantDelta",
          payload: { text },
        });
      }
    }

    if (event.message.stopReason === "error") {
      this.writeError(
        session.activeReplyTo,
        "model_failed",
        "Pi model returned an error.",
        true,
        event.message.errorMessage ? { reason: event.message.errorMessage } : undefined,
      );
      session.completed = true;
    }
  }

  /**
   * 从 Pi tool_call event 生成 RuntimeHost 稳定审批请求。
   *
   * @param {object} event Pi tool_call event。
   * @returns {object} toolApprovalRequested payload。
   */
  toolApprovalRequestFromEvent(event) {
    const toolName = typeof event.toolName === "string" ? event.toolName : "tool";
    const input = isPlainObject(event.input) ? event.input : {};
    return {
      toolCallId: typeof event.toolCallId === "string" && event.toolCallId.length > 0
        ? event.toolCallId
        : this.nextToolCallId(),
      toolName,
      risk: toolApprovalRiskForTool(toolName),
      summary: toolApprovalSummaryForTool(toolName),
      details: toolApprovalDetailsForTool(toolName, input),
    };
  }

  /**
   * 释放 Pi session 相关资源。
   *
   * @param {object} session RuntimeHost 内部 session 状态。
   */
  disposePiSession(session) {
    if (typeof session.unsubscribe === "function") {
      session.unsubscribe();
    }
    if (typeof session.piSession.dispose === "function") {
      session.piSession.dispose();
    }
    if (session.testFauxRegistration && typeof session.testFauxRegistration.unregister === "function") {
      session.testFauxRegistration.unregister();
    }
  }

  /**
   * 处理 Swift 返回的工具审批决策。
   *
   * @param {{ id: string, payload?: object }} command approveToolCall command。
   */
  async approveToolCall(command) {
    const payload = command.payload ?? {};
    const sessionId = typeof payload.sessionId === "string" ? payload.sessionId : null;
    const toolCallId = typeof payload.toolCallId === "string" ? payload.toolCallId : null;
    const decision = typeof payload.decision === "string" ? payload.decision : null;
    const reason = typeof payload.reason === "string" ? payload.reason : "";

    if (!sessionId || !this.sessions.has(sessionId)) {
      this.writeError(command.id, "missing_session", "Session not found.", true);
      return;
    }
    if (!toolCallId || !["approved", "denied"].includes(decision)) {
      this.writeError(
        command.id,
        "invalid_command",
        "approveToolCall requires toolCallId and an approved or denied decision.",
        true,
      );
      return;
    }

    const session = this.sessions.get(sessionId);
    const pending = session.pendingToolApprovals?.get(toolCallId);
    if (!pending) {
      this.writeError(command.id, "missing_tool_approval", "Tool approval request not found.", true);
      return;
    }

    session.pendingToolApprovals.delete(toolCallId);
    this.writeEvent({
      replyTo: command.id,
      sessionId,
      name: "toolApprovalResolved",
      payload: {
        toolCallId,
        decision,
      },
    });
    pending.resolve({ decision, reason });
  }

  /**
   * 发出工具审批请求并等待 approveToolCall command。
   *
   * @param {object} session RuntimeHost 内部 session 状态。
   * @param {string} replyTo 当前 sendMessage command id。
   * @param {object} request toolApprovalRequested payload。
   * @returns {Promise<object>} 审批决策。
   */
  waitForToolApproval(session, replyTo, request) {
    const pending = new Promise((resolve) => {
      session.pendingToolApprovals.set(request.toolCallId, { resolve });
    });

    this.writeEvent({
      replyTo,
      sessionId: session.id,
      name: "toolApprovalRequested",
      payload: request,
    });

    return pending;
  }

  /**
   * 取消 session 中仍在等待的审批请求。
   *
   * @param {object} session RuntimeHost 内部 session 状态。
   * @param {string} reason 取消原因。
   */
  rejectPendingToolApprovals(session, reason) {
    for (const [toolCallId, pending] of session.pendingToolApprovals ?? []) {
      pending.resolve({ decision: "denied", reason });
      session.pendingToolApprovals.delete(toolCallId);
    }
  }

  /**
   * 为 mock session 输出多段 assistant delta 和完成事件。
   *
   * @param {string} replyTo command id。
   * @param {object} session RuntimeHost 内部 mock session。
   * @param {string} content 用户消息。
   */
  async sendMockMessage(replyTo, session, content) {
    if (this.mockToolApprovalEnabled) {
      await this.waitForToolApproval(session, replyTo, {
        toolCallId: this.nextToolCallId(),
        toolName: "bash",
        risk: "shell",
        summary: "Run shell command",
        details: {
          command: content,
        },
      });
    }

    for (const text of this.mockAssistantDeltas(content)) {
      this.writeEvent({
        replyTo,
        sessionId: session.id,
        name: "assistantDelta",
        payload: { text },
      });
    }

    this.writeEvent({
      replyTo,
      sessionId: session.id,
      name: "messageCompleted",
      payload: {},
    });
  }

  /**
   * 校验 command envelope。
   *
   * @param {unknown} command 待校验的 JSON object。
   * @returns {string|null} 校验失败原因，成功时返回 null。
   */
  validateCommand(command) {
    if (!isPlainObject(command)) {
      return "Command must be a JSON object.";
    }
    if (command.type !== "command") {
      return 'Command field "type" must be "command".';
    }
    if (typeof command.id !== "string" || command.id.length === 0) {
      return 'Command field "id" must be a non-empty string.';
    }
    if (typeof command.name !== "string" || command.name.length === 0) {
      return 'Command field "name" must be a non-empty string.';
    }
    if (
      command.payload !== undefined
      && (!isPlainObject(command.payload))
    ) {
      return 'Command field "payload" must be an object when provided.';
    }
    return null;
  }

  /**
   * 输出一个 RuntimeHost event envelope。
   *
   * @param {{ replyTo?: string|null, sessionId?: string, name: string, payload?: object }} event
   * 事件内容。
   */
  writeEvent(event) {
    const envelope = {
      type: "event",
      id: this.nextEventId(),
      name: event.name,
    };

    if (event.replyTo !== undefined) {
      envelope.replyTo = event.replyTo;
    }
    if (event.sessionId !== undefined) {
      envelope.sessionId = event.sessionId;
    }
    if (event.payload !== undefined) {
      envelope.payload = event.payload;
    }

    this.output.write(`${JSON.stringify(envelope)}\n`);
  }

  /**
   * 输出统一错误事件。
   *
   * @param {string|null|undefined} replyTo 对应 command id。
   * @param {string} code 机器可读错误码。
   * @param {string} message 人类可读错误信息。
   * @param {boolean} recoverable 当前 RuntimeHost 是否可继续使用。
   * @param {object|undefined} details 诊断详情。
   */
  writeError(replyTo, code, message, recoverable, details) {
    this.writeEvent({
      replyTo: replyTo ?? null,
      name: "error",
      payload: {
        code,
        message,
        recoverable,
        ...(details ? { details } : {}),
      },
    });
  }

  /**
   * 生成稳定递增的 event id。
   *
   * @returns {string} event id。
   */
  nextEventId() {
    const id = `evt_${String(this.nextEventNumber).padStart(3, "0")}`;
    this.nextEventNumber += 1;
    return id;
  }

  /**
   * 生成稳定递增的 session id。
   *
   * @returns {string} session id。
   */
  nextSessionId() {
    const id = `ses_${String(this.nextSessionNumber).padStart(3, "0")}`;
    this.nextSessionNumber += 1;
    return id;
  }

  /**
   * 生成稳定递增的 tool call id。
   *
   * @returns {string} tool call id。
   */
  nextToolCallId() {
    const id = `tool_${String(this.nextToolCallNumber).padStart(3, "0")}`;
    this.nextToolCallNumber += 1;
    return id;
  }

  /**
   * 构造第一阶段 mock assistant 输出。
   *
   * @param {string} userText 用户消息。
   * @returns {string[]} 流式输出片段。
   */
  mockAssistantDeltas(userText) {
    const normalizedText = userText.trim();
    const subject = normalizedText.length > 0 ? normalizedText : "这条消息";
    return [
      "RuntimeHost mock 已收到：",
      subject,
      "。",
    ];
  }

  /**
   * 写入 stderr 诊断日志，避免污染 stdout JSONL。
   *
   * @param {string} message 诊断信息。
   */
  log(message) {
    this.error.write(`[runtime-host] ${message}\n`);
  }
}

/**
 * 判断值是否为普通 JSON object。
 *
 * @param {unknown} value 待判断的值。
 * @returns {boolean} 是否为普通 object。
 */
function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * 定位 Pi coding-agent 入口。
 *
 * @param {string} hostDir RuntimeHost 文件所在目录。
 * @returns {string} Pi SDK 入口文件绝对路径。
 */
function resolvePiModuleEntryPath(hostDir) {
  const override = process.env.AGENTMAC_PI_MODULE_ENTRY;
  if (override) {
    const resolvedOverride = path.resolve(override);
    if (existsSync(resolvedOverride)) {
      return resolvedOverride;
    }
    throw new Error(`Pi module entry not found: ${resolvedOverride}`);
  }

  const candidates = [
    path.resolve(hostDir, "..", PI_MODULE_RELATIVE_PATH),
    path.resolve(hostDir, "..", "..", "Vendor", "Runtime", "darwin-arm64", PI_MODULE_RELATIVE_PATH),
  ];
  const found = candidates.find((candidate) => existsSync(candidate));
  if (!found) {
    throw new Error(`Pi module entry not found. Checked: ${candidates.join(", ")}`);
  }
  return found;
}

/**
 * 定位 Pi faux provider 入口，仅供 RuntimeHost 自动化测试使用。
 *
 * @param {string} piEntryPath Pi coding-agent 入口路径。
 * @returns {string} faux provider 入口文件绝对路径。
 */
function resolvePiFauxProviderEntryPath(piEntryPath) {
  const nodeModulesRoot = path.resolve(
    piEntryPath,
    "..",
    "..",
    "..",
    "..",
  );
  const candidate = path.join(
    nodeModulesRoot,
    "@earendil-works",
    "pi-ai",
    "dist",
    "providers",
    "faux.js",
  );
  if (!existsSync(candidate)) {
    throw new Error(`Pi faux provider entry not found: ${candidate}`);
  }
  return candidate;
}

/**
 * 生成 RuntimeHost 进度事件 payload，只暴露小字段，避免把工具参数或结果塞进协议。
 *
 * @param {object} event Pi event。
 * @returns {object} runtimeActivity payload。
 */
function piActivityPayload(event) {
  const payload = {
    piEventType: typeof event.type === "string" ? event.type : "unknown",
  };
  if (isPlainObject(event.assistantMessageEvent)) {
    payload.assistantEventType = typeof event.assistantMessageEvent.type === "string"
      ? event.assistantMessageEvent.type
      : "unknown";
  }
  addStringDetail(payload, "toolCallId", event.toolCallId);
  addStringDetail(payload, "toolName", event.toolName);
  return payload;
}

/**
 * 将 Pi 工具名称映射为 AgentMac 稳定审批风险类型。
 *
 * @param {string} toolName Pi tool name。
 * @returns {"shell"|"edit"|"write"|"network"|"unknown"} RuntimeHost 稳定风险类型。
 */
function toolApprovalRiskForTool(toolName) {
  switch (toolName) {
    case "bash":
      return "shell";
    case "read":
    case "edit":
      return "edit";
    case "write":
      return "write";
    default:
      return "unknown";
  }
}

/**
 * 生成工具审批摘要。
 *
 * @param {string} toolName Pi tool name。
 * @returns {string} 可展示摘要。
 */
function toolApprovalSummaryForTool(toolName) {
  switch (toolName) {
    case "bash":
      return "Run shell command";
    case "read":
      return "Read file";
    case "edit":
      return "Edit file";
    case "write":
      return "Write file";
    default:
      return `Run ${toolName}`;
  }
}

/**
 * 生成工具审批详情，避免把完整文件内容直接塞进审批事件。
 *
 * @param {string} toolName Pi tool name。
 * @param {object} input 已校验的工具参数。
 * @returns {object} RuntimeHost details payload。
 */
function toolApprovalDetailsForTool(toolName, input) {
  const details = {};
  addStringDetail(details, "command", input.command);
  addStringDetail(details, "path", input.path ?? input.file_path);
  addNumberDetail(details, "timeout", input.timeout);
  addNumberDetail(details, "offset", input.offset);
  addNumberDetail(details, "limit", input.limit);

  if (toolName === "write" && typeof input.content === "string") {
    details.contentLength = input.content.length;
    details.contentPreview = previewToolDetail(input.content);
  }

  if (toolName === "edit") {
    const edits = Array.isArray(input.edits) ? input.edits.filter(isPlainObject) : [];
    if (edits.length > 0) {
      details.editCount = edits.length;
      addStringDetail(details, "firstOldTextPreview", previewToolDetail(edits[0].oldText));
      addStringDetail(details, "firstNewTextPreview", previewToolDetail(edits[0].newText));
    } else {
      addStringDetail(details, "oldTextPreview", previewToolDetail(input.oldText));
      addStringDetail(details, "newTextPreview", previewToolDetail(input.newText));
    }
  }

  return details;
}

/**
 * 向详情对象添加字符串字段。
 *
 * @param {object} details 详情对象。
 * @param {string} key 字段名。
 * @param {unknown} value 值。
 */
function addStringDetail(details, key, value) {
  if (typeof value === "string" && value.length > 0) {
    details[key] = value;
  }
}

/**
 * 向详情对象添加数字字段。
 *
 * @param {object} details 详情对象。
 * @param {string} key 字段名。
 * @param {unknown} value 值。
 */
function addNumberDetail(details, key, value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    details[key] = value;
  }
}

/**
 * 截断工具详情中的大块文本。
 *
 * @param {unknown} value 原始值。
 * @returns {string|undefined} 截断后的字符串。
 */
function previewToolDetail(value) {
  if (typeof value !== "string") {
    return undefined;
  }
  if (value.length <= TOOL_DETAIL_PREVIEW_LIMIT) {
    return value;
  }
  return `${value.slice(0, TOOL_DETAIL_PREVIEW_LIMIT)}...`;
}

/**
 * 提取 assistant message 中的文本 block。
 *
 * @param {object} message Pi assistant message。
 * @returns {string} 拼接后的文本。
 */
function extractAssistantText(message) {
  if (!Array.isArray(message.content)) {
    return "";
  }
  return message.content
    .filter((block) => isPlainObject(block) && block.type === "text" && typeof block.text === "string")
    .map((block) => block.text)
    .join("");
}

/**
 * 将未知错误转为可写入 JSON 的 message。
 *
 * @param {unknown} error 未知错误。
 * @returns {string} 错误信息。
 */
function formatErrorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

/**
 * 将 Pi 异常映射为 RuntimeHost 协议错误码。
 *
 * @param {unknown} error Pi 异常。
 * @returns {string} RuntimeHost 错误码。
 */
function classifyPiError(error) {
  const message = formatErrorMessage(error);
  if (/api key|auth|credential|model|provider/i.test(message)) {
    return "model_failed";
  }
  return "runtime_failed";
}

if (require.main === module) {
  const host = new RuntimeHost({
    input: process.stdin,
    output: process.stdout,
    error: process.stderr,
  });
  host.start();
}

module.exports = {
  RuntimeHost,
  isPlainObject,
};
