import ComposableArchitecture
import Foundation
import Testing
@testable import AgentMac

/// AppShell Resource Feature 的状态流转测试。
///
/// 测试只注入 mock `AppResourceClient`，不访问真实 Application Support。
@MainActor
struct ResourceFeatureTests {
    /// 验证加载 knowledge 列表会保存摘要。
    @Test func loadKnowledgeStoresSummaries() async {
        let summaries = [
            makeSummary(kind: .knowledge, id: "refund.md", name: "refund", path: "library/knowledge/refund.md"),
        ]
        let store = TestStore(initialState: ResourceFeature.State()) {
            ResourceFeature()
        } withDependencies: {
            $0.appResourceClient = makeClient(
                listResources: { kind in
                    #expect(kind == .knowledge)
                    return summaries
                }
            )
        }

        await store.send(.task) {
            $0.isLoadingList = true
            $0.errorMessage = nil
        }
        await store.receive(.loadResourcesSucceeded(kind: .knowledge, resources: summaries)) {
            $0.isLoadingList = false
            $0.resources = summaries
        }
    }

    /// 验证切换资源类型会清理当前编辑区并加载新列表。
    @Test func switchingKindClearsEditorAndLoadsList() async {
        let toolSummary = makeSummary(kind: .tool, id: "ticket-search", name: "Ticket Search", path: "library/tools/ticket-search")
        var state = ResourceFeature.State()
        state.resources = [
            makeSummary(kind: .knowledge, id: "refund.md", name: "refund", path: "library/knowledge/refund.md"),
        ]
        state.populateEditor(with: makeDocument(kind: .knowledge, id: "refund.md", name: "refund", primaryContent: "old"))

        let store = TestStore(initialState: state) {
            ResourceFeature()
        } withDependencies: {
            $0.appResourceClient = makeClient(
                listResources: { kind in
                    #expect(kind == .tool)
                    return [toolSummary]
                }
            )
        }

        await store.send(.selectedKindChanged(.tool)) {
            $0.selectedKind = .tool
            $0.resources = []
            $0.selectedResourceID = nil
            $0.selectedResource = nil
            $0.editorPrimaryContent = ""
            $0.editorResourceName = ""
            $0.editorSecondaryContent = ""
            $0.isLoadingList = true
            $0.isLoadingResource = false
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        await store.receive(.loadResourcesSucceeded(kind: .tool, resources: [toolSummary])) {
            $0.isLoadingList = false
            $0.resources = [toolSummary]
        }
    }

    /// 验证选择资源会加载编辑区内容。
    @Test func selectingResourceLoadsEditorFields() async {
        let document = makeDocument(
            kind: .skill,
            id: "report-writing",
            name: "report-writing",
            primaryContent: "# Report\n"
        )
        var state = ResourceFeature.State()
        state.selectedKind = .skill
        let store = TestStore(initialState: state) {
            ResourceFeature()
        } withDependencies: {
            $0.appResourceClient = makeClient(
                loadResource: { kind, id in
                    #expect(kind == .skill)
                    #expect(id == "report-writing")
                    return document
                }
            )
        }

        await store.send(.resourceSelected("report-writing")) {
            $0.selectedResourceID = "report-writing"
            $0.errorMessage = nil
            $0.isLoadingResource = true
        }
        await store.receive(.loadResourceSucceeded(document)) {
            $0.isLoadingResource = false
            $0.selectedResource = document
            $0.selectedResourceID = "report-writing"
            $0.editorPrimaryContent = "# Report\n"
            $0.editorResourceName = "report-writing"
            $0.editorSecondaryContent = ""
        }
    }

    /// 验证创建 knowledge 不需要用户输入 ID，创建成功后选中 dependency 返回的资源。
    @Test func createKnowledgeAllowsEmptyIDAndSelectsGeneratedDocument() async {
        let document = makeDocument(
            kind: .knowledge,
            id: "knowledge-2.md",
            name: "knowledge-2",
            primaryContent: ""
        )
        let recorder = Recorder()
        var state = ResourceFeature.State()
        let store = TestStore(initialState: state) {
            ResourceFeature()
        } withDependencies: {
            $0.appResourceClient = makeClient(
                createResource: { kind, id, name in
                    recorder.createdResources.append(CreatedResource(kind: kind, id: id, name: name))
                    return document
                }
            )
        }

        await store.send(.createResourceButtonTapped) {
            $0.isCreatingResource = true
            $0.errorMessage = nil
        }
        await store.receive(.createResourceSucceeded(document)) {
            $0.isCreatingResource = false
            $0.resources = [document.summary]
            $0.selectedResource = document
            $0.selectedResourceID = "knowledge-2.md"
            $0.editorPrimaryContent = document.primaryContent
            $0.editorResourceName = "knowledge-2"
            $0.editorSecondaryContent = ""
            $0.errorMessage = nil
        }

        #expect(recorder.createdResources == [
            CreatedResource(kind: .knowledge, id: "", name: ""),
        ])
    }

    /// 验证创建 tool 不需要用户输入名称，并会选中新资源、更新列表。
    @Test func createToolSelectsNewResourceAndUpdatesList() async {
        let document = makeDocument(
            kind: .tool,
            id: "ticket-search",
            name: "Ticket Search",
            primaryContent: "id: ticket-search\nentry: index.js\n",
            secondaryContent: "export default async function run() {}\n"
        )
        let recorder = Recorder()
        var state = ResourceFeature.State()
        state.selectedKind = .tool
        let store = TestStore(initialState: state) {
            ResourceFeature()
        } withDependencies: {
            $0.appResourceClient = makeClient(
                createResource: { kind, id, name in
                    recorder.createdResources.append(CreatedResource(kind: kind, id: id, name: name))
                    return document
                }
            )
        }

        await store.send(.createResourceButtonTapped) {
            $0.isCreatingResource = true
            $0.errorMessage = nil
        }
        await store.receive(.createResourceSucceeded(document)) {
            $0.isCreatingResource = false
            $0.resources = [document.summary]
            $0.selectedResource = document
            $0.selectedResourceID = "ticket-search"
            $0.editorPrimaryContent = document.primaryContent
            $0.editorResourceName = "Ticket Search"
            $0.editorSecondaryContent = document.secondaryContent ?? ""
            $0.errorMessage = nil
        }

        #expect(recorder.createdResources == [
            CreatedResource(kind: .tool, id: "", name: ""),
        ])
    }

    /// 验证创建 skill 不需要用户输入 ID，创建成功后选中 dependency 返回的资源。
    @Test func createSkillAllowsEmptyIDAndSelectsGeneratedDocument() async {
        let document = makeDocument(
            kind: .skill,
            id: "skill-2",
            name: "skill-2",
            primaryContent: ""
        )
        let recorder = Recorder()
        var state = ResourceFeature.State()
        state.selectedKind = .skill
        let store = TestStore(initialState: state) {
            ResourceFeature()
        } withDependencies: {
            $0.appResourceClient = makeClient(
                createResource: { kind, id, name in
                    recorder.createdResources.append(CreatedResource(kind: kind, id: id, name: name))
                    return document
                }
            )
        }

        await store.send(.createResourceButtonTapped) {
            $0.isCreatingResource = true
            $0.errorMessage = nil
        }
        await store.receive(.createResourceSucceeded(document)) {
            $0.isCreatingResource = false
            $0.resources = [document.summary]
            $0.selectedResource = document
            $0.selectedResourceID = "skill-2"
            $0.editorPrimaryContent = document.primaryContent
            $0.editorResourceName = "skill-2"
            $0.editorSecondaryContent = ""
            $0.errorMessage = nil
        }

        #expect(recorder.createdResources == [
            CreatedResource(kind: .skill, id: "", name: ""),
        ])
    }

    /// 验证导入 skill 会选中导入后的资源并更新列表。
    @Test func importSkillSelectsImportedDocumentAndUpdatesList() async {
        let document = makeDocument(
            kind: .skill,
            id: "report-writing",
            name: "Report Writing",
            primaryContent: """
            ---
            name: "Report Writing"
            ---
            """
        )
        let recorder = Recorder()
        var state = ResourceFeature.State()
        state.selectedKind = .skill
        let store = TestStore(initialState: state) {
            ResourceFeature()
        } withDependencies: {
            $0.appResourceClient = makeClient(
                importSkillDirectory: { path in
                    recorder.importedSkillPaths.append(path)
                    return document
                }
            )
        }

        await store.send(.importSkillDirectorySelected("/tmp/Report Writing")) {
            $0.isImportingResource = true
            $0.errorMessage = nil
        }
        await store.receive(.importSkillSucceeded(document)) {
            $0.isImportingResource = false
            $0.resources = [document.summary]
            $0.selectedResource = document
            $0.selectedResourceID = "report-writing"
            $0.editorPrimaryContent = document.primaryContent
            $0.editorResourceName = "Report Writing"
            $0.editorSecondaryContent = ""
            $0.errorMessage = nil
        }

        #expect(recorder.importedSkillPaths == ["/tmp/Report Writing"])
    }

    /// 验证非 skill 类型下会忽略导入目录选择。
    @Test func importSkillIsIgnoredOutsideSkillKind() async {
        let store = TestStore(initialState: ResourceFeature.State()) {
            ResourceFeature()
        } withDependencies: {
            $0.appResourceClient = makeClient()
        }

        await store.send(.importSkillDirectorySelected("/tmp/Report Writing"))
    }

    /// 验证删除 knowledge 会移除列表项并清空编辑区。
    @Test func deleteKnowledgeRemovesResourceAndClearsEditor() async {
        let document = makeDocument(
            kind: .knowledge,
            id: "refund.md",
            name: "refund",
            primaryContent: "content"
        )
        let recorder = Recorder()
        var state = ResourceFeature.State()
        state.resources = [document.summary]
        state.populateEditor(with: document)
        let store = TestStore(initialState: state) {
            ResourceFeature()
        } withDependencies: {
            $0.appResourceClient = makeClient(
                deleteResource: { kind, id in
                    recorder.deletedResources.append(DeletedResource(kind: kind, id: id))
                }
            )
        }

        await store.send(.deleteResourceButtonTapped) {
            $0.isDeletingResource = true
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        await store.receive(.deleteResourceSucceeded(kind: .knowledge, id: "refund.md")) {
            $0.isDeletingResource = false
            $0.resources = []
            $0.selectedResourceID = nil
            $0.selectedResource = nil
            $0.editorPrimaryContent = ""
            $0.editorResourceName = ""
            $0.editorSecondaryContent = ""
            $0.errorMessage = nil
            $0.successMessage = nil
        }

        #expect(recorder.deletedResources == [
            DeletedResource(kind: .knowledge, id: "refund.md"),
        ])
    }

    /// 验证删除 skill 会移除列表项并清空编辑区。
    @Test func deleteSkillRemovesResourceAndClearsEditor() async {
        let document = makeDocument(
            kind: .skill,
            id: "report-writing",
            name: "Report Writing",
            primaryContent: "# Report\n"
        )
        let recorder = Recorder()
        var state = ResourceFeature.State()
        state.selectedKind = .skill
        state.resources = [document.summary]
        state.populateEditor(with: document)
        let store = TestStore(initialState: state) {
            ResourceFeature()
        } withDependencies: {
            $0.appResourceClient = makeClient(
                deleteResource: { kind, id in
                    recorder.deletedResources.append(DeletedResource(kind: kind, id: id))
                }
            )
        }

        await store.send(.deleteResourceButtonTapped) {
            $0.isDeletingResource = true
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        await store.receive(.deleteResourceSucceeded(kind: .skill, id: "report-writing")) {
            $0.isDeletingResource = false
            $0.resources = []
            $0.selectedResourceID = nil
            $0.selectedResource = nil
            $0.editorPrimaryContent = ""
            $0.editorResourceName = ""
            $0.editorSecondaryContent = ""
            $0.errorMessage = nil
            $0.successMessage = nil
        }

        #expect(recorder.deletedResources == [
            DeletedResource(kind: .skill, id: "report-writing"),
        ])
    }

    /// 验证保存 knowledge 会提交编辑后的名称，改名成功后替换列表旧项并展示成功提示。
    @Test func saveKnowledgeSendsEditedNameAndShowsSuccess() async {
        let original = makeDocument(kind: .knowledge, id: "refund.md", name: "refund", primaryContent: "old")
        let saved = makeDocument(kind: .knowledge, id: "refund-policy.md", name: "refund-policy", primaryContent: "new")
        let recorder = Recorder()
        var state = ResourceFeature.State()
        state.resources = [original.summary]
        state.populateEditor(with: original)
        state.editorResourceName = "refund-policy"
        state.editorPrimaryContent = "new"

        let store = TestStore(initialState: state) {
            ResourceFeature()
        } withDependencies: {
            $0.appResourceClient = makeClient(
                saveResource: { document in
                    recorder.savedDocuments.append(document)
                    return saved
                }
            )
        }

        await store.send(.saveResourceButtonTapped) {
            $0.isSavingResource = true
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        await store.receive(.saveResourceSucceeded(saved)) {
            $0.isSavingResource = false
            $0.resources = [saved.summary]
            $0.selectedResource = saved
            $0.selectedResourceID = "refund-policy.md"
            $0.editorPrimaryContent = "new"
            $0.editorResourceName = "refund-policy"
            $0.editorSecondaryContent = ""
            $0.errorMessage = nil
            $0.successMessage = "refund-policy saved."
        }

        #expect(recorder.savedDocuments.count == 1)
        #expect(recorder.savedDocuments.first?.id == "refund.md")
        #expect(recorder.savedDocuments.first?.name == "refund-policy")
        #expect(recorder.savedDocuments.first?.primaryContent == "new")
    }

    /// 验证保存 skill 只提交编辑后的 `SKILL.md`，不会由 UI 层改变目录 ID。
    @Test func saveSkillKeepsDirectoryIDAndUpdatesDisplayName() async {
        let original = makeDocument(
            kind: .skill,
            id: "skill",
            name: "skill",
            primaryContent: """
            ---
            name: "skill"
            ---
            """
        )
        let saved = makeDocument(
            kind: .skill,
            id: "skill",
            name: "Report Writing",
            primaryContent: """
            ---
            name: "Report Writing"
            ---
            """
        )
        let recorder = Recorder()
        var state = ResourceFeature.State()
        state.selectedKind = .skill
        state.resources = [original.summary]
        state.populateEditor(with: original)
        state.editorPrimaryContent = saved.primaryContent

        let store = TestStore(initialState: state) {
            ResourceFeature()
        } withDependencies: {
            $0.appResourceClient = makeClient(
                saveResource: { document in
                    recorder.savedDocuments.append(document)
                    return saved
                }
            )
        }

        await store.send(.saveResourceButtonTapped) {
            $0.isSavingResource = true
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        await store.receive(.saveResourceSucceeded(saved)) {
            $0.isSavingResource = false
            $0.resources = [saved.summary]
            $0.selectedResource = saved
            $0.selectedResourceID = "skill"
            $0.editorPrimaryContent = saved.primaryContent
            $0.editorResourceName = "Report Writing"
            $0.editorSecondaryContent = ""
            $0.errorMessage = nil
            $0.successMessage = "Report Writing saved."
        }

        #expect(recorder.savedDocuments.count == 1)
        #expect(recorder.savedDocuments.first?.id == "skill")
        #expect(recorder.savedDocuments.first?.primaryContent == saved.primaryContent)
    }

    /// 验证删除 tool 会移除列表项并清空编辑区。
    @Test func deleteToolRemovesResourceAndClearsEditor() async {
        let document = makeDocument(
            kind: .tool,
            id: "ticket-search",
            name: "Ticket Search",
            primaryContent: "id: ticket-search\nentry: index.js\n",
            secondaryContent: "export default async function run() {}\n"
        )
        let recorder = Recorder()
        var state = ResourceFeature.State()
        state.selectedKind = .tool
        state.resources = [document.summary]
        state.populateEditor(with: document)
        let store = TestStore(initialState: state) {
            ResourceFeature()
        } withDependencies: {
            $0.appResourceClient = makeClient(
                deleteResource: { kind, id in
                    recorder.deletedResources.append(DeletedResource(kind: kind, id: id))
                }
            )
        }

        await store.send(.deleteResourceButtonTapped) {
            $0.isDeletingResource = true
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        await store.receive(.deleteResourceSucceeded(kind: .tool, id: "ticket-search")) {
            $0.isDeletingResource = false
            $0.resources = []
            $0.selectedResourceID = nil
            $0.selectedResource = nil
            $0.editorPrimaryContent = ""
            $0.editorResourceName = ""
            $0.editorSecondaryContent = ""
            $0.errorMessage = nil
            $0.successMessage = nil
        }

        #expect(recorder.deletedResources == [
            DeletedResource(kind: .tool, id: "ticket-search"),
        ])
    }

    /// 验证删除失败时清理进行中标记并展示错误。
    @Test func deleteSkillFailureClearsFlagAndStoresError() async {
        let document = makeDocument(kind: .skill, id: "report-writing", name: "Report Writing", primaryContent: "")
        let error = AppResourceClientError("delete failed")
        var state = ResourceFeature.State()
        state.selectedKind = .skill
        state.populateEditor(with: document)
        let store = TestStore(initialState: state) {
            ResourceFeature()
        } withDependencies: {
            $0.appResourceClient = makeClient(
                deleteResource: { _, _ in
                    throw error
                }
            )
        }

        await store.send(.deleteResourceButtonTapped) {
            $0.isDeletingResource = true
            $0.errorMessage = nil
            $0.successMessage = nil
        }
        await store.receive(.deleteResourceFailed(error)) {
            $0.isDeletingResource = false
            $0.errorMessage = "delete failed"
            $0.successMessage = nil
        }
    }

    /// 验证保存 tool 会把 manifest 和入口文件内容传给 dependency。
    @Test func saveToolSendsEditedManifestAndEntry() async {
        let original = makeDocument(
            kind: .tool,
            id: "ticket-search",
            name: "Ticket Search",
            primaryContent: "id: ticket-search\nentry: index.js\n",
            secondaryContent: "old entry\n"
        )
        let saved = makeDocument(
            kind: .tool,
            id: "ticket-search",
            name: "Ticket Search",
            primaryContent: "id: ticket-search\nentry: index.js\nname: Ticket Search\n",
            secondaryContent: "new entry\n"
        )
        let recorder = Recorder()
        var state = ResourceFeature.State()
        state.selectedKind = .tool
        state.populateEditor(with: original)
        state.editorPrimaryContent = saved.primaryContent
        state.editorSecondaryContent = saved.secondaryContent ?? ""

        let store = TestStore(initialState: state) {
            ResourceFeature()
        } withDependencies: {
            $0.appResourceClient = makeClient(
                saveResource: { document in
                    recorder.savedDocuments.append(document)
                    return saved
                }
            )
        }

        await store.send(.saveResourceButtonTapped) {
            $0.isSavingResource = true
            $0.errorMessage = nil
        }
        await store.receive(.saveResourceSucceeded(saved)) {
            $0.isSavingResource = false
            $0.resources = [saved.summary]
            $0.selectedResource = saved
            $0.selectedResourceID = "ticket-search"
            $0.editorPrimaryContent = saved.primaryContent
            $0.editorResourceName = "Ticket Search"
            $0.editorSecondaryContent = saved.secondaryContent ?? ""
            $0.errorMessage = nil
            $0.successMessage = "Ticket Search saved."
        }

        #expect(recorder.savedDocuments.count == 1)
        #expect(recorder.savedDocuments.first?.primaryContent == saved.primaryContent)
        #expect(recorder.savedDocuments.first?.secondaryContent == saved.secondaryContent)
    }

    /// 验证创建失败时清理进行中标记并展示错误。
    @Test func createResourceFailureClearsFlagAndStoresError() async {
        let error = AppResourceClientError("create failed")
        var state = ResourceFeature.State()
        let store = TestStore(initialState: state) {
            ResourceFeature()
        } withDependencies: {
            $0.appResourceClient = makeClient(
                createResource: { _, _, _ in
                    throw error
                }
            )
        }

        await store.send(.createResourceButtonTapped) {
            $0.isCreatingResource = true
            $0.errorMessage = nil
        }
        await store.receive(.createResourceFailed(error)) {
            $0.isCreatingResource = false
            $0.errorMessage = "create failed"
        }
    }

    /// 验证保存失败时清理进行中标记并展示错误。
    @Test func saveResourceFailureClearsFlagAndStoresError() async {
        let document = makeDocument(kind: .knowledge, id: "refund.md", name: "refund", primaryContent: "content")
        let error = AppResourceClientError("save failed")
        var state = ResourceFeature.State()
        state.populateEditor(with: document)
        let store = TestStore(initialState: state) {
            ResourceFeature()
        } withDependencies: {
            $0.appResourceClient = makeClient(
                saveResource: { _ in
                    throw error
                }
            )
        }

        await store.send(.saveResourceButtonTapped) {
            $0.isSavingResource = true
            $0.errorMessage = nil
        }
        await store.receive(.saveResourceFailed(error)) {
            $0.isSavingResource = false
            $0.errorMessage = "save failed"
        }
    }
}

