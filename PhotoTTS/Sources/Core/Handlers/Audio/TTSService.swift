import Foundation
import os.log
import UIKit

// MARK: - TTS服务协议
protocol TTSServiceProtocol {
    /// 语音合成
    /// - Parameters:
    ///   - text: 待合成的文字
    ///   - voiceSettings: 语音设置
    ///   - completion: 完成回调
    func synthesizeSpeech(_ text: String, voiceSettings: VoiceSettings, completion: @escaping (Result<AudioResponse, Error>) -> Void)
}

// MARK: - 火山TTS配置模型
struct HuoshanTTSConfiguration {
    let provider: String
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

// MARK: - 火山TTS服务
class TTSService: TTSServiceProtocol {
    private let configuration: HuoshanTTSConfiguration
    private let session: URLSession
    
    init(configuration: HuoshanTTSConfiguration) {
        self.configuration = configuration
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configuration.timeout
        config.timeoutIntervalForResource = configuration.timeout
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - 语音合成
    func synthesizeSpeech(_ text: String, voiceSettings: VoiceSettings, completion: @escaping (Result<AudioResponse, Error>) -> Void) {
        let providerTag = "[TTS] 模型\(configuration.provider)，"
        logInfo("\(providerTag) 转换，文字长度: \(text.count)")
        
        guard !text.isEmpty else {
            let error = TTSError.invalidInput("文字内容不能为空")
            logError("\(providerTag) TTS转换失败: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        synthesizeSpeechWithRetry(text: text, voiceSettings: voiceSettings, completion: completion)
    }
    
    private func synthesizeSpeechWithRetry(text: String, voiceSettings: VoiceSettings, completion: @escaping (Result<AudioResponse, Error>) -> Void) {
        let providerTag = "[TTS] 模型\(configuration.provider)，"
        
        func attemptTTS(attempt: Int, lastError: Error?) {
            logInfo("\(providerTag) TTS API调用尝试 \(attempt)/\(configuration.maxRetryCount)")
            
            synthesizeSpeechOnce(text, voiceSettings: voiceSettings) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    self.logInfo("\(providerTag) TTS API调用成功，尝试 \(attempt)")
                    completion(.success(response))
                case .failure(let error):
                    self.logError("\(providerTag) TTS API调用失败，尝试 \(attempt)/\(self.configuration.maxRetryCount): \(error.localizedDescription)")
                    
                    if attempt < self.configuration.maxRetryCount {
                        self.logInfo("\(providerTag) 等待 \(self.configuration.retryDelay) 秒后重试...")
                        DispatchQueue.global().asyncAfter(deadline: .now() + self.configuration.retryDelay) {
                            attemptTTS(attempt: attempt + 1, lastError: error)
                        }
                    } else {
                        self.logError("\(providerTag) TTS API调用失败，已重试 \(self.configuration.maxRetryCount) 次")
                        completion(.failure(error))
                    }
                }
            }
        }
        
        attemptTTS(attempt: 1, lastError: nil)
    }
    
    private func synthesizeSpeechOnce(_ text: String, voiceSettings: VoiceSettings, completion: @escaping (Result<AudioResponse, Error>) -> Void) {
        let providerTag = "[TTS] 模型\(configuration.provider)，"
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)
        
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
        
        guard let url = URL(string: configuration.baseURL) else {
            let error = TTSError.invalidURL
            logError("\(providerTag) TTS转换失败: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let bearerToken = "Bearer; \(configuration.accessKey)"
        request.setValue(bearerToken, forHTTPHeaderField: "Authorization")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: doubaoParams)
            request.httpBody = jsonData
            
            logInfo("\(providerTag) 发送TTS请求到: \(url)")
            
            session.dataTask(with: request) { data, response, error in
                if let error = error {
                    self.logError("\(providerTag) TTS转换失败: 网络错误 - \(error.localizedDescription)")
                    completion(.failure(TTSError.networkError(error)))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.logError("\(providerTag) TTS转换失败: 无效的HTTP响应")
                    completion(.failure(TTSError.invalidResponse))
                    return
                }
                
                self.logInfo("\(providerTag) TTS响应状态: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode != 200 {
                    let errorMessage = String(data: data ?? Data(), encoding: .utf8) ?? "未知错误"
                    self.logError("\(providerTag) TTS转换失败: HTTP错误 \(httpResponse.statusCode) - \(errorMessage)")
                    completion(.failure(TTSError.httpError(httpResponse.statusCode, errorMessage)))
                    return
                }
                
                guard let data = data else {
                    self.logError("\(providerTag) TTS转换失败: 响应数据为空")
                    completion(.failure(TTSError.noData))
                    return
                }
                
                if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                    self.logInfo("\(providerTag) 收到TTS响应，Content-Type: \(contentType)")
                    
                    if contentType.contains("audio/") {
                        self.logInfo("\(providerTag) 收到音频数据，大小: \(data.count) 字节")
                        let audioResponse = AudioResponse(
                            audioData: data,
                            format: self.configuration.encoding,
                            duration: Double(data.count) / 16000.0
                        )
                        completion(.success(audioResponse))
                        return
                    }
                }
                
                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    self.logInfo("\(providerTag) 收到TTS API响应")
                    
                    if let audioBase64 = json?["audio"] as? String,
                       let audioData = Data(base64Encoded: audioBase64) {
                        self.logInfo("\(providerTag) 成功解析Base64音频数据，大小: \(audioData.count) 字节")
                        let audioResponse = AudioResponse(
                            audioData: audioData,
                            format: self.configuration.encoding,
                            duration: Double(audioData.count) / 16000.0
                        )
                        completion(.success(audioResponse))
                        return
                    }
                    
                    if let audioBase64 = json?["data"] as? String,
                       let audioData = Data(base64Encoded: audioBase64) {
                        self.logInfo("\(providerTag) 成功解析data字段中的音频数据，大小: \(audioData.count) 字节")
                        let audioResponse = AudioResponse(
                            audioData: audioData,
                            format: self.configuration.encoding,
                            duration: Double(audioData.count) / 16000.0
                        )
                        completion(.success(audioResponse))
                        return
                    }
                    
                    if let result = json?["result"] as? [String: Any],
                       let audioBase64 = result["audio"] as? String,
                       let audioData = Data(base64Encoded: audioBase64) {
                        self.logInfo("\(providerTag) 成功解析result中的音频数据，大小: \(audioData.count) 字节")
                        let audioResponse = AudioResponse(
                            audioData: audioData,
                            format: self.configuration.encoding,
                            duration: Double(audioData.count) / 16000.0
                        )
                        completion(.success(audioResponse))
                        return
                    }
                    
                    self.logError("\(providerTag) 未找到音频数据字段")
                    completion(.failure(TTSError.noAudioData))
                    
                } catch {
                    let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
                    let isAudioContentType = contentType.contains("audio/")
                    let isAudioMagicBytes = Self.hasAudioMagicBytes(data)
                    
                    if data.count > 0 && (isAudioContentType || isAudioMagicBytes) {
                        self.logInfo("\(providerTag) 收到二进制音频数据，大小: \(data.count) 字节，Content-Type: \(contentType)")
                        let audioResponse = AudioResponse(
                            audioData: data,
                            format: self.configuration.encoding,
                            duration: Double(data.count) / 16000.0
                        )
                        completion(.success(audioResponse))
                        return
                    }
                    
                    self.logError("\(providerTag) 响应数据无法解析为音频: Content-Type=\(contentType), 数据大小=\(data.count)")
                    completion(.failure(TTSError.invalidResponse))
                }
                
            }.resume()
            
        } catch {
            logError("\(providerTag) TTS转换失败: JSON序列化错误 - \(error.localizedDescription)")
            completion(.failure(error))
        }
    }
    
    // MARK: - 音频格式校验
    private static func hasAudioMagicBytes(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        if data[0] == 0xFF && (data[1] & 0xE0 == 0xE0) { return true }
        if data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33 { return true }
        if data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 { return true }
        return false
    }
    
    // MARK: - 日志方法
    private func logInfo(_ message: String) {
        os.Logger.ttsService.info("\(message)")
    }
    
    private func logError(_ message: String) {
        os.Logger.ttsService.error("\(message)")
    }
}

