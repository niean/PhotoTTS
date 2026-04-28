//
//  PerformanceMonitorManager.swift
//  PhotoTTS
//
//  性能监控管理器 - 采集 CPU、内存、磁盘、网络指标
//

import Foundation
import os
import UIKit
import MachO

// MARK: - 性能监控管理器
@MainActor
class PerformanceMonitorManager: ObservableObject {
    // MARK: - 单例
    static let shared = PerformanceMonitorManager()
    
    // MARK: - 公开属性
    @Published var cpuData: MetricData
    @Published var memoryData: MetricData
    @Published var diskData: MetricData
    @Published var networkData: MetricData
    
    /// 监控状态（公共访问）
    var isMonitoring: Bool {
        return timer != nil
    }
    
    private var timer: Timer?
    private var lastCollectTime: Date = Date()
    
    // CPU 基线
    private var lastTotalCPU: Double = 0
    
    // Disk I/O 基线（累计字节数）
    private var lastDiskReadBytes: UInt64 = 0
    private var lastDiskWriteBytes: UInt64 = 0
    
    // Network I/O 基线（累计字节数）
    private var lastNetworkSentBytes: UInt64 = 0
    private var lastNetworkReceivedBytes: UInt64 = 0
    
    // MARK: - Logger
    private let logger = os.Logger.performanceMonitor
    
    // MARK: - 私有初始化
    private init() {
        self.cpuData = MetricData(type: .cpu, points: [], currentValue: 0, peakValue: 0)
        self.memoryData = MetricData(type: .memory, points: [], currentValue: 0, peakValue: 0)
        self.diskData = MetricData(type: .disk, points: [], currentValue: 0, secondaryCurrentValue: 0, peakValue: 0, secondaryPeakValue: 0)
        self.networkData = MetricData(type: .network, points: [], currentValue: 0, secondaryCurrentValue: 0, peakValue: 0, secondaryPeakValue: 0)
        
        // 初始化历史数据点
        let now = Date()
        for i in 0..<10 {
            let timestamp = now.addingTimeInterval(TimeInterval(i - 10))
            cpuData.points.append(MetricPoint(timestamp: timestamp, value: 0))
            memoryData.points.append(MetricPoint(timestamp: timestamp, value: 0))
            diskData.points.append(MetricPoint(timestamp: timestamp, value: 0, secondaryValue: 0))
            networkData.points.append(MetricPoint(timestamp: timestamp, value: 0, secondaryValue: 0))
        }
        
        // 初始化计数器基线
        initializeCounters()
    }
    
    // MARK: - 初始化计数器
    private func initializeCounters() {
        // Network 基线
        let netCounters = getNetworkIOCounters()
        lastNetworkSentBytes = netCounters.sent
        lastNetworkReceivedBytes = netCounters.received
        
        // Disk I/O 基线
        let diskCounters = getDiskIOBytes()
        lastDiskReadBytes = diskCounters.read
        lastDiskWriteBytes = diskCounters.write
        
        lastCollectTime = Date()
    }
    
    // MARK: - 开始监控
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        logger.info("性能监控已启动")
        
        // 立即采集一次
        collectMetrics()
        
