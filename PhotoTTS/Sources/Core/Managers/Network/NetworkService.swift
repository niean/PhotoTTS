import Foundation
import os.log

// MARK: - 网络服务协议
/// 网络服务协议，定义了与豆包API交互的所有方法
/// 支持TTS语音合成功能
protocol NetworkServiceProtocol {
    // MARK: - 文字转语音（TTS）
    /// 文字转语音（TTS）
    /// 将识别出的文字转换为语音
    /// - Parameter text: 要转换的文字
    /// - Parameter voiceSettings: 语音设置参数
    /// - Parameter completion: 完成回调，返回音频响应或错误
    func convertTextToSpeech(_ text: String, voiceSettings: VoiceSettings, completion: @escaping (Result<AudioResponse, Error>) -> Void)
    
    /// 批量文字转语音（TTS）
    /// 一次性处理多段文字的TTS转换
    /// - Parameter texts: 要转换的文字数组
    /// - Parameter voiceSettings: 语音设置参数
    /// - Parameter completion: 完成回调，返回音频响应数组或错误
    func convertTextsToSpeech(_ texts: [String], voiceSettings: VoiceSettings, completion: @escaping (Result<[AudioResponse], Error>) -> Void)
    
    /// 批量文字转语音（TTS）- 别名方法
    /// - Parameter texts: 要转换的文字数组
    /// - Parameter voiceSettings: 语音设置参数
    /// - Parameter completion: 完成回调，返回音频响应数组或错误
    func convertTextToSpeechBatch(_ texts: [String], voiceSettings: VoiceSettings, completion: @escaping (Result<[AudioResponse], Error>) -> Void)
    
    /// 测试网络连接
    /// - Parameter completion: 完成回调，返回连接状态或错误
    func testConnection(completion: @escaping (Result<Bool, Error>) -> Void)
    
    /// 取消所有进行中的网络请求
    func cancelAllRequests()
}

// MARK: - 网络服务
/// 网络服务实现类，负责与豆包API的网络通信
/// 支持TTS语音合成功能
/// 使用URLSession进行HTTP请求，支持超时、重试等配置
class NetworkService: NetworkServiceProtocol {
    
    // MARK: - 属性
    /// 设置管理器，用于获取API密钥和用户配置
    private let settingsManager: SettingsManager
    /// URLSession，配置了超时和连接策略
    private let session: URLSession
    /// API基础URL
    private let baseURL = AppConstants.Network.baseURL
    
    // MARK: - 初始化
    /// 初始化网络服务
    /// - Parameter settingsManager: 设置管理器实例，默认使用共享实例
    init(settingsManager: SettingsManager = .shared) {
        self.settingsManager = settingsManager
        
        // 配置URLSession
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = AppConstants.Network.requestTimeout
        configuration.timeoutIntervalForResource = AppConstants.Network.resourceTimeout
        configuration.waitsForConnectivity = true
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        self.session = URLSession(configuration: configuration)
    }
    
