// MARK: - SmartPasteParser.swift
// 智能粘贴解析引擎 v9
//
// 支持格式：姓名 电话 地址 产品组合 金额 身高+体重+年龄(可选) 物流单号 备注
//
// v9 体征提取重构（令牌分词器）：
//   extractValue(from:keyword:) — 找关键词锚点，截取到下一关键词或结尾的片段
//   extractFirstNumber(from:)  — 从片段提取首个数字（跳过冒号/空格前缀）
//   tokenizeBio(from:)         — 三关键词分词主函数，任意顺序均可正确识别
//   Trace Log: [解析器] 找到关键词: XXX，提取数值: YYY
//   parseWarning 非 nil → UI 强制橙色（isManualReviewRequired 语义）

import Foundation

// MARK: 解析结果
struct ParsedRow: Identifiable {
    let id       = UUID()
    let rawLine:  String
    let rowIndex: Int

    var name:           String
    var phone:          String?
    var address:        String?
    var leadAmount:     Double?
    var conversionType: ConversionType
    var age:            Int?
    var height:         Double?
    var weight:         Double?
    var gender:         String = "女"
    var productNote:    String?
    var dataType:       CustomerDataType
    var importDate:     Date? = nil      // Excel 日期列；缺失时入库使用当前时间
    var customerNumber: String? = nil   // 导入时可选填；留空表示后期补录
    var parseWarning:   String? = nil   // 调试：非 nil 时列出缺失字段，nil 表示解析完整
    var channel:        String  = "食谱"  // v7：渠道检测结果
    var advisor:        String? = nil   // 预览页可为单条客户指定顾问；nil 时沿用整批顾问

    var isValid:        Bool { !name.isEmpty }
    var isFullCustomer: Bool { dataType == .fullCustomer && phone != nil }
}

// MARK: 解析失败行
struct ParseFailedRow: Identifiable {
    let id         = UUID()
    let lineNumber: Int
    let rawLine:    String
    let reason:     String
}

// MARK: 解析字段缺失错误（调试模式）
enum ParseFieldError: Error, LocalizedError {
    case missingFields(_ fields: [String], rawLine: String)

    var errorDescription: String? {
        switch self {
        case .missingFields(let fields, let raw):
            return "解析缺失字段：\(fields.joined(separator: "、")) ← 原文：\(raw)"
        }
    }
}

// MARK: 主解析器
enum SmartPasteParser {

    // ── 正则（预编译）────────────────────────────────────────
    private static let phoneRx = try! NSRegularExpression(
        pattern: #"(?<![0-9])1[3-9]\d{9}(?![0-9])"#
    )
    private static let amountRx = try! NSRegularExpression(
        pattern: #"(?<![0-9A-Za-z])(\d{2,6}(?:\.\d{1,2})?)(?:\s*[元￥])?(?![0-9])"#
    )
    // 关键词直接匹配（\s* 为零次，即紧挨关键词的数字也可捕获）
    private static let heightRx = try! NSRegularExpression(
        pattern: #"身高\s*[：:]?\s*(\d{2,3}(?:\.\d+)?)|(\d{2,3}(?:\.\d+)?)\s*(?:cm|厘米)"#,
        options: .caseInsensitive
    )
    private static let weightRx = try! NSRegularExpression(
        pattern: #"体重\s*[：:]?\s*(\d{2,3}(?:\.\d+)?)|(\d{2,3}(?:\.\d+)?)\s*(?:kg|斤|公斤)"#,
        options: .caseInsensitive
    )
    private static let ageRx = try! NSRegularExpression(
        pattern: #"年龄\s*[：:]?\s*(\d{1,3})|(\d{1,3})\s*岁"#
    )
    private static let genderRx = try! NSRegularExpression(
        pattern: #"性别[：:]\s*([男女])|(性别)\s*([男女])"#
    )
    // 紧凑体征：165+55+28（身高+体重+年龄），三段区间验证防误匹配
    private static let bioCompactRx = try! NSRegularExpression(
        pattern: #"(\d{2,3}(?:\.\d+)?)\s*[+＋]\s*(\d{2,3}(?:\.\d+)?)\s*[+＋]\s*(\d{1,3}(?:\.\d+)?)"#
    )
    // 关键词+数字格式（v8）：(身高|体重|年龄)(\d+)，全局扫描，任意顺序任意位置
    private static let bioKeywordRx = try! NSRegularExpression(
        pattern: #"(身高|体重|年龄)\s*[：:]?\s*(\d{1,3}(?:\.\d+)?)"#
    )
    // v9 令牌分词器：从片段中找到第一个数字（不锚定开头，兼容"约165""共165cm"等前缀）
    private static let firstNumberRx = try! NSRegularExpression(
        pattern: #"(\d{1,3}(?:\.\d+)?)"#
    )
    // Excel 日期格式：8.01 / 8月1日 / 2026-08-01
    private static let spreadsheetDateRx = try! NSRegularExpression(
        pattern: #"^(?:(\d{4})\s*[年./-]\s*)?(\d{1,2})\s*(?:月|[./-])\s*(\d{1,2})\s*日?$"#
    )
    // 物流单号（SF 顺丰为重点，兼容主流快递前缀）
    private static let trackingRx = try! NSRegularExpression(
        pattern: #"(?:SF|YT|ZT|JD|EMS|UC|BS|DB|STO|ANE|HTKY|ZJS|DEPPON|BEST)\d{8,20}|(?:顺丰|圆通|韵达|中通|申通|邮政|百世|德邦|安能|天天)\d{8,20}"#,
        options: .caseInsensitive
    )
    // 带标签产品（在 cleanLabels 前运行，捕获含/不含"+"的产品名）
    private static let productLabelRx = try! NSRegularExpression(
        pattern: #"产品\s*[：:]\s*([^\s，,；;。\n\t]{1,30})"#
    )
    // 自由格式产品组合（含 + 的组合词）
    private static let productRx = try! NSRegularExpression(
        pattern: #"[一-龥\w]+(?:\d*[+＋][一-龥\w]+\d*)+"#
    )

