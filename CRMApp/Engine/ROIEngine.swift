// MARK: - ROIEngine.swift
// ROI 与销售漏斗核心计算层

import Foundation

// MARK: 漏斗单级
struct FunnelStage: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
    let totalAmount: Double
    let conversionRate: Double
    let denominator: Int
    // 固化本次统计窗口命中的客户和成交记录，确保看板数字与下钻明细口径一致。
    let customerIDs: Set<UUID>
    let conversionRecordIDs: Set<UUID>

    var conversionRateText: String {
        guard denominator > 0 else { return "—" }
        return String(format: "%.1f%%", conversionRate * 100)
    }
    var totalAmountText: String { String(format: "%.0f 元", totalAmount) }
}

// MARK: 期间汇总
struct PeriodSummary {
    let importedLeadCount: Int
    let totalCost: Double
    let funnelRevenue: Double
    let nonFunnelRevenue: Double
    var totalRevenue: Double { funnelRevenue + nonFunnelRevenue }

    var roi: Double {
        guard totalCost > 0 else { return 0 }
        return funnelRevenue / totalCost
    }
    var roiText: String { String(format: "%.2f", roi) }
    let funnelStages: [FunnelStage]

    // 新单成交率（仅智能导入+有线索金额+纳入成本口径）
    let cumulativeNewOrderRate: Double   // 累计：全量新单人数 / 全量线索数
    let monthlyNewOrderRate: Double      // 当月：当月新单人数 / 当月线索数
    let cumulativeNewOrderCount: Int
    let cumulativeTotalLeads: Int
    let monthlyNewOrderCount: Int
    let monthlyTotalLeads: Int

    var cumulativeNewOrderRateText: String {
        cumulativeTotalLeads > 0 ? String(format: "%.1f%%", cumulativeNewOrderRate * 100) : "—"
    }
    var monthlyNewOrderRateText: String {
        monthlyTotalLeads > 0 ? String(format: "%.1f%%", monthlyNewOrderRate * 100) : "—"
    }
}

// MARK: 顾问统计
struct AdvisorStats: Identifiable {
    let id = UUID()
    let name:          String
    let totalLeads:    Int
    /// 当前筛选月份内开出的全部新单客户，包含历史月份派发后本月才开单的客户。
    let newOrderCount: Int
    /// 截止当前筛选期的累计派发与累计新单客户数。
    let cumulativeLeadCount: Int
    let cumulativeNewOrderCount: Int
    /// 当前筛选期新单客户中已经产生有效二次的客户数。
    let secondCount:   Int
    let revenue:       Double
    let pending15Days: Int
    let channelRows:   [ChannelRow]
    let leadUnitPrice: Double

    struct ChannelRow: Identifiable {
        let id = UUID()
        let channel:       String
        let leads:         Int
        let newOrderCount: Int
        var newOrderRate: Double { leads > 0 ? Double(newOrderCount) / Double(leads) : 0 }
        var rateText: String { leads > 0 ? String(format: "%.0f%%", newOrderRate * 100) : "—" }
    }

    var newOrderRate: Double {
        // 新客户成交率统一按“本月有效新单数 ÷ 本月派发资料数”计算。
        // 未签收新单被作废/删除后会从 validConversions 中移除，因此分子会实时下降；
        // 客户资料及本月派发数保持不变。
        totalLeads > 0 ? Double(newOrderCount) / Double(totalLeads) : 0
    }
    var cumulativeNewOrderRate: Double {
        cumulativeLeadCount > 0 ? Double(cumulativeNewOrderCount) / Double(cumulativeLeadCount) : 0
    }
    var secondRate:   Double { newOrderCount > 0 ? Double(secondCount) / Double(newOrderCount) : 0 }
    var newOrderRateText: String { totalLeads > 0 ? String(format: "%.0f%%", newOrderRate * 100) : "—" }
    var cumulativeNewOrderRateText: String {
        cumulativeLeadCount > 0 ? String(format: "%.0f%%", cumulativeNewOrderRate * 100) : "—"
    }
    var secondRateText:   String { newOrderCount > 0 ? String(format: "%.0f%%", secondRate * 100) : "—" }
    var revenueText: String { "¥\(Int(revenue))" }
    var leadCost: Double { Double(totalLeads) * leadUnitPrice }
    var personalROI: Double { leadCost > 0 ? revenue / leadCost : 0 }
    var personalROIText: String { leadCost > 0 ? String(format: "%.2f", personalROI) : "—" }
}

