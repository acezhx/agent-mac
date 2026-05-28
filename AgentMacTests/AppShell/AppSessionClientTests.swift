import Testing
@testable import AgentMac

/// AppSessionClient 面向 UI 的错误提示测试。
struct AppSessionClientTests {
    /// 验证缺少内置 Runtime 资源时提示包含可执行修复方向。
    @Test func missingRuntimeResourcesUseActionableMessages() {
        let nodeMessage = AppSessionClientError(
            RuntimeBridgeError.nodeExecutableUnavailable(path: "/App/Runtime/node/bin/node")
        ).message
        let hostMessage = AppSessionClientError(
            RuntimeBridgeError.runtimeHostScriptUnavailable(path: "/App/Runtime/host/runtime-host.js")
        ).message
        let piMessage = AppSessionClientError(
            RuntimeBridgeError.piRuntimeUnavailable(path: "/App/Runtime/pi/node_modules/pi/index.js")
        ).message

        #expect(nodeMessage.contains("Node runtime is missing or is not executable"))
        #expect(nodeMessage.contains("AGENTMAC_NODE_PATH"))
        #expect(hostMessage.contains("Runtime Host is missing"))
        #expect(hostMessage.contains("runtime-host.js"))
        #expect(piMessage.contains("Pi runtime is missing"))
        #expect(piMessage.contains("scripts/update-vendored-runtime.mjs"))
    }

    /// 验证 RuntimeHost 退出和超时时提示用户查看 runtime 日志。
    @Test func runtimeStartupFailuresMentionRuntimeLog() {
        let exitMessage = AppSessionClientError(
            RuntimeBridgeError.processExited(status: 7, stderr: "runtime boom")
        ).message
        let timeoutMessage = AppSessionClientError(
            RuntimeBridgeError.eventReadTimeout(seconds: 5)
        ).message

        #expect(exitMessage.contains("Runtime Host exited before it was ready"))
        #expect(exitMessage.contains("runtime boom"))
        #expect(exitMessage.contains("runtime-host.log"))
        #expect(timeoutMessage.contains("Runtime Host did not respond within 5 seconds"))
        #expect(timeoutMessage.contains("runtime-host.log"))
    }

    /// 验证常见 Pi 配置错误会转换成用户可理解的提示。
    @Test func sessionErrorsUseCommonRuntimeGuidance() {
        let missingPiMessage = AppSessionClientError(
            SessionError.runtimeFailed(
                code: "internal_error",
                message: "RuntimeHost command failed.\nPi module entry not found.",
                recoverable: true
            )
        ).message
        let modelMessage = AppSessionClientError(
            SessionError.runtimeFailed(
                code: "model_failed",
                message: "Pi session failed to process the message.\nAPI key missing.",
                recoverable: true
            )
        ).message

        #expect(missingPiMessage.contains("Pi runtime could not be loaded"))
        #expect(missingPiMessage.contains("Runtime/pi"))
        #expect(modelMessage.contains("Pi model or authentication configuration failed"))
        #expect(modelMessage.contains("settings.json"))
        #expect(modelMessage.contains("auth.json"))
    }
}
