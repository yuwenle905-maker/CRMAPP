// MARK: - Customer.swift
// 核心数据模型

import Foundation

// MARK: 客户记录类型
enum CustomerDataType: String, Codable {
    case fullCustomer  // 完整客户：含姓名+电话+地址，计入客户总数
    case ledgerEntry   // 流水/跟进记录：仅含姓名+转化类型+金额，不新增客户
}

// MARK: 转化状态
enum ConversionType: String, Codable, CaseIterable {
    case newOrder = "新单"
    case second   = "二次"
    case third    = "三次"
    case fourth   = "四次"
    case fifth    = "五次"
    case sixth    = "六次"
    case seventh  = "七次"
    case eighth   = "八次"
    case multiple = "多次"
    case unknown  = "未知"
}

// MARK: 客户跟进标注
enum CustomerTag: String, Codable, CaseIterable {
    case highValue  = "高价值"
    case lost       = "已失去价值"
    case invalid    = "已作废"

    var color: String {
        switch self {
        case .highValue: return "gold"
        case .lost:      return "gray"
        case .invalid:   return "red"
        }
    }
}

// MARK: 去重处理策略
enum DuplicateResolution {
    case overwrite
    case skip
    case merge
}

// MARK: 顾问业绩归属（支持多人分成）
struct AdvisorSplit: Codable, Equatable {
    var name:  String
    var ratio: Double   // 1.0 = 100%，0.5 = 各半

    var ratioText: String { ratio == 1.0 ? "100%" : String(format: "%.0f%%", ratio * 100) }
}

// MARK: 转化/消费记录（生命周期时间轴）
struct ConversionRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var type: ConversionType
    var amount: Double
    var date: Date
    var productNote: String?
    var note: String?
    var advisorSplits: [AdvisorSplit] = []
    // 未签收、退款等无效成交保留原始记录，但不参与成交率、营业额和顾问业绩。
    var isVoided: Bool = false

    init(type: ConversionType, amount: Double,
         date: Date = Date(), productNote: String? = nil, note: String? = nil,
         advisorSplits: [AdvisorSplit] = [], isVoided: Bool = false) {
        self.type          = type
        self.amount        = amount
        self.date          = date
        self.productNote   = productNote
        self.note          = note
        self.advisorSplits = advisorSplits
        self.isVoided      = isVoided
    }

    // 旧数据没有 advisorSplits 字段，用 decodeIfPresent 兼容
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decodeIfPresent(UUID.self,           forKey: .id)            ?? UUID()
        type          = try c.decode(ConversionType.self,          forKey: .type)
        amount        = try c.decode(Double.self,                  forKey: .amount)
        date          = try c.decode(Date.self,                    forKey: .date)
        productNote   = try c.decodeIfPresent(String.self,         forKey: .productNote)
        note          = try c.decodeIfPresent(String.self,         forKey: .note)
        advisorSplits = try c.decodeIfPresent([AdvisorSplit].self, forKey: .advisorSplits) ?? []
        isVoided      = try c.decodeIfPresent(Bool.self,            forKey: .isVoided)      ?? false
    }

    var countsInStatistics: Bool { !isVoided }
}

// MARK: 主客户模型
struct Customer: Identifiable, Codable, Equatable {

    var id: UUID = UUID()
    var dataType: CustomerDataType = .fullCustomer

    // 基础资料
    var name: String
    var phone: String
    var address: String?
    var age: Int?
    var height: Double?
    var weight: Double?
    var gender: String = "未知"
    var customerNumber: String?   // 手动录入的客户编号，系统不自动生成
    var costEnabled: Bool = false  // 是否纳入成本计算。流水录入默认false，智能导入默认true

    // 线索金额（智能导入时提取，仅用于画像统计，不计入营业额）
    var leadAmount: Double?

    // 历史单价留存（需求2）
    // 入库时自动固化当时的 AppSettings.leadUnitPrice，之后改价不影响此值
    var lineCost: Double

    // 来源
    var importBatchID: UUID?
    var importDate: Date

    // 标签
    var tags: [String] = []

    // 跟进标注（用于"暂未成交"客户的人工标记）
    var followUpTag: CustomerTag? = nil

    // 来源渠道（v7：智能粘贴自动检测；旧数据 nil 展示为"自然流量"，Codable 向后兼容）
    var channel: String? = nil

    // 当前服务顾问：可随客户转交而变化。
    var advisor: String? = nil

    // 首次派发时的 ROI 成本归属：nil 表示旧数据尚未锁定，空字符串表示离职后不归属任何个人。
    // 与当前服务顾问分离，避免二次转交把历史资料成本计入接手人的 ROI。
    var roiAdvisor: String? = nil