// MARK: 小组 ROI 统计
struct AdvisorTeamStats: Identifiable {
    let groupName: String
    let advisors: [AdvisorStats]
    let leaderNames: [String]
    let memberNames: [String]
    let memberLeadCount: Int
    let totalRevenue: Double
    let leadUnitPrice: Double

    var id: String { groupName }
    var totalCost: Double { Double(memberLeadCount) * leadUnitPrice }
    var roi: Double { totalCost > 0 ? totalRevenue / totalCost : 0 }
    var roiText: String { totalCost > 0 ? String(format: "%.2f", roi) : "—" }
    var revenueText: String { "¥\(Int(totalRevenue))" }
    var costText: String { "¥\(Int(totalCost))" }
    var leaderDisplay: String { leaderNames.isEmpty ? "未设置组长" : leaderNames.joined(separator: "、") }
}

// MARK: 渠道统计（v7）
struct ChannelStats: Identifiable {
    let id = UUID()
    let channel:             String
    let leadCount:           Int     // 该渠道总线索（完整客户）数
    let newOrderCount:       Int     // 有"新单"记录的客户数
    let secondPurchaseCount: Int     // 有"二次"记录的客户数
    let revenue:             Double  // 该渠道全部成交金额之和

    var newOrderRate: Double {
        guard leadCount > 0 else { return 0 }
        return Double(newOrderCount) / Double(leadCount)
    }
    var retentionRate: Double {
        guard newOrderCount > 0 else { return 0 }
        return Double(secondPurchaseCount) / Double(newOrderCount)
    }
    var newOrderRateText:  String { leadCount > 0 ? pct(newOrderRate)  : "—" }
    var retentionRateText: String { newOrderCount > 0 ? pct(retentionRate) : "—" }
    var revenueText: String { "¥\(Int(revenue))" }
    private func pct(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
}

// MARK: 通用画像条目（地域/年龄/金额共用）
struct ProfileItem: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
    let percentage: Double
    // 下钻时用于过滤客户
    let filterKey: String

    var percentageText: String { String(format: "%.1f%%", percentage * 100) }
}

// MARK: ROI 引擎
enum ROIEngine {

    /// “暂未成交二次”的作废现在只是列表级隐藏，不再改变客户的漏斗资格。
    /// 保留该入口供现有调用统一使用，避免旧标记继续影响系统统计。
    static func isFunnelActive(_ customer: Customer) -> Bool {
        true
    }

    /// 待跟进和漏斗分母共用同一套有效线索口径，避免两处人数不一致。
    static func isQualifiedFunnelLead(_ customer: Customer) -> Bool {
        customer.dataType == .fullCustomer &&
        customer.costEnabled &&
        customer.leadAmount != nil &&
        isFunnelActive(customer)
    }

    // MARK: 期间汇总（双轨制）
    //
    // customers  = 该时间窗口内的所有客户记录（fullCustomer + ledgerEntry）
    // 漏斗过滤网：costEnabled == true 的 fullCustomer 才计入漏斗分母和转化率
    // 营业额双轨：funnelRevenue（漏斗内）+ nonFunnelRevenue（漏斗外）= totalRevenue

