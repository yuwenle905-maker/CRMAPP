// MARK: - ImportView.swift
// 智能粘贴导入界面（废弃文件选择，改为文本粘贴 + 逐条确认 + 去重弹窗）

import SwiftUI
import UIKit

// MARK: - 主界面
struct ImportView: View {

    @EnvironmentObject var store: DataStore
    @State private var pasteText:       String = ""
    @State private var parsedRows:      [ParsedRow]      = []
    @State private var failedRows:      [ParseFailedRow] = []
    @State private var showConfirmSheet = false
    @State private var importAdvisor:   String = ""   // 本批次服务顾问
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── 说明卡片 ───────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Text("直接粘贴数据，系统自动解析")
                            .font(.headline)
                        Text("支持格式：姓名 电话 地址 商品 金额 身高/体重/年龄 快递单号")
                            .font(.caption).foregroundColor(.secondary)
                        Text("也支持流水格式：张三 新单 4280（不产生新客户）")
                            .font(.caption).foregroundColor(.orange)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // ── 服务顾问选择（有顾问名单时显示）─────────
                    if !store.settings.advisors.isEmpty {
                        HStack {
                            Text("服务顾问").font(.subheadline).foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $importAdvisor) {
                                Text("未分配").tag("")
                                ForEach(store.settings.advisors, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    // ── 粘贴文本框 ────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("粘贴数据")
                                .font(.subheadline.bold())
                            Spacer()
                            if !pasteText.isEmpty {
                                Button("清空") {
                                    dismissKeyboard()
                                    pasteText   = ""
                                    parsedRows  = []
                                    failedRows  = []
                                }
                                .font(.caption)
                                .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal)

                        PasteAwareTextEditor(text: $pasteText, onPaste: { self.forceParse(text: $0) })
                            .frame(minHeight: 180, maxHeight: 320)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                    }

                    // ── 操作按钮 ─────────────────────────────
                    HStack(spacing: 10) {
                        // 第3层：直接读剪贴板，绕过所有 UITextView 事件机制
                        Button {
                            if let clip = UIPasteboard.general.string,
                               !clip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                pasteText = clip
                                forceParse(text: clip)
                            }
                        } label: {
                            Label("读取剪贴板", systemImage: "doc.on.clipboard")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(.secondarySystemGroupedBackground))
                                .foregroundColor(.blue)
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1))
                        }

                        Button {
                            forceParse(text: pasteText)
                        } label: {
                            Label("解析预览", systemImage: "text.magnifyingglass")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                            ? Color.gray : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            dismissKeyboard()
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .padding(10)
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)

                    // ── 解析失败提示 ─────────────────────────
                    if !failedRows.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("无法解析的行（\(failedRows.count) 条）")
                                .font(.caption.bold()).foregroundColor(.red)
                                .padding(.horizontal).padding(.top, 8)
                            Divider()
                            ForEach(failedRows) { row in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("第\(row.lineNumber)行：\(row.rawLine)")
                                        .font(.caption.monospaced()).lineLimit(2)
                                    Text(row.reason).font(.caption2).foregroundColor(.red)
                                }
                                .padding(.horizontal).padding(.vertical, 6)
                                Divider()
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("智能导入")
            .onTapGesture { dismissKeyboard() }
        }
        // 确认弹窗
        .sheet(isPresented: $showConfirmSheet) {
            ImportConfirmSheet(
                rows:      parsedRows,
                failed:    failedRows,
                onConfirm: { confirmed in
                    commitToStore(rows: confirmed, advisor: importAdvisor)
                    showConfirmSheet = false
                    pasteText  = ""
                    parsedRows = []
                    failedRows = []
                },
                onCancel: { showConfirmSheet = false }
            )
            .environmentObject(store)
        }
    }

    // MARK: 粘贴解析入口

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    func forceParse(text: String) {
        dismissKeyboard()
        let result = SmartPasteParser.parse(text)
        parsedRows = result.rows
        failedRows = result.failed
        if !parsedRows.isEmpty { showConfirmSheet = true }
    }

    // MARK: 入库逻辑
    // 到达这里的行已经过用户的所有弹窗确认，直接写入
    private func commitToStore(rows: [ParsedRow], advisor: String) {
        var batchImported = 0
        var batchFull     = 0
        let batchID       = UUID()

        for row in rows {
            let rowAdvisor = row.advisor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let resolvedAdvisor = rowAdvisor.isEmpty
                ? advisor.trimmingCharacters(in: .whitespacesAndNewlines)
                : rowAdvisor

            // 流水记录：追加转化到已有客户，金额写入 ConversionRecord
            if row.dataType == .ledgerEntry {
                let matchPhone = row.phone
                if let idx = store.customers.firstIndex(where: {
                    $0.name == row.name &&
                    $0.dataType == .fullCustomer &&
                    (matchPhone == nil || $0.phone == matchPhone)
                }) {
                    let record = ConversionRecord(
                        type:        row.conversionType,
                        amount:      row.leadAmount ?? 0,   // 修复：写入真实金额
                        date:        row.importDate ?? Date(),
                        productNote: row.productNote
                    )
                    store.customers[idx].conversions.append(record)
                    store.save()
                }
                continue
            }

            // 完整客户写入（智能导入只建档案，不生成成交流水，防止身高/体重等数字污染营业额）
            let phone           = row.phone ?? "unknown_\(UUID().uuidString.prefix(8))"
            let currentLineCost = store.settings.leadUnitPrice
            let customer = Customer(
                name:           row.name,
                phone:          phone,
                address:        row.address,
                age:            row.age,
                height:         row.height,
                weight:         row.weight,
                gender:         row.gender,
                customerNumber: row.customerNumber,
                costEnabled:    true,
                leadAmount:     row.leadAmount,
                lineCost:       currentLineCost,
                dataType:       .fullCustomer,
                importBatchID:  batchID,
                importDate:     row.importDate ?? Date(),
                conversions:    [],  // 智能导入不生成成交流水，需手动录入
                channel:        row.channel,
                advisor:        resolvedAdvisor.isEmpty ? nil : resolvedAdvisor
            )
            store.addCustomer(customer)
            batchFull    += 1
            batchImported += 1
        }

        let batch = ImportBatch(
            id:                batchID,
            source:            "智能粘贴",
            importDate:        Date(),
            recordCount:       batchImported,
            fullCustomerCount: batchFull
        )
        store.addBatch(batch)
    }
}

