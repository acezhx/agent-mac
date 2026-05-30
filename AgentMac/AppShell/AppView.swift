import AppKit
import ComposableArchitecture
import MarkdownUI
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
                    HStack(spacing: 0) {
                        WorkbenchSidebar(store: store.scope(state: \.session, action: \.session))
                        Divider()
                        SessionView(store: store.scope(state: \.session, action: \.session))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// Agent 会话工作台侧栏。
private struct WorkbenchSidebar: View {
    /// 会话页面 store。
    @Perception.Bindable var store: StoreOf<SessionFeature>

    /// 打开 AppShell 独立管理窗口的环境入口。
    @Environment(\.openWindow) private var openWindow

    /// 侧栏内容。
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                sidebarHeader
                Divider()
                projectList
                Divider()
                sidebarFooter
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var sidebarHeader: some View {
        WithPerceptionTracking {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1")
                    .foregroundStyle(.secondary)
                Text("AgentMac")
                    .font(.headline)
                Spacer()
                Button {
                    store.send(.prepareNewSessionButtonTapped)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .disabled(!store.canPrepareNewSession)
                .help("New Session")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var projectList: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Projects")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 10)

                    if store.sidebarProjectPath != nil {
                        ProjectSidebarRow(
                            title: store.sidebarProjectName,
                            subtitle: store.sidebarProjectDetail,
                            isSelected: true,
                            chooseWorkspace: {
                                chooseWorkspaceDirectory()
                            },
                            canChooseWorkspace: store.canEditSessionSetup
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 6) {
            Button {
                openWindow(id: AppWindowID.agentLibrary.rawValue)
            } label: {
                Label("Agents", systemImage: AppWindowID.agentLibrary.systemImage)
            }
            .help("Manage Agents")

            Button {
                openWindow(id: AppWindowID.resourceLibrary.rawValue)
            } label: {
                Label("Resources", systemImage: AppWindowID.resourceLibrary.systemImage)
            }
            .help("Resource Library")

            Button {
                openWindow(id: AppWindowID.settings.rawValue)
            } label: {
                Image(systemName: AppWindowID.settings.systemImage)
            }
            .help("Settings")
        }
        .labelStyle(.iconOnly)
        .padding(10)
    }

    private func chooseWorkspaceDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        store.send(.workspacePathChanged(url.path))
    }
}

/// 项目侧栏行。
private struct ProjectSidebarRow: View {
    /// 项目展示名。
    let title: String

    /// 项目路径说明。
    let subtitle: String

    /// 是否为当前选中项。
    let isSelected: Bool

    /// 选择项目目录的回调。
    let chooseWorkspace: () -> Void

    /// 是否允许选择项目目录。
    let canChooseWorkspace: Bool

    /// 行内容。
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                chooseWorkspace()
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.borderless)
            .disabled(!canChooseWorkspace)
            .help("Choose Workspace")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
    }

    private var rowBackground: Color {
        isSelected ? Color.accentColor.opacity(0.16) : .clear
    }
}

/// Agent 会话视图。
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
                if store.isPreparingSession {
                    SessionStartView(store: store)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    header
                    Divider()
                    messageList
                    Divider()
                    composer
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .task {
                store.send(.task)
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
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Session")
                            .font(.title2.weight(.semibold))
                        Text(headerDetail)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    StatusBadge(title: store.statusTitle)
                }

                HStack(spacing: 8) {
                    Picker(
                        "Agent",
                        selection: $store.selectedAgentID.sending(\.agentSelected)
                    ) {
                        ForEach(store.agentPickerOptions) { agent in
                            Text(agent.name)
                                .tag(agent.id)
                        }
                    }
                    .frame(width: 280)
                    .disabled(!store.canEditSessionSetup || store.isLoadingAgents)

                    Button {
                        store.send(.refreshAgentsButtonTapped)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.hasOperationInFlight)
                    .help("Refresh Agents")

                    Spacer()

                    Button {
                        store.send(.cancelTurnButtonTapped)
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .disabled(!store.canCancelCurrentTurn)
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
    }

    private var headerDetail: String {
        return "\(store.currentSessionWorkspaceName) / \(store.currentSessionAgentName) / \(store.statusDetail)"
    }

    private var messageList: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                WithPerceptionTracking {
                    let contentWidth = max(CGFloat(0), geometry.size.width - 32)

                    ScrollView(.vertical) {
                        LazyVStack(spacing: 12) {
                            if store.messages.isEmpty {
                                EmptySessionView()
                                    .frame(width: contentWidth)
                                    .frame(minHeight: 240)
                                } else {
                                    ForEach(store.messages) { message in
                                        MessageRow(message: message, rowWidth: contentWidth)
                                            .id(message.id)
                                    }
                                }
                        }
                        .padding(16)
                        .frame(width: geometry.size.width, alignment: .topLeading)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var composer: some View {
        WithPerceptionTracking {
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
                    if store.canCancelCurrentTurn {
                        store.send(.cancelTurnButtonTapped)
                    } else {
                        store.send(.sendMessageButtonTapped)
                    }
                } label: {
                    if store.canCancelCurrentTurn || store.isCancellingTurn {
                        Label("Stop", systemImage: "stop.fill")
                    } else {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!store.canSendMessage && !store.canCancelCurrentTurn)
            }
            .padding(16)
        }
    }
}

/// 新建 session 启动页。
private struct SessionStartView: View {
    /// 会话页面 store。
    @Perception.Bindable var store: StoreOf<SessionFeature>

    /// 页面内容。
    var body: some View {
        WithPerceptionTracking {
            let hasSelectedWorkspace = !store.workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let workspacePickerTitle = store.workspacePickerTitle

            VStack(spacing: 28) {
                Spacer(minLength: 120)

                Text(store.sessionPromptTitle)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                VStack(spacing: 0) {
                    TextField(
                        "尽管问",
                        text: $store.messageText.sending(\.messageTextChanged),
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(2...6)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .disabled(store.hasOperationInFlight)
                    .onSubmit {
                        store.send(.submitInitialMessageButtonTapped)
                    }

                    HStack(spacing: 12) {
                        Button {
                            chooseWorkspaceDirectory()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(store.hasOperationInFlight)
                        .help("Choose Workspace")

                        Spacer()

                        Button {
                            store.send(.submitInitialMessageButtonTapped)
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .disabled(!store.canSubmitInitialMessage)
                        .help("Send")
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)

                    Divider()

                    HStack(spacing: 10) {
                        Button {
                            chooseWorkspaceDirectory()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: hasSelectedWorkspace ? "folder" : "folder.badge.plus")
                                Text(workspacePickerTitle)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 280, alignment: .leading)

                        Picker(
                            "Agent",
                            selection: $store.selectedAgentID.sending(\.agentSelected)
                        ) {
                            ForEach(store.agentPickerOptions) { agent in
                                Text(agent.name)
                                    .tag(agent.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                        .disabled(!store.canEditSessionSetup || store.isLoadingAgents)

                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .disabled(store.hasOperationInFlight)
                }
                .frame(maxWidth: 730)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))

                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: 730, alignment: .leading)
                }

                Spacer()
            }
            .padding(.horizontal, 36)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func chooseWorkspaceDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        store.send(.workspacePathChanged(url.path))
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
            Text("No messages")
                .foregroundStyle(.secondary)
        }
    }
}

/// 单条 chat 消息视图。
private struct MessageRow: View {
    /// 消息模型。
    let message: ChatMessage

    /// 消息行可用宽度。
    let rowWidth: CGFloat

    /// 消息内容。
    var body: some View {
        messageBubble
            .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
            .frame(width: rowWidth, alignment: .leading)
    }

    private var messageBubble: some View {
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

            messageContent
        }
        .padding(12)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var messageContent: some View {
        if message.role == .assistant {
            Markdown(message.content.isEmpty ? " " : message.content)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Markdown(message.content.isEmpty ? " " : message.content)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
        }
    }

    private var bubbleMaxWidth: CGFloat {
        switch message.role {
        case .assistant:
            rowWidth
        case .user, .diagnostic:
            min(720, rowWidth)
        }
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
