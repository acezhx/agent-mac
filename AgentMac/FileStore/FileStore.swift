import Foundation

/// AgentMac 可变用户数据的标准磁盘布局。
///
/// `FileStore` 是 Swift 侧唯一应该直接理解 Application Support 目录结构的模块。
/// 上层模块需要通过 `FileStore` 完成文件操作，不应该自行拼接或复制这些路径规则。
nonisolated struct AppDataLayout {
    /// AgentMac 在用户 Application Support 下使用的目录名。
    ///
    /// 生产环境根目录为 `~/Library/Application Support/AgentMac`。测试环境可以通过
    /// `FileStore.init(rootDirectory:fileManager:)` 注入临时目录，不依赖真实用户数据。
    static let applicationDirectoryName = "AgentMac"

    /// 当前布局对应的绝对根目录。
    ///
    /// 所有 Agent、资源库、会话和设置文件路径都从该目录派生。该属性只保存路径值，
    /// 不会主动创建目录；目录创建由 `FileStore.initialize()` 负责。
    let rootDirectory: URL

    /// 创建一个以指定根目录为基础的数据布局。
    ///
    /// - Parameter rootDirectory: Application Support 根目录或测试用临时根目录。
    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory.standardizedFileURL
    }

    /// Agent 目录，保存每个 Agent 的私有配置目录。
    var agentsDirectory: URL {
        rootDirectory.appendingPathComponent("agents", isDirectory: true)
    }

    /// 共享资源库根目录，包含 knowledge、skills 和 tools。
    var libraryDirectory: URL {
        rootDirectory.appendingPathComponent("library", isDirectory: true)
    }

    /// 共享 knowledge 文件目录。
    var knowledgeDirectory: URL {
        libraryDirectory.appendingPathComponent("knowledge", isDirectory: true)
    }

    /// 共享 skill 目录集合。
    var skillsDirectory: URL {
        libraryDirectory.appendingPathComponent("skills", isDirectory: true)
    }

    /// 共享 tool 目录集合。
    var toolsDirectory: URL {
        libraryDirectory.appendingPathComponent("tools", isDirectory: true)
    }

    /// 会话数据目录。
    var sessionsDirectory: URL {
        rootDirectory.appendingPathComponent("sessions", isDirectory: true)
    }

    /// 运行时和应用诊断日志目录。
    var logsDirectory: URL {
        rootDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    /// 应用级设置文件路径。
    ///
    /// `settings.yaml` 不保存 Agent 定义，只保存应用级配置。默认内容由
    /// `FileStore.defaultSettingsYAML` 提供。
    var settingsFile: URL {
        rootDirectory.appendingPathComponent("settings.yaml", isDirectory: false)
    }

    /// FileStore 初始化时必须存在的目录集合。
    ///
    /// 返回值包含根目录本身以及第一版需要的 agents、library、knowledge、skills、
    /// tools、sessions、logs 目录。顺序保持从父目录到子目录，便于创建目录时保持清晰。
    var requiredDirectories: [URL] {
        [
            rootDirectory,
            agentsDirectory,
            libraryDirectory,
            knowledgeDirectory,
            skillsDirectory,
            toolsDirectory,
            sessionsDirectory,
            logsDirectory,
        ]
    }
}

/// FileStore 文件持久化边界的结构化错误。
///
/// 错误尽量携带调用方传入的相对路径和可诊断原因，让上层模块可以直接展示或记录问题，
/// 而不需要理解底层 Foundation 错误类型。
nonisolated enum FileStoreError: Error, Equatable {
    /// 无法解析用户 Application Support 目录。
    ///
    /// 关联值保存底层系统错误的文本原因。
    case applicationSupportDirectoryUnavailable(String)

    /// 调用方传入了非法路径。
    ///
    /// `path` 是原始输入路径，`reason` 描述路径为空、绝对路径、包含 null byte 或越界等原因。
    case invalidPath(path: String, reason: String)

    /// 期望读取的文件不存在，或该路径不是普通文件。
    case fileNotFound(path: String)

    /// 期望扫描的目录不存在，或该路径不是目录。
    case directoryNotFound(path: String)

    /// 文件读取失败。
    ///
    /// 该错误用于已通过路径校验和存在性检查后仍然读取失败的场景。
    case readFailed(path: String, reason: String)

    /// 文件或目录写入失败。
    ///
    /// 该错误覆盖创建目录、写入文本文件、删除文件和默认设置文件失败等持久化问题。
    case writeFailed(path: String, reason: String)

    /// YAML 读取入口中的调用方解码失败。
    ///
    /// FileStore 不解析 YAML 结构定义；该错误用于把调用方解码失败与普通文件读取失败区分开。
    case yamlReadFailed(path: String, reason: String)

    /// YAML 写入入口中的调用方编码失败。
    ///
    /// FileStore 不选择具体 YAML 编码库；该错误用于把调用方编码失败与普通文件写入失败区分开。
    case yamlWriteFailed(path: String, reason: String)
}

