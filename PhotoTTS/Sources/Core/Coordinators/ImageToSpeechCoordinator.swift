import Foundation
import os.log

// MARK: - Array扩展
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - 图片转语音协调器协议
/// 图片转语音协调器协议，定义了图片转语音处理的核心接口
/// 支持单张和批量图片处理，提供进度跟踪和取消功能
protocol ImageToSpeechCoordinatorProtocol {
    /// 批量图片转语音处理
    /// - Parameters:
    ///   - images: 要处理的图片数据数组
    ///   - progressHandler: 进度回调，实时报告处理状态
    ///   - completion: 完成回调，返回拼接后的文字和整段音频
    func convertBatchImagesToSpeech(_ images: [Data], progressHandler: @escaping (ProcessingProgress) -> Void, completion: @escaping (Result<AudioResponse, ImageToSpeechProcessingError>) -> Void)

    /// 批量图片转语音处理（从指定阶段开始）
    /// - Parameters:
    ///   - images: 要处理的图片数据数组
    ///   - startStage: 启动阶段（.ocr / .llm / .tts）
    ///   - ocrTexts: 已有 OCR 文本数组（从 LLM/TTS 阶段启动时传入）
    ///   - ocrCombinedText: 已有 OCR 合并文本（从 TTS 阶段启动时传入）
    ///   - llmStoryName: 已有 LLM 故事名（从 TTS 阶段启动时传入）
    ///   - llmHighlights: 已有 LLM 要点（从 TTS 阶段启动时传入）
    ///   - progressHandler: 进度回调
    ///   - completion: 完成回调
    func convertBatchImagesToSpeech(_ images: [Data], startingFrom startStage: ProcessingProgress.ProcessingStage, ocrTexts: [String]?, ocrCombinedText: String?, llmStoryName: String?, llmHighlights: String?, progressHandler: @escaping (ProcessingProgress) -> Void, completion: @escaping (Result<AudioResponse, ImageToSpeechProcessingError>) -> Void)

    /// 文字转语音处理
    /// - Parameters:
    ///   - text: 要转换的文字内容
    ///   - completion: 完成回调，返回处理结果或错误
    func convertTextToSpeech(_ text: String, completion: @escaping (Result<AudioResponse, ImageToSpeechProcessingError>) -> Void)
    
    /// 测试网络连接
    /// - Parameter completion: 完成回调，返回连接状态或错误
    func testNetworkConnection(completion: @escaping (Result<Bool, Error>) -> Void)
    
    /// 取消当前正在进行的处理任务
    func cancelProcessing()
}

// MARK: - 阶段结果
struct StageResults {
    let ocrTexts: [String]?           // OCR阶段完成后的文本数组
    let validImageCount: Int?         // 有效图片数
    let llmStoryName: String?         // LLM阶段完成后的故事名
    let llmHighlights: String?        // LLM阶段完成后的要点

    // 新增统计字段
    let totalImageCount: Int?         // 总图片数
    let ocrCompletedCount: Int?       // OCR已完成图片数
    let ocrCharCount: Int?            // OCR识别总字数
    let ocrDuration: TimeInterval?    // OCR耗时
    let llmCharCount: Int?            // LLM分析字数
    let llmDuration: TimeInterval?    // LLM耗时
    let llmStatus: LLMStageStatus?    // LLM阶段状态

    // TTS统计字段
    let ttsCharCount: Int?            // TTS合成字数
    let ttsDuration: TimeInterval?    // TTS耗时
    let ttsStatus: TTSStageStatus?    // TTS阶段状态
    let ttsAudioSize: Int?            // TTS音频大小
    let ttsAudioDuration: TimeInterval?  // TTS音频时长
    let ttsSegmentCount: Int?         // TTS总分段数
    let ttsCompletedSegmentCount: Int? // TTS已完成分段数
    let ttsCurrentSegmentNumber: Int? // 当前更新的分段编号
    let ttsCurrentSegmentImageStartIndex: Int? // 当前分段起始图片索引
    let ttsCurrentSegmentImageEndIndex: Int? // 当前分段结束图片索引

    // 便利 init：TTS 参数默认 nil，兼容现有调用点
    init(ocrTexts: [String]? = nil, validImageCount: Int? = nil, llmStoryName: String? = nil, llmHighlights: String? = nil, totalImageCount: Int? = nil, ocrCompletedCount: Int? = nil, ocrCharCount: Int? = nil, ocrDuration: TimeInterval? = nil, llmCharCount: Int? = nil, llmDuration: TimeInterval? = nil, llmStatus: LLMStageStatus? = nil, ttsCharCount: Int? = nil, ttsDuration: TimeInterval? = nil, ttsStatus: TTSStageStatus? = nil, ttsAudioSize: Int? = nil, ttsAudioDuration: TimeInterval? = nil, ttsSegmentCount: Int? = nil, ttsCompletedSegmentCount: Int? = nil, ttsCurrentSegmentNumber: Int? = nil, ttsCurrentSegmentImageStartIndex: Int? = nil, ttsCurrentSegmentImageEndIndex: Int? = nil) {
        self.ocrTexts = ocrTexts
        self.validImageCount = validImageCount
        self.llmStoryName = llmStoryName
        self.llmHighlights = llmHighlights
        self.totalImageCount = totalImageCount
        self.ocrCompletedCount = ocrCompletedCount
        self.ocrCharCount = ocrCharCount
        self.ocrDuration = ocrDuration
        self.llmCharCount = llmCharCount
        self.llmDuration = llmDuration
        self.llmStatus = llmStatus
        self.ttsCharCount = ttsCharCount
        self.ttsDuration = ttsDuration
        self.ttsStatus = ttsStatus
        self.ttsAudioSize = ttsAudioSize
        self.ttsAudioDuration = ttsAudioDuration
        self.ttsSegmentCount = ttsSegmentCount
        self.ttsCompletedSegmentCount = ttsCompletedSegmentCount
        self.ttsCurrentSegmentNumber = ttsCurrentSegmentNumber
        self.ttsCurrentSegmentImageStartIndex = ttsCurrentSegmentImageStartIndex
        self.ttsCurrentSegmentImageEndIndex = ttsCurrentSegmentImageEndIndex
    }
}

// MARK: - 处理进度
struct ProcessingProgress {
    let stage: ProcessingStage
    let currentStep: Int
    let totalSteps: Int
    let percentage: Double
    let message: String

    // 阶段结果
    let stageResults: StageResults?

