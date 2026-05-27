#!/usr/bin/env node

const readline = require("node:readline");

/**
 * RuntimeHost 的最小 JSONL 协议入口。
 *
 * 该类只负责 stdin/stdout 边界，不读取 Agent 配置，不接 UI，也不处理审批流程。
 */
class RuntimeHost {
  /**
   * @param {{ input: NodeJS.ReadableStream, output: NodeJS.WritableStream, error: NodeJS.WritableStream }} streams
   * RuntimeHost 使用的标准流。
   */
  constructor(streams) {
    this.input = streams.input;
    this.output = streams.output;
    this.error = streams.error;
    this.nextEventNumber = 1;
    this.nextSessionNumber = 1;
    this.sessions = new Map();
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

    this.handleCommand(command);
  }

  /**
   * 执行已校验的 command。
   *
   * @param {{ type: "command", id: string, name: string, payload?: object }} command
   * 已通过 envelope 校验的 command。
   */
  handleCommand(command) {
    switch (command.name) {
      case "ping":
        this.writeEvent({
          replyTo: command.id,
          name: "pong",
          payload: {},
        });
        break;
      case "startSession":
        this.startSession(command);
        break;
      case "sendMessage":
        this.sendMessage(command);
        break;
      case "abortSession":
        this.abortSession(command);
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
   * 创建第一阶段 mock session。
   *
   * @param {{ id: string, payload?: object }} command startSession command。
   */
  startSession(command) {
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
    this.sessions.set(sessionId, {
      id: sessionId,
      workspacePath: typeof payload.workspacePath === "string" ? payload.workspacePath : null,
    });

    this.writeEvent({
      replyTo: command.id,
      sessionId,
      name: "sessionStarted",
      payload: {},
    });
  }

  /**
   * 为 mock session 输出多段 assistant delta 和完成事件。
   *
   * @param {{ id: string, payload?: object }} command sendMessage command。
   */
  sendMessage(command) {
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

    for (const text of this.mockAssistantDeltas(message.content)) {
      this.writeEvent({
        replyTo: command.id,
        sessionId,
        name: "assistantDelta",
        payload: { text },
      });
    }

    this.writeEvent({
      replyTo: command.id,
      sessionId,
      name: "messageCompleted",
      payload: {},
    });
  }

  /**
   * 中断并移除 mock session。
   *
   * @param {{ id: string, payload?: object }} command abortSession command。
   */
  abortSession(command) {
    const payload = command.payload ?? {};
    const sessionId = typeof payload.sessionId === "string" ? payload.sessionId : null;
    if (!sessionId || !this.sessions.has(sessionId)) {
      this.writeError(command.id, "missing_session", "Session not found.", true);
      return;
    }

    this.sessions.delete(sessionId);
    this.writeEvent({
      replyTo: command.id,
      sessionId,
      name: "sessionAborted",
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