extension FileStoreError: LocalizedError {
    /// 面向日志和 UI 诊断的错误描述。
    ///
    /// 当前描述保持稳定、直接，包含路径和原因。上层模块如果需要本地化展示，可以基于
    /// `FileStoreError` 的 case 自行映射。
    var errorDescription: String? {
        switch self {
        case let .applicationSupportDirectoryUnavailable(reason):
            "Unable to resolve Application Support directory: \(reason)"
        case let .invalidPath(path, reason):
            "Invalid path '\(path)': \(reason)"
        case let .fileNotFound(path):
            "File not found: \(path)"
        case let .directoryNotFound(path):
            "Directory not found: \(path)"
        case let .readFailed(path, reason):
            "Failed to read '\(path)': \(reason)"
        case let .writeFailed(path, reason):
            "Failed to write '\(path)': \(reason)"
        case let .yamlReadFailed(path, reason):
            "Failed to read YAML '\(path)': \(reason)"
        case let .yamlWriteFailed(path, reason):
            "Failed to write YAML '\(path)': \(reason)"
        }
    }
}

/// AgentMac Application Support 数据树的底层文件服务。
///
/// `FileStore` 负责目录初始化、UTF-8 文本读写、YAML 读写入口、一级目录扫描和安全相对路径解析。
/// 它不理解 Agent、Resource、Session 或 Runtime 的业务含义，也不负责校验这些文件代表的业务对象。
///
/// 应用构建目标当前开启了默认 MainActor 隔离，但 `FileStore` 没有 UI 状态，也不持有共享可变状态，
/// 因此显式声明为 `nonisolated`，便于测试和后续后台服务直接调用。
nonisolated struct FileStore {
    /// 新数据目录中默认创建的 `settings.yaml` 内容。
    ///
    /// 默认内容写入当前 app data 版本号和 app 级默认设置。重复初始化不会覆盖用户已修改或后续模块已扩展的设置文件。
    static let defaultSettingsYAML = """
    appDataVersion: 1
    lastWorkspace: null

    runtime:
      useBundledRuntime: true

    agent:
      allowedModelProviders:
        - "openai"
    """

    /// 当前 FileStore 实例使用的数据目录布局。
    ///
    /// 所有对外文件操作都通过该布局解析到同一个应用数据根目录，避免不同模块各自维护路径规则。
    let layout: AppDataLayout

    /// 实际执行文件系统操作的 Foundation 文件管理器。
    ///
    /// 默认使用 `.default`；测试可以注入自定义实例。FileStore 不在该对象之外维护文件状态缓存。
    private let fileManager: FileManager

    /// 创建一个以调用方指定根目录为边界的 FileStore。
    ///
    /// - Parameters:
    ///   - rootDirectory: 应用数据根目录。生产代码通常不直接传入该值，测试应传入临时目录。
    ///   - fileManager: 文件系统操作对象，默认使用 `FileManager.default`。
    init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.layout = AppDataLayout(rootDirectory: rootDirectory)
        self.fileManager = fileManager
    }

    /// 创建生产环境 FileStore，根目录位于用户 Application Support 下。
    ///
    /// 该初始化只解析路径，不创建目录。调用方在写入前应先调用 `initialize()`。
    ///
    /// - Parameter fileManager: 文件系统操作对象，默认使用 `FileManager.default`。
    /// - Throws: 无法解析 Application Support 目录时抛出 `FileStoreError.applicationSupportDirectoryUnavailable`。
    init(fileManager: FileManager = .default) throws {
        self.init(rootDirectory: try Self.defaultRootDirectory(fileManager: fileManager), fileManager: fileManager)
    }

    /// 解析生产环境 AgentMac Application Support 根目录。
    ///
    /// 该方法不会创建目录，只返回标准化后的根目录 URL。目录创建由 `initialize()` 统一负责。
    ///
    /// - Parameter fileManager: 用于查询系统目录的文件管理器。
    /// - Returns: `~/Library/Application Support/AgentMac` 对应的标准化 URL。
    /// - Throws: 无法从系统查询 Application Support 目录时抛出 FileStore 错误。
    static func defaultRootDirectory(fileManager: FileManager = .default) throws -> URL {
        do {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            return applicationSupport
                .appendingPathComponent(AppDataLayout.applicationDirectoryName, isDirectory: true)
                .standardizedFileURL
        } catch {
            throw FileStoreError.applicationSupportDirectoryUnavailable(error.localizedDescription)
        }
    }

    /// 初始化 app data 根目录、基础子目录和默认设置文件。
    ///
    /// 该操作是幂等的：目录已存在时不会失败，`settings.yaml` 已存在时不会覆盖已有内容。
    ///
    /// - Throws: 任一目录创建失败或默认设置文件写入失败时抛出 `FileStoreError.writeFailed`。
    func initialize() throws {
        for directory in layout.requiredDirectories {
            try createDirectory(directory)
        }

        if !fileManager.fileExists(atPath: layout.settingsFile.path) {
            try writeText(FileStore.defaultSettingsYAML, to: layout.settingsFile)
        }
    }

    /// 将 app data 相对路径解析为安全的绝对 URL。
    ///
    /// 该方法是 FileStore 的路径安全边界。调用方必须传入非空相对路径；绝对路径、包含 null byte
    /// 的路径，以及标准化或解析符号链接后会逃逸应用数据根目录的路径都会被拒绝。
    ///
    /// - Parameter relativePath: 相对于应用数据根目录的路径。
    /// - Returns: 位于应用数据根目录内部的绝对 URL。
    /// - Throws: 路径非法或逃逸根目录时抛出 `FileStoreError.invalidPath`。
    func resolveAppDataPath(_ relativePath: String) throws -> URL {
        try validateRelativePath(relativePath)

        let root = layout.rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        let resolved = resolveExistingSymlinks(in: candidate, root: root)

        let rootPath = root.path
        let resolvedPath = resolved.path
        guard resolvedPath == rootPath || resolvedPath.hasPrefix(rootPath + "/") else {
            throw FileStoreError.invalidPath(path: relativePath, reason: "Path escapes the app data directory.")
        }

        return resolved
    }

    /// 读取 app data 内的 UTF-8 文本文件。
    ///
    /// 读取前会先执行安全路径解析，并确认目标是普通文件。
    ///
    /// - Parameter relativePath: 相对于应用数据根目录的文件路径。
    /// - Returns: 文件中的 UTF-8 文本。
    /// - Throws: 文件不存在时抛出 `fileNotFound`；读取或解码失败时抛出 `readFailed`。
    func readTextFile(at relativePath: String) throws -> String {
        let url = try resolveAppDataPath(relativePath)
        guard fileExists(at: url) else {
            throw FileStoreError.fileNotFound(path: relativePath)
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw FileStoreError.readFailed(path: relativePath, reason: error.localizedDescription)
        }
    }

    /// 写入 app data 内的 UTF-8 文本文件。
    ///
    /// 写入前会先完成路径安全校验；父目录会自动创建；目标文件已存在时会被覆盖。
    ///
    /// - Parameters:
    ///   - contents: 要写入的 UTF-8 文本内容。
    ///   - relativePath: 相对于应用数据根目录的目标文件路径。
    /// - Throws: 路径非法时抛出 `invalidPath`；创建目录或写入失败时抛出 `writeFailed`。
    func writeTextFile(_ contents: String, to relativePath: String) throws {
        let url = try resolveAppDataPath(relativePath)
        try writeText(contents, to: url)
    }

    /// 删除 app data 内的普通文件。
    ///
    /// 删除前会先执行安全路径解析，并确认目标是普通文件。该方法不删除目录，避免上层模块误删
    /// 一整棵应用数据子树。
    ///
    /// - Parameter relativePath: 相对于应用数据根目录的文件路径。
    /// - Throws: 文件不存在时抛出 `fileNotFound`；删除失败时抛出 `writeFailed`。
    func deleteFile(at relativePath: String) throws {
        let url = try resolveAppDataPath(relativePath)
        guard fileExists(at: url) else {
            throw FileStoreError.fileNotFound(path: relativePath)
        }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw FileStoreError.writeFailed(path: relativePath, reason: error.localizedDescription)
        }
    }

    /// 删除 app data 内的目录及其全部内容。
    ///
    /// 删除前会先执行安全路径解析，并确认目标是目录。该方法用于上层模块删除目录型资源；
    /// 普通文件仍应使用 `deleteFile(at:)`，避免调用方混淆资源边界。
    ///
    /// - Parameter relativePath: 相对于应用数据根目录的目录路径。
    /// - Throws: 目录不存在时抛出 `directoryNotFound`；删除失败时抛出 `writeFailed`。
    func deleteDirectory(at relativePath: String) throws {
        let url = try resolveAppDataPath(relativePath)
        guard directoryExists(at: url) else {
            throw FileStoreError.directoryNotFound(path: relativePath)
        }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw FileStoreError.writeFailed(path: relativePath, reason: error.localizedDescription)
        }
    }

    /// 移动 app data 内的目录及其全部内容。
    ///
    /// 该方法用于上层模块重命名目录型资源。源目录和目标目录都会通过 app data 安全边界解析；
    /// 目标目录已存在时拒绝覆盖，避免重命名操作误改已有资源。
    ///
    /// - Parameters:
    ///   - sourceRelativePath: 相对于应用数据根目录的源目录路径。
    ///   - destinationRelativePath: 相对于应用数据根目录的目标目录路径。
    /// - Throws: 源目录不存在、目标已存在或移动失败时抛出 FileStore 错误。
    func moveDirectory(from sourceRelativePath: String, to destinationRelativePath: String) throws {
        let source = try resolveAppDataPath(sourceRelativePath)
        guard directoryExists(at: source) else {
            throw FileStoreError.directoryNotFound(path: sourceRelativePath)
        }

        let destination = try resolveAppDataPath(destinationRelativePath)
        guard source.path != destination.path else {
            return
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw FileStoreError.writeFailed(path: destinationRelativePath, reason: "Destination already exists.")
        }

        try createDirectory(destination.deletingLastPathComponent())
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            throw FileStoreError.writeFailed(path: destinationRelativePath, reason: error.localizedDescription)
        }
    }

    /// 将外部目录递归复制到 app data 内。
    ///
    /// 该方法用于导入用户选择的本地资源目录。目标路径仍通过 app data 安全边界解析；
    /// 目标目录已存在时不会覆盖，避免导入操作误改已有资源。
    ///
    /// - Parameters:
    ///   - sourceDirectory: app data 外部或内部的源目录 URL。
    ///   - relativePath: 相对于应用数据根目录的目标目录路径。
    /// - Throws: 源目录不存在时抛出 `directoryNotFound`；目标路径非法或复制失败时抛出 FileStore 错误。
    func copyDirectory(from sourceDirectory: URL, to relativePath: String) throws {
        let source = sourceDirectory.standardizedFileURL
        guard directoryExists(at: source) else {
            throw FileStoreError.directoryNotFound(path: source.path)
        }

        let destination = try resolveAppDataPath(relativePath)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw FileStoreError.writeFailed(path: relativePath, reason: "Destination already exists.")
        }

        try createDirectory(destination.deletingLastPathComponent())
        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw FileStoreError.writeFailed(path: relativePath, reason: error.localizedDescription)
        }
    }

    /// 读取 YAML 文件文本，并把实际 YAML 解码委托给调用方。
    ///
    /// FileStore 不绑定具体 YAML 库，也不理解上层结构定义。它只提供安全文件读取和错误包装。
    ///
    /// - Parameters:
    ///   - relativePath: 相对于应用数据根目录的 YAML 文件路径。
    ///   - decode: 调用方提供的 YAML 文本解码闭包。
    /// - Returns: 调用方解码后的值。
    /// - Throws: 文件读取错误按文本读取规则抛出；解码闭包抛错时包装为 `yamlReadFailed`。
    func readYAMLFile<Value>(at relativePath: String, decode: (String) throws -> Value) throws -> Value {
        let text = try readTextFile(at: relativePath)
        do {
            return try decode(text)
        } catch {
            throw FileStoreError.yamlReadFailed(path: relativePath, reason: error.localizedDescription)
        }
    }

    /// 将调用方提供的值编码为 YAML 文本，并安全写入 app data。
    ///
    /// FileStore 只负责调用编码闭包和写入文本，不校验 YAML 结构定义。
    ///
    /// - Parameters:
    ///   - value: 要写入的业务值。
    ///   - relativePath: 相对于应用数据根目录的目标 YAML 文件路径。
    ///   - encode: 调用方提供的 YAML 文本编码闭包。
    /// - Throws: 编码闭包抛错时包装为 `yamlWriteFailed`；文件写入错误按文本写入规则抛出。
    func writeYAMLFile<Value>(_ value: Value, to relativePath: String, encode: (Value) throws -> String) throws {
        let text: String
        do {
            text = try encode(value)
        } catch {
            throw FileStoreError.yamlWriteFailed(path: relativePath, reason: error.localizedDescription)
        }

        try writeTextFile(text, to: relativePath)
    }

    /// 检查 app data 相对路径是否存在且为普通文件。
    ///
    /// - Parameter relativePath: 相对于应用数据根目录的路径。
    /// - Returns: 路径存在且不是目录时返回 `true`，不存在或是目录时返回 `false`。
    /// - Throws: 路径非法或逃逸根目录时抛出 `invalidPath`。
    func fileExists(at relativePath: String) throws -> Bool {
        fileExists(at: try resolveAppDataPath(relativePath))
    }

    /// 检查 app data 相对路径是否存在且为目录。
    ///
    /// - Parameter relativePath: 相对于应用数据根目录的路径。
    /// - Returns: 路径存在且是目录时返回 `true`，不存在或是普通文件时返回 `false`。
    /// - Throws: 路径非法或逃逸根目录时抛出 `invalidPath`。
    func directoryExists(at relativePath: String) throws -> Bool {
        directoryExists(at: try resolveAppDataPath(relativePath))
    }

    /// 列出指定 app data 目录下的可见一级子目录。
    ///
    /// 该方法不会递归扫描。隐藏目录、`.DS_Store` 和普通文件会被过滤；结果按目录名稳定排序。
    ///
    /// - Parameter relativePath: 相对于应用数据根目录的目录路径。
    /// - Returns: 排序后的一级子目录 URL 列表。
    /// - Throws: 路径不存在或不是目录时抛出 `directoryNotFound`；读取目录失败时抛出 `readFailed`。
    func listDirectories(at relativePath: String) throws -> [URL] {
        let directory = try resolveAppDataPath(relativePath)
        guard directoryExists(at: directory) else {
            throw FileStoreError.directoryNotFound(path: relativePath)
        }

        return try directoryContents(of: directory, requestedPath: relativePath)
            .filter { isVisibleFile($0) && directoryExists(at: $0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// 列出指定 app data 目录下匹配扩展名的可见一级文件。
    ///
    /// 该方法不会递归扫描。扩展名过滤大小写不敏感，调用方传入的扩展名可以带点或不带点。
    /// 隐藏文件、`.DS_Store` 和目录会被过滤；结果按文件名稳定排序。
    ///
    /// - Parameters:
    ///   - relativePath: 相对于应用数据根目录的目录路径。
    ///   - extensions: 允许的文件扩展名集合，例如 `["md", ".txt"]`。
    /// - Returns: 排序后的一级文件 URL 列表。
    /// - Throws: 路径不存在或不是目录时抛出 `directoryNotFound`；读取目录失败时抛出 `readFailed`。
    func listFiles(at relativePath: String, matchingExtensions extensions: Set<String>) throws -> [URL] {
        let directory = try resolveAppDataPath(relativePath)
        guard directoryExists(at: directory) else {
            throw FileStoreError.directoryNotFound(path: relativePath)
        }

        let normalizedExtensions = Set(extensions.map { normalizedFileExtension($0) })
        return try directoryContents(of: directory, requestedPath: relativePath)
            .filter { url in
                isVisibleFile(url)
                    && fileExists(at: url)
                    && normalizedExtensions.contains(url.pathExtension.lowercased())
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// 在 URL 标准化前校验路径字符串层面的基本契约。
    ///
    /// - Parameter path: 调用方传入的原始相对路径。
    /// - Throws: 路径为空、包含 null byte 或是绝对路径时抛出 `invalidPath`。
    private func validateRelativePath(_ path: String) throws {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FileStoreError.invalidPath(path: path, reason: "Path cannot be empty.")
        }
        guard !path.contains("\0") else {
            throw FileStoreError.invalidPath(path: path, reason: "Path cannot contain null bytes.")
        }
        guard !(path as NSString).isAbsolutePath else {
            throw FileStoreError.invalidPath(path: path, reason: "Path must be relative to the app data directory.")
        }
    }

    /// 创建目录及其缺失的父目录。
    ///
    /// - Parameter directory: 要创建的绝对目录 URL。
    /// - Throws: 创建失败时抛出 `writeFailed`。
    private func createDirectory(_ directory: URL) throws {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw FileStoreError.writeFailed(path: directory.path, reason: error.localizedDescription)
        }
    }

    /// 将 UTF-8 文本写入绝对文件 URL。
    ///
    /// 该方法假设调用方已完成路径安全校验。它会创建父目录，并以原子写方式覆盖目标文件。
    ///
    /// - Parameters:
    ///   - contents: 要写入的文本内容。
    ///   - url: 已解析的绝对目标文件 URL。
    /// - Throws: 父目录创建或文件写入失败时抛出 `writeFailed`。
    private func writeText(_ contents: String, to url: URL) throws {
        let parentDirectory = url.deletingLastPathComponent()
        try createDirectory(parentDirectory)

        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw FileStoreError.writeFailed(path: url.path, reason: error.localizedDescription)
        }
    }

    /// 读取指定目录的一级内容。
    ///
    /// - Parameters:
    ///   - directory: 已解析的绝对目录 URL。
    ///   - requestedPath: 调用方原始相对路径，用于错误报告。
    /// - Returns: 目录下的一级 URL 列表。
    /// - Throws: 目录读取失败时抛出 `readFailed`。
    private func directoryContents(of directory: URL, requestedPath: String) throws -> [URL] {
        do {
            return try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isHiddenKey],
                options: []
            )
        } catch {
            throw FileStoreError.readFailed(path: requestedPath, reason: error.localizedDescription)
        }
    }

    /// 解析路径中每一个已存在组件的符号链接。
    ///
    /// Foundation 的 `resolvingSymlinksInPath()` 在目标文件尚未创建时，不总能捕获中间组件的
    /// 符号链接逃逸。FileStore 需要在写入新文件前也能拒绝这种逃逸，因此从可信根目录开始逐段解析。
    ///
    /// - Parameters:
    ///   - url: 已拼接并标准化的候选绝对 URL。
    ///   - root: 已标准化并解析符号链接的应用数据根目录。
    /// - Returns: 尽可能解析已有组件符号链接后的 URL。
    private func resolveExistingSymlinks(in url: URL, root: URL) -> URL {
        let candidate = url.standardizedFileURL
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents

        guard candidateComponents.starts(with: rootComponents) else {
            return candidate.resolvingSymlinksInPath()
        }

        var resolved = root
        let relativeComponents = candidateComponents.dropFirst(rootComponents.count)
        for (index, component) in relativeComponents.enumerated() {
            resolved.appendPathComponent(component)

            if fileManager.fileExists(atPath: resolved.path) {
                resolved = resolved.resolvingSymlinksInPath()
                continue
            }

            for remainingComponent in relativeComponents.dropFirst(index + 1) {
                resolved.appendPathComponent(remainingComponent)
            }
            return resolved.standardizedFileURL
        }

        return resolved.standardizedFileURL
    }

    /// 检查绝对 URL 是否存在且为普通文件。
    ///
    /// - Parameter url: 已解析的绝对 URL。
    /// - Returns: 存在且不是目录时返回 `true`。
    private func fileExists(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    /// 检查绝对 URL 是否存在且为目录。
    ///
    /// - Parameter url: 已解析的绝对 URL。
    /// - Returns: 存在且是目录时返回 `true`。
    private func directoryExists(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// 判断目录扫描结果是否应作为可见条目返回。
    ///
    /// - Parameter url: 目录扫描得到的一级 URL。
    /// - Returns: 非隐藏文件系统条目且名称不是 `.DS_Store` 时返回 `true`。
    private func isVisibleFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard name != ".DS_Store", !name.hasPrefix(".") else {
            return false
        }

        return ((try? url.resourceValues(forKeys: [.isHiddenKey]).isHidden) ?? false) == false
    }

    /// 规范化调用方传入的扩展名过滤条件。
    ///
    /// - Parameter fileExtension: 可能带前导点或大小写混合的扩展名。
    /// - Returns: 去掉前导点并转成小写后的扩展名。
    private func normalizedFileExtension(_ fileExtension: String) -> String {
        let lowercasedExtension = fileExtension.lowercased()
        if lowercasedExtension.hasPrefix(".") {
            return String(lowercasedExtension.dropFirst())
        }
        return lowercasedExtension
    }
}
