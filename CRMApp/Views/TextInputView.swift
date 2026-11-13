// MARK: - TextInputView.swift
// 手动流水录入界面（iOS 15 兼容）

import SwiftUI

// MARK: - 单一 Sheet 枚举，防止并发白屏
private enum LedgerSheet: Identifiable {
    case newCustomer(TextParseResult)
    case matchExisting(TextParseResult, [Customer])
    case batchDuplicate(name: String, results: [TextParseResult])

    var id: String {
        switch self {
        case .newCustomer(let r):        return "new_\(r.id)"
        case .matchExisting(let r, _):   return "match_\(r.id)"
        case .batchDuplicate(let n, _):  return "dup_\(n)"
        }
    }
}

struct TextInputView: View {

    @EnvironmentObject var store: DataStore
    @State private var inputText:    String = ""
    @State private var parseResults: [TextParseResult] = []
    @State private var parseErrors:  [TextParseError]  = []
    @State private var showPreview:  Bool = false
    @State private var showSaveToast: Bool = false
    @State private var toastMessage:  String = ""
    @FocusState private var editorFocused: Bool

    @State private var activeSheet:   LedgerSheet? = nil
    @State private var pendingQueue:  [TextParseResult] = []
    @State private var matchedCount:  Int = 0
    @State private var newBuiltCount: Int = 0
    @State private var revenueDate:   Date = Date()   // 营业额归属日期，默认今天

