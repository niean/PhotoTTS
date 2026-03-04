import Foundation
import UIKit
import os.log

// MARK: - 制作状态
/// 会话记录的制作状态
enum MakeStatus: String, Codable {
    /// 制作中（OCR+TTS处理中）
    case making
    /// 制作完成（可播放、可保存）
    case completed
}

// MARK: - 会话历史事件（存储在 history.json 中，随会话导入导出）
/// 单次制作或播放事件
struct SessionHistoryEvent: Codable {
    let timestamp: Date
    /// 发起者身份名称，来自 SettingsManager.identityName
    let identity: String
}

// MARK: - 会话历史（每个会话目录下的 history.json）
struct SessionHistory: Codable {
    var makeEvents: [SessionHistoryEvent]
    var playEvents: [SessionHistoryEvent]

    init(makeEvents: [SessionHistoryEvent] = [], playEvents: [SessionHistoryEvent] = []) {
        self.makeEvents = makeEvents
        self.playEvents = playEvents
    }
}

// MARK: - 会话记录数据模型
/// 会话记录数据模型，用于存储一次完整的OCR+TTS处理会话
/// 包含时间、图片、文字、语音、状态信息等
struct SessionRecord: Codable, Identifiable, Hashable {
    /// 唯一标识符
    let id: String
    /// 自定义名称
    var name: String
    /// 创建时间
    let createdAt: Date
    /// 更新时间
    var updatedAt: Date
    
    // MARK: - 内容数据
    /// 图片数据（Base64编码，用于JSON存储）
    let imageDataList: [String]
    /// OCR识别的文本内容
    let ocrText: String
    /// OCR文本分段（每张图片对应的文本）
    let ocrTextSegments: [String]
    /// 音频数据（Base64编码，用于JSON存储）
    let audioDataBase64: String
    /// 音频格式（如 mp3）
    let audioFormat: String
    /// 音频时长（秒）
    let audioDuration: TimeInterval
    
    // MARK: - 状态信息
    /// OCR处理耗时（秒）
    let ocrDuration: TimeInterval
    /// TTS处理耗时（秒）
    let ttsDuration: TimeInterval
    /// 有效图片数量
    let validImageCount: Int
    /// 总图片数量
    let totalImageCount: Int
    /// 文本总长度（字符数）
    let textLength: Int
    /// 音频文件大小（字节）
    let audioSize: Int
    
    // MARK: - 语音设置
    /// 语音设置（可选）
    let voiceSettings: VoiceSettings?
    
    // MARK: - 头像设置
    var avatarImageIndex: Int
    
    // MARK: - 存储信息
    var storageSize: Int64
    
    // MARK: - 制作状态
    /// 制作状态：nil 或 .completed 表示已完成，.making 表示制作中（向后兼容旧数据）
    let makeStatus: MakeStatus?
    
    // MARK: - 初始化
    init(
        id: String = UUID().uuidString,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        images: [UIImage],
        ocrText: String,
        ocrTextSegments: [String],
        audioData: Data,
        audioFormat: String,
        audioDuration: TimeInterval,
        ocrDuration: TimeInterval,
        ttsDuration: TimeInterval,
        validImageCount: Int,
        voiceSettings: VoiceSettings? = nil,
        avatarImageIndex: Int = 0,
        storageSize: Int64 = 0,
        makeStatus: MakeStatus? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        
        // 将图片转换为Base64编码
        self.imageDataList = images.compactMap { image in
            guard let imageData = image.jpegData(compressionQuality: 1.0) else { return nil }
            return imageData.base64EncodedString()
        }
        
        self.ocrText = ocrText
        self.ocrTextSegments = ocrTextSegments
        self.audioDataBase64 = audioData.base64EncodedString()
        self.audioFormat = audioFormat
        self.audioDuration = audioDuration
        
        self.ocrDuration = ocrDuration
        self.ttsDuration = ttsDuration
        self.validImageCount = validImageCount
        self.totalImageCount = images.count
        self.textLength = ocrText.count
        self.audioSize = audioData.count
        
        self.voiceSettings = voiceSettings
        self.avatarImageIndex = min(max(0, avatarImageIndex), images.count > 0 ? images.count - 1 : 0)
        self.storageSize = storageSize
        self.makeStatus = makeStatus
    }
    
    // MARK: - Hashable（用于 navigationDestination(item:) 等，仅以 id 区分）
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    static func == (lhs: SessionRecord, rhs: SessionRecord) -> Bool {
        lhs.id == rhs.id
    }
    
