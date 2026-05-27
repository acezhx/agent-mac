import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const runtimeHostPath = fileURLToPath(new URL("./runtime-host.js", import.meta.url));

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

function startRuntimeHost(t) {
  const child = spawn(process.execPath, [runtimeHostPath], {
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
        }, 1000);
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