    // MARK: 体征关键词定义（v9 令牌分词器用）
    private static let bioKeywordDefs: [(keyword: String, field: String)] = [
        ("身高", "height"),
        ("体重", "weight"),
        ("年龄", "age"),
    ]

    // MARK: 渠道关键词字典（v7）
    // 按优先级顺序，先匹配先返回；"推荐"放最后防止截断"老客推荐"
    static let channelKeywordMap: [(keyword: String, channel: String)] = [
        ("问答",      "问答"),
        ("小红书",    "小红书"),
        ("直播间",    "直播"),    // 显式别名，防止"直播间"未被"直播"子串匹配
        ("直播",      "直播"),
        ("朋友圈",    "朋友圈"),
        ("食谱",      "食谱"),
        ("抖音",      "抖音"),
        ("视频号",    "视频号"),
        ("微博",      "微博"),
        ("老客推荐",  "老客推荐"),
        ("转介绍",    "转介绍"),
        ("推荐",      "转介绍"),
        ("广告",      "广告投流"),
    ]

    // 标签白名单
    private static let labelPrefixes = [
        "产品", "今天", "信息", "快递", "备注", "地址", "姓名",
        "电话", "手机", "单号", "金额", "收货", "收件", "寄件"
    ]

    // 转化类型优先级表
    private static let convKwTable: [(keys: [String], type: ConversionType)] = [
        (["八次","8次","第八"],              .eighth),
        (["七次","7次","第七"],              .seventh),
        (["六次","6次","第六"],              .sixth),
        (["五次","5次","第五"],              .fifth),
        (["四次","4次","第四"],              .fourth),
        (["三次","3次","第三"],              .third),
        (["二次","2次","第二","复购"],        .second),
        (["新单","首单","一次","1次","新"],   .newOrder),
    ]

    // 地址特征词
    private static let addrKeywords = [
        "省","市","区","县","路","街","镇","乡","村","号","楼","室","单元","巷","弄",
        "广东","广西","海南","上海","江苏","浙江","安徽","福建","江西","山东","台湾",
        "北京","天津","河北","山西","内蒙古","内蒙","辽宁","吉林","黑龙江",
        "河南","湖北","湖南","重庆","四川","贵州","云南","西藏",
        "陕西","甘肃","甘州","张掖","青海","宁夏","新疆","香港","澳门",
        "广州","深圳","珠海","佛山","东莞","中山","惠州",
        "南京","杭州","苏州","宁波","无锡","武汉","成都","西安","沈阳","长春","哈尔滨"
    ]

    // MARK: ─── 预处理（v6 新增）────────────────────────────────
    //
    // 进入正则解析前的文本标准化：
    //   1. 中文标点 → 空格（冒号保留，供标签检测使用）
    //   2. 身高/体重/年龄/性别 关键词前若无分隔则自动补入空格
    //   3. 压缩多余空格
    //
    // 标记为 static（非 private）：可在单元测试 / 调试环境中独立调用

    static func preprocessLine(_ s: String) -> String {
        var t = s

        // 1. 中文标点 → 空格（保留 ：冒号 供后续标签解析）
        let punctMap: [String] = [
            "，","。","！","？","；",
            "\u{201C}", "\u{201D}",   // " "
            "\u{2018}", "\u{2019}",   // ' '
            "【","】","《","》","、","…","—","～","·","〜","｜","「","」","『","』"
        ]
        for ch in punctMap {
            t = t.replacingOccurrences(of: ch, with: " ")
        }

        // 2. 关键词前若紧挨其他字符则插入空格
        //    示例："张三身高165" → "张三 身高165"
        for kw in ["身高", "体重", "年龄", "性别"] {
            var result = ""
            var idx    = t.startIndex
            while idx < t.endIndex, let kwRange = t.range(of: kw, range: idx..<t.endIndex) {
                let seg = t[idx..<kwRange.lowerBound]
                result += seg
                if let last = seg.last, !last.isWhitespace { result += " " }
                result += kw
                idx = kwRange.upperBound
            }
            result += t[idx...]
            t = result
        }

        // 3. 压缩多余空格
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t.trimmingCharacters(in: .whitespaces)
    }

