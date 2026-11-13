// MARK: - DashboardView.swift
// ROI 核心看板 — 月/年 ROI + 可折叠漏斗 + 可点击画像统计（iOS 15 兼容）

import SwiftUI

// MARK: - 看板视图模式
enum DashboardViewMode: String, CaseIterable {
    case monthly    = "本月"
    case cumulative = "累计"
}

struct DashboardView: View {

    @EnvironmentObject var store: DataStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewMode:     DashboardViewMode = .monthly
    @State private var selectedYear:  Int = Calendar.current.component(.year,  from: Date())
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var observedSystemYear:  Int = Calendar.current.component(.year,  from: Date())
    @State private var observedSystemMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var funnelExpanded:  Bool = true
    @AppStorage("presentationDisplayConfig") private var presentationRaw: String = ""
    @State private var showPresentationSettings = false

    private var presentation: PresentationDisplayConfig { .decode(presentationRaw) }

    // 漏斗内客户（全量，用于待跟进卡片）
    private var qualifiedCustomers: [Customer] {
        store.customers.filter(ROIEngine.isQualifiedFunnelLead)
    }
    // 暂未成交新单（无任何 newOrder 记录）
    private var pendingNewOrder: [Customer] {
        qualifiedCustomers.filter { !$0.validConversions.contains { $0.type == .newOrder } }
    }
    // 15天内派发且暂未成交新单
    private var pending15DaysNewOrder: [Customer] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -15, to: Date())!
        return pendingNewOrder.filter { $0.importDate >= cutoff }
    }
    // 暂未成交二次（有 newOrder 但无 second）
    private var pendingSecond: [Customer] {
        let dismissed = Set(store.settings.dismissedPendingSecondCustomerIDs)
        return qualifiedCustomers.filter {
            !dismissed.contains($0.id) &&
            $0.validConversions.contains { $0.type == .newOrder } &&
            !$0.validConversions.contains { $0.type == .second }
        }
    }

    // ── 当前视图模式下的客户集合 ───────────────────────────
    private var activeCustomers: [Customer] {
        switch viewMode {
        case .monthly:    return store.allCustomers(inYear: selectedYear, month: selectedMonth)
        case .cumulative: return store.customers
        }
    }
    // 仅完整客户（画像统计用）
    private var activeFullCustomers: [Customer] {
        activeCustomers.filter { $0.dataType == .fullCustomer }
    }
    private var activeSummary: PeriodSummary {
        switch viewMode {
        case .monthly:
            return ROIEngine.summary(customers: store.customers,
                                     leadUnitPrice: store.settings.leadUnitPrice,
                                     year: selectedYear, month: selectedMonth)
        case .cumulative:
            return ROIEngine.summary(customers: store.customers,
                                     leadUnitPrice: store.settings.leadUnitPrice)
        }
    }
    private var yearSummary: PeriodSummary {
        ROIEngine.summary(customers: store.customers,
                          leadUnitPrice: store.settings.leadUnitPrice,
                          year: selectedYear, month: nil)
    }

    private var periodLabel: String {
        switch viewMode {
        case .monthly:    return "\(selectedYear)年\(selectedMonth)月"
        case .cumulative: return "历史累计"
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if presentation.demoEnabled { DemoDataBadge() }

                    // 月度 / 累计 Tab 切换
                    Picker("视图", selection: $viewMode) {
                        ForEach(DashboardViewMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // 月度模式显示时间选择器
                    if viewMode == .monthly {
                        PeriodPickerView(year: $selectedYear, month: $selectedMonth)
                            .padding(.horizontal)
                    }

                    // KPI 四格
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {

                        // ROI（漏斗内业绩 / 成本）
                        if !presentation.isHidden(PresentationMetric.dashboardROI) {
                            KPICard(title: "\(periodLabel) ROI",
                                    value: presentation.text("dashboard.roi", fallback: activeSummary.roiText),
                                    subtitle: "漏斗业绩 / 成本",
                                    color: activeSummary.roi >= 1 ? .green : .orange)
                        }

                        // 年度 ROI（对比参考）
                        if !presentation.isHidden(PresentationMetric.dashboardYearROI) {
                            KPICard(title: "\(selectedYear)年 ROI",
                                    value: presentation.text("dashboard.yearROI", fallback: yearSummary.roiText),
                                    subtitle: "年度漏斗口径",
                                    color: yearSummary.roi >= 1 ? .green : .orange)
                        }

                        // 成本 — 点击明细
                        if !presentation.isHidden(PresentationMetric.dashboardCost) {
                            NavigationLink(destination:
                                MonthlyCostDetailView(
                                    customers: activeCustomers,
                                    year: selectedYear, month: selectedMonth
                                )
                            ) {
                                KPICard(title: "\(periodLabel)成本",
                                        value: presentation.text("dashboard.cost", fallback: "¥\(Int(activeSummary.totalCost))"),
                                        subtitle: "\(presentation.text("dashboard.leads", fallback: "\(activeSummary.importedLeadCount) 条"))（点击明细）",
                                        color: .blue)
                            }
                            .buttonStyle(.plain)
                            .allowsHitTesting(!presentation.demoEnabled)
                        }

                        // 全量营业额 — 点击双轨明细
                        if !presentation.isHidden(PresentationMetric.dashboardRevenue) {
                            NavigationLink(destination:
                                RevenueBreakdownView(
                                    customers: store.customers,
                                    year: viewMode == .monthly ? selectedYear  : nil,
                                    month: viewMode == .monthly ? selectedMonth : nil,
                                    periodLabel: periodLabel
                                )
                            ) {
                                KPICard(title: "\(periodLabel)营业额",
                                        value: presentation.text("dashboard.revenue", fallback: "¥\(Int(activeSummary.totalRevenue))"),
                                        subtitle: "漏斗\(presentation.text("dashboard.funnelRevenue", fallback: "¥\(Int(activeSummary.funnelRevenue))")) + 其他\(presentation.text("dashboard.otherRevenue", fallback: "¥\(Int(activeSummary.nonFunnelRevenue))"))",
                                        color: .indigo)
                            }
                            .buttonStyle(.plain)
                            .allowsHitTesting(!presentation.demoEnabled)
                        }
                    }
                    .padding(.horizontal)

                    // 待跟进客户卡片
                    if !presentation.isHidden(PresentationMetric.dashboardFollowUp) {
                        FollowUpCard(pendingNewOrder: pendingNewOrder,
                                     pendingSecond: pendingSecond,
                                     pending15Days: pending15DaysNewOrder,
                                     displayConfig: presentation)
                            .padding(.horizontal)
                    }

                    // 销售漏斗（仅漏斗内客户）
                    if !presentation.isHidden(PresentationMetric.dashboardFunnel) {
                        FunnelCard(stages: activeSummary.funnelStages,
                                   summary: activeSummary,
                                   allCustomers: store.customers,
                                   viewMode: viewMode,
                                   expanded: $funnelExpanded,
                                   displayConfig: presentation)
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 32)
                }
                .padding(.top)
            }
            .navigationTitle("数据看板")
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showPresentationSettings = true } label: {
                        Image(systemName: presentation.hiddenMetrics.isEmpty ? "eye" : "eye.slash")
                    }
                    .accessibilityLabel("展示与演示设置")
                }
            }
            .sheet(isPresented: $showPresentationSettings) {
                PresentationSettingsView(rawConfig: $presentationRaw,
                                         customers: activeFullCustomers,
                                         dashboardSummary: activeSummary,
                                         dashboardYearSummary: yearSummary)
            }
        }
        .environment(\.presentationDisplayConfig, presentation)
        .onAppear { syncToCurrentMonthIfCalendarChanged() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { syncToCurrentMonthIfCalendarChanged() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            syncToCurrentMonthIfCalendarChanged()
        }
    }

    /// App 跨月运行或从后台恢复时，自动切换到新的当前月份。
    /// 同一月份内仍保留用户手动选择的历史月份，不强制跳回。
    private func syncToCurrentMonthIfCalendarChanged() {
        let now = Date()
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: now)
        let currentMonth = cal.component(.month, from: now)
        guard currentYear != observedSystemYear || currentMonth != observedSystemMonth else { return }

        observedSystemYear = currentYear
        observedSystemMonth = currentMonth
        selectedYear = currentYear
        selectedMonth = currentMonth
        viewMode = .monthly
    }
}

