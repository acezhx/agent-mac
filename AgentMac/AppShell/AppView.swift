import ComposableArchitecture
import Perception
import SwiftUI

/// AgentMac 根视图。
struct AppView: View {
    /// AppShell 根 store。
    @Perception.Bindable var store: StoreOf<AppFeature>

    /// 打开 AppShell 独立管理窗口的环境入口。
    @Environment(\.openWindow) private var openWindow

    /// 根视图内容。
    var body: some View {
        WithPerceptionTracking {
            NavigationStack {
                SessionView(store: store.scope(state: \.session, action: \.session))
                    .navigationTitle("AgentMac")
                    .toolbar {
                        ToolbarItemGroup {
                            Button {
                                openWindow(id: AppWindowID.agentLibrary.rawValue)
                            } label: {
                                Label("Manage Agents", systemImage: AppWindowID.agentLibrary.systemImage)
                            }
                            .help("Manage Agents")

                            Button {
                                openWindow(id: AppWindowID.resourceLibrary.rawValue)
                            } label: {
                                Label("Resource Library", systemImage: AppWindowID.resourceLibrary.systemImage)
                            }
                            .help("Resource Library")
                        }
                    }
            }
            .frame(minWidth: 960, minHeight: 620)
        }
    }
}

/// 固定 Pi coding agent 会话视图。
private struct SessionView: View {
    /// 会话页面 store。
    @Perception.Bindable var store: StoreOf<SessionFeature>

    /// 页面内容。
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                header
                Divider()
                messageList
                Divider()
                composer
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fixed Coding Agent")
                        .font(.title2.weight(.semibold))
                    Text(store.statusDetail)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                StatusBadge(title: store.statusTitle)
            }

            HStack(spacing: 8) {
                TextField(
                    "Workspace path",
                    text: $store.workspacePath.sending(\.workspacePathChanged)
                )
                .textFieldStyle(.roundedBorder)
                .disabled(store.snapshot != nil || store.hasOperationInFlight)

                Button {
                    store.send(.createSessionButtonTapped)
                } label: {
                    Label("New Session", systemImage: "plus.circle")
                }
                .disabled(!store.canCreateSession)

                Button {
                    store.send(.startSessionButtonTapped)
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .disabled(!store.canStartSession)

                Button {
                    store.send(.abortSessionButtonTapped)
                } label: {
                    Label("Abort", systemImage: "stop.fill")
                }
                .disabled(!store.canAbortSession)

                Button {
                    store.send(.resetSessionButtonTapped)
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .disabled(!store.canResetSession)
            }

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            WithPerceptionTracking {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if store.messages.isEmpty {
                            EmptySessionView()
                                .frame(maxWidth: .infinity, minHeight: 240)
                        } else {
                            ForEach(store.messages) { message in
                                MessageRow(message: message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: store.messages.last?.id) { id in
                    guard let id else {
                        return
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                "Message",
                text: $store.messageText.sending(\.messageTextChanged),
                axis: .vertical
            )
            .lineLimit(1...5)
            .textFieldStyle(.roundedBorder)
            .disabled(store.snapshot == nil || store.snapshot?.runtimeSessionID == nil || store.hasOperationInFlight)
            .onSubmit {
                store.send(.sendMessageButtonTapped)
            }

            Button {
                store.send(.sendMessageButtonTapped)
            } label: {
                Label("Send", systemImage: "paperplane.fill")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!store.canSendMessage)
        }
        .padding(16)
    }
}

/// 会话状态标记。
private struct StatusBadge: View {
    /// 状态标题。
    let title: String

    /// 标记内容。
    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
    }
}

/// 空会话占位视图。
private struct EmptySessionView: View {
    /// 占位内容。
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "message")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Create and start a session to chat with the fixed coding agent.")
                .foregroundStyle(.secondary)
        }
    }
}

/// 单条 chat 消息视图。
private struct MessageRow: View {
    /// 消息模型。
    let message: ChatMessage

    /// 消息内容。
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .foregroundStyle(roleColor)
                Text(roleTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if message.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(message.content.isEmpty ? " " : message.content)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private var roleTitle: String {
        switch message.role {
        case .user:
            "User"
        case .assistant:
            "Assistant"
        case .diagnostic:
            "Diagnostic"
        }
    }

    private var iconName: String {
        switch message.role {
        case .user:
            "person.fill"
        case .assistant:
            "sparkles"
        case .diagnostic:
            "exclamationmark.triangle.fill"
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user:
            .accentColor
        case .assistant:
            .green
        case .diagnostic:
            .orange
        }
    }

    private var rowBackground: Color {
        switch message.role {
        case .user:
            Color.accentColor.opacity(0.08)
        case .assistant:
            Color(nsColor: .controlBackgroundColor)
        case .diagnostic:
            Color.orange.opacity(0.1)
        }
    }
}

#Preview {
    AppView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
        }
    )
}
