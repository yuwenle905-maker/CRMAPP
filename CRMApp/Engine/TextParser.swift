// MARK: - TextParser.swift
// 手动文本批量录入解析引擎
// v2：支持两种输入格式
//   A. 每行一条（换行分隔）：张三新单4280
//   B. 连续平铺（空格分隔）：严亚 新单 2260 朱忠惠 新单 2680 ...

import Foundation

// MARK: 解析错误
enum ParseError: Error {
    case formatMismatch(String)
    case invalidAmount(String)
}

// MARK: 单条解析结果
struct TextParseResult: Identifiable {
    let id = UUID()
    let rawLine: String
    var name: String
    var conversionType: ConversionType
    var amount: Double
    var customerNumber: String? = nil   // 非nil时按编号匹配，name仅作显示用
    var orderDate: Date = Date()        // 逐单确认的开单日期
    var advisorSplits: [AdvisorSplit] = [] // 逐单业绩归属，支持单人或双人各半
}

// MARK: 解析错误行
struct TextParseError: Identifiable {
    let id = UUID()
    let lineNumber: Int
    let rawLine: String
    let reason: String
}

// MARK: 主解析器
enum TextParser {

    // 状态关键词表
    private static let conversionKeywords: [(keywords: [String], type: ConversionType)] = [
        (["多次", "后续", "后续开发", "续单", "续购", "后续单", "N次", "n次"], .multiple),
        (["八次", "8次", "第八"],                                              .eighth),
        (["七次", "7次", "第七"],                                              .seventh),
        (["六次", "6次", "第六"],                                              .sixth),
        (["五次", "5次", "第五"],                                              .fifth),
        (["四次", "4次", "第四"],                                              .fourth),
        (["三次", "3次", "第三"],                                              .third),
        (["二次", "2次", "第二", "复购"],                                      .second),
        (["新单", "首单", "一次", "1次", "第一", "新"],                        .newOrder),
    ]

    // 全局循环正则：匹配 [姓名] [状态词] [金额] 三元组
    // 姓名：至少1个非空白非纯数字字符
    // 状态：固定关键词
    // 金额：纯数字（含小数/逗号）
    private static let triplePattern = try! NSRegularExpression(
        pattern: #"([^\s\d,，。、\n\r]{1,10}(?:女士|先生|小姐)?)\s*(新单|首单|二次|三次|四次|五次|六次|七次|八次|复购|一次|多次|后续|后续开发|续单|续购|后续单)\s*(\d[\d,，.]*)"#,
        options: []
    )

