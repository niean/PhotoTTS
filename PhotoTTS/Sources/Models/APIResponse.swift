import Foundation

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