private func makeClient(
    listResources: @escaping @Sendable (AppResourceKind) async throws -> [AppResourceSummary] = { _ in
        throw AppResourceClientError("Unexpected listResources call.")
    },
    loadResource: @escaping @Sendable (AppResourceKind, String) async throws -> AppResourceDocument = { _, _ in
        throw AppResourceClientError("Unexpected loadResource call.")
    },
    createResource: @escaping @Sendable (AppResourceKind, String, String) async throws -> AppResourceDocument = { _, _, _ in
        throw AppResourceClientError("Unexpected createResource call.")
    },
    importSkillDirectory: @escaping @Sendable (String) async throws -> AppResourceDocument = { _ in
        throw AppResourceClientError("Unexpected importSkillDirectory call.")
    },
    saveResource: @escaping @Sendable (AppResourceDocument) async throws -> AppResourceDocument = { _ in
        throw AppResourceClientError("Unexpected saveResource call.")
    },
    deleteResource: @escaping @Sendable (AppResourceKind, String) async throws -> Void = { _, _ in
        throw AppResourceClientError("Unexpected deleteResource call.")
    }
) -> AppResourceClient {
    AppResourceClient(
        listResources: listResources,
        loadResource: loadResource,
        createResource: createResource,
        importSkillDirectory: importSkillDirectory,
        saveResource: saveResource,
        deleteResource: deleteResource
    )
}

