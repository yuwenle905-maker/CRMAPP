// MARK: - AdvisorHubView.swift
// 顾问Tab：总业绩饼图 + 每人详细数据 + 排除顾问/仅计业绩过滤

import SwiftUI

// MARK: - 主 Hub
struct AdvisorHubView: View {

    @EnvironmentObject var store: DataStore

    // 时间范围
    @State private var viewMode: Int = 1
    @State private var selectedYear:  Int = Calendar.current.component(.year,  from: Date())
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())

    // 排除顾问（完全隐藏）
    @AppStorage("hubExcludedAdvisors")  private var excludedRaw:     String = ""
    // 仅计业绩（不统计派发/新单/15天）
    @AppStorage("hubRevenueOnlyAdvisors") private var revenueOnlyRaw: String = ""
    // 展示隐私与演示配置：仅影响 UI，不写入客户或订单数据。
    @AppStorage("presentationDisplayConfig") private var presentationRaw: String = ""
    @State private var showExcludeSheet = false
    @State private var showOrganizationSheet = false
    @State private var showPresentationSettings = false

    private var presentation: PresentationDisplayConfig {
        PresentationDisplayConfig.decode(presentationRaw)
    }
    private var showsRevenue: Bool { true }

    private var yearRange:  [Int] { Array(2023...Calendar.current.component(.year, from: Date())) }
    private var monthRange: [Int] { Array(1...12) }

    private var filterYear:  Int? { viewMode == 1 ? selectedYear  : nil }
    private var filterMonth: Int? { viewMode == 1 ? selectedMonth : nil }

    private var allStats: [AdvisorStats] {
        ROIEngine.advisorStats(customers: store.customers,
                               advisorNames: store.settings.advisors,
                               leadUnitPrice: store.settings.leadUnitPrice,
                               year: filterYear, month: filterMonth)
    }

    private var excluded: Set<String> {
        Set(excludedRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private var revenueOnly: Set<String> {
        Set(revenueOnlyRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private var stats: [AdvisorStats] {
        allStats.filter { !excluded.contains($0.name) }
    }

    private var teamStats: [AdvisorTeamStats] {
        ROIEngine.advisorTeamStats(
            advisors: stats,
            profiles: store.settings.advisorProfiles,
            configuredGroups: store.settings.advisorGroups,
            revenueOnlyNames: revenueOnly,
            leadUnitPrice: store.settings.leadUnitPrice
        )
    }

    private var totalRevenue: Double { stats.reduce(0) { $0 + $1.revenue } }

    private var totalPending15: Int {
        stats.filter { !revenueOnly.contains($0.name) }
             .reduce(0) { $0 + $1.pending15Days }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if presentation.demoEnabled { DemoDataBadge() }
                    periodPicker
                    if !presentation.isHidden(PresentationMetric.totalRevenue) {
                        totalRevenueBanner
                    }

                    if stats.isEmpty {
                        emptyState
                    } else {
                        if totalPending15 > 0 && !presentation.isHidden(PresentationMetric.pendingAlert) { pendingAlert }
                        if unassignedCount > 0 && !presentation.isHidden(PresentationMetric.unassignedAlert) {
                            unassignedAlert
                        }
                        advisorTeamList
                        if !presentation.isHidden(PresentationMetric.revenuePie) {
                            RevenuePieSection(stats: stats, total: totalRevenue,
                                              showsRevenue: showsRevenue,
                                              displayConfig: presentation)
                                .padding(.horizontal)
                        }
                    }

                    Spacer(minLength: 24)
                }
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("顾问")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showOrganizationSheet = true } label: {
                        Image(systemName: "person.3.sequence.fill")
                            .foregroundColor(.blue)
                    }
                    .accessibilityLabel("小组与角色设置")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showExcludeSheet = true } label: {
                        Image(systemName: (excluded.isEmpty && revenueOnly.isEmpty)
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                        .foregroundColor((excluded.isEmpty && revenueOnly.isEmpty) ? .primary : .orange)
                    }
                }
            }
            .sheet(isPresented: $showExcludeSheet) {
                AdvisorFilterSheet(
                    allStats:       allStats,
                    excludedRaw:    $excludedRaw,
                    revenueOnlyRaw: $revenueOnlyRaw
                )
            }
            .sheet(isPresented: $showOrganizationSheet) {
                AdvisorOrganizationSheet()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showPresentationSettings) {
                PresentationSettingsView(
                    rawConfig: $presentationRaw,
                    teams: teamStats,
                    advisors: stats,
                    channels: analyticsChannels,
                    regionItems: analyticsRegions,
                    ageItems: analyticsAges,
                    amountItems: analyticsAmounts,
                    customers: store.customers.filter { $0.dataType == .fullCustomer }
                )
            }
        }
    }

    private var analyticsCustomers: [Customer] {
        if let y = filterYear, let m = filterMonth {
            return store.allCustomers(inYear: y, month: m).filter { $0.dataType == .fullCustomer }
        }
        return store.customers.filter { $0.dataType == .fullCustomer }
    }
    private var analyticsChannels: [ChannelStats] {
        if let y = filterYear, let m = filterMonth {
            return ROIEngine.channelStats(customers: store.customers, year: y, month: m)
        }
        return ROIEngine.channelStats(customers: store.customers)
    }
    private var analyticsRegions: [ProfileItem] { ROIEngine.regionProfiles(customers: analyticsCustomers) }
    private var analyticsAges: [ProfileItem] { ROIEngine.ageProfiles(customers: analyticsCustomers) }
    private var analyticsAmounts: [ProfileItem] { ROIEngine.amountProfiles(customers: analyticsCustomers) }

    // MARK: 时间筛选条
    private var periodPicker: some View {
        VStack(spacing: 8) {
            Picker("", selection: $viewMode) {
                Text("累计").tag(0)
                Text("本月").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if viewMode == 1 {
                HStack(spacing: 8) {
                    Picker("年", selection: $selectedYear) {
                        ForEach(yearRange, id: \.self) { Text("\($0)年").tag($0) }
                    }
                    .pickerStyle(.menu)
                    Picker("月", selection: $selectedMonth) {
                        ForEach(monthRange, id: \.self) { Text("\($0)月").tag($0) }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @State private var showHubRevenueDetail = false

    // MARK: 总业绩横幅（可点击查看明细）
    private var totalRevenueBanner: some View {
        Button {
            guard showsRevenue else { return }
            showHubRevenueDetail = true
        } label: {
            VStack(spacing: 4) {
                Text(viewMode == 1 ? "\(selectedYear)年\(selectedMonth)月总业绩" : "历史累计总业绩")
                    .font(.caption).foregroundColor(.secondary)
                Text(showsRevenue
                     ? presentation.text("top.totalRevenue", fallback: String(format: "¥ %d", Int(totalRevenue)))
                     : "¥ ••••••")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                HStack(spacing: 12) {
                    Text("共 \(stats.count) 位顾问")
                        .font(.caption2).foregroundColor(.secondary)
                    if !excluded.isEmpty {
                        Text("已排除 \(excluded.count) 位")
                            .font(.caption2).foregroundColor(.orange)
                    }
                    if !revenueOnly.isEmpty {
                        Text("\(revenueOnly.count) 位仅计业绩")
                            .font(.caption2).foregroundColor(.blue)
                    }
                    Text(showsRevenue ? "点击查看明细" : "业绩金额已隐藏")
                        .font(.caption2)
                        .foregroundColor(showsRevenue ? .blue : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!presentation.demoEnabled)
        .sheet(isPresented: $showHubRevenueDetail) {
            HubRevenueDetailSheet(
                stats: stats,
                total: totalRevenue,
                year: filterYear, month: filterMonth
            ).environmentObject(store)
        }
    }

    @State private var showPendingDetail    = false
    @State private var showUnassignedDetail = false

    // 当前时段内未完成50/50分配的成交记录数（含无splits和单人独占）
    private var unassignedCount: Int {
        let cal = Calendar.current
        var count = 0
        for c in store.customers {
            for rec in c.validConversions {
                if let y = filterYear, let m = filterMonth {
                    let comp = cal.dateComponents([.year, .month], from: rec.date)
                    guard comp.year == y && comp.month == m else { continue }
                }
                if rec.advisorSplits.count != 2 {
                    count += 1
                }
            }
        }
        return count
    }

    // MARK: 15天未成交提醒条（可点击）
    private var pendingAlert: some View {
        Button { showPendingDetail = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text("共 \(presentation.text("top.pending", fallback: "\(totalPending15)")) 位客户派发超15天尚未成交，请跟进")
                    .font(.caption.bold()).foregroundColor(.orange)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(10)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!presentation.demoEnabled)
        .sheet(isPresented: $showPendingDetail) {
            Pending15DetailSheet(
                advisorNames: Set(stats.filter { !revenueOnly.contains($0.name) }.map { $0.name }),
                year: filterYear, month: filterMonth
            ).environmentObject(store)
        }
    }

    // MARK: 未分配业绩提醒条（可点击）
    private var unassignedAlert: some View {
        Button { showUnassignedDetail = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.minus").foregroundColor(.purple)
                Text("共 \(presentation.text("top.unassigned", fallback: "\(unassignedCount)")) 笔业绩未完成50/50分配")
                    .font(.caption.bold()).foregroundColor(.purple)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.purple)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.purple.opacity(0.08))
            .cornerRadius(10)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!presentation.demoEnabled)
        .sheet(isPresented: $showUnassignedDetail) {
            UnassignedRevenueSheet(year: filterYear, month: filterMonth)
                .environmentObject(store)
        }
    }

    // MARK: 按小组展示顾问与 ROI
    private var advisorTeamList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("小组 ROI").font(.headline)
                    Text("组员按个人核算，组长按全组核算")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    showPresentationSettings = true
                } label: {
                    Image(systemName: presentation.hiddenMetrics.isEmpty ? "eye" : "eye.slash")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("展示与演示设置")
            }

            ForEach(teamStats) { team in
                AdvisorTeamCard(
                    team: team,
                    allStats: stats,
                    profiles: store.settings.advisorProfiles,
                    totalRevenue: totalRevenue,
                    revenueOnly: revenueOnly,
                    showsRevenue: showsRevenue,
                    displayConfig: presentation,
                    year: filterYear,
                    month: filterMonth
                )
                .environmentObject(store)
            }
        }
        .padding(.horizontal)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 44)).foregroundColor(.secondary.opacity(0.4))
            Text("暂无顾问数据")
                .font(.headline).foregroundColor(.secondary)
            Text("在【设置】页添加顾问姓名，\n导入客户时选择负责人即可开始统计")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - 顾问页内的小组与角色设置
private struct AdvisorOrganizationSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                AdvisorManagementSection()
            }
            .navigationTitle("小组与角色")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("完成") { dismiss() })
        }
    }
}

