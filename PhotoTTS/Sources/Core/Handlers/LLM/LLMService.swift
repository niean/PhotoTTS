import Foundation
import os.log

// MARK: - LLM分析结果
/// LLM绘本分析结果，包含绘本名称和要点
struct LLMStoryAnalysisResult {
    /// 绘本名称（3-12字符）
    let storyName: String?
    /// 绘本要点（15-30字符）
    let storyHighlights: String?
    /// 名称提取是否成功
    let isNameSuccess: Bool
    /// 要点提取是否成功
    let isHighlightsSuccess: Bool

    /// 整体是否成功（任一成功视为整体成功）
    var isSuccess: Bool {
        isNameSuccess || isHighlightsSuccess
    }
}

// MARK: - LLM服务协议
/// LLM服务协议，定义绘本分析的核心接口
protocol LLMServiceProtocol {
    /// 分析绘本内容，生成名称和要点
    /// - Parameter ocrText: OCR识别的完整文本
    /// - Returns: 分析结果（名称和要点）
    func analyzeStory(ocrText: String) async throws -> LLMStoryAnalysisResult
}

// MARK: - LLM配置
/// LLM服务配置
struct LLMConfiguration {
    let provider: String
    let apiKey: String
    let modelName: String
    let baseURL: String
    let promptUser: String
    let timeout: TimeInterval
    let maxRetryCount: Int
    let retryDelay: TimeInterval

    init(
        provider: String = "doubao",
        apiKey: String,
        modelName: String,
        baseURL: String,
        promptUser: String,
        timeout: TimeInterval = 30.0,
        maxRetryCount: Int = 3,
        retryDelay: TimeInterval = 1.0
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.modelName = modelName
        self.baseURL = baseURL
        self.promptUser = promptUser
        self.timeout = timeout
        self.maxRetryCount = maxRetryCount
        self.retryDelay = retryDelay
    }
}

// MARK: - LLM常量
struct LLMConstants {
    /// LLM输入文本最大长度（字符数），超过则拒绝处理
    static let maxInputTextLength = 20000
    /// 绘本名称需要过滤的特殊字符集
    static let storyNameInvalidCharacters: CharacterSet = CharacterSet(charactersIn: "`'\"「」『』〔〕【】〖〗[]()（）")
}

// MARK: - LLM错误
/// LLM服务错误类型
enum LLMError: Error, LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case apiError(String)
    case networkError(Error)
    case parsingError(String)
    case retryExhausted
    case textTooLong(Int)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "LLM配置无效"
        case .invalidResponse:
            return "LLM响应格式错误"
        case .apiError(let message):
            return "LLM API错误: \(message)"
        case .networkError:
            return "LLM网络请求失败"
        case .parsingError:
            return "LLM结果解析失败"
        case .retryExhausted:
            return "LLM请求重试次数耗尽"
        case .textTooLong:
            return "输入文本过长"
        }
    }

    var technicalDescription: String {
        switch self {
        case .invalidConfiguration:
            return "[LLM-001] 配置缺失或无效"
        case .invalidResponse:
            return "[LLM-002] API响应无法解析"
        case .apiError(let message):
            return "[LLM-003] API错误: \(message)"
        case .networkError(let error):
            return "[LLM-004] 网络错误: \(error.localizedDescription)"
        case .parsingError(let details):
            return "[LLM-005] 解析错误: \(details)"
        case .retryExhausted:
            return "[LLM-006] 重试次数耗尽"
        case .textTooLong(let length):
            return "[LLM-007] 输入文本过长: \(length) 字符，限制: \(LLMConstants.maxInputTextLength)"
        }
    }
}

// MARK: - LLM服务工厂
/// LLM服务工厂，创建对应Provider的服务实例
enum LLMServiceFactory {
    /// 创建LLM服务实例
    /// - Returns: LLM服务实例，配置无效时返回nil
    static func createLLMService() -> LLMServiceProtocol? {
        let settingsManager = SettingsManager.shared

        guard let config = settingsManager.loadActiveLLMProviderConfig() else {
            os.Logger.llmService.warning("LLM配置无效，无法创建服务")
            return nil
        }

        // 检查API Key是否为空
        if config.apiKey.isEmpty {
            os.Logger.llmService.warning("LLM API Key为空，provider: \(config.provider)")
        }

        let llmConfig = LLMConfiguration(
            provider: config.provider,
            apiKey: config.apiKey,
            modelName: config.modelName,
            baseURL: config.baseURL,
            promptUser: config.promptUser,
            timeout: config.timeout,
            maxRetryCount: config.maxRetryCount,
            retryDelay: config.retryDelay
        )

        switch config.provider {
        case "doubao":
            return DoubaoLLMService(configuration: llmConfig)
        case "openai":
            return OpenAILLMService(configuration: llmConfig)
        default:
            os.Logger.llmService.warning("未知的LLM Provider: \(config.provider)，使用豆包作为默认")
            return DoubaoLLMService(configuration: llmConfig)
        }
    }
}

