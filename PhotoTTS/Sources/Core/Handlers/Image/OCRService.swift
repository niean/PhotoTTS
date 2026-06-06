import Foundation
import CoreImage
import os.log

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - OCR服务协议
public protocol OCRServiceProtocol {
    func recognizeText(from imageData: Data) async throws -> OCRResult
    func recognizeText(from imageData: Data, withPrompt prompt: String) async throws -> OCRResult
}

// MARK: - OCR服务委托
public protocol OCRServiceDelegate: AnyObject {
    func ocrService(_ service: OCRService, didStartRecognition imageData: Data)
    func ocrService(_ service: OCRService, didUpdateProgress progress: Float)
    func ocrService(_ service: OCRService, didCompleteRecognition result: OCRResult)
    func ocrService(_ service: OCRService, didFailWith error: Error)
}

// MARK: - OCR结果
public struct OCRResult: Codable {
    public let recognizedText: String
    public let confidence: Float?
    public let processingTime: TimeInterval
    public let imageSize: CGSize
    public let modelUsed: String
    public let timestamp: Date

    public init(recognizedText: String, confidence: Float? = nil, processingTime: TimeInterval, imageSize: CGSize, modelUsed: String) {
        self.recognizedText = recognizedText
        self.confidence = confidence
        self.processingTime = processingTime
        self.imageSize = imageSize
        self.modelUsed = modelUsed
        self.timestamp = Date()
    }
}

// MARK: - OCR配置
public struct OCRConfiguration {
    public let provider: String
    public let apiKey: String
    public let modelName: String
    public let baseURL: String
    public let defaultPrompt: String
    public let timeout: TimeInterval
    public let maxImageSize: Int
    public let maxRetryCount: Int
    public let retryDelay: TimeInterval
    
    public init(provider: String = "doubao", apiKey: String, modelName: String, baseURL: String, defaultPrompt: String, timeout: TimeInterval = 30.0, maxImageSize: Int = 10 * 1024 * 1024, maxRetryCount: Int = 3, retryDelay: TimeInterval = 1.0) {
        self.provider = provider
        self.apiKey = apiKey
        self.modelName = modelName
        self.baseURL = baseURL
        self.defaultPrompt = defaultPrompt
        self.timeout = timeout
        self.maxImageSize = maxImageSize
        self.maxRetryCount = maxRetryCount
        self.retryDelay = retryDelay
    }
}

// MARK: - OCR服务（OpenAI Compatible）
public class OCRService: OCRServiceProtocol, ObservableObject {
    
    // MARK: - 属性
    public weak var delegate: OCRServiceDelegate?
    
    @Published public private(set) var isProcessing = false
    @Published public private(set) var processingProgress: Float = 0.0
    @Published public private(set) var currentOperation: String = ""
    
    private let configuration: OCRConfiguration
    private let processingQueue = DispatchQueue(label: "com.phototts.ocr", qos: .userInitiated)
    private let session: URLSession
    
