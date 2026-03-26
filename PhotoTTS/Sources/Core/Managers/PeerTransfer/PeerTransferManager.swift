import Foundation
import MultipeerConnectivity
import UIKit
import os

// MARK: - 传输状态

enum TransferState: Equatable {
    case idle
    case browsing
    case advertising
    case connecting
    case preparing
    case transferring
    case importing
    case completed(imported: Int, skipped: Int)
    case failed(String)

    static func == (lhs: TransferState, rhs: TransferState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.browsing, .browsing), (.advertising, .advertising),
             (.connecting, .connecting), (.preparing, .preparing), (.transferring, .transferring),
             (.importing, .importing):
            return true
        case (.completed(let a1, let a2), .completed(let b1, let b2)):
            return a1 == b1 && a2 == b2
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - 邀请上下文

struct TransferInvitationContext: Codable {
    let sessionCount: Int
    let totalSize: Int64
    let deviceName: String
    let sessionIDs: [String]
}

struct TransferConflictDecision: Codable {
    let skipDuplicates: Bool
    let existingIDs: [String]
}

struct TransferInvitation: Identifiable {
    let id = UUID()
    let peerID: MCPeerID
    let context: TransferInvitationContext
    let existingIDs: [String]
    let handler: (Bool) -> Void
}

// MARK: - PeerTransferManager

class PeerTransferManager: NSObject, ObservableObject {
    static let shared = PeerTransferManager()

    @Published var discoveredPeers: [MCPeerID] = []
    @Published var transferState: TransferState = .idle
    @Published var transferProgress: Double = 0
    @Published var pendingInvitation: TransferInvitation?
    /// 实际传输记录数（去重后），发送方在 sendSessions 中设置，接收方在接受邀请时设置
    @Published private(set) var actualSendCount: Int = 0
    /// 跳过的重复记录数
    @Published private(set) var skippedDuplicateCount: Int = 0

    private let serviceType = Constants.PeerTransfer.serviceType
    private let myPeerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var browsingTimer: Timer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var transferProgressObserver: NSKeyValueObservation?
    private(set) var pendingSendIDs: [String] = []
    private(set) var pendingSendPeer: MCPeerID?
    /// 发送方标志：从 invitePeer 开始到传输完成/失败/取消为止保持 true，用于区分发送方和接收方
    @Published private(set) var isSender: Bool = false
    /// 接收方待发送的决策（连接建立后发送给发送方）
    var pendingDecisionToSend: TransferConflictDecision?
    /// 发送方收到的决策（用于过滤传输内容）
    private(set) var pendingDecision: TransferConflictDecision?
    /// 决策等待超时定时器（发送方使用）
    private var decisionTimeoutTimer: Timer?

    private override init() {
        self.myPeerID = MCPeerID(displayName: UIDevice.current.name)
        super.init()
    }

    // MARK: - 会话管理

    private func createSession() {
        if session != nil { return }
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
    }

    private func teardownSession() {
        session?.disconnect()
        session = nil
        transferProgressObserver?.invalidate()
        transferProgressObserver = nil
        cancelBackgroundTask()
    }

    // MARK: - 后台任务

