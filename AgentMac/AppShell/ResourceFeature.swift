import ComposableArchitecture
import Foundation

/// Resource 管理页面 Feature。
///
/// 该 Feature 只管理 Resource 列表、创建表单和编辑表单的 UI 状态。资源文件读写通过
/// `AppResourceClient` 注入，底层 `ResourceLibrary` 不依赖 TCA。
@Reducer
struct ResourceFeature {
    /// Resource 管理页面状态。
    @ObservableState
    struct State: Equatable {
        /// 当前资源类型。
        var selectedKind: AppResourceKind

        /// 当前资源类型的摘要列表。
        var resources: [AppResourceSummary]

        /// 当前选中的资源 ID。
        var selectedResourceID: String?

        /// 当前加载到编辑区的资源文档。
        var selectedResource: AppResourceDocument?

        /// 编辑表单中的主内容。
        var editorPrimaryContent: String

        /// 编辑表单中的资源展示名称。第一版仅 knowledge 通过该字段改名。
        var editorResourceName: String

        /// 编辑表单中的 tool 入口内容。
        var editorSecondaryContent: String

        /// 最近一次操作错误。
        var errorMessage: String?

        /// 最近一次成功操作提示。
        var successMessage: String?

        /// 是否正在加载列表。
        var isLoadingList: Bool

        /// 是否正在加载选中资源。
        var isLoadingResource: Bool

        /// 是否正在创建资源。
        var isCreatingResource: Bool

        /// 是否正在导入资源。
        var isImportingResource: Bool

        /// 是否正在保存资源。
        var isSavingResource: Bool

        /// 是否正在删除资源。
        var isDeletingResource: Bool

        /// 创建 Resource 管理页面状态。
        init() {
            self.selectedKind = .knowledge
            self.resources = []
            self.selectedResourceID = nil
            self.selectedResource = nil
            self.editorPrimaryContent = ""
            self.editorResourceName = ""
            self.editorSecondaryContent = ""
            self.errorMessage = nil
            self.successMessage = nil
            self.isLoadingList = false
            self.isLoadingResource = false
            self.isCreatingResource = false
            self.isImportingResource = false
            self.isSavingResource = false
            self.isDeletingResource = false
        }

        /// 是否有 Resource 操作正在运行。
        var hasOperationInFlight: Bool {
            isLoadingList || isLoadingResource || isCreatingResource || isImportingResource || isSavingResource || isDeletingResource
        }

        /// 是否可以创建资源。
        var canCreateResource: Bool {
            !hasOperationInFlight
        }

        /// 是否可以保存当前资源。
        var canSaveResource: Bool {
            selectedResource != nil && !hasOperationInFlight
        }

        /// 是否可以删除当前选中的资源。
        var canDeleteResource: Bool {
            selectedResource != nil && !hasOperationInFlight
        }

        /// 当前编辑区标题。
        var editorTitle: String {
            guard let selectedResource else {
                return "No Resource"
            }

            return selectedResource.name.isEmpty ? selectedResource.id : selectedResource.name
        }

        /// 清空编辑区。
        mutating func clearEditor() {
            selectedResource = nil
            editorPrimaryContent = ""
            editorResourceName = ""
            editorSecondaryContent = ""
        }

        /// 用资源文档填充编辑区。
        ///
        /// - Parameter document: 已加载或已保存的资源文档。
        mutating func populateEditor(with document: AppResourceDocument) {
            selectedResource = document
            selectedResourceID = document.id
            editorPrimaryContent = document.primaryContent
            editorResourceName = document.name
            editorSecondaryContent = document.secondaryContent ?? ""
        }

        /// 生成可保存的资源编辑文档。
        ///
        /// - Returns: 当前编辑区对应的资源文档；没有选中资源时返回 `nil`。
        func editedResource() -> AppResourceDocument? {
            guard var document = selectedResource else {
                return nil
            }

            document.primaryContent = editorPrimaryContent
            if document.kind == .knowledge {
                document.name = editorResourceName
            }
            if document.kind == .tool {
                document.secondaryContent = editorSecondaryContent
            }
            return document
        }

        /// 插入或替换资源摘要，并按 ID 稳定排序。
        ///
        /// - Parameter summary: 要同步到列表中的资源摘要。
        mutating func upsertSummary(_ summary: AppResourceSummary) {
            resources.removeAll { $0.id == summary.id }
            resources.append(summary)
            resources.sort { $0.id < $1.id }
        }
    }

    /// Resource 管理页面 action。
    enum Action: Equatable {
        /// 页面进入时加载资源列表。
        case task

        /// 用户点击刷新列表。
        case refreshButtonTapped

        /// 用户切换资源类型。
        case selectedKindChanged(AppResourceKind)

        /// 资源列表加载成功。
        case loadResourcesSucceeded(kind: AppResourceKind, resources: [AppResourceSummary])