    // 顾问分配
    @State private var advisorMode:  Int    = 0   // 0=未分配 1=单人 2=双人各半
    @State private var advisor1:     String = ""
    @State private var advisor2:     String = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {

                    // ── 说明卡片 ──────────────────────────────────
                    VStack(alignment: .leading, spacing: 4) {
                        Text("流水录入").font(.headline)
                        Text("格式：姓名 状态 金额（此处金额计入营业额）")
                            .font(.caption).foregroundColor(.secondary)
                        Text("支持连续粘贴：严亚 新单 2260 朱忠惠 新单 2680 ...")
                            .font(.caption).foregroundColor(.secondary)
                        Text("库中无此客户时，系统引导你建立新档案")
                            .font(.caption2).foregroundColor(.blue)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // ── 批量默认顾问分配 ─────────────────────────
                    Text("批量默认业绩归属（解析后可逐单修改）")
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal)
                    AdvisorSplitPicker(mode: $advisorMode, advisor1: $advisor1, advisor2: $advisor2)
                        .environmentObject(store)

                    // ── 批量默认营业额归属日期 ────────────────────
                    HStack {
                        Text("默认开单日期").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        DatePicker("", selection: $revenueDate, displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // ── 输入框 ───────────────────────────────────
                    TextEditor(text: $inputText)
                        .focused($editorFocused)
                        .font(.body.monospaced())
                        .frame(minHeight: 160, maxHeight: 280)
                        .padding(8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)

                    // ── 操作按钮 ─────────────────────────────────
                    HStack(spacing: 12) {
                        Button("解析预览") {
                            editorFocused = false
                            let r = TextParser.parse(inputText)
                            let defaultSplits = makeAdvisorSplits()
                            parseResults = r.results.map { parsed in
                                var pending = parsed
                                pending.orderDate = revenueDate
                                pending.advisorSplits = defaultSplits
                                return pending
                            }
                            parseErrors  = r.errors
                            showPreview  = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("收起键盘") { editorFocused = false }
                            .buttonStyle(.bordered).tint(.secondary)

                        Button("清空") {
                            editorFocused = false
                            inputText    = ""
                            parseResults = []
                            parseErrors  = []
                            showPreview  = false
                        }
                        .buttonStyle(.bordered).tint(.red)
                    }
                    .padding(.horizontal)

                    // ── 解析预览区 ───────────────────────────────
                    if showPreview {

                        if !parseResults.isEmpty {
                            previewList
                        }

                        if !parseErrors.isEmpty {
                            errorList
                        }

                        if !parseResults.isEmpty {
                            saveButton
                        }
                    }

                    Spacer(minLength: 40)
                }
            }
            .onTapGesture { editorFocused = false }
            .navigationTitle("流水录入")
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .bottom) {
                if showSaveToast {
                    Text(toastMessage)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
        }
    }

    // MARK: ── 子视图拆分（减轻编译器类型推断负担）

    private var previewList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("解析成功（\(parseResults.count) 条，点击任一订单确认日期与业绩归属）")
                .font(.caption).foregroundColor(.secondary)
                .padding(.horizontal).padding(.top, 8)
            Divider()
            ForEach($parseResults) { $r in
                let matched: Customer? = {
                    if let num = r.customerNumber {
                        return store.customers.first { $0.customerNumber == num && $0.dataType == .fullCustomer }
                    }
                    return store.customers.first { $0.name == r.name && $0.dataType == .fullCustomer }
                }()
                let hasMatch = matched != nil
                NavigationLink(destination: LedgerPendingOrderEditView(result: $r).environmentObject(store)) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(r.customerNumber != nil
                                     ? "编号\(r.customerNumber!) · \(matched?.name ?? "未找到")"
                                     : r.name).fontWeight(.semibold)
                                Text(hasMatch ? "已匹配" : (r.customerNumber != nil ? "编号不存在" : "新客户"))
                                    .font(.caption2)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(hasMatch
                                        ? Color.green.opacity(0.15)
                                        : Color.blue.opacity(0.12))
                                    .foregroundColor(hasMatch ? .green : .blue)
                                    .cornerRadius(4)
                            }
                            Text(r.rawLine)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary).lineLimit(1)
                            HStack(spacing: 10) {
                                Label(Self.orderDateFormatter.string(from: r.orderDate), systemImage: "calendar")
                                Label(advisorSummary(r.advisorSplits), systemImage: "person.2")
                            }
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(r.conversionType.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(conversionColor(r.conversionType).opacity(0.15))
                                .foregroundColor(conversionColor(r.conversionType))
                                .clipShape(Capsule())
                            Text("¥\(Int(r.amount))")
                                .fontWeight(.semibold).foregroundColor(.green)
                            Text("点击确认").font(.caption2).foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal).padding(.vertical, 8)
                Divider()
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var errorList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("解析失败 (\(parseErrors.count) 行)")
                .font(.caption).foregroundColor(.red)
                .padding(.horizontal).padding(.top, 8)
            Divider()
            ForEach(parseErrors) { e in
                VStack(alignment: .leading, spacing: 2) {
                    Text("第 \(e.lineNumber) 行：\(e.rawLine)")
                        .font(.caption.monospaced())
                    Text(e.reason).font(.caption2).foregroundColor(.red)
                }
                .padding(.horizontal).padding(.vertical, 6)
                Divider()
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var saveButton: some View {
        Button { startSaveFlow() } label: {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("批量保存 \(parseResults.count) 条记录")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(14)
        }
        .padding(.horizontal)
    }

    // MARK: ── Sheet 内容
    @ViewBuilder
    private func sheetContent(_ sheet: LedgerSheet) -> some View {
        switch sheet {
        case .newCustomer(let result):
            NewCustomerFromLedgerSheet(
                result: result,
                onCreate: { num, confirmedResult in
                    activeSheet = nil
                    DispatchQueue.main.async {
                        commitNewCustomer(result: confirmedResult, customerNumber: num)
                        processNextSave()
                    }
                }
            )
            .environmentObject(store)

        case .matchExisting(let result, let candidates):
            LedgerMatchSheet(
                result:     result,
                candidates: candidates,
                onAppend: { target, confirmedResult in
                    activeSheet = nil
                    DispatchQueue.main.async {
                        appendToExisting(result: confirmedResult, target: target)
                        processNextSave()
                    }
                },
                onNewEntry: { confirmedResult in
                    activeSheet = .newCustomer(confirmedResult)
                }
            )
            .environmentObject(store)

        case .batchDuplicate(let name, let results):
            BatchDuplicateSheet(
                name:    name,
                results: results,
                onMerge: {
                    activeSheet = nil
                    DispatchQueue.main.async {
                        commitBatchMerge(name: name, results: results)
                        processNextSave()
                    }
                },
                onSeparate: {
                    activeSheet = nil
                    DispatchQueue.main.async {
                        pendingQueue = results + pendingQueue
                        processNextSave()
                    }
                }
            )
            .environmentObject(store)
        }
    }

    // MARK: ── 保存主流程
    private func startSaveFlow() {
        editorFocused   = false
        matchedCount    = 0
        newBuiltCount   = 0

        // 每一笔都必须依次确认客户、日期与业绩分配，不再绕过确认直接合并。
        pendingQueue = parseResults
        processNextSave()
    }

    private func processNextSave() {
        guard !pendingQueue.isEmpty else {
            finalizeSave()
            return
        }
        let result = pendingQueue.removeFirst()

        // 按编号查找优先，否则按姓名
        let candidates: [Customer]
        if let num = result.customerNumber {
            candidates = store.customers.filter {
                $0.customerNumber == num && $0.dataType == .fullCustomer
            }
        } else {
            candidates = store.customers.filter {
                !$0.name.isEmpty && $0.name == result.name && $0.dataType == .fullCustomer
            }
        }

        if candidates.isEmpty {
            if result.customerNumber != nil {
                // 编号不存在：直接提示，跳过建新客户（编号模式不自动建档）
                activeSheet = .newCustomer(result)
            } else {
                activeSheet = .newCustomer(result)
            }
        } else {
            activeSheet = .matchExisting(result, candidates)
        }
    }

    private func makeAdvisorSplits() -> [AdvisorSplit] {
        switch advisorMode {
        case 1 where !advisor1.isEmpty:
            return [AdvisorSplit(name: advisor1, ratio: 1.0)]
        case 2 where !advisor1.isEmpty && !advisor2.isEmpty && advisor1 != advisor2:
            return [AdvisorSplit(name: advisor1, ratio: 0.5),
                    AdvisorSplit(name: advisor2, ratio: 0.5)]
        default:
            return []
        }
    }

    private func commitNewCustomer(result: TextParseResult, customerNumber: String?) {
        let record = ConversionRecord(type: result.conversionType, amount: result.amount,
                                      date: result.orderDate, advisorSplits: result.advisorSplits)
        let numStr = customerNumber?.trimmingCharacters(in: .whitespaces)
        let c = Customer(
            name:           result.name,
            phone:          "待补全_\(UUID().uuidString.prefix(8))",
            customerNumber: (numStr?.isEmpty == false) ? numStr : nil,
            costEnabled:    false,   // 流水录入不计成本
            lineCost:       store.settings.leadUnitPrice,
            dataType:       .fullCustomer,
            importDate:     Date(),
            conversions:    [record]
        )
        store.customers.append(c)
        store.save()
        newBuiltCount += 1
    }

    private func appendToExisting(result: TextParseResult, target: Customer) {
        guard let idx = store.customers.firstIndex(where: { $0.id == target.id }) else { return }
        let record = ConversionRecord(type: result.conversionType, amount: result.amount,
                                      date: result.orderDate, advisorSplits: result.advisorSplits)
        store.customers[idx].conversions.append(record)
        store.save()
        matchedCount += 1
    }

    private func commitBatchMerge(name: String, results: [TextParseResult]) {
        let records = results.map { ConversionRecord(type: $0.conversionType, amount: $0.amount,
                                                     date: $0.orderDate, advisorSplits: $0.advisorSplits) }
        if let idx = store.customers.firstIndex(where: { $0.name == name && $0.dataType == .fullCustomer }) {
            store.customers[idx].conversions.append(contentsOf: records)
            store.save()
            matchedCount += results.count
        } else {
            let c = Customer(
                name:        name,
                phone:       "待补全_\(UUID().uuidString.prefix(8))",
                costEnabled: false,
                lineCost:    store.settings.leadUnitPrice,
                dataType:    .fullCustomer,
                importDate:  Date(),
                conversions: records
            )
            store.customers.append(c)
            store.save()
            newBuiltCount += 1
        }
    }

    private func finalizeSave() {
        parseResults = []
        parseErrors  = []
        inputText    = ""
        showPreview  = false
        activeSheet  = nil

        let total = matchedCount + newBuiltCount
        if newBuiltCount == 0 {
            toastMessage = "✅ 已关联 \(matchedCount) 条转化记录到已有客户"
        } else if matchedCount == 0 {
            toastMessage = "✅ 新建 \(newBuiltCount) 位客户档案并写入成交记录"
        } else {
            toastMessage = "✅ 关联 \(matchedCount) 条，新建 \(newBuiltCount) 位，共 \(total) 条"
        }
        withAnimation { showSaveToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showSaveToast = false }
        }
    }