    private func beginBackgroundTask() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            os.Logger.peerTransfer.warning("后台任务即将过期")
            self?.cancelBackgroundTask()
        }
    }

    private func cancelBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    // MARK: - 广播（接收方）

    func startAdvertising() {
        guard advertiser == nil else { return }
        createSession()
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }

    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        if transferState == .advertising || transferState == .idle {
            teardownSession()
        }
    }

    // MARK: - 搜索（发送方）

    func startBrowsing() {
        guard browser == nil else { return }
        createSession()
        DispatchQueue.main.async {
            self.discoveredPeers = []
            self.transferState = .browsing
            self.transferProgress = 0
        }
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()

        browsingTimer = Timer.scheduledTimer(withTimeInterval: Constants.PeerTransfer.browsingTimeout, repeats: false) { [weak self] _ in
            guard let self, self.transferState == .browsing, self.discoveredPeers.isEmpty else { return }
            DispatchQueue.main.async {
                self.transferState = .failed("未找到附近设备，请确认两台设备都已打开 PhotoTTS")
            }
        }
    }

    func stopBrowsing() {
        browsingTimer?.invalidate()
        browsingTimer = nil
        browser?.stopBrowsingForPeers()
        browser = nil
    }

    func reset() {
        stopBrowsing()
        stopAdvertising()
        teardownSession()
        decisionTimeoutTimer?.invalidate()
        decisionTimeoutTimer = nil
        DispatchQueue.main.async {
            self.discoveredPeers = []
            self.transferState = .idle
            self.transferProgress = 0
            self.pendingInvitation = nil
            self.isSender = false
            self.pendingSendIDs = []
            self.pendingSendPeer = nil
            self.pendingDecision = nil
            self.pendingDecisionToSend = nil
            self.actualSendCount = 0
            self.skippedDuplicateCount = 0
        }
    }

    // MARK: - 邀请设备

    func invitePeer(_ peer: MCPeerID, sessionIDs: [String]) {
        guard let browser, let session else {
            DispatchQueue.main.async { self.transferState = .failed("搜索未启动") }
            return
        }
        DispatchQueue.main.async {
            self.transferState = .connecting
            self.isSender = true
        }

        pendingSendIDs = sessionIDs
        pendingSendPeer = peer

        let context = TransferInvitationContext(
            sessionCount: sessionIDs.count,
            totalSize: 0,
            deviceName: UIDevice.current.name,
            sessionIDs: sessionIDs
        )
        let contextData = try? JSONEncoder().encode(context)

        browser.invitePeer(peer, to: session, withContext: contextData,
                           timeout: Constants.PeerTransfer.transferTimeout)
        stopBrowsing()
        os.Logger.peerTransfer.info("已邀请设备: \(peer.displayName)")
    }

    // MARK: - 发送

    func sendSessions(ids: [String], to peer: MCPeerID) {
        guard let session, session.connectedPeers.contains(peer) else {
            DispatchQueue.main.async {
                self.transferState = .failed("设备未连接，请重试")
            }
            return
        }

        beginBackgroundTask()

        // 根据决策过滤IDs
        var idsToSend = ids
        var skippedCount = 0
        if let decision = pendingDecision {
            if decision.skipDuplicates {
                let existingSet = Set(decision.existingIDs)
                idsToSend = ids.filter { !existingSet.contains($0) }
            }
            skippedCount = ids.count - idsToSend.count
            pendingDecision = nil  // 清理决策
        }

        // 发布去重结果供 UI 展示
        DispatchQueue.main.async {
            self.actualSendCount = idsToSend.count
            self.skippedDuplicateCount = skippedCount
        }

        // 如果没有需要传输的记录
        if idsToSend.isEmpty {
            os.Logger.peerTransfer.info("无需传输: 全部 \(ids.count) 条已存在")
            DispatchQueue.main.async {
                self.transferState = .completed(imported: 0, skipped: skippedCount)
            }
            return
        }

        DispatchQueue.main.async {
            self.transferState = .preparing
            self.transferProgress = 0
        }
        UIApplication.shared.isIdleTimerDisabled = true

        Task {
            do {
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent(Constants.PeerTransfer.zipTempPrefix + UUID().uuidString)

                let exportResult = SessionRecordManager.shared.exportSelectedSessions(
                    idsToSend, to: tempDir, isAllSelected: false
                )
                guard exportResult.success else {
                    throw NSError(domain: Constants.ErrorInfo.domain, code: Constants.ErrorInfo.defaultCode,
                                  userInfo: [NSLocalizedDescriptionKey: exportResult.errorMessage ?? "导出失败"])
                }

                let archiveURL = try archiveDirectory(source: tempDir)
                try? FileManager.default.removeItem(at: tempDir)

                DispatchQueue.main.async {
                    self.transferState = .transferring
                }

                let progress = session.sendResource(at: archiveURL, withName: "transfer.ptarchive", toPeer: peer) { [weak self] error in
                    try? FileManager.default.removeItem(at: archiveURL)
                    DispatchQueue.main.async {
                        UIApplication.shared.isIdleTimerDisabled = false
                        self?.cancelBackgroundTask()
                        if let error {
                            os.Logger.peerTransfer.error("传输失败: \(error.localizedDescription)")
                            self?.transferState = .failed("传输失败，请重试")
                        } else {
                            os.Logger.peerTransfer.info("传输完成: \(idsToSend.count) 条")
                            self?.transferState = .completed(imported: idsToSend.count, skipped: skippedCount)
                        }
                    }
                }

                if let progress {
                    let observer = progress.observe(\.fractionCompleted) { prog, _ in
                        let fraction = prog.fractionCompleted
                        DispatchQueue.main.async {
                            PeerTransferManager.shared.transferProgress = fraction
                        }
                    }
                    DispatchQueue.main.async {
                        self.transferProgressObserver = observer
                    }
                }

            } catch {
                DispatchQueue.main.async {
                    UIApplication.shared.isIdleTimerDisabled = false
                    self.cancelBackgroundTask()
                    os.Logger.peerTransfer.error("打包失败: \(error.localizedDescription)")
                    self.transferState = .failed("数据打包失败，请重试")
                }
            }
        }
    }

    // MARK: - 取消

    func cancelTransfer() {
        os.Logger.peerTransfer.info("用户取消传输")

        let tempDir = FileManager.default.temporaryDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for item in contents where item.lastPathComponent.hasPrefix(Constants.PeerTransfer.zipTempPrefix) {
                try? FileManager.default.removeItem(at: item)
            }
        }

        UIApplication.shared.isIdleTimerDisabled = false
        cancelBackgroundTask()
        teardownSession()

        DispatchQueue.main.async {
            self.transferState = .idle
            self.transferProgress = 0
            self.isSender = false
            self.pendingSendIDs = []
            self.pendingSendPeer = nil
            self.discoveredPeers = []
            self.pendingDecision = nil
            self.pendingDecisionToSend = nil
            self.actualSendCount = 0
            self.skippedDuplicateCount = 0
            self.decisionTimeoutTimer?.invalidate()
            self.decisionTimeoutTimer = nil
        }
    }

    /// 接收方：设置去重统计（接受邀请时由 UI 调用）
    func setReceiverDedupInfo(totalCount: Int, skipDuplicates: Bool, duplicateCount: Int) {
        DispatchQueue.main.async {
            self.actualSendCount = skipDuplicates ? totalCount - duplicateCount : totalCount
            self.skippedDuplicateCount = skipDuplicates ? duplicateCount : 0
        }
    }

    // MARK: - 决策消息传输

    /// 发送决策到发送方（接收方调用）
    private func sendDecision(_ decision: TransferConflictDecision, to peer: MCPeerID) {
        guard let session, session.connectedPeers.contains(peer) else { return }
        do {
            let data = try JSONEncoder().encode(decision)
            try session.send(data, toPeers: [peer], with: .reliable)
            os.Logger.peerTransfer.info("已发送决策: skipDuplicates=\(decision.skipDuplicates), existingCount=\(decision.existingIDs.count)")
        } catch {
            os.Logger.peerTransfer.error("发送决策失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 归档工具（iOS 兼容，流式写入）

    // 格式：[count:UInt32][entry...]，每个 entry: [pathLen:UInt32][path:UTF8][dataLen:UInt64][data]
    // 流式写入：逐个文件读取并写入归档，内存中同一时刻只持有一个文件的数据
    func archiveDirectory(source: URL) throws -> URL {
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(Constants.PeerTransfer.zipTempPrefix + UUID().uuidString + ".ptarchive")

        // 第一遍：收集相对路径和文件大小（不读内容）
        var filePaths: [(relativePath: String, fileURL: URL)] = []
        let basePath = source.path

        if let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let fileURL as URL in enumerator {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard resourceValues.isRegularFile == true else { continue }
                let relativePath = String(fileURL.path.dropFirst(basePath.count + 1))
                filePaths.append((relativePath: relativePath, fileURL: fileURL))
            }
        }

        // 创建输出流
        guard let outputStream = OutputStream(url: archiveURL, append: false) else {
            throw NSError(domain: Constants.ErrorInfo.domain, code: Constants.ErrorInfo.defaultCode,
                          userInfo: [NSLocalizedDescriptionKey: "无法创建归档文件"])
        }
        outputStream.open()
        defer { outputStream.close() }

        // 写入文件计数
        var count = UInt32(filePaths.count)
        try writeBytes(&count, count: 4, to: outputStream)

        // 逐文件流式写入
        for entry in filePaths {
            // 写入路径
            let pathData = Data(entry.relativePath.utf8)
            var pathLen = UInt32(pathData.count)
            try writeBytes(&pathLen, count: 4, to: outputStream)
            try writeData(pathData, to: outputStream)

            // 读取文件大小（不读内容）
            let attrs = try FileManager.default.attributesOfItem(atPath: entry.fileURL.path)
            let fileSize = (attrs[.size] as? UInt64) ?? 0
            var dataLen = fileSize
            try writeBytes(&dataLen, count: 8, to: outputStream)

            // 流式复制文件内容（分块读取，每块最大 256KB）
            guard let inputStream = InputStream(url: entry.fileURL) else { continue }
            inputStream.open()
            defer { inputStream.close() }

            try streamCopy(from: inputStream, to: outputStream)
        }

        return archiveURL
    }

    private func writeBytes(_ pointer: UnsafeMutableRawPointer, count: Int, to stream: OutputStream) throws {
        let bytes = pointer.bindMemory(to: UInt8.self, capacity: count)
        var written = 0
        while written < count {
            let result = stream.write(bytes + written, maxLength: count - written)
            if result < 0 { throw stream.streamError ?? NSError(domain: Constants.ErrorInfo.domain, code: Constants.ErrorInfo.defaultCode, userInfo: nil) }
            written += result
        }
    }

    /// 流式复制：从 inputStream 读取并写入 outputStream，每次最多 256KB
    /// length 为 nil 时读到 EOF；指定 length 时精确读取该字节数
    /// 在解压目录中查找实际的导出包目录（含 export_manifest.json 或 record.json）
    private func findImportDirectory(in directory: URL) throws -> URL {
        // 直接检查当前目录
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("export_manifest.json").path) ||
           FileManager.default.fileExists(atPath: directory.appendingPathComponent("record.json").path) {
            return directory
        }
        // 搜索一级子目录
        if let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) {
            for item in contents {
                let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey])
                guard resourceValues?.isDirectory == true else { continue }
                if FileManager.default.fileExists(atPath: item.appendingPathComponent("export_manifest.json").path) ||
                   FileManager.default.fileExists(atPath: item.appendingPathComponent("record.json").path) {
                    return item
                }
            }
        }
        // 未找到，返回原目录（让 importSessions 报告具体错误）
        return directory
    }

    private func streamCopy(from input: InputStream, to output: OutputStream, length: Int? = nil) throws {
        let bufferSize = 256 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var remaining = length ?? Int.max
        while remaining > 0 {
            let toRead = min(remaining, bufferSize)
            let bytesRead = input.read(buffer, maxLength: toRead)
            if bytesRead < 0 { throw input.streamError ?? NSError(domain: Constants.ErrorInfo.domain, code: Constants.ErrorInfo.defaultCode, userInfo: nil) }
            if bytesRead == 0 { break }
            var written = 0
            while written < bytesRead {
                let result = output.write(buffer + written, maxLength: bytesRead - written)
                if result < 0 { throw output.streamError ?? NSError(domain: Constants.ErrorInfo.domain, code: Constants.ErrorInfo.defaultCode, userInfo: nil) }
                written += result
            }
            if length != nil { remaining -= bytesRead }
        }
    }

    private func writeData(_ data: Data, to stream: OutputStream) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var written = 0
            while written < data.count {
                let result = stream.write(bytes + written, maxLength: data.count - written)
                if result < 0 { throw stream.streamError ?? NSError(domain: Constants.ErrorInfo.domain, code: Constants.ErrorInfo.defaultCode, userInfo: nil) }
                written += result
            }
        }
    }

    func unarchiveFile(source: URL, destination: URL) throws {
        // 流式读取解档
        guard let inputStream = InputStream(url: source) else {
            throw NSError(domain: Constants.ErrorInfo.domain, code: Constants.ErrorInfo.defaultCode,
                          userInfo: [NSLocalizedDescriptionKey: "无法打开归档文件"])
        }
        inputStream.open()
        defer { inputStream.close() }

        func readExact(_ count: Int) throws -> Data {
            var data = Data(count: count)
            var totalRead = 0
            try data.withUnsafeMutableBytes { rawBuffer in
                guard let bytes = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                while totalRead < count {
                    let result = inputStream.read(bytes + totalRead, maxLength: count - totalRead)
                    if result < 0 { throw inputStream.streamError ?? NSError(domain: Constants.ErrorInfo.domain, code: Constants.ErrorInfo.defaultCode, userInfo: nil) }
                    if result == 0 { throw NSError(domain: Constants.ErrorInfo.domain, code: Constants.ErrorInfo.defaultCode, userInfo: [NSLocalizedDescriptionKey: "归档文件不完整"]) }
                    totalRead += result
                }
            }
            return data
        }

        func readUInt32() throws -> UInt32 {
            let data = try readExact(4)
            return data.withUnsafeBytes { $0.load(as: UInt32.self) }
        }
        func readUInt64() throws -> UInt64 {
            let data = try readExact(8)
            return data.withUnsafeBytes { $0.load(as: UInt64.self) }
        }

        let count = try readUInt32()
        for _ in 0..<count {
            let pathLen = Int(try readUInt32())
            let pathData = try readExact(pathLen)
            guard let relativePath = String(data: pathData, encoding: .utf8) else { continue }

            let dataLen = Int(try readUInt64())

            let fileURL = destination.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)

            // 流式写出文件（分块，每块最大 256KB）
            guard let fileStream = OutputStream(url: fileURL, append: false) else { continue }
            fileStream.open()
            defer { fileStream.close() }

            try streamCopy(from: inputStream, to: fileStream, length: dataLen)
        }
    }
}