    // year/month 非 nil 时：线索/成本按 importDate 过滤，营业额按 ConversionRecord.date 过滤
    // allCustomers 用于计算累计新单成交率（全局口径，不受月份限制）
    static func summary(customers: [Customer], leadUnitPrice: Double,
                        year: Int? = nil, month: Int? = nil) -> PeriodSummary {
        let cal = Calendar.current

        // 当期线索（按 importDate）
        let periodCustomers: [Customer]
        if let y = year, let m = month {
            periodCustomers = customers.filter {
                let c = cal.dateComponents([.year, .month], from: $0.importDate)
                return c.year == y && c.month == m
            }
        } else {
            periodCustomers = customers
        }

        let funnelCustomers = periodCustomers.filter(isQualifiedFunnelLead)

        let leadCount = funnelCustomers.count
        let totalCost = funnelCustomers.reduce(0) { $0 + $1.lineCost }

        // 营业额按 ConversionRecord.date 过滤
        func periodConversions(of list: [Customer]) -> [ConversionRecord] {
            let allConvs = list.flatMap { $0.validConversions }
            guard let y = year, let m = month else { return allConvs }
            return allConvs.filter {
                let c = cal.dateComponents([.year, .month], from: $0.date)
                return c.year == y && c.month == m
            }
        }

        // 客户不会因为停止二次跟进而退出漏斗；只有单笔未签收/退款订单会由
        // validConversions 排除，客户资料、派发成本和其他有效成交均保持不变。
        let allFunnelCustomers = customers.filter {
            $0.dataType == .fullCustomer && $0.costEnabled && isFunnelActive($0)
        }
        let allFunnelCustomerIDs = Set(allFunnelCustomers.map { $0.id })
        let allNonFunnelCustomers = customers.filter { !allFunnelCustomerIDs.contains($0.id) }
        let funnelRevenue    = periodConversions(of: allFunnelCustomers).reduce(0) { $0 + $1.amount }
        let nonFunnelRevenue = periodConversions(of: allNonFunnelCustomers).reduce(0) { $0 + $1.amount }

        // 二次成交按开单日期归属看板：
        // “本月”只统计当月开的二次，“累计”统计历史全部二次；客户派发月份不参与过滤。
        let visibleSecondRecords = periodConversions(of: customers.filter(isFunnelActive))
            .filter { $0.type == .second }
        let visibleSecondRecordIDs = Set(visibleSecondRecords.map { $0.id })
        let visibleSecondCustomerIDs = Set(customers.compactMap { customer in
            customer.validConversions.contains { visibleSecondRecordIDs.contains($0.id) }
                ? customer.id : nil
        })

        // 二次率分母跟随看板：本月用当月新单人数，累计用累计新单人数。
        let visibleNewOrderCustomers = periodCustomers.filter(isQualifiedFunnelLead).filter {
            $0.validConversions.contains { $0.type == .newOrder }
        }

        let stages = buildFunnel(
            funnelCustomers: funnelCustomers,
            totalLeads: leadCount,
            secondRecordIDs: visibleSecondRecordIDs,
            secondCustomerIDs: visibleSecondCustomerIDs,
            secondAmount: visibleSecondRecords.reduce(0) { $0 + $1.amount },
            secondDenominator: visibleNewOrderCustomers.count
        )

        // 累计新单成交率（全量口径）
        let qualifiedAll = customers.filter(isQualifiedFunnelLead)
        let cumulativeTotalLeads = qualifiedAll.count
        let cumulativeNewOrderCount = qualifiedAll.filter { $0.validConversions.contains { $0.type == .newOrder } }.count
        let cumulativeRate = cumulativeTotalLeads > 0 ? Double(cumulativeNewOrderCount) / Double(cumulativeTotalLeads) : 0

        // 当月新单成交率（当期口径）
        let qualifiedPeriod = periodCustomers.filter(isQualifiedFunnelLead)
        let monthlyTotalLeads = qualifiedPeriod.count
        let monthlyNewOrderCount = qualifiedPeriod.filter { $0.validConversions.contains { $0.type == .newOrder } }.count
        let monthlyRate = monthlyTotalLeads > 0 ? Double(monthlyNewOrderCount) / Double(monthlyTotalLeads) : 0

        return PeriodSummary(
            importedLeadCount:      leadCount,
            totalCost:              totalCost,
            funnelRevenue:          funnelRevenue,
            nonFunnelRevenue:       nonFunnelRevenue,
            funnelStages:           stages,
            cumulativeNewOrderRate: cumulativeRate,
            monthlyNewOrderRate:    monthlyRate,
            cumulativeNewOrderCount: cumulativeNewOrderCount,
            cumulativeTotalLeads:   cumulativeTotalLeads,
            monthlyNewOrderCount:   monthlyNewOrderCount,
            monthlyTotalLeads:      monthlyTotalLeads
        )
    }

