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

// MARK: - 处理进度
struct ProcessingProgress {
    let stage: ProcessingStage
    let currentStep: Int
    let totalSteps: Int
    let percentage: Double
    let message: String
    
    enum ProcessingStage {
        case ocr
        case llm      // LLM分析阶段
        case tts
        case completed
        case failed
    }
    
    init(stage: ProcessingStage, currentStep: Int, totalSteps: Int, message: String) {
        self.stage = stage
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.message = message
        self.percentage = Double(currentStep) / Double(totalSteps) * 100.0
    }
    
    init(stage: ProcessingStage, currentStep: Int, totalSteps: Int, message: String, percentage: Double) {
        self.stage = stage
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.message = message
        self.percentage = percentage
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
        case .ocrFailed(let error):
            return "文字识别失败: \(error.localizedDescription)"
        case .llmFailed(let error):
            return "绘本分析失败: \(error.localizedDescription)"
        case .ttsFailed(let error):
            return "文字转语音失败: \(error.localizedDescription)"
        case .partialSuccess:
            return "部分处理成功，部分失败"
        case .cancelled:
            return "处理已取消"
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
    
    // MARK: - 属性
    /// 网络服务，用于调用TTS API
    private let networkService: NetworkServiceProtocol
    /// 设置管理器，用于获取用户配置
    private let settingsManager: SettingsManager
    /// OCR服务，用于文字识别
    private let ocrService: OCRService?
    /// LLM服务，用于绘本分析
    private let llmService: LLMServiceProtocol?
    /// 当前是否正在处理中
    private var isProcessing = false
    /// 当前处理任务，用于支持取消操作
    private var currentTask: DispatchWorkItem?
    
    // MARK: - 初始化
    init(networkService: NetworkServiceProtocol, settingsManager: SettingsManager = .shared) {
        self.networkService = networkService
        self.settingsManager = settingsManager
        self.ocrService = OCRServiceFactory.createOCRService()
        self.llmService = LLMServiceFactory.createLLMService()

        if self.ocrService == nil {
            os.Logger.coordinator.error("ImageToSpeechCoordinator: OCR服务初始化失败")
        } else {
            os.Logger.coordinator.info("ImageToSpeechCoordinator: OCR服务初始化成功")
        }

        if self.llmService == nil {
            os.Logger.coordinator.warning("ImageToSpeechCoordinator: LLM服务初始化失败，将跳过绘本分析")
        } else {
            os.Logger.coordinator.info("ImageToSpeechCoordinator: LLM服务初始化成功")
        }
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
                await MainActor.run {
                    progressHandler(ProcessingProgress(
                        stage: .ocr,
                        currentStep: 50,
                        totalSteps: 100,
                        message: "OCR识别进度: 完成",
                        percentage: 50.0
                    ))
                }

                let (combinedText, validImageCount) = try combineOCRResults(recognizedTexts)

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
                        percentage: 50.0
                    ))
                }

                // 调用LLM分析（失败不阻断主流程）
                if let llmService = llmService {
                    do {
                        llmResult = try await llmService.analyzeStory(ocrText: combinedText)

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

                        await MainActor.run {
                            progressHandler(ProcessingProgress(
                                stage: .llm,
                                currentStep: 70,
                                totalSteps: 100,
                                message: "LLM分析: 完成",
                                percentage: 70.0
                            ))
                        }
                    } catch {
                        os.Logger.coordinator.warning("LLM分析失败，继续进入TTS: \(error.localizedDescription)")
                        await MainActor.run {
                            progressHandler(ProcessingProgress(
                                stage: .llm,
                                currentStep: 70,
                                totalSteps: 100,
                                message: "LLM分析: 跳过",
                                percentage: 70.0
                            ))
                        }
                    }
                } else {
                    // LLM服务未初始化，跳过
                    await MainActor.run {
                        progressHandler(ProcessingProgress(
                            stage: .llm,
                            currentStep: 70,
                            totalSteps: 100,
                            message: "LLM分析: 未配置",
                            percentage: 70.0
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
                        percentage: 70.0
                    ))
                }

                // 使用同步方式调用TTS
                let audioResponse = try await convertTextToSpeechAsync(finalText)

                // 报告TTS完成
                await MainActor.run {
                    progressHandler(ProcessingProgress(
                        stage: .tts,
                        currentStep: 100,
                        totalSteps: 100,
                        message: "TTS合成进度: 完成",
                        percentage: 100.0
                    ))
                }

                // 创建包含拼接后文字的完整响应
                let finalResponse = AudioResponse(
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
                    storyName: llmResult?.storyName,
                    storyHighlights: storyHighlights,
                    hasVirtualPage: hasVirtualPage
                )

                await MainActor.run {
                    self.isProcessing = false
                    progressHandler(ProcessingProgress(
                        stage: .completed,
                        currentStep: 100,
                        totalSteps: 100,
                        message: "批量处理完成",
                        percentage: 100.0
                    ))
                    completion(.success(finalResponse))
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
                os.Logger.coordinator.warning("空图片：第 \(index + 1) 张图片为空（返回了系统保留字符 \(AppConstants.ocrEmptyResultIndicator)）")
                // 即使为空，也保留位置，添加空字符串和分隔符
                combinedText += "" + (index < results.count - 1 ? AppConstants.ocrTextSeparator : "")
            } else if trimmedText.isEmpty {
                // OCR失败的情况，也保留位置
                failedResultCount += 1
                os.Logger.coordinator.warning("OCR失败：第 \(index + 1) 张图片OCR识别失败，保留空文本记录项")
                // 即使失败，也保留位置，添加空字符串和分隔符
                combinedText += "" + (index < results.count - 1 ? AppConstants.ocrTextSeparator : "")
            } else {
                // 正常情况，添加文本和分隔符
                combinedText += text + (index < results.count - 1 ? AppConstants.ocrTextSeparator : "")
            }
        }

        combinedText = combinedText.replacingOccurrences(of: AppConstants.ocrEmptyResultIndicator, with: "")

        // 检查文本是否超限
        let maxLength = getTTSMaxLength()
        if combinedText.count > maxLength {
            os.Logger.coordinator.error("OCR拼接文字超限：长度 \(combinedText.count)，限制 \(maxLength)")
            throw ImageToSpeechProcessingError.ttsFailed(NetworkError.textTooLong)
        }

        let validImageCount = results.count - emptyResultCount - failedResultCount
        os.Logger.coordinator.info("OCR拼接完成：总长度 \(combinedText.count)，限制 \(maxLength)，空图片 \(emptyResultCount) 张，失败 \(failedResultCount) 张，有效图片 \(validImageCount) 张")
        return (combinedText, validImageCount)
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
        
        let concurrentCount = getOCRConcurrentCount()
        let totalImages = images.count
        
        os.Logger.coordinator.info("开始并发OCR识别，图片数量: \(totalImages)，并发数: \(concurrentCount)")
        
        // 分批处理图片，每批的并发数不超过配置的并发数
        let batchSize = concurrentCount
        let batches = images.chunked(into: batchSize)
        var allResults: [(Int, String)] = []
        
        for (batchIndex, batch) in batches.enumerated() {
            os.Logger.coordinator.info("处理第 \(batchIndex + 1)/\(batches.count) 批，包含 \(batch.count) 张图片")
            
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
                            os.Logger.coordinator.error("OCR识别失败，图片索引: \(globalIndex + 1)，错误: \(error.localizedDescription)")
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
            
            // 更新进度 (0-70%)
            let completedImages = allResults.count
            let progress = Double(completedImages) / Double(totalImages) * 0.7
            await MainActor.run {
                progressHandler(ProcessingProgress(
                    stage: .ocr,
                    currentStep: Int(progress * 100),
                    totalSteps: 100,
                    message: "OCR识别进度: \(completedImages)/\(totalImages) (并发: \(concurrentCount))",
                    percentage: progress * 100
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
        
        os.Logger.coordinator.info("并发OCR识别完成，处理了 \(recognizedTexts.count) 张图片（成功: \(successCount)，空图片: \(emptyCount)，失败: \(failedCount)）")
        return recognizedTexts
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