    // MARK: - 初始化
    public init(configuration: OCRConfiguration) {
        self.configuration = configuration
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configuration.timeout
        config.timeoutIntervalForResource = configuration.timeout
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - 主要OCR方法
    public func recognizeText(from imageData: Data) async throws -> OCRResult {
        return try await recognizeText(from: imageData, withPrompt: configuration.defaultPrompt, imageIndex: nil)
    }
    
    public func recognizeText(from imageData: Data, withPrompt prompt: String) async throws -> OCRResult {
        return try await recognizeText(from: imageData, withPrompt: prompt, imageIndex: nil)
    }
    
    public func recognizeText(from imageData: Data, imageIndex: Int) async throws -> OCRResult {
        return try await recognizeText(from: imageData, withPrompt: configuration.defaultPrompt, imageIndex: imageIndex)
    }
    
    public func recognizeText(from imageData: Data, withPrompt prompt: String, imageIndex: Int?) async throws -> OCRResult {
        let startTime = Date()
        
        // 打印图片索引和Provider
        let providerTag = "[OCR] 模型\(configuration.provider)，"
        if let index = imageIndex {
            logInfo("\(providerTag) 开始OCR识别，图片索引: \(index + 1)")
        } else {
            logInfo("\(providerTag) 开始OCR识别")
        }
        
        await MainActor.run {
            self.isProcessing = true
            self.processingProgress = 0.0
            let operationText = imageIndex != nil ? "开始OCR识别（图片\(imageIndex! + 1)）" : "开始OCR识别"
            self.currentOperation = operationText
        }
        
        delegate?.ocrService(self, didStartRecognition: imageData)
        
        do {
            // 验证图片数据
            try validateImageData(imageData)
            
            // 预处理图片（转换为JPEG格式）
            let processedImageData = try await preprocessImage(imageData)
            
            await updateProgress(0.3, operation: "图片预处理完成")
            
            // 调用OCR API（带重试）
            let recognizedText = try await callOCRAPIWithRetry(imageData: processedImageData, prompt: prompt, imageIndex: imageIndex)
            
            await updateProgress(0.8, operation: "API调用完成")
            
            // 后处理结果
            let finalText = postprocessText(recognizedText)
            
            await updateProgress(1.0, operation: "OCR识别完成")
            
            let processingTime = Date().timeIntervalSince(startTime)
            let imageSize = getImageSize(from: processedImageData)
            
            let result = OCRResult(
                recognizedText: finalText,
                confidence: nil, // OCR API不返回置信度
                processingTime: processingTime,
                imageSize: imageSize,
                modelUsed: configuration.modelName
            )
            
            await MainActor.run {
                self.isProcessing = false
                self.processingProgress = 0.0
                self.currentOperation = ""
            }
            
            delegate?.ocrService(self, didCompleteRecognition: result)
            return result
            
        } catch {
            await MainActor.run {
                self.isProcessing = false
                self.processingProgress = 0.0
                self.currentOperation = ""
            }
            
            delegate?.ocrService(self, didFailWith: error)
            throw error
        }
    }
    
    // MARK: - 私有方法
    
    private func validateImageData(_ imageData: Data) throws {
        guard !imageData.isEmpty else {
            throw OCRError.invalidImageData
        }
        
        guard imageData.count <= configuration.maxImageSize else {
            throw OCRError.imageTooLarge(imageData.count, configuration.maxImageSize)
        }
    }
    
    private func preprocessImage(_ imageData: Data) async throws -> Data {
        // 检查图片格式，如果不是JPEG则转换
        if let image = createImage(from: imageData) {
            if !isJPEGFormat(imageData) {
                return try convertToJPEG(image: image)
            }
        }
        return imageData
    }
    
    private func callOCRAPIWithRetry(imageData: Data, prompt: String, imageIndex: Int?) async throws -> String {
        var lastError: Error?
        
        let providerTag = "[OCR] 模型\(configuration.provider)，"
        let imageIndexText = imageIndex != nil ? "，图片索引: \(imageIndex! + 1)" : ""
        let totalStartTime = Date()
        
        for attempt in 1...configuration.maxRetryCount {
            let attemptStartTime = Date()
            do {
                logInfo("\(providerTag) OCR API调用尝试 \(attempt)/\(self.configuration.maxRetryCount)\(imageIndexText)")
                let result = try await callOCRAPI(imageData: imageData, prompt: prompt)
                
                // 检查返回结果是否为空（且不是系统保留字符）
                let trimmedResult = result.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // 如果返回结果包含系统保留字符"空字符串"，且长度大于系统保留字符长度+2，这是正常结果，直接返回
                if trimmedResult.contains(AppConstants.ocrEmptyResultIndicator) && 
                   trimmedResult.count <= AppConstants.ocrEmptyResultIndicator.count + 2 {
                    let attemptDuration = Date().timeIntervalSince(attemptStartTime)
                    let totalDuration = Date().timeIntervalSince(totalStartTime)
                    logInfo("\(providerTag) OCR API调用成功（返回空字符串标识），尝试 \(attempt)\(imageIndexText)，本次耗时: \(String(format: "%.2f", attemptDuration))秒，总耗时: \(String(format: "%.2f", totalDuration))秒，识别结果: \(result)")
                    return result
                }
                
                // 如果结果为空字符串，视为失败并重试
                if trimmedResult.isEmpty {
                    let emptyError = OCRError.invalidResponseData
                    lastError = emptyError
                    let attemptDuration = Date().timeIntervalSince(attemptStartTime)
                    let totalDuration = Date().timeIntervalSince(totalStartTime)
                    logWarning("\(providerTag) OCR API返回结果为空（非系统保留字符），尝试 \(attempt)/\(self.configuration.maxRetryCount)\(imageIndexText)，本次耗时: \(String(format: "%.2f", attemptDuration))秒，总耗时: \(String(format: "%.2f", totalDuration))秒")
                    
                    // 如果不是最后一次尝试，等待重试间隔
                    if attempt < configuration.maxRetryCount {
                        logInfo("等待 \(self.configuration.retryDelay) 秒后重试...")
                        try await Task.sleep(nanoseconds: UInt64(configuration.retryDelay * 1_000_000_000))
                    }
                    continue
                }
                
                let attemptDuration = Date().timeIntervalSince(attemptStartTime)
                let totalDuration = Date().timeIntervalSince(totalStartTime)
                logInfo("\(providerTag) OCR API调用成功，尝试 \(attempt)\(imageIndexText)，本次耗时: \(String(format: "%.2f", attemptDuration))秒，总耗时: \(String(format: "%.2f", totalDuration))秒")
                return result
            } catch {
                lastError = error
                let attemptDuration = Date().timeIntervalSince(attemptStartTime)
                let totalDuration = Date().timeIntervalSince(totalStartTime)
                logError("\(providerTag) OCR API调用失败，尝试 \(attempt)/\(self.configuration.maxRetryCount)\(imageIndexText)，本次耗时: \(String(format: "%.2f", attemptDuration))秒，总耗时: \(String(format: "%.2f", totalDuration))秒，错误: \(error.localizedDescription)")
                
                // 如果不是最后一次尝试，等待重试间隔
                if attempt < configuration.maxRetryCount {
                    os.Logger.ocrService.info("等待 \(self.configuration.retryDelay) 秒后重试...")
                    try await Task.sleep(nanoseconds: UInt64(configuration.retryDelay * 1_000_000_000))
                }
            }
        }
        
        // 所有重试都失败了
        let totalDuration = Date().timeIntervalSince(totalStartTime)
        logError("\(providerTag) OCR API调用失败，已重试 \(self.configuration.maxRetryCount) 次，总耗时: \(String(format: "%.2f", totalDuration))秒")
        throw lastError ?? OCRError.networkError(NSError(domain: Constants.ErrorInfo.domain, code: Constants.ErrorInfo.defaultCode, userInfo: [NSLocalizedDescriptionKey: "重试失败"]))
    }
    
    private func callOCRAPI(imageData: Data, prompt: String) async throws -> String {
        let imageBase64 = imageData.base64EncodedString()
        
        // 构建OpenAI Compatible多模态请求体
        let requestBody: [String: Any] = [
            "model": configuration.modelName,
            "messages": [
                [
                    "content": [
                        [
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(imageBase64)"
                            ],
                            "type": "image_url"
                        ],
                        [
                            "text": prompt,
                            "type": "text"
                        ]
                    ],
                    "role": "user"
                ]
            ]
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw OCRError.invalidRequestData
        }
        
        // 创建请求
        guard let url = URL(string: configuration.baseURL) else {
            throw OCRError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        
        // 设置请求头
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        
        // 发送请求
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OCRError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw OCRError.apiError(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "未知错误")
        }
        
        // 解析响应
        guard let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = jsonData["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OCRError.invalidResponseData
        }
        
        return content
    }
    