    private func conversionColor(_ type: ConversionType) -> Color {
        switch type {
        case .newOrder: return .blue
        case .second:   return .green
        case .third:    return .orange
        case .fourth:   return .purple
        case .fifth:    return .red
        case .sixth:    return .indigo
        case .seventh:  return Color(red: 0, green: 0.5, blue: 0.5)
        case .eighth:   return Color(red: 0, green: 0.7, blue: 0.9)
        case .multiple: return Color(red: 0.6, green: 0.3, blue: 0.8)
        case .unknown:  return .gray
        }
    }

    private func advisorSummary(_ splits: [AdvisorSplit]) -> String {
        guard !splits.isEmpty else { return "未分配" }
        return splits.map { "\($0.name) \($0.ratioText)" }.joined(separator: " + ")
    }

    private static let orderDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()
}

// MARK: - 流水待导入订单编辑
struct LedgerPendingOrderEditView: View {
    @Binding var result: TextParseResult
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var customerNumber: String
    @State private var conversionType: ConversionType
    @State private var amountText: String
    @State private var orderDate: Date
    @State private var advisorMode: Int
    @State private var advisor1: String
    @State private var advisor2: String
    @State private var validationMessage = ""
    @State private var showValidationAlert = false

    private let conversionOptions: [ConversionType] = [
        .newOrder, .second, .third, .fourth, .fifth,
        .sixth, .seventh, .eighth, .multiple
    ]