    // 末尾金额正则（单行模式备用）
    private static let trailingAmountPattern = try! NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)?)\s*[元￥]?\s*$"#
    )

    // 编号格式正则：[3-6位数字编号] [状态词] [金额]
    // 例：2013 新单 2860 / 2013多次2860
    private static let numberIDPattern = try! NSRegularExpression(
        pattern: #"(\d{3,6})\s*(新单|首单|二次|三次|四次|五次|六次|七次|八次|复购|一次|多次|后续|后续开发|续单|续购|后续单)\s*(\d[\d,，.]*)"#,
        options: []
    )

    // MARK: 批量解析入口
    static func parse(_ text: String) -> (results: [TextParseResult], errors: [TextParseError]) {
        let normalized = text
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2003}", with: " ")
            .replacingOccurrences(of: "\t",        with: " ")
            .replacingOccurrences(of: "，",         with: " ")
            .replacingOccurrences(of: "、",         with: " ")
            .replacingOccurrences(of: "　",         with: " ")

        // 编号格式优先扫描（平铺多条）
        let numberResults = parseByNumberID(normalized)
        if numberResults.count >= 2 { return (numberResults, []) }

        // 名称三元组平铺扫描
        let globalResults = parseByGlobalRegex(normalized)
        if globalResults.count >= 2 { return (globalResults, []) }

        // 按行解析（单行或多行标准格式）
        return parseByLines(normalized)
    }

    // MARK: 编号批量扫描
    static func parseByNumberID(_ text: String) -> [TextParseResult] {
        let nsText = text as NSString
        let matches = numberIDPattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { m -> TextParseResult? in
            guard m.numberOfRanges == 4,
                  let numRange    = Range(m.range(at: 1), in: text),
                  let statusRange = Range(m.range(at: 2), in: text),
                  let amtRange    = Range(m.range(at: 3), in: text) else { return nil }
            let numStr  = String(text[numRange])
            let status  = String(text[statusRange])
            let amtStr  = String(text[amtRange]).replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: "")
            guard let amount = Double(amtStr) else { return nil }
            return TextParseResult(rawLine: "\(numStr) \(status) \(amtStr)",
                                   name: "编号\(numStr)",
                                   conversionType: resolveConversionType(status),
                                   amount: amount,
                                   customerNumber: numStr)
        }
    }

    // MARK: 全局正则扫描（平铺格式核心）
    static func parseByGlobalRegex(_ text: String) -> [TextParseResult] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = triplePattern.matches(in: text, range: fullRange)

        return matches.compactMap { m -> TextParseResult? in
            guard m.numberOfRanges == 4,
                  let nameRange   = Range(m.range(at: 1), in: text),
                  let statusRange = Range(m.range(at: 2), in: text),
                  let amountRange = Range(m.range(at: 3), in: text)
            else { return nil }

            let name      = String(text[nameRange]).trimmingCharacters(in: .whitespaces)
            let statusStr = String(text[statusRange])
            let amtStr    = String(text[amountRange])
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "，", with: "")
            guard !name.isEmpty, let amount = Double(amtStr) else { return nil }

            let convType = resolveConversionType(statusStr)
            let rawLine  = "\(name) \(statusStr) \(amtStr)"
            return TextParseResult(rawLine: rawLine, name: name,
                                   conversionType: convType, amount: amount)
        }
    }

    // MARK: 按行解析（原逻辑，保留兼容性）
    private static func parseByLines(_ normalized: String) -> (results: [TextParseResult], errors: [TextParseError]) {
        let lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var results: [TextParseResult] = []
        var errors:  [TextParseError]  = []

        for (i, line) in lines.enumerated() {
            switch parseLine(line) {
            case .success(let r):
                results.append(r)
            case .failure(let err):
                let reason: String
                switch err {
                case .formatMismatch(let m): reason = m
                case .invalidAmount(let m):  reason = m
                }
                errors.append(TextParseError(lineNumber: i + 1, rawLine: line, reason: reason))
            }
        }
        return (results, errors)
    }

    // MARK: 单行解析
    static func parseLine(_ raw: String) -> Result<TextParseResult, ParseError> {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return .failure(.formatMismatch("空行")) }

        // 优先尝试编号格式（纯数字打头）
        let nsS = s as NSString
        if let m = numberIDPattern.firstMatch(in: s, range: NSRange(location: 0, length: nsS.length)),
           m.numberOfRanges == 4,
           let numR = Range(m.range(at: 1), in: s),
           let stR  = Range(m.range(at: 2), in: s),
           let amtR = Range(m.range(at: 3), in: s) {
            let numStr = String(s[numR])
            let status = String(s[stR])
            let amtStr = String(s[amtR]).replacingOccurrences(of: ",", with: "")
            if let amount = Double(amtStr) {
                return .success(TextParseResult(rawLine: raw, name: "编号\(numStr)",
                                               conversionType: resolveConversionType(status),
                                               amount: amount, customerNumber: numStr))
            }
        }

        let nsRange = NSRange(s.startIndex..., in: s)
        guard let amountMatch = trailingAmountPattern.firstMatch(in: s, range: nsRange),
              let amtRange = Range(amountMatch.range(at: 1), in: s) else {
            return .failure(.formatMismatch("找不到金额数字，请确保行末包含金额，例如：张三新单4280"))
        }
        let amountStr = String(s[amtRange]).replacingOccurrences(of: ",", with: "")
        guard let amount = Double(amountStr), amount >= 0 else {
            return .failure(.invalidAmount("金额解析失败：\(amountStr)"))
        }

        let prefixEnd = amountMatch.range.location == NSNotFound
            ? s.endIndex
            : s.index(s.startIndex, offsetBy: amountMatch.range.location)
        let prefix = String(s[s.startIndex..<prefixEnd]).trimmingCharacters(in: .whitespaces)

        var convType: ConversionType = .unknown
        var nameCandidate = prefix

        for entry in conversionKeywords {
            for kw in entry.keywords {
                if prefix.contains(kw) {
                    convType = entry.type
                    nameCandidate = prefix
                        .replacingOccurrences(of: kw, with: "")
                        .trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            if convType != .unknown { break }
        }

        let name = nameCandidate.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            return .failure(.formatMismatch("解析出的姓名为空，请检查格式。示例：张三新单4280"))
        }

        return .success(TextParseResult(rawLine: raw, name: name,
                                        conversionType: convType, amount: amount))
    }

    // MARK: 辅助：状态词 → ConversionType
    private static func resolveConversionType(_ s: String) -> ConversionType {
        for entry in conversionKeywords {
            if entry.keywords.contains(s) { return entry.type }
        }
        return .newOrder
    }
}
