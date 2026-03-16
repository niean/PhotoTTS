//
//  RealTimeMonitorView.swift
//  PhotoTTS
//
//  实时监控主视图
//

import SwiftUI

// MARK: - 实时监控视图
struct RealTimeMonitorView: View {
    @ObservedObject private var monitor = PerformanceMonitorManager.shared
    @Environment(\.dismiss) private var dismiss
    
    private let iconSize: CGFloat = 24
    private let horizontalPadding: CGFloat = 16
    
    var body: some View {
        CustomZStack {
            // 主内容区
            List {
                Section {
                    MetricCardView(title: "CPU", data: monitor.cpuData)
                    MetricCardView(title: "Memory", data: monitor.memoryData)
                    MetricCardView(title: "Disk I/O", data: monitor.diskData)
                    MetricCardView(title: "Network", data: monitor.networkData)
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 0, for: .scrollContent)
            .padding(.top, 45) // 为导航栏留出空间
            
            TopAndLeftSideNavigationBar(title: "实时监控", onSwipeBack: { dismiss() }, leading: {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(Constants.Fonts.fixedNavAction)
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.primary)
                }
            })
        }
        .navigationBarHidden(true) // 隐藏系统导航栏
        .onAppear {
            monitor.startMonitoring()
        }
        .onDisappear {
            monitor.stopMonitoring()
        }
    }
}

// MARK: - 指标卡片视图
struct MetricCardView: View {
    let title: String
    let data: MetricData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题（主题蓝色）
            Text(title)
                .font(Constants.Fonts.subheadline)
                .foregroundStyle(.blue)
            
            // 当前值和峰值（主题蓝色文本）
            HStack {
                Text("当前：\(data.formatCurrentValue())")
                    .font(Constants.Fonts.body)
                    .foregroundStyle(.blue)
                Spacer()
                Text("峰值：\(data.formatPeakValue())")
                    .font(Constants.Fonts.caption)
                    .foregroundStyle(.blue)
            }
            
            // 图表（主题蓝色）
            RealTimeMonitorChartView(data: data, color: .blue)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 预览
#Preview {
    RealTimeMonitorView()
}
