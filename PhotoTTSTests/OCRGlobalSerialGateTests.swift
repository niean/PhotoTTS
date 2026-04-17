import XCTest
@testable import PhotoTTS

/// OCR 跨任务串行闸门测试
/// 闸门为单例（actor），单测按 FIFO 排队语义设计；setUp 中通过持有者释放确保初态干净
final class OCRGlobalSerialGateTests: XCTestCase {

    private func drainGate() async {
        // 兜底：若前个测试异常退出导致 holder 残留，尝试用当前 holder 名释放
        if let holder = await OCRGlobalSerialGate.shared.currentHolder {
            await OCRGlobalSerialGate.shared.release(taskId: holder)
        }
    }

    override func setUp() async throws {
        try await super.setUp()
        await drainGate()
    }

    override func tearDown() async throws {
        await drainGate()
        try await super.tearDown()
    }

    /// 初次 acquire 立即获取，state 应反映 holder
    func testAcquireImmediatelyWhenIdle() async {
        let taskId = "task-A"
        await OCRGlobalSerialGate.shared.acquire(taskId: taskId)
        let holder = await OCRGlobalSerialGate.shared.currentHolder
        XCTAssertEqual(holder, taskId, "initial acquire should set holder")
        await OCRGlobalSerialGate.shared.release(taskId: taskId)
        let holderAfter = await OCRGlobalSerialGate.shared.currentHolder
        XCTAssertNil(holderAfter, "after release holder should be nil")
    }

    /// release 非持有者应当被忽略，不影响持有者
    func testReleaseByNonHolderIsIgnored() async {
        let holderId = "holder-A"
        await OCRGlobalSerialGate.shared.acquire(taskId: holderId)
        // 非持有者尝试释放
        await OCRGlobalSerialGate.shared.release(taskId: "intruder-B")
        let holder = await OCRGlobalSerialGate.shared.currentHolder
        XCTAssertEqual(holder, holderId, "non-holder release must not change holder")
        await OCRGlobalSerialGate.shared.release(taskId: holderId)
    }

    /// 第 2 个 acquire 应在第 1 个 release 前挂起，release 后才能返回
    func testSecondAcquireWaitsUntilReleased() async {
        let firstId = "task-1"
        let secondId = "task-2"
        await OCRGlobalSerialGate.shared.acquire(taskId: firstId)

        // 启动第二个申请，它应该在 withCheckedContinuation 上挂起
        let secondAcquireStarted = XCTestExpectation(description: "second acquire returned")
        let acquireTask = Task { () -> Void in
            await OCRGlobalSerialGate.shared.acquire(taskId: secondId)
            secondAcquireStarted.fulfill()
        }

        // 等待 100ms 确保 second 已进入排队；未释放前 fulfillment 不应发生
        try? await Task.sleep(nanoseconds: 100_000_000)
        let waitersDuring = await OCRGlobalSerialGate.shared.waitingCount
        XCTAssertEqual(waitersDuring, 1, "second acquire should be queued")

        let holderDuring = await OCRGlobalSerialGate.shared.currentHolder
        XCTAssertEqual(holderDuring, firstId, "holder should still be first before release")

        // 释放第 1 个，第 2 个应立即被唤醒
        await OCRGlobalSerialGate.shared.release(taskId: firstId)

        // 等待 secondAcquireStarted fulfill（超时 2s，充裕）
        await fulfillment(of: [secondAcquireStarted], timeout: 2.0)

        let holderAfter = await OCRGlobalSerialGate.shared.currentHolder
        XCTAssertEqual(holderAfter, secondId, "after release, second should become holder")

        let waitersAfter = await OCRGlobalSerialGate.shared.waitingCount
        XCTAssertEqual(waitersAfter, 0, "no more waiters")

        // 清理
        await OCRGlobalSerialGate.shared.release(taskId: secondId)
        _ = await acquireTask.value
    }

    /// 3 个并发 acquire 应严格 FIFO：第 1 立即获取，2/3 排队
    func testFIFOOrderingAcrossThreeTasks() async {
        let ids = ["fifo-1", "fifo-2", "fifo-3"]

        // 第 1 个立即 acquire
        await OCRGlobalSerialGate.shared.acquire(taskId: ids[0])

        // 第 2 第 3 个排队
        let exp2 = XCTestExpectation(description: "second resumed")
        let exp3 = XCTestExpectation(description: "third resumed")

        let t2 = Task { () -> Void in
            await OCRGlobalSerialGate.shared.acquire(taskId: ids[1])
            exp2.fulfill()
        }

        // 给 t2 一点时间进入队列
        try? await Task.sleep(nanoseconds: 50_000_000)

        let t3 = Task { () -> Void in
            await OCRGlobalSerialGate.shared.acquire(taskId: ids[2])
            exp3.fulfill()
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        let waiters = await OCRGlobalSerialGate.shared.waitingCount
        XCTAssertEqual(waiters, 2, "two waiters queued")

        // 释放第 1 个 -> 第 2 个被唤醒
        await OCRGlobalSerialGate.shared.release(taskId: ids[0])
        await fulfillment(of: [exp2], timeout: 2.0)
        let holderAfter1 = await OCRGlobalSerialGate.shared.currentHolder
        XCTAssertEqual(holderAfter1, ids[1], "second should hold after first release")

        // 释放第 2 个 -> 第 3 个被唤醒
        await OCRGlobalSerialGate.shared.release(taskId: ids[1])
        await fulfillment(of: [exp3], timeout: 2.0)
        let holderAfter2 = await OCRGlobalSerialGate.shared.currentHolder
        XCTAssertEqual(holderAfter2, ids[2], "third should hold after second release")

        await OCRGlobalSerialGate.shared.release(taskId: ids[2])
        _ = await t2.value
        _ = await t3.value
    }
}