    // MARK: ─── 公开统一入口：parseCustomerLine（v6）──────────
    //
    // 单行/块文本 → ParsedRow，永远返回结果
    // · 缺失字段（身高/体重/年龄）置 nil，不影响整行成功
    // · 姓名无法识别时回退"未知"
    // · row.parseWarning 非 nil 时说明存在缺失，UI 可据此提示用户

    static func parseCustomerLine(_ line: String, index: Int = 0) -> ParsedRow {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("[解析原始文本] \(line.prefix(120))")

        let raw = line.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else {
            print("[解析] 空行，跳过")
            return ParsedRow(rawLine: raw, rowIndex: index, name: "未知",
                            phone: nil, address: nil, leadAmount: nil,
                            conversionType: .newOrder, age: nil, height: nil,
                            weight: nil, productNote: nil, dataType: .ledgerEntry,
                            parseWarning: "⚠ 缺失字段：姓名、电话、地址、身高、体重、年龄 ← （空行）")
        }

        // 制表符多列格式优先（Excel 粘贴）
        if raw.contains("\t") {
            print("[格式检测] 发现制表符 → 进入 parseTabRow")
            if let row = parseTabRow(raw, rawOriginal: raw, index: index) {
                print("[解析结果-Tab] 姓名: \(row.name), 渠道: \(row.channel), 身高: \(row.height.map { "\(Int($0))cm" } ?? "nil"), 体重: \(row.weight.map { "\(Int($0))kg" } ?? "nil"), 年龄: \(row.age.map { "\($0)岁" } ?? "nil")")
                return row
            }
            print("[格式检测] parseTabRow 返回 nil，回退普通解析")
        } else {
            print("[格式检测] 普通文本格式 → 进入 parseBlockCore")
        }

        // 预处理：标准化标点 + 补全关键词前空格
        let preprocessed = preprocessLine(raw)
        print("[预处理后] \(preprocessed.prefix(120))")

        // 在清洗标签前提取带标签产品名（cleanLabels 会抹去"产品："上下文）
        let labeledProduct = extractLabeledProduct(from: preprocessed)

        // 清洗标签后进入核心解析
        let cleaned = cleanLabels(preprocessed)
        print("[标签清洗后] \(cleaned.prefix(120))")
        var row     = parseBlockCore(cleaned, rawOriginal: raw, index: index)

        // 带标签产品优先于自动检测的"+"组合
        if row.productNote == nil, let lp = labeledProduct {
            row.productNote = lp
        }

        print("[解析结果] 姓名: \(row.name), 电话: \(row.phone ?? "nil"), 渠道: \(row.channel), 身高: \(row.height.map { "\(Int($0))cm" } ?? "nil"), 体重: \(row.weight.map { "\(Int($0))kg" } ?? "nil"), 年龄: \(row.age.map { "\($0)岁" } ?? "nil")")
        if let w = row.parseWarning { print("[⚠️ 警告] \(w)") }

        return row
    }

    // MARK: ─── 调试模式：parseCustomerLineStrict ─────────────
    //
    // 与 parseCustomerLine 解析逻辑完全相同；
    // 若结果中存在任何缺失字段（含身高/体重/年龄）则抛出 ParseFieldError，
    // 错误信息包含具体缺失字段列表 + 原始文本，便于快速定位识别阻断位置。
    //
    // 用法（调试时）：
    //   do {
    //       let row = try SmartPasteParser.parseCustomerLineStrict(line)
    //   } catch let e as ParseFieldError {
    //       print(e.localizedDescription)   // 解析缺失字段：身高、体重 ← 原文：…
    //   }

    static func parseCustomerLineStrict(_ line: String, index: Int = 0) throws -> ParsedRow {
        let row = parseCustomerLine(line, index: index)
        if let warning = row.parseWarning {
            // 从 warning 还原字段列表："⚠ 缺失字段：身高、体重 ← 原文"
            let afterColon = warning.components(separatedBy: "：").dropFirst().first ?? ""
            let fieldsPart = afterColon.components(separatedBy: " ←").first ?? ""
            let fields     = fieldsPart.components(separatedBy: "、").filter { !$0.isEmpty }
            throw ParseFieldError.missingFields(fields, rawLine: line)
        }
        return row
    }

    // MARK: ─── 多行批量入口 ──────────────────────────────────

