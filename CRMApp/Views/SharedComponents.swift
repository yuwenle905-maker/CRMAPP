// MARK: - SharedComponents.swift
// 跨视图共享的基础 UI 组件

import SwiftUI

// MARK: - Date 中文格式化
extension Date {
    /// 格式：2026年06月28日 14:30
    var chineseDateTime: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年MM月dd日 HH:mm"
        return fmt.string(from: self)
    }

    /// 格式：6月28日
    var chineseDate: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "M月d日"
        return fmt.string(from: self)
    }
}

/// iOS 15 兼容的键值展示行（替代 LabeledContent）
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
