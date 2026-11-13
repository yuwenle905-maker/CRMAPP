import Foundation
import SwiftUI

/// 只影响顾问/分析页面的展示层，不参与任何数据持久化与统计计算。
struct PresentationDisplayConfig: Codable, Equatable {
    var demoEnabled: Bool = false
    var hiddenMetrics: Set<String> = []
    var overrides: [String: String] = [:]

    static let empty = PresentationDisplayConfig()

    static func decode(_ raw: String) -> PresentationDisplayConfig {
        guard let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode(PresentationDisplayConfig.self, from: data) else {
            return .empty
        }
        return value
    }

    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    func isHidden(_ metric: String) -> Bool { hiddenMetrics.contains(metric) }

    func text(_ key: String, fallback: String) -> String {
        guard demoEnabled else { return fallback }
        let value = overrides[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallback : value
    }
}

enum PresentationMetric {
    static let totalRevenue   = "advisor.totalRevenue"
    static let pendingAlert   = "advisor.pendingAlert"
    static let unassignedAlert = "advisor.unassignedAlert"
    static let teamROI        = "advisor.teamROI"
    static let teamRevenue    = "advisor.teamRevenue"
    static let teamLeads      = "advisor.teamLeads"
    static let advisorLeads   = "advisor.leads"
    static let advisorOrders  = "advisor.newOrders"
    static let advisorPending = "advisor.pending"
    static let advisorRevenue = "advisor.revenue"
    static let advisorROI     = "advisor.roi"
    static let advisorRate    = "advisor.newRate"
    static let advisorShare   = "advisor.share"
    static let revenuePie     = "advisor.revenuePie"

    static let channelLeads     = "analytics.channelLeads"
    static let channelNewRate   = "analytics.channelNewRate"
    static let channelRetention = "analytics.channelRetention"
    static let channelRevenue   = "analytics.channelRevenue"
    static let regionSection    = "analytics.region"
    static let ageSection       = "analytics.age"
    static let amountSection    = "analytics.amount"
    static let profileCount     = "analytics.profileCount"
    static let profilePercent   = "analytics.profilePercent"

    static let dashboardROI      = "dashboard.roi"
    static let dashboardYearROI  = "dashboard.yearROI"
    static let dashboardCost     = "dashboard.cost"
    static let dashboardRevenue  = "dashboard.revenue"
    static let dashboardFollowUp = "dashboard.followUp"
    static let dashboardFunnel   = "dashboard.funnel"

    static let customerPhone       = "customer.phone"
    static let customerAddress     = "customer.address"
    static let customerRevenue     = "customer.revenue"
    static let customerConversions = "customer.conversions"
}

enum PresentationKey {
    static func team(_ group: String, _ field: String) -> String { "team.\(group).\(field)" }
    static func advisor(_ name: String, _ field: String) -> String { "advisor.\(name).\(field)" }
    static func channel(_ name: String, _ field: String) -> String { "channel.\(name).\(field)" }
    static func profile(_ title: String, _ label: String, _ field: String) -> String {
        "profile.\(title).\(label).\(field)"
    }
    static func customer(_ id: UUID, _ field: String) -> String { "customer.\(id.uuidString).\(field)" }
    static func conversion(_ id: UUID, _ field: String) -> String { "conversion.\(id.uuidString).\(field)" }
}

private struct PresentationDisplayConfigEnvironmentKey: EnvironmentKey {
    static let defaultValue = PresentationDisplayConfig.empty
}

extension EnvironmentValues {
    var presentationDisplayConfig: PresentationDisplayConfig {
        get { self[PresentationDisplayConfigEnvironmentKey.self] }
        set { self[PresentationDisplayConfigEnvironmentKey.self] = newValue }
    }
}