        /// 资源列表加载失败。
        case loadResourcesFailed(kind: AppResourceKind, AppResourceClientError)

        /// 用户选择资源。
        case resourceSelected(String?)

        /// 资源加载成功。
        case loadResourceSucceeded(AppResourceDocument)

        /// 资源加载失败。
        case loadResourceFailed(AppResourceClientError)

        /// 用户点击创建资源。
        case createResourceButtonTapped

        /// 资源创建成功。
        case createResourceSucceeded(AppResourceDocument)

        /// 资源创建失败。
        case createResourceFailed(AppResourceClientError)

        /// 用户选择了要导入的 skill 目录。
        case importSkillDirectorySelected(String)

        /// skill 导入成功。
        case importSkillSucceeded(AppResourceDocument)

        /// skill 导入失败。
        case importSkillFailed(AppResourceClientError)

        /// 编辑表单主内容变化。
        case editorPrimaryContentChanged(String)

        /// 编辑表单资源名称变化。
        case editorResourceNameChanged(String)

        /// 编辑表单 tool 入口内容变化。
        case editorSecondaryContentChanged(String)

        /// 用户点击保存资源。
        case saveResourceButtonTapped

        /// 资源保存成功。
        case saveResourceSucceeded(AppResourceDocument)

        /// 资源保存失败。
        case saveResourceFailed(AppResourceClientError)

        /// 用户确认删除当前资源。
        case deleteResourceButtonTapped

        /// 资源删除成功。
        case deleteResourceSucceeded(kind: AppResourceKind, id: String)

        /// 资源删除失败。
        case deleteResourceFailed(AppResourceClientError)
    }

    private nonisolated enum CancelID: Hashable {
        case list
        case selectedResource
    }

    /// Resource 管理页面 reducer。
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task, .refreshButtonTapped:
                state.isLoadingList = true
                state.errorMessage = nil
                state.successMessage = nil
                return loadResourcesEffect(kind: state.selectedKind)

            case let .selectedKindChanged(kind):
                guard state.selectedKind != kind else {
                    return .none
                }
                state.selectedKind = kind
                state.resources = []
                state.selectedResourceID = nil
                state.clearEditor()
                state.isLoadingList = true
                state.isLoadingResource = false
                state.errorMessage = nil
                state.successMessage = nil
                return .merge(
                    .cancel(id: CancelID.selectedResource),
                    loadResourcesEffect(kind: kind)
                )

            case let .loadResourcesSucceeded(kind, resources):
                guard kind == state.selectedKind else {
                    return .none
                }
                state.isLoadingList = false
                state.resources = resources
                if let selectedResourceID = state.selectedResourceID,
                   !resources.contains(where: { $0.id == selectedResourceID }) {
                    state.selectedResourceID = nil
                    state.clearEditor()
                }
                return .none

            case let .loadResourcesFailed(kind, error):
                guard kind == state.selectedKind else {
                    return .none
                }
                state.isLoadingList = false
                state.errorMessage = error.message
                state.successMessage = nil
                return .none

            case let .resourceSelected(id):
                state.selectedResourceID = id
                state.errorMessage = nil
                state.successMessage = nil
                guard let id else {
                    state.isLoadingResource = false
                    state.clearEditor()
                    return .cancel(id: CancelID.selectedResource)
                }

                state.isLoadingResource = true
                state.clearEditor()
                state.selectedResourceID = id
                return loadResourceEffect(kind: state.selectedKind, id: id)

            case let .loadResourceSucceeded(document):
                guard document.kind == state.selectedKind else {
                    return .none
                }
                state.isLoadingResource = false
                state.populateEditor(with: document)
                return .none

            case let .loadResourceFailed(error):
                state.isLoadingResource = false
                state.errorMessage = error.message
                state.successMessage = nil
                return .none

            case .createResourceButtonTapped:
                guard state.canCreateResource else {
                    return .none
                }
                state.isCreatingResource = true
                state.errorMessage = nil
                state.successMessage = nil
                let kind = state.selectedKind
                let id = ""
                let name = ""
                @Dependency(AppResourceClient.self) var appResourceClient
                return .run { send in
                    do {
                        let document = try await appResourceClient.createResource(kind, id, name)
                        await send(.createResourceSucceeded(document))
                    } catch {
                        await send(.createResourceFailed(AppResourceClientError(error)))
                    }
                }

            case let .createResourceSucceeded(document):
                guard document.kind == state.selectedKind else {
                    state.isCreatingResource = false
                    return .none
                }
                state.isCreatingResource = false
                state.upsertSummary(document.summary)
                state.populateEditor(with: document)
                state.errorMessage = nil
                state.successMessage = nil
                return .none

            case let .createResourceFailed(error):
                state.isCreatingResource = false
                state.errorMessage = error.message
                state.successMessage = nil
                return .none