    /// 按成员复制
    internal init(id: String, name: String, createdAt: Date, updatedAt: Date, imageDataList: [String], ocrText: String, ocrTextSegments: [String], audioDataBase64: String, audioFormat: String, audioDuration: TimeInterval, ocrDuration: TimeInterval, ttsDuration: TimeInterval, validImageCount: Int, totalImageCount: Int, textLength: Int, audioSize: Int, voiceSettings: VoiceSettings?, avatarImageIndex: Int, storageSize: Int64, makeStatus: MakeStatus? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.imageDataList = imageDataList
        self.ocrText = ocrText
        self.ocrTextSegments = ocrTextSegments
        self.audioDataBase64 = audioDataBase64
        self.audioFormat = audioFormat
        self.audioDuration = audioDuration
        self.ocrDuration = ocrDuration
        self.ttsDuration = ttsDuration
        self.validImageCount = validImageCount
        self.totalImageCount = totalImageCount
        self.textLength = textLength
        self.audioSize = audioSize
        self.voiceSettings = voiceSettings
        self.avatarImageIndex = avatarImageIndex
        self.storageSize = storageSize
        self.makeStatus = makeStatus
    }
    
    // MARK: - Codable 自定义编码
    
    /// 自定义编码，不将图片数据写入JSON（图片已单独保存为文件）
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode([String](), forKey: .imageDataList)
        try container.encode(ocrText, forKey: .ocrText)
        try container.encode(ocrTextSegments, forKey: .ocrTextSegments)
        try container.encode(String(), forKey: .audioDataBase64)
        try container.encode(audioFormat, forKey: .audioFormat)
        try container.encode(audioDuration, forKey: .audioDuration)
        try container.encode(ocrDuration, forKey: .ocrDuration)
        try container.encode(ttsDuration, forKey: .ttsDuration)
        try container.encode(validImageCount, forKey: .validImageCount)
        try container.encode(totalImageCount, forKey: .totalImageCount)
        try container.encode(textLength, forKey: .textLength)
        try container.encode(audioSize, forKey: .audioSize)
        try container.encodeIfPresent(voiceSettings, forKey: .voiceSettings)
        try container.encode(avatarImageIndex, forKey: .avatarImageIndex)
        try container.encode(storageSize, forKey: .storageSize)
        try container.encodeIfPresent(makeStatus, forKey: .makeStatus)
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case updatedAt
        case imageDataList
        case ocrText
        case ocrTextSegments
        case audioDataBase64
        case audioFormat
        case audioDuration
        case ocrDuration
        case ttsDuration
        case validImageCount
        case totalImageCount
        case textLength
        case audioSize
        case voiceSettings
        case avatarImageIndex
        case storageSize
        case makeStatus
    }
    
    // 自定义解码
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        imageDataList = try container.decode([String].self, forKey: .imageDataList)
        ocrText = try container.decode(String.self, forKey: .ocrText)
        ocrTextSegments = try container.decode([String].self, forKey: .ocrTextSegments)
        audioDataBase64 = try container.decodeIfPresent(String.self, forKey: .audioDataBase64) ?? ""
        audioFormat = try container.decode(String.self, forKey: .audioFormat)
        audioDuration = try container.decode(TimeInterval.self, forKey: .audioDuration)
        ocrDuration = try container.decode(TimeInterval.self, forKey: .ocrDuration)
        ttsDuration = try container.decode(TimeInterval.self, forKey: .ttsDuration)
        validImageCount = try container.decode(Int.self, forKey: .validImageCount)
        totalImageCount = try container.decode(Int.self, forKey: .totalImageCount)
        textLength = try container.decode(Int.self, forKey: .textLength)
        audioSize = try container.decode(Int.self, forKey: .audioSize)
        voiceSettings = try container.decodeIfPresent(VoiceSettings.self, forKey: .voiceSettings)
        avatarImageIndex = try container.decodeIfPresent(Int.self, forKey: .avatarImageIndex) ?? 0
        storageSize = try container.decodeIfPresent(Int64.self, forKey: .storageSize) ?? 0
        makeStatus = try container.decodeIfPresent(MakeStatus.self, forKey: .makeStatus)
    }
    
    /// 返回带新 storageSize 的副本（用于保存后写回 record.json）
    func withStorageSize(_ size: Int64) -> SessionRecord {
        SessionRecord(id: id, name: name, createdAt: createdAt, updatedAt: updatedAt, imageDataList: imageDataList, ocrText: ocrText, ocrTextSegments: ocrTextSegments, audioDataBase64: audioDataBase64, audioFormat: audioFormat, audioDuration: audioDuration, ocrDuration: ocrDuration, ttsDuration: ttsDuration, validImageCount: validImageCount, totalImageCount: totalImageCount, textLength: textLength, audioSize: audioSize, voiceSettings: voiceSettings, avatarImageIndex: avatarImageIndex, storageSize: size, makeStatus: makeStatus)
    }
    
    // MARK: - 辅助方法
    
    private static let logger = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "SessionRecord")

    /// 从Base64字符串恢复图片数组
    /// 注意：此方法主要用于兼容旧数据，新数据应从文件系统加载
    func getImages() -> [UIImage] {
        let memorySizeMB = imageDataList.reduce(0, { $0 + $1.count }) / 1024 / 1024
        Self.logger.warning("getImages 被调用，imageDataList 数量: \(self.imageDataList.count) 张, 约 \(memorySizeMB) MB")
        return imageDataList.compactMap { base64String in
            guard let imageData = Data(base64Encoded: base64String),
                  let image = UIImage(data: imageData) else {
                return nil
            }
            return image
        }
    }
    
    /// 获取音频数据
    func getAudioData() -> Data? {
        guard !audioDataBase64.isEmpty, let data = Data(base64Encoded: audioDataBase64) else {
            return nil
        }
        return data
    }
    
    /// 获取总处理耗时
    var totalDuration: TimeInterval {
        return ocrDuration + ttsDuration
    }
    
    /// 格式化显示时间
    var formattedCreatedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: createdAt)
    }
    
    /// 格式化显示日期（仅日期）
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: createdAt)
    }
    
    /// 格式化显示时间（仅时间）
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: createdAt)
    }
}

