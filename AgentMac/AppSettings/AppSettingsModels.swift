import Foundation

/// AgentMac 应用级设置。
///
/// 该模型对应 Application Support 下的 `settings.yaml`，只保存跨 Agent 共享的 app 级配置。
/// Agent 自身定义仍保存在各自的 `agent.yaml` 中。
nonisolated struct AppSettings: Equatable, Sendable {
    /// 默认允许 Agent 使用的模型 provider。
    static let defaultAllowedModelProviders = ["openai"]

    /// 默认应用设置。
    static let `default` = AppSettings()

    /// app data 布局版本。
    var appDataVersion: Int

    /// 上次选择的 workspace。
    var lastWorkspace: String?

    /// Runtime 相关设置。
    var runtime: RuntimeSettings

    /// Agent 相关应用级设置。
    var agent: AgentAppSettings

    /// 创建应用设置。
    ///
    /// - Parameters:
    ///   - appDataVersion: app data 布局版本。
    ///   - lastWorkspace: 上次选择的 workspace。
    ///   - runtime: Runtime 相关设置。
    ///   - agent: Agent 相关应用级设置。
    init(
        appDataVersion: Int = 1,
        lastWorkspace: String? = nil,
        runtime: RuntimeSettings = RuntimeSettings(),
        agent: AgentAppSettings = AgentAppSettings()
    ) {
        self.appDataVersion = appDataVersion
        self.lastWorkspace = lastWorkspace
        self.runtime = runtime
        self.agent = agent
    }
}

/// Runtime 相关应用级设置。
nonisolated struct RuntimeSettings: Equatable, Sendable {
    /// 是否优先使用 app bundle 内置 runtime。
    var useBundledRuntime: Bool

    /// 创建 Runtime 设置。
    ///
    /// - Parameter useBundledRuntime: 是否优先使用 app bundle 内置 runtime。
    init(useBundledRuntime: Bool = true) {
        self.useBundledRuntime = useBundledRuntime
    }
}

/// Agent 相关应用级设置。
nonisolated struct AgentAppSettings: Equatable, Sendable {
    /// Agent 编辑和运行允许使用的模型 provider。
    var allowedModelProviders: [String]

    /// 创建 Agent 应用级设置。
    ///
    /// - Parameter allowedModelProviders: Agent 可使用的模型 provider；保存前会去重并移除空值。
    init(allowedModelProviders: [String] = AppSettings.defaultAllowedModelProviders) {
        self.allowedModelProviders = Self.normalizedProviders(allowedModelProviders)
    }

    /// 规范化 provider 列表。
    ///
    /// - Parameter providers: 原始 provider 列表。
    /// - Returns: 去除空白、空值和重复项后的 provider 列表。
    static func normalizedProviders(_ providers: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for provider in providers {
            let trimmed = provider.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }
            seen.insert(trimmed)
            normalized.append(trimmed)
        }
        return normalized
    }
}

/// `settings.yaml` 轻量编解码错误。
nonisolated enum AppSettingsYAMLError: Error, Equatable {
    /// YAML 内容无法按当前支持的简单设置结构解析。
    case invalidSyntax(String)
}

extension AppSettingsYAMLError: LocalizedError {
    /// 面向 FileStore YAML 错误包装的描述。
    var errorDescription: String? {
        switch self {
        case let .invalidSyntax(reason):
            reason
        }
    }
}