    // MARK: 累计汇总（跨所有时间）
    static func cumulativeSummary(customers: [Customer], leadUnitPrice: Double) -> PeriodSummary {
        summary(customers: customers, leadUnitPrice: leadUnitPrice)
    }

    // MARK: 漏斗（仅新单+二次）—— 分母/分子均来自漏斗内客户
    // 新单率：新单人数 / 总线索数
    // 二次率：二次人数 / 累计新单人数（全局口径）
    private static func buildFunnel(
        funnelCustomers: [Customer],
        totalLeads: Int,
        secondRecordIDs: Set<UUID>,
        secondCustomerIDs: Set<UUID>,
        secondAmount: Double,
        secondDenominator: Int
    ) -> [FunnelStage] {
        let newOrderCustomers = funnelCustomers.filter {
            $0.validConversions.contains { $0.type == .newOrder }
        }
        let newOrderRecords = newOrderCustomers
            .flatMap { $0.validConversions.filter { $0.type == .newOrder } }
        let newOrderCount = newOrderCustomers.count
        let newOrderAmount = newOrderRecords.reduce(0) { $0 + $1.amount }
        let newOrderRate: Double = totalLeads > 0 ? Double(newOrderCount) / Double(totalLeads) : 0

        // “几单”按成交记录笔数统计；同一客户多次二次成交也不会少算。
        let secondCount = secondRecordIDs.count
        // 二次率分母跟随当前看板：本月使用本月新单人数，累计使用累计新单人数。
        let secondRate: Double = secondDenominator > 0
            ? Double(secondCount) / Double(secondDenominator) : 0

        return [
            FunnelStage(label: "新单", count: newOrderCount, totalAmount: newOrderAmount,
                        conversionRate: newOrderRate, denominator: totalLeads,
                        customerIDs: Set(newOrderCustomers.map { $0.id }),
                        conversionRecordIDs: Set(newOrderRecords.map { $0.id })),
            FunnelStage(label: "二次", count: secondCount, totalAmount: secondAmount,
                        conversionRate: secondRate, denominator: secondDenominator,
                        customerIDs: secondCustomerIDs,
                        conversionRecordIDs: secondRecordIDs),
        ]
    }

    // MARK: 七大地理区划（需求4）
    // filterKey 与 regionLabel(for:) 保持一致，供下钻使用
    private static let regionGroups: [(label: String, provinces: [String])] = [
        ("华南地区", ["广东","广州","深圳","珠海","佛山","东莞","中山","惠州","江门","肇庆","广西","海南","香港","澳门"]),
        ("华东地区", ["上海","江苏","南京","苏州","无锡","浙江","杭州","宁波","安徽","福建","厦门","江西","山东","台湾"]),
        ("华北地区", ["北京","天津","河北","山西","内蒙古","内蒙"]),
        ("华中地区", ["河南","郑州","湖北","武汉","湖南","长沙"]),
        ("东北地区", ["辽宁","沈阳","吉林","长春","黑龙江","哈尔滨"]),
        ("西南地区", ["重庆","四川","成都","贵州","云南","昆明","西藏"]),
        ("西北地区", ["陕西","西安","甘肃","青海","宁夏","新疆"]),
    ]

    /// 根据地址字符串返回所属大区 label
    static func regionLabel(for address: String?) -> String {
        guard let addr = address, !addr.isEmpty else { return "未知/其他" }
        for group in regionGroups {
            if group.provinces.contains(where: { addr.contains($0) }) {
                return group.label
            }
        }
        return "未知/其他"
    }

