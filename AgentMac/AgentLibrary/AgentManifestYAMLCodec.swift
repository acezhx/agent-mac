import Foundation

/// `agent.yaml` 轻量编解码错误。
nonisolated enum AgentManifestYAMLError: Error, Equatable {
    /// 缺少必填字段。
    case missingRequiredField(String)

    /// 权限字段值非法。
    case invalidPermission(field: String, value: String)

    /// YAML 结构不符合第一版支持的 manifest 形态。
    case invalidSyntax(String)
}

extension AgentManifestYAMLError: LocalizedError {
    /// 面向 FileStore YAML 错误包装的描述。
    var errorDescription: String? {
        switch self {
        case let .missingRequiredField(field):
            "Missing required field: \(field)"
        case let .invalidPermission(field, value):
            "Invalid permission \(field): \(value)"
        case let .invalidSyntax(reason):
            reason
        }
    }
}

/// `agent.yaml` 第一版支持形态的轻量编解码器。
///
/// FileStore 不绑定具体 YAML 库，AgentLibrary 只需要解析当前 manifest 使用的简单标量、二级映射和
/// 字符串数组，因此这里保持窄解析器，避免新增依赖。
nonisolated enum AgentManifestYAMLCodec {
    /// 解码 manifest YAML。
    ///
    /// - Parameter text: YAML 文本。
    /// - Returns: 解码后的 manifest。
    static func decode(_ text: String) throws -> AgentManifest {
        let parsed = try parse(text)
        let permissions = try PermissionConfig(
            bash: permission(named: "bash", in: parsed),
            edit: permission(named: "edit", in: parsed),
            network: permission(named: "network", in: parsed)
        )

        return AgentManifest(
            id: try requiredScalar(named: "id", in: parsed),
            name: try requiredScalar(named: "name", in: parsed),
            model: ModelConfig(
                provider: try requiredNestedScalar(section: "model", name: "provider", in: parsed),
                name: try requiredNestedScalar(section: "model", name: "name", in: parsed)
            ),
            systemPrompt: try requiredScalar(named: "systemPrompt", in: parsed),
            knowledge: parsed.arrays["knowledge"] ?? [],
            skills: parsed.arrays["skills"] ?? [],
            tools: parsed.arrays["tools"] ?? [],
            permissions: permissions
        )
    }

    /// 编码 manifest YAML。
    ///
    /// - Parameter manifest: 要编码的 manifest。
    /// - Returns: YAML 文本。
    static func encode(_ manifest: AgentManifest) -> String {
        [
            "id: \(manifest.id)",
            "name: \"\(escapedDoubleQuotedScalar(manifest.name))\"",
            "",
            "model:",
            "  provider: \"\(escapedDoubleQuotedScalar(manifest.model.provider))\"",
            "  name: \"\(escapedDoubleQuotedScalar(manifest.model.name))\"",
            "",
            "systemPrompt: \"\(escapedDoubleQuotedScalar(manifest.systemPrompt))\"",
            "",
            yamlArray(named: "knowledge", values: manifest.knowledge),
            "",
            yamlArray(named: "skills", values: manifest.skills),
            "",
            yamlArray(named: "tools", values: manifest.tools),
            "",
            "permissions:",
            "  bash: \(manifest.permissions.bash.rawValue)",
            "  edit: \(manifest.permissions.edit.rawValue)",
            "  network: \(manifest.permissions.network.rawValue)",
            "",
        ].joined(separator: "\n")
    }

    /// 解析 YAML 顶层字符串标量。
    ///
    /// - Parameters:
    ///   - name: 顶层字段名。
    ///   - yaml: YAML 文本。
    /// - Returns: 解析出的标量值；字段缺失或不是顶层标量时返回 `nil`。
    static func topLevelScalar(named name: String, in yaml: String) -> String? {
        guard let rawValue = try? parse(yaml).scalars[name] else {
            return nil
        }
        return rawValue
    }

    /// 解码权限字段。
    ///
    /// - Parameters:
    ///   - name: 权限字段名。
    ///   - parsed: 解析后的 YAML。
    /// - Returns: 权限值；字段缺失时默认为 `ask`。
    private static func permission(named name: String, in parsed: ParsedYAML) throws -> PermissionDecision {
        guard let value = parsed.maps["permissions"]?[name] else {
            return .ask
        }
        guard let decision = PermissionDecision(rawValue: value) else {
            throw AgentManifestYAMLError.invalidPermission(field: name, value: value)
        }
        return decision
    }

    /// 读取必填顶层标量。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - parsed: 解析后的 YAML。
    /// - Returns: 标量值。
    private static func requiredScalar(named name: String, in parsed: ParsedYAML) throws -> String {
        guard let value = parsed.scalars[name] else {
            throw AgentManifestYAMLError.missingRequiredField(name)
        }
        return value
    }

    /// 读取必填二级标量。
    ///
    /// - Parameters:
    ///   - section: 顶层 section 名称。
    ///   - name: 二级字段名。
    ///   - parsed: 解析后的 YAML。
    /// - Returns: 标量值。
    private static func requiredNestedScalar(section: String, name: String, in parsed: ParsedYAML) throws -> String {
        guard let value = parsed.maps[section]?[name] else {
            throw AgentManifestYAMLError.missingRequiredField("\(section).\(name)")
        }
        return value
    }

    /// 编码 YAML 字符串数组。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - values: 字符串数组。
    /// - Returns: YAML 文本片段。
    private static func yamlArray(named name: String, values: [String]) -> String {
        guard !values.isEmpty else {
            return "\(name): []"
        }

        let items = values
            .map { "  - \"\(escapedDoubleQuotedScalar($0))\"" }
            .joined(separator: "\n")
        return "\(name):\n\(items)"
    }

    /// 解析第一版 manifest 使用的 YAML 子集。
    ///
    /// - Parameter text: YAML 文本。
    /// - Returns: 顶层标量、二级映射和数组。
    private static func parse(_ text: String) throws -> ParsedYAML {
        var parsed = ParsedYAML()
        var currentSection: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else {
                continue
            }

            let indentation = leadingSpaceCount(in: rawLine)
            if indentation == 0 {
                currentSection = nil
                let pair = try keyValuePair(in: trimmedLine)
                guard !pair.key.isEmpty else {
                    throw AgentManifestYAMLError.invalidSyntax("YAML key cannot be empty.")
                }

                if pair.value.isEmpty {
                    currentSection = pair.key
                    parsed.maps[pair.key, default: [:]] = parsed.maps[pair.key] ?? [:]
                    parsed.arrays[pair.key, default: []] = parsed.arrays[pair.key] ?? []
                } else if let array = inlineArray(from: pair.value) {
                    parsed.arrays[pair.key] = array
                } else {
                    parsed.scalars[pair.key] = unquotedScalar(pair.value)
                }
                continue
            }

            guard let section = currentSection else {
                throw AgentManifestYAMLError.invalidSyntax("Indented YAML content must belong to a top-level section.")
            }
            if trimmedLine.hasPrefix("- ") {
                let rawValue = String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                parsed.arrays[section, default: []].append(unquotedScalar(rawValue))
            } else {
                let pair = try keyValuePair(in: trimmedLine)
                parsed.maps[section, default: [:]][pair.key] = unquotedScalar(pair.value)
            }
        }

        return parsed
    }

    /// 解析 `key: value` 行。
    ///
    /// - Parameter line: 已去掉首尾空白的行。
    /// - Returns: key 和未去引号的 value。
    private static func keyValuePair(in line: String) throws -> (key: String, value: String) {
        guard let separator = line.firstIndex(of: ":") else {
            throw AgentManifestYAMLError.invalidSyntax("Expected YAML key-value line: \(line)")
        }

        let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rawValue = String(line[line.index(after: separator)...])
        return (key, strippedInlineComment(from: rawValue))
    }

    /// 解析简单行内数组。
    ///
    /// - Parameter value: 字段值。
    /// - Returns: 字符串数组；不是行内数组时返回 `nil`。
    private static func inlineArray(from value: String) -> [String]? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.hasPrefix("["), trimmedValue.hasSuffix("]") else {
            return nil
        }

        let inner = String(trimmedValue.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inner.isEmpty else {
            return []
        }

        return splitCommaSeparated(inner).map { unquotedScalar($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// 按逗号切分简单数组内容，忽略引号内逗号。
    ///
    /// - Parameter text: 数组内部文本。
    /// - Returns: 切分后的字段。
    private static func splitCommaSeparated(_ text: String) -> [String] {
        var values: [String] = []
        var start = text.startIndex
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaped = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character == "\\" && inDoubleQuote {
                escaped.toggle()
            } else {
                if character == "\"", !inSingleQuote, !escaped {
                    inDoubleQuote.toggle()
                } else if character == "'", !inDoubleQuote {
                    inSingleQuote.toggle()
                } else if character == ",", !inSingleQuote, !inDoubleQuote {
                    values.append(String(text[start..<index]))
                    start = text.index(after: index)
                }
                escaped = false
            }
            index = text.index(after: index)
        }

        values.append(String(text[start..<text.endIndex]))
        return values
    }

    /// 去掉 YAML 值中的行内注释。
    ///
    /// - Parameter value: 冒号后的原始值。
    /// - Returns: 去除注释和首尾空白后的值。
    private static func strippedInlineComment(from value: String) -> String {
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaped = false
        var index = value.startIndex

        while index < value.endIndex {
            let character = value[index]
            if character == "\\" && inDoubleQuote {
                escaped.toggle()
            } else {
                if character == "\"", !inSingleQuote, !escaped {
                    inDoubleQuote.toggle()
                } else if character == "'", !inDoubleQuote {
                    inSingleQuote.toggle()
                } else if character == "#", !inSingleQuote, !inDoubleQuote {
                    return String(value[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                escaped = false
            }
            index = value.index(after: index)
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 去掉 YAML 简单标量的外层引号，并还原当前编码器会写出的转义序列。
    ///
    /// - Parameter value: 字段原始值。
    /// - Returns: 标量值。
    private static func unquotedScalar(_ value: String) -> String {
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            return decodedDoubleQuotedScalar(String(value.dropFirst().dropLast()))
        }
        if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
            return String(value.dropFirst().dropLast())
                .replacingOccurrences(of: "''", with: "'")
        }
        return value
    }

    /// 转义 YAML 双引号标量中的特殊字符。
    ///
    /// - Parameter value: 原始标量。
    /// - Returns: 可放入双引号内的标量文本。
    private static func escapedDoubleQuotedScalar(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0:
                result += "\\0"
            case 8:
                result += "\\b"
            case 9:
                result += "\\t"
            case 10:
                result += "\\n"
            case 12:
                result += "\\f"
            case 13:
                result += "\\r"
            case 34:
                result += "\\\""
            case 92:
                result += "\\\\"
            case 1...31:
                result += "\\x\(twoDigitHex(scalar.value))"
            default:
                result.append(String(scalar))
            }
        }
        return result
    }

    /// 还原 YAML 双引号标量中的转义序列。
    ///
    /// - Parameter value: 已去掉外层双引号的标量文本。
    /// - Returns: 还原后的标量值。
    private static func decodedDoubleQuotedScalar(_ value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        var result = ""
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]
            guard scalar.value == 92, index + 1 < scalars.count else {
                result.append(String(scalar))
                index += 1
                continue
            }

            let escape = scalars[index + 1]
            switch escape.value {
            case 34:
                result += "\""
                index += 2
            case 48:
                result += "\0"
                index += 2
            case 92:
                result += "\\"
                index += 2
            case 98:
                result += "\u{08}"
                index += 2
            case 102:
                result += "\u{0C}"
                index += 2
            case 110:
                result += "\n"
                index += 2
            case 114:
                result += "\r"
                index += 2
            case 116:
                result += "\t"
                index += 2
            case 120:
                if let decoded = decodedHexScalar(scalars, start: index + 2, count: 2) {
                    result.append(String(decoded))
                    index += 4
                } else {
                    result += "\\x"
                    index += 2
                }
            case 117:
                if let decoded = decodedHexScalar(scalars, start: index + 2, count: 4) {
                    result.append(String(decoded))
                    index += 6
                } else {
                    result += "\\u"
                    index += 2
                }
            case 85:
                if let decoded = decodedHexScalar(scalars, start: index + 2, count: 8) {
                    result.append(String(decoded))
                    index += 10
                } else {
                    result += "\\U"
                    index += 2
                }
            default:
                result += "\\"
                result.append(String(escape))
                index += 2
            }
        }

        return result
    }

    /// 解析固定长度十六进制 Unicode 标量。
    ///
    /// - Parameters:
    ///   - scalars: 源字符串的 Unicode 标量。
    ///   - start: 十六进制内容开始位置。
    ///   - count: 十六进制位数。
    /// - Returns: 合法 Unicode 标量；内容不足或非法时返回 `nil`。
    private static func decodedHexScalar(_ scalars: [UnicodeScalar], start: Int, count: Int) -> UnicodeScalar? {
        guard start + count <= scalars.count else {
            return nil
        }

        var value: UInt32 = 0
        for scalar in scalars[start..<(start + count)] {
            guard let digit = hexDigitValue(scalar) else {
                return nil
            }
            value = value * 16 + digit
        }
        return UnicodeScalar(value)
    }

    /// 解析十六进制数字。
    ///
    /// - Parameter scalar: 候选 ASCII Unicode 标量。
    /// - Returns: 十六进制数值；不是十六进制字符时返回 `nil`。
    private static func hexDigitValue(_ scalar: UnicodeScalar) -> UInt32? {
        switch scalar.value {
        case 48...57:
            return scalar.value - 48
        case 65...70:
            return scalar.value - 55
        case 97...102:
            return scalar.value - 87
        default:
            return nil
        }
    }

    /// 生成两位大写十六进制文本。
    ///
    /// - Parameter value: 0 到 255 范围内的数值。
    /// - Returns: 两位十六进制文本。
    private static func twoDigitHex(_ value: UInt32) -> String {
        let hex = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 2 - hex.count)) + hex
    }

    /// 计算行首空格数量。
    ///
    /// - Parameter text: 原始行。
    /// - Returns: 行首空格数量。
    private static func leadingSpaceCount(in text: String) -> Int {
        var count = 0
        for character in text {
            guard character == " " else {
                break
            }
            count += 1
        }
        return count
    }
}

/// 第一版 YAML 子集解析结果。
private nonisolated struct ParsedYAML {
    /// 顶层字符串标量。
    var scalars: [String: String] = [:]

    /// 顶层 section 下的二级标量映射。
    var maps: [String: [String: String]] = [:]

    /// 顶层字符串数组。
    var arrays: [String: [String]] = [:]
}
