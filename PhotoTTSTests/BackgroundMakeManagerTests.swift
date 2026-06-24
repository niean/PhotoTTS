import XCTest
import UIKit
@testable import PhotoTTS

/// BackgroundMakeManager 多任务并发语义测试
/// 本套件聚焦容量/索引/清理的纯内存语义，不验证 Coordinator 真实 I/O 流程
final class BackgroundMakeManagerTests: XCTestCase {

    private let manager = BackgroundMakeManager.shared
    private var deferredDraftIDs: [String] = []

    override func setUp() {
        super.setUp()
        // 清理残留任务（容错前一测试异常退出）
        for (id, _) in manager.tasks {
            manager.removeTask(sessionId: id)
        }
    }

    override func tearDown() {
        for (id, _) in manager.tasks {
            manager.removeTask(sessionId: id)
        }
        for id in deferredDraftIDs {
            _ = SessionRecordManager.shared.deleteSession(id: id)
        }
        deferredDraftIDs.removeAll()
        super.tearDown()
    }

    /// 初始状态应无活跃任务、容量充足
    func testInitialStateHasCapacity() {
        XCTAssertEqual(manager.activeTaskCount, 0, "initial activeTaskCount should be 0")
        XCTAssertTrue(manager.hasCapacity, "initial should have capacity")
        XCTAssertFalse(manager.hasAnyActiveTask, "initial should have no active task")
    }

    /// 手动注入达到并发上限数量的未完成任务后，hasCapacity 应返回 false
    func testCapacityLimitAtConfiguredTaskCount() {
        // 手动注入：模拟达到并发上限数量的未完成任务（直接写 tasks 字典）
        // 避免走 startMaking 的磁盘 I/O，仅验证容量门
        let ids = (1...Constants.BackgroundMake.maxConcurrentTasks).map { "unit-task-\($0)" }
        for id in ids {
            let t = MakeTask(sessionId: id, imageCount: 1)
            manager.tasks[id] = t
        }
        XCTAssertEqual(
            manager.activeTaskCount,
            Constants.BackgroundMake.maxConcurrentTasks,
            "after inject maxConcurrentTasks, activeCount should reach the configured limit"
        )
        XCTAssertFalse(manager.hasCapacity, "active tasks at the configured limit should fill capacity")
        XCTAssertTrue(manager.hasAnyActiveTask)

        // 标记 1 个完成，容量恢复
        if let t = manager.tasks[ids[0]] {
            t.markFailed(error: NSError(domain: "unit", code: -1))
        }
        XCTAssertEqual(
            manager.activeTaskCount,
            Constants.BackgroundMake.maxConcurrentTasks - 1,
            "failed task should not count as active"
        )
        XCTAssertTrue(manager.hasCapacity, "after one completed, capacity should recover")
    }

    /// task(for:) 应按 id 精准返回；activeTask(for:) 过滤已完成任务
    func testTaskLookupByIdSemantics() {
        let activeId = "lookup-active"
        let completedId = "lookup-completed"

        let active = MakeTask(sessionId: activeId, imageCount: 1)
        let completed = MakeTask(sessionId: completedId, imageCount: 1)
        completed.markFailed(error: NSError(domain: "unit", code: -1))

        manager.tasks[activeId] = active
        manager.tasks[completedId] = completed

        XCTAssertNotNil(manager.task(for: activeId), "task(for:) should return active task")
        XCTAssertNotNil(manager.task(for: completedId), "task(for:) should also return completed task")
        XCTAssertNotNil(manager.activeTask(for: activeId), "activeTask(for:) should return only when not completed")
        XCTAssertNil(manager.activeTask(for: completedId), "activeTask(for:) should be nil for completed task")
        XCTAssertNil(manager.task(for: "non-existent-id"), "task(for:) should return nil for unknown id")
    }

    /// removeTask 按 id 精准移除，不影响其它任务
    func testRemoveTaskIsolatedById() {
        let keepId = "keep-me"
        let removeId = "remove-me"
        manager.tasks[keepId] = MakeTask(sessionId: keepId, imageCount: 1)
        manager.tasks[removeId] = MakeTask(sessionId: removeId, imageCount: 1)

        manager.removeTask(sessionId: removeId)
        XCTAssertNil(manager.tasks[removeId], "removed task should be gone")
        XCTAssertNotNil(manager.tasks[keepId], "other task should remain")
    }