    static func regionProfiles(customers: [Customer]) -> [ProfileItem] {
        let total = customers.count
        guard total > 0 else { return [] }

        var counts: [String: Int] = [:]
        for c in customers {
            let label = regionLabel(for: c.address)
            counts[label, default: 0] += 1
        }

        // 按七大区顺序 + 未知
        let ordered: [String] = regionGroups.map { $0.label } + ["未知/其他"]
        return ordered.compactMap { label -> ProfileItem? in
            guard let count = counts[label], count > 0 else { return nil }
            return ProfileItem(label: label, count: count,
                               percentage: Double(count) / Double(total),
                               filterKey: label)
        }
    }

    // MARK: 年龄段（需求5）
    static func ageProfiles(customers: [Customer]) -> [ProfileItem] {
        let withAge = customers.compactMap { $0.age }
        let total   = withAge.count
        guard total > 0 else { return [] }

        let bands: [(String, ClosedRange<Int>)] = [
            ("20-30岁", 20...29),
            ("30-40岁", 30...39),
            ("40岁以上", 40...120),
            ("20岁以下", 1...19),
        ]
        return bands.compactMap { (label, range) in
            let count = withAge.filter { range.contains($0) }.count
            guard count > 0 else { return nil }
            return ProfileItem(label: label, count: count,
                               percentage: Double(count) / Double(total),
                               filterKey: label)
        }
    }

    // MARK: 渠道分组漏斗（v7）
    //
    // 输入：完整客户列表（dataType == .fullCustomer）
    // 输出：按线索量降序排列的渠道统计列表
    //
    // 分子/分母说明：
    //   新单率  = 有"新单"ConversionRecord 的客户数 / 该渠道总线索数
    //   复购率  = 有"二次"ConversionRecord 的客户数 / 有"新单"的客户数（非总线索）
    //   营业额  = 该渠道全部 ConversionRecord.amount 之和

    static func channelStats(customers: [Customer], year: Int? = nil, month: Int? = nil) -> [ChannelStats] {
        let cal = Calendar.current
        // 线索按 importDate 归月；营业额按 ConversionRecord.date 归月
        let full: [Customer]
        if let y = year, let m = month {
            full = customers.filter {
                guard $0.dataType == .fullCustomer && $0.costEnabled else { return false }
                let c = cal.dateComponents([.year, .month], from: $0.importDate)
                return c.year == y && c.month == m
            }
        } else {
            full = customers.filter { $0.dataType == .fullCustomer && $0.costEnabled }
        }
        guard !full.isEmpty else { return [] }

        let grouped = Dictionary(grouping: full) { $0.channelDisplay }

        return grouped.map { (channel, group) in
            // 营业额：该渠道所有客户中，属于该月的成交记录
            let allGroupCustomers = customers.filter {
                $0.dataType == .fullCustomer && $0.costEnabled && $0.channelDisplay == channel
            }
            let revenue: Double
            if let y = year, let m = month {
                revenue = allGroupCustomers.flatMap { $0.validConversions }.filter {
                    let c = cal.dateComponents([.year, .month], from: $0.date)
                    return c.year == y && c.month == m
                }.reduce(0.0) { $0 + $1.amount }
            } else {
                revenue = allGroupCustomers.flatMap { $0.validConversions }.reduce(0.0) { $0 + $1.amount }
            }
            let newOrders = group.filter { $0.validConversions.contains { $0.type == .newOrder } }.count
            let seconds   = group.filter { $0.validConversions.contains { $0.type == .second  } }.count
            return ChannelStats(
                channel:             channel,
                leadCount:           group.count,
                newOrderCount:       newOrders,
                secondPurchaseCount: seconds,
                revenue:             revenue
            )
        }
        .sorted { $0.leadCount > $1.leadCount }
    }

