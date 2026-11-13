// MARK: - DataStore.swift
// 本地数据仓库 — 内存 + JSON 持久化

import Foundation
import Combine

// MARK: - 顾问组织架构
enum AdvisorRole: String, Codable, CaseIterable, Identifiable {
    case leader = "组长"
    case member = "组员"

    var id: String { rawValue }
}

struct AdvisorProfile: Codable, Equatable, Identifiable {
    var name: String
    var role: AdvisorRole = .member
    var groupName: String = ""

    var id: String { name }
    var groupDisplay: String { groupName.isEmpty ? "未分组" : groupName }
}

// MARK: - AppSettings
class AppSettings: ObservableObject, Codable {

    @Published var leadUnitPrice:        Double   = 1200
    @Published var biometricLockEnabled: Bool     = false
    @Published var appPINEnabled:        Bool     = false
    @Published var appPIN:               String   = ""
    @Published var advisors:             [String] = []   // 服务顾问预设名单
    @Published var advisorGroups:         [String] = ["销售一组", "销售二组"]
    @Published var advisorProfiles:       [AdvisorProfile] = []
    // 仅从“暂未成交二次”待办中隐藏，不修改客户本身，也不影响任何统计。
    @Published var dismissedPendingSecondCustomerIDs: [UUID] = []
    // 关闭时渠道分析页完全移除营业额相关视图，不显示占位或隐藏提示。
    @Published var channelRevenueVisible: Bool = true

    enum CodingKeys: String, CodingKey {
        case leadUnitPrice, biometricLockEnabled, appPINEnabled, appPIN, advisors
        case advisorGroups, advisorProfiles, dismissedPendingSecondCustomerIDs, channelRevenueVisible
    }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        leadUnitPrice        = try c.decodeIfPresent(Double.self,   forKey: .leadUnitPrice)        ?? 1200
        biometricLockEnabled = try c.decodeIfPresent(Bool.self,     forKey: .biometricLockEnabled) ?? false
        appPINEnabled        = try c.decodeIfPresent(Bool.self,     forKey: .appPINEnabled)        ?? false
        appPIN               = try c.decodeIfPresent(String.self,   forKey: .appPIN)               ?? ""
        advisors             = try c.decodeIfPresent([String].self,  forKey: .advisors)             ?? []
        advisorGroups        = try c.decodeIfPresent([String].self, forKey: .advisorGroups)
            ?? ["销售一组", "销售二组"]
        advisorProfiles      = try c.decodeIfPresent([AdvisorProfile].self, forKey: .advisorProfiles)
            ?? advisors.map { AdvisorProfile(name: $0) }
        dismissedPendingSecondCustomerIDs = try c.decodeIfPresent(
            [UUID].self,
            forKey: .dismissedPendingSecondCustomerIDs
        ) ?? []
        channelRevenueVisible = try c.decodeIfPresent(Bool.self, forKey: .channelRevenueVisible) ?? true
        normalizeAdvisorProfiles()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(leadUnitPrice,        forKey: .leadUnitPrice)
        try c.encode(biometricLockEnabled, forKey: .biometricLockEnabled)
        try c.encode(appPINEnabled,        forKey: .appPINEnabled)
        try c.encode(appPIN,               forKey: .appPIN)
        try c.encode(advisors,             forKey: .advisors)
        try c.encode(advisorGroups,        forKey: .advisorGroups)
        try c.encode(advisorProfiles,      forKey: .advisorProfiles)
        try c.encode(dismissedPendingSecondCustomerIDs, forKey: .dismissedPendingSecondCustomerIDs)
        try c.encode(channelRevenueVisible, forKey: .channelRevenueVisible)
    }

    init() {}

    func profile(for name: String) -> AdvisorProfile {
        advisorProfiles.first(where: { $0.name == name }) ?? AdvisorProfile(name: name)
    }

    func updateProfile(name: String, role: AdvisorRole? = nil, groupName: String? = nil) {
        var profile = profile(for: name)
        if let role = role { profile.role = role }
        if let groupName = groupName { profile.groupName = groupName }
        if let index = advisorProfiles.firstIndex(where: { $0.name == name }) {
            advisorProfiles[index] = profile
        } else {
            advisorProfiles.append(profile)
        }
    }

    func normalizeAdvisorProfiles() {
        var seen = Set<String>()
        advisorProfiles = advisorProfiles.filter { profile in
            guard !profile.name.isEmpty, !seen.contains(profile.name) else { return false }
            seen.insert(profile.name)
            return true
        }
        for name in advisors where !seen.contains(name) {
            advisorProfiles.append(AdvisorProfile(name: name))
            seen.insert(name)
        }
        for group in advisorProfiles.map({ $0.groupName })
            where !group.isEmpty && !advisorGroups.contains(group) {
            advisorGroups.append(group)
        }
    }

    func dismissPendingSecondCustomer(_ id: UUID) {
        guard !dismissedPendingSecondCustomerIDs.contains(id) else { return }
        dismissedPendingSecondCustomerIDs.append(id)
    }

    func restorePendingSecondCustomer(_ id: UUID) {
        dismissedPendingSecondCustomerIDs.removeAll { $0 == id }
    }
}