/// `settings.yaml` 第一版支持形态的轻量编解码器。
///
/// FileStore 不绑定具体 YAML 库，因此这里只解析当前 settings 使用的简单标量、二级映射和字符串数组。
nonisolated enum AppSettingsYAMLCodec {
    /// 解码 settings YAML。
    ///
    /// - Parameter text: YAML 文本。
    /// - Returns: 解码后的应用设置；缺失字段使用默认值。
    static func decode(_ text: String) throws -> AppSettings {
        let parsed = try parse(text)
        var settings = AppSettings.default

        if let version = parsed.scalars["appDataVersion"] {
            guard let intValue = Int(version) else {
                throw AppSettingsYAMLError.invalidSyntax("appDataVersion must be an integer.")
            }
            settings.appDataVersion = intValue
        }
        if let lastWorkspace = parsed.scalars["lastWorkspace"] {
            settings.lastWorkspace = nilIfNull(lastWorkspace)
        }
        if let useBundledRuntime = parsed.maps["runtime"]?["useBundledRuntime"] {
            settings.runtime.useBundledRuntime = try boolValue(useBundledRuntime, field: "runtime.useBundledRuntime")
        }
        if let allowedProviders = parsed.arrays["agent.allowedModelProviders"] {
            settings.agent.allowedModelProviders = AgentAppSettings.normalizedProviders(allowedProviders)
        }

        return settings
    }

    /// 编码 settings YAML。
    ///
    /// - Parameter settings: 要编码的应用设置。
    /// - Returns: YAML 文本。
    static func encode(_ settings: AppSettings) -> String {
        let providers = AgentAppSettings.normalizedProviders(settings.agent.allowedModelProviders)
        return [
            "appDataVersion: \(settings.appDataVersion)",
            "lastWorkspace: \(settings.lastWorkspace.map(escapedDoubleQuotedScalar) ?? "null")",
            "",
            "runtime:",
            "  useBundledRuntime: \(settings.runtime.useBundledRuntime ? "true" : "false")",
            "",
            "agent:",
            yamlArray(named: "allowedModelProviders", values: providers, indent: "  "),
            "",
        ].joined(separator: "\n")
    }

    private static func parse(_ text: String) throws -> ParsedSettingsYAML {
        var parsed = ParsedSettingsYAML()
        var currentSection: String?
        var currentArrayKey: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }

            let indent = line.prefix { $0 == " " }.count
            if indent == 0 {
                currentArrayKey = nil
                if trimmed.hasSuffix(":") {
                    currentSection = String(trimmed.dropLast())
                    continue
                }
                currentSection = nil
                let (key, value) = try keyValue(from: trimmed)
                parsed.scalars[key] = unquotedScalar(value)
            } else if indent == 2, let currentSection {
                if trimmed.hasSuffix(":") {
                    let key = String(trimmed.dropLast())
                    let arrayKey = "\(currentSection).\(key)"
                    currentArrayKey = arrayKey
                    parsed.arrays[arrayKey] = []
                    continue
                }
                currentArrayKey = nil
                let (key, value) = try keyValue(from: trimmed)
                if value == "[]" {
                    parsed.arrays["\(currentSection).\(key)"] = []
                    continue
                }
                parsed.maps[currentSection, default: [:]][key] = unquotedScalar(value)
            } else if indent == 4, let currentArrayKey, trimmed.hasPrefix("-") {
                let value = String(trimmed.dropFirst())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                parsed.arrays[currentArrayKey, default: []].append(unquotedScalar(value))
            } else {
                throw AppSettingsYAMLError.invalidSyntax("Unsupported settings.yaml line: \(line)")
            }
        }

        return parsed
    }

    private static func keyValue(from line: String) throws -> (String, String) {
        guard let separator = line.firstIndex(of: ":") else {
            throw AppSettingsYAMLError.invalidSyntax("Expected key-value line: \(line)")
        }
        let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw AppSettingsYAMLError.invalidSyntax("Setting key cannot be empty.")
        }
        return (key, value)
    }

    private static func boolValue(_ value: String, field: String) throws -> Bool {
        switch value.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            throw AppSettingsYAMLError.invalidSyntax("\(field) must be true or false.")
        }
    }

    private static func nilIfNull(_ value: String) -> String? {
        value.lowercased() == "null" ? nil : value
    }

    private static func unquotedScalar(_ value: String) -> String {
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            return String(value.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return value
    }

    private static func escapedDoubleQuotedScalar(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func yamlArray(named name: String, values: [String], indent: String) -> String {
        guard !values.isEmpty else {
            return "\(indent)\(name): []"
        }
        return (["\(indent)\(name):"] + values.map { "\(indent)  - \(escapedDoubleQuotedScalar($0))" })
            .joined(separator: "\n")
    }
}

private struct ParsedSettingsYAML {
    var scalars: [String: String] = [:]
    var maps: [String: [String: String]] = [:]
    var arrays: [String: [String]] = [:]
}