// MARK: - 确认弹窗 Sheet
struct ImportConfirmSheet: View {

    @EnvironmentObject var store: DataStore
    let rows:      [ParsedRow]
    let failed:    [ParseFailedRow]
    let onConfirm: ([ParsedRow]) -> Void
    let onCancel:  () -> Void

    @State private var confirmedRows: [ParsedRow]
    @State private var pendingQueue:  [ParsedRow] = []
    @State private var processedRows: [ParsedRow] = []

    // 同名同电话二次确认 Sheet（需求3）
    @State private var showDoubleCheckSheet = false
    @State private var doubleCheckRow:       ParsedRow?
    @State private var doubleCheckExisting:  Customer?

    init(rows: [ParsedRow], failed: [ParseFailedRow],
         onConfirm: @escaping ([ParsedRow]) -> Void,
         onCancel: @escaping () -> Void) {
        self.rows      = rows
        self.failed    = failed
        self.onConfirm = onConfirm
        self.onCancel  = onCancel
        _confirmedRows = State(initialValue: rows)
    }

    var fullCustomerCount: Int { confirmedRows.filter { $0.isFullCustomer }.count }
    var ledgerCount:       Int { confirmedRows.filter { $0.dataType == .ledgerEntry }.count }
    var pendingCount:      Int { confirmedRows.filter { $0.parseWarning != nil }.count }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                List {
                    // ── 汇总卡 ──────────────────────────────────
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("共解析 \(confirmedRows.count) 条")
                                    .font(.headline)
                                Text("新客户 \(fullCustomerCount) 人 · 流水 \(ledgerCount) 条"
                                     + (pendingCount > 0 ? " · ⚠ \(pendingCount) 条待补录" : ""))
                                    .font(.caption)
                                    .foregroundColor(pendingCount > 0 ? .orange : .secondary)
                            }
                            Spacer()
                            Image(systemName: pendingCount > 0
                                  ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundColor(pendingCount > 0 ? .orange : .green)
                                .font(.title2)
                        }
                        .padding(.vertical, 4)
                    }

                    // ── 可编辑预览卡片 ──────────────────────────
                    // 点击卡片进入 PendingCustomerEditView 补录/修改
                    // 橙色背景 = 解析时有字段缺失，需要手动补全
                    Section(header: HStack {
                        Text("点击卡片补录信息（左滑删除）")
                        if pendingCount > 0 {
                            Spacer()
                            Text("\(pendingCount) 条橙色待补录")
                                .foregroundColor(.orange)
                        }
                    }) {
                        ForEach($confirmedRows) { $row in
                            NavigationLink(
                                destination: PendingCustomerEditView(row: $row)
                            ) {
                                PendingRowCard(row: row)
                            }
                            .listRowBackground(
                                row.parseWarning != nil
                                    ? Color.orange.opacity(0.07)
                                    : nil
                            )
                        }
                        .onDelete { confirmedRows.remove(atOffsets: $0) }
                    }

                    // ── 失败行 ───────────────────────────────────
                    if !failed.isEmpty {
                        Section(header: Text("未能解析（\(failed.count) 行）").foregroundColor(.red)) {
                            ForEach(failed) { f in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.rawLine).font(.caption.monospaced()).lineLimit(2)
                                    Text(f.reason).font(.caption2).foregroundColor(.red)
                                }
                            }
                        }
                    }

                    // 底部按钮占位
                    Color.clear.frame(height: 84)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.insetGrouped)

                // ── 固定底部：确认全部导入 ──────────────────────
                VStack(spacing: 0) {
                    Divider()
                    Button { startProcessing() } label: {
                        HStack {
                            Spacer()
                            Label("确认全部导入（\(confirmedRows.count) 条）",
                                  systemImage: "checkmark.circle.fill")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(confirmedRows.isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(confirmedRows.isEmpty)
                    .padding()
                    .background(Color(.systemBackground))
                }
            }
            .navigationTitle("预览待导入数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) { onCancel() }
                }
            }
        }
        // 同名同电话二次确认
        .sheet(isPresented: $showDoubleCheckSheet) {
            if let row = doubleCheckRow, let existing = doubleCheckExisting {
                DoubleCheckSheet(
                    incomingRow: row,
                    existing:    existing,
                    onMerge:     { handleMerge(row: row, into: existing) },
                    onForceNew:  { handleForceNew(row: row) }
                )
                .environmentObject(store)
            }
        }
    }

    // MARK: ── 处理队列入口
    private func startProcessing() {
        pendingQueue  = confirmedRows
        processedRows = []
        processNext()
    }

    private func processNext() {
        guard !pendingQueue.isEmpty else {
            onConfirm(processedRows)
            return
        }
        let row = pendingQueue.removeFirst()

        // 流水行：姓名+电话匹配 → 直接放行（commitToStore 负责写入）
        // 同名但电话不同 → 不拦截，也直接放行作新客户
        if row.dataType == .ledgerEntry {
            processedRows.append(row)
            processNext()
            return
        }

        // 完整客户行：检查是否同名同电话
        guard let phone = row.phone else {
            // 无电话：直接新建，不拦截
            processedRows.append(row)
            processNext()
            return
        }

        // 同名且同电话：拦截弹窗，等用户决策（需求2+3）
        if let existing = store.customers.first(where: {
            $0.phone == phone && $0.name == row.name && $0.dataType == .fullCustomer
        }) {
            doubleCheckRow      = row
            doubleCheckExisting = existing
            showDoubleCheckSheet = true
            return   // 挂起，等回调
        }

        // 同名但电话不同：静默新建（需求2）
        processedRows.append(row)
        processNext()
    }

    // 用户选「合并/追加到已有客户」
    private func handleMerge(row: ParsedRow, into existing: Customer) {
        showDoubleCheckSheet = false
        if let idx = store.customers.firstIndex(where: { $0.id == existing.id }) {
            let record = ConversionRecord(
                type:        row.conversionType,
                amount:      row.leadAmount ?? 0,
                date:        row.importDate ?? Date(),
                productNote: row.productNote
            )
            store.customers[idx].conversions.append(record)
            if let newAmt = row.leadAmount {
                store.customers[idx].leadAmount = newAmt
            }
            if let advisor = row.advisor?.trimmingCharacters(in: .whitespacesAndNewlines),
               !advisor.isEmpty {
                store.customers[idx].reassignAdvisor(to: advisor)
            }
            store.save()
        }
        doubleCheckRow      = nil
        doubleCheckExisting = nil
        processNext()
    }

    // 用户选「作为独立新客户写入」
    private func handleForceNew(row: ParsedRow) {
        showDoubleCheckSheet = false
        processedRows.append(row)   // 带原始 phone 进 commitToStore，生成新 UUID
        doubleCheckRow      = nil
        doubleCheckExisting = nil
        processNext()
    }
}