// MARK: - 阿里千问TTS配置模型
struct AliqwenTTSConfiguration {
    let provider: String
    let baseURL: String
    let secretKey: String
    let model: String
    let voice: String
    let languageType: String
    let instructions: String
    let stream: Bool
    let timeout: TimeInterval
    let maxRetryCount: Int
    let retryDelay: TimeInterval
}

// MARK: - 阿里千问TTS服务
class AliqwenTTSService: TTSServiceProtocol {
    private let configuration: AliqwenTTSConfiguration
    private let session: URLSession
    
    init(configuration: AliqwenTTSConfiguration) {
        self.configuration = configuration
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configuration.timeout
        config.timeoutIntervalForResource = configuration.timeout
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - 语音合成
    func synthesizeSpeech(_ text: String, voiceSettings: VoiceSettings, completion: @escaping (Result<AudioResponse, Error>) -> Void) {
        let providerTag = "[TTS] 模型\(configuration.provider)，"
        logInfo("\(providerTag) 转换，文字长度: \(text.count)")
        
        guard !text.isEmpty else {
            let error = TTSError.invalidInput("文字内容不能为空")
            logError("\(providerTag) TTS转换失败: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        synthesizeSpeechWithRetry(text: text, voiceSettings: voiceSettings, completion: completion)
    }
    
    private func synthesizeSpeechWithRetry(text: String, voiceSettings: VoiceSettings, completion: @escaping (Result<AudioResponse, Error>) -> Void) {
        let providerTag = "[TTS] 模型\(configuration.provider)，"
        
        func attemptTTS(attempt: Int, lastError: Error?) {
            logInfo("\(providerTag) TTS API调用尝试 \(attempt)/\(configuration.maxRetryCount)")
            
            synthesizeSpeechOnce(text, voiceSettings: voiceSettings) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    self.logInfo("\(providerTag) TTS API调用成功，尝试 \(attempt)")
                    completion(.success(response))
                case .failure(let error):
                    self.logError("\(providerTag) TTS API调用失败，尝试 \(attempt)/\(self.configuration.maxRetryCount): \(error.localizedDescription)")
                    
                    if attempt < self.configuration.maxRetryCount {
                        self.logInfo("\(providerTag) 等待 \(self.configuration.retryDelay) 秒后重试...")
                        DispatchQueue.global().asyncAfter(deadline: .now() + self.configuration.retryDelay) {
                            attemptTTS(attempt: attempt + 1, lastError: error)
                        }
                    } else {
                        self.logError("\(providerTag) TTS API调用失败，已重试 \(self.configuration.maxRetryCount) 次")
                        completion(.failure(error))
                    }
                }
            }
        }
        
        attemptTTS(attempt: 1, lastError: nil)
    }
    
    private func synthesizeSpeechOnce(_ text: String, voiceSettings: VoiceSettings, completion: @escaping (Result<AudioResponse, Error>) -> Void) {
        let providerTag = "[TTS] 模型\(configuration.provider)，"
        
        // 构建阿里千问3-TTS-Flash请求体（DashScope扁平input格式）
        // 官方文档: https://help.aliyun.com/zh/model-studio/qwen-tts-api
        let requestBody: [String: Any] = [
            "model": configuration.model,
            "input": [
                "text": text,
                "voice": configuration.voice,
                "language_type": configuration.languageType
            ]
        ]
        
        guard let url = URL(string: configuration.baseURL) else {
            let error = TTSError.invalidURL
            logError("\(providerTag) TTS转换失败: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.secretKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [.sortedKeys])
            request.httpBody = jsonData
            
            logInfo("\(providerTag) 发送TTS请求到: \(url.host ?? "")\(url.path), model=\(configuration.model), textLen=\(text.count)")
            
            session.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.logError("\(providerTag) TTS转换失败: 网络错误 - \(error.localizedDescription)")
                    completion(.failure(TTSError.networkError(error)))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.logError("\(providerTag) TTS转换失败: 无效的HTTP响应")
                    completion(.failure(TTSError.invalidResponse))
                    return
                }
                
                self.logInfo("\(providerTag) TTS响应状态: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode != 200 {
                    let errorMessage = String(data: data ?? Data(), encoding: .utf8) ?? "未知错误"
                    self.logError("\(providerTag) TTS转换失败: HTTP错误 \(httpResponse.statusCode) - \(errorMessage)")
                    completion(.failure(TTSError.httpError(httpResponse.statusCode, errorMessage)))
                    return
                }
                
                guard let data = data else {
                    self.logError("\(providerTag) TTS转换失败: 响应数据为空")
                    completion(.failure(TTSError.noData))
                    return
                }
                
                // 解析DashScope响应
                self.parseDashScopeResponse(data: data, providerTag: providerTag, completion: completion)
                
            }.resume()
            
        } catch {
            logError("\(providerTag) TTS转换失败: JSON序列化错误 - \(error.localizedDescription)")
            completion(.failure(error))
        }
    }
    
