import Foundation
import UIKit
import Combine
import os.log

// MARK: - LLM阶段状态
enum LLMStageStatus {
    case notStarted    // 未开始
    case inProgress    // 分析中
    case completed     // 已完成
    case skipped       // 跳过（图片少于5张）
    case notConfigured // 未配置
}

// MARK: - 中间结果
struct IntermediateResults {
    var ocrTexts: [String] = []
    var validImageCount: Int = 0
    var llmStoryName: String?
    var llmHighlights: String?

    // 新增统计字段
    var totalImageCount: Int = 0         // 总图片数
    var ocrCompletedCount: Int = 0       // OCR已完成图片数（用于M/N展示）
    var ocrCharCount: Int = 0            // OCR识别总字数
    var ocrDuration: TimeInterval = 0    // OCR耗时（秒）
    var llmCharCount: Int = 0            // LLM分析字数（故事名+要点）
    var llmDuration: TimeInterval = 0    // LLM耗时（秒）
    var llmStatus: LLMStageStatus = .notStarted  // LLM阶段状态
}

// MARK: - 后台制作任务
/// 单个后台制作任务，持有独立的 Coordinator 实例
class MakeTask: ObservableObject, Identifiable {
    let id: String  // 即 sessionId
    let imageCount: Int

    /// 处理进度 0.0~1.0
    @Published var progress: Float = 0.0
    /// 当前操作描述
    @Published var operationMessage: String = ""
    /// 是否已完成（成功或失败）
    @Published var isCompleted: Bool = false
    /// 是否处理成功
    @Published var isSuccess: Bool = false
    /// 失败时的错误
    @Published var error: Error? = nil
    /// 完成后的音频响应（用于 MakeView 重连后触发播放）
    @Published var audioResponse: AudioResponse? = nil
    /// OCR 文本分段
    @Published var ocrTextSegments: [String] = []
    /// OCR 合并文本
    @Published var ocrText: String = ""
    /// 音频数据
    @Published var audioData: Data? = nil
    /// 中间结果（OCR文本、LLM摘要等）
    @Published var intermediateResults: IntermediateResults?

    /// OCR 耗时
    var ocrDuration: TimeInterval = 0
    /// LLM 耗时
    var llmDuration: TimeInterval = 0
    /// TTS 耗时
    var ttsDuration: TimeInterval = 0

    /// 独立的 Coordinator 实例
    let coordinator: ImageToSpeechCoordinator

    private var ocrStartTime: Date?
    private var llmStartTime: Date?
    private var ttsStartTime: Date?

    init(sessionId: String, imageCount: Int) {
        self.id = sessionId
        self.imageCount = imageCount
        self.coordinator = ImageToSpeechCoordinator(
            networkService: NetworkService(),
            settingsManager: SettingsManager.shared
        )
    }

    /// 更新进度（由 BackgroundMakeManager 在 progressHandler 中调用）
    func updateProgress(_ processingProgress: ProcessingProgress) {
        let normalized = max(0.0, min(1.0, processingProgress.percentage / 100.0))
        self.progress = Float(normalized)
        self.operationMessage = processingProgress.message

        // 记录 OCR 开始时间
        if processingProgress.stage == .ocr && ocrStartTime == nil {
            ocrStartTime = Date()
        }

        // 记录 LLM 开始时间
        if processingProgress.stage == .llm && llmStartTime == nil {
            llmStartTime = Date()
        }

        // 记录 TTS 开始时间
        if processingProgress.stage == .tts && ttsStartTime == nil {
            ttsStartTime = Date()
        }

        // 计算 OCR 耗时
        if processingProgress.stage == .llm, let start = ocrStartTime {
            ocrDuration = Date().timeIntervalSince(start)
        }

        // 计算 LLM 耗时
        if processingProgress.stage == .tts, let start = llmStartTime {
            llmDuration = Date().timeIntervalSince(start)
        }

        // 计算 TTS 耗时（更新中）
        if processingProgress.stage == .tts, let start = ttsStartTime {
            ttsDuration = Date().timeIntervalSince(start)
        }

        // 同步阶段结果
        if let stageResults = processingProgress.stageResults {
            if self.intermediateResults == nil {
                self.intermediateResults = IntermediateResults()
            }
            if let ocrTexts = stageResults.ocrTexts {
                self.intermediateResults?.ocrTexts = ocrTexts
            }
            if let validCount = stageResults.validImageCount {
                self.intermediateResults?.validImageCount = validCount
            }
            if let storyName = stageResults.llmStoryName {
                self.intermediateResults?.llmStoryName = storyName
            }
            if let highlights = stageResults.llmHighlights {
                self.intermediateResults?.llmHighlights = highlights
            }

            // 同步新增统计字段
            if let totalImageCount = stageResults.totalImageCount {
                self.intermediateResults?.totalImageCount = totalImageCount
            }
            if let ocrCompletedCount = stageResults.ocrCompletedCount {
                self.intermediateResults?.ocrCompletedCount = ocrCompletedCount
            }
            if let ocrCharCount = stageResults.ocrCharCount {
                self.intermediateResults?.ocrCharCount = ocrCharCount
            }
            if let llmCharCount = stageResults.llmCharCount {
                self.intermediateResults?.llmCharCount = llmCharCount
            }
            if let llmStatus = stageResults.llmStatus {
                self.intermediateResults?.llmStatus = llmStatus
            }
        }

        // 耗时同步放在 stageResults 守卫外部，确保即使 stageResults 为 nil 也能同步
        // OCR 耗时在阶段切换时更新
        if processingProgress.stage == .llm {
            self.intermediateResults?.ocrDuration = self.ocrDuration
        }

        // LLM 耗时在阶段切换时更新
        if processingProgress.stage == .tts {
            self.intermediateResults?.llmDuration = self.llmDuration
        }
    }