// MARK: - 会话记录元数据（用于列表展示，不包含完整数据）
struct SessionRecordMetadata: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    let createdAt: Date
    var updatedAt: Date
    let totalImageCount: Int
    let validImageCount: Int  // 有效图片数量（文字内容不为空的图片张数）
    let textLength: Int
    let audioDuration: TimeInterval
    let avatarImageIndex: Int
    let storageSize: Int64
    /// 制作状态：nil 或 .completed 表示已完成，.making 表示制作中（向后兼容旧数据）
    let makeStatus: MakeStatus?
    
    /// 是否正在制作中
    var isMaking: Bool { makeStatus == .making }
    
    init(from record: SessionRecord) {
        self.id = record.id
        self.name = record.name
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.totalImageCount = record.totalImageCount
        self.validImageCount = record.validImageCount
        self.textLength = record.textLength
        self.audioDuration = record.audioDuration
        self.avatarImageIndex = record.avatarImageIndex
        self.storageSize = record.storageSize
        self.makeStatus = record.makeStatus
    }
    
    init(id: String, name: String, createdAt: Date, updatedAt: Date, totalImageCount: Int, validImageCount: Int, textLength: Int, audioDuration: TimeInterval, avatarImageIndex: Int, storageSize: Int64, makeStatus: MakeStatus? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.totalImageCount = totalImageCount
        self.validImageCount = validImageCount
        self.textLength = textLength
        self.audioDuration = audioDuration
        self.avatarImageIndex = avatarImageIndex
        self.storageSize = storageSize
        self.makeStatus = makeStatus
    }
    
    /// 返回带新 storageSize 的元数据副本（用于保存后写回 metadata.json）
    func withStorageSize(_ size: Int64) -> SessionRecordMetadata {
        SessionRecordMetadata(id: id, name: name, createdAt: createdAt, updatedAt: updatedAt, totalImageCount: totalImageCount, validImageCount: validImageCount, textLength: textLength, audioDuration: audioDuration, avatarImageIndex: avatarImageIndex, storageSize: size, makeStatus: makeStatus)
    }
    
    /// 返回带新 makeStatus 的元数据副本
    func withMakeStatus(_ status: MakeStatus?) -> SessionRecordMetadata {
        SessionRecordMetadata(id: id, name: name, createdAt: createdAt, updatedAt: updatedAt, totalImageCount: totalImageCount, validImageCount: validImageCount, textLength: textLength, audioDuration: audioDuration, avatarImageIndex: avatarImageIndex, storageSize: storageSize, makeStatus: status)
    }
    
    // 为了兼容旧数据，提供自定义解码
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        totalImageCount = try container.decode(Int.self, forKey: .totalImageCount)
        validImageCount = try container.decodeIfPresent(Int.self, forKey: .validImageCount) ?? totalImageCount
        textLength = try container.decode(Int.self, forKey: .textLength)
        audioDuration = try container.decode(TimeInterval.self, forKey: .audioDuration)
        avatarImageIndex = try container.decodeIfPresent(Int.self, forKey: .avatarImageIndex) ?? 0
        storageSize = try container.decodeIfPresent(Int64.self, forKey: .storageSize) ?? 0
        makeStatus = try container.decodeIfPresent(MakeStatus.self, forKey: .makeStatus)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(totalImageCount, forKey: .totalImageCount)
        try container.encode(validImageCount, forKey: .validImageCount)
        try container.encode(textLength, forKey: .textLength)
        try container.encode(audioDuration, forKey: .audioDuration)
        try container.encode(avatarImageIndex, forKey: .avatarImageIndex)
        try container.encode(storageSize, forKey: .storageSize)
        try container.encodeIfPresent(makeStatus, forKey: .makeStatus)
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case updatedAt
        case totalImageCount
        case validImageCount
        case textLength
        case audioDuration
        case avatarImageIndex
        case storageSize
        case makeStatus
    }
    
    // Hashable 实现
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
    }
    
    static func == (lhs: SessionRecordMetadata, rhs: SessionRecordMetadata) -> Bool {
        return lhs.id == rhs.id && lhs.name == rhs.name && lhs.avatarImageIndex == rhs.avatarImageIndex
    }
}

