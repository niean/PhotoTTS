import XCTest
@testable import PhotoTTS

final class ContinuousPlaybackTests: XCTestCase {

    /// 测试：从指定记录开始，收集名称前缀同日期的后续记录
    func testBuildSameDateQueue_normalCase() {
        // 名称前缀日期相同（26.03.26），但 createdAt 可能不同
        let metadataList: [SessionRecordMetadata] = [
            makeMetadata(id: "a", name: "26.03.26 小红帽"),
            makeMetadata(id: "b", name: "26.03.26 三只小猪"),
            makeMetadata(id: "c", name: "26.03.25 白雪公主"),  // 名称前缀日期不同
            makeMetadata(id: "d", name: "26.03.26 灰姑娘"),
        ]

        let queue = SessionRecordManager.buildSameDateQueue(from: "a", in: metadataList)
        // c 名称前缀日期不同停止，d 在 c 之后不可达
        XCTAssertEqual(queue, ["a", "b"])
    }

    /// 测试：从中间记录开始
    func testBuildSameDateQueue_startFromMiddle() {
        let metadataList: [SessionRecordMetadata] = [
            makeMetadata(id: "a", name: "26.03.26 小红帽"),
            makeMetadata(id: "b", name: "26.03.26 三只小猪"),
            makeMetadata(id: "c", name: "26.03.26 白雪公主"),
        ]

        let queue = SessionRecordManager.buildSameDateQueue(from: "b", in: metadataList)
        XCTAssertEqual(queue, ["b", "c"])
    }

    /// 测试：只有一条记录
    func testBuildSameDateQueue_singleRecord() {
        let metadataList: [SessionRecordMetadata] = [
            makeMetadata(id: "a", name: "26.03.26 小红帽"),
        ]

        let queue = SessionRecordManager.buildSameDateQueue(from: "a", in: metadataList)
        XCTAssertEqual(queue, ["a"])
    }

    /// 测试：起始 ID 不存在
    func testBuildSameDateQueue_idNotFound() {
        let metadataList: [SessionRecordMetadata] = [
            makeMetadata(id: "a", name: "26.03.26 小红帽"),
        ]

        let queue = SessionRecordManager.buildSameDateQueue(from: "nonexistent", in: metadataList)
        XCTAssertEqual(queue, [])
    }

    /// 测试：跳过 makeStatus 非 completed 的记录
    func testBuildSameDateQueue_skipIncomplete() {
        let metadataList: [SessionRecordMetadata] = [
            makeMetadata(id: "a", name: "26.03.26 小红帽", makeStatus: .completed),
            makeMetadata(id: "b", name: "26.03.26 三只小猪", makeStatus: .making),
            makeMetadata(id: "c", name: "26.03.26 白雪公主", makeStatus: .completed),
        ]

        let queue = SessionRecordManager.buildSameDateQueue(from: "a", in: metadataList)
        XCTAssertEqual(queue, ["a", "c"])
    }

    /// 测试：名称前缀格式不正确时回退到 createdAt
    func testBuildSameDateQueue_fallbackToCreatedAt() {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        // 名称无日期前缀，使用 createdAt 判断
        let metadataList: [SessionRecordMetadata] = [
            makeMetadata(id: "a", name: "无前缀名称", createdAt: today),
            makeMetadata(id: "b", name: "无前缀名称2", createdAt: today),
            makeMetadata(id: "c", name: "无前缀名称3", createdAt: yesterday),  // createdAt 不同
            makeMetadata(id: "d", name: "无前缀名称4", createdAt: today),
        ]

        let queue = SessionRecordManager.buildSameDateQueue(from: "a", in: metadataList)
        // c 的 createdAt 不同停止，d 在 c 之后不可达
        XCTAssertEqual(queue, ["a", "b"])
    }

    /// 测试：名称前缀日期与 createdAt 不同时，使用名称前缀日期
    func testBuildSameDateQueue_namePrefixOverridesCreatedAt() {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        // 名称前缀日期为今天，但 createdAt 为昨天
        let metadataList: [SessionRecordMetadata] = [
            makeMetadata(id: "a", name: "26.03.26 小红帽", createdAt: today),
            makeMetadata(id: "b", name: "26.03.26 三只小猪", createdAt: yesterday),  // 名称前缀日期相同
            makeMetadata(id: "c", name: "26.03.25 白雪公主", createdAt: today),  // 名称前缀日期不同
        ]

        let queue = SessionRecordManager.buildSameDateQueue(from: "a", in: metadataList)
        // b 名称前缀日期相同包含在内，c 名称前缀日期不同停止
        XCTAssertEqual(queue, ["a", "b"])
    }

    // MARK: - Helper

    private func makeMetadata(id: String, name: String, createdAt: Date? = nil, makeStatus: MakeStatus? = nil) -> SessionRecordMetadata {
        let date = createdAt ?? Date()
        return SessionRecordMetadata(
            id: id, name: name, createdAt: date, updatedAt: date,
            totalImageCount: 1, validImageCount: 1, textLength: 100,
            audioDuration: 10, avatarImageIndex: 0, storageSize: 1000,
            makeStatus: makeStatus
        )
    }
}