// MARK: - MCSessionDelegate

extension PeerTransferManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                os.Logger.peerTransfer.info("已连接: \(peerID.displayName)")
                if self.isSender {
                    // 发送方：设置决策等待超时（10秒）
                    self.decisionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
                        guard let self, self.pendingDecision == nil, !self.pendingSendIDs.isEmpty else { return }
                        os.Logger.peerTransfer.warning("等待决策超时，使用默认行为")
                        DispatchQueue.main.async {
                            if let sendPeer = self.pendingSendPeer, !self.pendingSendIDs.isEmpty {
                                self.sendSessions(ids: self.pendingSendIDs, to: sendPeer)
                                self.pendingSendIDs = []
                                self.pendingSendPeer = nil
                            }
                        }
                        self.decisionTimeoutTimer = nil
                    }
                } else {
                    // 接收方：发送决策到发送方
                    if let decision = self.pendingDecisionToSend {
                        self.sendDecision(decision, to: peerID)
                        self.pendingDecisionToSend = nil
                    }
                }
            case .connecting:
                os.Logger.peerTransfer.info("连接中: \(peerID.displayName)")
            case .notConnected:
                os.Logger.peerTransfer.info("断开连接: \(peerID.displayName)")
                self.decisionTimeoutTimer?.invalidate()
                self.decisionTimeoutTimer = nil
                if self.transferState == .transferring || self.transferState == .connecting {
                    self.transferState = .failed("连接中断，请靠近后重试")
                    UIApplication.shared.isIdleTimerDisabled = false
                    self.cancelBackgroundTask()
                }
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // 解析决策消息
        if let decision = try? JSONDecoder().decode(TransferConflictDecision.self, from: data) {
            os.Logger.peerTransfer.info("收到决策: skipDuplicates=\(decision.skipDuplicates), existingCount=\(decision.existingIDs.count)")
            DispatchQueue.main.async {
                // 取消超时定时器
                self.decisionTimeoutTimer?.invalidate()
                self.decisionTimeoutTimer = nil
                // 存储决策
                self.pendingDecision = decision
                // 开始传输
                if let sendPeer = self.pendingSendPeer, sendPeer == peerID, !self.pendingSendIDs.isEmpty {
                    self.sendSessions(ids: self.pendingSendIDs, to: peerID)
                    self.pendingSendIDs = []
                    self.pendingSendPeer = nil
                }
            }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        os.Logger.peerTransfer.info("开始接收: \(resourceName) from \(peerID.displayName)")
        DispatchQueue.main.async {
            self.transferState = .transferring
            UIApplication.shared.isIdleTimerDisabled = true
        }
        beginBackgroundTask()

        transferProgressObserver = progress.observe(\.fractionCompleted) { [weak self] prog, _ in
            DispatchQueue.main.async {
                self?.transferProgress = prog.fractionCompleted
            }
        }
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        transferProgressObserver?.invalidate()
        transferProgressObserver = nil

        guard let localURL, error == nil else {
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = false
                self.cancelBackgroundTask()
                os.Logger.peerTransfer.error("接收失败: \(error?.localizedDescription ?? "未知错误")")
                self.transferState = .failed("接收失败，请重试")
            }
            return
        }

        DispatchQueue.main.async {
            self.transferState = .importing
        }

        Task {
            do {
                // 检查磁盘空间
                let archiveSize = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0
                let freeSpace = (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? Int64) ?? 0
                if freeSpace < archiveSize * 2 {
                    throw NSError(domain: Constants.ErrorInfo.domain, code: Constants.ErrorInfo.defaultCode,
                                  userInfo: [NSLocalizedDescriptionKey: "设备存储空间不足，无法接收"])
                }

                let unpackDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent(Constants.PeerTransfer.zipTempPrefix + UUID().uuidString)
                try FileManager.default.createDirectory(at: unpackDir, withIntermediateDirectories: true)
                try unarchiveFile(source: localURL, destination: unpackDir)

                // exportSelectedSessions 在目标目录下创建子目录（如 PhotoTTS-P_YYMMDD/），
                // 需要找到包含 export_manifest.json 的实际导出目录传给 importSessions
                let importDir = try findImportDirectory(in: unpackDir)
                let result = SessionRecordManager.shared.importSessions(from: importDir)

                try? FileManager.default.removeItem(at: unpackDir)
                try? FileManager.default.removeItem(at: localURL)

                DispatchQueue.main.async {
                    UIApplication.shared.isIdleTimerDisabled = false
                    self.cancelBackgroundTask()
                    if result.success {
                        os.Logger.peerTransfer.info("导入完成: \(result.importedCount) 条, 跳过 \(result.skippedCount + result.duplicateCount) 条")
                        self.transferState = .completed(imported: result.importedCount, skipped: result.skippedCount + result.duplicateCount)
                        if result.importedCount > 0 {
                            NotificationCenter.default.post(name: Constants.NotificationNames.sessionsDidImport, object: nil)
                        }
                    } else {
                        os.Logger.peerTransfer.error("导入失败: \(result.errorMessage ?? "未知错误")")
                        self.transferState = .failed(result.errorMessage ?? "导入失败")
                    }
                }
            } catch {
                try? FileManager.default.removeItem(at: localURL)
                DispatchQueue.main.async {
                    UIApplication.shared.isIdleTimerDisabled = false
                    self.cancelBackgroundTask()
                    os.Logger.peerTransfer.error("解压失败: \(error.localizedDescription)")
                    self.transferState = .failed(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension PeerTransferManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {

        var invitationContext = TransferInvitationContext(sessionCount: 0, totalSize: 0, deviceName: peerID.displayName, sessionIDs: [])
        if let context, let decoded = try? JSONDecoder().decode(TransferInvitationContext.self, from: context) {
            invitationContext = decoded
        }

        // 检查本地已存在哪些重复 session
        let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "PeerTransfer.邀请检查")
        let localIDs = Set(allMetadata.map(\.id))
        let duplicateIDs = invitationContext.sessionIDs.filter { localIDs.contains($0) }

        DispatchQueue.main.async {
            self.pendingInvitation = TransferInvitation(
                peerID: peerID,
                context: invitationContext,
                existingIDs: duplicateIDs,
                handler: { [weak self] accept in
                    invitationHandler(accept, accept ? self?.session : nil)
                    if !accept {
                        DispatchQueue.main.async {
                            self?.pendingInvitation = nil
                        }
                    }
                }
            )
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        os.Logger.peerTransfer.error("广播启动失败: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension PeerTransferManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        os.Logger.peerTransfer.info("发现设备: \(peerID.displayName)")
        DispatchQueue.main.async {
            if !self.discoveredPeers.contains(where: { $0.displayName == peerID.displayName }) {
                self.discoveredPeers.append(peerID)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        os.Logger.peerTransfer.info("设备消失: \(peerID.displayName)")
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0.displayName == peerID.displayName }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        os.Logger.peerTransfer.error("搜索启动失败: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.transferState = .failed("搜索设备失败，请检查网络设置")
        }
    }
}