    init(result: Binding<TextParseResult>) {
        _result = result
        let value = result.wrappedValue
        _name = State(initialValue: value.name)
        _customerNumber = State(initialValue: value.customerNumber ?? "")
        _conversionType = State(initialValue: value.conversionType)
        _amountText = State(initialValue: Self.amountString(value.amount))
        _orderDate = State(initialValue: value.orderDate)

        if value.advisorSplits.count >= 2 {
            _advisorMode = State(initialValue: 2)
            _advisor1 = State(initialValue: value.advisorSplits[0].name)
            _advisor2 = State(initialValue: value.advisorSplits[1].name)
        } else if let split = value.advisorSplits.first {
            _advisorMode = State(initialValue: 1)
            _advisor1 = State(initialValue: split.name)
            _advisor2 = State(initialValue: "")
        } else {
            _advisorMode = State(initialValue: 0)
            _advisor1 = State(initialValue: "")
            _advisor2 = State(initialValue: "")
        }
    }

    var body: some View {
        Form {
            Section(header: Text("订单信息"), footer: Text("修改只作用于这笔待导入订单，点击右上角保存后返回预览。")) {
                TextField("客户姓名", text: $name)
                TextField("客户编号（选填）", text: $customerNumber)
                    .keyboardType(.numberPad)

                Picker("成交类型", selection: $conversionType) {
                    ForEach(conversionOptions, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                HStack {
                    Text("业绩金额")
                    Spacer()
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("元").foregroundColor(.secondary)
                }

                DatePicker("开单日期", selection: $orderDate, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }

            Section(header: Text("本单业绩分享"), footer: Text("选择双人各半后，这笔订单的业绩会按 50% / 50% 分配给两位顾问。")) {
                AdvisorSplitPicker(mode: $advisorMode, advisor1: $advisor1, advisor2: $advisor2)
                    .environmentObject(store)
            }
        }
        .navigationTitle("确认单笔订单")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { saveChanges() }
            }
        }
        .alert("无法保存", isPresented: $showValidationAlert) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(validationMessage)
        }
    }

