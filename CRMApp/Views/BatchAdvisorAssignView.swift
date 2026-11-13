// MARK: - BatchAdvisorAssignView.swift
// 业绩分配：单个查找 + 批量文本导入归属

import SwiftUI

// MARK: - 入口（Tab 切换）
struct BatchAdvisorAssignView: View {
    @State private var tab: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("单个查找").tag(0)
                Text("快速分配").tag(1)
                Text("批量导入").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 12)

            if tab == 0 {
                SingleAssignView()
            } else if tab == 1 {
                QuickAssignView()
            } else {
                BulkAssignView()
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - 单个查找（原逻辑）
private struct SingleAssignView: View {

    @EnvironmentObject var store: DataStore

    @State private var queryNumber: String = ""
    @State private var mode:     Int    = 0
    @State private var advisor1: String = ""
    @State private var advisor2: String = ""
    @State private var showToast = false
    @State private var toastMsg  = ""
    @FocusState private var fieldFocused: Bool

    private var matched: Customer? {
        let q = queryNumber.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        return store.customers.first { $0.customerNumber == q && $0.dataType == .fullCustomer }
    }

    private var splits: [AdvisorSplit] {
        switch mode {
        case 1 where !advisor1.isEmpty:
            return [AdvisorSplit(name: advisor1, ratio: 1.0)]
        case 2 where !advisor1.isEmpty && !advisor2.isEmpty:
            return [AdvisorSplit(name: advisor1, ratio: 0.5),
                    AdvisorSplit(name: advisor2, ratio: 0.5)]
        default: return []
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 编号搜索框
                HStack(spacing: 10) {
                    Image(systemName: "number.circle.fill")
                        .foregroundColor(.blue).font(.title3)
                    TextField("输入客户编号（如 2013）", text: $queryNumber)
                        .keyboardType(.numberPad)
                        .focused($fieldFocused)
                        .font(.title3.bold())
                    if !queryNumber.isEmpty {
                        Button { queryNumber = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(14)
                .padding(.horizontal)

                if let c = matched {
                    customerCard(c)
                    orderList(c)
                    advisorPickerSection
                    assignButton(c)
                } else if !queryNumber.trimmingCharacters(in: .whitespaces).isEmpty {
                    notFoundCard
                } else {
                    unassignedList
                }
                Spacer(minLength: 40)
            }
            .padding(.top, 12)
        }
        .onTapGesture { fieldFocused = false }
        .overlay(alignment: .bottom) {
            if showToast {
                Text(toastMsg)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func customerCard(_ c: Customer) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.blue.opacity(0.12)).frame(width: 48, height: 48)
                Text(String(c.name.prefix(1))).font(.title2.bold()).foregroundColor(.blue)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.name).font(.headline)
                    if let num = c.customerNumber {
                        Text("编号 \(num)").font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1)).foregroundColor(.blue).cornerRadius(4)
                    }
                }
                Text("共 \(c.conversions.count) 笔订单 · 总额 ¥\(Int(c.totalRevenue))")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14).padding(.horizontal)
    }

    private func orderList(_ c: Customer) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("订单列表").font(.caption.bold()).foregroundColor(.secondary)
                .padding(.horizontal, 20).padding(.vertical, 8)
            Divider()
            ForEach(c.conversions.sorted { $0.date > $1.date }) { rec in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rec.type.rawValue).font(.subheadline.bold())
                        Text(rec.date.chineseDate).font(.caption2).foregroundColor(.secondary)
                        if !rec.advisorSplits.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(rec.advisorSplits, id: \.name) { s in
                                    Text("\(s.name) \(s.ratioText)").font(.caption2.bold())
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.purple.opacity(0.12))
                                        .foregroundColor(.purple).cornerRadius(4)
                                }
                            }
                        } else {
                            Text("未分配").font(.caption2).foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                    Spacer()
                    Text("¥\(Int(rec.amount))").font(.subheadline.bold()).foregroundColor(.green)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                Divider()
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14).padding(.horizontal)
    }

    private var advisorPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择归属顾问").font(.caption.bold()).foregroundColor(.secondary).padding(.horizontal, 4)
            AdvisorSplitPicker(mode: $mode, advisor1: $advisor1, advisor2: $advisor2)
                .environmentObject(store)
        }
        .padding(.horizontal)
    }

    private func assignButton(_ c: Customer) -> some View {
        Button {
            guard !splits.isEmpty else { showTip("请先选择归属顾问"); return }
            assign(to: c)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.checkmark.fill")
                Text("一键分配所有订单").fontWeight(.bold)
            }
            .frame(maxWidth: .infinity).padding()
            .background(splits.isEmpty ? Color.gray.opacity(0.4) : Color.blue)
            .foregroundColor(.white).cornerRadius(14)
        }
        .disabled(splits.isEmpty).padding(.horizontal)
    }

    private var notFoundCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.fill.questionmark").font(.largeTitle).foregroundColor(.secondary.opacity(0.4))
            Text("编号 \(queryNumber) 未找到").font(.headline).foregroundColor(.secondary)
            Text("请确认编号是否正确").font(.caption).foregroundColor(.secondary)
        }.padding(40)
    }

    // 未分配业绩的客户列表（搜索框为空时展示）
    private var unassignedCustomers: [(customer: Customer, unassignedCount: Int)] {
        store.customers
            .filter { c in
                guard c.dataType == .fullCustomer else { return false }
                let hasAdvisor = !(c.advisor ?? "").isEmpty
                if hasAdvisor {
                    // advisor 已设但有新记录没有 splits
                    return c.conversions.contains { $0.advisorSplits.isEmpty }
                } else {
                    return !c.conversions.isEmpty
                }
            }
            .map { c in
                let count = c.conversions.filter { rec in
                    rec.advisorSplits.isEmpty && (c.advisor == nil || c.advisor!.isEmpty)
                }.count
                return (customer: c, unassignedCount: count)
            }
            .filter { $0.unassignedCount > 0 }
            .sorted {
                if $0.customer.importDate != $1.customer.importDate {
                    return $0.customer.importDate > $1.customer.importDate
                }
                let a = $0.customer.customerNumber.flatMap(Int.init) ?? 0
                let b = $1.customer.customerNumber.flatMap(Int.init) ?? 0
                return a > b
            }
    }

    private var unassignedList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if unassignedCustomers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.largeTitle).foregroundColor(.green.opacity(0.5))
                    Text("所有客户业绩已分配").font(.subheadline).foregroundColor(.secondary)
                    Text("输入编号可单独查找并修改归属")
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                // 标题栏
                HStack {
                    Label("待分配业绩客户", systemImage: "person.badge.minus")
                        .font(.caption.bold()).foregroundColor(.purple)
                    Spacer()
                    Text("\(unassignedCustomers.count) 位")
                        .font(.caption.bold()).foregroundColor(.secondary)
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Color.purple.opacity(0.06))

                Divider()

                ForEach(unassignedCustomers, id: \.customer.id) { item in
                    Button {
                        queryNumber = item.customer.customerNumber ?? ""
                        fieldFocused = false
                    } label: {
                        HStack(spacing: 12) {
                            // 编号
                            if let num = item.customer.customerNumber {
                                Text(num)
                                    .font(.system(.subheadline, design: .monospaced).bold())
                                    .foregroundColor(.blue)
                                    .frame(width: 44, alignment: .leading)
                            } else {
                                Spacer().frame(width: 44)
                            }
                            // 姓名
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.customer.name).font(.subheadline.bold()).foregroundColor(.primary)
                                Text("\(item.unassignedCount) 笔未分配")
                                    .font(.caption2).foregroundColor(.purple)
                            }
                            Spacer()
                            // 总业绩
                            Text("¥\(Int(item.customer.totalRevenue))")
                                .font(.subheadline.bold()).foregroundColor(.indigo)
                            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 60)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .padding(.horizontal)
    }

    private func assign(to customer: Customer) {
        guard let idx = store.customers.firstIndex(where: { $0.id == customer.id }) else { return }
        for i in store.customers[idx].conversions.indices
            where store.customers[idx].conversions[i].advisorSplits.isEmpty {
            store.customers[idx].conversions[i].advisorSplits = splits
        }
        if splits.count == 1 {
            store.customers[idx].reassignAdvisor(to: splits[0].name)
        }
        store.save()
        let desc = splits.count == 1 ? "\(splits[0].name) 100%" : "\(splits[0].name)+\(splits[1].name) 各50%"
        showTip("已分配：\(customer.name) \(customer.conversions.count)笔 → \(desc)")
    }

    private func showTip(_ msg: String) {
        toastMsg = msg
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { showToast = false } }
    }
}

