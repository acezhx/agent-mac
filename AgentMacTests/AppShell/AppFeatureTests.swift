import ComposableArchitecture
import Testing
@testable import AgentMac

/// AppShell 根 Feature 的启动初始化测试。
@MainActor
struct AppFeatureTests {
    /// 验证根视图进入时会初始化本地数据目录，且成功后不会重复初始化。
    @Test func taskInitializesAppDataOnce() async {
        let recorder = StartupRecorder()
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.appStartupClient = AppStartupClient(
                initializeAppData: {
                    recorder.initializeCount += 1
                }
            )
        }

        await store.send(.task)
        await store.receive(.appDataInitializationSucceeded) {
            $0.hasInitializedAppData = true
            $0.startupErrorMessage = nil
        }
        await store.send(.task)

        #expect(recorder.initializeCount == 1)
        await store.finish()
    }

    /// 验证启动初始化失败时会保存面向 UI 的错误信息。
    @Test func startupFailureStoresErrorMessage() async {
        let error = AppStartupClientError("startup failed")
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.appStartupClient = AppStartupClient(
                initializeAppData: {
                    throw error
                }
            )
        }

        await store.send(.task)
        await store.receive(.appDataInitializationFailed(error)) {
            $0.hasInitializedAppData = false
            $0.startupErrorMessage = "startup failed"
        }
        await store.finish()
    }
}

/// `@Sendable` mock closure 中记录启动初始化调用次数的容器。
private final class StartupRecorder: @unchecked Sendable {
    /// 初始化调用次数。
    var initializeCount = 0
}
