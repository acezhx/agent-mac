import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { existsSync } from "node:fs";
import { mkdtemp } from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const require = createRequire(import.meta.url);
const { RuntimeHost } = require("./runtime-host.js");
const runtimeHostPath = fileURLToPath(new URL("./runtime-host.js", import.meta.url));
const vendorNodePath = fileURLToPath(new URL("../../Vendor/Runtime/darwin-arm64/node/bin/node", import.meta.url));
const vendorPiEntryPath = fileURLToPath(new URL(
  "../../Vendor/Runtime/darwin-arm64/pi/node_modules/@earendil-works/pi-coding-agent/dist/index.js",
  import.meta.url,
));

test("ping command returns pong event", async (t) => {
  const host = startRuntimeHost(t);

  host.writeCommand({ type: "command", id: "cmd_001", name: "ping", payload: {} });

  assert.deepEqual(await host.readEvent(), {
    type: "event",
    id: "evt_001",
    replyTo: "cmd_001",
    name: "pong",
    payload: {},
  });
});

test("invalid JSON returns recoverable protocol error and keeps process alive", async (t) => {
  const host = startRuntimeHost(t);

  host.writeLine("{not json");
  host.writeCommand({ type: "command", id: "cmd_002", name: "ping", payload: {} });

  const errorEvent = await host.readEvent();
  assert.equal(errorEvent.type, "event");
  assert.equal(errorEvent.name, "error");
  assert.equal(errorEvent.replyTo, null);
  assert.equal(errorEvent.payload.code, "invalid_json");
  assert.equal(errorEvent.payload.recoverable, true);

  assert.deepEqual(await host.readEvent(), {
    type: "event",
    id: "evt_002",
    replyTo: "cmd_002",
    name: "pong",
    payload: {},
  });
});

test("unknown command returns unsupported command error", async (t) => {
  const host = startRuntimeHost(t);

  host.writeCommand({ type: "command", id: "cmd_003", name: "unknown", payload: {} });

  const event = await host.readEvent();
  assert.equal(event.type, "event");
  assert.equal(event.replyTo, "cmd_003");
  assert.equal(event.name, "error");
  assert.equal(event.payload.code, "unsupported_command");
  assert.equal(event.payload.recoverable, true);
});

test("fixed coding agent session starts and streams mock message", async (t) => {
  const host = startRuntimeHost(t);

  host.writeCommand({
    type: "command",
    id: "cmd_004",
    name: "startSession",
    payload: {
      agent: { mode: "fixedCodingAgent" },
      workspacePath: "/tmp/agentmac-runtimehost-test",
    },
  });

  assert.deepEqual(await host.readEvent(), {
    type: "event",
    id: "evt_001",
    replyTo: "cmd_004",
    sessionId: "ses_001",
    name: "sessionStarted",
    payload: {},
  });

  host.writeCommand({
    type: "command",
    id: "cmd_005",
    name: "sendMessage",
    payload: {
      sessionId: "ses_001",
      message: {
        role: "user",
        content: "你好",
      },
    },
  });

  assert.deepEqual(await host.readEvent(), {
    type: "event",
    id: "evt_002",
    replyTo: "cmd_005",
    sessionId: "ses_001",
    name: "assistantDelta",
    payload: { text: "RuntimeHost mock 已收到：" },
  });
  assert.deepEqual(await host.readEvent(), {
    type: "event",
    id: "evt_003",
    replyTo: "cmd_005",
    sessionId: "ses_001",
    name: "assistantDelta",
    payload: { text: "你好" },
  });
  assert.deepEqual(await host.readEvent(), {
    type: "event",
    id: "evt_004",
    replyTo: "cmd_005",
    sessionId: "ses_001",
    name: "assistantDelta",
    payload: { text: "。" },
  });
  assert.deepEqual(await host.readEvent(), {
    type: "event",
    id: "evt_005",
    replyTo: "cmd_005",
    sessionId: "ses_001",
    name: "messageCompleted",
    payload: {},
  });
});

test("sendMessage requires an existing session", async (t) => {
  const host = startRuntimeHost(t);

  host.writeCommand({
    type: "command",
    id: "cmd_006",
    name: "sendMessage",
    payload: {
      sessionId: "ses_missing",
      message: {
        role: "user",
        content: "你好",
      },
    },
  });

  const event = await host.readEvent();
  assert.equal(event.type, "event");
  assert.equal(event.replyTo, "cmd_006");
  assert.equal(event.name, "error");
  assert.equal(event.payload.code, "missing_session");
  assert.equal(event.payload.recoverable, true);
});