    /// 解析DashScope API响应，从 output.audio.url 下载音频文件
    private func parseDashScopeResponse(data: Data, providerTag: String, completion: @escaping (Result<AudioResponse, Error>) -> Void) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logError("\(providerTag) TTS转换失败: 响应不是有效的JSON")
                completion(.failure(TTSError.invalidResponse))
                return
            }
            
            logInfo("\(providerTag) 收到阿里千问TTS API响应")
            
            // 检查API级别错误（code非空字符串表示有错误）
            if let code = json["code"] as? String, !code.isEmpty,
               let message = json["message"] as? String {
                logError("\(providerTag) API返回错误: code=\(code), message=\(message)")
                completion(.failure(TTSError.httpError(-1, "\(code): \(message)")))
                return
            }
            
            // 解析 output.audio
            guard let output = json["output"] as? [String: Any],
                  let audio = output["audio"] as? [String: Any] else {
                logError("\(providerTag) 响应中未找到 output.audio 字段")
                completion(.failure(TTSError.noAudioData))
                return
            }
            
            // 获取 usage.characters 用于日志
            let characters = (json["usage"] as? [String: Any])?["characters"] as? Int ?? 0
            logInfo("\(providerTag) API处理字符数: \(characters)")
            
            // 优先从 output.audio.url 下载音频
            // DashScope返回的URL可能是http，强制转换为https以符合ATS安全策略
            if let audioURLString = audio["url"] as? String, !audioURLString.isEmpty {
                let secureURLString = audioURLString.hasPrefix("http://")
                    ? audioURLString.replacingOccurrences(of: "http://", with: "https://", options: [], range: audioURLString.startIndex..<audioURLString.index(audioURLString.startIndex, offsetBy: min(7, audioURLString.count)))
                    : audioURLString
                guard let audioURL = URL(string: secureURLString) else {
                    logError("\(providerTag) 音频URL无效: \(secureURLString.prefix(80))")
                    completion(.failure(TTSError.invalidURL))
                    return
                }
                logInfo("\(providerTag) 从URL下载音频: \(secureURLString.prefix(80))...")
                self.downloadAudio(from: audioURL, providerTag: providerTag, completion: completion)
                return
            }
            
            // 备用: 从 output.audio.data 解码base64音频
            if let audioBase64 = audio["data"] as? String, !audioBase64.isEmpty,
               let audioData = Data(base64Encoded: audioBase64) {
                logInfo("\(providerTag) 成功解析base64音频数据，大小: \(audioData.count) 字节")
                let audioResponse = AudioResponse(
                    audioData: audioData,
                    format: "wav",
                    duration: Double(audioData.count) / 16000.0
                )
                completion(.success(audioResponse))
                return
            }
            
            logError("\(providerTag) output.audio 中未找到有效的 url 或 data")
            completion(.failure(TTSError.noAudioData))
            
        } catch {
            logError("\(providerTag) 响应JSON解析失败: \(error.localizedDescription)")
            completion(.failure(TTSError.invalidResponse))
        }
    }
    
    /// 从URL下载音频文件
    private func downloadAudio(from url: URL, providerTag: String, completion: @escaping (Result<AudioResponse, Error>) -> Void) {
        session.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logError("\(providerTag) 音频下载失败: \(error.localizedDescription)")
                completion(.failure(TTSError.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                self.logError("\(providerTag) 音频下载失败: HTTP \(statusCode)")
                completion(.failure(TTSError.httpError(statusCode, "音频文件下载失败")))
                return
            }
            
            guard let audioData = data, !audioData.isEmpty else {
                self.logError("\(providerTag) 音频下载失败: 数据为空")
                completion(.failure(TTSError.noData))
                return
            }
            
            // 从Content-Type或URL推断音频格式
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            let format: String
            if contentType.contains("wav") || url.pathExtension == "wav" {
                format = "wav"
            } else if contentType.contains("mp3") || url.pathExtension == "mp3" {
                format = "mp3"
            } else {
                format = "wav" // DashScope默认返回wav
            }
            
            self.logInfo("\(providerTag) 音频下载成功，大小: \(audioData.count) 字节，格式: \(format)")
            let audioResponse = AudioResponse(
                audioData: audioData,
                format: format,
                duration: Double(audioData.count) / 16000.0
            )
            completion(.success(audioResponse))
        }.resume()
    }
    
    // MARK: - 日志方法
    private func logInfo(_ message: String) {
        os.Logger.ttsService.info("\(message)")
    }
    
    private func logError(_ message: String) {
        os.Logger.ttsService.error("\(message)")
    }
}

