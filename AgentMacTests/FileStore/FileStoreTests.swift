import Foundation
import Testing
@testable import AgentMac

/// `FileStore` 模块的行为测试集合。
///
/// 所有测试都使用临时目录作为应用数据根目录，避免读取或写入真实 Application Support 数据。
/// 测试只验证 FileStore 的可观察文件行为和错误契约，不依赖私有实现细节。
struct FileStoreTests {
    /// 验证初始化会创建完整目录布局，并且重复初始化不会覆盖已有设置文件。
    ///
    /// 该测试覆盖 `agents/`、`library/`、`library/knowledge/`、`library/skills/`、
    /// `library/tools/`、`sessions/` 和默认 `settings.yaml` 的创建行为。
    @Test func initializeCreatesLayoutAndPreservesExistingSettings() throws {
        let (store, root) = makeStore()
        defer { removeTemporaryRoot(root) }

        try store.initialize()

        #expect(try store.directoryExists(at: "agents"))
        #expect(try store.directoryExists(at: "library"))
        #expect(try store.directoryExists(at: "library/knowledge"))
        #expect(try store.directoryExists(at: "library/skills"))
        #expect(try store.directoryExists(at: "library/tools"))
        #expect(try store.directoryExists(at: "sessions"))
        #expect(try store.readTextFile(at: "settings.yaml") == FileStore.defaultSettingsYAML)

        try store.writeTextFile("appDataVersion: 2\n", to: "settings.yaml")
        try store.initialize()

        #expect(try store.readTextFile(at: "settings.yaml") == "appDataVersion: 2\n")
    }

    /// 验证文本写入会自动创建父目录，并且文本读取和存在性检查返回正确结果。
    ///
    /// 该测试使用中文内容确认 UTF-8 文本读写路径可用。
    @Test func textReadWriteCreatesParentsAndReportsExistence() throws {
        let (store, root) = makeStore()
        defer { removeTemporaryRoot(root) }

        try store.writeTextFile("退款规则", to: "library/knowledge/policies/refund.md")

        #expect(try store.fileExists(at: "library/knowledge/policies/refund.md"))
        #expect(try store.directoryExists(at: "library/knowledge/policies"))
        #expect(try store.readTextFile(at: "library/knowledge/policies/refund.md") == "退款规则")
    }