// MARK: - 批量文本导入归属
private struct BulkAssignView: View {

    @EnvironmentObject var store: DataStore

    @State private var inputText: String = ""
    @State private var preview:   [BulkRow] = []
    @State private var isParsed   = false
    @State private var showToast  = false
    @State private var toastMsg   = ""
    @FocusState private var focused: Bool

    // 解析结果行
    struct BulkRow: Identifiable {
        let id = UUID()
        let raw: String
        let customerNumber: String?
        let customerName:   String?   // 按名字匹配时使用
        let advisorName:    String
        var matched:        Customer? = nil
        var status: Status = .pending

        enum Status { case pending, ok, notFound, noAdvisor }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // 格式说明
                formatHint

                // 输入区
                VStack(alignment: .leading, spacing: 6) {
                    Text("粘贴分配名单").font(.caption.bold()).foregroundColor(.secondary)
                    ZStack(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text("每行一条，支持格式：\n编号 顾问名  →  2013 媚\n姓名 顾问名  →  张三 媚")
                                .font(.caption).foregroundColor(.secondary.opacity(0.6))
                                .padding(10)
                        }
                        TextEditor(text: $inputText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 180)
                            .focused($focused)
                            .opacity(inputText.isEmpty ? 0.25 : 1)
                    }
                    .padding(4)
                    .background(Color(.tertiarySystemFill))
                    .cornerRadius(10)
                }
                .padding(.horizontal)

