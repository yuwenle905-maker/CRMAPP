// MARK: - CustomerListView.swift
// 客户列表：三层树状（年→月→日）+ 全局搜索 + 滑动删除

import SwiftUI
import UIKit

// MARK: - 分组数据结构

struct DayGroup: Identifiable {
    let id = UUID()
    let dayKey:     String    // yyyy-MM-dd
    let dayDisplay: String    // M月d日
    var customers:  [Customer]
}

struct MonthGroup: Identifiable {
    let id = UUID()
    let monthKey:    String   // yyyy-MM
    let monthDisplay: String  // X月
    var dayGroups:   [DayGroup]
    var totalCount:  Int { dayGroups.reduce(0) { $0 + $1.customers.count } }
}

struct YearGroup: Identifiable {
    let id = UUID()
    let yearKey:    String    // yyyy
    let yearDisplay: String   // XXXX年
    var monthGroups: [MonthGroup]
    var totalCount:  Int { monthGroups.reduce(0) { $0 + $1.totalCount } }
}

// MARK: - 主列表视图
struct CustomerListView: View {

    @EnvironmentObject var store: DataStore
    @State private var searchText       = ""
    @State private var batchMode        = false
    @State private var selectedIDs      = Set<UUID>()
    @State private var showChannelSheet = false
    @AppStorage("presentationDisplayConfig") private var presentationRaw: String = ""
    @State private var showPresentationSettings = false

    private var presentation: PresentationDisplayConfig { .decode(presentationRaw) }

    private let batchChannelOptions = ["直播", "食谱", "小红书", "问答", "千川", "广点通", "视频号", "朋友圈", "抖音", "自然流量"]

    // 仅完整客户（不含流水记录）
    private var realCustomers: [Customer] {
        store.customers.filter { $0.dataType == .fullCustomer }
    }

