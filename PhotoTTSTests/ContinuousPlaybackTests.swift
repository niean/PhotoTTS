import XCTest
@testable import PhotoTTS

final class ContinuousPlaybackTests: XCTestCase {

    /// 测试：从指定记录开始，收集同日期的后续记录
    func testBuildSameDateQueue_normalCase() {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        let metadataList: [SessionRecordMetadata] = [
            makeMetadata(id: "a", createdAt: today),
            makeMetadata(id: "b", createdAt: today),
            makeMetadata(id: "c", createdAt: yesterday),
            makeMetadata(id: "d", createdAt: today),
        ]

        let queue = SessionRecordManager.buildSameDateQueue(from: "a", in: metadataList)
        // c 跨天停止，d 在 c 之后不可达
        XCTAssertEqual(queue, ["a", "b"])
    }

    /// 测试：从中间记录开始
    func testBuildSameDateQueue_startFromMiddle() {
        let today = Date()
        let metadataList: [SessionRecordMetadata] = [
            makeMetadata(id: "a", createdAt: today),
            makeMetadata(id: "b", createdAt: today),
            makeMetadata(id: "c", createdAt: today),
        ]

        let queue = SessionRecordManager.buildSameDateQueue(from: "b", in: metadataList)
        XCTAssertEqual(queue, ["b", "c"])
    }

    /// 测试：只有一条记录
    func testBuildSameDateQueue_singleRecord() {
        let today = Date()
        let metadataList: [SessionRecordMetadata] = [
            makeMetadata(id: "a", createdAt: today),
        ]

        let queue = SessionRecordManager.buildSameDateQueue(from: "a", in: metadataList)
        XCTAssertEqual(queue, ["a"])
    }

    /// 测试：起始 ID 不存在
    func testBuildSameDateQueue_idNotFound() {
        let today = Date()
        let metadataList: [SessionRecordMetadata] = [
            makeMetadata(id: "a", createdAt: today),
        ]

        let queue = SessionRecordManager.buildSameDateQueue(from: "nonexistent", in: metadataList)
        XCTAssertEqual(queue, [])
    }

    /// 测试：跳过 makeStatus 非 completed 的记录
    func testBuildSameDateQueue_skipIncomplete() {
        let today = Date()
        let metadataList: [SessionRecordMetadata] = [
            makeMetadata(id: "a", createdAt: today, makeStatus: .completed),
            makeMetadata(id: "b", createdAt: today, makeStatus: .making),
            makeMetadata(id: "c", createdAt: today, makeStatus: .completed),
        ]

        let queue = SessionRecordManager.buildSameDateQueue(from: "a", in: metadataList)
        XCTAssertEqual(queue, ["a", "c"])
    }

    // MARK: - Helper

    private func makeMetadata(id: String, createdAt: Date, makeStatus: MakeStatus? = nil) -> SessionRecordMetadata {
        SessionRecordMetadata(
            id: id, name: "Test", createdAt: createdAt, updatedAt: createdAt,
            totalImageCount: 1, validImageCount: 1, textLength: 100,
            audioDuration: 10, avatarImageIndex: 0, storageSize: 1000,
            makeStatus: makeStatus
        )
    }
}