    // MARK: 顾问绩效统计
    static func advisorStats(customers: [Customer], advisorNames: [String] = [],
                             leadUnitPrice: Double = 0,
                             year: Int? = nil, month: Int? = nil) -> [AdvisorStats] {
        let cal = Calendar.current
        let now = Date()
        let funnelAll = customers.filter {
            $0.dataType == .fullCustomer && $0.costEnabled && isFunnelActive($0)
        }

        // 线索按 importDate 归月
        let periodLeads: [Customer]
        if let y = year, let m = month {
            periodLeads = funnelAll.filter {
                let c = cal.dateComponents([.year, .month], from: $0.importDate)
                return c.year == y && c.month == m
            }
        } else {
            periodLeads = funnelAll
        }

        // 收集所有顾问名（来自 customer.advisor 和 ConversionRecord.advisorSplits）
        let configuredNames = Set(advisorNames)
        var names = configuredNames
        names.formUnion(periodLeads.compactMap { $0.advisor }.filter { !$0.isEmpty })
        for c in customers {
            for r in c.validConversions {
                for s in r.advisorSplits { names.insert(s.name) }
            }
        }
        guard !names.isEmpty else { return [] }

        let fifteenDaysAgo = cal.date(byAdding: .day, value: -15, to: now)!

        // 月度成交率：本月有效新单 / 本月派发资料。
        // 累计数据仅保留在顾问详情中供进一步查看。
        let periodEnd: Date?
        if let y = year, let m = month {
            let periodStart = cal.date(from: DateComponents(year: y, month: m, day: 1))
            periodEnd = periodStart.flatMap { cal.date(byAdding: .month, value: 1, to: $0) }
        } else {
            periodEnd = nil
        }

        func isInSelectedPeriod(_ date: Date) -> Bool {
            guard let y = year, let m = month else { return true }
            let c = cal.dateComponents([.year, .month], from: date)
            return c.year == y && c.month == m
        }

        func isVisibleCumulatively(_ date: Date) -> Bool {
            guard let end = periodEnd else { return true }
            return date < end
        }

        return names.map { name in
            // ROI 成本按首次派发人锁定；转交服务人不会把历史资料成本转给接手人。
            let myLeads = periodLeads.filter { $0.roiAdvisorName == name }

            // 新单列：按实际开单日归期，包含历史月份派发、本月才开单的客户。
            let periodNewOrderCustomers = funnelAll.filter { customer in
                guard customer.roiAdvisorName == name else { return false }
                return customer.validConversions.contains { record in
                    record.type == .newOrder && isInSelectedPeriod(record.date)
                }
            }
            let newOrders = periodNewOrderCustomers.count

            // 累计新客：截止筛选期末的累计派发客户中，已经产生有效新单的客户。
            let cumulativeLeads = funnelAll.filter {
                $0.roiAdvisorName == name && isVisibleCumulatively($0.importDate)
            }
            let cumulativeNewOrders = cumulativeLeads.filter { customer in
                customer.validConversions.contains {
                    $0.type == .newOrder && isVisibleCumulatively($0.date)
                }
            }.count

            // 复购率严格以“本期全部新单客户”为分母，不再按客户派发月份筛选。
            let seconds = periodNewOrderCustomers.filter {
                $0.validConversions.contains { $0.type == .second }
            }.count

            // 营业额：所有客户类型（含 ledgerEntry）中有顾问归属的订单都计入
            var revenue = 0.0
            for customer in customers {
                for record in customer.validConversions {
                    if let y = year, let m = month {
                        let c = cal.dateComponents([.year, .month], from: record.date)
                        guard c.year == y && c.month == m else { continue }
                    }
                    if record.advisorSplits.isEmpty {
                        if customer.advisor == name { revenue += record.amount }
                    } else if let split = record.advisorSplits.first(where: { $0.name == name }) {
                        revenue += record.amount * split.ratio
                    }
                }
            }

            // 待跟进属于运营视角，始终跟随当前服务顾问。
            let allMyLeads = funnelAll.filter { $0.advisor == name }
            let pending15 = allMyLeads.filter {
                $0.importDate >= fifteenDaysAgo &&
                !$0.validConversions.contains { $0.type == .newOrder }
            }.count

            // 渠道拆分
            let channelGroups = Dictionary(grouping: myLeads) { $0.channelDisplay }
            let channelRows = channelGroups.map { (ch, cg) in
                AdvisorStats.ChannelRow(
                    channel:       ch,
                    leads:         cg.count,
                    newOrderCount: cg.filter { customer in
                        customer.validConversions.contains {
                            $0.type == .newOrder && isInSelectedPeriod($0.date)
                        }
                    }.count
                )
            }.sorted { $0.leads > $1.leads }

            return AdvisorStats(
                name:          name,
                totalLeads:    myLeads.count,
                newOrderCount: newOrders,
                cumulativeLeadCount: cumulativeLeads.count,
                cumulativeNewOrderCount: cumulativeNewOrders,
                secondCount:   seconds,
                revenue:       revenue,
                pending15Days: pending15,
                channelRows:   channelRows,
                leadUnitPrice: leadUnitPrice
            )
        }
        .filter { $0.totalLeads > 0 || $0.revenue > 0 || configuredNames.contains($0.name) }
        .sorted { $0.revenue > $1.revenue }
    }