    /// 从 LLM/TTS 阶段重跑时，应保留已完成阶段的中间结果和耗时，供状态页展示和最终持久化复用
    func testMakeTaskCanSeedExistingStageSnapshotForRemake() {
        let task = MakeTask(sessionId: "seed-existing-results", imageCount: 2)
        var intermediate = IntermediateResults()
        intermediate.ocrTexts = ["第一页", "第二页"]
        intermediate.validImageCount = 2
        intermediate.totalImageCount = 2
        intermediate.ocrCompletedCount = 2
        intermediate.ocrCharCount = 6
        intermediate.ocrDuration = 1.25
        intermediate.llmStoryName = "故事名"
        intermediate.llmHighlights = "故事要点"
        intermediate.llmCharCount = 7
        intermediate.llmDuration = 0.85
        intermediate.llmStatus = .completed

        task.seedExistingResults(
            intermediateResults: intermediate,
            ocrText: intermediate.ocrTexts.joined(separator: Constants.ocrTextSeparator),
            ocrTextSegments: intermediate.ocrTexts,
            ocrDuration: intermediate.ocrDuration,
            llmDuration: intermediate.llmDuration,
            ttsDuration: 0
        )

        XCTAssertEqual(task.ocrTextSegments, ["第一页", "第二页"])
        XCTAssertEqual(task.ocrText, "第一页\(Constants.ocrTextSeparator)第二页")
        XCTAssertEqual(task.ocrDuration, 1.25, accuracy: 0.001)
        XCTAssertEqual(task.llmDuration, 0.85, accuracy: 0.001)
        XCTAssertEqual(task.intermediateResults?.llmStoryName, "故事名")
        XCTAssertEqual(task.intermediateResults?.llmHighlights, "故事要点")
        XCTAssertEqual(task.intermediateResults?.ocrTexts, ["第一页", "第二页"])
    }

    /// 并发排队时保持 0%，真正进入 OCR 后立即显示 1%，便于 UI 区分等待与制作中
    func testMakeTaskProgressSeparatesQueuedAndOCRStarted() {
        let task = MakeTask(sessionId: "ocr-progress-start", imageCount: 3)

        XCTAssertEqual(task.progress, 0, accuracy: 0.0001, "queued task should stay at 0% before OCR starts")

        task.updateProgress(
            ProcessingProgress(
                stage: .ocr,
                currentStep: 1,
                totalSteps: 100,
                message: "OCR识别进度: 0/3",
                percentage: 1,
                stageResults: StageResults(
                    ocrTexts: [],
                    validImageCount: nil,
                    llmStoryName: nil,
                    llmHighlights: nil,
                    totalImageCount: 3,
                    ocrCompletedCount: 0,
                    ocrCharCount: nil,
                    ocrDuration: nil,
                    llmCharCount: nil,
                    llmDuration: nil,
                    llmStatus: nil
                )
            )
        )

        XCTAssertEqual(task.progress, 0.01, accuracy: 0.0001, "task should move to 1% once OCR actually starts")
        XCTAssertEqual(task.intermediateResults?.totalImageCount, 3)
        XCTAssertEqual(task.intermediateResults?.ocrCompletedCount, 0)
    }

    /// 并发上限常量符合 spec 约定（10）
    func testConcurrencyLimitConstant() {
        XCTAssertEqual(Constants.BackgroundMake.maxConcurrentTasks, 10, "spec contract: maxConcurrentTasks == 10")
    }

