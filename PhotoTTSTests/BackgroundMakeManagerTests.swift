import XCTest
import UIKit
@testable import PhotoTTS

/// BackgroundMakeManager 多任务并发语义测试
/// 本套件聚焦容量/索引/清理的纯内存语义，不验证 Coordinator 真实 I/O 流程
final class BackgroundMakeManagerTests: XCTestCase {

    private let manager = BackgroundMakeManager.shared

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
        super.tearDown()
    }

    /// 初始状态应无活跃任务、容量充足
    func testInitialStateHasCapacity() {
        XCTAssertEqual(manager.activeTaskCount, 0, "initial activeTaskCount should be 0")
        XCTAssertTrue(manager.hasCapacity, "initial should have capacity")
        XCTAssertFalse(manager.hasAnyActiveTask, "initial should have no active task")
    }

    /// 手动注入 3 个未完成任务后应达到上限，第 4 个 hasCapacity 返回 false
    func testCapacityLimitAtThreeTasks() {
        // 手动注入：模拟 3 个未完成任务（直接写 tasks 字典）
        // 避免走 startMaking 的磁盘 I/O，仅验证容量门
        let ids = ["unit-task-1", "unit-task-2", "unit-task-3"]
        for id in ids {
            let t = MakeTask(sessionId: id, imageCount: 1)
            manager.tasks[id] = t
        }
        XCTAssertEqual(manager.activeTaskCount, 3, "after inject 3 tasks, activeCount == 3")
        XCTAssertFalse(manager.hasCapacity, "3 active tasks should fill capacity")
        XCTAssertTrue(manager.hasAnyActiveTask)

        // 标记 1 个完成，容量恢复
        if let t = manager.tasks[ids[0]] {
            t.markFailed(error: NSError(domain: "unit", code: -1))
        }
        XCTAssertEqual(manager.activeTaskCount, 2, "failed task should not count as active")
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

    /// 并发上限常量符合 spec 约定（3）
    func testConcurrencyLimitConstant() {
        XCTAssertEqual(Constants.BackgroundMake.maxConcurrentTasks, 3, "spec contract: maxConcurrentTasks == 3")
    }
}
