import Foundation

// MARK: - API响应基础模型
struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let message: String?
    let data: T?
    let error: APIError?
    
    enum CodingKeys: String, CodingKey {
        case success
        case message
        case data
        case error
    }
}

// MARK: - API错误模型
struct APIError: Codable, LocalizedError {
    let code: String
    let message: String
    let details: String?
    
    var errorDescription: String? {
        return message
    }
    
    var failureReason: String? {
        return details
    }
}

// MARK: - 音频响应模型
struct AudioResponse: Codable, Identifiable {
    let id: String
    let audioURL: String
    let text: String
    let language: String
    let duration: TimeInterval
    let format: String
    let quality: String
    let timestamp: Date
    let voiceSettings: VoiceSettings?
    let audioData: Data? // 添加音频数据属性
    let validImageCount: Int? // 添加有效图片数属性
    let recognizedTexts: [String]? // 每张图片对应的文本数组
    
    enum CodingKeys: String, CodingKey {
        case id
        case audioURL = "audio_url"
        case text
        case language
        case duration
        case format
        case quality
        case timestamp
        case voiceSettings = "voice_settings"
        case validImageCount = "valid_image_count"
        case recognizedTexts = "recognized_texts"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        audioURL = try container.decode(String.self, forKey: .audioURL)
        text = try container.decode(String.self, forKey: .text)
        language = try container.decode(String.self, forKey: .language)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        format = try container.decode(String.self, forKey: .format)
        quality = try container.decode(String.self, forKey: .quality)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        voiceSettings = try container.decodeIfPresent(VoiceSettings.self, forKey: .voiceSettings)
        validImageCount = try container.decodeIfPresent(Int.self, forKey: .validImageCount)
        recognizedTexts = try container.decodeIfPresent([String].self, forKey: .recognizedTexts)
        audioData = nil // 从JSON解码时，audioData通常为nil
    }
    
    // 自定义初始化器（用于测试）
    init(id: String, audioURL: String, text: String, language: String, duration: TimeInterval, format: String, quality: String, timestamp: Date, voiceSettings: VoiceSettings? = nil, audioData: Data? = nil, validImageCount: Int? = nil, recognizedTexts: [String]? = nil) {
        self.id = id
        self.audioURL = audioURL
        self.text = text
        self.language = language
        self.duration = duration
        self.format = format
        self.quality = quality
        self.timestamp = timestamp
        self.voiceSettings = voiceSettings
        self.audioData = audioData
        self.validImageCount = validImageCount
        self.recognizedTexts = recognizedTexts
    }
    
    // TTS专用初始化器（用于从TTS响应创建）
    init(audioData: Data, format: String, duration: Double, validImageCount: Int? = nil, recognizedTexts: [String]? = nil) {
        self.id = UUID().uuidString
        self.audioURL = "" // TTS直接返回音频数据，不需要URL
        self.text = "" // TTS输入的文字，这里暂时为空
        self.language = "zh" // 默认中文
        self.duration = duration
        self.format = format
        self.quality = "high" // TTS音频质量
        self.timestamp = Date()
        self.voiceSettings = nil
        self.audioData = audioData // 设置音频数据
        self.validImageCount = validImageCount
        self.recognizedTexts = recognizedTexts
    }
}

// MARK: - 批量音频响应模型
struct BatchAudioResponse: Codable {
    let responses: [AudioResponse]
    let totalCount: Int
    let successCount: Int
    let failedCount: Int
    let processingTime: TimeInterval
    
    enum CodingKeys: String, CodingKey {
        case responses
        case totalCount = "total_count"
        case successCount = "success_count"
        case failedCount = "failed_count"
        case processingTime = "processing_time"
    }
}

// MARK: - 图片上传请求模型
struct ImageUploadRequest: Codable {
    let image: String          // Base64编码的图片
    let format: String         // 图片格式 (jpg, png)
    let quality: Int           // 图片质量 (1-100)
    let language: String?      // 目标语言
    let voiceSettings: VoiceSettingsRequest?
    