// MARK: - 单个小组卡片
private struct AdvisorTeamCard: View {
    @EnvironmentObject var store: DataStore

    let team: AdvisorTeamStats
    let allStats: [AdvisorStats]
    let profiles: [AdvisorProfile]
    let totalRevenue: Double
    let revenueOnly: Set<String>
    let showsRevenue: Bool
    let displayConfig: PresentationDisplayConfig
    let year: Int?
    let month: Int?

    private func profile(for name: String) -> AdvisorProfile {
        profiles.first(where: { $0.name == name }) ?? AdvisorProfile(name: name)
    }

    private func color(for name: String) -> Color {
        let index = allStats.firstIndex(where: { $0.name == name }) ?? 0
        return AdvisorPalette.color(for: index)
    }

    private func roiText(for stat: AdvisorStats, profile: AdvisorProfile) -> String {
        if profile.role == .leader { return team.roiText }
        if revenueOnly.contains(stat.name) { return "—" }
        return stat.personalROIText
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.3.fill")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayConfig.text(PresentationKey.team(team.groupName, "name"), fallback: team.groupName)).font(.headline)
                            Text("组长：\(displayConfig.text(PresentationKey.team(team.groupName, "leader"), fallback: team.leaderDisplay))")
                                .font(.caption2)
                                .foregroundColor(team.leaderNames.isEmpty ? .orange : .secondary)
                        }
                    }
                    Spacer()
                    Text("\(displayConfig.text(PresentationKey.team(team.groupName, "members"), fallback: "\(team.advisors.count)")) 人")
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    if !displayConfig.isHidden(PresentationMetric.teamROI) {
                        TeamMetric(title: "小组ROI", value: showsRevenue ? displayConfig.text(PresentationKey.team(team.groupName, "roi"), fallback: team.roiText) : "••", color: .blue)
                    }
                    if !displayConfig.isHidden(PresentationMetric.teamRevenue) {
                        TeamMetric(title: "小组业绩", value: showsRevenue ? displayConfig.text(PresentationKey.team(team.groupName, "revenue"), fallback: team.revenueText) : "••••", color: .indigo)
                    }
                    if !displayConfig.isHidden(PresentationMetric.teamLeads) {
                        TeamMetric(title: "组员派发", value: displayConfig.text(PresentationKey.team(team.groupName, "leads"), fallback: "\(team.memberLeadCount) 条"), color: .orange)
                    }
                }

            }
            .padding(14)

            Divider()

            HStack(spacing: 0) {
                Text("员工").frame(width: 56, alignment: .leading)
                if !displayConfig.isHidden(PresentationMetric.advisorLeads) { Text("派发").frame(maxWidth: .infinity, alignment: .trailing) }
                if !displayConfig.isHidden(PresentationMetric.advisorOrders) { Text("新单").frame(maxWidth: .infinity, alignment: .trailing) }
                if !displayConfig.isHidden(PresentationMetric.advisorPending) {
                    Text("未成交\n(15天)").multilineTextAlignment(.trailing).foregroundColor(.orange).frame(maxWidth: .infinity, alignment: .trailing)
                }
                if !displayConfig.isHidden(PresentationMetric.advisorRevenue) { Text("业绩").frame(width: 68, alignment: .trailing) }
                Spacer().frame(width: 16)
            }
            .font(.caption2.bold())
            .foregroundColor(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(Color(.systemGroupedBackground))

            ForEach(Array(team.advisors.enumerated()), id: \.element.id) { index, stat in
                let employeeProfile = profile(for: stat.name)
                NavigationLink(destination:
                    AdvisorDetailView(
                        stat: stat,
                        year: year,
                        month: month,
                        role: employeeProfile.role,
                        groupName: employeeProfile.groupDisplay,
                        roiText: roiText(for: stat, profile: employeeProfile)
                    )
                        .environmentObject(store)
                ) {
                    AdvisorHubRow(
                        stat: stat,
                        color: color(for: stat.name),
                        share: totalRevenue > 0 ? stat.revenue / totalRevenue : 0,
                        revenueOnly: revenueOnly.contains(stat.name),
                        showsRevenue: showsRevenue,
                        displayConfig: displayConfig,
                        role: employeeProfile.role,
                        roiText: roiText(for: stat, profile: employeeProfile)
                    )
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!displayConfig.demoEnabled)
                if index < team.advisors.count - 1 {
                    Divider().padding(.leading, 20)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

private struct TeamMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - 顾问过滤 Sheet（排除 + 仅计业绩）
// 用 ScrollView 而非 List，避免 List 行拦截按钮触摸
struct AdvisorFilterSheet: View {
    let allStats: [AdvisorStats]
    @Binding var excludedRaw:    String
    @Binding var revenueOnlyRaw: String
    @Environment(\.dismiss) var dismiss

    private var excluded: Set<String> {
        Set(excludedRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }
    private var revenueOnly: Set<String> {
        Set(revenueOnlyRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    // 三态：0=正常 1=仅计业绩 2=完全排除
    private func currentMode(_ name: String) -> Int {
        if excluded.contains(name)    { return 2 }
        if revenueOnly.contains(name) { return 1 }
        return 0
    }

    private func setMode(_ name: String, mode: Int) {
        var ex = excluded
        var ro = revenueOnly
        ex.remove(name); ro.remove(name)        // 先清除
        if mode == 1 { ro.insert(name) }
        if mode == 2 { ex.insert(name) }
        excludedRaw    = ex.joined(separator: ",")
        revenueOnlyRaw = ro.joined(separator: ",")
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // 说明条
                    Text("正常统计：完整显示派发/新单/15天\n仅计业绩：派发/新单/15天显示「—」\n完全排除：不出现在列表和饼图")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding()

                    ForEach(allStats) { stat in
                        let mode = currentMode(stat.name)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(stat.name).font(.subheadline.bold())
                                Spacer()
                                Text(stat.revenueText)
                                    .font(.caption).foregroundColor(.secondary)
                            }

                            // 三选一按钮组（独立 Button，不嵌套在 List 行里）
                            HStack(spacing: 8) {
                                segBtn(label: "正常统计", active: mode == 0, color: .blue)  { setMode(stat.name, mode: 0) }
                                segBtn(label: "仅计业绩", active: mode == 1, color: .purple) { setMode(stat.name, mode: 1) }
                                segBtn(label: "完全排除", active: mode == 2, color: .red)    { setMode(stat.name, mode: 2) }
                            }
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.top, 4)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("顾问统计设置")
            .navigationBarItems(trailing: Button("完成") { dismiss() })
        }
    }

    private func segBtn(label: String, active: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(active ? color : Color(.systemFill))
                .foregroundColor(active ? .white : .primary)
                .cornerRadius(8)
        }
    }
}

// MARK: - 顾问行（紧凑版）
private struct AdvisorHubRow: View {
    let stat:        AdvisorStats
    let color:       Color
    let share:       Double
    let revenueOnly: Bool
    let showsRevenue: Bool
    let displayConfig: PresentationDisplayConfig
    let role:         AdvisorRole
    let roiText:      String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                // 色条 + 顾问名（固定宽度，不拉伸）
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 5, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayConfig.text(PresentationKey.advisor(stat.name, "name"), fallback: stat.name)).font(.subheadline.bold()).foregroundColor(.primary)
                        if revenueOnly {
                            Text("仅计业绩").font(.caption2).foregroundColor(.blue)
                        } else {
                            Text(role.rawValue)
                                .font(.caption2)
                                .foregroundColor(role == .leader ? .orange : .secondary)
                        }
                    }
                }
                .frame(width: 56, alignment: .leading)

                // 派发
                if !displayConfig.isHidden(PresentationMetric.advisorLeads) {
                    Text(revenueOnly ? "—" : displayConfig.text(PresentationKey.advisor(stat.name, "leads"), fallback: "\(stat.totalLeads)"))
                        .font(.subheadline.bold()).foregroundColor(revenueOnly ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                // 新单成交
                if !displayConfig.isHidden(PresentationMetric.advisorOrders) {
                    Text(revenueOnly ? "—" : displayConfig.text(PresentationKey.advisor(stat.name, "orders"), fallback: "\(stat.newOrderCount)"))
                        .font(.subheadline.bold()).foregroundColor(revenueOnly ? .secondary : .blue)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                // 15天未成交
                if !displayConfig.isHidden(PresentationMetric.advisorPending) {
                    Group {
                        if revenueOnly {
                            Text("—").foregroundColor(.secondary)
                        } else {
                            Text(stat.pending15Days > 0 ? displayConfig.text(PresentationKey.advisor(stat.name, "pending"), fallback: "\(stat.pending15Days)") : "—")
                                .foregroundColor(stat.pending15Days > 0 ? .red : .secondary)
                        }
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                // 业绩
                if !displayConfig.isHidden(PresentationMetric.advisorRevenue) {
                    Text(showsRevenue ? displayConfig.text(PresentationKey.advisor(stat.name, "revenue"), fallback: stat.revenueText) : "••••")
                        .font(.caption.bold()).foregroundColor(showsRevenue ? .indigo : .secondary)
                        .frame(width: 68, alignment: .trailing)
                }

                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                    .frame(width: 16, alignment: .trailing)
            }

            // 首页保持简洁：只展示 ROI 和新客户成交率。
            // 累计新客成交率、复购率可点击顾问进入详情查看。
            HStack(spacing: 6) {
                if !displayConfig.isHidden(PresentationMetric.advisorROI) {
                    rateChip(value: showsRevenue ? displayConfig.text(PresentationKey.advisor(stat.name, "roi"), fallback: roiText) : "••", label: role == .leader ? "小组ROI" : "个人ROI", color: .purple)
                }
                if !revenueOnly && !displayConfig.isHidden(PresentationMetric.advisorRate) {
                    rateChip(value: displayConfig.text(PresentationKey.advisor(stat.name, "rate"), fallback: stat.newOrderRateText), label: "新客户成交率", color: .blue)
                }
                Spacer()
                if !displayConfig.isHidden(PresentationMetric.advisorShare) {
                    Text(displayConfig.text(PresentationKey.advisor(stat.name, "share"), fallback: String(format: "占比 %.0f%%", share * 100)))
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.leading, 11)

            // 占比进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(.systemFill)).frame(height: 3)
                    RoundedRectangle(cornerRadius: 2).fill(color)
                        .frame(width: geo.size.width * share, height: 3)
                }
            }
            .frame(height: 3)
            .padding(.leading, 11)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func rateChip(value: String, label: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.caption2.bold()).foregroundColor(value == "—" ? .secondary : color)
        }
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(value == "—" ? Color(.systemFill) : color.opacity(0.1))
        .cornerRadius(4)
    }
}

// MARK: - 饼图区（Canvas，iOS 15+）
struct RevenuePieSection: View {
    let stats: [AdvisorStats]
    let total: Double
    let showsRevenue: Bool
    var displayConfig: PresentationDisplayConfig = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("业绩占比").font(.headline).padding(.top, 4)

            HStack(alignment: .center, spacing: 20) {
                Canvas { ctx, size in
                    guard total > 0 else { return }
                    let cx = size.width / 2, cy = size.height / 2
                    let r  = min(cx, cy) - 4
                    var startAngle = Angle(degrees: -90)
                    for (i, stat) in stats.enumerated() {
                        let sweep = Angle(degrees: 360 * stat.revenue / total)
                        let path  = Path { p in
                            p.move(to: CGPoint(x: cx, y: cy))
                            p.addArc(center: CGPoint(x: cx, y: cy),
                                     radius: r,
                                     startAngle: startAngle,
                                     endAngle: startAngle + sweep,
                                     clockwise: false)
                            p.closeSubpath()
                        }
                        ctx.fill(path, with: .color(AdvisorPalette.color(for: i)))
                        startAngle += sweep
                    }
                    let hole = Path(ellipseIn: CGRect(x: cx - r * 0.5, y: cy - r * 0.5,
                                                      width: r, height: r))
                    ctx.fill(hole, with: .color(Color(.secondarySystemGroupedBackground)))
                }
                .frame(width: 140, height: 140)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(stats.enumerated()), id: \.element.id) { i, stat in
                        HStack(spacing: 6) {
                            Circle().fill(AdvisorPalette.color(for: i)).frame(width: 10, height: 10)
                            Text(displayConfig.text(PresentationKey.advisor(stat.name, "name"), fallback: stat.name)).font(.caption2).foregroundColor(.primary)
                            Spacer()
                            let percentage = String(
                                format: "%.0f%%",
                                total > 0 ? stat.revenue / total * 100 : 0
                            )
                            let displayedRevenue = displayConfig.text(PresentationKey.advisor(stat.name, "revenue"), fallback: stat.revenueText)
                            Text(showsRevenue ? "\(percentage)  \(displayedRevenue)" : percentage)
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - 总业绩明细 Sheet（按客户列出贡献）
struct HubRevenueDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: DataStore

    let stats:  [AdvisorStats]
    let total:  Double
    var year:   Int?
    var month:  Int?

    // 汇总每个客户对所有顾问的贡献
    private struct CustomerEntry: Identifiable {
        let id = UUID()
        let customer: Customer
        let advisorName: String
        let amount: Double
    }

    private var entries: [CustomerEntry] {
        let cal = Calendar.current
        var result: [CustomerEntry] = []
        let advisorNames = Set(stats.map { $0.name })
        for c in store.customers {
            for rec in c.validConversions {
                if let y = year, let m = month {
                    let comp = cal.dateComponents([.year, .month], from: rec.date)
                    guard comp.year == y && comp.month == m else { continue }
                }
                if rec.advisorSplits.isEmpty {
                    if let adv = c.advisor, !adv.isEmpty, advisorNames.contains(adv) {
                        result.append(CustomerEntry(customer: c, advisorName: adv, amount: rec.amount))
                    }
                } else {
                    for split in rec.advisorSplits where advisorNames.contains(split.name) {
                        result.append(CustomerEntry(customer: c, advisorName: split.name,
                                                    amount: rec.amount * split.ratio))
                    }
                }
            }
        }
        return result.sorted { $0.amount > $1.amount }
    }

    private var totalText: String { String(format: "¥ %d", Int(total)) }

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Text("总计").font(.headline)
                        Spacer()
                        Text(totalText).font(.title3.bold()).foregroundColor(.indigo)
                    }
                }

                Section(header: Text("全部成交记录（\(entries.count) 笔）")) {
                    ForEach(entries) { entry in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(entry.customer.name).font(.subheadline.bold())
                                    if let num = entry.customer.customerNumber {
                                        Text("#\(num)").font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                Text(entry.advisorName)
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }
                            Spacer()
                            Text("¥\(Int(entry.amount))")
                                .font(.subheadline.bold()).foregroundColor(.indigo)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("业绩总明细")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("完成") { dismiss() })
        }
    }
}