    private func postprocessText(_ text: String) -> String {
        OCRTextProcessor.process(text)
    }
    
    private func createImage(from data: Data) -> CIImage? {
        return CIImage(data: data)
    }
    
    private func isJPEGFormat(_ data: Data) -> Bool {
        return data.count >= 2 && data[0] == 0xFF && data[1] == 0xD8
    }
    
    private func convertToJPEG(image: CIImage) throws -> Data {
        let context = CIContext()
        guard let data = context.jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9]) else {
            throw OCRError.imageConversionFailed
        }
        return data
    }
    
    private func getImageSize(from data: Data) -> CGSize {
        guard let image = createImage(from: data) else {
            return CGSize.zero
        }
        return image.extent.size
    }
    
    private func updateProgress(_ progress: Float, operation: String) async {
        await MainActor.run {
            self.processingProgress = progress
            self.currentOperation = operation
        }
        
        delegate?.ocrService(self, didUpdateProgress: progress)
    }

    // MARK: - 日志方法
    private func logInfo(_ message: String) {
        os.Logger.ocrService.info("\(message)")
        DebugLogManager.shared.directLog(message)
    }

    private func logError(_ message: String) {
        os.Logger.ocrService.error("\(message)")
        DebugLogManager.shared.directLog(message)
    }

    private func logWarning(_ message: String) {
        os.Logger.ocrService.warning("\(message)")
        DebugLogManager.shared.directLog(message)
    }
}

