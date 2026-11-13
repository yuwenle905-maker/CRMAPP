// MARK: - AnalyticsView.swift
// 渠道 & 画像分析独立 Tab

import SwiftUI

struct AnalyticsView: View {

    @EnvironmentObject var store: DataStore
    @State private var viewMode:      DashboardViewMode = .monthly
    @State private var selectedYear:  Int = Calendar.current.component(.year,  from: Date())
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var channelExpanded:  Bool = true
    @AppStorage("presentationDisplayConfig") private var presentationRaw: String = ""
    @State private var showPresentationSettings = false

    private var presentation: PresentationDisplayConfig {
        PresentationDisplayConfig.decode(presentationRaw)
    }

    private var activeFullCustomers: [Customer] {
        switch viewMode {
        case .monthly:
            return store.allCustomers(inYear: selectedYear, month: selectedMonth)
                        .filter { $0.dataType == .fullCustomer }
        case .cumulative:
            return store.customers.filter { $0.dataType == .fullCustomer }
        }
    }

    private var funnelCustomers: [Customer] {
        store.customers.filter { $0.dataType == .fullCustomer && $0.costEnabled }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if presentation.demoEnabled { DemoDataBadge() }

                    // 月度 / 累计切换
                    Picker("视图", selection: $viewMode) {
                        ForEach(DashboardViewMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if viewMode == .monthly {
                        PeriodPickerView(year: $selectedYear, month: $selectedMonth)
                            .padding(.horizontal)
                    }

                    // 渠道漏斗分析
                    ChannelFunnelCard(
                        channels: viewMode == .monthly
                            ? ROIEngine.channelStats(customers: store.customers,
                                                     year: selectedYear, month: selectedMonth)
                            : ROIEngine.channelStats(customers: store.customers),
                        allCustomers: funnelCustomers,
                        showRevenue: store.settings.channelRevenueVisible,
                        year:  viewMode == .monthly ? selectedYear  : nil,
                        month: viewMode == .monthly ? selectedMonth : nil,
                        expanded: $channelExpanded,
                        displayConfig: presentation
                    )
                    .padding(.horizontal)

                    // 地域分布
                    if !presentation.isHidden(PresentationMetric.regionSection) {
                        DrillDownProfileCard(title: "地域分布（七大区）", items: regionItems,
                                             allCustomers: activeFullCustomers, drillType: .region,
                                             displayConfig: presentation)
                            .padding(.horizontal)
                    }

                    // 年龄段分布
                    if !presentation.isHidden(PresentationMetric.ageSection) {
                        DrillDownProfileCard(title: "年龄段分布", items: ageItems,
                                             allCustomers: activeFullCustomers, drillType: .age,
                                             displayConfig: presentation)
                            .padding(.horizontal)
                    }

                    // 线索金额分布
                    if !presentation.isHidden(PresentationMetric.amountSection) {
                        DrillDownProfileCard(title: "线索金额分布", items: amountItems,
                                             allCustomers: activeFullCustomers, drillType: .amount,
                                             displayConfig: presentation)
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 32)
                }
                .padding(.top)
            }
            .navigationTitle("渠道分析")
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showPresentationSettings = true } label: {
                        Image(systemName: presentation.hiddenMetrics.isEmpty ? "eye" : "eye.slash")
                    }
                    .accessibilityLabel("展示与演示设置")
                }
            }
            .sheet(isPresented: $showPresentationSettings) {
                PresentationSettingsView(rawConfig: $presentationRaw,
                                         channels: channelItems,
                                         regionItems: regionItems,
                                         ageItems: ageItems,
                                         amountItems: amountItems,
                                         customers: store.customers.filter { $0.dataType == .fullCustomer })
            }
        }
    }

    private var channelItems: [ChannelStats] {
        viewMode == .monthly
            ? ROIEngine.channelStats(customers: store.customers, year: selectedYear, month: selectedMonth)
            : ROIEngine.channelStats(customers: store.customers)
    }
    private var regionItems: [ProfileItem] { ROIEngine.regionProfiles(customers: activeFullCustomers) }
    private var ageItems: [ProfileItem] { ROIEngine.ageProfiles(customers: activeFullCustomers) }
    private var amountItems: [ProfileItem] { ROIEngine.amountProfiles(customers: activeFullCustomers) }
}
