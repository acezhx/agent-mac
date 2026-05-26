import Foundation

/// Agent 定义的文件型应用服务。
///
/// `AgentLibrary` 负责创建、加载、保存和校验 Agent，并把持久化相对路径解析为运行时需要的
/// `ResolvedAgentConfig`。它通过 `FileStore` 访问磁盘，并沿用 `ResourceLibrary` 的资源分类，
/// 不依赖 SwiftUI、TCA、Session、RuntimeBridge、RuntimeHost 或 Approval。
nonisolated struct AgentLibrary {
    /// Agent 目录集合。
    private static let agentsDirectory = "agents"

    /// `agent.yaml` 文件名。
    private static let manifestFileName = "agent.yaml"

    /// 默认 system prompt 文件名。
    private static let defaultSystemPromptFileName = "system.md"

    /// 所有文件访问都委托给 FileStore。
    private let fileStore: FileStore

    /// 创建 Agent 服务。
    ///
    /// - Parameter fileStore: 已指向当前 app data 根目录的文件服务。
    init(fileStore: FileStore) {
        self.fileStore = fileStore
    }

    /// 创建 Agent 目录、初始 `agent.yaml` 和私有 `system.md`。
    ///
    /// - Parameters:
    ///   - id: Agent ID，必须满足项目 ID 规则。
    ///   - name: Agent 展示名称。
    ///   - model: 模型配置，默认使用第一版默认模型。
    ///   - systemPrompt: 初始 system prompt 文本，默认允许为空。
    ///   - permissions: 权限配置，默认全部为 `ask`。
    /// - Returns: 创建后的 Agent 编辑模型。
    /// - Throws: ID 非法、名称为空、ID 已存在或写入失败。
    @discardableResult
    func createAgent(
        id: String,
        name: String,
        model: ModelConfig = .default,
        systemPrompt: String = "",
        permissions: PermissionConfig = .default
    ) throws -> Agent {
        try requireValidAgentID(id)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentValidationError.emptyAgentName(agentID: id)
        }
        guard try !fileStore.directoryExists(at: agentDirectoryPath(id: id)) else {
            throw AgentLibraryError.duplicateAgentID(id: id)
        }

        let manifest = AgentManifest(
            id: id,
            name: name,
            model: model,
            systemPrompt: Self.defaultSystemPromptFileName,
            permissions: permissions
        )
        let agent = Agent(manifest: manifest, systemPrompt: systemPrompt)
        try saveAgent(agent)
        return agent
    }

    /// 加载 Agent 摘要列表。
    ///
    /// 列表按 Agent 目录名稳定排序。任一 Agent manifest 无法加载时会抛出错误，避免静默隐藏损坏配置。
    ///
    /// - Returns: Agent 摘要列表。
    /// - Throws: 目录扫描或 manifest 读取错误。
    func listAgents() throws -> [AgentSummary] {
        try fileStore
            .listDirectories(at: Self.agentsDirectory)
            .map { try loadAgent(id: $0.lastPathComponent).summary }
    }

    /// 加载单个 Agent 的 manifest 和私有 system prompt。
    ///
    /// - Parameter id: Agent ID。
    /// - Returns: Agent 编辑模型。
    /// - Throws: ID 非法、manifest 读取失败、ID 不匹配或 system prompt 读取失败。
    func loadAgent(id: String) throws -> Agent {
        try requireValidAgentID(id)
        let manifest = try readManifest(id: id)
        guard manifest.id == id else {
            throw AgentValidationError.manifestIDMismatch(directoryID: id, manifestID: manifest.id)
        }

        let systemPromptPath = try systemPromptAppDataPath(for: manifest)
        let systemPrompt = try fileStore.readTextFile(at: systemPromptPath)
        return Agent(id: id, manifest: manifest, systemPrompt: systemPrompt)
    }

    /// 保存 Agent manifest 和私有 system prompt。
    ///
    /// 该方法保存 typed 编辑模型，不执行共享资源存在性校验；缺失资源由 `validateAgent(id:)`
    /// 在启动 session 前报告。保存前仍会校验 ID、名称、模型字段和持久化路径安全，避免写入非法配置。
    ///
    /// - Parameter agent: 要保存的 Agent 编辑模型。
    /// - Returns: 保存后的 Agent 编辑模型。
    /// - Throws: 配置字段非法或写入失败。
    @discardableResult
    func saveAgent(_ agent: Agent) throws -> Agent {
        try validateWritableAgent(agent)
        try writeManifest(agent.manifest, agentID: agent.id)
        try fileStore.writeTextFile(agent.systemPrompt, to: systemPromptAppDataPath(for: agent.manifest, agentID: agent.id))
        return agent
    }

    /// 校验 Agent manifest、私有 system prompt 和已选择资源。
    ///
    /// - Parameter id: Agent ID。
    /// - Returns: 校验结果；`errors` 为空表示可以生成运行时配置。
    /// - Throws: 文件系统读取错误。
    func validateAgent(id: String) throws -> AgentValidationStatus {
        guard agentIDValidationError(id) == nil else {
            return AgentValidationStatus(errors: [.invalidAgentID(id: id)])
        }

        var errors: [AgentValidationError] = []
        guard try fileStore.directoryExists(at: agentDirectoryPath(id: id)) else {
            return AgentValidationStatus(errors: [.missingAgentDirectory(agentID: id)])
        }
        guard try fileStore.fileExists(at: manifestPath(id: id)) else {
            return AgentValidationStatus(errors: [.missingManifest(agentID: id)])
        }

        let manifest: AgentManifest
        do {
            manifest = try decodeManifestForValidation(id: id)
        } catch let error as AgentManifestYAMLError {
            return AgentValidationStatus(errors: [manifestValidationError(error, agentID: id)])
        }

        let manifestAtDirectory = AgentManifest(
            id: id,
            name: manifest.name,
            model: manifest.model,
            systemPrompt: manifest.systemPrompt,
            knowledge: manifest.knowledge,
            skills: manifest.skills,
            tools: manifest.tools,
            permissions: manifest.permissions
        )
        errors.append(contentsOf: validateManifestFields(manifest, expectedID: id))
        errors.append(contentsOf: validateSystemPromptReference(manifestAtDirectory))
        errors.append(contentsOf: try validateKnowledgeReferences(manifestAtDirectory))
        errors.append(contentsOf: try validateSkillReferences(manifestAtDirectory))
        errors.append(contentsOf: try validateToolReferences(manifestAtDirectory))

        return AgentValidationStatus(errors: errors)
    }

    /// 生成运行时需要的绝对路径配置。
    ///
    /// 生成前会完整校验 Agent。返回结构中的路径只用于传给 Runtime，不会写回 `agent.yaml`。
    ///
    /// - Parameters:
    ///   - id: Agent ID。
    ///   - workspaceDirectory: 会话工作区目录。
    /// - Returns: 解析后的运行时配置。
    /// - Throws: Agent 校验失败、manifest 读取失败或路径解析失败。
    func resolvedAgentConfig(for id: String, workspaceDirectory: URL) throws -> ResolvedAgentConfig {
        let status = try validateAgent(id: id)
        guard status.isValid else {
            throw AgentLibraryError.validationFailed(agentID: id, errors: status.errors)
        }

        let agent = try loadAgent(id: id)
        let manifest = agent.manifest
        return ResolvedAgentConfig(
            id: manifest.id,
            name: manifest.name,
            model: manifest.model,
            systemPromptPath: try absolutePath(for: systemPromptAppDataPath(for: manifest)),
            knowledgePaths: try manifest.knowledge.map { try absolutePath(for: agentRelativePath($0, agentID: manifest.id, kind: .knowledge)) },
            skillPaths: try manifest.skills.map { try absolutePath(for: agentRelativePath($0, agentID: manifest.id, kind: .skill)) },
            toolPaths: try manifest.tools.map { try absolutePath(for: agentRelativePath($0, agentID: manifest.id, kind: .tool)) },
            permissions: manifest.permissions,
            workspacePath: workspaceDirectory.standardizedFileURL.path
        )
    }

    /// 读取并解码 `agent.yaml`。
    ///
    /// - Parameter id: Agent ID。
    /// - Returns: 解码后的 manifest。
    private func readManifest(id: String) throws -> AgentManifest {
        try fileStore.readYAMLFile(at: manifestPath(id: id)) {
            try AgentManifestYAMLCodec.decode($0)
        }
    }

    /// 读取 manifest 文本并保留解码错误类型，供校验结果做精确映射。
    ///
    /// - Parameter id: Agent ID。
    /// - Returns: 解码后的 manifest。
    private func decodeManifestForValidation(id: String) throws -> AgentManifest {
        let text = try fileStore.readTextFile(at: manifestPath(id: id))
        return try AgentManifestYAMLCodec.decode(text)
    }

    /// 写入 `agent.yaml`。
    ///
    /// - Parameter manifest: 要保存的 manifest。
    private func writeManifest(_ manifest: AgentManifest, agentID: String) throws {
        try fileStore.writeYAMLFile(manifest, to: manifestPath(id: agentID)) {
            AgentManifestYAMLCodec.encode($0)
        }
    }

    /// 校验可持久化的 Agent 编辑模型。
    ///
    /// - Parameter agent: 要保存的 Agent。
    private func validateWritableAgent(_ agent: Agent) throws {
        try requireValidAgentID(agent.id)
        let fieldErrors = validateManifestFields(agent.manifest, expectedID: agent.id)
        if let firstError = fieldErrors.first {
            throw firstError
        }
        _ = try systemPromptAppDataPath(for: agent.manifest, agentID: agent.id)

        for reference in agent.manifest.knowledge {
            _ = try agentRelativePath(reference, agentID: agent.id, kind: .knowledge)
        }
        for reference in agent.manifest.skills {
            _ = try agentRelativePath(reference, agentID: agent.id, kind: .skill)
        }
        for reference in agent.manifest.tools {
            _ = try agentRelativePath(reference, agentID: agent.id, kind: .tool)
        }
    }

    /// 校验 manifest 中不依赖文件系统存在性的字段。
    ///
    /// - Parameters:
    ///   - manifest: 要校验的 manifest。
    ///   - expectedID: Agent 目录 ID。
    /// - Returns: 字段错误列表。
    private func validateManifestFields(_ manifest: AgentManifest, expectedID: String) -> [AgentValidationError] {
        var errors: [AgentValidationError] = []
        if agentIDValidationError(manifest.id) != nil {
            errors.append(.invalidAgentID(id: manifest.id))
        }
        if manifest.id != expectedID {
            errors.append(.manifestIDMismatch(directoryID: expectedID, manifestID: manifest.id))
        }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyAgentName(agentID: expectedID))
        }
        if manifest.model.provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyModelProvider(agentID: expectedID))
        }
        if manifest.model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyModelName(agentID: expectedID))
        }
        return errors
    }

    /// 校验 system prompt 引用。
    ///
    /// - Parameter manifest: Agent manifest。
    /// - Returns: system prompt 路径或存在性错误。
    private func validateSystemPromptReference(_ manifest: AgentManifest) -> [AgentValidationError] {
        do {
            let path = try systemPromptAppDataPath(for: manifest)
            guard try fileStore.fileExists(at: path) else {
                return [.missingSystemPrompt(agentID: manifest.id, path: manifest.systemPrompt)]
            }
            return []
        } catch let error as AgentValidationError {
            return [error]
        } catch {
            return [
                .invalidSystemPromptPath(
                    agentID: manifest.id,
                    path: manifest.systemPrompt,
                    reason: error.localizedDescription
                ),
            ]
        }
    }

    /// 校验 selected knowledge 文件引用。
    ///
    /// - Parameter manifest: Agent manifest。
    /// - Returns: knowledge 引用错误。
    private func validateKnowledgeReferences(_ manifest: AgentManifest) throws -> [AgentValidationError] {
        try manifest.knowledge.compactMap { reference in
            let path: String
            do {
                path = try agentRelativePath(reference, agentID: manifest.id, kind: .knowledge)
            } catch let error as AgentValidationError {
                return error
            }

            return try fileStore.fileExists(at: path)
                ? nil
                : .missingKnowledgeFile(agentID: manifest.id, path: reference)
        }
    }

    /// 校验 selected skill 目录引用。
    ///
    /// - Parameter manifest: Agent manifest。
    /// - Returns: skill 引用错误。
    private func validateSkillReferences(_ manifest: AgentManifest) throws -> [AgentValidationError] {
        try manifest.skills.compactMap { reference in
            let path: String
            do {
                path = try agentRelativePath(reference, agentID: manifest.id, kind: .skill)
            } catch let error as AgentValidationError {
                return error
            }

            guard try fileStore.directoryExists(at: path) else {
                return .missingSkillDirectory(agentID: manifest.id, path: reference)
            }
            guard try fileStore.fileExists(at: "\(path)/SKILL.md") else {
                return .missingSkillManifest(agentID: manifest.id, path: reference)
            }
            return nil
        }
    }

    /// 校验 selected tool 目录引用。
    ///
    /// - Parameter manifest: Agent manifest。
    /// - Returns: tool 引用错误。
    private func validateToolReferences(_ manifest: AgentManifest) throws -> [AgentValidationError] {
        try manifest.tools.compactMap { reference in
            let path: String
            do {
                path = try agentRelativePath(reference, agentID: manifest.id, kind: .tool)
            } catch let error as AgentValidationError {
                return error
            }

            guard try fileStore.directoryExists(at: path) else {
                return .missingToolDirectory(agentID: manifest.id, path: reference)
            }
            guard try fileStore.fileExists(at: "\(path)/tool.yaml") else {
                return .missingToolManifest(agentID: manifest.id, path: reference)
            }
            return try validateToolEntry(agentID: manifest.id, toolReference: reference, toolAppDataPath: path)
        }
    }

    /// 校验 tool 入口文件引用。
    ///
    /// - Parameters:
    ///   - agentID: Agent ID。
    ///   - toolReference: manifest 中保存的 tool 路径。
    ///   - toolAppDataPath: tool 目录对应的 app data 相对路径。
    /// - Returns: tool 入口错误；入口合法时返回 `nil`。
    private func validateToolEntry(agentID: String, toolReference: String, toolAppDataPath: String) throws -> AgentValidationError? {
        let manifest = try fileStore.readYAMLFile(at: "\(toolAppDataPath)/tool.yaml") { $0 }
        guard let entry = AgentManifestYAMLCodec.topLevelScalar(named: "entry", in: manifest), !entry.isEmpty else {
            return .missingToolEntry(agentID: agentID, path: toolReference)
        }
        guard !entry.contains("\0") else {
            return .invalidToolEntry(agentID: agentID, path: toolReference, entry: entry, reason: "Entry cannot contain null bytes.")
        }
        guard !(entry as NSString).isAbsolutePath else {
            return .invalidToolEntry(agentID: agentID, path: toolReference, entry: entry, reason: "Entry must be relative to the tool directory.")
        }

        let entryPath = "\(toolAppDataPath)/\(entry)"
        do {
            let toolURL = try fileStore.resolveAppDataPath(toolAppDataPath)
            let entryURL = try fileStore.resolveAppDataPath(entryPath)
            guard entryURL.path != toolURL.path, entryURL.path.hasPrefix(toolURL.path + "/") else {
                return .invalidToolEntry(agentID: agentID, path: toolReference, entry: entry, reason: "Entry must stay inside the tool directory.")
            }
        } catch let error as FileStoreError {
            return .invalidToolEntry(agentID: agentID, path: toolReference, entry: entry, reason: error.localizedDescription)
        }

        return try fileStore.fileExists(at: entryPath)
            ? nil
            : .missingToolEntryFile(agentID: agentID, path: toolReference, entry: entry)
    }

    /// 将 Agent 相对路径解析为 app data 相对路径。
    ///
    /// - Parameters:
    ///   - reference: manifest 中保存的相对路径。
    ///   - agentID: Agent ID。
    ///   - kind: 资源类型，用于错误诊断。
    /// - Returns: 可交给 `FileStore` 使用的 app data 相对路径。
    private func agentRelativePath(_ reference: String, agentID: String, kind: ResourceKind) throws -> String {
        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReference.isEmpty else {
            throw AgentValidationError.invalidResourcePath(agentID: agentID, kind: kind, path: reference, reason: "Path cannot be empty.")
        }
        guard !reference.contains("\0") else {
            throw AgentValidationError.invalidResourcePath(agentID: agentID, kind: kind, path: reference, reason: "Path cannot contain null bytes.")
        }
        guard !(reference as NSString).isAbsolutePath else {
            throw AgentValidationError.invalidResourcePath(agentID: agentID, kind: kind, path: reference, reason: "Path must be relative to the agent directory.")
        }

        let path = "\(agentDirectoryPath(id: agentID))/\(reference)"
        do {
            _ = try fileStore.resolveAppDataPath(path)
            return path
        } catch {
            throw AgentValidationError.invalidResourcePath(agentID: agentID, kind: kind, path: reference, reason: error.localizedDescription)
        }
    }

    /// 将 manifest 中的 system prompt 路径解析为 app data 相对路径。
    ///
    /// system prompt 必须留在当前 Agent 目录中，避免保存 Agent 时写入共享资源库或其他 Agent 目录。
    ///
    /// - Parameter manifest: Agent manifest。
    /// - Returns: system prompt 的 app data 相对路径。
    private func systemPromptAppDataPath(for manifest: AgentManifest, agentID: String? = nil) throws -> String {
        let id = agentID ?? manifest.id
        let reference = manifest.systemPrompt
        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReference.isEmpty else {
            throw AgentValidationError.invalidSystemPromptPath(agentID: id, path: reference, reason: "Path cannot be empty.")
        }
        guard !reference.contains("\0") else {
            throw AgentValidationError.invalidSystemPromptPath(agentID: id, path: reference, reason: "Path cannot contain null bytes.")
        }
        guard !(reference as NSString).isAbsolutePath else {
            throw AgentValidationError.invalidSystemPromptPath(agentID: id, path: reference, reason: "Path must be relative to the agent directory.")
        }

        let agentDirectory = agentDirectoryPath(id: id)
        let path = "\(agentDirectory)/\(reference)"
        do {
            let agentURL = try fileStore.resolveAppDataPath(agentDirectory)
            let promptURL = try fileStore.resolveAppDataPath(path)
            guard promptURL.path != agentURL.path, promptURL.path.hasPrefix(agentURL.path + "/") else {
                throw AgentValidationError.invalidSystemPromptPath(
                    agentID: id,
                    path: reference,
                    reason: "Path must stay inside the agent directory."
                )
            }
            return path
        } catch let error as AgentValidationError {
            throw error
        } catch {
            throw AgentValidationError.invalidSystemPromptPath(agentID: id, path: reference, reason: error.localizedDescription)
        }
    }

    /// 将 app data 相对路径解析为绝对路径字符串。
    ///
    /// - Parameter path: app data 相对路径。
    /// - Returns: 绝对路径字符串。
    private func absolutePath(for path: String) throws -> String {
        try fileStore.resolveAppDataPath(path).path
    }

    /// 要求 Agent ID 满足项目 ID 规则。
    ///
    /// - Parameter id: Agent ID。
    private func requireValidAgentID(_ id: String) throws {
        if let error = agentIDValidationError(id) {
            throw error
        }
    }

    /// 生成 Agent ID 校验错误。
    ///
    /// - Parameter id: Agent ID。
    /// - Returns: ID 合法时返回 `nil`，否则返回校验错误。
    private func agentIDValidationError(_ id: String) -> AgentValidationError? {
        guard (2...64).contains(id.count),
              id.first != "-",
              id.last != "-"
        else {
            return .invalidAgentID(id: id)
        }

        let isValid = id.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return value == 45 || (48...57).contains(value) || (97...122).contains(value)
        }
        return isValid ? nil : .invalidAgentID(id: id)
    }

    /// 将 manifest 解码错误映射成 Agent 校验错误。
    ///
    /// - Parameters:
    ///   - error: manifest 解码错误。
    ///   - agentID: Agent ID。
    /// - Returns: Agent 校验错误。
    private func manifestValidationError(_ error: AgentManifestYAMLError, agentID: String) -> AgentValidationError {
        switch error {
        case let .invalidPermission(field, value):
            .invalidPermission(agentID: agentID, field: field, value: value)
        case let .missingRequiredField(field):
            .invalidManifest(agentID: agentID, reason: "Missing required field: \(field)")
        case let .invalidSyntax(reason):
            .invalidManifest(agentID: agentID, reason: reason)
        }
    }

    /// 构造 Agent 目录路径。
    ///
    /// - Parameter id: Agent ID。
    /// - Returns: app data 相对路径。
    private func agentDirectoryPath(id: String) -> String {
        "\(Self.agentsDirectory)/\(id)"
    }

    /// 构造 Agent manifest 路径。
    ///
    /// - Parameter id: Agent ID。
    /// - Returns: app data 相对路径。
    private func manifestPath(id: String) -> String {
        "\(agentDirectoryPath(id: id))/\(Self.manifestFileName)"
    }
}
