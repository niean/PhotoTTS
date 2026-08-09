import XCTest
@testable import PhotoTTS

final class RecordAnalysisSnapshotTests: XCTestCase {

    // MARK: - Helpers

    /// 构造属于指定系列的 N 条记录元数据，名称格式 "26.08.09 {series}-第i章"
    private func makeMetadata(series: String, count: Int) -> [SessionRecordMetadata] {
        (0..<count).map { i in
            SessionRecordMetadata(
                id: "\(series)-\(i)",
                name: "26.08.09 \(series)-第\(i + 1)章",
                createdAt: Date(),
                updatedAt: Date(),
                totalImageCount: 1,
                validImageCount: 1,
                textLength: 10,
                audioDuration: 10,
                avatarImageIndex: 0,
                storageSize: 100
            )
        }
    }

    /// 构造无法解析系列名的记录（名称无日期前缀，seriesName 解析为"未分类"）
    private func makeUncategorized(count: Int) -> [SessionRecordMetadata] {
        (0..<count).map { i in
            SessionRecordMetadata(
                id: "uncategorized-\(i)",
                name: "杂项记录\(i)",
                createdAt: Date(),
                updatedAt: Date(),
                totalImageCount: 1,
                validImageCount: 1,
                textLength: 10,
                audioDuration: 10,
                avatarImageIndex: 0,
                storageSize: 100
            )
        }
    }

    private func item(
        _ snapshot: [RecordAnalysisSnapshot.SeriesItem],
        named name: String
    ) -> RecordAnalysisSnapshot.SeriesItem? {
        snapshot.first { $0.name == name }
    }

    // MARK: - 阈值规则（>= 阈值单独展示，< 阈值归并到"其它"）

    func testSeriesAtThresholdShownStandalone() {
        // 系列恰好 5 本（= 阈值）应单独展示，不产生"其它"
        let metadata = makeMetadata(series: "小红帽", count: 5)
        let items = RecordAnalysisSnapshot.buildSeriesItems(metadataList: metadata, statsMap: [:])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(item(items, named: "小红帽")?.totalCount, 5)
        XCTAssertNil(item(items, named: "其它"))
    }

    func testSeriesAboveThresholdShownStandalone() {
        let metadata = makeMetadata(series: "小红帽", count: 8)
        let items = RecordAnalysisSnapshot.buildSeriesItems(metadataList: metadata, statsMap: [:])

        XCTAssertEqual(item(items, named: "小红帽")?.totalCount, 8)
        XCTAssertNil(item(items, named: "其它"))
    }

    func testSeriesBelowThresholdMergedIntoOther() {
        // 系列仅 4 本（< 阈值）应整体归并到"其它"
        let metadata = makeMetadata(series: "小系列", count: 4)
        let items = RecordAnalysisSnapshot.buildSeriesItems(metadataList: metadata, statsMap: [:])

        XCTAssertNil(item(items, named: "小系列"))
        XCTAssertEqual(item(items, named: "其它")?.totalCount, 4)
    }

    func testMixedSeriesMergeAndStandalone() {
        // 混合：达标系列单独展示，未达标系列归并到"其它"
        let metadata = makeMetadata(series: "小红帽", count: 6)
            + makeMetadata(series: "大灰狼", count: 5)
            + makeMetadata(series: "小猫", count: 2)
            + makeMetadata(series: "小狗", count: 3)
        let items = RecordAnalysisSnapshot.buildSeriesItems(metadataList: metadata, statsMap: [:])

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(item(items, named: "小红帽")?.totalCount, 6)
        XCTAssertEqual(item(items, named: "大灰狼")?.totalCount, 5)
        XCTAssertNil(item(items, named: "小猫"))
        XCTAssertNil(item(items, named: "小狗"))
        XCTAssertEqual(item(items, named: "其它")?.totalCount, 5)  // 2 + 3
    }

    // MARK: - 排序

    func testStandaloneSeriesSortedByCountDesc() {
        let metadata = makeMetadata(series: "较少", count: 5)
            + makeMetadata(series: "较多", count: 10)
        let items = RecordAnalysisSnapshot.buildSeriesItems(metadataList: metadata, statsMap: [:])

        XCTAssertEqual(items.first?.name, "较多")
        XCTAssertEqual(items.last?.name, "较少")
    }

    // MARK: - 未分类归并

    func testUncategorizedMergedIntoOther() {
        // 无系列名的记录归入"其它"，不应作为独立系列出现
        let metadata = makeMetadata(series: "小红帽", count: 5)
            + makeUncategorized(count: 3)
        let items = RecordAnalysisSnapshot.buildSeriesItems(metadataList: metadata, statsMap: [:])

        XCTAssertEqual(item(items, named: "小红帽")?.totalCount, 5)
        XCTAssertEqual(item(items, named: "其它")?.totalCount, 3)
        XCTAssertNil(item(items, named: "未分类"))
    }

    // MARK: - 边界

    func testEmptyInputReturnsEmpty() {
        let items = RecordAnalysisSnapshot.buildSeriesItems(metadataList: [], statsMap: [:])
        XCTAssertTrue(items.isEmpty)
    }

    func testOtherOmittedWhenAllStandalone() {
        // 所有系列均达标且无未分类时，不应出现"其它"
        let metadata = makeMetadata(series: "小红帽", count: 5)
        let items = RecordAnalysisSnapshot.buildSeriesItems(metadataList: metadata, statsMap: [:])

        XCTAssertNil(item(items, named: "其它"))
    }

    // MARK: - 已读计数

    func testReadCountPropagatedToStandaloneAndOther() {
        let red = makeMetadata(series: "小红帽", count: 5)    // 已读 2
        let small = makeMetadata(series: "小猫", count: 3)     // 已读 1，归并到"其它"
        let all = red + small
        var statsMap: [String: PlayStatInfo] = [:]
        statsMap[red[0].id] = PlayStatInfo(lastPlayedAt: Date(), playCount: 1)
        statsMap[red[1].id] = PlayStatInfo(lastPlayedAt: Date(), playCount: 1)
        statsMap[small[0].id] = PlayStatInfo(lastPlayedAt: Date(), playCount: 1)

        let items = RecordAnalysisSnapshot.buildSeriesItems(metadataList: all, statsMap: statsMap)

        XCTAssertEqual(item(items, named: "小红帽")?.readCount, 2)
        XCTAssertEqual(item(items, named: "其它")?.readCount, 1)
    }
}