// MARK: - OCR错误
public enum OCRError: LocalizedError {
    case invalidImageData
    case imageTooLarge(Int, Int)
    case invalidRequestData
    case invalidURL
    case invalidResponse
    case invalidResponseData
    case apiError(Int, String)
    case imageConversionFailed
    case networkError(Error)
    
    /// 用户可见描述：中文、无技术细节
    public var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "图片数据无法识别，请重新选择图片"
        case .imageTooLarge:
            return "图片太大，请压缩后重试"
        case .invalidRequestData:
            return "请求准备失败，请重试"
        case .invalidURL:
            return "服务配置异常，请检查设置"
        case .invalidResponse:
            return "服务响应异常，请重试"
        case .invalidResponseData:
            return "识别结果解析失败，请重试"
        case .apiError:
            return "识别服务出错，请稍后重试"
        case .imageConversionFailed:
            return "图片格式转换失败，请换一张图片"
        case .networkError:
            return "网络连接失败，请检查网络后重试"
        }
    }
    
    /// 技术描述：供 os.Logger 使用，包含错误码和内部信息
    public var technicalDescription: String {
        switch self {
        case .invalidImageData:
            return "OCR invalidImageData: 图片数据为空或无法解析"
        case .imageTooLarge(let actual, let max):
            return "OCR imageTooLarge: \(actual) bytes, max=\(max) bytes"
        case .invalidRequestData:
            return "OCR invalidRequestData: JSON序列化失败"
        case .invalidURL:
            return "OCR invalidURL: API URL无效"
        case .invalidResponse:
            return "OCR invalidResponse: 非HTTPURLResponse"
        case .invalidResponseData:
            return "OCR invalidResponseData: JSON解析失败或choices为空"
        case .apiError(let code, let message):
            return "OCR apiError: HTTP \(code), body=\(message)"
        case .imageConversionFailed:
            return "OCR imageConversionFailed: CIContext JPEG转换失败"
        case .networkError(let error):
            return "OCR networkError: \(error.localizedDescription)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .invalidImageData:
            return "请检查图片文件是否损坏"
        case .imageTooLarge:
            return "请压缩图片或使用较小的图片"
        case .invalidRequestData:
            return "请重试"
        case .invalidURL:
            return "请检查OCR服务配置"
        case .invalidResponse:
            return "请重试"
        case .invalidResponseData:
            return "请重试"
        case .apiError:
            return "请检查API密钥和配置"
        case .imageConversionFailed:
            return "请使用支持的图片格式"
        case .networkError:
            return "请检查网络连接"
        }
    }
}

// MARK: - OCR服务工厂
public class OCRServiceFactory {
    