            case let .importSkillDirectorySelected(sourceDirectoryPath):
                guard state.selectedKind == .skill, !state.hasOperationInFlight else {
                    return .none
                }
                state.isImportingResource = true
                state.errorMessage = nil
                state.successMessage = nil
                @Dependency(AppResourceClient.self) var appResourceClient
                return .run { send in
                    do {
                        let document = try await appResourceClient.importSkillDirectory(sourceDirectoryPath)
                        await send(.importSkillSucceeded(document))
                    } catch {
                        await send(.importSkillFailed(AppResourceClientError(error)))
                    }
                }

            case let .importSkillSucceeded(document):
                guard state.selectedKind == .skill, document.kind == .skill else {
                    state.isImportingResource = false
                    return .none
                }
                state.isImportingResource = false
                state.upsertSummary(document.summary)
                state.populateEditor(with: document)
                state.errorMessage = nil
                state.successMessage = nil
                return .none

            case let .importSkillFailed(error):
                state.isImportingResource = false
                state.errorMessage = error.message
                state.successMessage = nil
                return .none

            case let .editorPrimaryContentChanged(content):
                state.editorPrimaryContent = content
                state.successMessage = nil
                return .none

            case let .editorResourceNameChanged(name):
                state.editorResourceName = name
                state.successMessage = nil
                return .none

            case let .editorSecondaryContentChanged(content):
                state.editorSecondaryContent = content
                state.successMessage = nil
                return .none

            case .saveResourceButtonTapped:
                guard state.canSaveResource, let document = state.editedResource() else {
                    return .none
                }
                state.isSavingResource = true
                state.errorMessage = nil
                state.successMessage = nil
                @Dependency(AppResourceClient.self) var appResourceClient
                return .run { send in
                    do {
                        let savedDocument = try await appResourceClient.saveResource(document)
                        await send(.saveResourceSucceeded(savedDocument))
                    } catch {
                        await send(.saveResourceFailed(AppResourceClientError(error)))
                    }
                }

            case let .saveResourceSucceeded(document):
                guard document.kind == state.selectedKind else {
                    state.isSavingResource = false
                    return .none
                }
                state.isSavingResource = false
                if let selectedResourceID = state.selectedResourceID, selectedResourceID != document.id {
                    state.resources.removeAll { $0.id == selectedResourceID }
                }
                state.upsertSummary(document.summary)
                state.populateEditor(with: document)
                state.errorMessage = nil
                state.successMessage = "\(document.name) saved."
                return .none

            case let .saveResourceFailed(error):
                state.isSavingResource = false
                state.errorMessage = error.message
                state.successMessage = nil
                return .none

            case .deleteResourceButtonTapped:
                guard state.canDeleteResource,
                      let resource = state.selectedResource
                else {
                    return .none
                }
                state.isDeletingResource = true
                state.errorMessage = nil
                state.successMessage = nil
                let kind = state.selectedKind
                let id = resource.id
                @Dependency(AppResourceClient.self) var appResourceClient
                return .run { send in
                    do {
                        try await appResourceClient.deleteResource(kind, id)
                        await send(.deleteResourceSucceeded(kind: kind, id: id))
                    } catch {
                        await send(.deleteResourceFailed(AppResourceClientError(error)))
                    }
                }

            case let .deleteResourceSucceeded(kind, id):
                state.isDeletingResource = false
                guard state.selectedKind == kind else {
                    return .none
                }
                state.resources.removeAll { $0.id == id }
                if state.selectedResourceID == id {
                    state.selectedResourceID = nil
                    state.clearEditor()
                }
                state.errorMessage = nil
                state.successMessage = nil
                return .none

            case let .deleteResourceFailed(error):
                state.isDeletingResource = false
                state.errorMessage = error.message
                state.successMessage = nil
                return .none
            }
        }
    }

    private func loadResourcesEffect(kind: AppResourceKind) -> Effect<Action> {
        @Dependency(AppResourceClient.self) var appResourceClient
        return .run { send in
            do {
                let resources = try await appResourceClient.listResources(kind)
                await send(.loadResourcesSucceeded(kind: kind, resources: resources))
            } catch {
                await send(.loadResourcesFailed(kind: kind, AppResourceClientError(error)))
            }
        }
        .cancellable(id: CancelID.list, cancelInFlight: true)
    }

    private func loadResourceEffect(kind: AppResourceKind, id: String) -> Effect<Action> {
        @Dependency(AppResourceClient.self) var appResourceClient
        return .run { send in
            do {
                let document = try await appResourceClient.loadResource(kind, id)
                await send(.loadResourceSucceeded(document))
            } catch {
                await send(.loadResourceFailed(AppResourceClientError(error)))
            }
        }
        .cancellable(id: CancelID.selectedResource, cancelInFlight: true)
    }
}