// MARK: - DataStore
class DataStore: ObservableObject {

    private static let customersURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("customers_v2.json")
    private static let batchesURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("batches_v2.json")
    private static let settingsURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("settings.json")

    @Published var customers: [Customer]    = []
    @Published var batches:   [ImportBatch] = []
    @Published var settings:  AppSettings   = AppSettings() {
        didSet { observeSettingsChanges() }
    }

    // AppSettings 是嵌套的 ObservableObject。将它的变更转发给 DataStore，
    // 确保顾问角色/小组修改后，设置页和顾问看板立即同步刷新。
    private var settingsObservation: AnyCancellable?

    init() {
        load()
        observeSettingsChanges()
    }

    private func observeSettingsChanges() {
        settingsObservation = settings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: 持久化
    func load() {
        // 防御性解码：单个字段缺失时给默认值，而非整体失败清空数据
        customers = safeDecodeArray([Customer].self, from: DataStore.customersURL) ?? []
        batches   = safeDecodeArray([ImportBatch].self, from: DataStore.batchesURL) ?? []
        settings  = decode(AppSettings.self, from: DataStore.settingsURL) ?? AppSettings()
        migrateLegacyInvalidFollowUpTags()
        migrateConversionDatesToImportDate()
    }

    // 旧版本把“暂未成交二次”的“已作废”写进 Customer.followUpTag，
    // 曾导致客户被全局漏斗与顾问成交率排除。升级后迁移为列表级隐藏状态，
    // 并恢复客户原始统计资格；以清空旧标记保证迁移天然幂等。
    private func migrateLegacyInvalidFollowUpTags() {
        var dismissed = Set(settings.dismissedPendingSecondCustomerIDs)
        var changed = false
        for index in customers.indices where customers[index].followUpTag == .invalid {
            dismissed.insert(customers[index].id)
            customers[index].followUpTag = nil
            changed = true
        }
        guard changed else { return }
        settings.dismissedPendingSecondCustomerIDs = Array(dismissed)
        save()
    }

    // 一次性迁移：把历史 ConversionRecord.date 统一对齐到客户 importDate
    // 保证旧数据的营业额仍归属到客户建档当月，与修改前行为一致
    private func migrateConversionDatesToImportDate() {
        let key = "conversionDateMigrationV1Done"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for i in customers.indices {
            for j in customers[i].conversions.indices {
                customers[i].conversions[j].date = customers[i].importDate
            }
        }
        save()
        UserDefaults.standard.set(true, forKey: key)
    }

    func save() {
        encode(customers, to: DataStore.customersURL)
        encode(batches,   to: DataStore.batchesURL)
        encode(settings,  to: DataStore.settingsURL)
    }

    // MARK: 客户统计（仅计完整客户）
    var fullCustomerCount: Int {
        customers.filter { $0.dataType == .fullCustomer }.count
    }

    // MARK: 去重检测
    func findExisting(phone: String) -> Customer? {
        customers.first { $0.phone == phone }
    }

    // MARK: 去重处理
    @discardableResult
    func applyDuplicateResolution(
        existing: inout Customer,
        incoming: Customer,
        resolution: DuplicateResolution
    ) -> Bool {
        switch resolution {
        case .overwrite:
            if let idx = customers.firstIndex(where: { $0.phone == existing.phone }) {
                customers[idx] = incoming
                existing = incoming
            }
            save()
            return true
        case .skip:
            return false
        case .merge:
            if let idx = customers.firstIndex(where: { $0.phone == existing.phone }) {
                let newConversions = incoming.conversions.filter { newRec in
                    !customers[idx].conversions.contains(where: { $0.id == newRec.id })
                }
                customers[idx].conversions.append(contentsOf: newConversions)
                existing = customers[idx]
            }
            save()
            return true
        }
    }

    // MARK: 增删改
    func addCustomer(_ customer: Customer) {
        customers.append(customer)
        save()
    }

    func addBatch(_ batch: ImportBatch) {
        batches.append(batch)
        save()
    }

    func updateCustomer(_ customer: Customer) {
        if let idx = customers.firstIndex(where: { $0.id == customer.id }) {
            customers[idx] = customer
            save()
        }
    }

    // MARK: 月度/年度过滤

    /// 用于客户列表展示：仅完整客户
    func customers(inYear year: Int, month: Int) -> [Customer] {
        let cal = Calendar.current
        return customers.filter {
            guard $0.dataType == .fullCustomer else { return false }
            let comps = cal.dateComponents([.year, .month], from: $0.importDate)
            return comps.year == year && comps.month == month
        }
    }

    func customers(inYear year: Int) -> [Customer] {
        let cal = Calendar.current
        return customers.filter {
            guard $0.dataType == .fullCustomer else { return false }
            return cal.component(.year, from: $0.importDate) == year
        }
    }

    /// 用于营业额/ROI 统计：包含所有类型（fullCustomer + ledgerEntry）
    /// 流水录入的转化记录也需要计入营业额
    func allCustomers(inYear year: Int, month: Int) -> [Customer] {
        let cal = Calendar.current
        return customers.filter {
            let comps = cal.dateComponents([.year, .month], from: $0.importDate)
            return comps.year == year && comps.month == month
        }
    }

    func allCustomers(inYear year: Int) -> [Customer] {
        let cal = Calendar.current
        return customers.filter {
            cal.component(.year, from: $0.importDate) == year
        }
    }

    // MARK: 历史数据迁移 — 自动标记 costEnabled
    //
    // 规则：fullCustomer 中，满足以下任意条件的客户标记 costEnabled = true：
    //   · 有产品组合记录（productNote != nil）且线索金额 > 0
    //   · 或已有成交转化记录（conversions.count > 0 且有 amount > 0）
    // 不满足的标记 false。
    // 函数幂等：多次调用结果一致。返回被修改的条数。

    @discardableResult
    func migrateHistoricalData() -> Int {
        var changed = 0
        for i in customers.indices {
            guard customers[i].dataType == .fullCustomer else { continue }
            let c = customers[i]
            // 有产品/金额记录（成交转化 amount > 0）或有线索金额 → 纳入漏斗考核
            let hasPurchase  = c.validConversions.contains { $0.amount > 0 }
            let hasLeadPrice = (c.leadAmount ?? 0) > 0
            let shouldEnable = hasPurchase || hasLeadPrice
            if customers[i].costEnabled != shouldEnable {
                customers[i].costEnabled = shouldEnable
                changed += 1
            }
        }
        if changed > 0 { save() }
        return changed
    }

    // MARK: Codable 辅助
    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomicWrite)
    }

    /// 防御性数组解码：整体 decode 失败时逐条尝试，保住能解的数据
    /// 适用于模型升级（新增字段）后覆盖安装导致旧数据无法整体解析的场景
    private func safeDecodeArray<T: Decodable>(_ type: [T].Type, from url: URL) -> [T]? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        // 优先尝试整体解码（新版本正常路径）
        let decoder = JSONDecoder()
        if let result = try? decoder.decode([T].self, from: data) {
            return result
        }

        // 整体失败：逐条解码（兼容旧版本字段缺失）
        guard let rawArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        var recovered: [T] = []
        for item in rawArray {
            guard let itemData = try? JSONSerialization.data(withJSONObject: item) else { continue }
            if let obj = try? decoder.decode(T.self, from: itemData) {
                recovered.append(obj)
            }
        }
        // 只要恢复了至少一条就返回，防止全量失败
        return recovered.isEmpty ? nil : recovered
    }
}
