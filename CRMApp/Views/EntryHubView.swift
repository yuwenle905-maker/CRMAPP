// MARK: - EntryHubView.swift
// 录入入口：智能导入 + 流水录入 合并为单一 Tab

import SwiftUI

struct EntryHubView: View {

    @EnvironmentObject var store: DataStore
    @State private var mode = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("录入方式", selection: $mode) {
                Text("智能导入").tag(0)
                Text("流水录入").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))

            Divider()

            if mode == 0 {
                ImportView()
                    .environmentObject(store)
            } else {
                TextInputView()
                    .environmentObject(store)
            }
        }
    }
}
