import ComposableArchitecture
import Foundation

/// AppShell 独立窗口标识。
nonisolated enum AppWindowID: String, Hashable {
    /// Agent 管理窗口。
    case agentLibrary = "agent-library"

    /// Resource 管理窗口。
    case resourceLibrary = "resource-library"

    /// Settings 窗口。
    case settings = "settings"

    /// 窗口标题。
    var title: String {
        switch self {
        case .agentLibrary:
            "Agent Library"
        case .resourceLibrary:
            "Resource Library"
        case .settings:
            "Settings"
        }
    }

    /// 窗口图标名称。
    var systemImage: String {
        switch self {
        case .agentLibrary:
            "person.crop.circle"
        case .resourceLibrary:
            "folder"
        case .settings:
            "gearshape"
        }
    }
}

/// AgentMac 根 Feature。
@Reducer
struct AppFeature {
    /// AppShell 根状态。
    @ObservableState
    struct State: Equatable {
        /// 首次启动数据目录是否已完成初始化。
        var hasInitializedAppData = false

        /// 首次启动初始化失败时展示的错误信息。
        var startupErrorMessage: String?

        /// 当前会话页面状态。
        var session = SessionFeature.State()
    }

    /// AppShell 根 action。
    enum Action: Equatable {
        /// 根视图进入时触发首次启动初始化。
        case task

        /// 首次启动数据目录初始化成功。
        case appDataInitializationSucceeded

        /// 首次启动数据目录初始化失败。
        case appDataInitializationFailed(AppStartupClientError)

        /// 会话页面 action。
        case session(SessionFeature.Action)
    }

    /// 根 reducer 组合。
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                guard !state.hasInitializedAppData else {
                    return .none
                }
                return initializeAppDataEffect()

            case .appDataInitializationSucceeded:
                state.hasInitializedAppData = true
                state.startupErrorMessage = nil
                return .none

            case let .appDataInitializationFailed(error):
                state.hasInitializedAppData = false
                state.startupErrorMessage = error.message
                return .none

            case .session:
                return .none
            }
        }

        Scope(state: \.session, action: \.session) {
            SessionFeature()
        }
    }

    private func initializeAppDataEffect() -> Effect<Action> {
        @Dependency(AppStartupClient.self) var appStartupClient
        return .run { send in
            do {
                try await appStartupClient.initializeAppData()
                await send(.appDataInitializationSucceeded)
            } catch {
                await send(.appDataInitializationFailed(AppStartupClientError(error)))
            }
        }
    }
}