private func makeSummary(
    kind: AppResourceKind,
    id: String,
    name: String,
    path: String,
    detail: String? = nil,
    validationMessages: [String] = []
) -> AppResourceSummary {
    AppResourceSummary(
        kind: kind,
        id: id,
        name: name,
        path: path,
        detail: detail ?? path,
        validationMessages: validationMessages
    )
}

private func makeDocument(
    kind: AppResourceKind,
    id: String,
    name: String,
    primaryContent: String,
    secondaryContent: String? = nil,
    validationMessages: [String] = []
) -> AppResourceDocument {
    AppResourceDocument(
        kind: kind,
        id: id,
        name: name,
        path: path(for: kind, id: id),
        primaryContent: primaryContent,
        secondaryContent: secondaryContent,
        validationMessages: validationMessages
    )
}

private func path(for kind: AppResourceKind, id: String) -> String {
    switch kind {
    case .knowledge:
        "library/knowledge/\(id)"
    case .skill:
        "library/skills/\(id)"
    case .tool:
        "library/tools/\(id)"
    }
}

/// `@Sendable` mock closures 中记录调用情况的简单容器。
private final class Recorder: @unchecked Sendable {
    /// createResource 收到的参数。
    var createdResources: [CreatedResource] = []

    /// importSkillDirectory 收到的路径。
    var importedSkillPaths: [String] = []

    /// saveResource 收到的文档。
    var savedDocuments: [AppResourceDocument] = []

    /// deleteResource 收到的资源。
    var deletedResources: [DeletedResource] = []
}

/// createResource 调用记录。
private struct CreatedResource: Equatable, Sendable {
    /// Resource 类型。
    let kind: AppResourceKind

    /// Resource ID。
    let id: String

    /// Resource 名称。
    let name: String
}

/// deleteResource 调用记录。
private struct DeletedResource: Equatable, Sendable {
    /// Resource 类型。
    let kind: AppResourceKind

    /// Resource ID。
    let id: String
}