    // MARK: - 文字转语音（TTS）
    func convertTextToSpeech(_ text: String, voiceSettings: VoiceSettings, completion: @escaping (Result<AudioResponse, Error>) -> Void) {
        logInfo("开始TTS转换，文字长度: \(text.count)")
        
        // 使用TTS服务工厂创建对应供应商的TTS服务
        guard let ttsService = TTSServiceFactory.createFromConfig() else {
            let error = NetworkError.missingAPIKey
            logError("TTS转换失败: 无法创建TTS服务")
            completion(.failure(error))
            return
        }
        
        ttsService.synthesizeSpeech(text, voiceSettings: voiceSettings) { result in
            switch result {
            case .success(let audioResponse):
                if let audioData = audioResponse.audioData {
                    self.logInfo("TTS转换成功，音频大小: \(audioData.count) 字节")
                                        } else {
                    self.logInfo("TTS转换成功，但音频数据为空")
                }
                completion(.success(audioResponse))
                    case .failure(let error):
                self.logError("TTS转换失败: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    func convertTextsToSpeech(_ texts: [String], voiceSettings: VoiceSettings, completion: @escaping (Result<[AudioResponse], Error>) -> Void) {
        logInfo("开始批量TTS转换，文字数量: \(texts.count)")
        
        // 验证输入
        guard !texts.isEmpty else {
            let error = NetworkError.invalidInput("文字数组不能为空")
            logError("批量TTS转换失败: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        // 使用DispatchGroup来管理多个异步请求
        let group = DispatchGroup()
        var results: [Result<AudioResponse, Error>] = []
        let queue = DispatchQueue(label: "com.phototts.network", qos: .userInitiated)
        
        for text in texts {
            group.enter()
            convertTextToSpeech(text, voiceSettings: voiceSettings) { result in
                queue.async {
                    results.append(result)
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            // 检查是否有任何错误
            let errors = results.compactMap { result -> Error? in
                if case .failure(let error) = result {
                    return error
                }
                return nil
            }
            
            if !errors.isEmpty {
                self.logError("批量TTS转换失败: \(errors.count) 个错误")
                completion(.failure(NetworkError.batchProcessingFailed(errors)))
                return
            }
            
            // 提取成功的响应
            let audioResponses = results.compactMap { result -> AudioResponse? in
                if case .success(let response) = result {
                    return response
                }
                return nil
            }
            
            self.logInfo("批量TTS转换成功，完成数量: \(audioResponses.count)")
            completion(.success(audioResponses))
        }
    }
    
    func convertTextToSpeechBatch(_ texts: [String], voiceSettings: VoiceSettings, completion: @escaping (Result<[AudioResponse], Error>) -> Void) {
        // 调用现有的批量方法
        convertTextsToSpeech(texts, voiceSettings: voiceSettings, completion: completion)
    }
    
    func testConnection(completion: @escaping (Result<Bool, Error>) -> Void) {
        logInfo("测试网络连接")
        
        guard let url = URL(string: "\(baseURL)\(AppConstants.APIEndpoints.testConnection)") else {
            let error = NetworkError.invalidURL
            logError("连接测试失败: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0
        
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logError("连接测试失败: 网络错误 - \(error.localizedDescription)")
                completion(.failure(NetworkError.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logError("连接测试失败: 无效的HTTP响应")
                completion(.failure(NetworkError.invalidResponse))
                return
            }
            
            let isConnected = httpResponse.statusCode == 200
            self.logInfo("连接测试结果: \(isConnected ? "成功" : "失败")")
            completion(.success(isConnected))
        }.resume()
    }
    
    func cancelAllRequests() {
        session.invalidateAndCancel()
        logInfo("已取消所有网络请求")
    }
    
    // MARK: - 私有方法
    
    /// 解析音频响应
    private func parseAudioResponse(data: Data, originalText: String) throws -> AudioResponse {
        // 这里应该根据实际的API响应格式来解析
        // 目前返回模拟数据
        return AudioResponse(
            audioData: data,
            format: "mp3",
            duration: 5.0 // 模拟时长
        )
    }
    
    /// 记录信息日志
    private func logInfo(_ message: String) {
        os.Logger.networkService.info("\(message)")
        DebugLogManager.shared.directLog(message)
    }

    /// 记录错误日志
    private func logError(_ message: String) {
        os.Logger.networkService.error("\(message)")
        DebugLogManager.shared.directLog(message)
    }
}

// MARK: - 网络错误
enum NetworkError: LocalizedError {
    case invalidInput(String)
    case missingAPIKey
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case httpError(Int)
    case noData
    case batchProcessingFailed([Error])
    case serverError
    case noTexts
    case tooManyTexts
    case textTooLong
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "输入无效: \(message)"
        case .missingAPIKey:
            return "缺少API密钥"
        case .invalidURL:
            return "无效的URL"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            return "无效的响应"
        case .httpError(let code):
            return "HTTP错误: \(code)"
        case .noData:
            return "响应数据为空"
        case .batchProcessingFailed(let errors):
            return "批量处理失败: \(errors.count) 个错误"
        case .serverError:
            return "服务器错误"
        case .noTexts:
            return "没有文字内容"
        case .tooManyTexts:
            return "文字数量过多"
        case .textTooLong:
            return "文字内容过长，超过TTS合成限制"
        }
    }
}