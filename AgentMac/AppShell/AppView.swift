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
                VStack(spacing: 0) {
                    if let startupErrorMessage = store.startupErrorMessage {
                        StartupErrorBanner(message: startupErrorMessage)
                        Divider()
                    }
                    SessionView(store: store.scope(state: \.session, action: \.session))
                }
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

                            Button {
                                openWindow(id: AppWindowID.settings.rawValue)
                            } label: {
                                Label("Settings", systemImage: AppWindowID.settings.systemImage)
                            }
                            .help("Settings")
                        }
                    }
            }
            .frame(minWidth: 960, minHeight: 620)
            .task {
                store.send(.task)
            }
        }
    }
}

/// 启动初始化错误提示。
private struct StartupErrorBanner: View {
    /// 错误信息。
    let message: String

    /// 提示内容。
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// 固定 Pi coding agent 会话视图。
private struct SessionView: View {
    /// 会话页面 store。
    @Perception.Bindable var store: StoreOf<SessionFeature>

    /// 当前展示中的工具审批请求副本，避免 SwiftUI sheet 的 escaping binding 直接读取 Perception state。
    @State private var presentedToolApprovalRequest: ToolApprovalRequest?

    /// 页面内容。
    var body: some View {
        WithPerceptionTracking {
            let pendingToolApprovalRequest = store.pendingToolApprovalRequest

            VStack(spacing: 0) {
                header
                Divider()
                messageList
                Divider()
                composer
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                presentedToolApprovalRequest = pendingToolApprovalRequest
            }
            .onChange(of: pendingToolApprovalRequest) { request in
                presentedToolApprovalRequest = request
            }
            .sheet(item: presentedToolApprovalBinding) { request in
                WithPerceptionTracking {
                    ToolApprovalSheet(
                        request: request,
                        isResolving: store.isResolvingToolApproval,
                        onAllow: {
                            store.send(.allowToolApprovalButtonTapped(request.toolCallID))
                        },
                        onDeny: {
                            store.send(.denyToolApprovalButtonTapped(request.toolCallID))
                        }
                    )
                }
            }
        }
    }

    private var presentedToolApprovalBinding: Binding<ToolApprovalRequest?> {
        Binding(
            get: {
                presentedToolApprovalRequest
            },
            set: { newValue in
                guard newValue == nil,
                      let toolCallID = presentedToolApprovalRequest?.toolCallID
                else {
                    presentedToolApprovalRequest = newValue
                    return
                }
                presentedToolApprovalRequest = nil
                store.send(.toolApprovalSheetDismissed(toolCallID))
            }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(DefaultCodingAgentTemplate.name)
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

/// 工具审批确认视图。
private struct ToolApprovalSheet: View {
    /// 审批请求。
    let request: ToolApprovalRequest

    /// 是否正在提交决策。
    let isResolving: Bool

    /// 批准回调。
    let onAllow: () -> Void

    /// 拒绝回调。
    let onDeny: () -> Void

    /// 视图内容。
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.toolName)
                        .font(.headline)
                    Text(request.summary)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            if !visibleDetails.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleDetails) { detail in
                        ApprovalDetailField(detail: detail)
                    }
                }
            }

            HStack {
                Spacer()
                Button(role: .cancel) {
                    onDeny()
                } label: {
                    Label("Deny", systemImage: "xmark.circle")
                }
                .disabled(isResolving)

                Button {
                    onAllow()
                } label: {
                    Label("Allow", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isResolving)
            }
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled(isResolving)
    }

    /// 弹窗展示的精简详情。
    private var visibleDetails: [VisibleApprovalDetail] {
        let detailsByKey = Dictionary(uniqueKeysWithValues: request.details.map { ($0.key, $0.value) })
        let keys: [String]
        switch request.toolName {
        case "bash":
            keys = ["command"]
        case "read":
            keys = ["path", "offset", "limit"]
        case "edit":
            keys = ["path", "editCount"]
        case "write":
            keys = ["path", "contentLength"]
        default:
            keys = ["path", "command"]
        }

        return keys.compactMap { key in
            guard let value = detailsByKey[key], !value.isEmpty else {
                return nil
            }
            return VisibleApprovalDetail(key: key, value: value)
        }
    }
}

/// 审批弹窗中的单个详情字段。
private struct ApprovalDetailField: View {
    /// 要展示的详情。
    let detail: VisibleApprovalDetail

    /// 字段内容。
    var body: some View {
        if detail.requiresFullText {
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.displayKey)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView(.vertical) {
                    Text(detail.displayValue)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 180)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                }
            }
        } else {
            LabeledContent(detail.displayKey) {
                Text(detail.displayValue)
                    .font(.system(.callout, design: detail.isMonospaced ? .monospaced : .default))
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
        }
    }
}

/// 审批弹窗中展示的精简详情。
private struct VisibleApprovalDetail: Identifiable {
    /// RuntimeHost detail key。
    let key: String

    /// RuntimeHost detail value。
    let value: String

    /// 稳定 id。
    var id: String { key }

    /// 面向用户的字段名。
    var displayKey: String {
        switch key {
        case "command":
            "Command"
        case "path":
            "Path"
        case "offset":
            "Offset"
        case "limit":
            "Limit"
        case "editCount":
            "Edits"
        case "contentLength":
            "Bytes"
        default:
            key
        }
    }

    /// 面向用户展示的字段值。
    var displayValue: String {
        if ["offset", "limit", "editCount", "contentLength"].contains(key),
           value.hasSuffix(".0") {
            return String(value.dropLast(2))
        }
        return value
    }

    /// 是否使用等宽字体展示。
    var isMonospaced: Bool {
        key == "command" || key == "path"
    }

    /// 是否需要完整展示。
    var requiresFullText: Bool {
        key == "command"
    }
}

#Preview {
    AppView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
        }
    )
}
