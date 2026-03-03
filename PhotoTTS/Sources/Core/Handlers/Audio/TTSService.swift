import Foundation
import os.log
import UIKit

// MARK: - TTS配置模型
struct TTSConfiguration {
    let baseURL: String
    let appId: String
    let accessKey: String
    let cluster: String
    let voiceType: String
    let encoding: String
    let bitrate: Int
    let rate: Int
    let speedRatio: Double
    let timeout: TimeInterval
    let maxRetryCount: Int
    let retryDelay: TimeInterval
}

// MARK: - TTS服务
class TTSService {
    private let configuration: TTSConfiguration
    private let session: URLSession
    
    init(configuration: TTSConfiguration) {
        self.configuration = configuration
        
        // 配置URLSession，设置超时
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configuration.timeout
        config.timeoutIntervalForResource = configuration.timeout
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - 从配置文件创建TTS服务
    static func createFromConfig() -> TTSService? {
        let ttsConfig = SettingsManager.shared.loadTTSConfig()
        
        guard !ttsConfig.isEmpty else {
            NSLog("❌ 无法读取TTS配置")
            return nil
        }
        
        NSLog("✅ 成功读取TTS配置")
        
        let baseURL = ttsConfig["base_url"] as? String ?? "https://openspeech.bytedance.com/api/v1/tts"
        let appId = ttsConfig["appid"] as? String ?? ""
        let accessKey = ttsConfig["access_key"] as? String ?? ""
        let cluster = ttsConfig["cluster"] as? String ?? "volcano_tts"
        let voiceType = ttsConfig["voice_type"] as? String ?? "zh_female_tianmeixiaoyuan_moon_bigtts"
        let encoding = ttsConfig["encoding"] as? String ?? "mp3"
        let bitrate = ttsConfig["bitrate"] as? Int ?? 64
        let rate = ttsConfig["rate"] as? Int ?? 16000
        let speedRatio = ttsConfig["speed_ratio"] as? Double ?? 0.9
        let timeout = ttsConfig["timeout"] as? TimeInterval ?? 60.0
        let maxRetryCount = ttsConfig["max_retry_count"] as? Int ?? 3
        let retryDelay = ttsConfig["retry_delay"] as? TimeInterval ?? 1.0
        
        NSLog("✅ TTS配置信息:")
        NSLog("   - Base URL: \(baseURL)")
        NSLog("   - App ID: \(appId)")
        NSLog("   - Access Key: \(accessKey.isEmpty ? "❌ 空" : "✅ 已配置")")
        NSLog("   - Cluster: \(cluster)")
        NSLog("   - Voice Type: \(voiceType)")
        NSLog("   - Encoding: \(encoding)")
        NSLog("   - Bitrate: \(bitrate) kbps")
        NSLog("   - Rate: \(rate) Hz")
        NSLog("   - Speed Ratio: \(speedRatio)")
        NSLog("   - Timeout: \(timeout)秒")
        NSLog("   - Max Retry: \(maxRetryCount)次")
        NSLog("   - Retry Delay: \(retryDelay)秒")
        
        guard !baseURL.isEmpty && !appId.isEmpty && !accessKey.isEmpty else {
            NSLog("❌ TTS配置不完整")
            return nil
        }
        
        let ttsConfiguration = TTSConfiguration(
            baseURL: baseURL,
            appId: appId,
            accessKey: accessKey,
            cluster: cluster,
            voiceType: voiceType,
            encoding: encoding,
            bitrate: bitrate,
            rate: rate,
            speedRatio: speedRatio,
            timeout: timeout,
            maxRetryCount: maxRetryCount,
            retryDelay: retryDelay
        )
        
        NSLog("✅ TTS服务初始化成功")
        return TTSService(configuration: ttsConfiguration)
    }
    
    // MARK: - 语音合成
    func synthesizeSpeech(_ text: String, voiceSettings: VoiceSettings, completion: @escaping (Result<AudioResponse, Error>) -> Void) {
        logInfo("转换，文字长度: \(text.count)")
        
        // 验证输入
        guard !text.isEmpty else {
            let error = TTSError.invalidInput("文字内容不能为空")
            logError("TTS转换失败: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        // 使用带重试的TTS转换
        synthesizeSpeechWithRetry(text: text, voiceSettings: voiceSettings, completion: completion)
    }
    
    private func synthesizeSpeechWithRetry(text: String, voiceSettings: VoiceSettings, completion: @escaping (Result<AudioResponse, Error>) -> Void) {
        func attemptTTS(attempt: Int, lastError: Error?) {
            logInfo("🔄 TTS API调用尝试 \(attempt)/\(configuration.maxRetryCount)")
            
            synthesizeSpeechOnce(text, voiceSettings: voiceSettings) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    self.logInfo("✅ TTS API调用成功，尝试 \(attempt)")
                    completion(.success(response))
                case .failure(let error):
                    self.logError("❌ TTS API调用失败，尝试 \(attempt)/\(self.configuration.maxRetryCount): \(error.localizedDescription)")
                    
                    // 如果不是最后一次尝试，等待重试间隔
                    if attempt < self.configuration.maxRetryCount {
                        self.logInfo("⏳ 等待 \(self.configuration.retryDelay) 秒后重试...")
                        DispatchQueue.global().asyncAfter(deadline: .now() + self.configuration.retryDelay) {
                            attemptTTS(attempt: attempt + 1, lastError: error)
                        }
                    } else {
                        // 所有重试都失败了
                        self.logError("❌ TTS API调用失败，已重试 \(self.configuration.maxRetryCount) 次")
                        completion(.failure(error))
                    }
                }
            }
        }
        
        attemptTTS(attempt: 1, lastError: nil)
    }
    
    private func synthesizeSpeechOnce(_ text: String, voiceSettings: VoiceSettings, completion: @escaping (Result<AudioResponse, Error>) -> Void) {
        // 获取设备唯一标识符
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)
        
        // 构建豆包TTS请求
        let doubaoParams: [String: Any] = [
            "app": [
                "appid": configuration.appId,
                "cluster": configuration.cluster,
                "token": "tts_token_\(deviceID)_\(timestamp)"
            ],
            "user": [
                "uid": "tts_uid_\(deviceID)_\(timestamp)"
            ],
            "request": [
                "reqid": UUID().uuidString,
                "operation": "query",
                "text": text
            ],
            "audio": [
                "encoding": configuration.encoding,
                "voice_type": configuration.voiceType,
                "bitrate": configuration.bitrate,
                "rate": configuration.rate,
                "speed_ratio": configuration.speedRatio
            ]
        ]
        
        // 发送TTS请求
        guard let url = URL(string: configuration.baseURL) else {
            let error = TTSError.invalidURL
            logError("TTS转换失败: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 添加Authorization头（Bearer Token认证）
        let bearerToken = "Bearer; \(configuration.accessKey)"
        request.setValue(bearerToken, forHTTPHeaderField: "Authorization")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: doubaoParams)
            request.httpBody = jsonData
            
            logInfo("发送TTS请求到: \(url)")
            
            session.dataTask(with: request) { data, response, error in
                if let error = error {
                    self.logError("TTS转换失败: 网络错误 - \(error.localizedDescription)")
                    completion(.failure(TTSError.networkError(error)))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.logError("TTS转换失败: 无效的HTTP响应")
                    completion(.failure(TTSError.invalidResponse))
                    return
                }
                
                self.logInfo("TTS响应状态: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode != 200 {
                    let errorMessage = String(data: data ?? Data(), encoding: .utf8) ?? "未知错误"
                    self.logError("TTS转换失败: HTTP错误 \(httpResponse.statusCode) - \(errorMessage)")
                    completion(.failure(TTSError.httpError(httpResponse.statusCode, errorMessage)))
                    return
                }
                
                guard let data = data else {
                    self.logError("TTS转换失败: 响应数据为空")
                    completion(.failure(TTSError.noData))
                    return
                }
                
                // 检查响应内容类型
                if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                    self.logInfo("收到TTS响应，Content-Type: \(contentType)")
                    
                    if contentType.contains("audio/") {
                        // 直接返回音频数据
                        self.logInfo("收到音频数据，大小: \(data.count) 字节")
                        let audioResponse = AudioResponse(
                            audioData: data,
                            format: self.configuration.encoding,
                            duration: Double(data.count) / 16000.0 // 估算时长
                        )
                        completion(.success(audioResponse))
                        return
                    }
                }
                
                // 尝试解析JSON响应
                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    self.logInfo("收到豆包TTS API响应")
                    
                    // 检查是否有音频数据（Base64编码）
                    if let audioBase64 = json?["audio"] as? String,
                       let audioData = Data(base64Encoded: audioBase64) {
                        self.logInfo("成功解析Base64音频数据，大小: \(audioData.count) 字节")
                        let audioResponse = AudioResponse(
                            audioData: audioData,
                            format: self.configuration.encoding,
                            duration: Double(audioData.count) / 16000.0
                        )
                        completion(.success(audioResponse))
                        return
                    }
                    
                    // 检查是否有data字段包含音频
                    if let audioBase64 = json?["data"] as? String,
                       let audioData = Data(base64Encoded: audioBase64) {
                        self.logInfo("成功解析data字段中的音频数据，大小: \(audioData.count) 字节")
                        let audioResponse = AudioResponse(
                            audioData: audioData,
                            format: self.configuration.encoding,
                            duration: Double(audioData.count) / 16000.0
                        )
                        completion(.success(audioResponse))
                        return
                    }
                    
                    // 检查是否有result字段
                    if let result = json?["result"] as? [String: Any],
                       let audioBase64 = result["audio"] as? String,
                       let audioData = Data(base64Encoded: audioBase64) {
                        self.logInfo("成功解析result中的音频数据，大小: \(audioData.count) 字节")
                        let audioResponse = AudioResponse(
                            audioData: audioData,
                            format: self.configuration.encoding,
                            duration: Double(audioData.count) / 16000.0
                        )
                        completion(.success(audioResponse))
                        return
                    }
                    
                    self.logError("未找到音频数据字段")
                    completion(.failure(TTSError.noAudioData))
                    
                } catch {
                    // 如果不是JSON，检查是否是直接的音频数据
                    if data.count > 0 {
                        self.logInfo("收到二进制数据，可能是音频文件，大小: \(data.count) 字节")
                        let audioResponse = AudioResponse(
                            audioData: data,
                            format: self.configuration.encoding,
                            duration: Double(data.count) / 16000.0
                        )
                        completion(.success(audioResponse))
                        return
                    }
                    
                    self.logError("响应数据为空或无法解析")
                    completion(.failure(TTSError.invalidResponse))
                }
                
            }.resume()
            
        } catch {
            logError("TTS转换失败: JSON序列化错误 - \(error.localizedDescription)")
            completion(.failure(error))
        }
    }
    
    // MARK: - 日志方法
    private func logInfo(_ message: String) {
        os.Logger.ttsService.info("\(message)")
    }
    
    private func logError(_ message: String) {
        os.Logger.ttsService.error("\(message)")
    }
}

// MARK: - TTS错误类型
enum TTSError: LocalizedError {
    case invalidInput(String)
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case httpError(Int, String)
    case noData
    case noAudioData
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "输入无效: \(message)"
        case .invalidURL:
            return "无效的URL"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            return "无效的响应"
        case .httpError(let code, let message):
            return "HTTP错误: \(code) - \(message)"
        case .noData:
            return "响应数据为空"
        case .noAudioData:
            return "未找到音频数据"
        }
    }
}
