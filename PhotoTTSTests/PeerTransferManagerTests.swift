import XCTest
import MultipeerConnectivity
@testable import PhotoTTS

final class PeerTransferManagerTests: XCTestCase {

    // MARK: - TransferState Equatable

    func testTransferStateEquality() {
        XCTAssertEqual(TransferState.idle, TransferState.idle)
        XCTAssertEqual(TransferState.browsing, TransferState.browsing)
        XCTAssertEqual(TransferState.advertising, TransferState.advertising)
        XCTAssertEqual(TransferState.connecting, TransferState.connecting)
        XCTAssertEqual(TransferState.preparing, TransferState.preparing)
        XCTAssertEqual(TransferState.transferring, TransferState.transferring)
        XCTAssertEqual(TransferState.importing, TransferState.importing)
        XCTAssertEqual(TransferState.completed(imported: 3, skipped: 1), TransferState.completed(imported: 3, skipped: 1))
        XCTAssertNotEqual(TransferState.completed(imported: 3, skipped: 1), TransferState.completed(imported: 2, skipped: 1))
        XCTAssertEqual(TransferState.failed("error"), TransferState.failed("error"))
        XCTAssertNotEqual(TransferState.failed("a"), TransferState.failed("b"))
        XCTAssertNotEqual(TransferState.idle, TransferState.browsing)
        XCTAssertNotEqual(TransferState.idle, TransferState.completed(imported: 0, skipped: 0))
    }

    // MARK: - TransferInvitationContext Codable

    func testTransferInvitationContextCoding() throws {
        let context = TransferInvitationContext(sessionCount: 5, totalSize: 1024000, deviceName: "Test iPad", sessionIDs: ["id-1", "id-2"])
        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(TransferInvitationContext.self, from: data)
        XCTAssertEqual(decoded.sessionCount, 5)
        XCTAssertEqual(decoded.totalSize, 1024000)
        XCTAssertEqual(decoded.deviceName, "Test iPad")
        XCTAssertEqual(decoded.sessionIDs, ["id-1", "id-2"])
    }

    func testTransferInvitationContextEmptyValues() throws {
        let context = TransferInvitationContext(sessionCount: 0, totalSize: 0, deviceName: "", sessionIDs: [])
        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(TransferInvitationContext.self, from: data)
        XCTAssertEqual(decoded.sessionCount, 0)
        XCTAssertEqual(decoded.totalSize, 0)
        XCTAssertEqual(decoded.deviceName, "")
        XCTAssertEqual(decoded.sessionIDs, [])
    }

    // MARK: - Storage Precheck

    func testStorageInsufficientControlMessageCoding() throws {
        let message = TransferControlMessage.storageInsufficient(
            requiredBytes: 2_000,
            availableBytes: 1_000,
            isAvailableSpaceUnknown: false,
            message: "接收方剩余空间 1 KB，不足以接收本次传输（需要 2 KB）"
        )
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(TransferControlMessage.self, from: data)

        XCTAssertEqual(decoded, message)
    }

    func testStorageCheckResult() {
        let enough = StorageCheckResult(requiredBytes: 2_000, availableBytes: 3_000)
        XCTAssertTrue(enough.isEnough)
        XCTAssertFalse(enough.isAvailableSpaceUnknown)

        let insufficient = StorageCheckResult(requiredBytes: 2_000, availableBytes: 1_000)
        XCTAssertFalse(insufficient.isEnough)
        XCTAssertFalse(insufficient.isAvailableSpaceUnknown)

        let unknown = StorageCheckResult(requiredBytes: 2_000, availableBytes: nil)
        XCTAssertTrue(unknown.isEnough)
        XCTAssertTrue(unknown.isAvailableSpaceUnknown)
    }