// MARK: - 15天未成交明细 Sheet
struct Pending15DetailSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: DataStore

    let advisorNames: Set<String>
    var year:  Int?
    var month: Int?

    private var pendingCustomers: [Customer] {
        let now = Date()
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -15, to: now) else { return [] }
        return store.customers.filter { c in
            guard c.dataType == .fullCustomer,
                  c.costEnabled,
                  ROIEngine.isFunnelActive(c),
                  advisorNames.contains(c.advisor ?? "") else { return false }
            return c.importDate >= cutoff && !c.validConversions.contains { $0.type == .newOrder }
        }.sorted { $0.importDate < $1.importDate }
    }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("共 \(pendingCustomers.count) 位，按派发时间升序")) {
                    if pendingCustomers.isEmpty {
                        Text("暂无超15天未成交客户").foregroundColor(.secondary).font(.caption)
                    } else {
                        ForEach(pendingCustomers) { c in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(c.name).font(.subheadline.bold())
                                        if let num = c.customerNumber {
                                            Text("#\(num)").font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                    Text("派发：\(c.importDate.chineseDate)")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                if let adv = c.advisor, !adv.isEmpty {
                                    Text(adv).font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue).cornerRadius(4)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("15天未成交")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("完成") { dismiss() })
        }
    }
}

