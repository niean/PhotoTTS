import XCTest
@testable import PhotoTTS

/// 播放事件落盘与读取回环验证（Bug: 计划内播完后状态未更新）
final class PlayHistoryManagerTests: XCTestCase {

    /// 测试：recordPlay 写入的播放事件可被 loadPlayStats / loadAllSessionHistories 读回
    func testRecordPlayPersistsAndReloadsPlayEvent() throws {
        let id = "test-play-history-\(UUID().uuidString)"
        let record = SessionRecord(
            id: id,
            name: "26.10.24 回环验证",
            createdAt: Date(),
            updatedAt: Date(),
            imageDataList: [],
            ocrText: "回环验证",
            ocrTextSegments: ["回环验证"],
            audioDataBase64: "",
            audioFormat: "mp3",
            audioSegments: [],
            audioDuration: 1,
            ocrDuration: 1,
            llmDuration: 0,
            ttsDuration: 1,
            validImageCount: 1,
            totalImageCount: 1,
            textLength: 4,
            audioSize: 0,
            voiceSettings: nil,
            avatarImageIndex: 0,
            storageSize: 0,
            makeStatus: .completed,
            storyHighlights: nil,
            hasVirtualPage: false,
            animationStyle: .rightToLeft,
            coverImagePath: nil
        )
        let saved = SessionRecordManager.shared.saveSession(record)
        XCTAssertTrue(saved.success)
        defer { _ = SessionRecordManager.shared.deleteSession(id: id) }

        let playedAt = Date()
        PlayHistoryManager.shared.recordPlay(sessionId: id, name: record.name, playedAt: playedAt)

        // 读回路径1：loadPlayStats（首页/管理状态判断来源）
        let stats = SessionRecordManager.shared.loadPlayStats(sessionIds: [id])
        XCTAssertNotNil(stats[id], "播放事件应能被 loadPlayStats 读回")

        // 读回路径2：loadAllSessionHistories（播放历史页面数据来源）
        let histories = SessionRecordManager.shared.loadAllSessionHistories()
        let entry = histories.first { $0.id == id }
        XCTAssertNotNil(entry, "会话历史应能被聚合读回")
        XCTAssertEqual(entry?.history.playEvents.count, 1)
    }
}