    static func parse(_ text: String) -> (rows: [ParsedRow], failed: [ParseFailedRow]) {
        let step1  = normalizeWhitespace(text)
        let blocks = splitIntoCustomerBlocks(step1)

        var rows:   [ParsedRow]      = []
        var failed: [ParseFailedRow] = []

        for (i, block) in blocks.enumerated() {
            // 粘贴 Excel 表头时直接跳过，避免标题进入待处理队列。
            if isSpreadsheetHeaderRow(block) {
                print("[Excel表头] 已跳过：\(block)")
                continue
            }

            let row = parseCustomerLine(block, index: i)
            // 姓名/电话/地址三项全无才归入失败
            if row.name == "未知" && row.phone == nil && row.address == nil {
                let reason = row.parseWarning
                    ?? "无法提取有效字段（需包含姓名，建议附上电话和地址）"
                failed.append(ParseFailedRow(lineNumber: i + 1, rawLine: block, reason: reason))
            } else {
                rows.append(row)
            }
        }
        return (rows, failed)
    }

    // MARK: ─── 制表符多列行专用解析器 ───────────────────────

    private static func parseTabRow(_ raw: String, rawOriginal: String, index: Int) -> ParsedRow? {
        let cols = raw.components(separatedBy: "\t").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard cols.count >= 2 else { return nil }

        var phoneIdx: Int?
        var extractedPhone: String?
        for (i, col) in cols.enumerated() {
            if let phone = firstMatch(phoneRx, in: col) {
                phoneIdx = i
                extractedPhone = phone
                break
            }
        }
        guard let pIdx = phoneIdx, pIdx >= 1 else { return nil }

        let name = cols[0..<pIdx].last { !$0.isEmpty } ?? ""
        guard !name.isEmpty else { return nil }
        let importDate = cols[0..<pIdx].compactMap { parseSpreadsheetDate($0) }.first

        var addrIdx: Int?
        var extractedAddress: String?
        if pIdx + 1 < cols.count {
            for i in (pIdx + 1)..<cols.count {
                if addrKeywords.contains(where: { cols[i].contains($0) }) {
                    addrIdx = i
                    extractedAddress = cols[i]
                    break
                }
            }
            if addrIdx == nil,
               let fallback = ((pIdx + 1)..<cols.count).first(where: { !cols[$0].isEmpty }) {
                addrIdx = fallback
                extractedAddress = cols[fallback]
            }
        }

        let dataStart = min((addrIdx ?? pIdx) + 1, cols.count)
        var numericCols: [(idx: Int, val: Double)] = []
        if dataStart < cols.count {
            for i in dataStart..<cols.count {
                let col = cols[i]
                guard !col.isEmpty,
                      col.allSatisfy({ $0.isNumber || $0 == "." }),
                      let value = Double(col) else { continue }
                numericCols.append((i, value))
            }
        }

        var leadAmount: Double?
        var height: Double?
        var weight: Double?
        var age: Int?
        var amountIdx: Int?
        var heightIdx: Int?
        var weightIdx: Int?
        var ageIdx: Int?

        // 标准表格：产品、金额、身高、体重、年龄。按连续列组识别，不受前方产品文字影响。
        if numericCols.count >= 4 {
            for start in 0...(numericCols.count - 4) {
                let amountCol = numericCols[start]
                let heightCol = numericCols[start + 1]
                let weightCol = numericCols[start + 2]
                let ageCol = numericCols[start + 3]
                guard heightCol.idx == amountCol.idx + 1,
                      weightCol.idx == heightCol.idx + 1,
                      ageCol.idx == weightCol.idx + 1,
                      (50...99999).contains(amountCol.val),
                      (100...220).contains(heightCol.val),
                      (30...200).contains(weightCol.val),
                      (1...99).contains(ageCol.val) else { continue }
                leadAmount = amountCol.val
                height = heightCol.val
                weight = weightCol.val
                age = Int(ageCol.val)
                amountIdx = amountCol.idx
                heightIdx = heightCol.idx
                weightIdx = weightCol.idx
                ageIdx = ageCol.idx
                break
            }
        }

        // 兼容没有金额列、仅有身高/体重/年龄三列的旧表格。
        if height == nil, numericCols.count >= 3 {
            for start in 0...(numericCols.count - 3) {
                let heightCol = numericCols[start]
                let weightCol = numericCols[start + 1]
                let ageCol = numericCols[start + 2]
                guard weightCol.idx == heightCol.idx + 1,
                      ageCol.idx == weightCol.idx + 1,
                      (100...220).contains(heightCol.val),
                      (30...200).contains(weightCol.val),
                      (1...99).contains(ageCol.val) else { continue }
                height = heightCol.val
                weight = weightCol.val
                age = Int(ageCol.val)
                heightIdx = heightCol.idx
                weightIdx = weightCol.idx
                ageIdx = ageCol.idx
                break
            }
        }

        // 兼容“身高 162 / 体重 155 / 年龄 39”等带关键词的表格。
        if height == nil || weight == nil || age == nil {
            let bio = tokenizeBio(from: cols.joined(separator: " "))
            if height == nil { height = bio.height }
            if weight == nil { weight = bio.weight }
            if age == nil { age = bio.age }
        }

        // 金额兜底：从纯数字列中排除已识别的体征列后取第一个合理金额。
        if leadAmount == nil {
            let bodyIndexes = Set([heightIdx, weightIdx, ageIdx].compactMap { $0 })
            if let candidate = numericCols.first(where: {
                !bodyIndexes.contains($0.idx) && (50...99999).contains($0.val)
            }) {
                leadAmount = candidate.val
                amountIdx = candidate.idx
            }
        }

        var gender = "女"
        if dataStart < cols.count {
            for i in dataStart..<cols.count where cols[i] == "男" || cols[i] == "女" {
                gender = cols[i]
                break
            }
        }

        var productNote: String?
        let productEnd = min(amountIdx ?? heightIdx ?? cols.count, cols.count)
        if dataStart < productEnd {
            productNote = cols[dataStart..<productEnd].first { !$0.isEmpty }
        }

        let joined = cols.joined(separator: " ")
        let (convType, _) = detectConvType(in: joined)
        let (detectedChannel, _) = extractChannel(from: rawOriginal)
        let dataType: CustomerDataType = (extractedPhone != nil && extractedAddress != nil)
            ? .fullCustomer : .ledgerEntry

        var missing: [String] = []
        if name.isEmpty { missing.append("姓名") }
        if extractedPhone == nil { missing.append("电话") }
        if extractedAddress == nil { missing.append("地址") }
        if leadAmount == nil { missing.append("金额") }
        if height == nil { missing.append("身高") }
        if weight == nil { missing.append("体重") }
        if age == nil { missing.append("年龄") }
        let warning: String? = missing.isEmpty ? nil
            : "⚠ 缺失字段：\(missing.joined(separator: "、")) ← \(rawOriginal.prefix(40))"

        print("[Excel解析] 日期: \(importDate.map { String(describing: $0) } ?? "nil"), 姓名: \(name), 金额: \(leadAmount.map { String($0) } ?? "nil"), 身高: \(height.map { String($0) } ?? "nil"), 体重: \(weight.map { String($0) } ?? "nil"), 年龄: \(age.map { String($0) } ?? "nil"), 渠道: \(detectedChannel)")

        return ParsedRow(rawLine: rawOriginal, rowIndex: index, name: name,
                         phone: extractedPhone, address: extractedAddress,
                         leadAmount: leadAmount, conversionType: convType,
                         age: age, height: height, weight: weight,
                         gender: gender, productNote: productNote, dataType: dataType,
                         importDate: importDate, parseWarning: warning,
                         channel: detectedChannel)
    }

