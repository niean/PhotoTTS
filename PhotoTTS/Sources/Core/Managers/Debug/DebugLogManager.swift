import Foundation
import os.log
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 调试日志管理器
/// 负责保存和管理应用的调试日志
class DebugLogManager {
    static let shared = DebugLogManager()

    private let fileManager = FileManager.default
    private let maxLogFileSize: Int64 = Constants.DebugLog.maxLogFileSize
    private let maxLogFiles = Constants.DebugLog.maxLogFiles

    private var logFileURL: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let logsDirectory = documentsPath.appendingPathComponent("Logs", isDirectory: true)

        // 确保日志目录存在
        if !fileManager.fileExists(atPath: logsDirectory.path) {
            try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        }

        return logsDirectory.appendingPathComponent("debug.log")
    }

    // 使用 .default QoS，避免优先级反转问题
    // .default 会根据调用线程的优先级自动调整，避免高优先级线程等待低优先级线程
    private let logQueue = DispatchQueue(label: "com.phototts.debuglog", qos: .default, attributes: .concurrent)
    private var logFileHandle: FileHandle?

    private init() {
        setupLogFile()
        startLogging()
    }

    deinit {
        stopLogging()
    }

    // MARK: - 文件管理

    /// 设置日志文件
    private func setupLogFile() {
        // 使用 barrier 确保文件操作的线程安全
        logQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            // 检查当前日志文件大小，如果超过限制则轮转
            if self.fileManager.fileExists(atPath: self.logFileURL.path) {
                if let attributes = try? self.fileManager.attributesOfItem(atPath: self.logFileURL.path),
                   let fileSize = attributes[.size] as? Int64,
                   fileSize > self.maxLogFileSize {
                    self.rotateLogFile()
                }
            }

            // 创建或打开日志文件
            if !self.fileManager.fileExists(atPath: self.logFileURL.path) {
                self.fileManager.createFile(atPath: self.logFileURL.path, contents: nil)
            }

            // 打开文件句柄用于追加写入
            if let fileHandle = FileHandle(forWritingAtPath: self.logFileURL.path) {
                fileHandle.seekToEndOfFile()
                self.logFileHandle = fileHandle
            }
        }
    }

    /// 轮转日志文件
    private func rotateLogFile() {
        // 清理旧日志文件
        let logsDirectory = logFileURL.deletingLastPathComponent()
        do {
            let logFiles = try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey], options: [])
                .filter { $0.lastPathComponent.hasPrefix("debug") && $0.lastPathComponent.hasSuffix(".log") }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return date1 < date2
                }

            // 删除超出数量的旧文件
            if logFiles.count >= maxLogFiles {
                for i in 0..<(logFiles.count - maxLogFiles + 1) {
                    try? fileManager.removeItem(at: logFiles[i])
                }
            }

            // 重命名当前日志文件
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let rotatedURL = logsDirectory.appendingPathComponent("debug_\(timestamp).log")
            try? fileManager.moveItem(at: logFileURL, to: rotatedURL)
        } catch {
            os.Logger.debugLog.error("轮转日志文件失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 日志记录

    /// 记录日志
    /// - Parameter message: 日志消息
    func log(_ message: String) {
        // 在入口处统一剥除 OSLOG 前缀，确保所有来源的日志都被清理
        let cleanedMessage = stripOSLogPrefix(message)
        guard !cleanedMessage.isEmpty else { return }

        // 使用 async 非阻塞方式，避免阻塞调用线程
        // 使用 barrier 确保写入操作的线程安全
        logQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let timestamp = DateFormatter.logFormatter.string(from: Date())
            let logEntry = "\(timestamp) \(cleanedMessage)\n"

            guard let data = logEntry.data(using: .utf8) else { return }
            // 每次打开-追加-关闭，避免长期持有 FileHandle 在 I/O 异常时导致 writeData 崩溃
            guard let fileHandle = FileHandle(forWritingAtPath: self.logFileURL.path) else { return }
            defer { try? fileHandle.close() }
            fileHandle.seekToEndOfFile()
            try? fileHandle.write(contentsOf: data)
        }
    }

    // MARK: - 日志读取

    /// 获取所有日志内容
    /// - Returns: 日志内容字符串
    func getAllLogs() -> String {
        var logs = ""

        // 使用同步方式读取，但使用 .default QoS 避免优先级反转
        // .default QoS 会根据调用线程的优先级自动调整
        logQueue.sync { [weak self] in
            guard let self = self else { return }

            if let data = try? Data(contentsOf: self.logFileURL),
               let content = String(data: data, encoding: .utf8) {
                logs = content
            }
        }

        return logs
    }

    /// 仅从文件尾部读取数据，避免大文件整份加载进内存
    private static let tailReadMaxBytes: Int = 256 * 1024 // 最多读取 256KB 尾部

    /// 从文件读取最新日志（不含队列同步，调用方需确保线程安全）
    private func readLatestLogsFromFile(lineCount: Int) -> String {
        guard self.fileManager.fileExists(atPath: self.logFileURL.path),
              let fileHandle = FileHandle(forReadingAtPath: self.logFileURL.path) else {
            return ""
        }
        defer { try? fileHandle.close() }

        let fullSize = (try? self.fileManager.attributesOfItem(atPath: self.logFileURL.path))?[.size] as? Int64 ?? 0
        let bytesToRead = min(Int(fullSize), Self.tailReadMaxBytes)
        guard bytesToRead > 0 else { return "" }

        fileHandle.seek(toFileOffset: UInt64(fullSize - Int64(bytesToRead)))
        let data = fileHandle.readData(ofLength: bytesToRead)
        guard !data.isEmpty, let content = String(data: data, encoding: .utf8) else {
            return ""
        }

        var lines = content.components(separatedBy: .newlines)
        // 若从中间截断，首段可能是某行的后半部分，丢弃不完整的第一行
        if fullSize > bytesToRead, !lines.isEmpty {
            lines.removeFirst()
        }
        let startIndex = max(0, lines.count - lineCount)
        // 时间倒序：最新日志在最前面
        // 读取时也剥除 OSLOG 前缀，确保已存储的旧日志也被清理
        let latestLines = Array(lines[startIndex..<lines.count].reversed()).map { self.stripOSLogPrefix($0) }
        var header = ""
        if Int(fullSize) > bytesToRead || lines.count > lineCount {
            let totalLinesHint = lines.count > lineCount ? "（当前段共 \(lines.count) 行）" : "（仅读取文件尾部 \(bytesToRead/1024)KB）"
            header = "[仅显示最新 \(lineCount) 行 \(totalLinesHint)]\n"
        }
        return header + latestLines.joined(separator: "\n")
    }

    /// 读取日志文件大小（不含队列同步，调用方需确保线程安全）
    private func readLogFileSize() -> Int64 {
        if let attributes = try? self.fileManager.attributesOfItem(atPath: self.logFileURL.path),
           let fileSize = attributes[.size] as? Int64 {
            return fileSize
        }
        return 0
    }

    /// 获取最新的N行日志（只读取文件尾部，最多加载 tailReadMaxBytes，降低内存占用）
    /// - Parameter lineCount: 要获取的行数，默认 50 行
    /// - Returns: 最新的日志内容字符串
    func getLatestLogs(lineCount: Int = 50) -> String {
        var logs = ""
        logQueue.sync { [weak self] in
            guard let self = self else { return }
            logs = self.readLatestLogsFromFile(lineCount: lineCount)
        }
        return logs
    }

    /// 刷新并获取最新日志（确保所有待写入日志已落盘后再读取）
    /// 使用 barrier 异步任务等待所有先前提交的 log() 写入完成后再读取文件
    /// - Parameters:
    ///   - lineCount: 要获取的行数，默认 50 行
    ///   - completion: 完成回调，返回 (日志内容, 文件大小)，在 logQueue 上调用
    func flushAndGetLatestLogs(lineCount: Int = 50, completion: @escaping (String, Int64) -> Void) {
        logQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else {
                completion("", 0)
                return
            }
            let logs = self.readLatestLogsFromFile(lineCount: lineCount)
            let size = self.readLogFileSize()
            completion(logs, size)
        }
    }

    /// 获取日志文件大小
    /// - Returns: 文件大小（字节）
    func getLogFileSize() -> Int64 {
        var size: Int64 = 0
        logQueue.sync { [weak self] in
            guard let self = self else { return }
            size = self.readLogFileSize()
        }
        return size
    }

    /// 清空日志
    func clearLogs() {
        // 使用 barrier 确保清空操作的线程安全
        logQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            self.logFileHandle?.closeFile()
            self.logFileHandle = nil

            try? "".write(to: self.logFileURL, atomically: true, encoding: .utf8)

            self.setupLogFile()
        }
    }

    // MARK: - 日志重定向

    private var originalStdErr: Int32 = 0
    private var originalStdOut: Int32 = 0
    private var stderrPipe: Pipe?
    private var stdoutPipe: Pipe?

    /// 开始捕获NSLog和print输出
    private func startLogging() {
        // 保存原始文件描述符
        originalStdErr = dup(STDERR_FILENO)
        originalStdOut = dup(STDOUT_FILENO)

        // 创建Pipe用于捕获stderr（NSLog输出）
        stderrPipe = Pipe()
        guard let stderrPipe = stderrPipe else { return }
        dup2(stderrPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty {
                self?.processLogData(data, isStderr: true)
            }
        }

        // 创建Pipe用于捕获stdout（print输出）
        stdoutPipe = Pipe()
        guard let stdoutPipe = stdoutPipe else { return }
        dup2(stdoutPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty {
                self?.processLogData(data, isStderr: false)
            }
        }
    }

    /// 处理日志数据
    private func processLogData(_ data: Data, isStderr: Bool) {
        guard let raw = String(data: data, encoding: .utf8) else { return }

        // 按行处理，剥除 os.Logger 内部元数据前缀后写入日志文件
        // os.Logger 写入 stderr 时会带如下前缀（对用户毫无意义）：
        //   OSLOG-UUID N N L hex {t:float,tid:hex} 实际消息
        let lines = raw.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let cleaned = stripOSLogPrefix(trimmed)
            guard !cleaned.isEmpty else { continue }
            log(cleaned)
        }

        // 同时输出到原始流：使用 POSIX write 避免 FileHandle.writeData 在 FD 失效时抛 I/O 异常崩溃
        let originalFD = isStderr ? originalStdErr : originalStdOut
        if originalFD > 0, !data.isEmpty {
            _ = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                guard let baseAddress = buffer.baseAddress else { return -1 }
                return write(Int32(originalFD), baseAddress, data.count)
            }
        }
    }

    /// OSLOG 元数据正则（编译一次复用）
    /// 匹配: OSLOG-<UUID> <fields> {t:<ts>,tid:<hex>} 及尾部可选空格
    /// 示例: OSLOG-AA9F2DF2-B46D-4921-94CC-291C9ED07AF9 7 80 L 1a {t:1772585718.989001,tid:0x28ab75}
    /// 注意: UUID 可以包含大写或小写字母 (A-F, a-f)
    private static let oslogRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"OSLOG-[A-Fa-f0-9-]+[^{]*\{[^}]*\}\s?"#)
    }()

    /// 剥除 os.Logger 内部元数据前缀（写入时和读取时通用）
    /// 格式示例（stderr 原始输出）：OSLOG-AA9F2DF2-...{t:...,tid:...} 实际消息
    /// 格式示例（已存储行）：0304T08:55:18 OSLOG-AA9F2DF2-...{t:...,tid:...} 实际消息
    private func stripOSLogPrefix(_ message: String) -> String {
        guard let regex = Self.oslogRegex else { return message }
        let nsRange = NSRange(message.startIndex..., in: message)
        let result = regex.stringByReplacingMatches(in: message, range: nsRange, withTemplate: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 停止捕获日志
    private func stopLogging() {
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil

        if originalStdErr > 0 {
            dup2(originalStdErr, STDERR_FILENO)
        }
        if originalStdOut > 0 {
            dup2(originalStdOut, STDOUT_FILENO)
        }

        logFileHandle?.closeFile()
    }
}

// MARK: - DateFormatter Extension

extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // 时间头格式：0219T16:24:56（去掉年份，用 T 分隔日期和时间）
        formatter.dateFormat = "MMdd'T'HH:mm:ss"
        return formatter
    }()
}
