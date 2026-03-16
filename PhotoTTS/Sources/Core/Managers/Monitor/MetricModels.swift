//
//  MetricModels.swift
//  PhotoTTS
//
//  实时监控数据模型
//

import Foundation

// MARK: - 监控指标类型
enum MetricType: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "Memory"
    case disk = "Disk"
    case network = "Network"
    
    var id: String { rawValue }
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disk: "Disk I/O"
        case .network: "Network"
        }
    }
    
    /// 单位
    var unit: String {
        switch self {
        case .cpu: "%"
        case .memory: "MB"
        case .disk: "MB/s"
        case .network: "MB/s"
        }
    }
}

// MARK: - 单个数据点
struct MetricPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
    let secondaryValue: Double? // 用于双曲线指标（如磁盘读/写、网络上传/下载）
    
    init(timestamp: Date, value: Double, secondaryValue: Double? = nil) {
        self.timestamp = timestamp
        self.value = value
        self.secondaryValue = secondaryValue
    }
}

// MARK: - 指标数据集合
struct MetricData {
    let type: MetricType
    var points: [MetricPoint]
    let currentValue: Double
    let secondaryCurrentValue: Double? // 用于双曲线指标
    let peakValue: Double
    let secondaryPeakValue: Double? // 用于双曲线指标
    
    init(type: MetricType, points: [MetricPoint], currentValue: Double, secondaryCurrentValue: Double? = nil, peakValue: Double, secondaryPeakValue: Double? = nil) {
        self.type = type
        self.points = points
        self.currentValue = currentValue
        self.secondaryCurrentValue = secondaryCurrentValue
        self.peakValue = peakValue
        self.secondaryPeakValue = secondaryPeakValue
    }
    
    /// 格式化当前值显示
    func formatCurrentValue() -> String {
        switch type {
        case .cpu:
            return String(format: "%.1f%%", currentValue)
        case .memory:
            return formatMemory(currentValue)
        case .disk:
            if let secondary = secondaryCurrentValue {
                return String(format: "R: %.2f  W: %.2f", currentValue, secondary)
            }
            return String(format: "%.2f", currentValue)
        case .network:
            if let secondary = secondaryCurrentValue {
                return String(format: "Tx: %.2f  Rx: %.2f", currentValue, secondary)
            }
            return String(format: "%.2f", currentValue)
        }
    }
    
    /// 格式化峰值显示
    func formatPeakValue() -> String {
        switch type {
        case .cpu:
            return String(format: "%.1f%%", peakValue)
        case .memory:
            return formatMemory(peakValue)
        case .disk:
            if let secondary = secondaryPeakValue {
                return String(format: "R: %.2f  W: %.2f", peakValue, secondary)
            }
            return String(format: "%.2f", peakValue)
        case .network:
            if let secondary = secondaryPeakValue {
                return String(format: "Tx: %.2f  Rx: %.2f", peakValue, secondary)
            }
            return String(format: "%.2f", peakValue)
        }
    }
    
    /// 格式化内存值
    private func formatMemory(_ value: Double) -> String {
        if value >= 1024 {
            return String(format: "%.1fGB", value / 1024)
        }
        return String(format: "%.1fMB", value)
    }
}