    /// 标记开始处理
    func markStarted() {
        ocrStartTime = Date()
    }

    /// 标记处理完成
    func markCompleted(response: AudioResponse) {
        let endTime = Date()
        // OCR 耗时已在 updateProgress 中计算（进入 LLM 阶段时）
        // LLM 耗时已在 updateProgress 中计算（进入 TTS 阶段时）
        // TTS 耗时需要在此处最终确认
        if let start = ttsStartTime {
            ttsDuration = endTime.timeIntervalSince(start)
        }

        self.audioResponse = response
        self.audioData = response.audioData
        self.ocrText = response.text
        self.ocrTextSegments = response.recognizedTexts ?? []
        self.progress = 1.0
        self.operationMessage = "处理完成"
        self.isSuccess = true
        self.isCompleted = true
    }

    /// 标记处理失败
    func markFailed(error: Error) {
        self.error = error
        self.progress = 0.0
        self.operationMessage = "处理失败"
        self.isSuccess = false
        self.isCompleted = true
    }

    /// 取消处理
    func cancel() {
        coordinator.cancelProcessing()
        self.error = ImageToSpeechProcessingError.cancelled
        self.isCompleted = true
    }
}

// MARK: - 后台制作管理器
/// 后台制作管理器，只允许1个后台制作任务
class BackgroundMakeManager: ObservableObject {

    // MARK: - 单例
    static let shared = BackgroundMakeManager()

    // MARK: - 属性
    /// 当前任务（只允许1个）
    @Published var currentTask: MakeTask? = nil

    private let logger = os.Logger.backgroundMake

    private init() {}

    // MARK: - 启动制作

    /// 启动后台制作任务（只允许1个，已有活跃任务时拒绝）
    /// 主线程仅做快速操作（创建 task），重 I/O（草稿保存 + jpegData）在后台线程执行
    /// - Parameters:
    ///   - images: 已降采样的图片数组
    /// - Returns: sessionId（草稿会话的 ID），nil 表示启动失败
    func startMaking(images: [UIImage]) -> String? {
        return startMaking(
            images: images,
            startingFrom: .ocr,
            ocrTexts: nil,
            ocrCombinedText: nil,
            llmStoryName: nil,
            llmHighlights: nil
        )
    }