    // MARK: 按小组核算 ROI
    static func advisorTeamStats(advisors: [AdvisorStats],
                                 profiles: [AdvisorProfile],
                                 configuredGroups: [String],
                                 revenueOnlyNames: Set<String> = [],
                                 leadUnitPrice: Double) -> [AdvisorTeamStats] {
        let profileByName = Dictionary(uniqueKeysWithValues: profiles.map { ($0.name, $0) })
        func profile(for name: String) -> AdvisorProfile {
            profileByName[name] ?? AdvisorProfile(name: name)
        }

        let grouped = Dictionary(grouping: advisors) { profile(for: $0.name).groupDisplay }
        var orderedGroups = configuredGroups.filter { grouped[$0] != nil }
        let extraGroups = grouped.keys
            .filter { !orderedGroups.contains($0) && $0 != "未分组" }
            .sorted()
        orderedGroups.append(contentsOf: extraGroups)
        if grouped["未分组"] != nil { orderedGroups.append("未分组") }

        return orderedGroups.compactMap { groupName in
            guard let teamAdvisors = grouped[groupName], !teamAdvisors.isEmpty else { return nil }
            let leaders = teamAdvisors.filter { profile(for: $0.name).role == .leader }
            let members = teamAdvisors.filter { profile(for: $0.name).role == .member }
            return AdvisorTeamStats(
                groupName: groupName,
                advisors: teamAdvisors.sorted {
                    let leftRole = profile(for: $0.name).role
                    let rightRole = profile(for: $1.name).role
                    if leftRole != rightRole { return leftRole == .leader }
                    return $0.revenue > $1.revenue
                },
                leaderNames: leaders.map { $0.name },
                memberNames: members.map { $0.name },
                memberLeadCount: members
                    .filter { !revenueOnlyNames.contains($0.name) }
                    .reduce(0) { $0 + $1.totalLeads },
                totalRevenue: teamAdvisors.reduce(0) { $0 + $1.revenue },
                leadUnitPrice: leadUnitPrice
            )
        }
    }

    // MARK: 线索金额分布（需求2：用 leadAmount，不用 conversions.amount）
    static func amountProfiles(customers: [Customer]) -> [ProfileItem] {
        // 只取有 leadAmount 的客户
        let amounts = customers.compactMap { $0.leadAmount }
        let total   = amounts.count
        guard total > 0 else { return [] }

        let bands: [(String, (Double) -> Bool)] = [
            ("300元以内",  { $0 <= 300 }),
            ("301-500元", { $0 > 300 && $0 <= 500 }),
            ("500元以上",  { $0 > 500 }),
        ]
        return bands.compactMap { (label, pred) in
            let count = amounts.filter(pred).count
            guard count > 0 else { return nil }
            return ProfileItem(label: label, count: count,
                               percentage: Double(count) / Double(total),
                               filterKey: label)
        }
    }
}
