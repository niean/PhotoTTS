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

// MARK: - TTS阶段状态
enum TTSStageStatus {
    case notStarted    // 未开始
    case inProgress    // 合成中
    case completed     // 已完成
    case failed        // 失败
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

    // TTS统计字段
    var ttsCharCount: Int = 0            // TTS合成字数
    var ttsDuration: TimeInterval = 0    // TTS耗时（秒）
    var ttsStatus: TTSStageStatus = .notStarted  // TTS阶段状态
    var ttsAudioSize: Int = 0            // TTS音频大小（字节）
    var ttsAudioDuration: TimeInterval = 0  // TTS音频时长（秒）
    var ttsSegmentCount: Int = 0         // TTS总分段数
    var ttsCompletedSegmentCount: Int = 0 // TTS已完成分段数
    var ttsCurrentSegmentNumber: Int = 0 // 当前分段编号
    var ttsCurrentSegmentImageStartIndex: Int = 0 // 当前分段起始图片索引
    var ttsCurrentSegmentImageEndIndex: Int = 0 // 当前分段结束图片索引
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
            settingsManager: SettingsManager.shared,
            ownerTaskId: sessionId
        )
    }

    /// 为从 LLM/TTS 继续制作的任务注入已有阶段快照，避免状态页和持久化丢失前序结果
    func seedExistingResults(
        intermediateResults: IntermediateResults?,
        ocrText: String,
        ocrTextSegments: [String],
        ocrDuration: TimeInterval,
        llmDuration: TimeInterval,
        ttsDuration: TimeInterval
    ) {
        self.intermediateResults = intermediateResults
        self.ocrText = ocrText
        self.ocrTextSegments = ocrTextSegments
        self.ocrDuration = ocrDuration
        self.llmDuration = llmDuration
        self.ttsDuration = ttsDuration
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

            // 同步 TTS 统计字段
            if let ttsCharCount = stageResults.ttsCharCount {
                self.intermediateResults?.ttsCharCount = ttsCharCount
            }
            if let ttsDuration = stageResults.ttsDuration {
                self.intermediateResults?.ttsDuration = ttsDuration
            }
            if let ttsStatus = stageResults.ttsStatus {
                self.intermediateResults?.ttsStatus = ttsStatus
            }
            if let ttsAudioSize = stageResults.ttsAudioSize {
                self.intermediateResults?.ttsAudioSize = ttsAudioSize
            }
            if let ttsAudioDuration = stageResults.ttsAudioDuration {
                self.intermediateResults?.ttsAudioDuration = ttsAudioDuration
            }
            if let ttsSegmentCount = stageResults.ttsSegmentCount {
                self.intermediateResults?.ttsSegmentCount = ttsSegmentCount
            }
            if let ttsCompletedSegmentCount = stageResults.ttsCompletedSegmentCount {
                self.intermediateResults?.ttsCompletedSegmentCount = ttsCompletedSegmentCount
            }
            if let ttsCurrentSegmentNumber = stageResults.ttsCurrentSegmentNumber {
                self.intermediateResults?.ttsCurrentSegmentNumber = ttsCurrentSegmentNumber
            }
            if let ttsCurrentSegmentImageStartIndex = stageResults.ttsCurrentSegmentImageStartIndex {
                self.intermediateResults?.ttsCurrentSegmentImageStartIndex = ttsCurrentSegmentImageStartIndex
            }
            if let ttsCurrentSegmentImageEndIndex = stageResults.ttsCurrentSegmentImageEndIndex {
                self.intermediateResults?.ttsCurrentSegmentImageEndIndex = ttsCurrentSegmentImageEndIndex
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

        // TTS 耗时在完成时更新
        if processingProgress.stage == .completed || processingProgress.stage == .tts {
            self.intermediateResults?.ttsDuration = self.ttsDuration
        }
    }

    /// 标记开始处理
    func markStarted() {
        // 制作任务创建时可能仍在等待 OCR 串行闸门，不能把排队时间计入 OCR 耗时。
        // 实际 OCR 开始时间由首个 OCR 进度事件写入。
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

        // 同步 TTS 最终统计到 intermediateResults
        if self.intermediateResults == nil {
            self.intermediateResults = IntermediateResults()
        }
        self.intermediateResults?.ttsDuration = self.ttsDuration
        self.intermediateResults?.ttsStatus = .completed
        self.intermediateResults?.ttsCharCount = response.text.count
        self.intermediateResults?.ttsAudioSize = response.audioData?.count ?? 0
        self.intermediateResults?.ttsAudioDuration = response.duration
        self.intermediateResults?.ttsSegmentCount = response.audioSegments?.count ?? 1
        self.intermediateResults?.ttsCompletedSegmentCount = response.audioSegments?.count ?? 1
        self.intermediateResults?.ttsCurrentSegmentNumber = response.audioSegments?.last?.sequenceNumber ?? (response.audioSegments == nil ? 1 : 0)
        self.intermediateResults?.ttsCurrentSegmentImageStartIndex = response.audioSegments?.last?.imageStartIndex ?? 0
        self.intermediateResults?.ttsCurrentSegmentImageEndIndex = response.audioSegments?.last?.imageEndIndex ?? max(0, (response.recognizedTexts?.count ?? 1) - 1)

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
/// 后台制作管理器，支持多任务并发（上限 Constants.BackgroundMake.maxConcurrentTasks）
/// - OCR 阶段跨任务整体互斥（通过 OCRGlobalSerialGate），单任务内仍按 ocr_concurrent_count 并发
/// - LLM/TTS 阶段无串行约束，跨任务自由并行
class BackgroundMakeManager: ObservableObject {

    // MARK: - 单例
    static let shared = BackgroundMakeManager()

    // MARK: - 属性
    /// 所有任务（含已完成，供 UI 在完成/失败后消费结果），按 sessionId 索引
    @Published var tasks: [String: MakeTask] = [:]

    private let logger = os.Logger.backgroundMake

    private init() {}

    // MARK: - 容量查询

    /// 当前未完成（!isCompleted）的任务数量
    var activeTaskCount: Int {
        tasks.values.filter { !$0.isCompleted }.count
    }

    /// 是否还有容量启动新任务
    var hasCapacity: Bool {
        activeTaskCount < Constants.BackgroundMake.maxConcurrentTasks
    }

    /// 是否存在任意未完成任务
    var hasAnyActiveTask: Bool {
        activeTaskCount > 0
    }

    private func makeDraftName() -> String {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = Constants.sessionNameDatePrefixFormat

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = Constants.draftSessionTimeSuffixFormat

        return dateFormatter.string(from: now) + Constants.draftSessionNamePrefix + timeFormatter.string(from: now)
    }

    // MARK: - 启动制作

    /// 并发已满时，仅保存草稿到本地，供管理页可见和后续继续制作
    /// - Parameters:
    ///   - images: 已降采样的图片数组
    ///   - reuseSessionId: 可选，复用已有草稿会话的 ID
    /// - Returns: 草稿会话 ID；保存失败时返回 nil
    func saveDeferredDraft(images: [UIImage], reuseSessionId: String? = nil) -> String? {
        let sessionId = reuseSessionId ?? UUID().uuidString
        let draftName = makeDraftName()

        let saved = SessionRecordManager.shared.saveDraftSession(id: sessionId, name: draftName, images: images)
        guard saved else {
            logger.error("并发已满时保存草稿失败: sessionId=\(sessionId), 图片数=\(images.count)")
            return nil
        }

        if SessionRecordManager.shared.updateDraftMakeStatus(id: sessionId, status: .incomplete) {
            logger.info("并发已满，已保存待制作草稿: sessionId=\(sessionId), 图片数=\(images.count)")
        } else {
            logger.warning("并发已满，草稿已保存但状态未更新为 incomplete: sessionId=\(sessionId)")
        }

        return sessionId
    }

    /// 启动后台制作任务（容量不足或指定复用 ID 对应任务仍活跃时拒绝）
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
        existingIntermediateResults: IntermediateResults? = nil,
        existingOCRDuration: TimeInterval = 0,
        existingLLMDuration: TimeInterval = 0,
        existingTTSDuration: TimeInterval = 0,
        reuseSessionId: String? = nil
    ) -> String? {
        // 若复用 ID 对应任务仍活跃，视为重入，拒绝
        if let rid = reuseSessionId, let existing = tasks[rid], !existing.isCompleted {
            logger.warning("任务已在进行中: sessionId=\(rid)，拒绝重新启动")
            return nil
        }

        // 容量检查
        guard hasCapacity else {
            logger.warning("已达并发上限 \(Constants.BackgroundMake.maxConcurrentTasks)，拒绝启动；activeCount=\(self.activeTaskCount)")
            return nil
        }

        let sessionId = reuseSessionId ?? UUID().uuidString

        let draftName = makeDraftName()

        // 创建任务并立即返回，不阻塞主线程
        let task = MakeTask(sessionId: sessionId, imageCount: images.count)
        task.seedExistingResults(
            intermediateResults: existingIntermediateResults,
            ocrText: ocrCombinedText ?? "",
            ocrTextSegments: ocrTexts ?? [],
            ocrDuration: existingOCRDuration,
            llmDuration: existingLLMDuration,
            ttsDuration: existingTTSDuration
        )
        tasks[sessionId] = task
        task.markStarted()
        logger.info("后台制作任务启动: sessionId=\(sessionId), 图片数=\(images.count), activeCount=\(self.activeTaskCount)")

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
                if let data = image.jpegData(compressionQuality: Constants.BackgroundMake.jpegCompressionQuality) {
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
                                DispatchQueue.main.async {
                                    NotificationCenter.default.post(
                                        name: Constants.NotificationNames.sessionMetadataDidUpdate,
                                        object: nil,
                                        userInfo: ["sessionId": sessionId]
                                    )
                                }
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
                                    DispatchQueue.main.async {
                                        NotificationCenter.default.post(
                                            name: Constants.NotificationNames.sessionMetadataDidUpdate,
                                            object: nil,
                                            userInfo: ["sessionId": sessionId]
                                        )
                                    }
                                } else {
                                    self.logger.error("草稿状态更新失败，保留 making 状态: sessionId=\(sessionId)")
                                }
                            } else {
                                DispatchQueue.main.async {
                                    NotificationCenter.default.post(
                                        name: Constants.NotificationNames.sessionMetadataDidUpdate,
                                        object: nil,
                                        userInfo: ["sessionId": sessionId]
                                    )
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

    /// 获取指定 sessionId 的任务（含已完成，供 UI 消费结果）
    func task(for sessionId: String) -> MakeTask? {
        return tasks[sessionId]
    }

    /// 获取指定 sessionId 的未完成任务（仅活跃任务）
    func activeTask(for sessionId: String) -> MakeTask? {
        guard let task = tasks[sessionId], !task.isCompleted else { return nil }
        return task
    }

    // MARK: - 清理任务

    /// 移除已消费的任务（MakeView 消费结果后调用）
    func removeTask(sessionId: String) {
        guard tasks[sessionId] != nil else { return }
        tasks.removeValue(forKey: sessionId)
        logger.info("移除后台制作任务: sessionId=\(sessionId), activeCount=\(self.activeTaskCount)")
    }

    /// 取消指定任务（删除草稿并移除）
    func cancelTask(sessionId: String) {
        guard let task = tasks[sessionId] else { return }
        task.cancel()
        // 删除草稿会话
        DispatchQueue.global(qos: .utility).async {
            _ = SessionRecordManager.shared.deleteSession(id: sessionId)
        }
        tasks.removeValue(forKey: sessionId)
        logger.info("取消后台制作任务: sessionId=\(sessionId), activeCount=\(self.activeTaskCount)")
    }
}