// MARK: - 待导入卡片（只读，作为 NavigationLink label 使用）
struct PendingRowCard: View {
    let row: ParsedRow

    private var isAnomalous: Bool { row.parseWarning != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // 头部：类型徽章 + 待补录徽章 + 姓名 + 金额
            HStack(spacing: 6) {
                Text(row.dataType == .fullCustomer ? "新客户" : "流水")
                    .font(.caption2.bold())
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(row.dataType == .fullCustomer
                                ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                    .foregroundColor(row.dataType == .fullCustomer ? .blue : .orange)
                    .cornerRadius(4)

                if isAnomalous {
                    Text("待补录")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.18))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }

                Text(row.name).fontWeight(.semibold)
                Spacer()
                if let amt = row.leadAmount {
                    Text("¥\(Int(amt))").fontWeight(.bold).foregroundColor(.green)
                }
            }

            // 电话 + 地址
            if let phone = row.phone {
                Text(phone).font(.caption).foregroundColor(.secondary)
            }
            if let addr = row.address {
                Text(addr).font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }

            // 渠道 + 体征
            HStack(spacing: 8) {
                Text(row.channel)
                    .font(.caption2)
                    .foregroundColor(.blue)
                if let advisor = row.advisor, !advisor.isEmpty {
                    Label(advisor, systemImage: "person.fill")
                        .font(.caption2)
                        .foregroundColor(.purple)
                }
                if let h = row.height { Text("\(Int(h))cm").font(.caption2).foregroundColor(.secondary) }
                if let w = row.weight { Text("\(Int(w))kg").font(.caption2).foregroundColor(.secondary) }
                if let a = row.age    { Text("\(a)岁").font(.caption2).foregroundColor(.secondary) }
                if let p = row.productNote { Text(p).font(.caption2).foregroundColor(.secondary).lineLimit(1) }
            }