    /// 启动后台制作任务（从指定阶段开始）
    /// - Parameters:
    ///   - images: 已降采样的图片数组
    ///   - startStage: 启动阶段
    ///   - ocrTexts: 已有 OCR 文本数组（从 LLM/TTS 阶段启动时）
    ///   - ocrCombinedText: 已有 OCR 合并文本（从 TTS 阶段启动时）
    ///   - llmStoryName: 已有 LLM 故事名（从 TTS 阶段启动时）
    ///   - llmHighlights: 已有 LLM 要点（从 TTS 阶段启动时）
    ///   - reuseSessionId: 可选，复用已有草稿会话的 ID（重试时使用）
    /// - Returns: sessionId（草稿会话的 ID），nil 表示启动失败
    func startMaking(
        images: [UIImage],
        startingFrom startStage: ProcessingProgress.ProcessingStage,
        ocrTexts: [String]?,
        ocrCombinedText: String?,
        llmStoryName: String?,
        llmHighlights: String?,
        reuseSessionId: String? = nil
    ) -> String? {
        // 只允许1个后台制作任务
        if let existing = currentTask, !existing.isCompleted {
            logger.warning("已有活跃的后台制作任务: sessionId=\(existing.id)，拒绝启动新任务")
            return nil
        }

        let sessionId = reuseSessionId ?? UUID().uuidString

        // 生成草稿名称 "YY.MM.DD 未命名"
        let formatter = DateFormatter()
        formatter.dateFormat = "yy.MM.dd "
        let draftName = formatter.string(from: Date()) + Constants.draftSessionNameSuffix

        // 创建任务并立即返回，不阻塞主线程
        let task = MakeTask(sessionId: sessionId, imageCount: images.count)
        currentTask = task
        task.markStarted()
        logger.info("后台制作任务启动: sessionId=\(sessionId), 图片数=\(images.count)")

        // 重 I/O 移到后台线程：草稿保存 + jpegData 转换 + 启动 Coordinator
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak task] in
            guard let self = self, let task = task else { return }

            // 保存草稿（图片落盘）
            let saved = SessionRecordManager.shared.saveDraftSession(id: sessionId, name: draftName, images: images)
            guard saved else {
                self.logger.error("草稿会话保存失败，无法启动后台制作")
                DispatchQueue.main.async {
                    task.markFailed(error: NSError(domain: Constants.ErrorInfo.domain, code: Constants.ErrorInfo.defaultCode, userInfo: [NSLocalizedDescriptionKey: "草稿保存失败"]))
                    self.objectWillChange.send()
                }
                return
            }

            // 准备图片数据
            var imageDataList: [Data] = []
            for image in images {
                if let data = image.jpegData(compressionQuality: 0.8) {
                    imageDataList.append(data)
                }
            }

            guard !imageDataList.isEmpty else {
                self.logger.error("图片数据转换失败，无法启动后台制作")
                DispatchQueue.main.async {
                    task.markFailed(error: NSError(domain: Constants.ErrorInfo.domain, code: Constants.ErrorInfo.defaultCode, userInfo: [NSLocalizedDescriptionKey: "图片数据转换失败"]))
                    self.objectWillChange.send()
                }
                return
            }

            self.logger.info("后台制作: 草稿保存+图片转换完成，启动 Coordinator: sessionId=\(sessionId), 阶段=\(String(describing: startStage))")

            // 启动 Coordinator 处理（根据阶段选择不同方法）
            let progressHandler: (ProcessingProgress) -> Void = { [weak self, weak task] progress in
                guard let self = self, let task = task else { return }
                DispatchQueue.main.async {
                    task.updateProgress(progress)
                    self.objectWillChange.send()
                }
            }