test("abortSession removes mock session", async (t) => {
  const host = startRuntimeHost(t);

  host.writeCommand({
    type: "command",
    id: "cmd_007",
    name: "startSession",
    payload: {
      agent: { mode: "fixedCodingAgent" },
    },
  });
  assert.equal((await host.readEvent()).name, "sessionStarted");

  host.writeCommand({
    type: "command",
    id: "cmd_008",
    name: "abortSession",
    payload: {
      sessionId: "ses_001",
    },
  });

  assert.deepEqual(await host.readEvent(), {
    type: "event",
    id: "evt_002",
    replyTo: "cmd_008",
    sessionId: "ses_001",
    name: "sessionAborted",
    payload: {},
  });

  host.writeCommand({
    type: "command",
    id: "cmd_009",
    name: "sendMessage",
    payload: {
      sessionId: "ses_001",
      message: {
        role: "user",
        content: "still there?",
      },
    },
  });

  const event = await host.readEvent();
  assert.equal(event.type, "event");
  assert.equal(event.replyTo, "cmd_009");
  assert.equal(event.name, "error");
  assert.equal(event.payload.code, "missing_session");
});

test("approveToolCall resolves a pending mock tool approval", async (t) => {
  const host = startRuntimeHost(t, {
    env: {
      AGENTMAC_RUNTIMEHOST_MOCK_TOOL_APPROVAL: "1",
    },
  });

  host.writeCommand({
    type: "command",
    id: "cmd_approval_start",
    name: "startSession",
    payload: {
      agent: { mode: "fixedCodingAgent" },
    },
  });
  assert.equal((await host.readEvent()).name, "sessionStarted");

  host.writeCommand({
    type: "command",
    id: "cmd_approval_send",
    name: "sendMessage",
    payload: {
      sessionId: "ses_001",
      message: {
        role: "user",
        content: "ls -la",
      },
    },
  });

  const request = await host.readEvent();
  assert.equal(request.name, "toolApprovalRequested");
  assert.equal(request.replyTo, "cmd_approval_send");
  assert.equal(request.sessionId, "ses_001");
  assert.equal(request.payload.toolCallId, "tool_001");
  assert.equal(request.payload.toolName, "bash");
  assert.equal(request.payload.risk, "shell");

  host.writeCommand({
    type: "command",
    id: "cmd_approval_decide",
    name: "approveToolCall",
    payload: {
      sessionId: "ses_001",
      toolCallId: "tool_001",
      decision: "approved",
      reason: "Approved in test.",
    },
  });

  assert.deepEqual(await host.readEvent(), {
    type: "event",
    id: "evt_003",
    replyTo: "cmd_approval_decide",
    sessionId: "ses_001",
    name: "toolApprovalResolved",
    payload: {
      toolCallId: "tool_001",
      decision: "approved",
    },
  });

  let completed = false;
  while (!completed) {
    const event = await host.readEvent();
    assert.equal(event.replyTo, "cmd_approval_send");
    completed = event.name === "messageCompleted";
  }
});

test("approveToolCall rejects missing pending approval", async (t) => {
  const host = startRuntimeHost(t);

  host.writeCommand({
    type: "command",
    id: "cmd_approval_missing_start",
    name: "startSession",
    payload: {
      agent: { mode: "fixedCodingAgent" },
    },
  });
  assert.equal((await host.readEvent()).name, "sessionStarted");

  host.writeCommand({
    type: "command",
    id: "cmd_approval_missing",
    name: "approveToolCall",
    payload: {
      sessionId: "ses_001",
      toolCallId: "tool_missing",
      decision: "denied",
      reason: "No request.",
    },
  });

  const event = await host.readEvent();
  assert.equal(event.type, "event");
  assert.equal(event.replyTo, "cmd_approval_missing");
  assert.equal(event.name, "error");
  assert.equal(event.payload.code, "missing_tool_approval");
});

test("abortSession removes pi session even when Pi abort throws", async () => {
  const events = [];
  let disposed = false;
  const host = new RuntimeHost({
    input: {},
    output: {
      write(line) {
        events.push(JSON.parse(line));
      },
    },
    error: {
      write() {},
    },
  });
  host.sessions.set("ses_001", {
    kind: "pi",
    id: "ses_001",
    piSession: {
      async abort() {
        throw new Error("abort boom");
      },
      dispose() {
        disposed = true;
      },
    },
    unsubscribe() {},
    testFauxRegistration: null,
  });

  await host.abortSession({
    id: "cmd_abort",
    payload: {
      sessionId: "ses_001",
    },
  });

  assert.equal(host.sessions.has("ses_001"), false);
  assert.equal(disposed, true);
  assert.equal(events.at(-1).replyTo, "cmd_abort");
  assert.equal(events.at(-1).sessionId, "ses_001");
  assert.equal(events.at(-1).name, "sessionAborted");
});

