import SwiftUI

struct PresentationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var rawConfig: String

    let teams: [AdvisorTeamStats]
    let advisors: [AdvisorStats]
    let channels: [ChannelStats]
    let regionItems: [ProfileItem]
    let ageItems: [ProfileItem]
    let amountItems: [ProfileItem]
    let customers: [Customer]
    let dashboardSummary: PeriodSummary?
    let dashboardYearSummary: PeriodSummary?

    @State private var config: PresentationDisplayConfig

    init(rawConfig: Binding<String>, teams: [AdvisorTeamStats] = [], advisors: [AdvisorStats] = [],
         channels: [ChannelStats] = [], regionItems: [ProfileItem] = [],
         ageItems: [ProfileItem] = [], amountItems: [ProfileItem] = [],
         customers: [Customer] = [], dashboardSummary: PeriodSummary? = nil,
         dashboardYearSummary: PeriodSummary? = nil) {
        _rawConfig = rawConfig
        self.teams = teams
        self.advisors = advisors
        self.channels = channels
        self.regionItems = regionItems
        self.ageItems = ageItems
        self.amountItems = amountItems
        self.customers = customers
        self.dashboardSummary = dashboardSummary
        self.dashboardYearSummary = dashboardYearSummary
        _config = State(initialValue: PresentationDisplayConfig.decode(rawConfig.wrappedValue))
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("模式"), footer: Text("演示数值只影响界面显示，不会写入客户、订单、成本或业绩数据库。关闭后立即恢复真实数据。")) {
                    Toggle("启用演示数据", isOn: binding(\.demoEnabled))
                    if config.demoEnabled {
                        Label("当前页面将显示“演示数据”标识", systemImage: "info.circle.fill")
                            .font(.caption).foregroundColor(.orange)
                    }
                }

                Section(header: Text("顾问页隐藏项目")) {
                    hideToggle("总业绩横幅", PresentationMetric.totalRevenue)
                    hideToggle("15天未成交提醒", PresentationMetric.pendingAlert)
                    hideToggle("业绩未分配提醒", PresentationMetric.unassignedAlert)
                    hideToggle("小组 ROI", PresentationMetric.teamROI)
                    hideToggle("小组业绩", PresentationMetric.teamRevenue)
                    hideToggle("组员派发资料数", PresentationMetric.teamLeads)
                    hideToggle("个人派发资料数", PresentationMetric.advisorLeads)
                    hideToggle("新单成交个数", PresentationMetric.advisorOrders)
                    hideToggle("15天未成交个数", PresentationMetric.advisorPending)
                    hideToggle("个人业绩", PresentationMetric.advisorRevenue)
                    hideToggle("个人/小组 ROI 标签", PresentationMetric.advisorROI)
                    hideToggle("新客户成交率", PresentationMetric.advisorRate)
                    hideToggle("业绩占比", PresentationMetric.advisorShare)
                    hideToggle("业绩饼图", PresentationMetric.revenuePie)
                }

                Section(header: Text("分析页隐藏项目")) {
                    hideToggle("渠道线索数", PresentationMetric.channelLeads)
                    hideToggle("渠道新单率", PresentationMetric.channelNewRate)
                    hideToggle("渠道复购率", PresentationMetric.channelRetention)
                    hideToggle("渠道营业额", PresentationMetric.channelRevenue)
                    hideToggle("地域分布", PresentationMetric.regionSection)
                    hideToggle("年龄段分布", PresentationMetric.ageSection)
                    hideToggle("线索金额分布", PresentationMetric.amountSection)
                    hideToggle("画像人数", PresentationMetric.profileCount)
                    hideToggle("画像百分比", PresentationMetric.profilePercent)
                }

                Section(header: Text("看板与客户页隐藏项目")) {
                    hideToggle("看板 ROI", PresentationMetric.dashboardROI)
                    hideToggle("看板年度 ROI", PresentationMetric.dashboardYearROI)
                    hideToggle("看板成本", PresentationMetric.dashboardCost)
                    hideToggle("看板营业额", PresentationMetric.dashboardRevenue)
                    hideToggle("待跟进客户", PresentationMetric.dashboardFollowUp)
                    hideToggle("销售漏斗", PresentationMetric.dashboardFunnel)
                    hideToggle("客户电话", PresentationMetric.customerPhone)
                    hideToggle("客户地址", PresentationMetric.customerAddress)
                    hideToggle("客户业绩", PresentationMetric.customerRevenue)
                    hideToggle("客户转化次数", PresentationMetric.customerConversions)
                }

                if config.demoEnabled {
                    demoEditor
                }

                Section {
                    Button("恢复全部显示") {
                        config.hiddenMetrics.removeAll(); persist()
                    }
                    Button("清除全部演示数值", role: .destructive) {
                        config.overrides.removeAll(); persist()
                    }
                }
            }
            .navigationTitle("展示与演示设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { persist(); dismiss() }
                }
            }
        }
    }

    @ViewBuilder private var demoEditor: some View {
        Section(header: Text("顾问页演示数值"), footer: Text("留空表示继续显示真实计算结果。")) {
            overrideField("总业绩", key: "top.totalRevenue", placeholder: "¥0")
            overrideField("超15天人数", key: "top.pending", placeholder: "0")
            overrideField("未完成分配笔数", key: "top.unassigned", placeholder: "0")
            ForEach(teams) { team in
                DisclosureGroup(team.groupName) {
                    overrideField("小组名称", key: PresentationKey.team(team.groupName, "name"), placeholder: team.groupName)
                    overrideField("组长", key: PresentationKey.team(team.groupName, "leader"), placeholder: team.leaderDisplay)
                    overrideField("人数", key: PresentationKey.team(team.groupName, "members"), placeholder: "\(team.advisors.count)")
                    overrideField("小组 ROI", key: PresentationKey.team(team.groupName, "roi"), placeholder: team.roiText)
                    overrideField("小组业绩", key: PresentationKey.team(team.groupName, "revenue"), placeholder: team.revenueText)
                    overrideField("组员派发", key: PresentationKey.team(team.groupName, "leads"), placeholder: "\(team.memberLeadCount) 条")
                }
            }
            ForEach(advisors) { stat in
                DisclosureGroup(stat.name) {
                    overrideField("显示姓名", key: PresentationKey.advisor(stat.name, "name"), placeholder: stat.name)
                    overrideField("派发", key: PresentationKey.advisor(stat.name, "leads"), placeholder: "\(stat.totalLeads)")
                    overrideField("新单", key: PresentationKey.advisor(stat.name, "orders"), placeholder: "\(stat.newOrderCount)")
                    overrideField("未成交", key: PresentationKey.advisor(stat.name, "pending"), placeholder: "\(stat.pending15Days)")
                    overrideField("业绩", key: PresentationKey.advisor(stat.name, "revenue"), placeholder: stat.revenueText)
                    overrideField("ROI", key: PresentationKey.advisor(stat.name, "roi"), placeholder: stat.personalROIText)
                    overrideField("新客户成交率", key: PresentationKey.advisor(stat.name, "rate"), placeholder: stat.newOrderRateText)
                    overrideField("业绩占比", key: PresentationKey.advisor(stat.name, "share"), placeholder: "自动计算")
                }
            }
        }

        Section(header: Text("渠道分析演示数值")) {
            DisclosureGroup("全部合计") {
                overrideField("线索", key: "channel.total.leads", placeholder: "自动计算")
                overrideField("新单率", key: "channel.total.newRate", placeholder: "自动计算")
                overrideField("复购率", key: "channel.total.retention", placeholder: "自动计算")
                overrideField("营业额", key: "channel.total.revenue", placeholder: "自动计算")
            }
            ForEach(channels) { stat in
                DisclosureGroup(stat.channel) {
                    overrideField("渠道名称", key: PresentationKey.channel(stat.channel, "name"), placeholder: stat.channel)
                    overrideField("线索", key: PresentationKey.channel(stat.channel, "leads"), placeholder: "\(stat.leadCount)")
                    overrideField("新单率", key: PresentationKey.channel(stat.channel, "newRate"), placeholder: stat.newOrderRateText)
                    overrideField("复购率", key: PresentationKey.channel(stat.channel, "retention"), placeholder: stat.retentionRateText)
                    overrideField("营业额", key: PresentationKey.channel(stat.channel, "revenue"), placeholder: stat.revenueText)
                }
            }
            profileEditors(title: "地域分布（七大区）", items: regionItems)
            profileEditors(title: "年龄段分布", items: ageItems)
            profileEditors(title: "线索金额分布", items: amountItems)
        }

        if let summary = dashboardSummary {
            Section(header: Text("看板演示数值")) {
                overrideField("当前 ROI", key: "dashboard.roi", placeholder: summary.roiText)
                overrideField("年度 ROI", key: "dashboard.yearROI", placeholder: dashboardYearSummary?.roiText ?? "—")
                overrideField("成本", key: "dashboard.cost", placeholder: "¥\(Int(summary.totalCost))")
                overrideField("派发资料数", key: "dashboard.leads", placeholder: "\(summary.importedLeadCount) 条")
                overrideField("营业额", key: "dashboard.revenue", placeholder: "¥\(Int(summary.totalRevenue))")
                overrideField("漏斗业绩", key: "dashboard.funnelRevenue", placeholder: "¥\(Int(summary.funnelRevenue))")
                overrideField("其他业绩", key: "dashboard.otherRevenue", placeholder: "¥\(Int(summary.nonFunnelRevenue))")
                overrideField("累计新单率", key: "dashboard.cumulativeRate", placeholder: summary.cumulativeNewOrderRateText)
                overrideField("累计新单分数", key: "dashboard.cumulativeFraction", placeholder: "\(summary.cumulativeNewOrderCount)/\(summary.cumulativeTotalLeads)")
                overrideField("本月新单率", key: "dashboard.monthlyRate", placeholder: summary.monthlyNewOrderRateText)
                overrideField("本月新单分数", key: "dashboard.monthlyFraction", placeholder: "\(summary.monthlyNewOrderCount)/\(summary.monthlyTotalLeads)")
                overrideField("15天内未成交", key: "dashboard.pending15", placeholder: "自动计算")
                overrideField("暂未成交新单", key: "dashboard.pendingNew", placeholder: "自动计算")
                overrideField("暂未成交二次", key: "dashboard.pendingSecond", placeholder: "自动计算")
                ForEach(summary.funnelStages) { stage in
                    DisclosureGroup(stage.label) {
                        overrideField("名称", key: "dashboard.stage.\(stage.label).label", placeholder: stage.label)
                        overrideField("单数与金额", key: "dashboard.stage.\(stage.label).summary", placeholder: "\(stage.count) 单 · \(stage.totalAmountText)")
                        overrideField("转化率", key: "dashboard.stage.\(stage.label).rate", placeholder: stage.conversionRateText)
                        overrideField("分数", key: "dashboard.stage.\(stage.label).fraction", placeholder: "\(stage.count)/\(stage.denominator)")
                    }
                }
            }
        }

        if !customers.isEmpty {
            Section(header: Text("客户页演示数值"), footer: Text("按客户单独设置；留空继续显示真实资料。")) {
                overrideField("客户总人数", key: "customer.totalCount", placeholder: "\(customers.count)")
                ForEach(customers) { customer in
                    DisclosureGroup(customer.name) {
                        customerEditor(customer)
                    }
                }
            }
        }
    }

    @ViewBuilder private func customerEditor(_ customer: Customer) -> some View {
        overrideField("姓名", key: PresentationKey.customer(customer.id, "name"), placeholder: customer.name)
        overrideField("电话", key: PresentationKey.customer(customer.id, "phone"), placeholder: customer.phone)
        overrideField("编号", key: PresentationKey.customer(customer.id, "number"), placeholder: customer.customerNumber ?? "—")
        overrideField("归属顾问", key: PresentationKey.customer(customer.id, "advisor"), placeholder: customer.advisorDisplay)
        overrideField("地址", key: PresentationKey.customer(customer.id, "address"), placeholder: customer.address ?? "—")
        overrideField("性别", key: PresentationKey.customer(customer.id, "gender"), placeholder: customer.gender)
        overrideField("年龄", key: PresentationKey.customer(customer.id, "age"), placeholder: customer.age.map { "\($0) 岁" } ?? "—")
        overrideField("身高", key: PresentationKey.customer(customer.id, "height"), placeholder: customer.height.map { "\($0) cm" } ?? "—")
        overrideField("体重", key: PresentationKey.customer(customer.id, "weight"), placeholder: customer.weight.map { "\($0) kg" } ?? "—")
        overrideField("渠道", key: PresentationKey.customer(customer.id, "channel"), placeholder: customer.channelDisplay)
        overrideField("线索金额", key: PresentationKey.customer(customer.id, "leadAmount"), placeholder: customer.leadAmount.map { "¥\(Int($0))" } ?? "—")
        overrideField("总营业额", key: PresentationKey.customer(customer.id, "revenue"), placeholder: "¥\(Int(customer.totalRevenue))")
        overrideField("有效转化次数", key: PresentationKey.customer(customer.id, "conversions"), placeholder: "\(customer.validConversions.count) 次")
        overrideField("导入日期", key: PresentationKey.customer(customer.id, "date"), placeholder: customer.importDayDisplay)
        overrideField("成本状态", key: PresentationKey.customer(customer.id, "cost"), placeholder: customer.costEnabled ? "¥\(Int(customer.lineCost)) 计入成本，参与漏斗考核" : "成本归零，业绩仅计入全量营业额")
        ForEach(customer.conversions) { record in
            DisclosureGroup("\(record.type.rawValue) · ¥\(Int(record.amount))") {
                overrideField("类型", key: PresentationKey.conversion(record.id, "type"), placeholder: record.type.rawValue)
                overrideField("金额", key: PresentationKey.conversion(record.id, "amount"), placeholder: "¥\(Int(record.amount))")
                overrideField("产品", key: PresentationKey.conversion(record.id, "product"), placeholder: record.productNote ?? "—")
                overrideField("日期", key: PresentationKey.conversion(record.id, "date"), placeholder: record.date.chineseDateTime)
            }
        }
    }

    private func profileEditors(title: String, items: [ProfileItem]) -> some View {
        DisclosureGroup(title) {
            ForEach(items) { item in
                overrideField("\(item.label) 名称", key: PresentationKey.profile(title, item.label, "label"), placeholder: item.label)
                overrideField("\(item.label) 人数", key: PresentationKey.profile(title, item.label, "count"), placeholder: "\(item.count) 人")
                overrideField("\(item.label) 占比", key: PresentationKey.profile(title, item.label, "percent"), placeholder: item.percentageText)
            }
        }
    }

    private func hideToggle(_ title: String, _ metric: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { config.hiddenMetrics.contains(metric) },
            set: { hidden in
                if hidden { config.hiddenMetrics.insert(metric) }
                else { config.hiddenMetrics.remove(metric) }
                persist()
            }
        ))
    }

    private func overrideField(_ title: String, key: String, placeholder: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: Binding(
                get: { config.overrides[key] ?? "" },
                set: { value in config.overrides[key] = value; persist() }
            ))
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 150)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<PresentationDisplayConfig, Bool>) -> Binding<Bool> {
        Binding(get: { config[keyPath: keyPath] }, set: { config[keyPath: keyPath] = $0; persist() })
    }

    private func persist() { rawConfig = config.encoded() }
}

struct DemoDataBadge: View {
    var body: some View {
        Text("演示数据")
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.orange.opacity(0.15))
            .foregroundColor(.orange)
            .clipShape(Capsule())
            .accessibilityLabel("当前为演示数据，不是原始经营数据")
    }
}