// MARK: - 豆包LLM服务
/// 豆包LLM服务实现（OpenAI Compatible API）
class DoubaoLLMService: LLMServiceProtocol {
    private let configuration: LLMConfiguration
    private let session: URLSession

    init(configuration: LLMConfiguration) {
        self.configuration = configuration

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configuration.timeout
        config.timeoutIntervalForResource = configuration.timeout
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    func analyzeStory(ocrText: String) async throws -> LLMStoryAnalysisResult {
        // 输入文本长度校验
        guard ocrText.count <= LLMConstants.maxInputTextLength else {
            os.Logger.llmService.warning("[LLM] 模型doubao，输入文本过长: \(ocrText.count) 字符，超过限制 \(LLMConstants.maxInputTextLength)")
            throw LLMError.textTooLong(ocrText.count)
        }

        let startTime = Date()
        os.Logger.llmService.info("[LLM] 模型doubao，开始LLM绘本分析，文本长度: \(ocrText.count)")

        // 构建请求体
        let requestBody: [String: Any] = [
            "model": configuration.modelName,
            "messages": [
                [
                    "role": "user",
                    "content": configuration.promptUser + "\n\n" + ocrText
                ]
            ],
            "temperature": 0.7,
            "max_tokens": 256
        ]

        // 调用API（带重试）
        let responseText = try await callLLMAPIWithRetry(requestBody: requestBody)

        // 解析结果
        let result = parseLLMResponse(responseText)

        let duration = Date().timeIntervalSince(startTime)
        os.Logger.llmService.info("[LLM] 模型doubao，LLM分析完成，耗时: \(String(format: "%.2f", duration))s，名称成功: \(result.isNameSuccess)，要点成功: \(result.isHighlightsSuccess)")

        return result
    }

    /// 调用LLM API（带重试）
    private func callLLMAPIWithRetry(requestBody: [String: Any]) async throws -> String {
        let maxRetryCount = self.configuration.maxRetryCount
        let retryDelay = self.configuration.retryDelay

        for attempt in 0..<maxRetryCount {
            do {
                return try await callLLMAPI(requestBody: requestBody)
            } catch {
                let attemptNumber = attempt + 1
                os.Logger.llmService.warning("[LLM] 模型doubao，LLM API调用失败（尝试 \(attemptNumber)/\(maxRetryCount)）: \(error.localizedDescription)")

                if attempt < maxRetryCount - 1 {
                    try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                }
            }
        }

        os.Logger.llmService.error("[LLM] 模型doubao，LLM API重试次数耗尽")
        throw LLMError.retryExhausted
    }

    /// 调用LLM API
    private func callLLMAPI(requestBody: [String: Any]) async throws -> String {
        let baseURL = self.configuration.baseURL
        guard let url = URL(string: baseURL) else {
            os.Logger.llmService.warning("[LLM] 模型doubao，LLM baseURL无效: \(baseURL)")
            throw LLMError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            os.Logger.llmService.warning("[LLM] 模型doubao，LLM请求体JSON序列化失败: \(error.localizedDescription)")
            throw LLMError.invalidConfiguration
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            os.Logger.llmService.error("[LLM] 模型doubao，LLM网络请求失败: \(error.localizedDescription)")
            throw LLMError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            os.Logger.llmService.warning("[LLM] 模型doubao，LLM响应无效，无法转换为HTTPURLResponse")
            throw LLMError.networkError(NSError(domain: Constants.ErrorInfo.domain, code: Constants.ErrorInfo.defaultCode))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            os.Logger.llmService.error("[LLM] 模型doubao，LLM API错误，状态码: \(httpResponse.statusCode)，响应: \(errorMessage)")
            throw LLMError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            let responseString = String(data: data, encoding: .utf8) ?? "无法解码"
            os.Logger.llmService.warning("[LLM] 模型doubao，LLM响应JSON解析失败，原始响应: \(responseString.prefix(500))")
            throw LLMError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 解析LLM响应
    private func parseLLMResponse(_ text: String) -> LLMStoryAnalysisResult {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }

        var storyName: String?
        var storyHighlights: String?
        var isNameSuccess = false
        var isHighlightsSuccess = false

        os.Logger.llmService.debug("[LLM] 模型doubao，LLM原始响应: \(text.prefix(200))...")

        // 第1行匹配"绘本名称："
        if let firstLine = lines.first {
            let namePrefix = "绘本名称："
            if firstLine.contains(namePrefix) || firstLine.contains("绘本名称:") {
                let extracted = firstLine
                    .replacingOccurrences(of: namePrefix, with: "")
                    .replacingOccurrences(of: "绘本名称:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !extracted.isEmpty && !extracted.contains("总结失败") {
                    let filtered = extracted.components(separatedBy: LLMConstants.storyNameInvalidCharacters).joined()
                    let trimmed = String(filtered.prefix(12))
                    if trimmed.count >= 3 {
                        storyName = trimmed
                        isNameSuccess = true
                    } else {
                        os.Logger.llmService.debug("[LLM] 模型doubao，绘本名称过短: \(trimmed.count)字符")
                    }
                } else {
                    os.Logger.llmService.debug("[LLM] 模型doubao，绘本名称提取失败或包含'总结失败'")
                }
            } else {
                os.Logger.llmService.debug("[LLM] 模型doubao，第一行未匹配绘本名称前缀: \(firstLine.prefix(50))")
            }
        } else {
            os.Logger.llmService.warning("[LLM] 模型doubao，LLM响应为空，无内容行")
        }

        // 第2行匹配"绘本要点："
        if lines.count >= 2 {
            let secondLine = lines[1]
            let highlightsPrefix = "绘本要点："
            if secondLine.contains(highlightsPrefix) || secondLine.contains("绘本要点:") {
                let extracted = secondLine
                    .replacingOccurrences(of: highlightsPrefix, with: "")
                    .replacingOccurrences(of: "绘本要点:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !extracted.isEmpty && !extracted.contains("总结失败") {
                    let trimmed = String(extracted.prefix(30))
                    if trimmed.count >= 15 {
                        storyHighlights = trimmed
                        isHighlightsSuccess = true
                    } else {
                        os.Logger.llmService.debug("[LLM] 模型doubao，绘本要点过短: \(trimmed.count)字符")
                    }
                } else {
                    os.Logger.llmService.debug("[LLM] 模型doubao，绘本要点提取失败或包含'总结失败'")
                }
            } else {
                os.Logger.llmService.debug("[LLM] 模型doubao，第二行未匹配绘本要点前缀: \(secondLine.prefix(50))")
            }
        } else {
            os.Logger.llmService.debug("[LLM] 模型doubao，LLM响应只有一行，无法提取要点")
        }

        return LLMStoryAnalysisResult(
            storyName: storyName,
            storyHighlights: storyHighlights,
            isNameSuccess: isNameSuccess,
            isHighlightsSuccess: isHighlightsSuccess
        )
    }
}

// MARK: - OpenAI LLM服务
/// OpenAI LLM服务实现（OpenAI Compatible API）
class OpenAILLMService: LLMServiceProtocol {
    private let configuration: LLMConfiguration
    private let session: URLSession

    init(configuration: LLMConfiguration) {
        self.configuration = configuration

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configuration.timeout
        config.timeoutIntervalForResource = configuration.timeout
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    func analyzeStory(ocrText: String) async throws -> LLMStoryAnalysisResult {
        // 输入文本长度校验
        guard ocrText.count <= LLMConstants.maxInputTextLength else {
            os.Logger.llmService.warning("[LLM] 模型openai，输入文本过长: \(ocrText.count) 字符，超过限制 \(LLMConstants.maxInputTextLength)")
            throw LLMError.textTooLong(ocrText.count)
        }

        let startTime = Date()
        os.Logger.llmService.info("[LLM] 模型openai，开始LLM绘本分析，文本长度: \(ocrText.count)")

        // 构建请求体
        let requestBody: [String: Any] = [
            "model": configuration.modelName,
            "messages": [
                [
                    "role": "user",
                    "content": configuration.promptUser + "\n\n" + ocrText
                ]
            ],
            "temperature": 0.7,
            "max_tokens": 256
        ]

        // 调用API（带重试）
        let responseText = try await callLLMAPIWithRetry(requestBody: requestBody)

        // 解析结果（与豆包相同）
        let result = parseLLMResponse(responseText)

        let duration = Date().timeIntervalSince(startTime)
        os.Logger.llmService.info("[LLM] 模型openai，LLM分析完成，耗时: \(String(format: "%.2f", duration))s，名称成功: \(result.isNameSuccess)，要点成功: \(result.isHighlightsSuccess)")

        return result
    }

    /// 调用LLM API（带重试）
    private func callLLMAPIWithRetry(requestBody: [String: Any]) async throws -> String {
        let maxRetryCount = self.configuration.maxRetryCount
        let retryDelay = self.configuration.retryDelay

        for attempt in 0..<maxRetryCount {
            do {
                return try await callLLMAPI(requestBody: requestBody)
            } catch {
                let attemptNumber = attempt + 1
                os.Logger.llmService.warning("[LLM] 模型openai，LLM API调用失败（尝试 \(attemptNumber)/\(maxRetryCount)）: \(error.localizedDescription)")

                if attempt < maxRetryCount - 1 {
                    try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                }
            }
        }

        os.Logger.llmService.error("[LLM] 模型openai，LLM API重试次数耗尽")
        throw LLMError.retryExhausted
    }

    /// 调用LLM API
    private func callLLMAPI(requestBody: [String: Any]) async throws -> String {
        let baseURL = self.configuration.baseURL
        guard let url = URL(string: baseURL) else {
            os.Logger.llmService.warning("[LLM] 模型openai，LLM baseURL无效: \(baseURL)")
            throw LLMError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            os.Logger.llmService.warning("[LLM] 模型openai，LLM请求体JSON序列化失败: \(error.localizedDescription)")
            throw LLMError.invalidConfiguration
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            os.Logger.llmService.error("[LLM] 模型openai，LLM网络请求失败: \(error.localizedDescription)")
            throw LLMError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            os.Logger.llmService.warning("[LLM] 模型openai，LLM响应无效，无法转换为HTTPURLResponse")
            throw LLMError.networkError(NSError(domain: Constants.ErrorInfo.domain, code: Constants.ErrorInfo.defaultCode))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            os.Logger.llmService.error("[LLM] 模型openai，LLM API错误，状态码: \(httpResponse.statusCode)，响应: \(errorMessage)")
            throw LLMError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            let responseString = String(data: data, encoding: .utf8) ?? "无法解码"
            os.Logger.llmService.warning("[LLM] 模型openai，LLM响应JSON解析失败，原始响应: \(responseString.prefix(500))")
            throw LLMError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 解析LLM响应
    private func parseLLMResponse(_ text: String) -> LLMStoryAnalysisResult {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }

        var storyName: String?
        var storyHighlights: String?
        var isNameSuccess = false
        var isHighlightsSuccess = false

        os.Logger.llmService.debug("[LLM] 模型openai，LLM原始响应: \(text.prefix(200))...")

        // 第1行匹配"绘本名称："
        if let firstLine = lines.first {
            let namePrefix = "绘本名称："
            if firstLine.contains(namePrefix) || firstLine.contains("绘本名称:") {
                let extracted = firstLine
                    .replacingOccurrences(of: namePrefix, with: "")
                    .replacingOccurrences(of: "绘本名称:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !extracted.isEmpty && !extracted.contains("总结失败") {
                    let filtered = extracted.components(separatedBy: LLMConstants.storyNameInvalidCharacters).joined()
                    let trimmed = String(filtered.prefix(12))
                    if trimmed.count >= 3 {
                        storyName = trimmed
                        isNameSuccess = true
                    } else {
                        os.Logger.llmService.debug("[LLM] 模型openai，绘本名称过短: \(trimmed.count)字符")
                    }
                } else {
                    os.Logger.llmService.debug("[LLM] 模型openai，绘本名称提取失败或包含'总结失败'")
                }
            } else {
                os.Logger.llmService.debug("[LLM] 模型openai，第一行未匹配绘本名称前缀: \(firstLine.prefix(50))")
            }
        } else {
            os.Logger.llmService.warning("[LLM] 模型openai，LLM响应为空，无内容行")
        }

        // 第2行匹配"绘本要点："
        if lines.count >= 2 {
            let secondLine = lines[1]
            let highlightsPrefix = "绘本要点："
            if secondLine.contains(highlightsPrefix) || secondLine.contains("绘本要点:") {
                let extracted = secondLine
                    .replacingOccurrences(of: highlightsPrefix, with: "")
                    .replacingOccurrences(of: "绘本要点:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !extracted.isEmpty && !extracted.contains("总结失败") {
                    let trimmed = String(extracted.prefix(30))
                    if trimmed.count >= 15 {
                        storyHighlights = trimmed
                        isHighlightsSuccess = true
                    } else {
                        os.Logger.llmService.debug("[LLM] 模型openai，绘本要点过短: \(trimmed.count)字符")
                    }
                } else {
                    os.Logger.llmService.debug("[LLM] 模型openai，绘本要点提取失败或包含'总结失败'")
                }
            } else {
                os.Logger.llmService.debug("[LLM] 模型openai，第二行未匹配绘本要点前缀: \(secondLine.prefix(50))")
            }
        } else {
            os.Logger.llmService.debug("[LLM] 模型openai，LLM响应只有一行，无法提取要点")
        }

        return LLMStoryAnalysisResult(
            storyName: storyName,
            storyHighlights: storyHighlights,
            isNameSuccess: isNameSuccess,
            isHighlightsSuccess: isHighlightsSuccess
        )
    }
}