    private func saveChanges() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAmount = amountText
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")

        guard !cleanName.isEmpty else {
            showError("客户姓名不能为空。")
            return
        }
        guard let amount = Double(normalizedAmount), amount >= 0 else {
            showError("请输入正确的业绩金额。")
            return
        }

        let splits: [AdvisorSplit]
        switch advisorMode {
        case 1:
            guard !advisor1.isEmpty else {
                showError("请选择归属顾问。")
                return
            }
            splits = [AdvisorSplit(name: advisor1, ratio: 1.0)]
        case 2:
            guard !advisor1.isEmpty, !advisor2.isEmpty else {
                showError("请选择两位参与业绩分享的顾问。")
                return
            }
            guard advisor1 != advisor2 else {
                showError("业绩分享需要选择两位不同的顾问。")
                return
            }
            splits = [AdvisorSplit(name: advisor1, ratio: 0.5),
                      AdvisorSplit(name: advisor2, ratio: 0.5)]
        default:
            splits = []
        }

        let cleanNumber = customerNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        result.name = cleanName
        result.customerNumber = cleanNumber.isEmpty ? nil : cleanNumber
        result.conversionType = conversionType
        result.amount = amount
        result.orderDate = orderDate
        result.advisorSplits = splits
        dismiss()
    }

    private func showError(_ message: String) {
        validationMessage = message
        showValidationAlert = true
    }

    private static func amountString(_ amount: Double) -> String {
        amount.rounded() == amount ? String(Int(amount)) : String(amount)
    }
}

// MARK: - 场景A：新建客户档案面板
struct NewCustomerFromLedgerSheet: View {

    @EnvironmentObject var store: DataStore
    let result:   TextParseResult
    let onCreate: (String?, TextParseResult) -> Void

    @State private var customerNumber: String = ""
    @State private var orderDate: Date
    @State private var advisorMode: Int
    @State private var advisor1: String
    @State private var advisor2: String