    // 搜索结果：全库检索，支持姓名/电话/地址/编号模糊匹配
    private var searchResults: [Customer] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return store.customers.filter {
            $0.name.lowercased().contains(q) ||
            $0.phone.contains(q) ||
            ($0.address ?? "").lowercased().contains(q) ||
            ($0.customerNumber ?? "").lowercased().contains(q)
        }
    }

    // 三层分组
    private var yearGroups: [YearGroup] {
        buildYearGroups(from: realCustomers)
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                Group {
                    if batchMode {
                        batchListView
                    } else if !searchText.isEmpty {
                        SearchResultList(results: searchResults)
                    } else {
                        TreeListView(yearGroups: yearGroups)
                    }
                }

                if batchMode {
                    VStack(spacing: 0) {
                        Divider()
                        HStack {
                            Text(selectedIDs.isEmpty ? "请选择客户" : "已选 \(selectedIDs.count) 人")
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("修改渠道") { showChannelSheet = true }
                                .buttonStyle(.borderedProminent)
                                .disabled(selectedIDs.isEmpty)
                        }
                        .padding(.horizontal).padding(.vertical, 12)
                        .background(Color(.systemBackground))
                    }
                }
            }
            .searchable(text: $searchText, prompt: "姓名、电话、地址、编号（模糊搜索）")
            .navigationTitle(batchMode ? "批量选择" : "客户（\(presentation.text("customer.totalCount", fallback: "\(realCustomers.count)")) 人）")
            .safeAreaInset(edge: .top) {
                if presentation.demoEnabled { DemoDataBadge().padding(.top, 4) }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(batchMode ? "完成" : "批量") {
                        withAnimation { batchMode.toggle() }
                        if !batchMode { selectedIDs.removeAll() }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showPresentationSettings = true } label: {
                        Image(systemName: presentation.hiddenMetrics.isEmpty ? "eye" : "eye.slash")
                    }
                    .accessibilityLabel("展示与演示设置")
                }
            }
        }
        .environment(\.presentationDisplayConfig, presentation)
        .sheet(isPresented: $showPresentationSettings) {
            PresentationSettingsView(rawConfig: $presentationRaw, customers: realCustomers)
        }
        .sheet(isPresented: $showChannelSheet) {
            NavigationView {
                List(batchChannelOptions, id: \.self) { option in
                    Button {
                        applyBatchChannel(option)
                        showChannelSheet = false
                    } label: {
                        Text(option).foregroundColor(.primary)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("批量修改渠道")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showChannelSheet = false }
                    }
                }
            }
        }
    }

    private var batchListView: some View {
        let sorted    = realCustomers.sorted { $0.importDate > $1.importDate }
        let allIDs    = Set(sorted.map { $0.id })
        let allSel    = !sorted.isEmpty && selectedIDs == allIDs
        let partSel   = !selectedIDs.isEmpty && !allSel

        return List {
            // ── 全选行 ────────────────────────────────────────────
            Section {
                Button {
                    selectedIDs = allSel ? [] : allIDs
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: allSel    ? "checkmark.circle.fill" :
                                          partSel   ? "minus.circle.fill"     : "circle")
                            .foregroundColor(allSel || partSel ? .blue : .secondary)
                            .font(.title3)
                        Text(allSel ? "取消全选" : "全选（\(sorted.count) 人）")
                            .fontWeight(.semibold)
                        Spacer()
                        if !selectedIDs.isEmpty {
                            Text("已选 \(selectedIDs.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            // ── 客户列表 ─────────────────────────────────────────
            Section {
                ForEach(sorted) { customer in
                    Button {
                        if selectedIDs.contains(customer.id) {
                            selectedIDs.remove(customer.id)
                        } else {
                            selectedIDs.insert(customer.id)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedIDs.contains(customer.id)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedIDs.contains(customer.id) ? .blue : .secondary)
                                .font(.title3)
                            CustomerRow(customer: customer)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func applyBatchChannel(_ channelValue: String) {
        var list = store.customers
        for id in selectedIDs {
            if let idx = list.firstIndex(where: { $0.id == id }) {
                list[idx].channel = channelValue
            }
        }
        store.customers = list
        store.save()
        selectedIDs.removeAll()
        batchMode = false
    }

    // MARK: 构建三层分组
    private func buildYearGroups(from customers: [Customer]) -> [YearGroup] {
        let cal = DateFormatter()

        // 按年月日逐层分组
        let byYear = Dictionary(grouping: customers) { c -> String in
            cal.dateFormat = "yyyy"
            return cal.string(from: c.importDate)
        }

        return byYear.map { (yearKey, yCusts) in
            let byMonth = Dictionary(grouping: yCusts) { c -> String in
                cal.dateFormat = "yyyy-MM"
                return cal.string(from: c.importDate)
            }
            let monthGroups: [MonthGroup] = byMonth.map { (monthKey, mCusts) in
                let byDay = Dictionary(grouping: mCusts) { c -> String in
                    cal.dateFormat = "yyyy-MM-dd"
                    return cal.string(from: c.importDate)
                }
                let dayGroups: [DayGroup] = byDay.map { (dayKey, dCusts) in
                    cal.dateFormat = "M月d日"
                    let display = cal.string(from: dCusts.first!.importDate)
                    return DayGroup(
                        dayKey:     dayKey,
                        dayDisplay: display,
                        customers:  dCusts.sorted { $0.importDate > $1.importDate }
                    )
                }.sorted { $0.dayKey > $1.dayKey }

                cal.dateFormat = "MM"
                let mNum = cal.string(from: mCusts.first!.importDate)
                return MonthGroup(
                    monthKey:     monthKey,
                    monthDisplay: "\(mNum)月",
                    dayGroups:    dayGroups
                )
            }.sorted { $0.monthKey > $1.monthKey }

            return YearGroup(
                yearKey:     yearKey,
                yearDisplay: "\(yearKey)年",
                monthGroups: monthGroups
            )
        }.sorted { $0.yearKey > $1.yearKey }
    }
}

// MARK: - 三层树状列表
struct TreeListView: View {

    @EnvironmentObject var store: DataStore
    let yearGroups: [YearGroup]

    // 展开状态
    @State private var expandedYears:  Set<String> = []
    @State private var expandedMonths: Set<String> = []

    var body: some View {
        List {
            if yearGroups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.3").font(.system(size: 44)).foregroundColor(.secondary)
                    Text("暂无客户数据").foregroundColor(.secondary)
                    Text("在「智能导入」标签粘贴数据开始").font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity).padding(48)
                .listRowBackground(Color.clear)
            } else {
                ForEach(yearGroups) { year in
                    yearSection(year)
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            // 默认展开最近一年和最近一月
            if let firstYear = yearGroups.first {
                expandedYears.insert(firstYear.yearKey)
                if let firstMonth = firstYear.monthGroups.first {
                    expandedMonths.insert(firstMonth.monthKey)
                }
            }
        }
    }

    // MARK: 年级 Section
    @ViewBuilder
    private func yearSection(_ year: YearGroup) -> some View {
        Section {
            // 年份折叠行
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedYears.contains(year.yearKey) {
                        expandedYears.remove(year.yearKey)
                    } else {
                        expandedYears.insert(year.yearKey)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: expandedYears.contains(year.yearKey)
                          ? "chevron.down.circle.fill" : "chevron.right.circle")
                        .foregroundColor(.blue)
                    Text(year.yearDisplay)
                        .font(.headline).foregroundColor(.primary)
                    Spacer()
                    Text("共 \(year.totalCount) 人")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            // 展开后显示月份
            if expandedYears.contains(year.yearKey) {
                ForEach(year.monthGroups) { month in
                    monthRows(month)
                }
            }
        }
    }

    // MARK: 月份行 + 日期行
    @ViewBuilder
    private func monthRows(_ month: MonthGroup) -> some View {
        // 月份折叠行
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expandedMonths.contains(month.monthKey) {
                    expandedMonths.remove(month.monthKey)
                } else {
                    expandedMonths.insert(month.monthKey)
                }
            }
        } label: {
            HStack {
                Image(systemName: expandedMonths.contains(month.monthKey)
                      ? "folder.fill" : "folder")
                    .foregroundColor(.orange)
                Text(month.monthDisplay)
                    .font(.subheadline.bold()).foregroundColor(.primary)
                Spacer()
                Text("\(month.totalCount) 人")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.leading, 16)
        }
        .buttonStyle(.plain)

        // 展开后显示每日数据卡片
        if expandedMonths.contains(month.monthKey) {
            ForEach(month.dayGroups) { day in
                dayCard(day)
            }
        }
    }

    // MARK: 每日数据卡片（需求4核心）
    @ViewBuilder
    private func dayCard(_ day: DayGroup) -> some View {
        NavigationLink(destination: DayCustomerList(day: day)) {
            VStack(alignment: .leading, spacing: 4) {
                // 卡片头部：导入日期 | 该批次数据条数
                HStack {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundColor(.green).font(.caption)
                    Text("\(day.dayDisplay)  |  \(day.customers.count) 条数据")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }

                // 预览前两条客户名
                let preview = day.customers.prefix(2).map { $0.name }.joined(separator: "、")
                let suffix   = day.customers.count > 2 ? " 等…" : ""
                Text(preview + suffix)
                    .font(.caption).foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
            .padding(.leading, 32)
        }
    }
}

// MARK: - 某日客户二级页面
struct DayCustomerList: View {

    @EnvironmentObject var store: DataStore
    let day: DayGroup

    var body: some View {
        List {
            Section(header:
                Text("\(day.dayDisplay)  |  共 \(day.customers.count) 条数据")
                    .font(.subheadline.bold())
            ) {
                ForEach(day.customers) { customer in
                    NavigationLink(destination: CustomerDetailView(customer: customer)) {
                        CustomerRow(customer: customer)
                    }
                }
                .onDelete { indexSet in
                    let toDelete = indexSet.map { day.customers[$0] }
                    store.customers.removeAll { c in toDelete.contains(where: { $0.id == c.id }) }
                    store.save()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(day.dayDisplay)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 搜索结果平铺（全库，跨日期）
struct SearchResultList: View {

    @EnvironmentObject var store: DataStore
    let results: [Customer]

    var body: some View {
        List {
            if results.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 44)).foregroundColor(.secondary)
                    Text("无匹配结果").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity).padding(48)
                .listRowBackground(Color.clear)
            } else {
                Section(header: Text("找到 \(results.count) 条结果")) {
                    ForEach(results) { customer in
                        NavigationLink(destination: CustomerDetailView(customer: customer)) {
                            CustomerRow(customer: customer)
                        }
                    }
                    .onDelete { indexSet in
                        let toDelete = indexSet.map { results[$0] }
                        store.customers.removeAll { c in toDelete.contains(where: { $0.id == c.id }) }
                        store.save()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - 客户行组件
struct CustomerRow: View {
    let customer: Customer
    @Environment(\.presentationDisplayConfig) private var displayConfig

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(customer.dataType == .fullCustomer ? Color.blue : Color.orange)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(displayConfig.text(PresentationKey.customer(customer.id, "name"), fallback: customer.name).prefix(1)))
                        .font(.subheadline.bold()).foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(displayConfig.text(PresentationKey.customer(customer.id, "name"), fallback: customer.name)).fontWeight(.semibold)
                    // 编号强制展示，无编号显示"未录入编号"
                    Text("（编号 \(displayConfig.text(PresentationKey.customer(customer.id, "number"), fallback: customer.customerNumber ?? "未录入"))）")
                        .font(.caption2).foregroundColor(.secondary)
                    if customer.dataType == .ledgerEntry {
                        Text("流水").font(.caption2)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange).cornerRadius(3)
                    }
                    if customer.gender != "未知" {
                        Text(customer.gender).font(.caption2)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(customer.gender == "女" ? Color.pink.opacity(0.15) : Color.blue.opacity(0.15))
                            .foregroundColor(customer.gender == "女" ? .pink : .blue)
                            .cornerRadius(3)
                    }
                }
                // 手机号 + 地址前15字，帮助区分同名客户
                HStack(spacing: 6) {
                    if !displayConfig.isHidden(PresentationMetric.customerPhone) {
                        Text(displayConfig.text(PresentationKey.customer(customer.id, "phone"), fallback: customer.phone))
                            .font(.caption).foregroundColor(.gray)
                    }
                    if !displayConfig.isHidden(PresentationMetric.customerAddress), let addr = customer.address, !addr.isEmpty {
                        Text("·").font(.caption).foregroundColor(.gray)
                        Text(String(displayConfig.text(PresentationKey.customer(customer.id, "address"), fallback: addr).prefix(15)))
                            .font(.caption).foregroundColor(.gray).lineLimit(1)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if !customer.validConversions.isEmpty {
                    if !displayConfig.isHidden(PresentationMetric.customerRevenue) {
                        Text(displayConfig.text(PresentationKey.customer(customer.id, "revenue"), fallback: "¥\(Int(customer.totalRevenue))"))
                            .font(.subheadline.bold()).foregroundColor(.green)
                    }
                    if !displayConfig.isHidden(PresentationMetric.customerConversions) {
                        Text(displayConfig.text(PresentationKey.customer(customer.id, "conversions"), fallback: "\(customer.validConversions.count) 次有效转化"))
                            .font(.caption2).foregroundColor(.secondary)
                    }
                } else {
                    Text("未转化").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 客户详情页
struct CustomerDetailView: View {

    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss
    let customer: Customer

    @State private var showEditSheet = false
    @State private var advisorEditRecord: ConversionRecord? = nil
    @State private var statusEditRecord: ConversionRecord? = nil
    @AppStorage("presentationDisplayConfig") private var presentationRaw: String = ""
    @State private var showPresentationSettings = false
    @State private var showCopyConfirmation = false

    private var presentation: PresentationDisplayConfig { .decode(presentationRaw) }
    private func demo(_ field: String, _ fallback: String) -> String {
        presentation.text(PresentationKey.customer(current.id, field), fallback: fallback)
    }

    // 始终从 store 实时读取最新数据，确保 Toggle 等操作立刻反映
    private var current: Customer {
        store.customers.first { $0.id == customer.id } ?? customer
    }

    var body: some View {
        List {
            if presentation.demoEnabled { DemoDataBadge() }
            Section(header: Text("基础资料")) {
                InfoRow(label: "姓名", value: demo("name", current.name))
                if !presentation.isHidden(PresentationMetric.customerPhone) { InfoRow(label: "电话", value: demo("phone", current.phone)) }
                InfoRow(label: "编号", value: "编号 \(demo("number", current.customerNumber ?? "未录入"))")
                InfoRow(label: "归属顾问", value: demo("advisor", current.advisorDisplay))
                if !presentation.isHidden(PresentationMetric.customerAddress) { InfoRow(label: "地址", value: demo("address", current.address ?? "—")) }
                InfoRow(label: "性别", value: demo("gender", current.gender))
                InfoRow(label: "年龄", value: demo("age", current.age.map { "\($0) 岁" } ?? "—"))
                InfoRow(label: "身高", value: demo("height", current.height.map { "\($0) cm" } ?? "—"))
                InfoRow(label: "体重", value: demo("weight", current.weight.map { "\($0) kg" } ?? "—"))
                if presentation.demoEnabled {
                    InfoRow(label: "渠道", value: demo("channel", current.channelDisplay))
                } else { HStack {
                    Text("渠道").foregroundColor(.secondary)
                    Spacer()
                    Picker("渠道", selection: Binding(
                        get: { current.channelDisplay },
                        set: { newVal in
                            var updated = current
                            updated.channel = newVal
                            store.updateCustomer(updated)
                        }
                    )) {
                        ForEach(["直播", "食谱", "小红书", "问答", "千川", "广点通", "视频号", "朋友圈", "抖音", "自然流量"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                } }
            }

            Section {
                Button {
                    UIPasteboard.general.string = customerCopyText
                    showCopyConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Label("一键复制全部客户资料", systemImage: "doc.on.doc")
                            .font(.body.weight(.semibold))
                        Spacer()
                    }
                }
                .disabled(presentation.demoEnabled)
            } footer: {
                Text(presentation.demoEnabled
                     ? "演示模式下暂停复制真实资料。"
                     : "复制内容会按基础资料、归属信息和成交记录自动分段。")
            }

            Section(header: Text("消费时间轴")) {
                if current.conversions.isEmpty {
                    Text("暂无消费记录").foregroundColor(.secondary)
                } else {
                    ForEach(current.conversions.sorted { $0.date > $1.date }) { record in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 5) {
                                    Text(presentation.text(PresentationKey.conversion(record.id, "type"), fallback: record.type.rawValue))
                                        .fontWeight(.semibold)
                                        .strikethrough(record.isVoided)
                                    if record.isVoided {
                                        Text("未签收/退款 · 不计统计")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.red.opacity(0.12))
                                            .foregroundColor(.red)
                                            .clipShape(Capsule())
                                    }
                                }
                                if let p = record.productNote {
                                    Text(presentation.text(PresentationKey.conversion(record.id, "product"), fallback: p)).font(.caption).foregroundColor(.secondary)
                                }
                                Text(presentation.text(PresentationKey.conversion(record.id, "date"), fallback: record.date.chineseDateTime))
                                    .font(.caption2).foregroundColor(.secondary)
                                // 顾问归属标签
                                if !record.advisorSplits.isEmpty {
                                    HStack(spacing: 4) {
                                        ForEach(record.advisorSplits, id: \.name) { split in
                                            Text("\(split.name) \(split.ratioText)")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.12))
                                                .foregroundColor(.blue)
                                                .cornerRadius(4)
                                        }
                                    }
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(presentation.text(PresentationKey.conversion(record.id, "amount"), fallback: "¥\(Int(record.amount))"))
                                    .fontWeight(.bold)
                                    .foregroundColor(record.isVoided ? .secondary : .green)
                                    .strikethrough(record.isVoided)
                                Button {
                                    advisorEditRecord = record
                                } label: {
                                    Text("编辑订单")
                                        .font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color(.systemFill))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                .disabled(presentation.demoEnabled)
                                Button {
                                    statusEditRecord = record
                                } label: {
                                    Text(record.isVoided ? "恢复统计" : "未签收作废")
                                        .font(.caption2)
                                        .foregroundColor(record.isVoided ? .blue : .red)
                                }
                                .buttonStyle(.plain)
                                .disabled(presentation.demoEnabled)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section(header: Text("汇总")) {
                // 漏斗状态标签
                HStack {
                    Text("漏斗状态").foregroundColor(.secondary)
                    Spacer()
                    if current.costEnabled {
                        Label("漏斗考核中", systemImage: "scope")
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(6)
                    } else {
                        Label("仅计入业绩", systemImage: "chart.bar")
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(6)
                    }
                }

                if let lead = current.leadAmount {
                    InfoRow(label: "线索金额", value: demo("leadAmount", "¥\(Int(lead))（仅记录，不计营业额）"))
                }
                if !presentation.isHidden(PresentationMetric.customerRevenue) { InfoRow(label: "总营业额", value: demo("revenue", "¥\(Int(current.totalRevenue))")) }
                if !presentation.isHidden(PresentationMetric.customerConversions) { InfoRow(label: "有效转化次数", value: demo("conversions", "\(current.validConversions.count) 次")) }
                InfoRow(label: "导入日期", value: demo("date", current.importDayDisplay))
                // 成本开关（同时控制漏斗归属）
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("纳入成本 & 漏斗")
                        Text(demo("cost", current.costEnabled
                                  ? "¥\(Int(current.lineCost)) 计入成本，参与漏斗考核"
                                  : "成本归零，业绩仅计入全量营业额"))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { current.costEnabled },
                        set: { newVal in
                            var updated = current
                            updated.costEnabled = newVal
                            store.updateCustomer(updated)  // 触发 @Published 刷新全局
                        }
                    ))
                    .labelsHidden()
                    .disabled(presentation.demoEnabled)
                }
            }

            Section {
                Button(role: .destructive) {
                    store.customers.removeAll { $0.id == current.id }
                    store.save()
                    dismiss()
                } label: {
                    HStack {
                        Spacer()
                        Label("删除此客户", systemImage: "trash")
                        Spacer()
                    }
                }
                .disabled(presentation.demoEnabled)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(demo("name", current.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("编辑") { showEditSheet = true }.disabled(presentation.demoEnabled)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showPresentationSettings = true } label: {
                    Image(systemName: presentation.hiddenMetrics.isEmpty ? "eye" : "eye.slash")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            CustomerEditSheet(customer: current)
                .environmentObject(store)
        }
        .sheet(isPresented: $showPresentationSettings) {
            PresentationSettingsView(rawConfig: $presentationRaw, customers: [current])
        }
        .sheet(item: $advisorEditRecord) { rec in
            ConversionAdvisorSheet(customerID: current.id, recordID: rec.id)
                .environmentObject(store)
        }
        .confirmationDialog(
            statusEditRecord?.isVoided == true ? "恢复这笔成交统计？" : "确认这笔订单未签收或已退款？",
            isPresented: Binding(
                get: { statusEditRecord != nil },
                set: { if !$0 { statusEditRecord = nil } }
            ),
            titleVisibility: .visible
        ) {
            if statusEditRecord?.isVoided == true {
                Button("恢复计入成交率和业绩") { setRecordVoided(false) }
            } else {
                Button("作废订单（客户资料保留）", role: .destructive) { setRecordVoided(true) }
            }
            Button("取消", role: .cancel) { statusEditRecord = nil }
        } message: {
            Text("这里只改变成交记录的统计状态，不会删除客户资料，也不会减少派发人数。")
        }
        .alert("复制成功", isPresented: $showCopyConfirmation) {
            Button("好", role: .cancel) { }
        } message: {
            Text("该客户的完整资料已复制到剪贴板。")
        }
    }

    private func setRecordVoided(_ isVoided: Bool) {
        guard let target = statusEditRecord,
              let index = current.conversions.firstIndex(where: { $0.id == target.id }) else { return }
        var updated = current
        updated.conversions[index].isVoided = isVoided
        statusEditRecord = nil
        store.updateCustomer(updated)
    }

    private var customerCopyText: String {
        let address = current.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var lines: [String] = [
            "【客户基础资料】",
            "姓名：\(current.name)",
            "编号：\(current.customerNumber ?? "未录入")",
            "电话：\(current.phone)",
            "地址：\(address.isEmpty ? "未录入" : address)",
            "性别：\(current.gender)",
            "年龄：\(current.age.map { String($0) } ?? "未录入")",
            "身高：\(current.height.map { Self.numberText($0) + " cm" } ?? "未录入")",
            "体重：\(current.weight.map { Self.numberText($0) + " kg" } ?? "未录入")",
            "渠道：\(current.channelDisplay)",
            "线索金额：\(current.leadAmount.map { "¥" + Self.numberText($0) } ?? "未录入")",
            "",
            "【归属与录入】",
            "跟进顾问：\(current.advisorDisplay)",
            "ROI成本归属：\(current.roiAdvisorName ?? "未分配")",
            "录入日期：\(current.importDate.chineseDateTime)",
            "漏斗状态：\(current.costEnabled ? "漏斗考核中" : "仅计入业绩")"
        ]

        if !current.tags.isEmpty {
            lines.append("客户标签：\(current.tags.joined(separator: "、"))")
        }
        if let followUpTag = current.followUpTag {
            lines.append("跟进标记：\(followUpTag.rawValue)")
        }

        lines.append("")
        lines.append("【成交记录】")

        let records = current.conversions.sorted { $0.date < $1.date }
        if records.isEmpty {
            lines.append("暂无成交记录")
        } else {
            for (index, record) in records.enumerated() {
                lines.append("")
                lines.append("\(index + 1). \(record.type.rawValue)\(record.isVoided ? "（未签收/退款，已作废）" : "")")
                lines.append("日期：\(record.date.chineseDateTime)")
                lines.append("金额：¥\(Self.numberText(record.amount))")
                let splits = record.advisorSplits.isEmpty
                    ? "未分配"
                    : record.advisorSplits.map { "\($0.name) \($0.ratioText)" }.joined(separator: " + ")
                lines.append("顾问分配：\(splits)")
                if let product = record.productNote, !product.isEmpty {
                    lines.append("产品：\(product)")
                }
                if let note = record.note, !note.isEmpty {
                    lines.append("备注：\(note)")
                }
            }
        }

        lines.append("")
        lines.append("【汇总】")
        lines.append("有效成交：\(current.validConversions.count) 笔")
        lines.append("总营业额：¥\(Self.numberText(current.totalRevenue))")
        return lines.joined(separator: "\n")
    }

    private static func numberText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }
}

// MARK: - 单笔订单补录与编辑 Sheet
struct ConversionAdvisorSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: DataStore

    let customerID: UUID
    let recordID:   UUID

    @State private var mode:     Int    = 0
    @State private var advisor1: String = ""
    @State private var advisor2: String = ""
    @State private var conversionType: ConversionType = .newOrder
    @State private var amountText: String = ""
    @State private var orderDate: Date = Date()
    @State private var validationMessage = ""
    @State private var showValidationAlert = false

    private let conversionOptions: [ConversionType] = [
        .newOrder, .second, .third, .fourth, .fifth,
        .sixth, .seventh, .eighth, .multiple
    ]

    private var customerIdx: Int? { store.customers.firstIndex { $0.id == customerID } }
    private var recordIdx: Int? {
        guard let ci = customerIdx else { return nil }
        return store.customers[ci].conversions.firstIndex { $0.id == recordID }
    }
    private var record: ConversionRecord? {
        guard let ci = customerIdx, let ri = recordIdx else { return nil }
        return store.customers[ci].conversions[ri]
    }

    var body: some View {
        NavigationView {
            List {
                if record != nil {
                    Section(header: Text("订单信息")) {
                        Picker("成交类型", selection: $conversionType) {
                            ForEach(conversionOptions, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        HStack {
                            Text("订单金额")
                            Spacer()
                            TextField("0", text: $amountText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("元").foregroundColor(.secondary)
                        }
                        DatePicker("开单日期", selection: $orderDate, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                    }
                }

                Section(header: Text("业绩归属"), footer: Text("可以暂存为未分配，之后再次进入本订单补录。")) {
                    AdvisorSplitPicker(mode: $mode, advisor1: $advisor1, advisor2: $advisor2)
                        .environmentObject(store)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("编辑单笔订单")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadCurrent() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if save() { dismiss() }
                    }
                    .font(.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) { dismiss() }
                }
            }
        }
        .alert("无法保存", isPresented: $showValidationAlert) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(validationMessage)
        }
    }

    private func loadCurrent() {
        guard let ci = customerIdx, let ri = recordIdx else { return }
        let currentRecord = store.customers[ci].conversions[ri]
        conversionType = currentRecord.type
        amountText = Self.amountString(currentRecord.amount)
        orderDate = currentRecord.date
        let splits = currentRecord.advisorSplits
        if splits.isEmpty {
            mode = 0
            advisor1 = ""
            advisor2 = ""
        } else if splits.count == 1 {
            mode = 1; advisor1 = splits[0].name
        } else {
            mode = 2; advisor1 = splits[0].name; advisor2 = splits[1].name
        }
    }

    private func save() -> Bool {
        guard let ci = customerIdx, let ri = recordIdx else { return false }
        let normalizedAmount = amountText
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
        guard let amount = Double(normalizedAmount), amount >= 0 else {
            validationMessage = "请输入正确的订单金额。"
            showValidationAlert = true
            return false
        }
        var newSplits: [AdvisorSplit] = []
        switch mode {
        case 1 where !advisor1.isEmpty:
            newSplits = [AdvisorSplit(name: advisor1, ratio: 1.0)]
        case 2 where !advisor1.isEmpty && !advisor2.isEmpty && advisor1 != advisor2:
            newSplits = [AdvisorSplit(name: advisor1, ratio: 0.5),
                         AdvisorSplit(name: advisor2, ratio: 0.5)]
        default:
            newSplits = []
        }
        store.customers[ci].conversions[ri].type = conversionType
        store.customers[ci].conversions[ri].amount = amount
        store.customers[ci].conversions[ri].date = orderDate
        store.customers[ci].conversions[ri].advisorSplits = newSplits
        store.save()
        return true
    }

    private static func amountString(_ amount: Double) -> String {
        amount.rounded() == amount ? String(Int(amount)) : String(amount)
    }
}

// MARK: - 客户编辑 Sheet
struct CustomerEditSheet: View {

    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss

    let customer: Customer

    @State private var name:           String
    @State private var phone:          String
    @State private var address:        String
    @State private var ageStr:         String
    @State private var heightStr:      String
    @State private var weightStr:      String
    @State private var gender:         String
    @State private var customerNumber: String
    @State private var leadAmountStr:  String
    @State private var note:           String
    @State private var costEnabled:    Bool
    @State private var lineCostStr:    String
    @State private var conversions:    [ConversionRecord]

    // 行内编辑成交记录 — 用独立 State 持有编辑中的快照，避免绑定引发重建
    @State private var importDate:      Date
    @State private var editingIndex:   Int?    = nil
    @State private var editAmountStr:  String  = ""
    @State private var editDate:       Date    = Date()
    @State private var editIsVoided:   Bool    = false
    @State private var showEditRecord  = false

    private let genderOptions   = ["未知", "女", "男"]
    private let channelOptions  = ["直播", "食谱", "小红书", "问答", "千川", "广点通", "视频号", "朋友圈", "抖音", "自然流量"]

    @State private var channel:  String
    @State private var advisor:  String

    private var validEditedConversions: [ConversionRecord] {
        conversions.filter(\.countsInStatistics)
    }

    init(customer: Customer) {
        self.customer = customer
        _name           = State(initialValue: customer.name)
        _phone          = State(initialValue: customer.phone)
        _address        = State(initialValue: customer.address ?? "")
        _ageStr         = State(initialValue: customer.age.map    { String($0) } ?? "")
        _heightStr      = State(initialValue: customer.height.map { String(Int($0)) } ?? "")
        _weightStr      = State(initialValue: customer.weight.map { String(Int($0)) } ?? "")
        _gender         = State(initialValue: customer.gender)
        _channel        = State(initialValue: customer.channel ?? "自然流量")
        _advisor        = State(initialValue: customer.advisor ?? "")
        _customerNumber = State(initialValue: customer.customerNumber ?? "")
        _leadAmountStr   = State(initialValue: customer.leadAmount.map { String(format: "%g", $0) } ?? "")
        _note           = State(initialValue: "")
        _costEnabled    = State(initialValue: customer.costEnabled)
        _lineCostStr    = State(initialValue: String(Int(customer.lineCost)))
        _conversions    = State(initialValue: customer.conversions.sorted { $0.date > $1.date })
        _importDate     = State(initialValue: customer.importDate)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基础资料")) {
                    HStack {
                        Text("姓名").frame(width: 44, alignment: .leading).foregroundColor(.secondary)
                        TextField("姓名", text: $name)
                    }
                    HStack {
                        Text("电话").frame(width: 44, alignment: .leading).foregroundColor(.secondary)
                        TextField("手机号", text: $phone).keyboardType(.phonePad)
                    }
                    HStack {
                        Text("地址").frame(width: 44, alignment: .leading).foregroundColor(.secondary)
                        TextField("收货地址", text: $address)
                    }
                    HStack {
                        Text("编号").frame(width: 44, alignment: .leading).foregroundColor(.secondary)
                        TextField("客户编号（如 8888）", text: $customerNumber)
                    }
                    HStack {
                        Text("金额").frame(width: 44, alignment: .leading).foregroundColor(.secondary)
                        TextField("线索金额（可留空）", text: $leadAmountStr)
                            .keyboardType(.decimalPad)
                        Text("元").foregroundColor(.secondary)
                    }
                    Text("线索金额仅用于客户资料和金额画像，不计入营业额。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Picker("渠道", selection: $channel) {
                        ForEach(channelOptions, id: \.self) { Text($0) }
                    }
                    if !store.settings.advisors.isEmpty {
                        Picker("服务顾问", selection: $advisor) {
                            Text("未分配").tag("")
                            ForEach(store.settings.advisors, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }

                Section(header: Text("体征数据")) {
                    HStack {
                        Text("身高").frame(width: 44, alignment: .leading).foregroundColor(.secondary)
                        TextField("cm", text: $heightStr).keyboardType(.numberPad)
                    }
                    HStack {
                        Text("体重").frame(width: 44, alignment: .leading).foregroundColor(.secondary)
                        TextField("kg", text: $weightStr).keyboardType(.numberPad)
                    }
                    HStack {
                        Text("年龄").frame(width: 44, alignment: .leading).foregroundColor(.secondary)
                        TextField("岁", text: $ageStr).keyboardType(.numberPad)
                    }
                    Picker("性别", selection: $gender) {
                        ForEach(genderOptions, id: \.self) { Text($0) }
                    }
                }

                Section(header: Text("录入日期")) {
                    DatePicker("录入日期", selection: $importDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                }

                Section(header: Text("备注")) {
                    TextEditor(text: $note)
                        .frame(minHeight: 60)
                }

                Section(header: Text("成本设置")) {
                    Toggle(isOn: $costEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("纳入成本计算")
                            Text(costEnabled ? "成本 ¥\(lineCostStr) 将计入看板" : "成本归零，全额算作利润")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    if costEnabled {
                        HStack {
                            Text("单价").frame(width: 44, alignment: .leading).foregroundColor(.secondary)
                            TextField("线索单价（元）", text: $lineCostStr)
                                .keyboardType(.numberPad)
                            Text("元").foregroundColor(.secondary)
                        }
                    }
                }

                // 成交历史明细
                Section(header: HStack {
                    Text("成交历史明细")
                    Spacer()
                    Text("有效 \(validEditedConversions.count) 笔 · ¥\(Int(validEditedConversions.reduce(0) { $0 + $1.amount }))")
                        .font(.caption).foregroundColor(.secondary)
                }) {
                    if conversions.isEmpty {
                        Text("暂无成交记录").foregroundColor(.secondary).font(.caption)
                    } else {
                        ForEach(conversions.indices, id: \.self) { idx in
                            let record = conversions[idx]
                            Button {
                                // 存索引快照，不存 record 引用，避免数组重建后引用失效
                                editingIndex  = idx
                                editAmountStr = String(Int(record.amount))
                                editDate      = record.date
                                editIsVoided  = record.isVoided
                                showEditRecord = true
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 5) {
                                            Text(record.type.rawValue)
                                            .font(.subheadline).fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                            if record.isVoided {
                                                Text("不计统计")
                                                    .font(.caption2.bold()).foregroundColor(.red)
                                            }
                                        }
                                        Text(record.date.chineseDateTime)
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text("¥\(Int(record.amount))")
                                        .fontWeight(.bold)
                                        .foregroundColor(record.isVoided ? .secondary : .green)
                                        .strikethrough(record.isVoided)
                                    Image(systemName: "pencil.circle")
                                        .foregroundColor(.blue).font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            conversions.remove(atOffsets: indexSet)
                        }
                    }
                }
            }
            .navigationTitle("编辑客户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Text("保存").font(.headline)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) { dismiss() }
                }
            }
        }
        // sheet 必须挂在 NavigationView 外部，避免在 toolbar 内触发重建死锁
        .sheet(isPresented: $showEditRecord) {
            RecordEditSheet(
                typeName:  editingIndex.map { conversions[$0].type.rawValue } ?? "",
                amountStr: $editAmountStr,
                date:      $editDate,
                isVoided:  $editIsVoided,
                onSave: {
                    // 先关闭 sheet，再修改数组，避免 ForEach identity 崩溃
                    showEditRecord = false
                    DispatchQueue.main.async {
                        guard let idx = editingIndex, idx < conversions.count else { return }
                        conversions[idx].amount = Double(editAmountStr) ?? conversions[idx].amount
                        conversions[idx].date   = editDate
                        conversions[idx].isVoided = editIsVoided
                        editingIndex = nil
                    }
                },
                onCancel: {
                    showEditRecord = false
                    editingIndex   = nil
                }
            )
        }
    }

    private func save() {
        var updated             = customer
        updated.name            = name.trimmingCharacters(in: .whitespaces)
        updated.phone           = phone.trimmingCharacters(in: .whitespaces)
        updated.address         = address.trimmingCharacters(in: .whitespaces).isEmpty
                                  ? nil : address.trimmingCharacters(in: .whitespaces)
        updated.age             = Int(ageStr.trimmingCharacters(in: .whitespaces))
        updated.height          = Double(heightStr.trimmingCharacters(in: .whitespaces))
        updated.weight          = Double(weightStr.trimmingCharacters(in: .whitespaces))
        updated.gender          = gender
        updated.channel         = channel
        updated.customerNumber  = customerNumber.trimmingCharacters(in: .whitespaces).isEmpty
                                  ? nil : customerNumber.trimmingCharacters(in: .whitespaces)
        let trimmedLeadAmount   = leadAmountStr.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.leadAmount      = trimmedLeadAmount.isEmpty ? nil : Double(trimmedLeadAmount)
        updated.costEnabled     = costEnabled
        updated.lineCost        = Double(lineCostStr.trimmingCharacters(in: .whitespaces)) ?? customer.lineCost
        updated.conversions     = conversions
        updated.reassignAdvisor(to: advisor.isEmpty ? nil : advisor)
        updated.importDate      = importDate
        store.updateCustomer(updated)
        dismiss()
    }
}

// MARK: - 单笔成交记录行内编辑 Sheet
struct RecordEditSheet: View {
    let typeName:  String
    @Binding var amountStr: String
    @Binding var date:      Date
    @Binding var isVoided:  Bool
    let onSave:   () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("修改成交记录")) {
                    HStack {
                        Text("类型").foregroundColor(.secondary)
                        Spacer()
                        Text(typeName).foregroundColor(.primary)
                    }
                    HStack {
                        Text("金额").foregroundColor(.secondary)
                        TextField("成交金额", text: $amountStr).keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("时间", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    Toggle(isOn: $isVoided) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("未签收/退款作废")
                            Text(isVoided
                                 ? "客户和派发数保留，此单不计成交率与业绩"
                                 : "正常计入成交率与业绩")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .tint(.red)
                }
            }
            .navigationTitle("编辑成交记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: onSave).font(.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel, action: onCancel)
                }
            }
        }
    }
}