                // 解析 & 清空按钮
                HStack(spacing: 12) {
                    Button {
                        inputText = ""; preview = []; isParsed = false
                    } label: {
                        Text("清空").frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Color(.systemFill)).foregroundColor(.primary).cornerRadius(10)
                    }
                    Button {
                        focused = false
                        preview = parse(inputText)
                        isParsed = true
                    } label: {
                        Text("解析预览").frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Color.blue).foregroundColor(.white).cornerRadius(10)
                    }
                }
                .padding(.horizontal)

                // 预览区
                if isParsed {
                    previewSection
                }

                Spacer(minLength: 40)
            }
            .padding(.top, 12)
        }
        .onTapGesture { focused = false }
        .overlay(alignment: .bottom) {
            if showToast {
                Text(toastMsg)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.green).foregroundColor(.white)
                    .clipShape(Capsule()).padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: 格式说明卡
    private var formatHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("支持的粘贴格式", systemImage: "info.circle").font(.caption.bold()).foregroundColor(.blue)
            Text("""
            每行一条，编号或姓名 + 空格 + 顾问名：
              2013 媚
              2015 Sa
              张三 龙
            也支持中间用制表符分隔（从 Excel/表格直接复制）。
            """)
            .font(.caption).foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.blue.opacity(0.06))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: 预览结果
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 统计条
            let okCount  = preview.filter { $0.status == .ok }.count
            let errCount = preview.filter { $0.status == .notFound || $0.status == .noAdvisor }.count
            HStack {
                Text("共 \(preview.count) 条").font(.caption.bold()).foregroundColor(.secondary)
                Spacer()
                if okCount > 0 {
                    Text("✓ \(okCount) 匹配").font(.caption.bold()).foregroundColor(.green)
                }
                if errCount > 0 {
                    Text("✗ \(errCount) 未找到").font(.caption.bold()).foregroundColor(.red).padding(.leading, 8)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))

            Divider()

            ForEach(preview) { row in
                HStack(spacing: 10) {
                    // 状态图标
                    Image(systemName: row.status == .ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(row.status == .ok ? .green : .red)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 2) {
                        if let c = row.matched {
                            HStack(spacing: 4) {
                                Text(c.name).font(.subheadline.bold())
                                if let num = c.customerNumber {
                                    Text("编号\(num)").font(.caption2)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Color.blue.opacity(0.1)).foregroundColor(.blue).cornerRadius(3)
                                }
                            }
                            Text("共\(c.conversions.count)笔订单").font(.caption2).foregroundColor(.secondary)
                        } else {
                            Text(row.raw).font(.subheadline).foregroundColor(.secondary)
                            Text(row.status == .noAdvisor ? "格式错误：缺少顾问名" : "未找到此客户")
                                .font(.caption2).foregroundColor(.red)
                        }
                    }
                    Spacer()
                    Text("→ \(row.advisorName)").font(.caption.bold()).foregroundColor(.purple)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                Divider()
            }

            // 一键应用按钮
            let applyCount = preview.filter { $0.status == .ok }.count
            if applyCount > 0 {
                Button { applyAll() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.checkmark.fill")
                        Text("应用 \(applyCount) 条归属").fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.blue).foregroundColor(.white).cornerRadius(14)
                }
                .padding(16)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14).padding(.horizontal)
    }

    // MARK: 解析逻辑
    private func parse(_ text: String) -> [BulkRow] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return lines.map { line in
            // 分隔符：制表符 或 多个空格 或 单空格
            let parts = line
                .replacingOccurrences(of: "\t", with: " ")
                .components(separatedBy: " ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard parts.count >= 2 else {
                return BulkRow(raw: line, customerNumber: nil, customerName: nil,
                               advisorName: "", status: .noAdvisor)
            }

            let advisorName = parts.last!
            let key = parts.dropLast().joined(separator: " ")

            // 判断 key 是编号（纯数字）还是姓名
            let isNumber = key.allSatisfy { $0.isNumber }
            var row = BulkRow(raw: line,
                              customerNumber: isNumber ? key : nil,
                              customerName:   isNumber ? nil : key,
                              advisorName:    advisorName)

            // 匹配客户
            if isNumber {
                row.matched = store.customers.first {
                    $0.customerNumber == key && $0.dataType == .fullCustomer
                }
            } else {
                row.matched = store.customers.first {
                    $0.name == key && $0.dataType == .fullCustomer
                }
            }

            row.status = row.matched != nil ? .ok : .notFound
            return row
        }
    }

    // MARK: 批量应用
    private func applyAll() {
        var applied = 0
        for row in preview where row.status == .ok {
            guard let customer = row.matched,
                  let idx = store.customers.firstIndex(where: { $0.id == customer.id }) else { continue }
            let splits = [AdvisorSplit(name: row.advisorName, ratio: 1.0)]
            for i in store.customers[idx].conversions.indices
                where store.customers[idx].conversions[i].advisorSplits.isEmpty {
                store.customers[idx].conversions[i].advisorSplits = splits
            }
            applied += 1
            store.customers[idx].reassignAdvisor(to: row.advisorName)
        }
        store.save()
        showTip("已完成：\(applied) 位客户归属已更新")
        preview = parse(inputText)   // 刷新预览状态
    }

    private func showTip(_ msg: String) {
        toastMsg = msg
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { showToast = false } }
    }
}