// MARK: - 未分配业绩 Sheet
struct UnassignedRevenueSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: DataStore

    var year:  Int?
    var month: Int?

    @State private var editTarget: UnassignedEntry?

    struct UnassignedEntry: Identifiable {
        let id = UUID()
        let customer: Customer
        let record:   ConversionRecord
        var isSinglePerson: Bool { record.advisorSplits.count == 1 }
    }

    private var entries: [UnassignedEntry] {
        let cal = Calendar.current
        var result: [UnassignedEntry] = []
        for c in store.customers {
            for rec in c.validConversions {
                if let y = year, let m = month {
                    let comp = cal.dateComponents([.year, .month], from: rec.date)
                    guard comp.year == y && comp.month == m else { continue }
                }
                if rec.advisorSplits.count != 2 {
                    result.append(UnassignedEntry(customer: c, record: rec))
                }
            }
        }
        return result.sorted { $0.record.date > $1.record.date }
    }

    private var totalAmount: Double { entries.reduce(0) { $0 + $1.record.amount } }

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Text("待处理合计").font(.headline)
                        Spacer()
                        Text(String(format: "¥ %d", Int(totalAmount)))
                            .font(.title3.bold()).foregroundColor(.purple)
                    }
                }
                Section(header: Text("共 \(entries.count) 笔 · 点击分配")) {
                    if entries.isEmpty {
                        Text("所有业绩均已完成50/50分配 ✓").foregroundColor(.secondary).font(.caption)
                    } else {
                        ForEach(entries) { e in
                            Button { editTarget = e } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(e.customer.name).font(.subheadline.bold())
                                                .foregroundColor(.primary)
                                            if let num = e.customer.customerNumber {
                                                Text("#\(num)").font(.caption2).foregroundColor(.secondary)
                                            }
                                            if e.isSinglePerson {
                                                Text("单人")
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                                    .background(Color.orange.opacity(0.15))
                                                    .foregroundColor(.orange).cornerRadius(3)
                                            } else {
                                                Text("未填")
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                                    .background(Color.red.opacity(0.12))
                                                    .foregroundColor(.red).cornerRadius(3)
                                            }
                                        }
                                        Text(e.record.type.rawValue + " · " + e.record.date.chineseDate)
                                            .font(.caption2).foregroundColor(.secondary)
                                        if e.isSinglePerson, let s = e.record.advisorSplits.first {
                                            Text("当前：\(s.name) 100%")
                                                .font(.caption2).foregroundColor(.orange)
                                        }
                                    }
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Text("¥\(Int(e.record.amount))")
                                            .font(.subheadline.bold()).foregroundColor(.indigo)
                                        Image(systemName: "chevron.right")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("待分配业绩")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("完成") { dismiss() })
            .sheet(item: $editTarget) { e in
                ConversionAdvisorSheet(customerID: e.customer.id, recordID: e.record.id)
                    .environmentObject(store)
            }
        }
    }
}

// MARK: - 顾问配色表
enum AdvisorPalette {
    static let palette: [Color] = [
        .blue, .orange, .green, .purple, .pink,
        Color(red: 0.0, green: 0.6, blue: 0.8),
        Color(red: 0.9, green: 0.5, blue: 0.1),
        Color(red: 0.3, green: 0.7, blue: 0.3),
    ]
    static func color(for index: Int) -> Color {
        palette[index % palette.count]
    }
}
