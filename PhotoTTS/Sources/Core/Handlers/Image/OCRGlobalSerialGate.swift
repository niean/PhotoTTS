import Foundation
import os.log

// MARK: - OCR 跨任务串行闸门
/// OCR 跨任务串行闸门
///
/// 多任务并发后台制作时，OCR 阶段整体互斥：任意时刻只允许 1 个任务持有闸门。
/// 单任务内的并发分批（由 `ocr_concurrent_count` 控制）不受此约束。
/// 设计为 FIFO 队列，先申请先获取；release 仅持有者能执行。
///
/// 使用方式：
/// ```
/// await OCRGlobalSerialGate.shared.acquire(taskId: sessionId)
/// defer {
///     let tid = sessionId
///     Task { await OCRGlobalSerialGate.shared.release(taskId: tid) }
/// }
/// // 执行 OCR 批次
/// ```
actor OCRGlobalSerialGate {
    // MARK: - 单例
    static let shared = OCRGlobalSerialGate()

    // MARK: - 状态
    /// 当前持有闸门的任务 ID
    private var holderTaskId: String?
    /// FIFO 等待队列
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private let logger = os.Logger.ocrService

    private init() {}

    // MARK: - API

    /// 获取闸门，若已被其他任务持有则排队挂起直至轮到
    /// - Parameter taskId: 申请方任务 ID（通常为 sessionId）
    func acquire(taskId: String) async {
        if holderTaskId == nil {
            holderTaskId = taskId
            logger.info("OCR gate acquired immediately, taskId=\(taskId), waiters=\(self.waiters.count)")
            return
        }

        let currentHolder = holderTaskId ?? "unknown"
        let waitingBefore = waiters.count
        logger.info("OCR gate waiting, taskId=\(taskId), holder=\(currentHolder), waitingBefore=\(waitingBefore)")

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }

        // 被唤醒后当前 holder 应为 nil（上一持有者释放时不会设置新 holder，由此处写入）
        holderTaskId = taskId
        logger.info("OCR gate acquired after waiting, taskId=\(taskId), remainingWaiters=\(self.waiters.count)")
    }

    /// 释放闸门。仅持有者能释放；若有排队者则唤醒下一个
    /// - Parameter taskId: 释放方任务 ID，必须与当前持有者匹配
    func release(taskId: String) {
        guard holderTaskId == taskId else {
            let holderDesc = holderTaskId ?? "nil"
            logger.warning("OCR gate release skipped, notHolder taskId=\(taskId), holder=\(holderDesc)")
            return
        }
        holderTaskId = nil
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        }
        logger.info("OCR gate released, taskId=\(taskId), remainingWaiters=\(self.waiters.count)")
    }

    // MARK: - 诊断/测试

    /// 当前持有者（仅供日志/测试使用）
    var currentHolder: String? { holderTaskId }
    /// 当前排队数量（仅供日志/测试使用）
    var waitingCount: Int { waiters.count }
}