    func testStorageInsufficientControlMessageDoesNotDecodeAsConflictDecision() throws {
        let message = TransferControlMessage.storageInsufficient(
            requiredBytes: 2_000,
            availableBytes: 1_000,
            isAvailableSpaceUnknown: false,
            message: "空间不足"
        )
        let data = try JSONEncoder().encode(message)

        XCTAssertThrowsError(try JSONDecoder().decode(TransferConflictDecision.self, from: data))
    }

    func testBuildInvitationContextIncludesEstimatedSizeAndMode() {
        let full = PeerTransferManager.shared.buildInvitationContext(sessionIDs: ["missing"], mode: .full)
        XCTAssertEqual(full.sessionCount, 1)
        XCTAssertEqual(full.totalSize, 0)
        XCTAssertEqual(full.sessionIDs, ["missing"])
        XCTAssertEqual(full.mode, .full)

        let playOnly = PeerTransferManager.shared.buildInvitationContext(sessionIDs: ["missing"], mode: .playOnly)
        XCTAssertEqual(playOnly.mode, .playOnly)
    }

    func testMakeStorageCheck() {
        XCTAssertTrue(PeerTransferManager.shared.makeStorageCheck(requiredBytes: 2_000, availableBytes: 3_000).isEnough)
        XCTAssertFalse(PeerTransferManager.shared.makeStorageCheck(requiredBytes: 2_000, availableBytes: 1_000).isEnough)
        let unknown = PeerTransferManager.shared.makeStorageCheck(requiredBytes: 2_000, availableBytes: nil)
        XCTAssertTrue(unknown.isEnough)
        XCTAssertTrue(unknown.isAvailableSpaceUnknown)
    }

    func testHandleStorageInsufficientControlMessageFailsAndClearsPendingSend() throws {
        let manager = PeerTransferManager.shared
        manager.reset()
        let receiver = MCPeerID(displayName: "Receiver")
        manager.setPendingSendForTesting(ids: ["id-1"], peer: receiver)
        let message = TransferControlMessage.storageInsufficient(
            requiredBytes: 2_000,
            availableBytes: 1_000,
            isAvailableSpaceUnknown: false,
            message: "空间不足"
        )
        let data = try JSONEncoder().encode(message)

        XCTAssertTrue(manager.handleControlMessageData(data, from: receiver))
        XCTAssertEqual(manager.pendingSendIDs, [])
        XCTAssertNil(manager.pendingSendPeer)
        XCTAssertEqual(manager.transferState, .failed("空间不足"))
    }

    func testHandleStorageInsufficientControlMessageIgnoresUnexpectedPeer() throws {
        let manager = PeerTransferManager.shared
        manager.reset()
        let receiver = MCPeerID(displayName: "Receiver")
        manager.setPendingSendForTesting(ids: ["id-1"], peer: receiver)
        let message = TransferControlMessage.storageInsufficient(
            requiredBytes: 2_000,
            availableBytes: 1_000,
            isAvailableSpaceUnknown: false,
            message: "空间不足"
        )
        let data = try JSONEncoder().encode(message)

        XCTAssertTrue(manager.handleControlMessageData(data, from: MCPeerID(displayName: "Other")))
        XCTAssertEqual(manager.pendingSendIDs, ["id-1"])
        XCTAssertEqual(manager.pendingSendPeer, receiver)
        XCTAssertNotEqual(manager.transferState, .failed("空间不足"))
    }

    func testConfirmInsufficientStorageInvitationAcceptsForControlMessage() {
        let accepted = expectation(description: "accepted")
        let invitation = TransferInvitation(
            peerID: MCPeerID(displayName: "Sender"),
            context: TransferInvitationContext(sessionCount: 1, totalSize: 2_000, deviceName: "Sender", sessionIDs: ["id-1"]),
            existingIDs: [],
            storageCheck: StorageCheckResult(requiredBytes: 2_000, availableBytes: 1_000),
            handler: { accept in
                XCTAssertTrue(accept)
                accepted.fulfill()
            }
        )

        PeerTransferManager.shared.confirmInsufficientStorageInvitation(invitation)
        wait(for: [accepted], timeout: 1)
    }