    enum ProcessingStage {
        case ocr
        case llm      // LLM分析阶段
        case tts
        case completed
        case failed
    }

    init(stage: ProcessingStage, currentStep: Int, totalSteps: Int, message: String, stageResults: StageResults? = nil) {
        self.stage = stage
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.message = message
        self.percentage = Double(currentStep) / Double(totalSteps) * 100.0
        self.stageResults = stageResults
    }

    init(stage: ProcessingStage, currentStep: Int, totalSteps: Int, message: String, percentage: Double, stageResults: StageResults? = nil) {
        self.stage = stage
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.message = message
        self.percentage = percentage
        self.stageResults = stageResults
    }
}

// MARK: - 图片转语音处理错误
enum ImageToSpeechProcessingError: Error, LocalizedError {
    case ocrFailed(Error)
    case llmFailed(Error)
    case ttsFailed(Error)
    case partialSuccess([AudioResponse], [Error])
    case cancelled

    var errorDescription: String? {
        switch self {
        case .ocrFailed:
            return "文字识别失败，请检查图片质量或重试"
        case .llmFailed:
            return "绘本分析失败，请检查网络连接或重试"
        case .ttsFailed:
            return "文字转语音失败，请检查文字内容或重试"
        case .partialSuccess:
            return "部分处理成功，部分失败"
        case .cancelled:
            return "处理已取消"
        }
    }

    var technicalDescription: String {
        switch self {
        case .ocrFailed(let error):
            return "ImageToSpeechProcessingError.ocrFailed: \(error.localizedDescription)"
        case .llmFailed(let error):
            return "ImageToSpeechProcessingError.llmFailed: \(error.localizedDescription)"
        case .ttsFailed(let error):
            return "ImageToSpeechProcessingError.ttsFailed: \(error.localizedDescription)"
        case .partialSuccess(let responses, let errors):
            return "ImageToSpeechProcessingError.partialSuccess: \(responses.count) succeeded, \(errors.count) failed"
        case .cancelled:
            return "ImageToSpeechProcessingError.cancelled"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .ocrFailed:
            return "请检查图片质量或重试"
        case .llmFailed:
            return "请检查网络连接或重试"
        case .ttsFailed:
            return "请检查文字内容或重试"
        case .partialSuccess:
            return "请查看详细结果"
        case .cancelled:
            return "可以重新开始处理"
        }
    }
}

// MARK: - 图片转语音协调器
/// 图片转语音协调器，负责协调OCR和TTS两个阶段的处理流程
/// 管理处理状态、进度跟踪、错误处理和任务取消
class ImageToSpeechCoordinator: ImageToSpeechCoordinatorProtocol, ObservableObject {

    struct PlannedTTSSegment: Equatable {
        let sequenceNumber: Int
        let text: String
        let imageStartIndex: Int
        let imageEndIndex: Int
        let textStartOffset: Int
        let textEndOffset: Int
    }
    
    // MARK: - 属性
    /// 网络服务，用于调用TTS API
    private let networkService: NetworkServiceProtocol
    /// 设置管理器，用于获取用户配置
    private let settingsManager: SettingsManager
    /// OCR服务，用于文字识别
    private let ocrService: OCRServiceProtocol?
    /// LLM服务，用于绘本分析
    private let llmService: LLMServiceProtocol?
    /// 当前是否正在处理中
    private var isProcessing = false
    /// 当前处理任务，用于支持取消操作
    private var currentTask: DispatchWorkItem?
    /// 所属任务标识（用于 OCR 跨任务串行闸门），默认随机 UUID 兼容非后台场景
    private let ownerTaskId: String

    // MARK: - 初始化
    init(networkService: NetworkServiceProtocol,
         settingsManager: SettingsManager = .shared,
         ownerTaskId: String = UUID().uuidString,
         ocrService: OCRServiceProtocol? = OCRServiceFactory.createOCRService(),
         llmService: LLMServiceProtocol? = LLMServiceFactory.createLLMService()) {
        self.networkService = networkService
        self.settingsManager = settingsManager
        self.ownerTaskId = ownerTaskId
        self.ocrService = ocrService
        self.llmService = llmService

        if self.ocrService == nil {
            logError("ImageToSpeechCoordinator: OCR服务初始化失败")
        } else {
            logInfo("ImageToSpeechCoordinator: OCR服务初始化成功")
        }

        if self.llmService == nil {
            logWarning("ImageToSpeechCoordinator: LLM服务初始化失败，将跳过绘本分析")
        } else {
            logInfo("ImageToSpeechCoordinator: LLM服务初始化成功")
        }
    }
    
    
    private func failWithLLMError(_ error: Error, progressHandler: @escaping (ProcessingProgress) -> Void, completion: @escaping (Result<AudioResponse, ImageToSpeechProcessingError>) -> Void) {
        self.isProcessing = false
        progressHandler(ProcessingProgress(
            stage: .failed,
            currentStep: 0,
            totalSteps: 100,
            message: "LLM分析失败: \(error.localizedDescription)",
            percentage: 0.0
        ))
        completion(.failure(.llmFailed(error)))
    }

    private func unusableLLMResultError() -> LLMError {
        LLMError.parsingError("LLM返回内容不可用：未生成绘本名称或绘本要点")
    }

    // MARK: - 批量图片转语音处理