// MARK: - 下钻类型
enum DrillType { case region, age, amount }

// MARK: - 可点击下钻的画像卡片（需求3）
struct DrillDownProfileCard: View {

    let title:        String
    let items:        [ProfileItem]
    let allCustomers: [Customer]
    let drillType:    DrillType
    var displayConfig: PresentationDisplayConfig = .empty

    var total: Int { items.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).padding(.horizontal).padding(.top)

            ForEach(items) { item in
                NavigationLink(destination:
                    DrillDownCustomerList(
                        title:       item.label,
                        filterKey:   item.filterKey,
                        customers:   allCustomers,
                        drillType:   drillType
                    )
                ) {
                    VStack(spacing: 4) {
                        HStack {
                            Text(displayConfig.text(PresentationKey.profile(title, item.label, "label"), fallback: item.label))
                                .font(.subheadline).foregroundColor(.primary)
                            Spacer()
                            if !displayConfig.isHidden(PresentationMetric.profileCount) {
                                Text(displayConfig.text(PresentationKey.profile(title, item.label, "count"), fallback: "\(item.count) 人"))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            if !displayConfig.isHidden(PresentationMetric.profilePercent) {
                                Text(displayConfig.text(PresentationKey.profile(title, item.label, "percent"), fallback: item.percentageText))
                                    .font(.subheadline.bold()).foregroundColor(.blue)
                                    .frame(width: 56, alignment: .trailing)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.systemGray5)).frame(height: 6)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.blue)
                                    .frame(
                                        width: total > 0
                                            ? geo.size.width * CGFloat(item.count) / CGFloat(total)
                                            : 0,
                                        height: 6
                                    )
                                    .animation(.easeInOut, value: item.count)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!displayConfig.demoEnabled)
            }
            Spacer(minLength: 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - 下钻客户列表页（需求3）
struct DrillDownCustomerList: View {

    let title:      String
    let filterKey:  String
    let customers:  [Customer]
    let drillType:  DrillType

    private var filtered: [Customer] {
        switch drillType {
        case .region:
            return customers.filter { ROIEngine.regionLabel(for: $0.address) == filterKey }
        case .age:
            return customers.filter { c in
                guard let age = c.age else { return false }
                switch filterKey {
                case "20-30岁":  return (20...29).contains(age)
                case "30-40岁":  return (30...39).contains(age)
                case "40岁以上": return age >= 40
                case "20岁以下": return age < 20
                default:         return false
                }
            }
        case .amount:
            return customers.filter { c in
                guard let amt = c.leadAmount else { return false }
                switch filterKey {
                case "300元以内":  return amt <= 300
                case "301-500元": return amt > 300 && amt <= 500
                case "500元以上":  return amt > 500
                default:           return false
                }
            }
        }
    }

    var body: some View {
        List {
            Section(header: Text("\(title) · \(filtered.count) 人")) {
                ForEach(filtered) { customer in
                    NavigationLink(destination: CustomerDetailView(customer: customer)) {
                        CustomerRow(customer: customer)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 时间选择器
struct PeriodPickerView: View {
    @Binding var year: Int
    @Binding var month: Int

    var body: some View {
        HStack {
            Stepper("\(year)年", value: $year, in: 2020...2099).labelsHidden()
            Text("\(year)年").fontWeight(.semibold)
            Spacer()
            Picker("月份", selection: $month) {
                ForEach(1...12, id: \.self) { m in Text("\(m)月").tag(m) }
            }
            .pickerStyle(.menu)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - KPI 卡片
struct KPICard: View {
    let title: String; let value: String; let subtitle: String; let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title2.bold()).foregroundColor(color)
            Text(subtitle).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - 漏斗卡片
struct FunnelCard: View {
    let stages:       [FunnelStage]
    let summary:      PeriodSummary
    let allCustomers: [Customer]  // 全量漏斗客户（含全时段），用于下钻
    let viewMode:     DashboardViewMode
    @Binding var expanded: Bool
    var displayConfig: PresentationDisplayConfig = .empty

    // 累计新单客户（全量）
    private var cumulativeNewOrderCustomers: [Customer] {
        allCustomers.filter { $0.validConversions.contains { $0.type == .newOrder } }
    }
    // 当月新单客户（由 summary 的月度分母推导：已有 stage 里的 newOrder 客户即为当期）
    // stage[0] = 新单，其 allCustomers 已是当期过滤后的客户
    private var monthlyNewOrderCustomers: [Customer] {
        // 取当期（已在 allCustomers 中按 importDate 过滤）且有新单的客户
        // allCustomers 此时为全量，通过 summary.monthlyTotalLeads 不好直接拿客户
        // 直接用 stages[0] 的下钻逻辑即可（FunnelStageCustomerList 内部过滤）
        return []  // 占位，下钻用 stages[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3)) { expanded.toggle() }
            } label: {
                HStack {
                    Text("销售漏斗").font(.headline).foregroundColor(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary).font(.caption)
                }
                .padding()
            }

            if expanded {
                Divider()
                VStack(spacing: 0) {
                    // 累计新单成交率行
                    NavigationLink(destination:
                        SimpleCustomerList(
                            title: "累计新单客户",
                            subtitle: "\(summary.cumulativeNewOrderCount) 人",
                            customers: cumulativeNewOrderCustomers)
                    ) {
                        FunnelRateRow(
                            label:       "累计新单成交率",
                            rateText:    displayConfig.text("dashboard.cumulativeRate", fallback: summary.cumulativeNewOrderRateText),
                            fraction:    displayConfig.text("dashboard.cumulativeFraction", fallback: "\(summary.cumulativeNewOrderCount)/\(summary.cumulativeTotalLeads)")
                        )
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(!displayConfig.demoEnabled)

                    Divider().padding(.leading)

                    // 当月新单成交率行（仅月度模式）
                    if viewMode == .monthly, let newOrderStage = stages.first {
                        NavigationLink(destination:
                            FunnelStageCustomerList(stage: newOrderStage, allCustomers: allCustomers)
                        ) {
                            FunnelRateRow(
                                label:    "当月新单成交率",
                                rateText: displayConfig.text("dashboard.monthlyRate", fallback: summary.monthlyNewOrderRateText),
                                fraction: displayConfig.text("dashboard.monthlyFraction", fallback: "\(summary.monthlyNewOrderCount)/\(summary.monthlyTotalLeads)")
                            )
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(!displayConfig.demoEnabled)
                        Divider().padding(.leading)
                    }

                    // 二次（stages[1]）
                    if stages.count > 1 {
                        NavigationLink(destination:
                            FunnelStageCustomerList(stage: stages[1], allCustomers: allCustomers)
                        ) {
                            FunnelRow(stage: stages[1], displayConfig: displayConfig)
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(!displayConfig.demoEnabled)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - 成交率行（累计/当月）
struct FunnelRateRow: View {
    let label:    String
    let rateText: String
    let fraction: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.bold())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(rateText).font(.title3.bold()).foregroundColor(.blue)
                Text(fraction).font(.caption2).foregroundColor(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }
}

// MARK: - 通用客户列表（下钻用）
struct SimpleCustomerList: View {
    let title:     String
    let subtitle:  String
    let customers: [Customer]

    var body: some View {
        List {
            Section(header: Text("\(subtitle)")) {
                if customers.isEmpty {
                    Text("暂无客户").foregroundColor(.secondary)
                } else {
                    ForEach(customers) { customer in
                        NavigationLink(destination: CustomerDetailView(customer: customer)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 4) {
                                        Text(customer.name).fontWeight(.semibold)
                                        Text("（\(customer.customerNumber.map { "编号 \($0)" } ?? "未录入编号")）")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Text(customer.phone).font(.caption).foregroundColor(.gray)
                                }
                                Spacer()
                                let revenue = customer.validConversions.filter { $0.type == .newOrder }.reduce(0.0) { $0 + $1.amount }
                                if revenue > 0 {
                                    Text("¥\(Int(revenue))").fontWeight(.bold).foregroundColor(.green)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 漏斗阶段客户列表
struct FunnelStageCustomerList: View {

    let stage:        FunnelStage
    let allCustomers: [Customer]

    private var stageCustomers: [Customer] {
        allCustomers.filter { stage.customerIDs.contains($0.id) }
    }

    var body: some View {
        List {
            Section(header: Text("\(stage.label) · \(stage.count) 单 · ¥\(Int(stage.totalAmount))")) {
                if stageCustomers.isEmpty {
                    Text("暂无客户").foregroundColor(.secondary)
                } else {
                    ForEach(stageCustomers) { customer in
                        NavigationLink(destination: CustomerDetailView(customer: customer)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    // 姓名 + 编号（必须展示，无编号显示"未录入编号"）
                                    HStack(spacing: 4) {
                                        Text(customer.name).fontWeight(.semibold)
                                        Text("（\(customer.customerNumber.map { "编号 \($0)" } ?? "未录入编号")）")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Text(customer.phone)
                                        .font(.caption).foregroundColor(.gray)
                                }
                                Spacer()
                                // 该阶段成交金额
                                let amt = customer.validConversions
                                    .filter { stage.conversionRecordIDs.contains($0.id) }
                                    .reduce(0) { $0 + $1.amount }
                                Text("¥\(Int(amt))")
                                    .fontWeight(.bold).foregroundColor(.green)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(stage.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FunnelRow: View {
    let stage: FunnelStage
    var displayConfig: PresentationDisplayConfig = .empty

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayConfig.text("dashboard.stage.\(stage.label).label", fallback: stage.label)).font(.subheadline.bold())
                Text(displayConfig.text("dashboard.stage.\(stage.label).summary", fallback: "\(stage.count) 单 · \(stage.totalAmountText)"))
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(displayConfig.text("dashboard.stage.\(stage.label).rate", fallback: stage.conversionRateText)).font(.title3.bold()).foregroundColor(.blue)
                Text(displayConfig.text("dashboard.stage.\(stage.label).fraction", fallback: "\(stage.count)/\(stage.denominator)"))
                    .font(.caption2).foregroundColor(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }
}

// MARK: - 渠道漏斗分析卡片（v7）
struct ChannelFunnelCard: View {
    let channels: [ChannelStats]
    let allCustomers: [Customer]
    let showRevenue: Bool
    var year:  Int? = nil
    var month: Int? = nil
    @Binding var expanded: Bool
    var displayConfig: PresentationDisplayConfig = .empty
    @State private var selectedStat: ChannelStats? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏（可折叠）
            Button {
                withAnimation(.spring(response: 0.3)) { expanded.toggle() }
            } label: {
                HStack {
                    Text("渠道漏斗分析").font(.headline).foregroundColor(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary).font(.caption)
                }
                .padding()
            }

            if expanded {
                Divider()
                if channels.isEmpty {
                    Text("暂无渠道数据\n（导入时自动识别小红书/直播/朋友圈等关键词）")
                        .font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    // 表头
                    HStack(spacing: 4) {
                        Text("渠道")
                            .font(.caption2.bold()).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !displayConfig.isHidden(PresentationMetric.channelLeads) { Text("线索").font(.caption2.bold()).foregroundColor(.secondary).frame(width: 36, alignment: .trailing) }
                        if !displayConfig.isHidden(PresentationMetric.channelNewRate) { Text("新单率").font(.caption2.bold()).foregroundColor(.secondary).frame(width: 48, alignment: .trailing) }
                        if !displayConfig.isHidden(PresentationMetric.channelRetention) { Text("复购率").font(.caption2.bold()).foregroundColor(.secondary).frame(width: 48, alignment: .trailing) }
                        if showRevenue && !displayConfig.isHidden(PresentationMetric.channelRevenue) {
                            Text("营业额").font(.caption2.bold()).foregroundColor(.secondary)
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 6)
                    .background(Color(.systemGroupedBackground))

                    // 总计行
                    let totalLeads    = channels.reduce(0) { $0 + $1.leadCount }
                    let totalNewOrders = channels.reduce(0) { $0 + $1.newOrderCount }
                    let totalSeconds  = channels.reduce(0) { $0 + $1.secondPurchaseCount }
                    let totalRevenue  = channels.reduce(0.0) { $0 + $1.revenue }
                    let totalNewRate  = totalLeads > 0 ? String(format: "%.0f%%", Double(totalNewOrders)/Double(totalLeads)*100) : "—"
                    let totalSecRate  = totalNewOrders > 0 ? String(format: "%.0f%%", Double(totalSeconds)/Double(totalNewOrders)*100) : "—"
                    let totalRevText  = "¥\(Int(totalRevenue))"

                    Divider()
                    HStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.blue).frame(width: 8, height: 8)
                            Text("全部合计").font(.subheadline.bold()).foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if !displayConfig.isHidden(PresentationMetric.channelLeads) { Text(displayConfig.text("channel.total.leads", fallback: "\(totalLeads)")).font(.subheadline.bold()).frame(width: 36, alignment: .trailing) }
                        if !displayConfig.isHidden(PresentationMetric.channelNewRate) { Text(displayConfig.text("channel.total.newRate", fallback: totalNewRate)).font(.subheadline.bold()).foregroundColor(.blue).frame(width: 48, alignment: .trailing) }
                        if !displayConfig.isHidden(PresentationMetric.channelRetention) { Text(displayConfig.text("channel.total.retention", fallback: totalSecRate)).font(.subheadline.bold()).foregroundColor(.green).frame(width: 48, alignment: .trailing) }
                        if showRevenue && !displayConfig.isHidden(PresentationMetric.channelRevenue) {
                            Text(displayConfig.text("channel.total.revenue", fallback: totalRevText)).font(.subheadline.bold()).foregroundColor(.indigo)
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                    .background(Color(.systemGray6))

                    Divider()
                    ForEach(channels) { stat in
                        Button {
                            selectedStat = stat
                        } label: {
                            ChannelRow(stat: stat, showRevenue: showRevenue, displayConfig: displayConfig)
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(!displayConfig.demoEnabled)
                        if stat.id != channels.last?.id {
                            Divider().padding(.leading)
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .sheet(item: $selectedStat) { stat in
            let cal = Calendar.current
            let customers = allCustomers.filter { c in
                guard c.channelDisplay == stat.channel else { return false }
                if let y = year, let m = month {
                    let comp = cal.dateComponents([.year, .month], from: c.importDate)
                    return comp.year == y && comp.month == m
                }
                return true
            }
            ChannelDetailSheet(stat: stat, customers: customers, showRevenue: showRevenue)
        }
    }
}

// MARK: - 渠道统计行
struct ChannelRow: View {
    let stat: ChannelStats
    let showRevenue: Bool
    var displayConfig: PresentationDisplayConfig = .empty

    private var channelColor: Color {
        switch stat.channel {
        case "问答":      return .cyan
        case "小红书":    return Color(red: 1, green: 0.2, blue: 0.3)
        case "直播间":   return .orange
        case "朋友圈":   return Color(red: 0.07, green: 0.73, blue: 0.33)
        case "食谱渠道": return .teal
        case "抖音":     return Color(red: 0.04, green: 0.04, blue: 0.04)
        case "视频号":   return .blue
        case "转介绍":   return .purple
        case "老客推荐": return .indigo
        case "广告投流": return .yellow
        default:        return .gray
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(channelColor).frame(width: 7, height: 7)
                Text(displayConfig.text(PresentationKey.channel(stat.channel, "name"), fallback: stat.channel)).font(.subheadline).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !displayConfig.isHidden(PresentationMetric.channelLeads) {
                Text(displayConfig.text(PresentationKey.channel(stat.channel, "leads"), fallback: "\(stat.leadCount)"))
                    .font(.subheadline.bold()).frame(width: 36, alignment: .trailing)
            }

            if !displayConfig.isHidden(PresentationMetric.channelNewRate) {
                Text(displayConfig.text(PresentationKey.channel(stat.channel, "newRate"), fallback: stat.newOrderRateText))
                    .font(.subheadline).foregroundColor(.blue).frame(width: 48, alignment: .trailing)
            }

            if !displayConfig.isHidden(PresentationMetric.channelRetention) {
                Text(displayConfig.text(PresentationKey.channel(stat.channel, "retention"), fallback: stat.retentionRateText))
                    .font(.subheadline).foregroundColor(.green).frame(width: 48, alignment: .trailing)
            }

            if showRevenue && !displayConfig.isHidden(PresentationMetric.channelRevenue) {
                Text(displayConfig.text(PresentationKey.channel(stat.channel, "revenue"), fallback: stat.revenueText))
                    .font(.caption.bold()).foregroundColor(.indigo)
                    .frame(width: 56, alignment: .trailing)
            }

            Image(systemName: "chevron.right")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal).padding(.vertical, 9)
    }
}

// MARK: - 渠道明细 Sheet
struct ChannelDetailSheet: View {
    @EnvironmentObject var store: DataStore
    let stat: ChannelStats
    let customers: [Customer]

    let showRevenue: Bool
    var body: some View {
        NavigationView {
            List {
                // 汇总卡（线索数用实际列表数量，与显示保持一致）
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("线索数").font(.caption).foregroundColor(.secondary)
                            Text("\(customers.count)").font(.title2.bold())
                        }
                        Spacer()
                        VStack(alignment: .center, spacing: 2) {
                            Text("新单率").font(.caption).foregroundColor(.secondary)
                            let newOrders = customers.filter { $0.validConversions.contains { $0.type == .newOrder } }.count
                            let rate = customers.isEmpty ? 0.0 : Double(newOrders) / Double(customers.count)
                            Text(customers.isEmpty ? "—" : String(format: "%.0f%%", rate * 100))
                                .font(.title2.bold()).foregroundColor(.blue)
                        }
                        Spacer()
                        if showRevenue {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("总营业额").font(.caption).foregroundColor(.secondary)
                                let rev = customers.flatMap { $0.validConversions }.reduce(0.0) { $0 + $1.amount }
                                Text("¥\(Int(rev))")
                                    .font(.title2.bold()).foregroundColor(.indigo)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 客户明细（可点击进入详情）
                Section(header: Text("客户明细（\(customers.count)人）")) {
                    if customers.isEmpty {
                        Text("暂无数据").foregroundColor(.secondary).font(.caption)
                    } else {
                        ForEach(customers) { customer in
                            NavigationLink(destination:
                                CustomerDetailView(customer: customer)
                                    .environmentObject(store)
                            ) {
                                ChannelCustomerRow(customer: customer, showRevenue: showRevenue)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("\(stat.channel) 渠道明细")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 渠道明细中的客户行
struct ChannelCustomerRow: View {
    let customer: Customer
    let showRevenue: Bool

    private var customerRevenue: Double {
        customer.validConversions.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(customer.name).font(.subheadline.bold())
                        if let num = customer.customerNumber {
                            Text("#\(num)").font(.caption2).foregroundColor(.secondary)
                        }
                        Text(customer.gender).font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    if !customer.phone.hasPrefix("unknown") {
                        Text(customer.phone).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                if showRevenue {
                    VStack(alignment: .trailing, spacing: 2) {
                        if customerRevenue > 0 {
                            Text("¥\(Int(customerRevenue))")
                                .font(.subheadline.bold()).foregroundColor(.indigo)
                        } else {
                            Text("未成交").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }

            // 成交记录
            if !customer.conversions.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(customer.conversions.sorted { $0.date > $1.date }) { record in
                        HStack(spacing: 8) {
                            Text(record.type.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                            if showRevenue {
                                Text("¥\(Int(record.amount))")
                                    .font(.caption2).foregroundColor(.primary)
                            }
                            Spacer()
                            Text(record.date.chineseDate)
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 本月营业额明细列表
struct MonthlyRevenueDetailView: View {

    let customers: [Customer]
    let year:  Int
    let month: Int

    // 展开所有成交记录，按时间倒序
    private struct RevenueEntry: Identifiable {
        let id = UUID()
        let customerName:   String
        let customerNumber: String?
        let record:         ConversionRecord
    }

    private var entries: [RevenueEntry] {
        customers
            .flatMap { c in
                c.validConversions
                    .filter { $0.amount > 0 }
                    .map { RevenueEntry(customerName: c.name, customerNumber: c.customerNumber, record: $0) }
            }
            .sorted { $0.record.date > $1.record.date }
    }

    private var totalRevenue: Double { entries.reduce(0) { $0 + $1.record.amount } }

    var body: some View {
        List {
            Section(header: Text("合计 ¥\(Int(totalRevenue)) · 共 \(entries.count) 笔")) {
                if entries.isEmpty {
                    Text("本月暂无成交记录").foregroundColor(.secondary)
                } else {
                    ForEach(entries) { e in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Text(e.customerName).fontWeight(.semibold)
                                    if let num = e.customerNumber {
                                        Text("编号 \(num)")
                                            .font(.caption2)
                                            .padding(.horizontal, 4).padding(.vertical, 1)
                                            .background(Color.blue.opacity(0.1))
                                            .foregroundColor(.blue).cornerRadius(3)
                                    }
                                }
                                Text(e.record.type.rawValue)
                                    .font(.caption)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.indigo.opacity(0.12))
                                    .foregroundColor(.indigo).cornerRadius(4)
                                Text(e.record.date.chineseDateTime)
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("¥\(Int(e.record.amount))")
                                .fontWeight(.bold).foregroundColor(.green)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("本月营业额明细")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 本月成本明细列表
struct MonthlyCostDetailView: View {

    let customers: [Customer]
    let year:  Int
    let month: Int

    private struct CostEntry: Identifiable {
        let id = UUID()
        let customer: Customer
    }

    private struct CostDayGroup: Identifiable {
        let day: Date
        let entries: [CostEntry]

        var id: Date { day }
        var total: Double { entries.reduce(0) { $0 + $1.customer.lineCost } }
    }

    private var costEntries: [CostEntry] {
        customers
            .filter { $0.dataType == .fullCustomer && $0.costEnabled }
            .sorted { $0.importDate > $1.importDate }
            .map { CostEntry(customer: $0) }
    }

    private var dayGroups: [CostDayGroup] {
        let cal = Calendar.current
        return Dictionary(grouping: costEntries) {
            cal.startOfDay(for: $0.customer.importDate)
        }
        .map { day, entries in
            CostDayGroup(
                day: day,
                entries: entries.sorted { $0.customer.importDate > $1.customer.importDate }
            )
        }
        .sorted { $0.day > $1.day }
    }

    private var totalCost: Double { costEntries.reduce(0) { $0 + $1.customer.lineCost } }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("成本合计").font(.caption).foregroundColor(.secondary)
                        Text("¥\(Int(totalCost))").font(.title2.bold()).foregroundColor(.blue)
                    }
                    Spacer()
                    Text("\(costEntries.count) 份资料")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            if costEntries.isEmpty {
                Section {
                    Text("暂无成本记录").foregroundColor(.secondary)
                }
            } else {
                ForEach(dayGroups) { group in
                    Section(header:
                        HStack {
                            Text(group.day.dashboardSectionDate)
                            Spacer()
                            Text("\(group.entries.count) 份 · ¥\(Int(group.total))")
                        }
                    ) {
                        ForEach(group.entries) { e in
                            NavigationLink(destination: CustomerDetailView(customer: e.customer)) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 4) {
                                            Text(e.customer.name).fontWeight(.semibold)
                                            if let num = e.customer.customerNumber {
                                                Text("编号 \(num)")
                                                    .font(.caption2)
                                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                                    .background(Color.blue.opacity(0.1))
                                                    .foregroundColor(.blue).cornerRadius(3)
                                            }
                                            Text("顾问 \(e.customer.advisorDisplay)")
                                                .font(.caption2)
                                                .lineLimit(1)
                                                .padding(.horizontal, 4).padding(.vertical, 1)
                                                .background(Color.purple.opacity(0.1))
                                                .foregroundColor(.purple).cornerRadius(3)
                                        }
                                        if let addr = e.customer.address {
                                            Text(String(addr.prefix(20)))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        Text(e.customer.importDate.chineseDateTime + " 录入")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("¥\(Int(e.customer.lineCost))")
                                            .fontWeight(.bold).foregroundColor(.blue)
                                        Text("历史单价")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("成本明细")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 双轨业绩明细（[当前总业绩] = [漏斗内] + [非漏斗]）
struct RevenueBreakdownView: View {

    let customers:   [Customer]
    let year:        Int?
    let month:       Int?
    let periodLabel: String

    fileprivate struct RevenueEntry: Identifiable {
        let id = UUID()
        let customer:       Customer
        let isFunnel:       Bool
        let record:         ConversionRecord
    }

    private struct RevenueDayGroup: Identifiable {
        let day: Date
        let entries: [RevenueEntry]

        var id: Date { day }
        var total: Double { entries.reduce(0) { $0 + $1.record.amount } }
    }

    private var entries: [RevenueEntry] {
        let cal = Calendar.current
        return customers
            .flatMap { c in
                c.validConversions
                    .filter { conv in
                        guard conv.amount > 0 else { return false }
                        guard let y = year, let m = month else { return true }
                        let comps = cal.dateComponents([.year, .month], from: conv.date)
                        return comps.year == y && comps.month == m
                    }
                    .map { RevenueEntry(customer: c, isFunnel: c.costEnabled, record: $0) }
            }
            .sorted { $0.record.date > $1.record.date }
    }

    private var funnelEntries:    [RevenueEntry] { entries.filter {  $0.isFunnel } }
    private var nonFunnelEntries: [RevenueEntry] { entries.filter { !$0.isFunnel } }
    private var funnelTotal:    Double { funnelEntries.reduce(0)    { $0 + $1.record.amount } }
    private var nonFunnelTotal: Double { nonFunnelEntries.reduce(0) { $0 + $1.record.amount } }
    private var grandTotal:     Double { funnelTotal + nonFunnelTotal }
    private var dayGroups: [RevenueDayGroup] {
        let cal = Calendar.current
        return Dictionary(grouping: entries) {
            cal.startOfDay(for: $0.record.date)
        }
        .map { day, entries in
            RevenueDayGroup(
                day: day,
                entries: entries.sorted { $0.record.date > $1.record.date }
            )
        }
        .sorted { $0.day > $1.day }
    }

    var body: some View {
        List {
            // 汇总头
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("总业绩").font(.caption).foregroundColor(.secondary)
                        Text("¥\(Int(grandTotal))").font(.title2.bold()).foregroundColor(.primary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                            Text("漏斗 ¥\(Int(funnelTotal))")
                                .font(.subheadline.bold()).foregroundColor(.green)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange).frame(width: 7, height: 7)
                            Text("其他 ¥\(Int(nonFunnelTotal))")
                                .font(.subheadline).foregroundColor(.orange)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // 每日开单明细：订单按实际开单日期分段，轨道归属保留在每一行。
            ForEach(dayGroups) { group in
                Section(header:
                    HStack {
                        Text(group.day.dashboardSectionDate)
                        Spacer()
                        Text("\(group.entries.count) 单 · ¥\(Int(group.total))")
                    }
                ) {
                    ForEach(group.entries) { e in
                        NavigationLink(destination: CustomerDetailView(customer: e.customer)) {
                            RevenueRow(entry: e)
                        }
                    }
                }
            }

            if entries.isEmpty {
                Section { Text("暂无成交记录").foregroundColor(.secondary) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(periodLabel)业绩明细")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RevenueRow: View {
    let entry: RevenueBreakdownView.RevenueEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(entry.customer.name).fontWeight(.semibold)
                    if let num = entry.customer.customerNumber {
                        Text("编号 \(num)")
                            .font(.caption2)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue).cornerRadius(3)
                    }
                }
                Text(entry.record.type.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.indigo.opacity(0.12))
                    .foregroundColor(.indigo).cornerRadius(4)
                Text(entry.isFunnel ? "漏斗计入" : "仅计业绩")
                    .font(.caption2.bold())
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background((entry.isFunnel ? Color.green : Color.orange).opacity(0.12))
                    .foregroundColor(entry.isFunnel ? .green : .orange)
                    .cornerRadius(4)
                Text(entry.record.date.chineseDateTime)
                    .font(.caption2).foregroundColor(.secondary)
                // 顾问归属标签
                if !entry.record.advisorSplits.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill").font(.caption2).foregroundColor(.purple)
                        ForEach(entry.record.advisorSplits, id: \.name) { split in
                            Text("\(split.name) \(split.ratioText)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.purple.opacity(0.12))
                                .foregroundColor(.purple).cornerRadius(4)
                        }
                    }
                } else {
                    Text("未分配顾问")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
            Spacer()
            Text("¥\(Int(entry.record.amount))")
                .fontWeight(.bold).foregroundColor(.green)
        }
        .padding(.vertical, 2)
    }
}

private extension Date {
    /// 看板明细按日分组标题；累计模式下保留年份，避免跨年日期混淆。
    var dashboardSectionDate: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月d日"
        return fmt.string(from: self)
    }
}

// MARK: - 待跟进客户卡片
struct FollowUpCard: View {
    @EnvironmentObject var store: DataStore
    let pendingNewOrder: [Customer]
    let pendingSecond:   [Customer]
    let pending15Days:   [Customer]
    var displayConfig: PresentationDisplayConfig = .empty

    private var stoppedPendingCount: Int {
        let existingIDs = Set(store.customers.map(\.id))
        return store.settings.dismissedPendingSecondCustomerIDs.filter {
            existingIDs.contains($0)
        }.count
    }

    private var voidedOrderCount: Int {
        store.customers.reduce(0) { count, customer in
            count + customer.conversions.filter(\.isVoided).count
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("待跟进客户").font(.headline).padding()
            Divider()

            // 15天内派发未成交（子项，缩进显示）
            NavigationLink(destination: FollowUpCustomerList(
                title: "15天内派发·未成交新单",
                customers: pending15Days,
                allowTagging: false
            )) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.badge.exclamationmark")
                                .foregroundColor(.red).font(.caption)
                            Text("15天内派发·未成交").font(.subheadline.bold()).foregroundColor(.red)
                        }
                        Text("近15天导入、尚未成交的线索").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(displayConfig.text("dashboard.pending15", fallback: "\(pending15Days.count)")) 人")
                        .font(.subheadline.bold()).foregroundColor(.red)
                    Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!displayConfig.demoEnabled)

            Divider().padding(.leading)

            NavigationLink(destination: FollowUpCustomerList(
                title: "暂未成交新单",
                customers: pendingNewOrder,
                allowTagging: false
            )) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("暂未成交新单").font(.subheadline.bold())
                        Text("尚未产生首次成交的客户").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(displayConfig.text("dashboard.pendingNew", fallback: "\(pendingNewOrder.count)")) 人")
                        .font(.subheadline.bold()).foregroundColor(.orange)
                    Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!displayConfig.demoEnabled)

            Divider().padding(.leading)

            NavigationLink(destination: FollowUpCustomerList(
                title: "暂未成交二次",
                customers: pendingSecond,
                allowTagging: true
            )) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("暂未成交二次").font(.subheadline.bold())
                        Text("已有新单、尚未二次成交的客户").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(displayConfig.text("dashboard.pendingSecond", fallback: "\(pendingSecond.count)")) 人")
                        .font(.subheadline.bold()).foregroundColor(.blue)
                    Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!displayConfig.demoEnabled)

            Divider().padding(.leading)

            NavigationLink(destination: FollowUpRecoveryView()) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已停止跟进 / 未签收订单").font(.subheadline.bold())
                        Text("查看并恢复误操作，不删除客户资料")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(stoppedPendingCount + voidedOrderCount) 条")
                        .font(.subheadline.bold()).foregroundColor(.red)
                    Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!displayConfig.demoEnabled)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - 已停止二次跟进 / 未签收订单恢复中心
private struct VoidedOrderItem: Identifiable {
    let customer: Customer
    let record: ConversionRecord
    var id: UUID { record.id }
}

struct FollowUpRecoveryView: View {
    @EnvironmentObject var store: DataStore

    private var stoppedCustomers: [Customer] {
        let dismissed = Set(store.settings.dismissedPendingSecondCustomerIDs)
        return store.customers
            .filter { dismissed.contains($0.id) }
            .sorted { $0.importDate > $1.importDate }
    }

    private var voidedOrders: [VoidedOrderItem] {
        store.customers.flatMap { customer in
            customer.conversions
                .filter(\.isVoided)
                .map { VoidedOrderItem(customer: customer, record: $0) }
        }
        .sorted { $0.record.date > $1.record.date }
    }

    var body: some View {
        List {
            if stoppedCustomers.isEmpty && voidedOrders.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.largeTitle).foregroundColor(.green)
                        Text("暂无需要恢复的记录")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            }

            if !stoppedCustomers.isEmpty {
                Section(header: Text("已停止二次跟进 · \(stoppedCustomers.count) 人"),
                        footer: Text("恢复后，符合“已有新单、尚未二次”条件的客户会重新进入待办。")) {
                    ForEach(stoppedCustomers) { customer in
                        VStack(alignment: .leading, spacing: 8) {
                            NavigationLink(destination: CustomerDetailView(customer: customer)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(customer.name).font(.subheadline.bold())
                                        if let number = customer.customerNumber {
                                            Text("编号 \(number)")
                                                .font(.caption2).foregroundColor(.blue)
                                        }
                                    }
                                    Text("\(customer.advisor ?? "未分配顾问") · \(customer.importDayDisplay)")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Button("恢复到二次跟进") {
                                withAnimation {
                                    store.settings.restorePendingSecondCustomer(customer.id)
                                    store.save()
                                }
                            }
                            .font(.caption.bold())
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            if !voidedOrders.isEmpty {
                Section(header: Text("未签收 / 退款订单 · \(voidedOrders.count) 笔"),
                        footer: Text("恢复后，该笔订单会重新计入成交率、顾问业绩和总营业额。客户及派发数据始终保留。")) {
                    ForEach(voidedOrders) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            NavigationLink(destination: CustomerDetailView(customer: item.customer)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.customer.name).font(.subheadline.bold())
                                        Text("\(item.record.type.rawValue) · \(item.record.date.chineseDate)")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text("¥\(Int(item.record.amount))")
                                        .font(.subheadline.bold()).foregroundColor(.red)
                                        .strikethrough()
                                }
                            }
                            Button("恢复计入统计") {
                                restoreOrder(item)
                            }
                            .font(.caption.bold())
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("恢复中心")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func restoreOrder(_ item: VoidedOrderItem) {
        guard let customerIndex = store.customers.firstIndex(where: { $0.id == item.customer.id }),
              let recordIndex = store.customers[customerIndex].conversions.firstIndex(where: { $0.id == item.record.id })
        else { return }
        var updated = store.customers[customerIndex]
        updated.conversions[recordIndex].isVoided = false
        withAnimation {
            store.updateCustomer(updated)
        }
    }
}

// MARK: - 待跟进客户列表
struct FollowUpCustomerList: View {
    @EnvironmentObject var store: DataStore
    let title:        String
    let customers:    [Customer]
    let allowTagging: Bool

    @State private var tagTarget: Customer? = nil

    // 从 DataStore 实时取最新客户。暂未成交二次列表会在作废或补录二次成交后立即移除该客户。
    private var visibleCustomers: [Customer] {
        let currentByID = Dictionary(uniqueKeysWithValues: store.customers.map { ($0.id, $0) })
        let dismissed = Set(store.settings.dismissedPendingSecondCustomerIDs)
        return customers.compactMap { currentByID[$0.id] }.filter { customer in
            guard allowTagging else { return true }
            return !dismissed.contains(customer.id) &&
                ROIEngine.isQualifiedFunnelLead(customer) &&
                customer.validConversions.contains { $0.type == .newOrder } &&
                !customer.validConversions.contains { $0.type == .second }
        }
    }

    private func tagColor(_ tag: CustomerTag?) -> Color {
        switch tag {
        case .highValue: return Color(red: 1, green: 0.8, blue: 0)
        case .lost:      return .gray
        case .invalid:   return .red
        case nil:        return .clear
        }
    }

    // 暂未成交二次列表显示客户归属人。旧数据若未设置客户顾问，
    // 则从新单成交记录的业绩分成人员中补取，避免显示为空。
    private func ownerDisplay(for customer: Customer) -> String {
        if let advisor = customer.advisor?.trimmingCharacters(in: .whitespacesAndNewlines),
           !advisor.isEmpty {
            return advisor
        }
        var seen = Set<String>()
        let names = customer.validConversions
            .filter { $0.type == .newOrder }
            .flatMap { $0.advisorSplits.map(\.name) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return names.isEmpty ? "未分配顾问" : names.joined(separator: "、")
    }

    // ConversionRecord.amount 是分成前的订单原始金额；advisorSplits 只影响顾问业绩归属。
    private func originalNewOrderAmount(for customer: Customer) -> Double {
        customer.validConversions
            .filter { $0.type == .newOrder }
            .reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        List {
            Section(header: Text("\(title) · \(visibleCustomers.count) 人")) {
                if visibleCustomers.isEmpty {
                    Text("暂无待跟进客户").foregroundColor(.secondary)
                } else {
                    ForEach(visibleCustomers) { customer in
                        HStack(spacing: 0) {
                            if let tag = customer.followUpTag {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(tagColor(tag))
                                    .frame(width: 4)
                                    .padding(.trailing, 8)
                            }
                            NavigationLink(destination: CustomerDetailView(customer: customer)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(customer.name).fontWeight(.semibold)
                                        if let num = customer.customerNumber {
                                            Text("编号 \(num)").font(.caption2)
                                                .padding(.horizontal, 4).padding(.vertical, 1)
                                                .background(Color.blue.opacity(0.1))
                                                .foregroundColor(.blue).cornerRadius(3)
                                        }
                                        if let tag = customer.followUpTag {
                                            Text(tag.rawValue).font(.caption2)
                                                .padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(tagColor(tag).opacity(0.2))
                                                .foregroundColor(tagColor(tag) == .gray ? .gray : tagColor(tag))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    HStack(spacing: 8) {
                                        if allowTagging {
                                            let owner = ownerDisplay(for: customer)
                                            Text(owner)
                                                .font(.caption)
                                                .foregroundColor(owner == "未分配顾问" ? .orange : .blue)
                                            Text(customer.importDayDisplay)
                                                .font(.caption).foregroundColor(.secondary)
                                            Text("新单¥\(Int(originalNewOrderAmount(for: customer)))")
                                                .font(.caption).foregroundColor(.secondary)
                                        } else {
                                            Text(customer.channelDisplay)
                                                .font(.caption).foregroundColor(.blue)
                                            Text(customer.importDayDisplay)
                                                .font(.caption).foregroundColor(.secondary)
                                            if let amt = customer.leadAmount {
                                                Text("线索¥\(Int(amt))")
                                                    .font(.caption).foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            if allowTagging {
                                Button {
                                    tagTarget = customer
                                } label: {
                                    Image(systemName: "tag")
                                        .font(.caption).foregroundColor(.secondary)
                                        .padding(.leading, 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("标注客户", isPresented: Binding(
            get: { tagTarget != nil },
            set: { if !$0 { tagTarget = nil } }
        ), titleVisibility: .visible) {
            Button("高价值客户") { applyTag(.highValue) }
            Button("已失去价值") { applyTag(.lost) }
            Button("停止二次跟进（仅移除此待办）", role: .destructive) {
                dismissPendingSecond()
            }
            if tagTarget?.followUpTag != nil {
                Button("清除标注", role: .cancel) { applyTag(nil) }
            }
            Button("取消", role: .cancel) { tagTarget = nil }
        } message: {
            if let c = tagTarget { Text("为「\(c.name)」选择标注") }
        }
    }

    private func applyTag(_ tag: CustomerTag?) {
        guard let target = tagTarget,
              let idx = store.customers.firstIndex(where: { $0.id == target.id }) else { return }
        var updated = store.customers[idx]
        updated.followUpTag = tag
        tagTarget = nil
        withAnimation {
            store.updateCustomer(updated)
        }
    }

    private func dismissPendingSecond() {
        guard allowTagging, let target = tagTarget else { return }
        tagTarget = nil
        withAnimation {
            store.settings.dismissPendingSecondCustomer(target.id)
            store.save()
        }
    }
}
