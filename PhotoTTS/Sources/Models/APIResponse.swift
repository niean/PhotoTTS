import Foundation

// MARK: - TTS 音频段模型
struct TTSAudioSegment: Codable, Identifiable, Equatable {
    let id: String
    let sequenceNumber: Int
    let text: String
    let format: String
    let duration: TimeInterval
    let imageStartIndex: Int
    let imageEndIndex: Int
    let textStartOffset: Int
    let textEndOffset: Int
    let audioData: Data?

    enum CodingKeys: String, CodingKey {
        case id
        case sequenceNumber = "sequence_number"
        case text
        case format
        case duration
        case imageStartIndex = "image_start_index"
        case imageEndIndex = "image_end_index"
        case textStartOffset = "text_start_offset"
        case textEndOffset = "text_end_offset"
        case audioDataBase64 = "audio_data_base64"
    }

    init(
        id: String = UUID().uuidString,
        sequenceNumber: Int = 1,
        text: String,
        format: String,
        duration: TimeInterval,
        imageStartIndex: Int,
        imageEndIndex: Int,
        textStartOffset: Int,
        textEndOffset: Int,
        audioData: Data?
    ) {
        self.id = id
        self.sequenceNumber = sequenceNumber
        self.text = text
        self.format = format
        self.duration = duration
        self.imageStartIndex = imageStartIndex
        self.imageEndIndex = imageEndIndex
        self.textStartOffset = textStartOffset
        self.textEndOffset = textEndOffset
        self.audioData = audioData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sequenceNumber = try container.decodeIfPresent(Int.self, forKey: .sequenceNumber) ?? 1
        text = try container.decode(String.self, forKey: .text)
        format = try container.decode(String.self, forKey: .format)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        imageStartIndex = try container.decode(Int.self, forKey: .imageStartIndex)
        imageEndIndex = try container.decode(Int.self, forKey: .imageEndIndex)
        textStartOffset = try container.decode(Int.self, forKey: .textStartOffset)
        textEndOffset = try container.decode(Int.self, forKey: .textEndOffset)
        if let base64 = try container.decodeIfPresent(String.self, forKey: .audioDataBase64),
           !base64.isEmpty {
            audioData = Data(base64Encoded: base64)
        } else {
            audioData = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sequenceNumber, forKey: .sequenceNumber)
        try container.encode(text, forKey: .text)
        try container.encode(format, forKey: .format)
        try container.encode(duration, forKey: .duration)
        try container.encode(imageStartIndex, forKey: .imageStartIndex)
        try container.encode(imageEndIndex, forKey: .imageEndIndex)
        try container.encode(textStartOffset, forKey: .textStartOffset)
        try container.encode(textEndOffset, forKey: .textEndOffset)
        try container.encode("", forKey: .audioDataBase64)
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
    let audioSegments: [TTSAudioSegment]? // 多段音频信息
    let storyName: String? // 绘本名称（LLM生成）
    let storyHighlights: String? // 绘本要点（LLM生成）
    let hasVirtualPage: Bool? // 是否存在虚拟页
    
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
        case audioSegments = "audio_segments"
        case storyName = "story_name"
        case storyHighlights = "story_highlights"
        case hasVirtualPage = "has_virtual_page"
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
        audioSegments = try container.decodeIfPresent([TTSAudioSegment].self, forKey: .audioSegments)
        storyName = try container.decodeIfPresent(String.self, forKey: .storyName)
        storyHighlights = try container.decodeIfPresent(String.self, forKey: .storyHighlights)
        hasVirtualPage = try container.decodeIfPresent(Bool.self, forKey: .hasVirtualPage)
        audioData = nil // 从JSON解码时，audioData通常为nil
    }
    
    // 自定义初始化器（用于测试）
    init(id: String, audioURL: String, text: String, language: String, duration: TimeInterval, format: String, quality: String, timestamp: Date, voiceSettings: VoiceSettings? = nil, audioData: Data? = nil, validImageCount: Int? = nil, recognizedTexts: [String]? = nil, audioSegments: [TTSAudioSegment]? = nil, storyName: String? = nil, storyHighlights: String? = nil, hasVirtualPage: Bool? = nil) {
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
        self.audioSegments = audioSegments
        self.storyName = storyName
        self.storyHighlights = storyHighlights
        self.hasVirtualPage = hasVirtualPage
    }
    
    // TTS专用初始化器（用于从TTS响应创建）
    init(audioData: Data, format: String, duration: Double, validImageCount: Int? = nil, recognizedTexts: [String]? = nil, audioSegments: [TTSAudioSegment]? = nil, storyName: String? = nil, storyHighlights: String? = nil, hasVirtualPage: Bool? = nil) {
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
        self.audioSegments = audioSegments
        self.storyName = storyName
        self.storyHighlights = storyHighlights
        self.hasVirtualPage = hasVirtualPage
    }
}