    private static func isSpreadsheetHeaderRow(_ raw: String) -> Bool {
        guard raw.contains("\t") else { return false }
        let cols = raw.components(separatedBy: "\t").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cols.contains("姓名") && cols.contains(where: { $0.contains("电话") })
    }

    private static func parseSpreadsheetDate(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = spreadsheetDateRx.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ) else { return nil }

        func integer(at group: Int) -> Int? {
            guard match.range(at: group).location != NSNotFound,
                  let range = Range(match.range(at: group), in: text) else { return nil }
            return Int(text[range])
        }

        let calendar = Calendar.current
        let year = integer(at: 1) ?? calendar.component(.year, from: Date())
        guard let month = integer(at: 2), let day = integer(at: 3) else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = TimeZone.current
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }
    // MARK: ─── 文本整体标准化 ────────────────────────────────

    private static func normalizeWhitespace(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r",   with: "\n")
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2003}", with: " ")
    }

    // MARK: ─── 客户块切分 ─────────────────────────────────────

    private static func splitIntoCustomerBlocks(_ text: String) -> [String] {
        let rawLines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var blocks:       [String] = []
        var currentLines: [String] = []

        for line in rawLines {
            if line.isEmpty {
                if !currentLines.isEmpty {
                    blocks.append(currentLines.joined(separator: "\n"))
                    currentLines = []
                }
                continue
            }
            let lineHasPhone  = containsPhone(line)
            let accumHasPhone = currentLines.contains { containsPhone($0) }
            let isLabelLine   = !line.contains("\t") && labelPrefixes.contains {
                line.hasPrefix($0 + "：") || line.hasPrefix($0 + ":")
            }
            if lineHasPhone && accumHasPhone && !isLabelLine {
                blocks.append(currentLines.joined(separator: "\n"))
                currentLines = [line]
            } else {
                currentLines.append(line)
            }
        }
        if !currentLines.isEmpty { blocks.append(currentLines.joined(separator: "\n")) }

        if blocks.count == 1 && text.contains("\n") {
            let fallback   = rawLines.filter { !$0.isEmpty }
            let phoneLines = fallback.filter { containsPhone($0) }
            if fallback.count > 1 && phoneLines.count > 1 {
                return fallback.filter { containsPhone($0) }
            }
        }
        return blocks.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func containsPhone(_ s: String) -> Bool {
        phoneRx.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    // MARK: ─── 标签清洗 ──────────────────────────────────────

    private static func cleanLabels(_ block: String) -> String {
        var s = block.replacingOccurrences(of: "\n", with: " ")
                     .replacingOccurrences(of: "\t", with: " ")
        s = s.replacingOccurrences(of: "，", with: " ")
        for prefix in labelPrefixes {
            s = s.replacingOccurrences(of: prefix + "：", with: " ")
            s = s.replacingOccurrences(of: prefix + ":",  with: " ")
        }
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: ─── 核心块解析（永远返回 ParsedRow，附调试警告）──

    private static func parseBlockCore(_ s: String, rawOriginal: String, index: Int) -> ParsedRow {
        var remaining = s.trimmingCharacters(in: .whitespaces)

        // 1. 物流单号
        let tracking  = firstMatch(trackingRx, in: remaining)
        remaining     = removePattern(trackingRx, from: remaining)

        // 2. 手机号（11位，以1开头）
        let phone = firstMatch(phoneRx, in: remaining)
        remaining = removePattern(phoneRx, from: remaining)

        // 3. 体征（v9 令牌分词器）：三级匹配，任意顺序，位置无关
        //    ① + 分隔紧凑格式（165+55+28）
        //    ② 关键词令牌分词器（按锚点分段，extractValue + extractFirstNumber）
        //    ③ 单位后缀兜底（160cm / 60kg / 30岁）
        var height: Double? = nil
        var weight: Double? = nil
        var age:    Int?    = nil

        if let bio = extractBioCompact(from: remaining) {
            height = bio.height; weight = bio.weight; age = bio.age
            remaining = removePattern(bioCompactRx, from: remaining)
            print("[解析器] 紧凑格式匹配：身高\(Int(bio.height)) 体重\(Int(bio.weight)) 年龄\(bio.age)")
        }

        // 主力：关键词令牌分词器（任意顺序）
        print("[体征提取] 传入令牌分词器的文本: \(remaining.prefix(80))")
        let bioTok = tokenizeBio(from: remaining)
        if height == nil { height = bioTok.height }
        if weight == nil { weight = bioTok.weight }
        if age    == nil { age    = bioTok.age }
        remaining = removePattern(bioKeywordRx, from: remaining)

        // 单位后缀兜底（160cm / 60kg / 30岁）
        if height == nil {
            if let h = extractNumeric(heightRx, from: remaining, range: 100...220) {
                height = h
                print("[解析器] 单位后缀兜底 身高: \(Int(h))cm")
            } else {
                print("[解析器] 身高：所有策略均未匹配 ← \(remaining.prefix(40))")
            }
        }
        if weight == nil {
            if let w = extractNumeric(weightRx, from: remaining, range: 30...200) {
                weight = w
                print("[解析器] 单位后缀兜底 体重: \(Int(w))kg")
            } else {
                print("[解析器] 体重：所有策略均未匹配 ← \(remaining.prefix(40))")
            }
        }
        if age == nil {
            if let a = extractNumericInt(ageRx, from: remaining, range: 1...99) {
                age = a
                print("[解析器] 单位后缀兜底 年龄: \(a)岁")
            } else {
                print("[解析器] 年龄：所有策略均未匹配 ← \(remaining.prefix(40))")
            }
        }
        remaining = removePattern(heightRx, from: remaining)
        remaining = removePattern(weightRx, from: remaining)
        remaining = removePattern(ageRx,    from: remaining)

        // 4. 性别
        let gender = extractGender(from: remaining) ?? "女"
        remaining  = removePattern(genderRx, from: remaining)

        // 5. 产品组合；无产品时将物流单号写入备注
        let product: String? = firstMatch(productRx, in: remaining)
            ?? tracking.map { "单号:\($0)" }

        // 6. 金额
        let amount = extractBestAmount(from: remaining)

        // 7. 转化类型
        let (convType, convKw) = detectConvType(in: remaining)

        // 8. 地址
        let (address, rest) = extractAddrAndRest(from: remaining, removeKw: convKw)

        // 9. 姓名：有电话时以电话为锚点取电话前首词（不依赖空格）；
        //          无电话时从剩余 token 中取首个短词；空串回退"未知"
        let rawName: String = {
            if let ph = phone {
                return extractNameByPhoneAnchor(from: s, phone: ph)
            }
            return extractName(from: rest, removeKw: convKw)
        }()
        let name = rawName.isEmpty ? "未知" : rawName

        // 10. 渠道检测（从原文尾部 50 字符优先匹配，退而全文搜索）
        //     检测到的关键词同时从 remaining 中清除，防止混入产品备注
        let (detectedChannel, channelKw) = extractChannel(from: rawOriginal)
        if let kw = channelKw {
            remaining = remaining
                .replacingOccurrences(of: kw, with: " ")
                .trimmingCharacters(in: .whitespaces)
        }

        // 11. 构建调试警告（记录所有缺失字段 + 原始文本前40字）
        var missing: [String] = []
        if name   == "未知" { missing.append("姓名") }
        if phone  == nil   { missing.append("电话") }
        if address == nil  { missing.append("地址") }
        if height  == nil  { missing.append("身高") }
        if weight  == nil  { missing.append("体重") }
        if age     == nil  { missing.append("年龄") }
        let warning: String? = missing.isEmpty ? nil
            : "⚠ 缺失字段：\(missing.joined(separator: "、")) ← \(rawOriginal.prefix(40))"

        let dataType: CustomerDataType = (phone != nil && address != nil) ? .fullCustomer : .ledgerEntry

        return ParsedRow(rawLine: rawOriginal, rowIndex: index, name: name,
                        phone: phone, address: address, leadAmount: amount,
                        conversionType: convType, age: age, height: height,
                        weight: weight, gender: gender, productNote: product,
                        dataType: dataType, parseWarning: warning,
                        channel: detectedChannel)
    }

    // MARK: ─── 辅助：以电话为锚点提取姓名（v6 新增）──────────
    //
    // 姓名 = 电话号码前的首个有效词（不依赖空格位置）
    // 若找不到电话则回退 extractName

    private static func extractNameByPhoneAnchor(from s: String, phone: String) -> String {
        guard let phoneRange = s.range(of: phone) else {
            return extractName(from: s, removeKw: nil)
        }
        let beforePhone = String(s[s.startIndex..<phoneRange.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let tokens = beforePhone
            .components(separatedBy: .whitespaces)
            .map    { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { !$0.allSatisfy { $0.isNumber || $0 == "." } }
        return tokens.filter { $0.count >= 1 && $0.count <= 8 }.first ?? tokens.first ?? ""
    }

    // MARK: ─── 辅助：带标签产品提取 ──────────────────────────

    private static func extractLabeledProduct(from s: String) -> String? {
        let ns = NSRange(s.startIndex..., in: s)
        guard let m = productLabelRx.firstMatch(in: s, range: ns),
              let r = Range(m.range(at: 1), in: s) else { return nil }
        let v = String(s[r]).trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }

    // MARK: ─── 辅助：紧凑体征解析 ────────────────────────────

    private static func extractBioCompact(from s: String) -> (height: Double, weight: Double, age: Int)? {
        let ns = NSRange(s.startIndex..., in: s)
        guard let m  = bioCompactRx.firstMatch(in: s, range: ns),
              let r1 = Range(m.range(at: 1), in: s),
              let r2 = Range(m.range(at: 2), in: s),
              let r3 = Range(m.range(at: 3), in: s),
              let h  = Double(s[r1]), let w = Double(s[r2]), let a = Double(s[r3])
        else { return nil }
        guard (100...220).contains(h), (30...200).contains(w), (1...99).contains(a) else { return nil }
        return (h, w, Int(a))
    }

    // MARK: ─── v9 令牌分词器：三函数体征提取 ──────────────────
    //
    // 原理：以关键词（身高/体重/年龄）为锚点，截取锚点→下一锚点之间的文本片段，
    // 再从片段中取首个数字。彻底不依赖顺序，无论"年龄40身高160"还是"身高160年龄40"均可识别。

    /// 提取 keyword 后的文本片段（截至下一个体征关键词或结尾）
    /// e.g. tokenizeBio 对 "身高165体重60年龄30" 中的 "体重" 调用时，返回 "60年龄30" 的前半段 "60"
    static func extractValue(from text: String, keyword: String) -> String? {
        guard let kwRange = text.range(of: keyword) else { return nil }
        let afterKw = text[kwRange.upperBound...]
        // 找到距离最近的下一个体征关键词，作为截断点
        var cutEnd = afterKw.endIndex
        for (nextKw, _) in bioKeywordDefs where nextKw != keyword {
            if let r = afterKw.range(of: nextKw), r.lowerBound < cutEnd {
                cutEnd = r.lowerBound
            }
        }
        return String(afterKw[..<cutEnd])
    }

    /// 从片段中提取首个数字（允许前置冒号/空格）
    private static func extractFirstNumber(from segment: String) -> Double? {
        let ns = NSRange(segment.startIndex..., in: segment)
        guard let m = firstNumberRx.firstMatch(in: segment, range: ns),
              let r = Range(m.range(at: 1), in: segment) else { return nil }
        return Double(segment[r])
    }

    /// 令牌分词器主函数：对每个体征关键词分别定位并提取数值
    private static func tokenizeBio(from text: String) -> (height: Double?, weight: Double?, age: Int?) {
        var height: Double? = nil
        var weight: Double? = nil
        var age:    Int?    = nil

        for (kw, field) in bioKeywordDefs {
            guard let segment = extractValue(from: text, keyword: kw) else {
                print("[解析器] 找到关键词: \(kw)，提取数值: 未找到关键词")
                continue
            }
            guard let num = extractFirstNumber(from: segment) else {
                print("[解析器] 找到关键词: \(kw)，提取数值: 无（片段=\"\(segment.prefix(20))\"）")
                continue
            }
            print("[解析器] 找到关键词: \(kw)，提取数值: \(num)")
            switch field {
            case "height":
                if (100...220).contains(num) { height = num }
                else { print("[解析器] 身高 \(Int(num)) 超出范围 100-220，已忽略") }
            case "weight":
                if (30...200).contains(num) { weight = num }
                else { print("[解析器] 体重 \(Int(num)) 超出范围 30-200，已忽略") }
            case "age":
                let a = Int(num)
                if (1...99).contains(a) { age = a }
                else { print("[解析器] 年龄 \(a) 超出范围 1-99，已忽略") }
            default: break
            }
        }
        return (height, weight, age)
    }

    // MARK: ─── 辅助方法 ──────────────────────────────────────

    private static func extractBestAmount(from s: String) -> Double? {
        let range   = NSRange(s.startIndex..., in: s)
        let matches = amountRx.matches(in: s, range: range)
        let candidates: [Double] = matches.compactMap { m in
            guard let r = Range(m.range(at: 1), in: s) else { return nil }
            return Double(s[r])
        }
        return candidates.filter { $0 >= 50 && $0 <= 99999 }.max() ?? candidates.first
    }

    private static func detectConvType(in s: String) -> (ConversionType, String?) {
        for entry in convKwTable {
            for kw in entry.keys where s.contains(kw) { return (entry.type, kw) }
        }
        return (.newOrder, nil)
    }

    private static func extractGender(from s: String) -> String? {
        let ns = NSRange(s.startIndex..., in: s)
        guard let m = genderRx.firstMatch(in: s, range: ns) else { return nil }
        for i in 1..<m.numberOfRanges {
            guard let r = Range(m.range(at: i), in: s) else { continue }
            let v = String(s[r])
            if v == "男" || v == "女" { return v }
        }
        return nil
    }

    private static func extractAddrAndRest(from s: String,
                                            removeKw: String?) -> (address: String?, rest: String) {
        var tokens = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if let kw = removeKw {
            tokens = tokens.map { $0.replacingOccurrences(of: kw, with: "") }.filter { !$0.isEmpty }
        }
        tokens = tokens.filter { !$0.allSatisfy { $0.isNumber || $0 == "." } }
        var addrParts: [String] = []
        var rest:      [String] = []
        for tok in tokens {
            if tok.count >= 2 && addrKeywords.contains(where: { tok.contains($0) }) {
                addrParts.append(tok)
            } else {
                rest.append(tok)
            }
        }
        return (addrParts.isEmpty ? nil : addrParts.joined(), rest.joined(separator: " "))
    }

    private static func extractName(from rest: String, removeKw: String?) -> String {
        var tokens = rest.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if let kw = removeKw { tokens = tokens.filter { !$0.contains(kw) } }
        tokens = tokens.filter { !$0.allSatisfy { $0.isNumber || $0 == "." } }
        return tokens.filter { $0.count >= 1 && $0.count <= 8 }.first ?? tokens.first ?? ""
    }

    private static func removePattern(_ rx: NSRegularExpression, from s: String) -> String {
        rx.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
    }

    private static func firstMatch(_ rx: NSRegularExpression, in s: String) -> String? {
        guard let m = rx.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range, in: s) else { return nil }
        return String(s[r])
    }

    private static func extractNumeric(_ rx: NSRegularExpression,
                                       from s: String,
                                       range vRange: ClosedRange<Double>) -> Double? {
        let ns = NSRange(s.startIndex..., in: s)
        guard let m = rx.firstMatch(in: s, range: ns) else { return nil }
        for i in 1..<m.numberOfRanges {
            guard let r = Range(m.range(at: i), in: s),
                  let v = Double(s[r]), vRange.contains(v) else { continue }
            return v
        }
        return nil
    }

    private static func extractNumericInt(_ rx: NSRegularExpression,
                                          from s: String,
                                          range vRange: ClosedRange<Int>) -> Int? {
        guard let v = extractNumeric(rx, from: s,
                                     range: Double(vRange.lowerBound)...Double(vRange.upperBound))
        else { return nil }
        return Int(v)
    }

    // MARK: ─── 渠道检测（v7）────────────────────────────────────
    //
    // 策略：从原文末尾 50 字符优先搜索（渠道标记通常在备注末尾），
    //       未匹配时再全文搜索（渠道词在文本中部时兜底）。
    // 调试日志：每次解析均在控制台输出 [解析渠道]: 关键词 -> 渠道
    //
    // 标记为 internal（非 private），可在单元测试中直接调用验证。

    static func extractChannel(from text: String) -> (channel: String, keyword: String?) {
        let tail = String(text.suffix(50))
        print("[渠道检测] 搜索全文尾50字: \"\(tail)\"")

        // 第一遍：从末尾 50 字符优先匹配
        for (kw, channel) in channelKeywordMap where tail.contains(kw) {
            print("[解析渠道]: \(kw) -> \(channel)")
            return (channel, kw)
        }
        print("[渠道检测] 尾部未匹配，搜索全文...")
        // 第二遍：全文兜底
        for (kw, channel) in channelKeywordMap where text.contains(kw) {
            print("[解析渠道]: \(kw)(全文) -> \(channel)")
            return (channel, kw)
        }
        print("[解析渠道]: 未匹配 -> 食谱")
        return ("食谱", nil)
    }
}
