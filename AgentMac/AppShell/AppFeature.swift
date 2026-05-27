import ComposableArchitecture
import Foundation

/// AppShell 独立窗口标识。
nonisolated enum AppWindowID: String, Hashable {
    /// Agent 管理窗口。
    case agentLibrary = "agent-library"

    /// Resource 管理窗口。
    case resourceLibrary = "resource-library"

    /// 窗口标题。
    var title: String {
        switch self {
        case .agentLibrary:
            "Agent Library"
        case .resourceLibrary:
            "Resource Library"
        }
    }

    /// 窗口图标名称。
    var systemImage: String {
        switch self {
        case .agentLibrary:
            "person.crop.circle"
        case .resourceLibrary:
            "folder"
        }
    }
}

/// AgentMac 根 Feature。
@Reducer
struct AppFeature {
    /// AppShell 根状态。
    @ObservableState
    struct State: Equatable {
        /// 当前会话页面状态。
        var session = SessionFeature.State()
    }

    /// AppShell 根 action。
    enum Action: Equatable {
        /// 会话页面 action。
        case session(SessionFeature.Action)
    }

    /// 根 reducer 组合。
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .session:
                return .none
            }
        }

        Scope(state: \.session, action: \.session) {
            SessionFeature()
        }
    }
}
