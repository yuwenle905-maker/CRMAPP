// MARK: - AdvisorView.swift
// 服务顾问绩效卡片 + 详情页

import SwiftUI

// MARK: - 顾问绩效卡片（嵌入分析页）
struct AdvisorCard: View {

    @EnvironmentObject var store: DataStore
    let stats:    [AdvisorStats]
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3)) { expanded.toggle() }
            } label: {
                HStack {
                    Text("顾问绩效").font(.headline).foregroundColor(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary).font(.caption)
                }
                .padding()
            }

            if expanded {
                Divider()
                if stats.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "person.badge.clock")
                            .font(.largeTitle).foregroundColor(.secondary)
                        Text("暂无顾问数据")
                            .font(.subheadline).foregroundColor(.secondary)
                        Text("在设置里添加顾问名单，导入客户时选择负责人")
                            .font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    // 表头
                    HStack(spacing: 4) {
                        Text("顾问")
                            .font(.caption2.bold()).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("派发").font(.caption2.bold()).foregroundColor(.secondary)
                            .frame(width: 36, alignment: .trailing)
                        Text("新单率").font(.caption2.bold()).foregroundColor(.secondary)
                            .frame(width: 48, alignment: .trailing)
                        Text("复购率").font(.caption2.bold()).foregroundColor(.secondary)
                            .frame(width: 48, alignment: .trailing)
                        Text("业绩").font(.caption2.bold()).foregroundColor(.secondary)
                            .frame(width: 56, alignment: .trailing)
                        Spacer().frame(width: 16)
                    }
                    .padding(.horizontal).padding(.vertical, 6)
                    .background(Color(.systemGroupedBackground))

                    Divider()
                    ForEach(stats) { stat in
                        NavigationLink(destination:
                            AdvisorDetailView(stat: stat)
                                .environmentObject(store)
                        ) {
                            AdvisorRow(stat: stat)
                        }
                        .buttonStyle(.plain)
                        if stat.id != stats.last?.id {
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
    }
}

// MARK: - 顾问行
private struct AdvisorRow: View {
    let stat: AdvisorStats

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stat.name).font(.subheadline.bold()).foregroundColor(.primary)
                if stat.pending15Days > 0 {
                    Text("⚠ \(stat.pending15Days)人15天未成交")
                        .font(.caption2).foregroundColor(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(stat.totalLeads)").font(.subheadline.bold())
                .frame(width: 36, alignment: .trailing)
            Text(stat.newOrderRateText).font(.subheadline.bold()).foregroundColor(.blue)
                .frame(width: 48, alignment: .trailing)
            Text(stat.secondRateText).font(.subheadline.bold()).foregroundColor(.green)
                .frame(width: 48, alignment: .trailing)
            Text(stat.revenueText).font(.caption.bold()).foregroundColor(.indigo)
                .frame(width: 56, alignment: .trailing)
            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }
}

// MARK: - 顾问详情页
struct AdvisorDetailView: View {

    @EnvironmentObject var store: DataStore
    let stat: AdvisorStats
    var year:  Int? = nil
    var month: Int? = nil
    var role: AdvisorRole? = nil
    var groupName: String? = nil
    var roiText: String? = nil

    @State private var drillDown: DrillDownType? = nil

    enum DrillDownType: String, Identifiable {
        case leads        = "派发线索"
        case pending15    = "15天未成交"
        case newOrders    = "新单客户"
        case secondOrders = "二次复购"
        case revenue      = "业绩明细"
        var id: String { rawValue }
    }

    private var resolvedProfile: AdvisorProfile {
        store.settings.profile(for: stat.name)
    }
    private var resolvedRole: AdvisorRole { role ?? resolvedProfile.role }
    private var resolvedGroup: String { groupName ?? resolvedProfile.groupDisplay }
    private var resolvedROIText: String {
        roiText ?? (resolvedRole == .member ? stat.personalROIText : "—")
    }

    // 该顾问在该时段内首次获派的客户；后续转交不移动 ROI 成本。
    private var periodLeads: [Customer] {
        let cal = Calendar.current
        return store.customers.filter { c in
            guard c.dataType == .fullCustomer,
                  c.costEnabled,
                  ROIEngine.isFunnelActive(c),
                  c.roiAdvisorName == stat.name else { return false }
            if let y = year, let m = month {
                let comp = cal.dateComponents([.year, .month], from: c.importDate)
                return comp.year == y && comp.month == m
            }
            return true
        }
    }

