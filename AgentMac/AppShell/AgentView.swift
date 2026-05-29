import ComposableArchitecture
import Perception
import SwiftUI

/// Agent 管理视图。
struct AgentView: View {
    /// Agent 管理页面 store。
    @Perception.Bindable var store: StoreOf<AgentFeature>

    /// 页面内容。
    var body: some View {
        WithPerceptionTracking {
            HStack(spacing: 0) {
                agentList
                Divider()
                editor
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .task {
                store.send(.task)
            }
        }
    }

    private var agentList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agents")
                    .font(.title2.weight(.semibold))

                Spacer()

                Button {
                    store.send(.refreshButtonTapped)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.hasOperationInFlight)
                .help("Refresh")
            }
            .padding(16)

            VStack(spacing: 8) {
                TextField(
                    "agent-id",
                    text: $store.newAgentID.sending(\.newAgentIDChanged)
                )
                .textFieldStyle(.roundedBorder)
                .disabled(store.hasOperationInFlight)

                TextField(
                    "Agent name",
                    text: $store.newAgentName.sending(\.newAgentNameChanged)
                )
                .textFieldStyle(.roundedBorder)
                .disabled(store.hasOperationInFlight)

                Button {
                    store.send(.createAgentButtonTapped)
                } label: {
                    Label("Create", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!store.canCreateAgent)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if store.isLoadingList && store.agents.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $store.selectedAgentID.sending(\.agentSelected)) {
                    ForEach(store.agents) { agent in
                        AgentSummaryRow(agent: agent)
                            .tag(Optional(agent.id))
                    }
                }
            }
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
    }

    private var editor: some View {
        VStack(spacing: 0) {
            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .top], 16)
            }

            if store.isLoadingAgent {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.selectedAgent == nil {
                EmptyAgentSelectionView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AgentEditorView(store: store)
            }
        }
    }
}

/// Agent 列表行。
private struct AgentSummaryRow: View {
    /// Agent 摘要。
    let agent: AgentSummary

    /// 行内容。
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(agent.name)
                .font(.body.weight(.medium))
                .lineLimit(1)

            Text("\(agent.model.provider) / \(agent.model.name)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

/// 未选中 Agent 时的占位视图。
private struct EmptyAgentSelectionView: View {
    /// 占位内容。
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("No Agent Selected")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Agent 编辑表单。
private struct AgentEditorView: View {
    /// Agent 管理页面 store。
    @Perception.Bindable var store: StoreOf<AgentFeature>

    /// 表单内容。
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.editorTitle)
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)

                        if let id = store.selectedAgent?.id {
                            Text(id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    Spacer()

                    Button {
                        store.send(.saveAgentButtonTapped)
                    } label: {
                        Label(store.isSavingAgent ? "Saving" : "Save", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!store.canSaveAgent)
                }
                .padding(16)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !store.isEditingDefaultCodingAgent {
                            formSection(title: "Profile") {
                                LabeledContent("Name") {
                                    TextField(
                                        "Agent name",
                                        text: $store.editorName.sending(\.editorNameChanged)
                                    )
                                    .textFieldStyle(.roundedBorder)
                                }
                            }
                        }

                        formSection(title: "Model") {
                            LabeledContent("Provider") {
                                TextField(
                                    "openai",
                                    text: $store.editorModelProvider.sending(\.editorModelProviderChanged)
                                )
                                .textFieldStyle(.roundedBorder)
                            }

                            LabeledContent("Name") {
                                TextField(
                                    "gpt-5-codex",
                                    text: $store.editorModelName.sending(\.editorModelNameChanged)
                                )
                                .textFieldStyle(.roundedBorder)
                            }
                        }

                        if !store.isEditingDefaultCodingAgent {
                            formSection(title: "Resources") {
                                ResourceSelectionList(
                                    title: "Knowledge",
                                    emptyTitle: "No knowledge resources",
                                    kind: .knowledge,
                                    resources: store.availableKnowledge,
                                    selectedReferences: store.editorKnowledgeReferences,
                                    store: store
                                )

                                ResourceSelectionList(
                                    title: "Skills",
                                    emptyTitle: "No skills",
                                    kind: .skill,
                                    resources: store.availableSkills,
                                    selectedReferences: store.editorSkillReferences,
                                    store: store
                                )

                                ResourceSelectionList(
                                    title: "Tools",
                                    emptyTitle: "No tools",
                                    kind: .tool,
                                    resources: store.availableTools,
                                    selectedReferences: store.editorToolReferences,
                                    store: store
                                )
                            }

                            formSection(title: "System Prompt") {
                                TextEditor(text: $store.editorSystemPrompt.sending(\.editorSystemPromptChanged))
                                    .font(.body)
                                    .frame(minHeight: 260)
                                    .scrollContentBackground(.hidden)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color(nsColor: .separatorColor))
                                    }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 760, alignment: .leading)
                }
            }
        }
    }

    private func formSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
    }
}

/// Agent 编辑页里的单类资源选择控件。
private struct ResourceSelectionList: View {
    /// 分组标题。
    let title: String

    /// 空列表提示。
    let emptyTitle: String

    /// 资源类型。
    let kind: AppResourceKind

    /// 当前资源库中可选择的资源。
    let resources: [AppResourceSummary]

    /// 当前 Agent 已选择的该类型资源引用。
    let selectedReferences: [String]

    /// Agent 管理页面 store。
    @Perception.Bindable var store: StoreOf<AgentFeature>

    /// 控件内容。
    var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    Text("\(selectedReferences.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if resources.isEmpty {
                    Text(emptyTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(resources) { resource in
                            let reference = resource.agentManifestReference
                            Toggle(
                                isOn: Binding(
                                    get: {
                                        selectedReferences.contains(reference)
                                    },
                                    set: { isSelected in
                                        store.send(.resourceSelectionChanged(
                                            kind: kind,
                                            reference: reference,
                                            isSelected: isSelected
                                        ))
                                    }
                                )
                            ) {
                                ResourceSelectionRow(resource: resource, reference: reference)
                            }
                            .toggleStyle(.checkbox)
                            .disabled(store.hasOperationInFlight)
                        }
                    }
                }
            }
        }
    }
}

/// Agent 资源选择行。
private struct ResourceSelectionRow: View {
    /// Resource 摘要。
    let resource: AppResourceSummary

    /// 写入 Agent manifest 的资源引用。
    let reference: String

    /// 行内容。
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: resource.kind.systemImage)
                .foregroundStyle(resource.isValid ? Color.secondary : Color.red)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(resource.name)
                        .font(.body)
                        .lineLimit(1)

                    if !resource.isValid {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Text(reference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
    }
}