    func convertBatchImagesToSpeech(_ images: [Data], progressHandler: @escaping (ProcessingProgress) -> Void, completion: @escaping (Result<AudioResponse, ImageToSpeechProcessingError>) -> Void) {
        guard !isProcessing else {
            completion(.failure(.ttsFailed(NetworkError.serverError)))
            return
        }

        guard !images.isEmpty else {
            completion(.failure(.ttsFailed(NetworkError.noTexts)))
            return
        }

        guard images.count <= Constants.maxBatchImageCount else {
            completion(.failure(.ttsFailed(NetworkError.tooManyTexts)))
            return
        }

        isProcessing = true

        // 步骤0:报告OCR开始
        progressHandler(ProcessingProgress(stage: .ocr, currentStep: 0, totalSteps: 4, message: "OCR识别进度: 开始"))

        Task {
            do {
                // 步骤1: 并发OCR识别 (0~50%)
                let recognizedTexts = try await performConcurrentOCR(images: images, progressHandler: progressHandler)

                // 步骤2: 拼接文字
                let (combinedText, validImageCount) = try combineOCRResults(recognizedTexts)

                await MainActor.run {
                    // 计算 OCR 总字数
                    let ocrCharCount = recognizedTexts.reduce(0) { $0 + $1.count }
                    progressHandler(ProcessingProgress(
                        stage: .ocr,
                        currentStep: 50,
                        totalSteps: 100,
                        message: "OCR识别进度: 完成",
                        percentage: 50.0,
                        stageResults: StageResults(
                            ocrTexts: recognizedTexts,
                            validImageCount: validImageCount,
                            llmStoryName: nil,
                            llmHighlights: nil,
                            totalImageCount: images.count,
                            ocrCompletedCount: images.count,
                            ocrCharCount: ocrCharCount,
                            ocrDuration: nil,
                            llmCharCount: nil,
                            llmDuration: nil,
                            llmStatus: nil
                        )
                    ))
                }

                // 步骤3: LLM分析 (50~70%)
                var llmResult: LLMStoryAnalysisResult?
                var finalText = combinedText
                var finalSegments = recognizedTexts
                var storyHighlights: String?
                var hasVirtualPage = false

                await MainActor.run {
                    progressHandler(ProcessingProgress(
                        stage: .llm,
                        currentStep: 50,
                        totalSteps: 100,
                        message: "LLM分析: 分析中",
                        percentage: 50.0,
                        stageResults: StageResults(
                            ocrTexts: nil,
                            validImageCount: nil,
                            llmStoryName: nil,
                            llmHighlights: nil,
                            totalImageCount: nil,
                            ocrCompletedCount: nil,
                            ocrCharCount: nil,
                            ocrDuration: nil,
                            llmCharCount: nil,
                            llmDuration: nil,
                            llmStatus: .inProgress
                        )
                    ))
                }

                // 调用LLM分析（失败不阻断主流程）
                // 图片少于5张时跳过LLM分析
                if images.count < Constants.LLM.minImageCountForAnalysis {
                    logInfo("LLM分析跳过：图片数量 \(images.count) 少于 \(Constants.LLM.minImageCountForAnalysis)")
                    await MainActor.run {
                        progressHandler(ProcessingProgress(
                            stage: .llm,
                            currentStep: 70,
                            totalSteps: 100,
                            message: "LLM分析: 跳过（图片少于5张）",
                            percentage: 70.0,
                            stageResults: StageResults(
                                ocrTexts: nil,
                                validImageCount: nil,
                                llmStoryName: nil,
                                llmHighlights: nil,
                                totalImageCount: nil,
                                ocrCompletedCount: nil,
                                ocrCharCount: nil,
                                ocrDuration: nil,
                                llmCharCount: nil,
                                llmDuration: nil,
                                llmStatus: .skipped
                            )
                        ))
                    }
                } else if let llmService = llmService {
                    do {
                        llmResult = try await llmService.analyzeStory(ocrText: combinedText)

                        if let result = llmResult, !result.isSuccess {
                            let error = self.unusableLLMResultError()
                            await MainActor.run {
                                self.failWithLLMError(error, progressHandler: progressHandler, completion: completion)
                            }
                            return
                        }

                        // 应用LLM结果
                        if let result = llmResult {
                            // 要点成功：追加到ocrTextSegments和ocrText
                            if result.isHighlightsSuccess, let highlights = result.storyHighlights {
                                finalSegments.append(highlights)
                                finalText = combinedText + AppConstants.ocrTextSeparator + highlights
                                storyHighlights = highlights
                                hasVirtualPage = true
                            }
                        }

                        let capturedStoryName = llmResult?.storyName
                        let capturedHighlights = storyHighlights
                        // 计算 LLM 字数
                        let llmCharCount = (capturedStoryName?.count ?? 0) + (capturedHighlights?.count ?? 0)
                        await MainActor.run {
                            progressHandler(ProcessingProgress(
                                stage: .llm,
                                currentStep: 70,
                                totalSteps: 100,
                                message: "LLM分析: 完成",
                                percentage: 70.0,
                                stageResults: StageResults(
                                    ocrTexts: recognizedTexts,
                                    validImageCount: validImageCount,
                                    llmStoryName: capturedStoryName,
                                    llmHighlights: capturedHighlights,
                                    totalImageCount: nil,
                                    ocrCompletedCount: nil,
                                    ocrCharCount: nil,
                                    ocrDuration: nil,
                                    llmCharCount: llmCharCount,
                                    llmDuration: nil,
                                    llmStatus: .completed
                                )
                            ))
                        }
                    } catch {
                        logWarning("LLM分析失败，暂停制作: \(error.localizedDescription)")
                        await MainActor.run {
                            self.failWithLLMError(error, progressHandler: progressHandler, completion: completion)
                        }
                        return
                    }
                } else {
                    // LLM服务未初始化，跳过
                    await MainActor.run {
                        progressHandler(ProcessingProgress(
                            stage: .llm,
                            currentStep: 70,
                            totalSteps: 100,
                            message: "LLM分析: 未配置",
                            percentage: 70.0,
                            stageResults: StageResults(
                                ocrTexts: nil,
                                validImageCount: nil,
                                llmStoryName: nil,
                                llmHighlights: nil,
                                totalImageCount: nil,
                                ocrCompletedCount: nil,
                                ocrCharCount: nil,
                                ocrDuration: nil,
                                llmCharCount: nil,
                                llmDuration: nil,
                                llmStatus: .notConfigured
                            )
                        ))
                    }
                }

                // 步骤4: TTS合成整段音频 (70~100%)
                await MainActor.run {
                    progressHandler(ProcessingProgress(
                        stage: .tts,
                        currentStep: 70,
                        totalSteps: 100,
                        message: "TTS合成进度: 开始合成",
                        percentage: 70.0,
                        stageResults: StageResults(
                            ocrTexts: nil, validImageCount: nil, llmStoryName: nil, llmHighlights: nil,
                            totalImageCount: nil, ocrCompletedCount: nil, ocrCharCount: nil, ocrDuration: nil,
                            llmCharCount: nil, llmDuration: nil, llmStatus: nil,
                            ttsCharCount: nil, ttsDuration: nil, ttsStatus: .inProgress, ttsAudioSize: nil, ttsAudioDuration: nil
                        )
                    ))
                }

                // 使用同步方式调用TTS
                let audioResponse = try await synthesizeSegmentedSpeech(
                    finalText: finalText,
                    finalSegments: finalSegments,
                    validImageCount: validImageCount,
                    storyName: llmResult?.storyName,
                    storyHighlights: storyHighlights,
                    hasVirtualPage: hasVirtualPage,
                    progressHandler: progressHandler
                )

                // 报告TTS完成
                let ttsCharCount = finalText.count
                let ttsAudioSize = audioResponse.audioData?.count
                let ttsAudioDuration = audioResponse.duration
                await MainActor.run {
                    progressHandler(ProcessingProgress(
                        stage: .tts,
                        currentStep: 100,
                        totalSteps: 100,
                        message: "TTS合成进度: 完成",
                        percentage: 100.0,
                        stageResults: StageResults(
                            ocrTexts: nil, validImageCount: nil, llmStoryName: nil, llmHighlights: nil,
                            totalImageCount: nil, ocrCompletedCount: nil, ocrCharCount: nil, ocrDuration: nil,
                            llmCharCount: nil, llmDuration: nil, llmStatus: nil,
                            ttsCharCount: ttsCharCount, ttsDuration: nil, ttsStatus: .completed,
                            ttsAudioSize: ttsAudioSize, ttsAudioDuration: ttsAudioDuration
                        )
                    ))
                }

                // 创建包含拼接后文字的完整响应
                await MainActor.run {
                    self.isProcessing = false
                    progressHandler(ProcessingProgress(
                        stage: .completed,
                        currentStep: 100,
                        totalSteps: 100,
                        message: "批量处理完成",
                        percentage: 100.0
                    ))
                    completion(.success(audioResponse))
                }

            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    progressHandler(ProcessingProgress(
                        stage: .failed,
                        currentStep: 0,
                        totalSteps: 100,
                        message: "批量处理失败: \(error.localizedDescription)",
                        percentage: 0.0
                    ))
                    completion(.failure(.ocrFailed(error)))
                }
            }
        }
    }
    
    // MARK: - 批量图片转语音处理（从指定阶段开始）

    func convertBatchImagesToSpeech(_ images: [Data], startingFrom startStage: ProcessingProgress.ProcessingStage, ocrTexts: [String]?, ocrCombinedText: String?, llmStoryName: String?, llmHighlights: String?, progressHandler: @escaping (ProcessingProgress) -> Void, completion: @escaping (Result<AudioResponse, ImageToSpeechProcessingError>) -> Void) {
        guard !isProcessing else {
            completion(.failure(.ttsFailed(NetworkError.serverError)))
            return
        }

        isProcessing = true

        switch startStage {
        case .ocr:
            // 从头开始，委托给原方法
            isProcessing = false
            convertBatchImagesToSpeech(images, progressHandler: progressHandler, completion: completion)

        case .llm:
            // 从 LLM 阶段开始，需要 ocrTexts
            guard let ocrTexts = ocrTexts, !ocrTexts.isEmpty else {
                isProcessing = false
                completion(.failure(.llmFailed(NetworkError.noTexts)))
                return
            }
            Task {
                do {
                    let (combinedText, validImageCount) = try self.combineOCRResults(ocrTexts)
                    await self.performLLMAndTTS(
                        images: images,
                        recognizedTexts: ocrTexts,
                        combinedText: combinedText,
                        validImageCount: validImageCount,
                        progressHandler: progressHandler,
                        completion: completion
                    )
                } catch {
                    await MainActor.run {
                        self.isProcessing = false
                        completion(.failure(.llmFailed(error)))
                    }
                }
            }

        case .tts:
            // 从 TTS 阶段开始，需要 ocrTexts + ocrCombinedText
            guard let ocrTexts = ocrTexts, !ocrTexts.isEmpty,
                  let ocrCombinedText = ocrCombinedText else {
                isProcessing = false
                completion(.failure(.ttsFailed(NetworkError.noTexts)))
                return
            }
            let validImageCount = ocrTexts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count

            // 重建 finalText 和 finalSegments（考虑 LLM highlights）
            var finalText = ocrCombinedText
            var finalSegments = ocrTexts
            var hasVirtualPage = false
            if let highlights = llmHighlights, !highlights.isEmpty {
                finalSegments.append(highlights)
                finalText = ocrCombinedText + AppConstants.ocrTextSeparator + highlights
                hasVirtualPage = true
            }

            Task {
                do {
                    await MainActor.run {
                        progressHandler(ProcessingProgress(
                            stage: .tts,
                            currentStep: 70,
                            totalSteps: 100,
                            message: "TTS合成进度: 开始合成",
                            percentage: 70.0
                        ))
                    }

                    let audioResponse = try await self.synthesizeSegmentedSpeech(
                        finalText: finalText,
                        finalSegments: finalSegments,
                        validImageCount: validImageCount,
                        storyName: llmStoryName,
                        storyHighlights: llmHighlights,
                        hasVirtualPage: hasVirtualPage,
                        progressHandler: progressHandler
                    )

                    let ttsCharCount = finalText.count
                    let ttsAudioSize = audioResponse.audioData?.count
                    let ttsAudioDuration = audioResponse.duration
                    await MainActor.run {
                        progressHandler(ProcessingProgress(
                            stage: .tts,
                            currentStep: 100,
                            totalSteps: 100,
                            message: "TTS合成进度: 完成",
                            percentage: 100.0,
                            stageResults: StageResults(
                                ocrTexts: nil, validImageCount: nil, llmStoryName: nil, llmHighlights: nil,
                                totalImageCount: nil, ocrCompletedCount: nil, ocrCharCount: nil, ocrDuration: nil,
                                llmCharCount: nil, llmDuration: nil, llmStatus: nil,
                                ttsCharCount: ttsCharCount, ttsDuration: nil, ttsStatus: .completed,
                                ttsAudioSize: ttsAudioSize, ttsAudioDuration: ttsAudioDuration
                            )
                        ))
                    }

                    await MainActor.run {
                        self.isProcessing = false
                        progressHandler(ProcessingProgress(
                            stage: .completed,
                            currentStep: 100,
                            totalSteps: 100,
                            message: "批量处理完成",
                            percentage: 100.0
                        ))
                        completion(.success(audioResponse))
                    }
                } catch {
                    await MainActor.run {
                        self.isProcessing = false
                        progressHandler(ProcessingProgress(
                            stage: .failed,
                            currentStep: 0,
                            totalSteps: 100,
                            message: "TTS合成失败: \(error.localizedDescription)",
                            percentage: 0.0
                        ))
                        completion(.failure(.ttsFailed(error)))
                    }
                }
            }

        case .completed, .failed:
            isProcessing = false
            return
        }
    }

    // MARK: - 文字转语音处理

    func convertTextToSpeech(_ text: String, completion: @escaping (Result<AudioResponse, ImageToSpeechProcessingError>) -> Void) {
        guard !isProcessing else {
            completion(.failure(.ttsFailed(NetworkError.serverError)))
            return
        }
        
        isProcessing = true
        
        Task {
            do {
                let audioResponse = try await convertTextToSpeechAsync(text)
                
                await MainActor.run {
                    self.isProcessing = false
                    completion(.success(audioResponse))
                }
                
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    completion(.failure(.ttsFailed(error)))
                }
            }
        }
    }
    
    // MARK: - 网络连接测试
    
    func testNetworkConnection(completion: @escaping (Result<Bool, Error>) -> Void) {
        networkService.testConnection(completion: completion)
    }
    
    // MARK: - LLM + TTS 流程（从 LLM 阶段开始）

    private func performLLMAndTTS(
        images: [Data],
        recognizedTexts: [String],
        combinedText: String,
        validImageCount: Int,
        progressHandler: @escaping (ProcessingProgress) -> Void,
        completion: @escaping (Result<AudioResponse, ImageToSpeechProcessingError>) -> Void
    ) async {
        do {
            // LLM 阶段
            await MainActor.run {
                progressHandler(ProcessingProgress(
                    stage: .llm,
                    currentStep: 50,
                    totalSteps: 100,
                    message: "LLM分析: 分析中",
                    percentage: 50.0,
                    stageResults: StageResults(
                        ocrTexts: nil, validImageCount: nil, llmStoryName: nil, llmHighlights: nil,
                        totalImageCount: nil, ocrCompletedCount: nil, ocrCharCount: nil, ocrDuration: nil,
                        llmCharCount: nil, llmDuration: nil, llmStatus: .inProgress
                    )
                ))
            }

            var llmResult: LLMStoryAnalysisResult?
            var finalText = combinedText
            var finalSegments = recognizedTexts
            var storyHighlights: String?
            var hasVirtualPage = false

            if images.count < Constants.LLM.minImageCountForAnalysis {
                logInfo("LLM分析跳过：图片数量 \(images.count) 少于 \(Constants.LLM.minImageCountForAnalysis)")
                await MainActor.run {
                    progressHandler(ProcessingProgress(
                        stage: .llm, currentStep: 70, totalSteps: 100,
                        message: "LLM分析: 跳过（图片少于5张）", percentage: 70.0,
                        stageResults: StageResults(
                            ocrTexts: nil, validImageCount: nil, llmStoryName: nil, llmHighlights: nil,
                            totalImageCount: nil, ocrCompletedCount: nil, ocrCharCount: nil, ocrDuration: nil,
                            llmCharCount: nil, llmDuration: nil, llmStatus: .skipped
                        )
                    ))
                }
            } else if let llmService = llmService {
                do {
                    llmResult = try await llmService.analyzeStory(ocrText: combinedText)
                    if let result = llmResult, !result.isSuccess {
                        let error = self.unusableLLMResultError()
                        await MainActor.run {
                            self.failWithLLMError(error, progressHandler: progressHandler, completion: completion)
                        }
                        return
                    }
                    if let result = llmResult {
                        if result.isHighlightsSuccess, let highlights = result.storyHighlights {
                            finalSegments.append(highlights)
                            finalText = combinedText + AppConstants.ocrTextSeparator + highlights
                            storyHighlights = highlights
                            hasVirtualPage = true
                        }
                    }
                    let capturedStoryName = llmResult?.storyName
                    let capturedHighlights = storyHighlights
                    let llmCharCount = (capturedStoryName?.count ?? 0) + (capturedHighlights?.count ?? 0)
                    await MainActor.run {
                        progressHandler(ProcessingProgress(
                            stage: .llm, currentStep: 70, totalSteps: 100,
                            message: "LLM分析: 完成", percentage: 70.0,
                            stageResults: StageResults(
                                ocrTexts: recognizedTexts, validImageCount: validImageCount,
                                llmStoryName: capturedStoryName, llmHighlights: capturedHighlights,
                                totalImageCount: nil, ocrCompletedCount: nil, ocrCharCount: nil, ocrDuration: nil,
                                llmCharCount: llmCharCount, llmDuration: nil, llmStatus: .completed
                            )
                        ))
                    }
                } catch {
                    logWarning("LLM分析失败，暂停制作: \(error.localizedDescription)")
                    await MainActor.run {
                        self.failWithLLMError(error, progressHandler: progressHandler, completion: completion)
                    }
                    return
                }
            } else {
                await MainActor.run {
                    progressHandler(ProcessingProgress(
                        stage: .llm, currentStep: 70, totalSteps: 100,
                        message: "LLM分析: 未配置", percentage: 70.0,
                        stageResults: StageResults(
                            ocrTexts: nil, validImageCount: nil, llmStoryName: nil, llmHighlights: nil,
                            totalImageCount: nil, ocrCompletedCount: nil, ocrCharCount: nil, ocrDuration: nil,
                            llmCharCount: nil, llmDuration: nil, llmStatus: .notConfigured
                        )
                    ))
                }
            }

            // TTS 阶段
            await MainActor.run {
                progressHandler(ProcessingProgress(
                    stage: .tts, currentStep: 70, totalSteps: 100,
                    message: "TTS合成进度: 开始合成", percentage: 70.0
                ))
            }

            let audioResponse = try await synthesizeSegmentedSpeech(
                finalText: finalText,
                finalSegments: finalSegments,
                validImageCount: validImageCount,
                storyName: llmResult?.storyName,
                storyHighlights: storyHighlights,
                hasVirtualPage: hasVirtualPage,
                progressHandler: progressHandler
            )

            let ttsCharCount = finalText.count
            let ttsAudioSize = audioResponse.audioData?.count
            let ttsAudioDuration = audioResponse.duration
            await MainActor.run {
                progressHandler(ProcessingProgress(
                    stage: .tts, currentStep: 100, totalSteps: 100,
                    message: "TTS合成进度: 完成", percentage: 100.0,
                    stageResults: StageResults(
                        ocrTexts: nil, validImageCount: nil, llmStoryName: nil, llmHighlights: nil,
                        totalImageCount: nil, ocrCompletedCount: nil, ocrCharCount: nil, ocrDuration: nil,
                        llmCharCount: nil, llmDuration: nil, llmStatus: nil,
                        ttsCharCount: ttsCharCount, ttsDuration: nil, ttsStatus: .completed,
                        ttsAudioSize: ttsAudioSize, ttsAudioDuration: ttsAudioDuration
                    )
                ))
            }

            await MainActor.run {
                self.isProcessing = false
                progressHandler(ProcessingProgress(
                    stage: .completed, currentStep: 100, totalSteps: 100,
                    message: "批量处理完成", percentage: 100.0
                ))
                completion(.success(audioResponse))
            }
        } catch {
            await MainActor.run {
                self.isProcessing = false
                progressHandler(ProcessingProgress(
                    stage: .failed, currentStep: 0, totalSteps: 100,
                    message: "处理失败: \(error.localizedDescription)", percentage: 0.0
                ))
                completion(.failure(.ttsFailed(error)))
            }
        }
    }

    // MARK: - 取消处理

    func cancelProcessing() {
        guard isProcessing else { return }
        
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
    }
    
    /// 拼接OCR结果
    private func combineOCRResults(_ results: [String]) throws -> (text: String, validImageCount: Int) {
        var combinedText = ""
        var emptyResultCount = 0
        var failedResultCount = 0
        
        for (index, text) in results.enumerated() {
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText == AppConstants.ocrEmptyResultIndicator {
                emptyResultCount += 1
                logWarning("空图片：第 \(index + 1) 张图片为空（返回了系统保留字符 \(AppConstants.ocrEmptyResultIndicator)）")
                // 即使为空，也保留位置，添加空字符串和分隔符
                combinedText += "" + (index < results.count - 1 ? AppConstants.ocrTextSeparator : "")
            } else if trimmedText.isEmpty {
                // OCR失败的情况，也保留位置
                failedResultCount += 1
                logWarning("OCR失败：第 \(index + 1) 张图片OCR识别失败，保留空文本记录项")
                // 即使失败，也保留位置，添加空字符串和分隔符
                combinedText += "" + (index < results.count - 1 ? AppConstants.ocrTextSeparator : "")
            } else {
                // 正常情况，添加文本和分隔符
                combinedText += text + (index < results.count - 1 ? AppConstants.ocrTextSeparator : "")
            }
        }

        combinedText = combinedText.replacingOccurrences(of: AppConstants.ocrEmptyResultIndicator, with: "")

        let validImageCount = results.count - emptyResultCount - failedResultCount
        logInfo("OCR拼接完成：总长度 \(combinedText.count)，空图片 \(emptyResultCount) 张，失败 \(failedResultCount) 张，有效图片 \(validImageCount) 张")
        return (combinedText, validImageCount)
    }

    func buildTTSSegments(
        from recognizedTexts: [String],
        characterLimit: Int = Constants.TTS.segmentCharacterLimit,
        isolateLastSegment: Bool = false
    ) -> [PlannedTTSSegment] {
        guard !recognizedTexts.isEmpty else { return [] }

        var planned: [PlannedTTSSegment] = []
        var currentTexts: [String] = []
        var currentStartIndex = 0
        var currentCharCount = 0
        var currentTextStartOffset = 0
        var globalOffset = 0

        func flush(endImageIndex: Int, endOffset: Int) {
            guard !currentTexts.isEmpty else { return }
            planned.append(
                PlannedTTSSegment(
                    sequenceNumber: planned.count + 1,
                    text: currentTexts.joined(separator: AppConstants.ocrTextSeparator),
                    imageStartIndex: currentStartIndex,
                    imageEndIndex: endImageIndex,
                    textStartOffset: currentTextStartOffset,
                    textEndOffset: endOffset
                )
            )
            currentTexts = []
            currentCharCount = 0
        }

        for (index, text) in recognizedTexts.enumerated() {
            let separator = currentTexts.isEmpty ? 0 : AppConstants.ocrTextSeparator.count
            let candidateCount = currentCharCount + separator + text.count
            let itemStartOffset = globalOffset
            let itemEndOffset = globalOffset + max(0, text.count - 1)

            if isolateLastSegment, index == recognizedTexts.count - 1, !currentTexts.isEmpty {
                let previousEndOffset = max(currentTextStartOffset, itemStartOffset - AppConstants.ocrTextSeparator.count - 1)
                flush(endImageIndex: index - 1, endOffset: previousEndOffset)
                currentStartIndex = index
                currentTextStartOffset = itemStartOffset
            }

            if !currentTexts.isEmpty && candidateCount > characterLimit {
                let previousEndOffset = currentTextStartOffset + max(0, currentCharCount - 1)
                flush(endImageIndex: index - 1, endOffset: previousEndOffset)
                currentStartIndex = index
                currentTextStartOffset = itemStartOffset
            } else if currentTexts.isEmpty {
                currentStartIndex = index
                currentTextStartOffset = itemStartOffset
            }

            currentTexts.append(text)
            currentCharCount = currentTexts.joined(separator: AppConstants.ocrTextSeparator).count

            if currentCharCount > characterLimit && currentTexts.count == 1 {
                flush(endImageIndex: index, endOffset: itemEndOffset)
                currentStartIndex = index + 1
                currentTextStartOffset = globalOffset + text.count + AppConstants.ocrTextSeparator.count
            }

            globalOffset += text.count
            if index < recognizedTexts.count - 1 {
                globalOffset += AppConstants.ocrTextSeparator.count
            }
        }

        if !currentTexts.isEmpty {
            flush(
                endImageIndex: recognizedTexts.count - 1,
                endOffset: max(currentTextStartOffset, globalOffset - 1)
            )
        }

        return planned
    }

    private func synthesizeSegmentedSpeech(
        finalText: String,
        finalSegments: [String],
        validImageCount: Int,
        storyName: String?,
        storyHighlights: String?,
        hasVirtualPage: Bool,
        progressHandler: @escaping (ProcessingProgress) -> Void
    ) async throws -> AudioResponse {
        let plannedSegments = buildTTSSegments(from: finalSegments, isolateLastSegment: hasVirtualPage)
        if plannedSegments.isEmpty {
            let audioResponse = try await convertTextToSpeechAsync(finalText)
            return AudioResponse(
                id: audioResponse.id,
                audioURL: audioResponse.audioURL,
                text: finalText,
                language: audioResponse.language,
                duration: audioResponse.duration,
                format: audioResponse.format,
                quality: audioResponse.quality,
                timestamp: audioResponse.timestamp,
                voiceSettings: audioResponse.voiceSettings,
                audioData: audioResponse.audioData,
                validImageCount: validImageCount,
                recognizedTexts: finalSegments,
                audioSegments: nil,
                storyName: storyName,
                storyHighlights: storyHighlights,
                hasVirtualPage: hasVirtualPage
            )
        }

        struct SegmentSynthesisResult {
            let planned: PlannedTTSSegment
            let response: AudioResponse
            let elapsed: TimeInterval
        }

        var collectedSegments: [TTSAudioSegment] = []
        var totalAudioData = Data()
        var totalDuration: TimeInterval = 0
        var responseFormat = "mp3"
        var responseQuality = "high"
        var responseLanguage = "zh"
        var responseTimestamp = Date()
        var responseVoiceSettings: VoiceSettings?
        let totalSegmentCount = plannedSegments.count
        var completedSegmentCount = 0

        await MainActor.run {
            progressHandler(ProcessingProgress(
                stage: .tts,
                currentStep: 70,
                totalSteps: 100,
                message: "TTS合成进度: 音频分段 0/\(totalSegmentCount)",
                percentage: 70.0,
                stageResults: StageResults(
                    ttsStatus: .inProgress,
                    ttsSegmentCount: totalSegmentCount,
                    ttsCompletedSegmentCount: 0
                )
            ))
        }

        for batch in plannedSegments.chunked(into: Constants.TTS.segmentConcurrentLimit) {
            let batchResults = try await withThrowingTaskGroup(of: SegmentSynthesisResult.self) { group in
                for planned in batch {
                    group.addTask {
                        let startTime = Date()
                        self.logInfo("TTS分段开始: 第\(planned.sequenceNumber)/\(totalSegmentCount)段, 图片=\(planned.imageStartIndex + 1)-\(planned.imageEndIndex + 1), 字数=\(planned.text.count)")
                        do {
                            let response = try await self.convertTextToSpeechAsync(planned.text)
                            let elapsed = Date().timeIntervalSince(startTime)
                            self.logInfo("TTS分段完成: 第\(planned.sequenceNumber)/\(totalSegmentCount)段, 图片=\(planned.imageStartIndex + 1)-\(planned.imageEndIndex + 1), 耗时=\(String(format: "%.2f", elapsed))s")
                            return SegmentSynthesisResult(planned: planned, response: response, elapsed: elapsed)
                        } catch {
                            let elapsed = Date().timeIntervalSince(startTime)
                            self.logError("TTS分段失败: 第\(planned.sequenceNumber)/\(totalSegmentCount)段, 图片=\(planned.imageStartIndex + 1)-\(planned.imageEndIndex + 1), 耗时=\(String(format: "%.2f", elapsed))s, 错误=\(error.localizedDescription)")
                            throw error
                        }
                    }
                }

                var results: [SegmentSynthesisResult] = []
                for try await result in group {
                    results.append(result)
                }
                return results
            }

            for result in batchResults.sorted(by: { $0.planned.sequenceNumber < $1.planned.sequenceNumber }) {
                let planned = result.planned
                let response = result.response
                responseFormat = response.format
                responseQuality = response.quality
                responseLanguage = response.language
                responseTimestamp = response.timestamp
                responseVoiceSettings = response.voiceSettings
                if let audioData = response.audioData {
                    totalAudioData.append(audioData)
                }
                totalDuration += response.duration
                completedSegmentCount += 1
                collectedSegments.append(
                    TTSAudioSegment(
                        id: response.id,
                        sequenceNumber: planned.sequenceNumber,
                        text: planned.text,
                        format: response.format,
                        duration: response.duration,
                        imageStartIndex: planned.imageStartIndex,
                        imageEndIndex: planned.imageEndIndex,
                        textStartOffset: planned.textStartOffset,
                        textEndOffset: planned.textEndOffset,
                        audioData: response.audioData
                    )
                )

                let progress = 70.0 + (Double(completedSegmentCount) / Double(totalSegmentCount) * 30.0)
                let completedCountSnapshot = completedSegmentCount
                let totalAudioSizeSnapshot = totalAudioData.count
                let totalDurationSnapshot = totalDuration
                let plannedSequenceNumber = planned.sequenceNumber
                let plannedImageStartIndex = planned.imageStartIndex
                let plannedImageEndIndex = planned.imageEndIndex
                await MainActor.run {
                    progressHandler(ProcessingProgress(
                        stage: .tts,
                        currentStep: Int(progress),
                        totalSteps: 100,
                        message: "TTS合成进度: 音频分段 \(completedCountSnapshot)/\(totalSegmentCount)",
                        percentage: progress,
                        stageResults: StageResults(
                            ttsCharCount: finalText.count,
                            ttsDuration: result.elapsed,
                            ttsStatus: completedCountSnapshot == totalSegmentCount ? .completed : .inProgress,
                            ttsAudioSize: totalAudioSizeSnapshot,
                            ttsAudioDuration: totalDurationSnapshot,
                            ttsSegmentCount: totalSegmentCount,
                            ttsCompletedSegmentCount: completedCountSnapshot,
                            ttsCurrentSegmentNumber: plannedSequenceNumber,
                            ttsCurrentSegmentImageStartIndex: plannedImageStartIndex,
                            ttsCurrentSegmentImageEndIndex: plannedImageEndIndex
                        )
                    ))
                }
            }
        }

        return AudioResponse(
            id: UUID().uuidString,
            audioURL: "",
            text: finalText,
            language: responseLanguage,
            duration: totalDuration,
            format: responseFormat,
            quality: responseQuality,
            timestamp: responseTimestamp,
            voiceSettings: responseVoiceSettings,
            audioData: totalAudioData.isEmpty ? nil : totalAudioData,
            validImageCount: validImageCount,
            recognizedTexts: finalSegments,
            audioSegments: collectedSegments,
            storyName: storyName,
            storyHighlights: storyHighlights,
            hasVirtualPage: hasVirtualPage
        )
    }
    
    // MARK: - 私有方法
    
    /// 读取TTS最大字符限制配置
    /// - Returns: TTS最大字符数，默认为1024
    private func getTTSMaxLength() -> Int {
        return settingsManager.getTTSMaxLength()
    }
    
    /// 读取OCR并发数配置
    /// - Returns: OCR并发数，默认为1
    private func getOCRConcurrentCount() -> Int {
        return settingsManager.getOCRConcurrentCount()
    }
    
    /// 执行并发OCR识别
    /// - Parameters:
    ///   - images: 图片数据数组
    ///   - progressHandler: 进度回调
    /// - Returns: 按顺序排列的识别结果
    private func performConcurrentOCR(images: [Data], progressHandler: @escaping (ProcessingProgress) -> Void) async throws -> [String] {
        guard let ocrService = ocrService else {
            throw ImageToSpeechProcessingError.ocrFailed(NetworkError.serverError)
        }

        // OCR 跨任务串行闸门：同一时刻仅 1 个任务持有，确保满足 OCR API 并发配额限制
        // 持有周期 = OCR 阶段全程，抛错/取消时通过 defer 保证释放
        let gateTaskId = ownerTaskId
        await OCRGlobalSerialGate.shared.acquire(taskId: gateTaskId)
        defer {
            // defer 是同步上下文，release 为 async，外包 Task 异步释放
            Task { await OCRGlobalSerialGate.shared.release(taskId: gateTaskId) }
        }

        let concurrentCount = getOCRConcurrentCount()
        let totalImages = images.count

        logInfo("开始并发OCR识别，图片数量: \(totalImages)，并发数: \(concurrentCount)，taskId: \(gateTaskId)")

        // 进度语义：
        // - 排队等待 OCR 闸门时保持 0%
        // - 一旦真正进入 OCR 阶段，立即推进到 1%，便于 UI 区分"排队中"与"正在制作"
        await MainActor.run {
            progressHandler(ProcessingProgress(
                stage: .ocr,
                currentStep: 1,
                totalSteps: 100,
                message: "OCR识别进度: 0/\(totalImages)",
                percentage: 1,
                stageResults: StageResults(
                    ocrTexts: [],
                    validImageCount: nil,
                    llmStoryName: nil,
                    llmHighlights: nil,
                    totalImageCount: totalImages,
                    ocrCompletedCount: 0,
                    ocrCharCount: nil,
                    ocrDuration: nil,
                    llmCharCount: nil,
                    llmDuration: nil,
                    llmStatus: nil
                )
            ))
        }
        
        // 分批处理图片，每批的并发数不超过配置的并发数
        let batchSize = concurrentCount
        let batches = images.chunked(into: batchSize)
        var allResults: [(Int, String)] = []
        
        for (batchIndex, batch) in batches.enumerated() {
            logInfo("处理第 \(batchIndex + 1)/\(batches.count) 批，包含 \(batch.count) 张图片")
            
            // 为当前批次的每张图片创建OCR任务
            await withTaskGroup(of: (Int, String).self) { group in
                for (imageIndex, image) in batch.enumerated() {
                    let globalIndex = batchIndex * batchSize + imageIndex
                    
                    group.addTask {
                        // 执行OCR识别，传递图片索引
                        // 即使OCR失败，也返回空字符串，保持索引对应关系
                        do {
                            let ocrResult = try await ocrService.recognizeText(from: image, imageIndex: globalIndex)
                            return (globalIndex, ocrResult.recognizedText)
                        } catch {
                            // OCR失败时，记录错误并返回空字符串，保持索引对应
                            // 在 TaskGroup 内无法调用 self 的实例方法，使用 os.Logger + directLog
                            os.Logger.coordinator.error("OCR识别失败，图片索引: \(globalIndex + 1)，错误: \(error.localizedDescription)")
                            DebugLogManager.shared.directLog("OCR识别失败，图片索引: \(globalIndex + 1)，错误: \(error.localizedDescription)")
                            return (globalIndex, "")
                        }
                    }
                }
                
                // 收集当前批次的结果
                var batchResults: [(Int, String)] = []
                for await (index, recognizedText) in group {
                    batchResults.append((index, recognizedText))
                }
                
                // 按索引排序并添加到总结果中
                let sortedBatchResults = batchResults.sorted { $0.0 < $1.0 }
                allResults.append(contentsOf: sortedBatchResults)
            }
            
            // 更新进度 (0-50%)
            let completedImages = allResults.count
            let progress = Double(completedImages) / Double(totalImages) * 0.5
            // 构建已完成部分的文字数组（按原始索引排序，未完成位置为空字符串）
            let sortedPartial = allResults.sorted { $0.0 < $1.0 }
            var partialTexts: [String] = Array(repeating: "", count: totalImages)
            for (index, text) in sortedPartial {
                if index < partialTexts.count {
                    partialTexts[index] = text
                }
            }
            // 只传已完成部分（截取到已完成数量）
            let partialOcrTexts = Array(partialTexts.prefix(completedImages))
            await MainActor.run {
                progressHandler(ProcessingProgress(
                    stage: .ocr,
                    currentStep: Int(progress * 100),
                    totalSteps: 100,
                    message: "OCR识别进度: \(completedImages)/\(totalImages)",
                    percentage: progress * 100,
                    stageResults: StageResults(
                        ocrTexts: partialOcrTexts,
                        validImageCount: nil,
                        llmStoryName: nil,
                        llmHighlights: nil,
                        totalImageCount: totalImages,
                        ocrCompletedCount: completedImages,
                        ocrCharCount: nil,
                        ocrDuration: nil,
                        llmCharCount: nil,
                        llmDuration: nil,
                        llmStatus: nil
                    )
                ))
            }
        }
        
        // 按原始顺序排序结果
        let sortedResults = allResults.sorted { $0.0 < $1.0 }
        
        // 确保结果数组长度等于输入图片数组长度，缺失的索引用空字符串填充
        var recognizedTexts: [String] = Array(repeating: "", count: totalImages)
        for (index, text) in sortedResults {
            if index < recognizedTexts.count {
                recognizedTexts[index] = text
            }
        }
        
        // 统计成功和失败的数量
        let successCount = recognizedTexts.filter { !$0.isEmpty && $0 != AppConstants.ocrEmptyResultIndicator }.count
        let emptyCount = recognizedTexts.filter { $0 == AppConstants.ocrEmptyResultIndicator }.count
        let failedCount = recognizedTexts.filter { $0.isEmpty }.count - emptyCount
        
        logInfo("并发OCR识别完成，处理了 \(recognizedTexts.count) 张图片（成功: \(successCount)，空图片: \(emptyCount)，失败: \(failedCount)）")
        return recognizedTexts
    }
    
    // MARK: - 日志方法
    private func logInfo(_ message: String) {
        os.Logger.coordinator.info("\(message)")
        DebugLogManager.shared.directLog(message)
    }

    private func logError(_ message: String) {
        os.Logger.coordinator.error("\(message)")
        DebugLogManager.shared.directLog(message)
    }

    private func logWarning(_ message: String) {
        os.Logger.coordinator.warning("\(message)")
        DebugLogManager.shared.directLog(message)
    }

    private func convertTextToSpeechAsync(_ text: String) async throws -> AudioResponse {
        return try await withCheckedThrowingContinuation { continuation in
            networkService.convertTextToSpeech(text, voiceSettings: settingsManager.voiceSettings) { result in
                switch result {
                case .success(let response):
                    continuation.resume(returning: response)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