    func testDraftPreservesOCRResultsAndIncompleteStatusAfterLLMFailure() {
        let sessionId = "llm-failure-draft-\(UUID().uuidString)"
        deferredDraftIDs.append(sessionId)
        let image = makeTestImage()
        let ocrTexts = ["第一页文字", "第二页文字"]
        let combinedText = ocrTexts.joined(separator: Constants.ocrTextSeparator)

        XCTAssertTrue(SessionRecordManager.shared.saveDraftSession(id: sessionId, name: "LLM失败草稿", images: [image, image]))
        XCTAssertTrue(SessionRecordManager.shared.updateDraftWithOCRResults(
            id: sessionId,
            ocrTexts: ocrTexts,
            ocrCombinedText: combinedText,
            validImageCount: ocrTexts.count,
            ocrDuration: 1.2,
            llmDuration: 0.3,
            llmStoryName: nil,
            llmHighlights: nil,
            hasVirtualPage: false
        ))

        let record = SessionRecordManager.shared.loadSession(id: sessionId)
        let metadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "BackgroundMakeManagerTests", forceRefresh: true)
            .first(where: { $0.id == sessionId })

        XCTAssertEqual(record?.makeStatus, .incomplete)
        XCTAssertEqual(metadata?.makeStatus, .incomplete)
        XCTAssertEqual(record?.ocrText, combinedText)
        XCTAssertEqual(record?.ocrTextSegments, ocrTexts)
        XCTAssertTrue(record?.audioDataBase64.isEmpty ?? false)
        XCTAssertEqual(record?.audioSize, 0)
    }

    func testMakeTaskLLMFailurePreservesIntermediateOCRResults() {
        let task = MakeTask(sessionId: "llm-failure-task", imageCount: 2)
        let ocrTexts = ["第一页文字", "第二页文字"]

        task.updateProgress(ProcessingProgress(
            stage: .ocr,
            currentStep: 50,
            totalSteps: 100,
            message: "OCR识别进度: 完成",
            percentage: 50,
            stageResults: StageResults(
                ocrTexts: ocrTexts,
                validImageCount: ocrTexts.count,
                totalImageCount: 2,
                ocrCompletedCount: 2
            )
        ))
        task.markFailed(error: ImageToSpeechProcessingError.llmFailed(LLMError.retryExhausted))

        XCTAssertTrue(task.isCompleted)
        XCTAssertFalse(task.isSuccess)
        XCTAssertEqual(task.intermediateResults?.ocrTexts, ocrTexts)
        XCTAssertEqual(task.intermediateResults?.validImageCount, ocrTexts.count)
    }

    /// 超出并发时也应保存草稿记录，供管理页可见和后续继续制作
    func testSaveDeferredDraftPersistsIncompleteRecord() {
        let image = makeTestImage()

        guard let sessionId = manager.saveDeferredDraft(images: [image]) else {
            XCTFail("saveDeferredDraft should persist a draft session")
            return
        }
        deferredDraftIDs.append(sessionId)

        let metadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "BackgroundMakeManagerTests", forceRefresh: true)
            .first(where: { $0.id == sessionId })

        XCTAssertNotNil(metadata, "deferred draft should be discoverable in metadata list")
        XCTAssertEqual(metadata?.makeStatus, .incomplete, "deferred draft should be marked incomplete instead of making")
        XCTAssertEqual(metadata?.totalImageCount, 1, "deferred draft should preserve image count")
        XCTAssertTrue(
            metadata?.name.range(of: #"^\d{2}\.\d{2}\.\d{2} 未命名-\d{6}$"#, options: .regularExpression) != nil,
            "deferred draft name should use yy.MM.dd 未命名-hhmmss format"
        )
        XCTAssertNil(manager.task(for: sessionId), "saving deferred draft should not create a running background task")
    }

    /// 后台制作草稿保存后应通知列表刷新，使已打开的管理页立即展示制作中状态
    func testStartMakingDraftSavePostsMetadataUpdateNotification() throws {
        let notificationExpectation = expectation(forNotification: Constants.NotificationNames.sessionMetadataDidUpdate, object: nil) { notification in
            guard let sessionId = notification.userInfo?["sessionId"] as? String else { return false }
            let metadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "BackgroundMakeManagerTests", forceRefresh: true)
                .first(where: { $0.id == sessionId })
            return metadata?.makeStatus == .making
        }

        guard let sessionId = manager.startMaking(images: [makeTestImage()]) else {
            XCTFail("startMaking should create a background task")
            return
        }
        deferredDraftIDs.append(sessionId)

        wait(for: [notificationExpectation], timeout: 3)
    }

    private func makeTestImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