// MARK: - 快速分配（勾选客户 → 一键归属顾问）
private struct QuickAssignView: View {

    @EnvironmentObject var store: DataStore

    @State private var searchText:   String       = ""
    @State private var selected:     Set<UUID>    = []
    @State private var advisorName:  String       = ""
    @State private var showToast     = false
    @State private var toastMsg      = ""
    @State private var filterMode:   Int          = 0  // 0=全部 1=未分配 2=已分配

    private var advisorList: [String] {
        store.settings.advisors.filter { !$0.isEmpty }
    }

    private var candidates: [Customer] {
        store.customers
            .filter { $0.dataType == .fullCustomer }
            .filter { c in
                switch filterMode {
                case 1: return (c.advisor == nil || c.advisor!.isEmpty) &&
                               !c.conversions.contains { !$0.advisorSplits.isEmpty }
                case 2: return c.advisor != nil && !c.advisor!.isEmpty
                default: return true
                }
            }
            .filter { c in
                guard !searchText.isEmpty else { return true }
                let q = searchText.lowercased()
                return c.name.lowercased().contains(q) ||
                       (c.customerNumber ?? "").contains(q)
            }
            .sorted {
                if $0.importDate != $1.importDate {
                    return $0.importDate > $1.importDate
                }
                let a = $0.customerNumber.flatMap(Int.init) ?? 0
                let b = $1.customerNumber.flatMap(Int.init) ?? 0
                return a > b
            }
    }