    init(result: TextParseResult, onCreate: @escaping (String?, TextParseResult) -> Void) {
        self.result = result
        self.onCreate = onCreate
        _customerNumber = State(initialValue: result.customerNumber ?? "")
        _orderDate = State(initialValue: result.orderDate)
        let assignment = Self.assignmentState(from: result.advisorSplits)
        _advisorMode = State(initialValue: assignment.mode)
        _advisor1 = State(initialValue: assignment.advisor1)
        _advisor2 = State(initialValue: assignment.advisor2)
    }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("本次录入内容")) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 38, height: 38)
                            .overlay(
                                Text(String(result.name.prefix(1)))
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.name).fontWeight(.semibold)
                            Text(result.conversionType.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue).cornerRadius(4)
                        }
                        Spacer()
                        Text("¥\(Int(result.amount))")
                            .font(.title3).fontWeight(.bold).foregroundColor(.green)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill").foregroundColor(.blue)
                            Text("正在为新客户「\(result.name)」建立档案")
                                .font(.subheadline).fontWeight(.semibold)
                        }
                        Text("未找到同名已有客户，请填写客户编号（可跳过留空）。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("第 1 项：匹配客户")) {
                    Label("客户库中没有匹配记录，将新建「\(result.name)」", systemImage: "person.crop.circle.badge.plus")
                        .foregroundColor(.orange)
                    Text("确认创建后，这笔订单会写入该新客户档案。")
                        .font(.caption).foregroundColor(.secondary)
                }

                Section(header: Text("客户编号（选填）")) {
                    HStack {
                        Text("编号").foregroundColor(.secondary).frame(width: 44, alignment: .leading)
                        TextField("如：8888（不填则留空）", text: $customerNumber)
                    }
                }

                Section(header: Text("第 2 项：确认开单日期")) {
                    DatePicker("开单日期", selection: $orderDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                }

                Section(header: Text("第 3 项：确认业绩分配"), footer: Text(assignmentFooter)) {
                    if store.settings.advisors.isEmpty {
                        Label("请先在顾问设置中添加员工", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    } else {
                        AdvisorSplitPicker(
                            mode: $advisorMode,
                            advisor1: $advisor1,
                            advisor2: $advisor2,
                            allowsUnassigned: true
                        )
                        .environmentObject(store)
                    }
                }

                Section {
                    Button {
                        onCreate(customerNumber, confirmedResult)
                    } label: {
                        HStack {
                            Spacer()
                            let num = customerNumber.trimmingCharacters(in: .whitespaces)
                            Label(num.isEmpty ? "确认新建并保存订单" : "确认新建编号 \(num) 并保存",
                                  systemImage: "person.crop.circle.badge.plus")
                                .foregroundColor(.white).font(.body.weight(.semibold))
                            Spacer()
                        }
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("确认订单与新客户")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }

    private var assignmentFooter: String {
        if advisorMode == 2 && !advisor1.isEmpty && advisor1 == advisor2 {
            return "两位顾问相同时会暂存为未分配，可在客户详情后期补录。"
        }
        return advisorMode == 0
            ? "当前暂存为未分配，保存后可在客户详情补录。"
            : "可选择单人 100% 或两位顾问各 50%，也可以暂不分配。"
    }

    private var confirmedResult: TextParseResult {
        var updated = result
        updated.orderDate = orderDate
        updated.advisorSplits = Self.makeSplits(mode: advisorMode, advisor1: advisor1, advisor2: advisor2)
        let number = customerNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.customerNumber = number.isEmpty ? nil : number
        return updated
    }

    private static func assignmentState(from splits: [AdvisorSplit]) -> (mode: Int, advisor1: String, advisor2: String) {
        if splits.count >= 2 { return (2, splits[0].name, splits[1].name) }
        if let split = splits.first { return (1, split.name, "") }
        return (0, "", "")
    }

    private static func makeSplits(mode: Int, advisor1: String, advisor2: String) -> [AdvisorSplit] {
        if mode == 1 && !advisor1.isEmpty {
            return [AdvisorSplit(name: advisor1, ratio: 1.0)]
        }
        if mode == 2 && !advisor1.isEmpty && !advisor2.isEmpty && advisor1 != advisor2 {
            return [AdvisorSplit(name: advisor1, ratio: 0.5), AdvisorSplit(name: advisor2, ratio: 0.5)]
        }
        return []
    }
}

// MARK: - 场景B：同名客户绑定确认面板
struct LedgerMatchSheet: View {

    @EnvironmentObject var store: DataStore

    let result:     TextParseResult
    let candidates: [Customer]
    let onAppend:   (Customer, TextParseResult) -> Void
    let onNewEntry: (TextParseResult) -> Void

    @State private var previewCustomer: Customer? = nil
    @State private var orderDate: Date
    @State private var advisorMode: Int
    @State private var advisor1: String
    @State private var advisor2: String
    @State private var selectedCustomerID: UUID? = nil
    @State private var previousAssignment: [AdvisorSplit] = []
    @State private var previousAssignmentCustomerName = ""
    @State private var showPreviousAssignmentPrompt = false

    init(result: TextParseResult,
         candidates: [Customer],
         onAppend: @escaping (Customer, TextParseResult) -> Void,
         onNewEntry: @escaping (TextParseResult) -> Void) {
        self.result = result
        self.candidates = candidates
        self.onAppend = onAppend
        self.onNewEntry = onNewEntry
        _orderDate = State(initialValue: result.orderDate)
        let assignment = Self.assignmentState(from: result.advisorSplits)
        _advisorMode = State(initialValue: assignment.mode)
        _advisor1 = State(initialValue: assignment.advisor1)
        _advisor2 = State(initialValue: assignment.advisor2)
    }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("本次录入内容")) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 38, height: 38)
                            .overlay(
                                Text(String(result.name.prefix(1)))
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.name).fontWeight(.semibold)
                            Text(result.conversionType.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12))
                                .foregroundColor(.orange).cornerRadius(4)
                        }
                        Spacer()
                        Text("¥\(Int(result.amount))")
                            .font(.title3).fontWeight(.bold).foregroundColor(.green)
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("第 1 项：选择匹配客户（必选）")) {
                    ForEach(candidates) { candidate in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color.blue.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Text(String(candidate.name.prefix(1)))
                                            .font(.subheadline).fontWeight(.semibold)
                                            .foregroundColor(.blue)
                                    )
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 4) {
                                        Text(candidate.name).fontWeight(.semibold)
                                        Text("（\(candidate.customerNumber.map { "编号 \($0)" } ?? "未录入编号")）")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                    Text(candidate.phone)
                                        .font(.caption).foregroundColor(.secondary)
                                    HStack(spacing: 6) {
                                        if let h = candidate.height {
                                            Text("\(Int(h))cm").font(.caption2).foregroundColor(.secondary)
                                        }
                                        if let w = candidate.weight {
                                            Text("\(Int(w))kg").font(.caption2).foregroundColor(.secondary)
                                        }
                                        Text("转化\(candidate.conversions.count)次")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                    if let addr = candidate.address {
                                        Text(String(addr.prefix(15)))
                                            .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Button {
                                    previewCustomer = candidate
                                } label: {
                                    VStack(spacing: 2) {
                                        Image(systemName: "doc.text.magnifyingglass").font(.title3)
                                        Text("完整资料").font(.caption2)
                                    }
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8).padding(.vertical, 6)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                selectCandidate(candidate)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: selectedCustomerID == candidate.id
                                          ? "checkmark.circle.fill" : "circle")
                                    Text(selectedCustomerID == candidate.id ? "已选择此客户" : "选择此客户")
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(selectedCustomerID == candidate.id
                                            ? Color.blue.opacity(0.12)
                                            : Color(.secondarySystemGroupedBackground))
                                .foregroundColor(.blue).cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.blue.opacity(selectedCustomerID == candidate.id ? 0.8 : 0.4), lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section(header: Text("第 2 项：确认开单日期")) {
                    DatePicker("开单日期", selection: $orderDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                }

                Section(header: Text("第 3 项：确认业绩分配"), footer: Text(assignmentFooter)) {
                    if store.settings.advisors.isEmpty {
                        Label("请先在顾问设置中添加员工", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    } else {
                        AdvisorSplitPicker(
                            mode: $advisorMode,
                            advisor1: $advisor1,
                            advisor2: $advisor2,
                            allowsUnassigned: true
                        )
                        .environmentObject(store)
                    }
                }

                Section {
                    Button {
                        guard let selected = selectedCustomer else { return }
                        onAppend(selected, confirmedResult)
                    } label: {
                        HStack {
                            Spacer()
                            Label("三项已确认，保存这笔订单", systemImage: "checkmark.circle.fill")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding()
                    .background(canCommit ? Color.blue : Color.gray)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCommit)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)

                    Button { onNewEntry(confirmedResult) } label: {
                        HStack {
                            Spacer()
                            Label("暂不匹配，建立独立档案后期补录", systemImage: "person.badge.plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.orange)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("确认单笔订单")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
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
        .alert("沿用上次业绩分配？", isPresented: $showPreviousAssignmentPrompt) {
            Button("沿用上次分配") {
                applyPreviousAssignment()
            }
            Button("本单重新分配", role: .cancel) { }
        } message: {
            Text("\(previousAssignmentCustomerName) 上次分配：\(previousAssignmentText)")
        }
    }

    private func selectCandidate(_ candidate: Customer) {
        selectedCustomerID = candidate.id

        guard let latest = candidate.conversions
            .filter({ !$0.isVoided && !$0.advisorSplits.isEmpty })
            .sorted(by: { $0.date > $1.date })
            .first else {
            previousAssignment = []
            return
        }

        let validSplits = latest.advisorSplits.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !validSplits.isEmpty else {
            previousAssignment = []
            return
        }

        previousAssignment = Array(validSplits.prefix(2))
        previousAssignmentCustomerName = candidate.name
        showPreviousAssignmentPrompt = true
    }

    private var previousAssignmentText: String {
        previousAssignment
            .map { "\($0.name) \($0.ratioText)" }
            .joined(separator: " + ")
    }

    private func applyPreviousAssignment() {
        guard let first = previousAssignment.first else { return }
        if previousAssignment.count >= 2 {
            advisorMode = 2
            advisor1 = first.name
            advisor2 = previousAssignment[1].name
        } else {
            advisorMode = 1
            advisor1 = first.name
            advisor2 = ""
        }
    }

    private var selectedCustomer: Customer? {
        guard let selectedCustomerID else { return nil }
        return candidates.first { $0.id == selectedCustomerID }
    }

    private var canCommit: Bool {
        selectedCustomer != nil
    }

    private var assignmentFooter: String {
        if advisorMode == 2 && !advisor1.isEmpty && advisor1 == advisor2 {
            return "请选择两位不同的顾问。"
        }
        return advisorMode == 0
            ? "当前暂存为未分配，保存后可在客户详情补录。"
            : "可选择单人 100% 或两位顾问各 50%，也可以暂不分配。"
    }

    private var confirmedResult: TextParseResult {
        var updated = result
        updated.orderDate = orderDate
        updated.advisorSplits = Self.makeSplits(mode: advisorMode, advisor1: advisor1, advisor2: advisor2)
        return updated
    }

    private static func assignmentState(from splits: [AdvisorSplit]) -> (mode: Int, advisor1: String, advisor2: String) {
        if splits.count >= 2 { return (2, splits[0].name, splits[1].name) }
        if let split = splits.first { return (1, split.name, "") }
        return (0, "", "")
    }

    private static func makeSplits(mode: Int, advisor1: String, advisor2: String) -> [AdvisorSplit] {
        if mode == 1 && !advisor1.isEmpty {
            return [AdvisorSplit(name: advisor1, ratio: 1.0)]
        }
        if mode == 2 && !advisor1.isEmpty && !advisor2.isEmpty && advisor1 != advisor2 {
            return [AdvisorSplit(name: advisor1, ratio: 0.5), AdvisorSplit(name: advisor2, ratio: 0.5)]
        }
        return []
    }
}

// MARK: - 场景C：批内同名合并面板
struct BatchDuplicateSheet: View {

    @Environment(\.dismiss) var dismiss
    let name:       String
    let results:    [TextParseResult]
    let onMerge:    () -> Void
    let onSeparate: () -> Void

    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.2.fill").foregroundColor(.orange)
                            Text("检测到「\(name)」有 \(results.count) 笔成交记录")
                                .font(.subheadline).fontWeight(.semibold)
                        }
                        Text("是否将以下记录合并为同一客户的多次连续订购？")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("本批次「\(name)」的所有记录")) {
                    ForEach(results) { r in
                        HStack {
                            Text(r.conversionType.rawValue).font(.subheadline).fontWeight(.semibold)
                            Spacer()
                            Text("¥\(Int(r.amount))").foregroundColor(.green).fontWeight(.bold)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section {
                    Button(action: onMerge) {
                        HStack {
                            Spacer()
                            Label("合并为同一客户的 \(results.count) 次订购", systemImage: "arrow.triangle.merge")
                                .foregroundColor(.white).font(.body.weight(.semibold))
                            Spacer()
                        }
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)

                    Button(action: onSeparate) {
                        HStack {
                            Spacer()
                            Label("各自独立新建（\(results.count) 个同名新客户）", systemImage: "person.badge.plus")
                                .foregroundColor(.orange).font(.body.weight(.semibold))
                            Spacer()
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("同名成交记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("合并处理", role: .cancel) { onMerge() }
                }
            }
        }
    }
}