        // 设置定时器
        timer = Timer.scheduledTimer(withTimeInterval: Constants.Monitor.collectionInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.collectMetrics()
            }
        }
    }
    
    // MARK: - 停止监控
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        timer?.invalidate()
        timer = nil
        logger.info("性能监控已停止")
    }
    
    // MARK: - 采集指标
    private func collectMetrics() {
        let now = Date()
        let deltaTime = now.timeIntervalSince(lastCollectTime)
        
        // 采集 CPU（使用进程线程 CPU 时间计算使用率）
        let cpuUsage = collectCPU(deltaTime: deltaTime)
        updateMetricData(&cpuData, value: cpuUsage)
        
        // 采集内存
        let memoryUsage = collectMemory()
        updateMetricData(&memoryData, value: memoryUsage)
        
        // 采集 Disk I/O（通过 getrusage 获取进程级累计读写块数）
        if deltaTime > 0 {
            let diskCounters = getDiskIOBytes()
            let readDelta = diskCounters.read >= lastDiskReadBytes ? diskCounters.read - lastDiskReadBytes : 0
            let writeDelta = diskCounters.write >= lastDiskWriteBytes ? diskCounters.write - lastDiskWriteBytes : 0
            let diskReadRate = Double(readDelta) / deltaTime / 1024 / 1024
            let diskWriteRate = Double(writeDelta) / deltaTime / 1024 / 1024
            updateMetricData(&diskData, value: diskReadRate, secondaryValue: diskWriteRate)
            lastDiskReadBytes = diskCounters.read
            lastDiskWriteBytes = diskCounters.write
        }
        
        // 采集 Network I/O（通过 getifaddrs 获取网络接口累计字节）
        if deltaTime > 0 {
            let netCounters = getNetworkIOCounters()
            let sentDelta = netCounters.sent >= lastNetworkSentBytes ? netCounters.sent - lastNetworkSentBytes : 0
            let receivedDelta = netCounters.received >= lastNetworkReceivedBytes ? netCounters.received - lastNetworkReceivedBytes : 0
            let netSentRate = Double(sentDelta) / deltaTime / 1024 / 1024
            let netReceivedRate = Double(receivedDelta) / deltaTime / 1024 / 1024
            updateMetricData(&networkData, value: netSentRate, secondaryValue: netReceivedRate)
            lastNetworkSentBytes = netCounters.sent
            lastNetworkReceivedBytes = netCounters.received
        }
        
        lastCollectTime = now
    }
    
    // MARK: - 更新指标数据
    private func updateMetricData(_ data: inout MetricData, value: Double, secondaryValue: Double? = nil) {
        let now = Date()
        
        // 添加新数据点
        let newPoint = MetricPoint(timestamp: now, value: value, secondaryValue: secondaryValue)
        data.points.append(newPoint)
        
        // 移除超时的数据点（超过 5 分钟）
        let cutoffTime = now.addingTimeInterval(-Constants.Monitor.fixedTimeRange)
        data.points.removeAll { $0.timestamp < cutoffTime }
        
        // 更新峰值
        var newPeak = data.peakValue
        var newSecondaryPeak = data.secondaryPeakValue ?? 0
        if value > newPeak {
            newPeak = value
        }
        if let secondary = secondaryValue, secondary > newSecondaryPeak {
            newSecondaryPeak = secondary
        }
        
        data = MetricData(
            type: data.type,
            points: data.points,
            currentValue: value,
            secondaryCurrentValue: secondaryValue,
            peakValue: newPeak,
            secondaryPeakValue: data.type == .disk || data.type == .network ? newSecondaryPeak : nil
        )
    }
    
    // MARK: - 采集 CPU 使用率
    // 使用 mach API 获取当前进程所有线程的 CPU 时间，计算使用率
    private func collectCPU(deltaTime: TimeInterval) -> Double {
        var totalCPU: Double = 0.0
        
        // 获取当前进程的所有线程
        var threads: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        let result = task_threads(mach_task_self_, &threads, &threadCount)
        
        if result == KERN_SUCCESS, let threadArray = threads {
            for i in 0..<Int(threadCount) {
                var threadInfo = thread_basic_info()
                var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
                
                let threadResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                        thread_info(threadArray[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                    }
                }
                
                if threadResult == KERN_SUCCESS {
                    if threadInfo.flags & TH_FLAGS_IDLE == 0 {
                        // 累加用户态 + 系统态 CPU 时间（包含微秒精度）
                        let userTime = Double(threadInfo.user_time.seconds) + Double(threadInfo.user_time.microseconds) / 1_000_000.0
                        let systemTime = Double(threadInfo.system_time.seconds) + Double(threadInfo.system_time.microseconds) / 1_000_000.0
                        totalCPU += userTime + systemTime
                    }
                }
            }
            
            // 释放线程数组
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threadArray), vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size))
        }
        
        guard deltaTime > 0 else { return 0 }
        
        // CPU 时间增量 / 实际时间 * 100%
        let cpuDelta = totalCPU - lastTotalCPU
        lastTotalCPU = totalCPU
        let cpuUsage = (cpuDelta / deltaTime) * 100.0
        
        // 限制在 0-100% 范围内
        return max(0, min(100, cpuUsage))
    }
    
    // MARK: - 采集内存使用量
    private func collectMemory() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return 0
        }
        
        // 返回 MB
        return Double(info.resident_size) / 1024 / 1024
    }
    
    // MARK: - 获取 Disk I/O 累计块数
    // 通过 getrusage(RUSAGE_SELF) 获取进程级磁盘读写块数（块大小通常为 512 字节）
    // 注意：iOS 沙盒环境下 ru_inblock/ru_oublock 可能返回 0，属于系统限制
    private func getDiskIOBytes() -> (read: UInt64, write: UInt64) {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return (0, 0) }
        // 每个 block 按 512 字节估算
        return (UInt64(usage.ru_inblock) * 512, UInt64(usage.ru_oublock) * 512)
    }
    
    // MARK: - 获取 Network I/O 累计字节数
    // 通过 getifaddrs 遍历网络接口，汇总 AF_LINK 层的收发字节
    private func getNetworkIOCounters() -> (sent: UInt64, received: UInt64) {
        var totalSent: UInt64 = 0
        var totalReceived: UInt64 = 0
        
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return (0, 0) }
        defer { freeifaddrs(ifaddrPtr) }
        
        var cursor = ifaddrPtr
        while let addr = cursor {
            // 只统计 AF_LINK（链路层）接口，包含物理网卡的累计流量
            if addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                if let data = addr.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self)
                    totalSent += UInt64(networkData.pointee.ifi_obytes)
                    totalReceived += UInt64(networkData.pointee.ifi_ibytes)
                }
            }
            cursor = addr.pointee.ifa_next
        }
        
        return (totalSent, totalReceived)
    }
}
