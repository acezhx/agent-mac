import Foundation

/// 工具审批风险类型。
nonisolated enum ToolApprovalRisk: String, CaseIterable, Equatable, Sendable {
    /// shell 命令执行。
    case shell

    /// 文件编辑。
    case edit

    /// 文件写入。
    case write

    /// 网络访问。
    case network

    /// 密钥或敏感凭据访问。
    case secrets

    /// Runtime Host 上报了当前版本不认识的风险类型。
    case unknown

    /// 从 Runtime Host 上报值创建风险类型。
    ///
    /// - Parameter rawValue: Runtime Host payload 中的 `risk` 字段。
    init(runtimeValue rawValue: String?) {
        guard let rawValue else {
            self = .unknown
            return
        }

        self = ToolApprovalRisk(rawValue: rawValue.lowercased()) ?? .unknown
    }
}

/// 工具审批请求。
nonisolated struct ToolApprovalRequest: Equatable, Identifiable, Sendable {
    /// 可展示的请求详情字段。
    nonisolated struct DetailField: Equatable, Identifiable, Sendable {
        /// 字段名。
        let key: String

        /// 字段值。
        let value: String

        /// 字段稳定 id。
        var id: String { key }

        /// 创建详情字段。
        ///
        /// - Parameters:
        ///   - key: 字段名。
        ///   - value: 字段值。
        init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    /// Runtime Host 工具调用 id。
    let toolCallID: String

    /// 工具名称。
    let toolName: String

    /// Runtime Host 上报的风险类型。
    let risk: ToolApprovalRisk

    /// 工具调用摘要。
    let summary: String

    /// 工具调用详情字段。
    let details: [DetailField]

    /// `Identifiable` 使用的稳定 id。
    var id: String { toolCallID }

    /// 创建工具审批请求。
    ///
    /// - Parameters:
    ///   - toolCallID: Runtime Host 工具调用 id。
    ///   - toolName: 工具名称。
    ///   - risk: 风险类型。
    ///   - summary: 工具调用摘要。
    ///   - details: 工具调用详情字段。
    init(
        toolCallID: String,
        toolName: String,
        risk: ToolApprovalRisk,
        summary: String,
        details: [DetailField] = []
    ) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.risk = risk
        self.summary = summary
        self.details = details
    }
}

/// 工具审批决策。
nonisolated enum ToolApprovalDecision: Codable, Equatable, Sendable {
    /// 允许工具请求。
    case allowed(reason: String)

    /// 拒绝工具请求。
    case denied(reason: String)

    /// 当前阶段不支持完整审批流程。
    case unsupported(reason: String)

    /// 决策原因。
    var reason: String {
        switch self {
        case let .allowed(reason), let .denied(reason), let .unsupported(reason):
            reason
        }
    }

    /// Runtime Host 协议使用的稳定决策值。
    var runtimeDecision: String {
        switch self {
        case .allowed:
            "approved"
        case .denied, .unsupported:
            "denied"
        }
    }

    /// UI 和诊断使用的短标题。
    var displayTitle: String {
        switch self {
        case .allowed:
            "批准"
        case .denied:
            "拒绝"
        case .unsupported:
            "不支持"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case reason
    }

    /// 从稳定 JSON 结构解码工具审批决策。
    ///
    /// - Parameter decoder: JSON decoder。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let reason = try container.decode(String.self, forKey: .reason)

        switch type {
        case "allowed", "approved":
            self = .allowed(reason: reason)
        case "denied":
            self = .denied(reason: reason)
        case "unsupported":
            self = .unsupported(reason: reason)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown tool approval decision type: \(type)."
            )
        }
    }

    /// 编码为稳定 JSON 结构。
    ///
    /// - Parameter encoder: JSON encoder。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .allowed(reason):
            try container.encode("allowed", forKey: .type)
            try container.encode(reason, forKey: .reason)
        case let .denied(reason):
            try container.encode("denied", forKey: .type)
            try container.encode(reason, forKey: .reason)
        case let .unsupported(reason):
            try container.encode("unsupported", forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }
}

/// 审批策略评估结果。
nonisolated enum ToolApprovalEvaluation: Equatable, Sendable {
    /// 已经得到自动决策。
    case resolved(ToolApprovalDecision)

    /// 需要 UI 请求用户确认。
    case requiresUserDecision
}