    private var allSelected: Bool { candidates.allSatisfy { selected.contains($0.id) } }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {

                // 搜索框
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("搜索编号或姓名", text: $searchText)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(10)
                .padding(.horizontal).padding(.top, 10)

                // 筛选条 + 全选
                HStack(spacing: 0) {
                    filterBtn("全部",  tag: 0)
                    filterBtn("未分配", tag: 1)
                    filterBtn("已分配", tag: 2)
                    Spacer()
                    Button {
                        if allSelected {
                            candidates.forEach { selected.remove($0.id) }
                        } else {
                            candidates.forEach { selected.insert($0.id) }
                        }
                    } label: {
                        Text(allSelected ? "取消全选" : "全选")
                            .font(.caption.bold()).foregroundColor(.blue)
                    }
                    .padding(.trailing, 16)
                }
                .padding(.top, 8)

                // 统计条
                HStack {
                    Text("共 \(candidates.count) 位 · 已选 \(selected.count) 位")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 4)

                Divider()

                // 客户列表
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(candidates) { customer in
                            customerRow(customer)
                            Divider().padding(.leading, 56)
                        }
                    }
                    .padding(.bottom, 140)   // 给底部操作栏留空间
                }
            }

            // 底部顾问选择 + 分配按钮
            bottomBar
        }
        .overlay(alignment: .bottom) {
            if showToast {
                Text(toastMsg)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.green).foregroundColor(.white)
                    .clipShape(Capsule()).padding(.bottom, 160)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: 客户行
    private func customerRow(_ c: Customer) -> some View {
        let isSelected = selected.contains(c.id)
        let currentAdvisor = c.advisor ?? ""
        return Button {
            if isSelected { selected.remove(c.id) } else { selected.insert(c.id) }
        } label: {
            HStack(spacing: 12) {
                // 勾选框
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                        .background(isSelected ? Color.blue.opacity(0.12) : Color.clear)
                        .cornerRadius(5)
                    if isSelected {
                        Image(systemName: "checkmark").font(.caption.bold()).foregroundColor(.blue)
                    }
                }
                .frame(width: 32)

                // 编号
                if let num = c.customerNumber {
                    Text(num)
                        .font(.system(.subheadline, design: .monospaced).bold())
                        .foregroundColor(.blue)
                        .frame(width: 44, alignment: .leading)
                }

                // 姓名
                Text(c.name).font(.subheadline).foregroundColor(.primary)

                Spacer()

                // 当前顾问
                if !currentAdvisor.isEmpty {
                    Text(currentAdvisor)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.1))
                        .foregroundColor(.purple).cornerRadius(4)
                } else {
                    Text("未分配").font(.caption2).foregroundColor(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(isSelected ? Color.blue.opacity(0.04) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: 底部操作栏
    private var bottomBar: some View {
        VStack(spacing: 10) {
            Divider()
            // 顾问选择
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(advisorList, id: \.self) { name in
                        Button {
                            advisorName = (advisorName == name) ? "" : name
                        } label: {
                            Text(name)
                                .font(.subheadline.bold())
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(advisorName == name ? Color.blue : Color(.systemFill))
                                .foregroundColor(advisorName == name ? .white : .primary)
                                .cornerRadius(20)
                        }
                    }
                }
                .padding(.horizontal)
            }

            // 分配按钮
            Button { applyAssign() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.checkmark.fill")
                    Text(selected.isEmpty
                         ? "请先勾选客户"
                         : advisorName.isEmpty
                           ? "请选择顾问"
                           : "分配 \(selected.count) 位客户 → \(advisorName)")
                    .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(canApply ? Color.blue : Color.gray.opacity(0.35))
                .foregroundColor(.white).cornerRadius(13)
            }
            .disabled(!canApply)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.regularMaterial)
    }

    private var canApply: Bool { !selected.isEmpty && !advisorName.isEmpty }

    private func filterBtn(_ label: String, tag: Int) -> some View {
        Button { filterMode = tag } label: {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(filterMode == tag ? Color.blue.opacity(0.12) : Color.clear)
                .foregroundColor(filterMode == tag ? .blue : .secondary)
                .cornerRadius(6)
        }
        .padding(.leading, tag == 0 ? 12 : 0)
    }

    // MARK: 执行分配
    private func applyAssign() {
        let splits = [AdvisorSplit(name: advisorName, ratio: 1.0)]
        var count = 0
        for id in selected {
            guard let idx = store.customers.firstIndex(where: { $0.id == id }) else { continue }
            for i in store.customers[idx].conversions.indices
                where store.customers[idx].conversions[i].advisorSplits.isEmpty {
                store.customers[idx].conversions[i].advisorSplits = splits
            }
            count += 1
            store.customers[idx].reassignAdvisor(to: advisorName)
        }
        store.save()
        selected.removeAll()
        withAnimation { showToast = true }
        toastMsg = "已完成：\(count) 位客户 → \(advisorName)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { showToast = false } }
    }
}