    // 转化/消费记录（手动录入，金额计入营业额）
    var conversions: [ConversionRecord] = []

    // MARK: 计算属性

    /// 渠道展示名（nil → 旧数据默认"自然流量"）
    var channelDisplay: String { channel ?? "自然流量" }

    /// 顾问展示名；兼容 nil、空字符串和只含空格的历史数据。
    var advisorDisplay: String {
        let value = advisor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "未分配" : value
    }

    /// 个人 ROI 的资料成本归属。显式空字符串代表不归属任何在职顾问。
    var roiAdvisorName: String? {
        if let locked = roiAdvisor {
            let value = locked.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        let legacy = advisor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return legacy.isEmpty ? nil : legacy
    }

    /// 营业额 = 手动录入转化记录之和（不含 leadAmount）
    var totalRevenue: Double {
        validConversions.reduce(0) { $0 + $1.amount }
    }

    /// 统计统一只读取有效成交；作废记录仍保留在时间轴供追溯和恢复。
    var validConversions: [ConversionRecord] {
        conversions.filter(\.countsInStatistics)
    }

    var importDayKey: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: importDate)
    }

    var importDayDisplay: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "M月d日"
        return fmt.string(from: importDate)
    }

    /// 转交客户时只改变当前服务人；首次派发人一旦确定，ROI 成本归属不再跟随转移。
    /// 已有但未显式分配顾问的历史订单会固化到转交前的服务人，避免历史业绩被转走。
    mutating func reassignAdvisor(to newAdvisor: String?) {
        let oldName = advisor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let newName = newAdvisor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if roiAdvisor == nil {
            if !oldName.isEmpty {
                roiAdvisor = oldName
            } else if !newName.isEmpty {
                roiAdvisor = newName
            }
        }

        if !oldName.isEmpty && oldName != newName {
            for index in conversions.indices where conversions[index].advisorSplits.isEmpty {
                conversions[index].advisorSplits = [AdvisorSplit(name: oldName, ratio: 1.0)]
            }
        }

        advisor = newName.isEmpty ? nil : newName
    }

    /// 删除当前服务员工时解除服务归属；只有该员工也是首次派发人时才清空 ROI 成本归属。
    /// 客户、订单、其他原始派发人的 ROI 归属、全局成本和营业额均完整保留。
    mutating func detachDeletedAdvisor() {
        let oldName = advisor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let removesROIAttribution = roiAdvisorName == oldName
        if !oldName.isEmpty {
            for index in conversions.indices where conversions[index].advisorSplits.isEmpty {
                conversions[index].advisorSplits = [AdvisorSplit(name: oldName, ratio: 1.0)]
            }
        }
        advisor = nil
        if removesROIAttribution {
            roiAdvisor = ""
        }
    }

    init(name: String, phone: String,
         address: String?        = nil,
         age: Int?               = nil,
         height: Double?         = nil,
         weight: Double?         = nil,
         gender: String          = "未知",
         customerNumber: String? = nil,
         costEnabled: Bool       = false,
         leadAmount: Double?     = nil,
         lineCost: Double        = 1200,
         dataType: CustomerDataType = .fullCustomer,
         importBatchID: UUID?    = nil,
         importDate: Date        = Date(),
         conversions: [ConversionRecord] = [],
         channel: String?        = nil,
         advisor: String?        = nil,
         roiAdvisor: String?     = nil) {
        self.name           = name
        self.phone          = phone
        self.address        = address
        self.age            = age
        self.height         = height
        self.weight         = weight
        self.gender         = gender
        self.customerNumber = customerNumber
        self.costEnabled    = costEnabled
        self.leadAmount     = leadAmount
        self.lineCost       = lineCost
        self.dataType       = dataType
        self.importBatchID  = importBatchID
        self.importDate     = importDate
        self.conversions    = conversions
        self.channel        = channel
        self.advisor        = advisor
        self.roiAdvisor     = roiAdvisor ?? advisor
    }
}

// MARK: 导入批次
struct ImportBatch: Identifiable, Codable {
    var id: UUID = UUID()
    var source: String
    var importDate: Date
    var recordCount: Int
    var fullCustomerCount: Int

    var displayHeader: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "M月d日 HH:mm"
        return "\(fmt.string(from: importDate))  |  \(recordCount) 条"
    }

    var yearKey:  String { "\(Calendar.current.component(.year, from: importDate))年" }
    var monthKey: String {
        let c = Calendar.current.dateComponents([.year, .month], from: importDate)
        return "\(c.year!)年\(c.month!)月"
    }
}