/// 工具审批服务。
///
/// 该服务只解释 Agent 权限配置，不持有 UI 状态，不调用 Runtime Host，也不执行工具。
nonisolated struct ApprovalService: Sendable {
    /// 创建审批服务。
    init() {}

    /// 根据 Agent 权限配置评估工具请求。
    ///
    /// - Parameters:
    ///   - request: Runtime Host 上报的工具审批请求。
    ///   - permissions: Agent 已解析权限配置。
    /// - Returns: 自动决策或需要用户确认的结果。
    func evaluate(
        _ request: ToolApprovalRequest,
        permissions: PermissionConfig
    ) -> ToolApprovalEvaluation {
        switch permissionDecision(for: request, permissions: permissions) {
        case .allow:
            return .resolved(.allowed(reason: "Allowed by agent permission policy."))
        case .ask:
            return .requiresUserDecision
        case .deny:
            return .resolved(.denied(reason: "Denied by agent permission policy."))
        }
    }

    /// 返回请求对应的 Agent 权限项。
    ///
    /// - Parameters:
    ///   - request: 工具审批请求。
    ///   - permissions: Agent 权限配置。
    /// - Returns: 当前请求的权限决策。
    private func permissionDecision(
        for request: ToolApprovalRequest,
        permissions: PermissionConfig
    ) -> PermissionDecision {
        switch request.risk {
        case .shell:
            return permissions.bash
        case .edit, .write:
            return permissions.edit
        case .network:
            return permissions.network
        case .secrets, .unknown:
            return .deny
        }
    }
}

/// 工具审批处理边界。
///
/// `Session` 通过该协议等待 UI 或默认策略给出用户确认结果。实现方不能依赖 TCA。
nonisolated protocol ToolApprovalHandling: AnyObject {
    /// 等待并返回用户对工具请求的决策。
    ///
    /// - Parameter request: Runtime Host 上报的工具审批请求。
    /// - Returns: 用户确认或默认拒绝决策。
    func handle(_ request: ToolApprovalRequest) -> ToolApprovalDecision
}

/// 第一版工具审批默认处理器。
nonisolated final class DefaultToolApprovalHandler: ToolApprovalHandling {
    /// 创建默认拒绝处理器。
    init() {}

    /// 默认拒绝，避免没有 UI 处理器时自动执行高风险工具。
    ///
    /// - Parameter request: Runtime Host 上报的工具审批请求。
    /// - Returns: denied 决策。
    func handle(_ request: ToolApprovalRequest) -> ToolApprovalDecision {
        .denied(reason: "Tool approval was denied because no interactive approval handler is configured.")
    }
}

/// 可由 AppShell 驱动的交互式审批处理器。
///
/// `Session` 在线程中等待 `handle(_:)` 返回；AppShell 通过 `submit(_:for:)` 提交用户选择。
/// 该类型只使用 Foundation 同步原语，不依赖 TCA 或 SwiftUI。
nonisolated final class InteractiveToolApprovalHandler: ToolApprovalHandling, @unchecked Sendable {
    private let condition = NSCondition()
    private var pendingToolCallIDs: Set<String> = []
    private var decisions: [String: ToolApprovalDecision] = [:]

    /// 创建交互式审批处理器。
    init() {}

    /// 等待 UI 提交当前请求的决策。
    ///
    /// - Parameter request: Runtime Host 上报的工具审批请求。
    /// - Returns: UI 提交的 allow/deny 决策。
    func handle(_ request: ToolApprovalRequest) -> ToolApprovalDecision {
        condition.lock()
        pendingToolCallIDs.insert(request.toolCallID)
        defer {
            pendingToolCallIDs.remove(request.toolCallID)
            decisions[request.toolCallID] = nil
            condition.unlock()
        }

        while decisions[request.toolCallID] == nil {
            condition.wait()
        }

        return decisions[request.toolCallID]
            ?? .denied(reason: "Tool approval was dismissed before a decision was recorded.")
    }

    /// 提交 UI 决策。
    ///
    /// - Parameters:
    ///   - decision: 用户选择的审批决策。
    ///   - toolCallID: Runtime Host 工具调用 id。
    func submit(_ decision: ToolApprovalDecision, for toolCallID: String) {
        condition.lock()
        decisions[toolCallID] = decision
        condition.broadcast()
        condition.unlock()
    }
}