test("fixed coding agent streams through Pi SDK faux provider", {
  skip: realPiRuntimeSkipReason(),
}, async (t) => {
  const tempDir = await mkdtemp(join(tmpdir(), "agentmac-runtimehost-pi-"));
  const host = startRuntimeHost(t, {
    nodePath: vendorNodePath,
    useMockPi: false,
    env: {
      AGENTMAC_PI_AGENT_DIR: join(tempDir, "agent"),
      AGENTMAC_PI_MODULE_ENTRY: vendorPiEntryPath,
      AGENTMAC_RUNTIMEHOST_TEST_FAUX_RESPONSE: "pong from pi sdk",
    },
  });

  host.writeCommand({
    type: "command",
    id: "cmd_010",
    name: "startSession",
    payload: {
      agent: { mode: "fixedCodingAgent" },
      workspacePath: tempDir,
    },
  });

  assert.deepEqual(await host.readEvent(), {
    type: "event",
    id: "evt_001",
    replyTo: "cmd_010",
    sessionId: "ses_001",
    name: "sessionStarted",
    payload: {},
  });

  host.writeCommand({
    type: "command",
    id: "cmd_011",
    name: "sendMessage",
    payload: {
      sessionId: "ses_001",
      message: {
        role: "user",
        content: "ping",
      },
    },
  });

  let assistantText = "";
  for (;;) {
    const event = await host.readEvent();
    assert.equal(event.type, "event");
    assert.equal(event.replyTo, "cmd_011");
    assert.equal(event.sessionId, "ses_001");
    if (event.name === "assistantDelta") {
      assistantText += event.payload.text;
    } else if (event.name === "messageCompleted") {
      break;
    } else {
      assert.fail(`Unexpected event: ${JSON.stringify(event)}`);
    }
  }

  assert.equal(assistantText, "pong from pi sdk");
});

test("fixed coding agent processes queued commands in input order", {
  skip: realPiRuntimeSkipReason(),
}, async (t) => {
  const tempDir = await mkdtemp(join(tmpdir(), "agentmac-runtimehost-pi-order-"));
  const host = startRuntimeHost(t, {
    nodePath: vendorNodePath,
    useMockPi: false,
    env: {
      AGENTMAC_PI_AGENT_DIR: join(tempDir, "agent"),
      AGENTMAC_PI_MODULE_ENTRY: vendorPiEntryPath,
      AGENTMAC_RUNTIMEHOST_TEST_FAUX_RESPONSE: "ordered response",
    },
  });

  host.writeCommand({
    type: "command",
    id: "cmd_start",
    name: "startSession",
    payload: {
      agent: { mode: "fixedCodingAgent" },
      workspacePath: tempDir,
    },
  });
  host.writeCommand({
    type: "command",
    id: "cmd_send",
    name: "sendMessage",
    payload: {
      sessionId: "ses_001",
      message: {
        role: "user",
        content: "ping",
      },
    },
  });

  const started = await host.readEvent();
  assert.equal(started.name, "sessionStarted");
  assert.equal(started.replyTo, "cmd_start");

  let assistantText = "";
  for (;;) {
    const event = await host.readEvent();
    assert.equal(event.replyTo, "cmd_send");
    if (event.name === "assistantDelta") {
      assistantText += event.payload.text;
    } else if (event.name === "messageCompleted") {
      break;
    } else {
      assert.fail(`Unexpected event: ${JSON.stringify(event)}`);
    }
  }

  assert.equal(assistantText, "ordered response");
});

function startRuntimeHost(t, options = {}) {
  const env = { ...process.env, ...options.env };
  if (options.useMockPi === false) {
    delete env.AGENTMAC_RUNTIMEHOST_USE_MOCK_PI;
  } else {
    env.AGENTMAC_RUNTIMEHOST_USE_MOCK_PI = "1";
  }

  const child = spawn(options.nodePath ?? process.execPath, [runtimeHostPath], {
    env,
    stdio: ["pipe", "pipe", "pipe"],
  });
  const events = [];
  const waiters = [];
  const stderr = [];
  let stdoutBuffer = "";
  let settledExit = false;

  child.stdout.setEncoding("utf8");
  child.stdout.on("data", (chunk) => {
    stdoutBuffer += chunk;
    let newlineIndex = stdoutBuffer.indexOf("\n");
    while (newlineIndex >= 0) {
      const line = stdoutBuffer.slice(0, newlineIndex);
      stdoutBuffer = stdoutBuffer.slice(newlineIndex + 1);
      if (line.length > 0) {
        pushEvent(JSON.parse(line));
      }
      newlineIndex = stdoutBuffer.indexOf("\n");
    }
  });

  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk) => {
    stderr.push(chunk);
  });

  child.on("exit", () => {
    settledExit = true;
  });

  t.after(async () => {
    child.stdin.end();
    if (!settledExit) {
      await once(child, "exit");
    }
  });

  return {
    writeLine(line) {
      child.stdin.write(`${line}\n`);
    },
    writeCommand(command) {
      child.stdin.write(`${JSON.stringify(command)}\n`);
    },
    readEvent() {
      if (events.length > 0) {
        return Promise.resolve(events.shift());
      }

      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error(`Timed out waiting for RuntimeHost event. stderr=${stderr.join("")}`));
        }, 5000);
        waiters.push((event) => {
          clearTimeout(timeout);
          resolve(event);
        });
      });
    },
  };

  function pushEvent(event) {
    const waiter = waiters.shift();
    if (waiter) {
      waiter(event);
    } else {
      events.push(event);
    }
  }
}

function realPiRuntimeSkipReason() {
  if (!existsSync(vendorNodePath)) {
    return "vendored Node runtime is not installed";
  }
  if (!existsSync(vendorPiEntryPath)) {
    return "vendored Pi runtime is not installed";
  }
  return false;
}
