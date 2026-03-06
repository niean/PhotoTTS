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
    public let confidence: Float
    public let processingTime: TimeInterval
    public let imageSize: CGSize
    public let modelUsed: String
    public let timestamp: Date
    
    public init(recognizedText: String, confidence: Float, processingTime: TimeInterval, imageSize: CGSize, modelUsed: String) {
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
        let providerTag = "[\(configuration.provider)]"
        if let index = imageIndex {
            os.Logger.ocrService.info("\(providerTag) 开始OCR识别，图片索引: \(index + 1)")
        } else {
            os.Logger.ocrService.info("\(providerTag) 开始OCR识别")
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
                confidence: 0.95, // 豆包大模型的高置信度
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
        
        let providerTag = "[\(configuration.provider)]"
        let imageIndexText = imageIndex != nil ? "，图片索引: \(imageIndex! + 1)" : ""
        let totalStartTime = Date()
        
        for attempt in 1...configuration.maxRetryCount {
            let attemptStartTime = Date()
            do {
                os.Logger.ocrService.info("\(providerTag) OCR API调用尝试 \(attempt)/\(self.configuration.maxRetryCount)\(imageIndexText)")
                let result = try await callOCRAPI(imageData: imageData, prompt: prompt)
                
                // 检查返回结果是否为空（且不是系统保留字符）
                let trimmedResult = result.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // 如果返回结果包含系统保留字符"空字符串"，且长度大于系统保留字符长度+2，这是正常结果，直接返回
                if trimmedResult.contains(AppConstants.ocrEmptyResultIndicator) && 
                   trimmedResult.count <= AppConstants.ocrEmptyResultIndicator.count + 2 {
                    let attemptDuration = Date().timeIntervalSince(attemptStartTime)
                    let totalDuration = Date().timeIntervalSince(totalStartTime)
                    os.Logger.ocrService.info("\(providerTag) OCR API调用成功（返回空字符串标识），尝试 \(attempt)\(imageIndexText)，本次耗时: \(String(format: "%.2f", attemptDuration))秒，总耗时: \(String(format: "%.2f", totalDuration))秒，识别结果: \(result)")
                    return result
                }
                
                // 如果结果为空字符串，视为失败并重试
                if trimmedResult.isEmpty {
                    let emptyError = OCRError.invalidResponseData
                    lastError = emptyError
                    let attemptDuration = Date().timeIntervalSince(attemptStartTime)
                    let totalDuration = Date().timeIntervalSince(totalStartTime)
                    os.Logger.ocrService.warning("\(providerTag) OCR API返回结果为空（非系统保留字符），尝试 \(attempt)/\(self.configuration.maxRetryCount)\(imageIndexText)，本次耗时: \(String(format: "%.2f", attemptDuration))秒，总耗时: \(String(format: "%.2f", totalDuration))秒")
                    
                    // 如果不是最后一次尝试，等待重试间隔
                    if attempt < configuration.maxRetryCount {
                        os.Logger.ocrService.info("等待 \(self.configuration.retryDelay) 秒后重试...")
                        try await Task.sleep(nanoseconds: UInt64(configuration.retryDelay * 1_000_000_000))
                    }
                    continue
                }
                
                let attemptDuration = Date().timeIntervalSince(attemptStartTime)
                let totalDuration = Date().timeIntervalSince(totalStartTime)
                os.Logger.ocrService.info("\(providerTag) OCR API调用成功，尝试 \(attempt)\(imageIndexText)，本次耗时: \(String(format: "%.2f", attemptDuration))秒，总耗时: \(String(format: "%.2f", totalDuration))秒")
                return result
            } catch {
                lastError = error
                let attemptDuration = Date().timeIntervalSince(attemptStartTime)
                let totalDuration = Date().timeIntervalSince(totalStartTime)
                os.Logger.ocrService.error("\(providerTag) OCR API调用失败，尝试 \(attempt)/\(self.configuration.maxRetryCount)\(imageIndexText)，本次耗时: \(String(format: "%.2f", attemptDuration))秒，总耗时: \(String(format: "%.2f", totalDuration))秒，错误: \(error.localizedDescription)")
                
                // 如果不是最后一次尝试，等待重试间隔
                if attempt < configuration.maxRetryCount {
                    os.Logger.ocrService.info("等待 \(self.configuration.retryDelay) 秒后重试...")
                    try await Task.sleep(nanoseconds: UInt64(configuration.retryDelay * 1_000_000_000))
                }
            }
        }
        
        // 所有重试都失败了
        let totalDuration = Date().timeIntervalSince(totalStartTime)
        os.Logger.ocrService.error("\(providerTag) OCR API调用失败，已重试 \(self.configuration.maxRetryCount) 次，总耗时: \(String(format: "%.2f", totalDuration))秒")
        throw lastError ?? OCRError.networkError(NSError(domain: "OCR", code: -1, userInfo: [NSLocalizedDescriptionKey: "重试失败"]))
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
        // 清理和格式化识别的文本
        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 移除多余的换行符
        cleanedText = cleanedText.replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)
        
        return cleanedText
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
    
    public var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "无效的图片数据"
        case .imageTooLarge(let actual, let max):
            return "图片太大: \(actual) bytes，最大支持: \(max) bytes"
        case .invalidRequestData:
            return "无效的请求数据"
        case .invalidURL:
            return "无效的API URL"
        case .invalidResponse:
            return "无效的API响应"
        case .invalidResponseData:
            return "无效的响应数据格式"
        case .apiError(let code, let message):
            return "API错误 (\(code)): \(message)"
        case .imageConversionFailed:
            return "图片格式转换失败"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .invalidImageData:
            return "请检查图片文件是否损坏"
        case .imageTooLarge:
            return "请压缩图片或使用较小的图片"
        case .invalidRequestData:
            return "请检查请求参数"
        case .invalidURL:
            return "请检查API配置"
        case .invalidResponse:
            return "请重试或联系技术支持"
        case .invalidResponseData:
            return "请重试或联系技术支持"
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
    
    /// 根据config_local.json中ocr.model字段创建对应的OCR服务
    /// 支持doubao和openai两种模型，均使用OpenAI Compatible请求格式
    public static func createOCRService() -> OCRService? {
        let settingsManager = SettingsManager.shared
        let activeModel = settingsManager.getActiveOCRModel()
        let modelConfig = settingsManager.loadActiveOCRModelConfig()
        
        guard !modelConfig.isEmpty else {
            os.Logger.ocrService.error("无法读取OCR模型[\(activeModel)]配置")
            return nil
        }
        
        os.Logger.ocrService.info("成功读取OCR配置，活跃模型: \(activeModel)")
        
        let baseURL = modelConfig["base_url"] as? String ?? Constants.ServiceDefaults.ocrBaseURL
        // 按模型名从对应Keychain key获取密钥，回退到config文件
        let apiKey = settingsManager.getOCRAPIKeyForModel(activeModel)
        let modelName = modelConfig["model_name"] as? String ?? Constants.ServiceDefaults.ocrModelName
        // prompt_user优先从模型子配置读取，回退到ocr根节点，再回退到默认值
        let ocrConfig = settingsManager.loadOCRConfig()
        let promptUser = modelConfig["prompt_user"] as? String
            ?? ocrConfig["prompt_user"] as? String
            ?? "你是一个专业的OCR识别助手。请识别绘本图片中的汉字，并整理断句、使表意顺畅。操作步骤如下：S1.调整图片的角度，使内容正对读者。S2.识别和分割多页，如果输入的绘本图片有多页，请按照从左到右、从上到下的顺序，将图片内容分成多页。S3.识别一页中的汉字，按照自上而下的顺序识别，保留标点符号，忽略拼音、忽略纯数字的段落。S4.整理一页中的汉字，合理断句、补全标点，同一句话去掉内部换行，产出表意顺畅的句子。S5.如果有多页内容，多页内容之间用一个换行、拼接在一起返回。其它要求：1.没识别到内容时，请返回`空字符串`这四个汉字；2.请不要添加任何内容，特别是第一页、第二页这样的多页时的分页语句"
        let timeout = modelConfig["timeout"] as? TimeInterval
            ?? ocrConfig["timeout"] as? TimeInterval
            ?? 120.0
        let maxRetryCount = modelConfig["max_retry_count"] as? Int
            ?? ocrConfig["max_retry_count"] as? Int
            ?? 3
        let retryDelay = modelConfig["retry_delay"] as? TimeInterval
            ?? ocrConfig["retry_delay"] as? TimeInterval
            ?? 1.0
        
        os.Logger.ocrService.info("配置信息:")
        os.Logger.ocrService.info("   - Active Model: \(activeModel)")
        os.Logger.ocrService.info("   - Base URL: \(baseURL)")
        os.Logger.ocrService.info("   - API Key: \(apiKey.isEmpty ? "空" : "***" + apiKey.suffix(4))")
        os.Logger.ocrService.info("   - Model Name: \(modelName)")
        os.Logger.ocrService.info("   - Prompt长度: \(promptUser.count)")
        os.Logger.ocrService.info("   - Timeout: \(timeout)秒")
        os.Logger.ocrService.info("   - Max Retry: \(maxRetryCount)次")
        os.Logger.ocrService.info("   - Retry Delay: \(retryDelay)秒")
        
        guard !apiKey.isEmpty else {
            os.Logger.ocrService.error("未配置OCR[\(activeModel)] API Key")
            return nil
        }
        
        let configuration = OCRConfiguration(
            provider: activeModel,
            apiKey: apiKey,
            modelName: modelName,
            baseURL: baseURL,
            defaultPrompt: promptUser,
            timeout: timeout,
            maxRetryCount: maxRetryCount,
            retryDelay: retryDelay
        )
        
        os.Logger.ocrService.info("OCR服务初始化成功，模型: \(activeModel)")
        return OCRService(configuration: configuration)
    }
}