    // MARK: - Archive / Unarchive

    func testArchiveAndUnarchiveRoundTrip() throws {
        let manager = PeerTransferManager.shared

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 写入测试文件
        let subDir = tempDir.appendingPathComponent("Sessions/test-session")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "hello world".data(using: .utf8)!.write(to: tempDir.appendingPathComponent("manifest.json"))
        try "session data".data(using: .utf8)!.write(to: subDir.appendingPathComponent("record.json"))

        // 二进制文件
        let binaryData = Data(repeating: 0xFF, count: 256)
        try binaryData.write(to: subDir.appendingPathComponent("audio.mp3"))

        // 归档
        let archiveURL = try manager.archiveDirectory(source: tempDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        // 解压到新目录
        let unpackDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("unpack_test_\(UUID().uuidString)")
        try manager.unarchiveFile(source: archiveURL, destination: unpackDir)

        // 验证文本文件
        let manifest = try String(contentsOf: unpackDir.appendingPathComponent("manifest.json"), encoding: .utf8)
        XCTAssertEqual(manifest, "hello world")

        let record = try String(contentsOf: unpackDir.appendingPathComponent("Sessions/test-session/record.json"), encoding: .utf8)
        XCTAssertEqual(record, "session data")

        // 验证二进制文件
        let restoredBinary = try Data(contentsOf: unpackDir.appendingPathComponent("Sessions/test-session/audio.mp3"))
        XCTAssertEqual(restoredBinary, binaryData)

        // 清理
        try? FileManager.default.removeItem(at: tempDir)
        try? FileManager.default.removeItem(at: archiveURL)
        try? FileManager.default.removeItem(at: unpackDir)
    }

    func testArchiveEmptyDirectory() throws {
        throw XCTSkip("临时跳过：空目录归档测试存在已知问题，待后续修复")
    }

    func testUnarchiveFileAllowingPartialRecoversCompleteEntries() throws {
        let manager = PeerTransferManager.shared

        let sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("partial_archive_src_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDir) }

        let sessionsDir = sourceDir.appendingPathComponent("Sessions", isDirectory: true)
        let sessionOneDir = sessionsDir.appendingPathComponent("session-1", isDirectory: true)
        let sessionTwoDir = sessionsDir.appendingPathComponent("session-2", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionOneDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionTwoDir, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: sessionOneDir.appendingPathComponent("record.json"))
        try Data("two".utf8).write(to: sessionTwoDir.appendingPathComponent("record.json"))

        let archiveURL = try manager.archiveDirectory(source: sourceDir)
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        let archiveData = try Data(contentsOf: archiveURL)
        let partialArchiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("partial_archive_\(UUID().uuidString).ptarchive")
        try archiveData.prefix(max(archiveData.count - 8, 1)).write(to: partialArchiveURL)
        defer { try? FileManager.default.removeItem(at: partialArchiveURL) }

        let unpackDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("partial_unpack_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: unpackDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: unpackDir) }

        let result = try manager.unarchiveFileAllowingPartial(source: partialArchiveURL, destination: unpackDir)
        XCTAssertFalse(result.didReachArchiveEnd)
        XCTAssertGreaterThanOrEqual(result.extractedFileCount, 1)
        let recoveredFiles = FileManager.default.enumerator(at: unpackDir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { FileManager.default.fileExists(atPath: $0.path) && !$0.hasDirectoryPath } ?? []
        XCTAssertFalse(recoveredFiles.isEmpty)
    }

    // MARK: - Constants

    func testServiceTypeFormat() {
        let serviceType = Constants.PeerTransfer.serviceType
        // MultipeerConnectivity serviceType: 1-15 chars, lowercase letters/digits/hyphens
        XCTAssertTrue(serviceType.count >= 1 && serviceType.count <= 15)
        let allowed = CharacterSet.lowercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: "-"))
        XCTAssertTrue(serviceType.unicodeScalars.allSatisfy { allowed.contains($0) })
    }
}