    /// 验证删除普通文件会移除目标文件，并保留目录删除边界。
    @Test func deleteFileRemovesOnlyRegularFiles() throws {
        let (store, root) = makeStore()
        defer { removeTemporaryRoot(root) }

        try store.writeTextFile("session", to: "sessions/session-1.json")
        try store.deleteFile(at: "sessions/session-1.json")

        #expect(try !store.fileExists(at: "sessions/session-1.json"))

        do {
            try store.deleteFile(at: "sessions")
            Issue.record("Expected directory deletion to be rejected.")
        } catch let FileStoreError.fileNotFound(path) {
            #expect(path == "sessions")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证删除目录会移除整棵子树，并拒绝把普通文件当目录删除。
    @Test func deleteDirectoryRemovesTreeAndRejectsFiles() throws {
        let (store, root) = makeStore()
        defer { removeTemporaryRoot(root) }

        try store.writeTextFile("skill", to: "library/skills/report-writing/SKILL.md")
        try store.writeTextFile("guide", to: "library/skills/report-writing/references/guide.md")
        try store.deleteDirectory(at: "library/skills/report-writing")

        #expect(try !store.directoryExists(at: "library/skills/report-writing"))

        try store.writeTextFile("not a directory", to: "library/skills/plain-file")
        do {
            try store.deleteDirectory(at: "library/skills/plain-file")
            Issue.record("Expected file deletion through deleteDirectory to be rejected.")
        } catch let FileStoreError.directoryNotFound(path) {
            #expect(path == "library/skills/plain-file")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证目录移动会保留整棵子树，并拒绝覆盖已有目标目录。
    @Test func moveDirectoryMovesTreeAndRejectsExistingDestination() throws {
        let (store, root) = makeStore()
        defer { removeTemporaryRoot(root) }

        try store.writeTextFile("skill", to: "library/skills/draft-skill/SKILL.md")
        try store.writeTextFile("guide", to: "library/skills/draft-skill/references/guide.md")
        try store.moveDirectory(from: "library/skills/draft-skill", to: "library/skills/report-writing")

        #expect(try !store.directoryExists(at: "library/skills/draft-skill"))
        #expect(try store.readTextFile(at: "library/skills/report-writing/SKILL.md") == "skill")
        #expect(try store.readTextFile(at: "library/skills/report-writing/references/guide.md") == "guide")

        try store.writeTextFile("existing", to: "library/skills/existing-skill/SKILL.md")
        do {
            try store.moveDirectory(from: "library/skills/report-writing", to: "library/skills/existing-skill")
            Issue.record("Expected existing destination to be rejected.")
        } catch let FileStoreError.writeFailed(path, reason) {
            #expect(path == "library/skills/existing-skill")
            #expect(reason.contains("already exists"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证外部目录可以递归复制到 app data 内，且不会覆盖已有目录。
    @Test func copyDirectoryCopiesExternalTreeWithoutOverwriting() throws {
        let (store, root) = makeStore()
        let source = FileManager.default.temporaryDirectory
            .appending(path: "AgentMac-FileStoreExternal-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            removeTemporaryRoot(root)
            removeTemporaryRoot(source)
        }

        try store.initialize()
        try createDirectory(source.appending(path: "references", directoryHint: .isDirectory))
        try "skill".write(to: source.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        try "guide".write(to: source.appending(path: "references/guide.md"), atomically: true, encoding: .utf8)

        try store.copyDirectory(from: source, to: "library/skills/imported-skill")

        #expect(try store.readTextFile(at: "library/skills/imported-skill/SKILL.md") == "skill")
        #expect(try store.readTextFile(at: "library/skills/imported-skill/references/guide.md") == "guide")

        do {
            try store.copyDirectory(from: source, to: "library/skills/imported-skill")
            Issue.record("Expected existing destination to be rejected.")
        } catch let FileStoreError.writeFailed(path, reason) {
            #expect(path == "library/skills/imported-skill")
            #expect(reason.contains("already exists"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证 YAML 读写入口会使用调用方提供的编码和解码闭包。
    ///
    /// FileStore 不绑定具体 YAML 库，因此测试只确认闭包参与读写流程。
    @Test func yamlReadWriteUsesCallerProvidedCodec() throws {
        let (store, root) = makeStore()
        defer { removeTemporaryRoot(root) }

        try store.writeYAMLFile(7, to: "settings.yaml") { value in
            "appDataVersion: \(value)\n"
        }

        let version = try store.readYAMLFile(at: "settings.yaml") { text in
            try #require(Int(text.replacing("appDataVersion: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        #expect(version == 7)
    }

    /// 验证 YAML 编解码闭包抛出的错误会映射为 FileStore 的 YAML 错误。
    ///
    /// 该测试区分结构定义或编解码失败和普通文件 I/O 失败，确保上层模块可以做不同错误处理。
    @Test func yamlCodecFailuresAreWrapped() throws {
        let (store, root) = makeStore()
        defer { removeTemporaryRoot(root) }

        try store.writeTextFile("invalid", to: "settings.yaml")

        do {
            let _: Int = try store.readYAMLFile(at: "settings.yaml") { _ in
                throw FileStoreError.invalidPath(path: "settings.yaml", reason: "invalid app data version")
            }
            Issue.record("Expected YAML decode failure to be wrapped.")
        } catch let FileStoreError.yamlReadFailed(path, reason) {
            #expect(path == "settings.yaml")
            #expect(reason.contains("invalid app data version"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            try store.writeYAMLFile(1, to: "settings.yaml") { _ in
                throw FileStoreError.invalidPath(path: "settings.yaml", reason: "cannot encode")
            }
            Issue.record("Expected YAML encode failure to be wrapped.")
        } catch let FileStoreError.yamlWriteFailed(path, reason) {
            #expect(path == "settings.yaml")
            #expect(reason.contains("cannot encode"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证一级子目录扫描会过滤隐藏条目和普通文件，并按目录名稳定排序。
    ///
    /// 该行为供 Agent 列表和资源库列表等上层模块复用。
    @Test func listDirectoriesFiltersHiddenEntriesAndSorts() throws {
        let (store, root) = makeStore()
        defer { removeTemporaryRoot(root) }

        try store.initialize()
        try createDirectory(root.appending(path: "agents/bravo", directoryHint: .isDirectory))
        try createDirectory(root.appending(path: "agents/alpha", directoryHint: .isDirectory))
        try createDirectory(root.appending(path: "agents/.hidden", directoryHint: .isDirectory))
        try store.writeTextFile("not a directory", to: "agents/readme.md")

        let names = try store.listDirectories(at: "agents").map(\.lastPathComponent)

        #expect(names == ["alpha", "bravo"])
    }

    /// 验证扫描不存在的目录时会返回可诊断的 `directoryNotFound` 错误。
    ///
    /// 该测试确保上层模块可以区分“目录不存在”和“目录存在但为空”。
    @Test func listDirectoriesReportsMissingDirectory() throws {
        let (store, root) = makeStore()
        defer { removeTemporaryRoot(root) }

        do {
            _ = try store.listDirectories(at: "agents")
            Issue.record("Expected missing directory to throw.")
        } catch let FileStoreError.directoryNotFound(path) {
            #expect(path == "agents")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证一级文件扫描会过滤隐藏文件、`.DS_Store`、目录和不匹配扩展名的文件。
    ///
    /// 该测试同时覆盖扩展名大小写不敏感和可带前导点的匹配规则。
    @Test func listFilesFiltersHiddenEntriesByExtensionAndSorts() throws {
        let (store, root) = makeStore()
        defer { removeTemporaryRoot(root) }

        try store.initialize()
        try store.writeTextFile("b", to: "library/knowledge/b.MD")
        try store.writeTextFile("a", to: "library/knowledge/a.txt")
        try store.writeTextFile("hidden", to: "library/knowledge/.secret.md")
        try store.writeTextFile("metadata", to: "library/knowledge/.DS_Store")
        try store.writeTextFile("json", to: "library/knowledge/c.json")
        try createDirectory(root.appending(path: "library/knowledge/folder.md", directoryHint: .isDirectory))

        let names = try store
            .listFiles(at: "library/knowledge", matchingExtensions: ["MD", ".txt"])
            .map(\.lastPathComponent)

        #expect(names == ["a.txt", "b.MD"])
    }

    /// 验证文件存在性和目录存在性检查不会互相混淆。
    ///
    /// 普通文件只应被 `fileExists` 识别，目录只应被 `directoryExists` 识别。
    @Test func existenceChecksDistinguishFilesAndDirectories() throws {
        let (store, root) = makeStore()
        defer { removeTemporaryRoot(root) }

        try store.initialize()
        try store.writeTextFile("notes", to: "library/knowledge/readme.md")

        #expect(try store.fileExists(at: "library/knowledge/readme.md"))
        #expect(try !store.directoryExists(at: "library/knowledge/readme.md"))
        #expect(try !store.fileExists(at: "library/knowledge"))
        #expect(try store.directoryExists(at: "library/knowledge"))
    }

    /// 验证 `..` 路径逃逸会被安全路径解析拒绝。
    ///
    /// 该测试覆盖最重要的应用数据根目录边界保护。
    @Test func resolveAppDataPathRejectsPathEscapes() throws {
        let (store, root) = makeStore()
        defer { removeTemporaryRoot(root) }

        do {
            _ = try store.resolveAppDataPath("../../outside.txt")
            Issue.record("Expected path escape to be rejected.")
        } catch let FileStoreError.invalidPath(path, reason) {
            #expect(path == "../../outside.txt")
            #expect(reason.contains("escapes"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证空路径、绝对路径和包含 null byte 的路径都会被拒绝。
    ///
    /// 这些输入在 URL 解析前就不满足 FileStore 的相对路径契约。
    @Test func resolveAppDataPathRejectsAbsoluteEmptyAndNullPaths() throws {
        let (store, root) = makeStore()
        defer { removeTemporaryRoot(root) }

        do {
            _ = try store.resolveAppDataPath("")
            Issue.record("Expected empty path to be rejected.")
        } catch let FileStoreError.invalidPath(path, reason) {
            #expect(path == "")
            #expect(reason.contains("empty"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            _ = try store.resolveAppDataPath("/tmp/outside.txt")
            Issue.record("Expected absolute path to be rejected.")
        } catch let FileStoreError.invalidPath(path, reason) {
            #expect(path == "/tmp/outside.txt")
            #expect(reason.contains("relative"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            _ = try store.resolveAppDataPath("bad\u{0}path")
            Issue.record("Expected null byte path to be rejected.")
        } catch let FileStoreError.invalidPath(path, reason) {
            #expect(path == "bad\u{0}path")
            #expect(reason.contains("null"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证中间路径组件为符号链接时，解析后逃逸应用数据根目录的路径会被拒绝。
    ///
    /// 该测试覆盖写入新文件前的路径安全场景：最终文件不存在时也必须解析已存在的符号链接组件。
    @Test func resolveAppDataPathRejectsSymlinkEscape() throws {
        let (store, root) = makeStore()
        defer { removeTemporaryRoot(root) }

        try store.initialize()
        let outsideDirectory = root.deletingLastPathComponent()
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "library/knowledge/link", directoryHint: .isDirectory),
            withDestinationURL: outsideDirectory
        )

        do {
            _ = try store.resolveAppDataPath("library/knowledge/link/outside.md")
            Issue.record("Expected symlink escape to be rejected.")
        } catch let FileStoreError.invalidPath(path, reason) {
            #expect(path == "library/knowledge/link/outside.md")
            #expect(reason.contains("escapes"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 验证读取不存在的文件会返回 `fileNotFound`，而不是泛化为普通读取失败。
    ///
    /// 该行为让上层模块可以给用户提供更准确的缺失文件诊断。
    @Test func readMissingFileReportsFileNotFound() throws {
        let (store, root) = makeStore()
        defer { removeTemporaryRoot(root) }

        do {
            _ = try store.readTextFile(at: "missing.md")
            Issue.record("Expected missing file to throw.")
        } catch let FileStoreError.fileNotFound(path) {
            #expect(path == "missing.md")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// 创建一个使用唯一临时根目录的 FileStore。
    ///
    /// - Returns: 可用于测试的 FileStore，以及测试结束后需要删除的临时根目录。
    private func makeStore() -> (FileStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AgentMac-FileStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (FileStore(rootDirectory: root), root)
    }

    /// 创建测试用目录。
    ///
    /// - Parameter url: 要创建的绝对目录 URL。
    private func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// 删除测试创建的临时根目录。
    ///
    /// 清理失败不应影响测试断言，因此这里忽略删除错误。
    ///
    /// - Parameter root: `makeStore()` 返回的临时根目录。
    private func removeTemporaryRoot(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }
}