    // 15天内派发但未成交
    private var pending15Customers: [Customer] {
        let now = Date()
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -15, to: now) else { return [] }
        return store.customers.filter { c in
            guard c.dataType == .fullCustomer,
                  c.costEnabled,
                  ROIEngine.isFunnelActive(c),
                  c.advisor == stat.name else { return false }
            return c.importDate >= cutoff && !c.validConversions.contains { $0.type == .newOrder }
        }
    }

    // 新单开发沿用首次派发人的 ROI 归属，并按实际开单日期归期。
    private var newOrderCustomers: [Customer] {
        let cal = Calendar.current
        return store.customers.filter { customer in
            guard customer.dataType == .fullCustomer,
                  customer.costEnabled,
                  ROIEngine.isFunnelActive(customer),
                  customer.roiAdvisorName == stat.name else { return false }
            return customer.validConversions.contains { record in
                guard record.type == .newOrder else { return false }
                if let year = year, let month = month {
                    let c = cal.dateComponents([.year, .month], from: record.date)
                    return c.year == year && c.month == month
                }
                return true
            }
        }
    }

    // 本期全部新单客户中，已经产生有效二次的客户；与首页复购率分子保持一致。
    private var secondOrderCustomers: [Customer] {
        newOrderCustomers.filter {
            $0.validConversions.contains { $0.type == .second }
        }
    }

    // 该顾问归属的每笔成交记录（含分成比例折算后的金额）
    private var revenueEntries: [(customer: Customer, record: ConversionRecord, amount: Double)] {
        let cal = Calendar.current
        var results: [(Customer, ConversionRecord, Double)] = []
        for c in store.customers {
            for rec in c.validConversions {
                if let y = year, let m = month {
                    let comp = cal.dateComponents([.year, .month], from: rec.date)
                    guard comp.year == y && comp.month == m else { continue }
                }
                if rec.advisorSplits.isEmpty {
                    if c.advisor == stat.name {
                        results.append((c, rec, rec.amount))
                    }
                } else if let split = rec.advisorSplits.first(where: { $0.name == stat.name }) {
                    results.append((c, rec, rec.amount * split.ratio))
                }
            }
        }
        return results.sorted { $0.1.date > $1.1.date }
    }

    var body: some View {
        List {
            Section(header: Text("组织与ROI")) {
                HStack {
                    Label(resolvedGroup, systemImage: "person.3.fill")
                    Spacer()
                    Text(resolvedRole.rawValue)
                        .font(.caption.bold())
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background((resolvedRole == .leader ? Color.orange : Color.blue).opacity(0.12))
                        .foregroundColor(resolvedRole == .leader ? .orange : .blue)
                        .clipShape(Capsule())
                }
                HStack {
                    Text(resolvedRole == .leader ? "小组ROI" : "个人ROI")
                    Spacer()
                    Text(resolvedROIText)
                        .font(.title3.bold()).foregroundColor(.purple)
                }
                Text(resolvedRole == .leader
                     ? "小组总业绩 ÷（本期所有组员派发资料 × 当前资料单价）"
                     : "个人业绩 ÷（本期个人派发资料 × 当前资料单价）")
                    .font(.caption2).foregroundColor(.secondary)
            }

            // 汇总 KPI（全部可点击）
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    Button { drillDown = .leads } label: {
                        AdvisorKPI(title: "派发线索", value: "\(periodLeads.count)", color: .primary, tappable: true)
                    }.buttonStyle(.plain)
                    Button { drillDown = .pending15 } label: {
                        AdvisorKPI(title: "15天未成交", value: "\(pending15Customers.count)",
                                   color: pending15Customers.isEmpty ? .secondary : .red, tappable: true)
                    }.buttonStyle(.plain)
                    Button { drillDown = .newOrders } label: {
                        AdvisorKPI(title: "新客户成交率", value: stat.newOrderRateText, color: .blue, tappable: true)
                    }.buttonStyle(.plain)
                    Button { drillDown = .newOrders } label: {
                        AdvisorKPI(title: "累计新客成交率", value: stat.cumulativeNewOrderRateText,
                                   color: .cyan, tappable: true)
                    }.buttonStyle(.plain)
                    Button { drillDown = .secondOrders } label: {
                        AdvisorKPI(title: "二次成交率", value: stat.secondRateText, color: .green, tappable: true)
                    }.buttonStyle(.plain)
                    Button { drillDown = .newOrders } label: {
                        AdvisorKPI(title: "新单客户数", value: "\(stat.newOrderCount)", color: .orange, tappable: true)
                    }.buttonStyle(.plain)
                    Button { drillDown = .revenue } label: {
                        AdvisorKPI(title: "本期业绩", value: stat.revenueText, color: .indigo, tappable: true)
                    }.buttonStyle(.plain)
                }
                .padding(.vertical, 6)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: { Text("绩效概览（点击查看明细）") }

            // 渠道拆分
            if !stat.channelRows.isEmpty {
                Section(header: Text("各渠道成交率")) {
                    ForEach(stat.channelRows) { row in
                        HStack {
                            Text(row.channel).font(.subheadline)
                            Spacer()
                            Text("\(row.leads) 人").font(.caption).foregroundColor(.secondary)
                            Text(row.rateText).font(.subheadline.bold()).foregroundColor(.blue)
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
            }

            // 客户列表（包含 advisorSplits 归属的客户）
            Section(header: Text("负责客户（\(periodLeads.count) 人）")) {
                if periodLeads.isEmpty {
                    Text("暂无数据").foregroundColor(.secondary).font(.caption)
                } else {
                    ForEach(periodLeads.sorted { $0.importDate > $1.importDate }) { customer in
                        NavigationLink(destination:
                            CustomerDetailView(customer: customer)
                                .environmentObject(store)
                        ) {
                            AdvisorCustomerRow(customer: customer, advisorName: stat.name)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(stat.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $drillDown) { type in
            drillSheet(type)
        }
    }

    @ViewBuilder
    private func drillSheet(_ type: DrillDownType) -> some View {
        switch type {
        case .leads:
            AdvisorCustomerListSheet(
                title: "派发线索",
                subtitle: "共 \(periodLeads.count) 位客户",
                customers: periodLeads,
                advisorName: stat.name
            ).environmentObject(store)

        case .pending15:
            AdvisorCustomerListSheet(
                title: "15天未成交",
                subtitle: "共 \(pending15Customers.count) 位，请跟进",
                customers: pending15Customers,
                advisorName: stat.name,
                accentColor: .red
            ).environmentObject(store)

        case .newOrders:
            AdvisorCustomerListSheet(
                title: "新单/复购客户",
                subtitle: "本期新单 \(newOrderCustomers.count) 人 · 新客户成交率 \(stat.newOrderRateText) · 累计率 \(stat.cumulativeNewOrderRateText)",
                customers: newOrderCustomers,
                advisorName: stat.name,
                accentColor: .blue
            ).environmentObject(store)

        case .secondOrders:
            AdvisorCustomerListSheet(
                title: "二次成交客户",
                subtitle: "共 \(secondOrderCustomers.count) 人 · 复购率 \(stat.secondRateText)",
                customers: secondOrderCustomers,
                advisorName: stat.name,
                accentColor: .green
            ).environmentObject(store)

        case .revenue:
            AdvisorRevenueSheet(
                title: "\(stat.name) 业绩明细",
                entries: revenueEntries,
                total: stat.revenue
            ).environmentObject(store)
        }
    }
}

// MARK: - KPI 小方块
private struct AdvisorKPI: View {
    let title:    String
    let value:    String
    let color:    Color
    var tappable: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold()).foregroundColor(color)
            Text(title).font(.caption2).foregroundColor(.secondary)
            if tappable {
                Image(systemName: "chevron.right.circle")
                    .font(.caption2).foregroundColor(color.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(tappable ? color.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - 客户列表 Sheet
struct AdvisorCustomerListSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: DataStore

    let title:       String
    let subtitle:    String
    let customers:   [Customer]
    let advisorName: String
    var accentColor: Color = .primary

    var body: some View {
        NavigationView {
            List {
                if !subtitle.isEmpty {
                    Section {
                        Text(subtitle)
                            .font(.subheadline).foregroundColor(accentColor)
                    }
                }
                Section {
                    if customers.isEmpty {
                        Text("暂无数据").foregroundColor(.secondary).font(.caption)
                    } else {
                        ForEach(customers.sorted { $0.importDate > $1.importDate }) { c in
                            NavigationLink(destination:
                                CustomerDetailView(customer: c).environmentObject(store)
                            ) {
                                AdvisorCustomerRow(customer: c, advisorName: advisorName)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing:
                Button("完成") { dismiss() }
            )
        }
    }
}

// MARK: - 业绩明细 Sheet
struct AdvisorRevenueSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: DataStore

    let title:   String
    let entries: [(customer: Customer, record: ConversionRecord, amount: Double)]
    let total:   Double

    private var totalText: String { String(format: "¥ %d", Int(total)) }

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Text("合计").font(.headline)
                        Spacer()
                        Text(totalText).font(.title3.bold()).foregroundColor(.indigo)
                    }
                }

                Section(header: Text("成交记录（\(entries.count) 笔）")) {
                    if entries.isEmpty {
                        Text("暂无数据").foregroundColor(.secondary).font(.caption)
                    } else {
                        ForEach(0..<entries.count, id: \.self) { i in
                            let entry = entries[i]
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(entry.customer.name).font(.subheadline.bold())
                                        if let num = entry.customer.customerNumber {
                                            Text("#\(num)").font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                    Text(entry.record.type.rawValue)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(entry.record.date.chineseDate)
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("¥\(Int(entry.amount))")
                                        .font(.subheadline.bold()).foregroundColor(.indigo)
                                    if entry.amount != entry.record.amount {
                                        Text("原 ¥\(Int(entry.record.amount))")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing:
                Button("完成") { dismiss() }
            )
        }
    }
}

// MARK: - 顾问详情中的客户行
struct AdvisorCustomerRow: View {
    let customer:    Customer
    let advisorName: String

    private var attributedRevenue: Double {
        customer.validConversions.reduce(0.0) { sum, rec in
            if rec.advisorSplits.isEmpty {
                return sum + rec.amount
            } else if let split = rec.advisorSplits.first(where: { $0.name == advisorName }) {
                return sum + rec.amount * split.ratio
            }
            return sum
        }
    }
    private var hasNewOrder: Bool { customer.validConversions.contains { $0.type == .newOrder } }

    private var statusColor: Color {
        if let tag = customer.followUpTag {
            switch tag {
            case .highValue: return Color(red: 1, green: 0.75, blue: 0)
            case .lost:      return .gray
            case .invalid:   return .red
            }
        }
        return hasNewOrder ? .green : .orange
    }
    private var statusText: String {
        if let tag = customer.followUpTag { return tag.rawValue }
        return hasNewOrder ? "已成交" : "未成交"
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(customer.name).font(.subheadline.bold())
                    if let num = customer.customerNumber {
                        Text("#\(num)").font(.caption2).foregroundColor(.secondary)
                    }
                }
                Text(customer.importDate.chineseDate)
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if attributedRevenue > 0 {
                    Text("¥\(Int(attributedRevenue))")
                        .font(.subheadline.bold()).foregroundColor(.indigo)
                }
                Text(statusText).font(.caption2).foregroundColor(statusColor)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 顾问管理（设置页内嵌）
struct AdvisorManagementSection: View {

    @EnvironmentObject var store: DataStore
    @State private var newName = ""
    @State private var newGroup = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            Section(header: Text("销售小组"), footer: Text("删除小组不会删除员工，原组员会自动转为“未分组”。")) {
                ForEach(store.settings.advisorGroups, id: \.self) { group in
                    Label(group, systemImage: "person.3.fill")
                        .foregroundColor(.primary)
                }
                .onDelete { indexSet in
                    removeGroups(at: indexSet)
                }

                HStack {
                    TextField("添加小组，如销售三组", text: $newGroup)
                    Button(action: addGroup) {
                        Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                    }
                    .disabled(newGroup.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section(header: Text("员工角色与归属"), footer: Text("组员显示个人ROI；组长显示所在小组ROI。角色和小组可随时修改。")) {
                if store.settings.advisors.isEmpty {
                    Text("暂无员工，在下方添加").foregroundColor(.secondary).font(.caption)
                } else {
                    ForEach(store.settings.advisors, id: \.self) { name in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(name).font(.subheadline.bold())
                            HStack(spacing: 12) {
                                Menu {
                                    ForEach(AdvisorRole.allCases) { role in
                                        Button {
                                            updateRole(role, for: name)
                                        } label: {
                                            if store.settings.profile(for: name).role == role {
                                                Label(role.rawValue, systemImage: "checkmark")
                                            } else {
                                                Text(role.rawValue)
                                            }
                                        }
                                    }
                                } label: {
                                    selectionLabel(
                                        title: "角色",
                                        value: store.settings.profile(for: name).role.rawValue
                                    )
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)

                                Menu {
                                    Button {
                                        updateGroup("", for: name)
                                    } label: {
                                        if store.settings.profile(for: name).groupName.isEmpty {
                                            Label("未分组", systemImage: "checkmark")
                                        } else {
                                            Text("未分组")
                                        }
                                    }
                                    ForEach(store.settings.advisorGroups, id: \.self) { group in
                                        Button {
                                            updateGroup(group, for: name)
                                        } label: {
                                            if store.settings.profile(for: name).groupName == group {
                                                Label(group, systemImage: "checkmark")
                                            } else {
                                                Text(group)
                                            }
                                        }
                                    }
                                } label: {
                                    selectionLabel(
                                        title: "归属小组",
                                        value: store.settings.profile(for: name).groupDisplay
                                    )
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .onDelete { indexSet in
                        removeAdvisors(at: indexSet)
                    }
                }

                HStack {
                    TextField("添加员工姓名", text: $newName)
                        .focused($fieldFocused)
                    Button(action: addAdvisor) {
                        Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func selectionLabel(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(8)
        .contentShape(Rectangle())
    }

    private func updateRole(_ role: AdvisorRole, for name: String) {
        store.settings.updateProfile(name: name, role: role)
        store.save()
    }

    private func updateGroup(_ groupName: String, for name: String) {
        store.settings.updateProfile(name: name, groupName: groupName)
        store.save()
    }

    private func addGroup() {
        let trimmed = newGroup.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !store.settings.advisorGroups.contains(trimmed) else { return }
        store.settings.advisorGroups.append(trimmed)
        store.save()
        newGroup = ""
    }

    private func removeGroups(at indexSet: IndexSet) {
        let removed = Set(indexSet.map { store.settings.advisorGroups[$0] })
        store.settings.advisorGroups.remove(atOffsets: indexSet)
        for index in store.settings.advisorProfiles.indices
            where removed.contains(store.settings.advisorProfiles[index].groupName) {
            store.settings.advisorProfiles[index].groupName = ""
        }
        store.save()
    }

    private func addAdvisor() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !store.settings.advisors.contains(trimmed) else { return }
        store.settings.advisors.append(trimmed)
        store.settings.updateProfile(name: trimmed)
        store.save()
        newName = ""
        fieldFocused = false
    }

    private func removeAdvisors(at indexSet: IndexSet) {
        let removed = Set(indexSet.map { store.settings.advisors[$0] })
        for index in store.customers.indices {
            let current = store.customers[index].advisor?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if removed.contains(current) {
                store.customers[index].detachDeletedAdvisor()
            } else if let roiOwner = store.customers[index].roiAdvisorName,
                      removed.contains(roiOwner) {
                store.customers[index].roiAdvisor = ""
            }
        }
        store.settings.advisors.remove(atOffsets: indexSet)
        store.settings.advisorProfiles.removeAll { removed.contains($0.name) }
        store.save()
    }
}

// MARK: - 导入/编辑时的顾问选择器行
struct AdvisorPickerRow: View {
    @EnvironmentObject var store: DataStore
    @Binding var advisor: String

    var body: some View {
        if !store.settings.advisors.isEmpty {
            Picker("服务顾问", selection: $advisor) {
                Text("未分配").tag("")
                ForEach(store.settings.advisors, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
        }
    }
}

// MARK: - 流水录入顾问分成选择器
struct AdvisorSplitPicker: View {
    @EnvironmentObject var store: DataStore
    @Binding var mode:     Int      // 0=未分配 1=单人 2=双人各半
    @Binding var advisor1: String
    @Binding var advisor2: String
    var allowsUnassigned: Bool = true

    private let labels = ["未分配", "单人", "双人各半"]
    private var availableModes: [Int] { allowsUnassigned ? [0, 1, 2] : [1, 2] }

    var body: some View {
        if store.settings.advisors.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill").foregroundColor(.blue).font(.caption)
                    Text("业绩归属").font(.subheadline.bold())
                    Spacer()
                    // 用 Button 替代 Picker(.segmented)，避免触摸被父容器拦截
                    HStack(spacing: 0) {
                        ForEach(availableModes, id: \.self) { idx in
                            Button {
                                mode = idx
                            } label: {
                                Text(labels[idx])
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(mode == idx ? Color.blue : Color(.systemFill))
                                    .foregroundColor(mode == idx ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1))
                }

                if mode == 1 {
                    Picker("顾问", selection: $advisor1) {
                        Text("请选择").tag("")
                        ForEach(store.settings.advisors, id: \.self) { n in Text(n).tag(n) }
                    }
                } else if mode == 2 {
                    HStack(spacing: 8) {
                        Picker("顾问A", selection: $advisor1) {
                            Text("顾问A").tag("")
                            ForEach(store.settings.advisors, id: \.self) { n in Text(n).tag(n) }
                        }
                        .frame(maxWidth: .infinity)
                        Text("各50%").font(.caption2).foregroundColor(.secondary)
                        Picker("顾问B", selection: $advisor2) {
                            Text("顾问B").tag("")
                            ForEach(store.settings.advisors, id: \.self) { n in Text(n).tag(n) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