    struct VoiceSettingsRequest: Codable {
        let speed: Double
        let pitch: Double
        let volume: Double
        let voiceType: String
    }
}

// MARK: - 批量图片上传请求模型
struct BatchImageUploadRequest: Codable {
    let images: [ImageUploadRequest]
    let batchId: String
    let priority: String       // low, normal, high
    let callbackURL: String?   // 回调URL
}

// MARK: - 上传进度模型
struct UploadProgress: Codable {
    let batchId: String
    let totalCount: Int
    let completedCount: Int
    let failedCount: Int
    let status: UploadStatus
    let estimatedTimeRemaining: TimeInterval?
    
    enum UploadStatus: String, Codable, CaseIterable {
        case pending = "pending"
        case processing = "processing"
        case completed = "completed"
        case failed = "failed"
        case cancelled = "cancelled"
        
        var displayName: String {
            switch self {
            case .pending:
                return "等待中"
            case .processing:
                return "处理中"
            case .completed:
                return "已完成"
            case .failed:
                return "失败"
            case .cancelled:
                return "已取消"
            }
        }
        
        var color: String {
            switch self {
            case .pending:
                return "blue"
            case .processing:
                return "orange"
            case .completed:
                return "green"
            case .failed:
                return "red"
            case .cancelled:
                return "gray"
            }
        }
    }
    
    var progress: Double {
        guard totalCount > 0 else { return 0.0 }
        return Double(completedCount + failedCount) / Double(totalCount)
    }
    
    var isCompleted: Bool {
        return status == .completed || status == .failed
        }
    
    var isProcessing: Bool {
        return status == .processing
    }
}

// MARK: - API端点枚举
enum APIEndpoint {
    case testConnection
    case textToSpeech
    case batchTextToSpeech
    
    var path: String {
        switch self {
        case .testConnection:
            return "/test"
        case .textToSpeech:
            return "/v1/tts/synthesize"
        case .batchTextToSpeech:
            return "/v1/tts/batch-synthesize"
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .testConnection:
            return .GET
        case .textToSpeech, .batchTextToSpeech:
            return .POST
        }
    }
    
    var requiresBody: Bool {
        switch self {
        case .textToSpeech, .batchTextToSpeech:
            return true
        default:
            return false
        }
    }
}

// MARK: - HTTP方法枚举
enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
    case PATCH = "PATCH"
}

// MARK: - 网络配置
struct NetworkConfig {
    static let baseURL = AppConstants.Network.baseURL
    static let timeout: TimeInterval = AppConstants.Network.requestTimeout
    static let maxRetryCount = AppConstants.Network.maxRetryCount
    static let retryDelay: TimeInterval = AppConstants.Network.retryDelay
    
    static let headers: [String: String] = [
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "PhotoTTS/\(AppConstants.appVersion)"
    ]
}

// MARK: - TTS请求模型
struct TextToSpeechRequest: Codable {
    let app: TTSAppInfo
    let user: TTSUserInfo
    let request: TTSRequestInfo
    let audio: TTSAudioSettings
}

struct TTSAppInfo: Codable {
    let appid: String
    let cluster: String
    let token: String
}

struct TTSUserInfo: Codable {
    let uid: String
}

struct TTSRequestInfo: Codable {
    let reqid: String
    let operation: String
    let text: String
}

struct TTSAudioSettings: Codable {
    let encoding: String
    let voiceType: String
    let speedRatio: Double
    
    enum CodingKeys: String, CodingKey {
        case encoding
        case voiceType = "voice_type"
        case speedRatio = "speed_ratio"
    }
}

struct VoiceSettingsRequest: Codable {
    let speed: Double
    let pitch: Double
    let volume: Double
    let voiceType: String
}

struct BatchTextToSpeechRequest: Codable {
    let texts: [TextToSpeechRequest]
    let batchId: String
    let priority: String
}

// MARK: - TTS响应模型
struct TTSResponse: Codable {
    let success: Bool
    let data: TTSData?
    let error: String?
}

struct TTSData: Codable {
    let audio: String // Base64编码的音频数据
    let format: String
    let duration: Double
}