    /// 根据config_local.json中ocr.provider字段创建对应的OCR服务
    /// 支持doubao和openai两种供应商，均使用OpenAI Compatible请求格式
    public static func createOCRService() -> OCRService? {
        let settingsManager = SettingsManager.shared
        let activeProvider = settingsManager.getActiveOCRProvider()
        let providerConfig = settingsManager.loadActiveOCRProviderConfig()
        
        guard !providerConfig.isEmpty else {
            let msg = "无法读取OCR供应商[\(activeProvider)]配置"
            os.Logger.ocrService.error("\(msg)")
            DebugLogManager.shared.directLog(msg)
            return nil
        }

        let readMsg = "成功读取OCR配置，活跃供应商: \(activeProvider)"
        os.Logger.ocrService.info("\(readMsg)")
        DebugLogManager.shared.directLog(readMsg)
        
        let baseURL = providerConfig["base_url"] as? String ?? Constants.ServiceDefaults.ocrBaseURL
        // 按供应商名从对应Keychain key获取密钥，回退到config文件
        let apiKey = settingsManager.getOCRAPIKeyForProvider(activeProvider)
        let modelName = providerConfig["model_name"] as? String ?? Constants.ServiceDefaults.ocrModelName
        // prompt_user优先从供应商子配置读取，回退到ocr根节点，再回退到默认值
        let ocrConfig = settingsManager.loadOCRConfig()
        let promptUser = providerConfig["prompt_user"] as? String
            ?? ocrConfig["prompt_user"] as? String
            ?? "你是一个专业的OCR识别助手。请识别绘本图片中的汉字，并整理断句、使表意顺畅。操作步骤如下：S1.调整图片的角度，使内容正对读者。S2.识别和分割多页，如果输入的绘本图片有多页，请按照从左到右、从上到下的顺序，将图片内容分成多页。S3.识别一页中的汉字，按照自上而下的顺序识别，保留标点符号，忽略拼音、忽略纯数字的段落。S4.整理一页中的汉字，合理断句、补全标点，同一句话去掉内部换行，产出表意顺畅的句子。S5.如果有多页内容，多页内容之间用一个换行、拼接在一起返回。其它要求：1.没识别到内容时，请返回`空字符串`这四个汉字；2.请不要添加任何内容，特别是第一页、第二页这样的多页时的分页语句"
        let timeout = providerConfig["timeout"] as? TimeInterval
            ?? ocrConfig["timeout"] as? TimeInterval
            ?? 120.0
        let maxRetryCount = providerConfig["max_retry_count"] as? Int
            ?? ocrConfig["max_retry_count"] as? Int
            ?? 3
        let retryDelay = providerConfig["retry_delay"] as? TimeInterval
            ?? ocrConfig["retry_delay"] as? TimeInterval
            ?? 1.0
        
        let configLines = [
            "配置信息:",
            "   - Active Provider: \(activeProvider)",
            "   - Base URL: \(baseURL)",
            "   - API Key: \(apiKey.isEmpty ? "空" : "***" + apiKey.suffix(4))",
            "   - Model Name: \(modelName)",
            "   - Prompt长度: \(promptUser.count)",
            "   - Timeout: \(timeout)秒",
            "   - Max Retry: \(maxRetryCount)次",
            "   - Retry Delay: \(retryDelay)秒"
        ]
        for line in configLines {
            os.Logger.ocrService.info("\(line)")
            DebugLogManager.shared.directLog(line)
        }

        guard !apiKey.isEmpty else {
            let errMsg = "未配置OCR[\(activeProvider)] API Key"
            os.Logger.ocrService.error("\(errMsg)")
            DebugLogManager.shared.directLog(errMsg)
            return nil
        }
        
        let configuration = OCRConfiguration(
            provider: activeProvider,
            apiKey: apiKey,
            modelName: modelName,
            baseURL: baseURL,
            defaultPrompt: promptUser,
            timeout: timeout,
            maxRetryCount: maxRetryCount,
            retryDelay: retryDelay
        )
        
        let successMsg = "OCR服务初始化成功，供应商: \(activeProvider)"
        os.Logger.ocrService.info("\(successMsg)")
        DebugLogManager.shared.directLog(successMsg)
        return OCRService(configuration: configuration)
    }
}