// MARK: - TTS服务工厂
class TTSServiceFactory {
    
    /// 根据config_local.json中tts.provider字段创建对应的TTS服务
    /// 支持huoshan和aliqwen两种供应商
    static func createFromConfig() -> TTSServiceProtocol? {
        let settingsManager = SettingsManager.shared
        let activeProvider = settingsManager.getActiveTTSProvider()
        let providerConfig = settingsManager.loadActiveTTSProviderConfig()
        
        guard !providerConfig.isEmpty else {
            os.Logger.ttsService.error("无法读取TTS供应商[\(activeProvider)]配置")
            return nil
        }
        
        os.Logger.ttsService.info("成功读取TTS配置，活跃供应商: \(activeProvider)")
        
        switch activeProvider {
        case "aliqwen":
            return createAliqwenService(providerConfig: providerConfig, settingsManager: settingsManager, activeProvider: activeProvider)
        default:
            return createHuoshanService(providerConfig: providerConfig, settingsManager: settingsManager, activeProvider: activeProvider)
        }
    }
    
    // MARK: - 火山TTS创建
    private static func createHuoshanService(providerConfig: [String: Any], settingsManager: SettingsManager, activeProvider: String) -> TTSServiceProtocol? {
        let ttsConfig = settingsManager.loadTTSConfig()
        
        let baseURL = providerConfig["base_url"] as? String ?? Constants.ServiceDefaults.ttsBaseURL
        let appId = providerConfig["appid"] as? String ?? ""
        let accessKey = settingsManager.getTTSSecretKeyForProvider(activeProvider)
        let cluster = providerConfig["cluster"] as? String ?? Constants.ServiceDefaults.ttsCluster
        let voiceType = providerConfig["voice_type"] as? String ?? Constants.ServiceDefaults.ttsVoiceType
        let encoding = providerConfig["encoding"] as? String ?? Constants.ServiceDefaults.ttsEncoding
        let bitrate = providerConfig["bitrate"] as? Int ?? Constants.ServiceDefaults.huoshanBitrate
        let rate = providerConfig["rate"] as? Int ?? Constants.ServiceDefaults.huoshanRate
        let speedRatio = providerConfig["speed_ratio"] as? Double ?? Constants.ServiceDefaults.huoshanSpeedRatio
        let timeout = providerConfig["timeout"] as? TimeInterval
            ?? ttsConfig["timeout"] as? TimeInterval
            ?? Constants.ServiceDefaults.huoshanTimeout
        let maxRetryCount = providerConfig["max_retry_count"] as? Int
            ?? ttsConfig["max_retry_count"] as? Int
            ?? 3
        let retryDelay = providerConfig["retry_delay"] as? TimeInterval
            ?? ttsConfig["retry_delay"] as? TimeInterval
            ?? 1.0
        
        os.Logger.ttsService.info("[TTS] 模型\(activeProvider)，配置: voiceType=\(voiceType), encoding=\(encoding), timeout=\(timeout)s, retry=\(maxRetryCount)x\(retryDelay)s")
        os.Logger.ttsService.info("[TTS] 模型\(activeProvider)，凭证: appId=\(appId.count > 4 ? "***" + appId.suffix(4) : (appId.isEmpty ? "空" : "已配置")), accessKey=\(accessKey.isEmpty ? "空" : "***" + accessKey.suffix(4))")
        
        guard !baseURL.isEmpty && !appId.isEmpty && !accessKey.isEmpty else {
            os.Logger.ttsService.error("[TTS] 模型\(activeProvider)，TTS配置不完整")
            return nil
        }
        
        let configuration = HuoshanTTSConfiguration(
            provider: activeProvider,
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
        
        os.Logger.ttsService.info("[TTS] 模型\(activeProvider)，TTS服务初始化成功")
        return TTSService(configuration: configuration)
    }
    
    // MARK: - 阿里千问TTS创建
    private static func createAliqwenService(providerConfig: [String: Any], settingsManager: SettingsManager, activeProvider: String) -> TTSServiceProtocol? {
        let ttsConfig = settingsManager.loadTTSConfig()
        
        let baseURL = providerConfig["base_url"] as? String ?? Constants.ServiceDefaults.aliqwenTTSBaseURL
        let secretKey = settingsManager.getTTSSecretKeyForProvider(activeProvider)
        let model = providerConfig["model"] as? String ?? Constants.ServiceDefaults.aliqwenTTSModel
        let voice = providerConfig["voice"] as? String ?? Constants.ServiceDefaults.aliqwenTTSVoice
        let languageType = providerConfig["language_type"] as? String ?? Constants.ServiceDefaults.aliqwenTTSLanguageType
        let instructions = providerConfig["instructions"] as? String ?? ""
        let stream = providerConfig["stream"] as? Bool ?? false
        let timeout = providerConfig["timeout"] as? TimeInterval
            ?? ttsConfig["timeout"] as? TimeInterval
            ?? Constants.ServiceDefaults.aliqwenTimeout
        let maxRetryCount = providerConfig["max_retry_count"] as? Int
            ?? ttsConfig["max_retry_count"] as? Int
            ?? 3
        let retryDelay = providerConfig["retry_delay"] as? TimeInterval
            ?? ttsConfig["retry_delay"] as? TimeInterval
            ?? 1.0
        
        os.Logger.ttsService.info("[TTS] 模型\(activeProvider)，配置: model=\(model), voice=\(voice), lang=\(languageType), timeout=\(timeout)s, retry=\(maxRetryCount)x\(retryDelay)s")
        os.Logger.ttsService.info("[TTS] 模型\(activeProvider)，凭证: secretKey=\(secretKey.isEmpty ? "空" : "***" + secretKey.suffix(4))")
        
        guard !secretKey.isEmpty else {
            os.Logger.ttsService.error("[TTS] 模型\(activeProvider)，未配置TTS Secret Key")
            return nil
        }
        
        let configuration = AliqwenTTSConfiguration(
            provider: activeProvider,
            baseURL: baseURL,
            secretKey: secretKey,
            model: model,
            voice: voice,
            languageType: languageType,
            instructions: instructions,
            stream: stream,
            timeout: timeout,
            maxRetryCount: maxRetryCount,
            retryDelay: retryDelay
        )
        
        os.Logger.ttsService.info("[TTS] 模型\(activeProvider)，TTS服务初始化成功")
        return AliqwenTTSService(configuration: configuration)
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
        case .invalidInput:
            return "输入内容无效，请检查后重试"
        case .invalidURL:
            return "服务配置异常，请检查设置"
        case .networkError:
            return "网络连接失败，请检查网络后重试"
        case .invalidResponse:
            return "语音合成服务响应异常，请稍后重试"
        case .httpError:
            return "语音合成服务暂时不可用，请稍后重试"
        case .noData:
            return "语音合成服务未返回数据，请稍后重试"
        case .noAudioData:
            return "语音合成未生成音频，请稍后重试"
        }
    }

    /// 技术详情描述，供 os.Logger 记录
    var technicalDescription: String {
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
