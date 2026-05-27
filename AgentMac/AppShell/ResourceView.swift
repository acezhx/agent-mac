import AppKit
import ComposableArchitecture
import Perception
import SwiftUI

/// Resource 管理视图。
struct ResourceView: View {
    /// Resource 管理页面 store。
    @Perception.Bindable var store: StoreOf<ResourceFeature>

    /// 页面内容。
    var body: some View {
        WithPerceptionTracking {
            HStack(spacing: 0) {
                resourceList
                Divider()
                editor
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .task {
                store.send(.task)
            }
        }
    }

    private var resourceList: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Resources")
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

                Picker(
                    "Resource Type",
                    selection: $store.selectedKind.sending(\.selectedKindChanged)
                ) {
                    ForEach(AppResourceKind.allCases, id: \.self) { kind in
                        Text(kind.title)
                            .tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(store.hasOperationInFlight)
            }
            .padding(16)

            createForm

            if store.isLoadingList && store.resources.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $store.selectedResourceID.sending(\.resourceSelected)) {
                    ForEach(store.resources) { resource in
                        ResourceSummaryRow(resource: resource)
                            .tag(Optional(resource.id))
                    }
                }
            }
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
    }

    private var createForm: some View {
        VStack(spacing: 8) {
            Button {
                store.send(.createResourceButtonTapped)
            } label: {
                Label("Create \(store.selectedKind.itemTitle)", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!store.canCreateResource)

            if store.selectedKind == .skill {
                Button {
                    importSkillDirectory()
                } label: {
                    Label(store.isImportingResource ? "Importing Skill" : "Import Skill", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .disabled(store.hasOperationInFlight)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func importSkillDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        store.send(.importSkillDirectorySelected(url.path))
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

            if let successMessage = store.successMessage {
                Text(successMessage)
                    .font(.callout)
                    .foregroundStyle(.green)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .top], 16)
            }

            if store.isLoadingResource {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.selectedResource == nil {
                EmptyResourceSelectionView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ResourceEditorView(store: store)
            }
        }
    }
}

/// Resource 列表行。
private struct ResourceSummaryRow: View {
    /// Resource 摘要。
    let resource: AppResourceSummary

    /// 行内容。
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: resource.kind.systemImage)
                .foregroundStyle(resource.isValid ? Color.secondary : Color.red)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(resource.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if !resource.isValid {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Text(resource.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 未选中 Resource 时的占位视图。
private struct EmptyResourceSelectionView: View {
    /// 占位内容。
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("No Resource Selected")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Resource 编辑表单。
private struct ResourceEditorView: View {
    /// Resource 管理页面 store。
    @Perception.Bindable var store: StoreOf<ResourceFeature>

    /// 是否正在确认删除当前资源。
    @State private var isConfirmingResourceDeletion = false

    /// 表单内容。
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                header
                Divider()
                editorContent
            }
            .confirmationDialog(
                deleteConfirmationTitle,
                isPresented: $isConfirmingResourceDeletion
            ) {
                Button("Delete", role: .destructive) {
                    store.send(.deleteResourceButtonTapped)
                }

                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.editorTitle)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)

                if let resource = store.selectedResource {
                    Text(resource.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            Button(role: .destructive) {
                isConfirmingResourceDeletion = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(!store.canDeleteResource)
            .help("Delete \(store.selectedKind.itemTitle)")

            Button {
                store.send(.saveResourceButtonTapped)
            } label: {
                Label(store.isSavingResource ? "Saving" : "Save", systemImage: "square.and.arrow.down")
            }
            .disabled(!store.canSaveResource)
        }
        .padding(16)
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let resource = store.selectedResource, !resource.validationMessages.isEmpty {
                    validationMessages(resource.validationMessages)
                }

                if store.selectedKind == .knowledge {
                    editorSection(title: "Name") {
                        TextField(
                            "Knowledge name",
                            text: $store.editorResourceName.sending(\.editorResourceNameChanged)
                        )
                        .textFieldStyle(.roundedBorder)
                        .disabled(store.hasOperationInFlight)
                    }
                }

                editorSection(title: store.selectedKind.primaryEditorTitle) {
                    TextEditor(text: $store.editorPrimaryContent.sending(\.editorPrimaryContentChanged))
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: store.selectedKind == .tool ? 220 : 420)
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor))
                        }
                }

                if store.selectedKind == .tool {
                    editorSection(title: "Entry File") {
                        TextEditor(text: $store.editorSecondaryContent.sending(\.editorSecondaryContentChanged))
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 220)
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
            .frame(maxWidth: 860, alignment: .leading)
        }
    }

    private func validationMessages(_ messages: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(messages, id: \.self) { message in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func editorSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            content()
        }
    }

    private var deleteConfirmationTitle: String {
        "Delete \(store.selectedKind.itemTitle)?"
    }
}