            let completionHandler: (Result<AudioResponse, ImageToSpeechProcessingError>) -> Void = { [weak self, weak task] result in
                guard let self = self, let task = task else { return }
                DispatchQueue.main.async {
                    switch result {
                    case .success(let audioResponse):
                        task.markCompleted(response: audioResponse)
                        self.logger.info("后台制作完成: sessionId=\(sessionId), 文本长度=\(audioResponse.text.count)")

                        // 在后台线程更新会话记录
                        DispatchQueue.global(qos: .userInitiated).async {
                            let updated = SessionRecordManager.shared.updateSessionWithResults(
                                id: sessionId,
                                audioResponse: audioResponse,
                                ocrDuration: task.ocrDuration,
                                llmDuration: task.llmDuration,
                                ttsDuration: task.ttsDuration
                            )
                            if updated {
                                self.logger.info("后台制作结果已持久化: sessionId=\(sessionId)")
                                // 记录制作历史事件（直接调用 addMakeEvent，绕过 recordSave 的名称过滤；
                                // loadEntries 聚合时按当前名称过滤，未命名会话不会展示）
                                let identity = SettingsManager.shared.identityName
                                SessionRecordManager.shared.addMakeEvent(sessionId: sessionId, timestamp: Date(), identity: identity)
                                self.logger.info("制作历史事件已记录: sessionId=\(sessionId), 身份: \(identity)")
                            } else {
                                self.logger.error("后台制作结果持久化失败: sessionId=\(sessionId)")
                            }
                        }

                    case .failure(let error):
                        task.markFailed(error: error)
                        self.logger.error("后台制作失败: sessionId=\(sessionId), 错误=\(error.localizedDescription)")
                        // 制作失败时保留草稿，先尝试保存已有的 OCR 结果，再标记为未完成
                        DispatchQueue.global(qos: .utility).async {
                            var saved = false
                            // 如果有中间结果（OCR已完成），先保存 OCR 文本
                            if let intermediate = task.intermediateResults, !intermediate.ocrTexts.isEmpty {
                                let ocrCombinedText = intermediate.ocrTexts.joined(separator: Constants.ocrTextSeparator)
                                let hasVirtualPage = intermediate.llmHighlights != nil && !intermediate.llmHighlights!.isEmpty
                                saved = SessionRecordManager.shared.updateDraftWithOCRResults(
                                    id: sessionId,
                                    ocrTexts: intermediate.ocrTexts,
                                    ocrCombinedText: ocrCombinedText,
                                    validImageCount: intermediate.validImageCount,
                                    ocrDuration: task.ocrDuration,
                                    llmDuration: task.llmDuration,
                                    llmStoryName: intermediate.llmStoryName,
                                    llmHighlights: intermediate.llmHighlights,
                                    hasVirtualPage: hasVirtualPage
                                )
                                if saved {
                                    self.logger.info("草稿OCR结果已保存: sessionId=\(sessionId), 文本长度=\(ocrCombinedText.count)")
                                }
                            }
                            // 标记为未完成（如果上面没保存成功，单独更新状态）
                            if !saved {
                                let updated = SessionRecordManager.shared.updateDraftMakeStatus(id: sessionId, status: .incomplete)
                                if updated {
                                    self.logger.info("草稿已标记为未完成: sessionId=\(sessionId)")
                                } else {
                                    self.logger.error("草稿状态更新失败，保留 making 状态: sessionId=\(sessionId)")
                                }
                            }
                        }
                    }
                    self.objectWillChange.send()
                }
            }

            switch startStage {
            case .ocr:
                task.coordinator.convertBatchImagesToSpeech(
                    imageDataList,
                    progressHandler: progressHandler,
                    completion: completionHandler
                )
            case .llm:
                task.coordinator.convertBatchImagesToSpeech(
                    imageDataList,
                    startingFrom: .llm,
                    ocrTexts: ocrTexts,
                    ocrCombinedText: nil,
                    llmStoryName: nil,
                    llmHighlights: nil,
                    progressHandler: progressHandler,
                    completion: completionHandler
                )
            case .tts:
                task.coordinator.convertBatchImagesToSpeech(
                    imageDataList,
                    startingFrom: .tts,
                    ocrTexts: ocrTexts,
                    ocrCombinedText: ocrCombinedText,
                    llmStoryName: llmStoryName,
                    llmHighlights: llmHighlights,
                    progressHandler: progressHandler,
                    completion: completionHandler
                )
            case .completed, .failed:
                break
            }
        }

        return sessionId
    }

    // MARK: - 查询任务

    /// 获取指定 sessionId 的任务（匹配当前任务时返回）
    func task(for sessionId: String) -> MakeTask? {
        guard let task = currentTask, task.id == sessionId else { return nil }
        return task
    }

    /// 是否有活跃（未完成）任务
    var hasActiveTask: Bool {
        guard let task = currentTask else { return false }
        return !task.isCompleted
    }

    // MARK: - 清理任务

    /// 移除已完成的任务（MakeView 消费结果后调用）
    func removeTask(sessionId: String) {
        guard currentTask?.id == sessionId else { return }
        currentTask = nil
        logger.info("移除后台制作任务: sessionId=\(sessionId)")
    }

    /// 取消当前任务
    func cancelTask(sessionId: String) {
        guard let task = currentTask, task.id == sessionId else { return }
        task.cancel()
        // 删除草稿会话
        DispatchQueue.global(qos: .utility).async {
            _ = SessionRecordManager.shared.deleteSession(id: sessionId)
        }
        currentTask = nil
        logger.info("取消后台制作任务: sessionId=\(sessionId)")
    }
}