            // 缺失字段提示
            if isAnomalous {
                let missing = row.parseWarning?
                    .components(separatedBy: "：").dropFirst().first?
                    .components(separatedBy: " ←").first ?? "部分字段"
                HStack(spacing: 3) {
                    Image(systemName: "pencil.circle").font(.caption2)
                    Text("缺失 \(missing) — 点击补录").font(.caption2)
                }
                .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 待导入客户编辑页（点击卡片后进入，可修改解析结果）
struct PendingCustomerEditView: View {

    @Binding var row: ParsedRow
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss

    @State private var name:      String
    @State private var phone:     String
    @State private var address:   String
    @State private var amountStr: String
    @State private var heightStr: String
    @State private var weightStr: String
    @State private var ageStr:    String
    @State private var channel:   String
    @State private var gender:    String
    @State private var custNum:   String
    @State private var advisor:   String

    private let channelOptions = ["直播", "食谱", "小红书", "问答", "千川", "广点通", "视频号", "朋友圈", "抖音", "自然流量"]
    private let genderOptions  = ["未知", "女", "男"]

    init(row: Binding<ParsedRow>) {
        _row = row
        let r = row.wrappedValue
        _name      = State(initialValue: r.name)
        _phone     = State(initialValue: r.phone    ?? "")
        _address   = State(initialValue: r.address  ?? "")
        _amountStr = State(initialValue: r.leadAmount.map { String(format: "%g", $0) } ?? "")
        _heightStr = State(initialValue: r.height.map { String(Int($0)) } ?? "")
        _weightStr = State(initialValue: r.weight.map { String(Int($0)) } ?? "")
        _ageStr    = State(initialValue: r.age.map  { String($0) }        ?? "")
        _channel   = State(initialValue: r.channel)
        _gender    = State(initialValue: r.gender)
        _custNum   = State(initialValue: r.customerNumber ?? "")
        _advisor   = State(initialValue: r.advisor ?? "")
    }

    var body: some View {
        Form {
            // 解析警告（置顶，橙色）
            if row.parseWarning != nil {
                Section {
                    let missing = row.parseWarning?
                        .components(separatedBy: "：").dropFirst().first?
                        .components(separatedBy: " ←").first ?? ""
                    Label("以下字段解析时缺失，请手动填写后保存：\(missing)",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Section(header: Text("基础信息")) {
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
                    TextField("客户编号（选填）", text: $custNum)
                }
                Picker("归属顾问", selection: $advisor) {
                    Text("未分配").tag("")
                    ForEach(store.settings.advisors, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                HStack {
                    Text("金额").frame(width: 44, alignment: .leading).foregroundColor(.secondary)
                    TextField("线索金额（可留空）", text: $amountStr)
                        .keyboardType(.decimalPad)
                    Text("元").foregroundColor(.secondary)
                }
                Text("线索金额仅用于客户资料和金额画像，不计入营业额。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Picker("渠道", selection: $channel) {
                    ForEach(channelOptions, id: \.self) { Text($0) }
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
        }
        .navigationTitle(name.isEmpty ? "补录信息" : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { applyChanges() }
                    .font(.headline)
            }
        }
    }

    private func applyChanges() {
        let trimName  = name.trimmingCharacters(in: .whitespaces)
        let trimPhone = phone.trimmingCharacters(in: .whitespaces)
        let trimAddr  = address.trimmingCharacters(in: .whitespaces)
        let trimNum   = custNum.trimmingCharacters(in: .whitespaces)

        row.name           = trimName.isEmpty ? "未知" : trimName
        row.phone          = trimPhone.isEmpty ? nil : trimPhone
        row.address        = trimAddr.isEmpty  ? nil : trimAddr
        let trimAmount     = amountStr.trimmingCharacters(in: .whitespacesAndNewlines)
        row.leadAmount     = trimAmount.isEmpty ? nil : Double(trimAmount)
        row.height         = Double(heightStr.trimmingCharacters(in: .whitespaces))
        row.weight         = Double(weightStr.trimmingCharacters(in: .whitespaces))
        row.age            = Int(ageStr.trimmingCharacters(in: .whitespaces))
        row.channel        = channel
        row.gender         = gender
        row.customerNumber = trimNum.isEmpty ? nil : trimNum
        let trimAdvisor     = advisor.trimmingCharacters(in: .whitespacesAndNewlines)
        row.advisor        = trimAdvisor.isEmpty ? nil : trimAdvisor

        // 更新 dataType：有电话且有地址 → 完整客户
        row.dataType = (row.phone != nil && row.address != nil) ? .fullCustomer : .ledgerEntry

        // 重新计算 parseWarning（字段全齐则清除警告）
        var missing: [String] = []
        if row.name == "未知"  { missing.append("姓名") }
        if row.phone == nil    { missing.append("电话") }
        if row.address == nil  { missing.append("地址") }
        if row.leadAmount == nil { missing.append("金额") }
        if row.height == nil   { missing.append("身高") }
        if row.weight == nil   { missing.append("体重") }
        if row.age == nil      { missing.append("年龄") }
        row.parseWarning = missing.isEmpty ? nil
            : "⚠ 缺失字段：\(missing.joined(separator: "、"))"

        dismiss()
    }
}

// MARK: - 同名同电话二次确认 Sheet（需求3）
struct DoubleCheckSheet: View {

    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) var dismiss

    let incomingRow: ParsedRow
    let existing:    Customer
    let onMerge:     () -> Void
    let onForceNew:  () -> Void

    @State private var previewCustomer: Customer? = nil

    var body: some View {
        NavigationView {
            List {

                // ── 本次录入内容 ──────────────────────────────
                Section(header: Text("本次录入内容")) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 38, height: 38)
                            .overlay(
                                Text(String(incomingRow.name.prefix(1)))
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(incomingRow.name).fontWeight(.semibold)
                            HStack(spacing: 6) {
                                Text(incomingRow.conversionType.rawValue)
                                    .font(.caption)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                                if let p = incomingRow.phone {
                                    Text(p).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        Spacer()
                        if let amt = incomingRow.leadAmount {
                            Text("¥\(Int(amt))")
                                .font(.title3).fontWeight(.bold).foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // ── 系统已有客户档案 ──────────────────────────
                Section(header: Text("系统中已有同名同电话客户")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color.blue.opacity(0.12))
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Text(String(existing.name.prefix(1)))
                                        .font(.subheadline).fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(existing.name).fontWeight(.semibold)
                                Text(existing.phone)
                                    .font(.caption).foregroundColor(.secondary)
                                HStack(spacing: 6) {
                                    if let h = existing.height { Text("\(Int(h))cm").font(.caption2).foregroundColor(.secondary) }
                                    if let w = existing.weight { Text("\(Int(w))kg").font(.caption2).foregroundColor(.secondary) }
                                    if existing.gender != "未知" { Text(existing.gender).font(.caption2).foregroundColor(.secondary) }
                                    Text("已转化 \(existing.conversions.count) 次")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                if let addr = existing.address {
                                    Text(String(addr.prefix(20)))
                                        .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            // 查看完整资料卡入口
                            Button {
                                previewCustomer = existing
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.title3)
                                    Text("完整资料")
                                        .font(.caption2)
                                }
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // ── 双通道选择按钮 ────────────────────────────
                Section(header: Text("请选择处理方式")) {
                    // 按钮A：合并追加
                    Button {
                        onMerge()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("合并 / 追加到该已有客户")
                                    .font(.subheadline).fontWeight(.semibold)
                                Text("金额和备注将累加到老档案中")
                                    .font(.caption).foregroundColor(.white.opacity(0.8))
                            }
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)

                    // 按钮B：强制新建
                    Button {
                        onForceNew()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.plus")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("作为独立新客户写入")
                                    .font(.subheadline).fontWeight(.semibold)
                                Text("生成全新 UUID，与上方客户完全独立")
                                    .font(.caption).foregroundColor(.orange.opacity(0.8))
                            }
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.12))
                        .foregroundColor(.orange)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("发现同名同电话客户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("跳过此条", role: .cancel) { onForceNew() }
                }
            }
        }
        // 查看完整资料卡（关闭后无缝返回本 Sheet）
        .sheet(item: $previewCustomer) { customer in
            NavigationView {
                CustomerDetailView(customer: customer)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("关闭") { previewCustomer = nil }
                        }
                    }
            }
            .environmentObject(store)
        }
    }
}

// MARK: - 粘贴拦截 UITextView（UIKit 桥接）

private class PasteInterceptTextView: UITextView {
    var onPasteCallback: ((String) -> Void)?

    // 长按菜单"粘贴"和 Cmd+V 均经过此方法
    override func paste(_ sender: Any?) {
        super.paste(sender)
        // asyncAfter 150ms：UITextView 内部文本插入偶尔跨越多个 RunLoop cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let t = self.text ?? ""
            guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            self.onPasteCallback?(t)
        }
    }
}

// MARK: - SwiftUI 包装：支持三重粘贴触发的 TextEditor

struct PasteAwareTextEditor: UIViewRepresentable {

    @Binding var text: String
    var onPaste: (String) -> Void   // 粘贴 / delta 检测 → 此回调

    func makeUIView(context: Context) -> UITextView {
        let tv = PasteInterceptTextView()
        tv.delegate           = context.coordinator
        tv.onPasteCallback    = onPaste
        tv.font               = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        tv.backgroundColor    = .clear
        tv.isScrollEnabled    = true
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // SwiftUI 每次重建 struct 后必须刷新回调，否则闭包变成悬空引用
        if let tv = uiView as? PasteInterceptTextView {
            tv.onPasteCallback = onPaste
        }
        // coordinator 是 class（长期存活），parent 是 value type（随 SwiftUI 重建）
        // 必须手动同步，否则 coordinator 持有过期的 View 副本
        context.coordinator.parent = self

        // 清空等外部写入操作同步到 UITextView
        if uiView.text != text { uiView.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PasteAwareTextEditor
        private var prevLength = 0      // 用于 delta 粘贴检测

        init(_ p: PasteAwareTextEditor) { parent = p }

        func textViewDidChange(_ tv: UITextView) {
            let newText = tv.text ?? ""
            let delta   = newText.count - prevLength
            prevLength  = newText.count
            parent.text = newText

            // 第2层保险：单次增量 ≥ 4 字符视为粘贴（逐字输入 delta 通常 = 1）
            // 与 paste(_:) override 可能重复触发，forceParse 幂等（结果相同）
            if delta >= 4 {
                parent.onPaste(newText)
            }
        }
    }
}
