import Foundation
import UIKit
import os.log

// MARK: - 播放方向（翻页动画样式）
/// 播放时的翻页动画方向
enum AnimationStyle: String, Codable {
    /// 从右到左（横向翻页，默认）
    case rightToLeft
    /// 从上到下（纵向翻页）
    case topToBottom
}

// MARK: - 制作状态
/// 会话记录的制作状态
enum MakeStatus: String, Codable {
    /// 制作中（OCR+TTS处理中）
    case making
    /// 制作完成（可播放、可保存）
    case completed
    /// 制作未完成（失败或中断，可查看/编辑/重新制作，不可播放）
    case incomplete
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

    private enum CodingKeys: String, CodingKey {
        case makeEvents
        case playEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        makeEvents = try container.decodeIfPresent([SessionHistoryEvent].self, forKey: .makeEvents) ?? []
        playEvents = try container.decodeIfPresent([SessionHistoryEvent].self, forKey: .playEvents) ?? []
    }
}

// MARK: - 播放统计
struct PlayStatInfo {
    let lastPlayedAt: Date
    let playCount: Int
}

// MARK: - 阅读状态筛选
enum SessionReadStatusFilter: String, CaseIterable {
    case read
    case unread

    var label: String {
        switch self {
        case .read:
            return "已读"
        case .unread:
            return "未读"
        }
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
    /// 音频分段（多段 TTS 记录）；旧记录为空数组
    let audioSegments: [TTSAudioSegment]
    /// 音频时长（秒）
    let audioDuration: TimeInterval
    
    // MARK: - 状态信息
    /// OCR处理耗时（秒）
    let ocrDuration: TimeInterval
    /// LLM处理耗时（秒）
    let llmDuration: TimeInterval
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

    // MARK: - LLM分析结果
    /// 绘本要点原文（LLM生成的要点），nil表示未生成或生成失败
    let storyHighlights: String?
    /// 是否存在虚拟页（由LLM要点生成）
    let hasVirtualPage: Bool

    // MARK: - 播放方向
    /// 播放方向（翻页动画样式），默认横向翻页（从右到左）
    let animationStyle: AnimationStyle

    // MARK: - 封面图片
    /// 封面图片路径（相对于 session 目录，如 cover.jpg），nil 时降级使用第1张图片
    var coverImagePath: String?

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
        audioSegments: [TTSAudioSegment] = [],
        audioDuration: TimeInterval,
        ocrDuration: TimeInterval,
        llmDuration: TimeInterval = 0,
        ttsDuration: TimeInterval,
        validImageCount: Int,
        voiceSettings: VoiceSettings? = nil,
        avatarImageIndex: Int = 0,
        storageSize: Int64 = 0,
        makeStatus: MakeStatus? = nil,
        storyHighlights: String? = nil,
        hasVirtualPage: Bool = false,
        animationStyle: AnimationStyle = .rightToLeft,
        coverImagePath: String? = nil
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
        self.audioSegments = audioSegments
        if audioSegments.isEmpty {
            self.audioDuration = audioDuration
        } else {
            let totalSegmentDuration = audioSegments.reduce(0) { $0 + $1.duration }
            self.audioDuration = totalSegmentDuration > 0 ? totalSegmentDuration : audioDuration
        }

        self.ocrDuration = ocrDuration
        self.llmDuration = llmDuration
        self.ttsDuration = ttsDuration
        self.validImageCount = validImageCount
        self.totalImageCount = images.count
        self.textLength = ocrText.count
        if audioSegments.isEmpty {
            self.audioSize = audioData.count
        } else {
            self.audioSize = audioSegments.compactMap(\.audioData).reduce(0) { $0 + $1.count }
        }
        
        self.voiceSettings = voiceSettings
        self.avatarImageIndex = min(max(0, avatarImageIndex), images.count > 0 ? images.count - 1 : 0)
        self.storageSize = storageSize
        self.makeStatus = makeStatus
        self.storyHighlights = storyHighlights
        self.hasVirtualPage = hasVirtualPage
        self.animationStyle = animationStyle
        self.coverImagePath = coverImagePath
    }

    // MARK: - Hashable（用于 navigationDestination(item:) 等，仅以 id 区分）
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    static func == (lhs: SessionRecord, rhs: SessionRecord) -> Bool {
        lhs.id == rhs.id
    }
    
    /// 按成员复制
    internal init(id: String, name: String, createdAt: Date, updatedAt: Date, imageDataList: [String], ocrText: String, ocrTextSegments: [String], audioDataBase64: String, audioFormat: String, audioSegments: [TTSAudioSegment] = [], audioDuration: TimeInterval, ocrDuration: TimeInterval, llmDuration: TimeInterval = 0, ttsDuration: TimeInterval, validImageCount: Int, totalImageCount: Int, textLength: Int, audioSize: Int, voiceSettings: VoiceSettings?, avatarImageIndex: Int, storageSize: Int64, makeStatus: MakeStatus? = nil, storyHighlights: String? = nil, hasVirtualPage: Bool = false, animationStyle: AnimationStyle = .rightToLeft, coverImagePath: String? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.imageDataList = imageDataList
        self.ocrText = ocrText
        self.ocrTextSegments = ocrTextSegments
        self.audioDataBase64 = audioDataBase64
        self.audioFormat = audioFormat
        self.audioSegments = audioSegments
        self.audioDuration = audioDuration
        self.ocrDuration = ocrDuration
        self.llmDuration = llmDuration
        self.ttsDuration = ttsDuration
        self.validImageCount = validImageCount
        self.totalImageCount = totalImageCount
        self.textLength = textLength
        self.audioSize = audioSize
        self.voiceSettings = voiceSettings
        self.avatarImageIndex = avatarImageIndex
        self.storageSize = storageSize
        self.makeStatus = makeStatus
        self.storyHighlights = storyHighlights
        self.hasVirtualPage = hasVirtualPage
        self.animationStyle = animationStyle
        self.coverImagePath = coverImagePath
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
        try container.encode(audioSegments, forKey: .audioSegments)
        try container.encode(audioDuration, forKey: .audioDuration)
        try container.encode(ocrDuration, forKey: .ocrDuration)
        try container.encode(llmDuration, forKey: .llmDuration)
        try container.encode(ttsDuration, forKey: .ttsDuration)
        try container.encode(validImageCount, forKey: .validImageCount)
        try container.encode(totalImageCount, forKey: .totalImageCount)
        try container.encode(textLength, forKey: .textLength)
        try container.encode(audioSize, forKey: .audioSize)
        try container.encodeIfPresent(voiceSettings, forKey: .voiceSettings)
        try container.encode(avatarImageIndex, forKey: .avatarImageIndex)
        try container.encode(storageSize, forKey: .storageSize)
        try container.encodeIfPresent(makeStatus, forKey: .makeStatus)
        try container.encodeIfPresent(storyHighlights, forKey: .storyHighlights)
        try container.encode(hasVirtualPage, forKey: .hasVirtualPage)
        try container.encode(animationStyle, forKey: .animationStyle)
        try container.encodeIfPresent(coverImagePath, forKey: .coverImagePath)
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
        case audioSegments
        case audioDuration
        case ocrDuration
        case llmDuration
        case ttsDuration
        case validImageCount
        case totalImageCount
        case textLength
        case audioSize
        case voiceSettings
        case avatarImageIndex
        case storageSize
        case makeStatus
        case storyHighlights
        case hasVirtualPage
        case animationStyle
        case coverImagePath
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
        audioSegments = try container.decodeIfPresent([TTSAudioSegment].self, forKey: .audioSegments) ?? []
        audioDuration = try container.decode(TimeInterval.self, forKey: .audioDuration)
        ocrDuration = try container.decode(TimeInterval.self, forKey: .ocrDuration)
        llmDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .llmDuration) ?? 0
        ttsDuration = try container.decode(TimeInterval.self, forKey: .ttsDuration)
        validImageCount = try container.decode(Int.self, forKey: .validImageCount)
        totalImageCount = try container.decode(Int.self, forKey: .totalImageCount)
        textLength = try container.decode(Int.self, forKey: .textLength)
        audioSize = try container.decode(Int.self, forKey: .audioSize)
        voiceSettings = try container.decodeIfPresent(VoiceSettings.self, forKey: .voiceSettings)
        let rawAvatarIndex = try container.decodeIfPresent(Int.self, forKey: .avatarImageIndex) ?? 0
        avatarImageIndex = min(max(0, rawAvatarIndex), max(0, totalImageCount - 1))
        storageSize = try container.decodeIfPresent(Int64.self, forKey: .storageSize) ?? 0
        makeStatus = try container.decodeIfPresent(MakeStatus.self, forKey: .makeStatus)
        storyHighlights = try container.decodeIfPresent(String.self, forKey: .storyHighlights)
        hasVirtualPage = try container.decodeIfPresent(Bool.self, forKey: .hasVirtualPage) ?? false
        animationStyle = try container.decodeIfPresent(AnimationStyle.self, forKey: .animationStyle) ?? .rightToLeft
        coverImagePath = try container.decodeIfPresent(String.self, forKey: .coverImagePath)
    }
    
    /// 返回带新 storageSize 的副本（用于保存后写回 record.json）
    func withStorageSize(_ size: Int64) -> SessionRecord {
        SessionRecord(id: id, name: name, createdAt: createdAt, updatedAt: updatedAt, imageDataList: imageDataList, ocrText: ocrText, ocrTextSegments: ocrTextSegments, audioDataBase64: audioDataBase64, audioFormat: audioFormat, audioSegments: audioSegments, audioDuration: audioDuration, ocrDuration: ocrDuration, llmDuration: llmDuration, ttsDuration: ttsDuration, validImageCount: validImageCount, totalImageCount: totalImageCount, textLength: textLength, audioSize: audioSize, voiceSettings: voiceSettings, avatarImageIndex: avatarImageIndex, storageSize: size, makeStatus: makeStatus, storyHighlights: storyHighlights, hasVirtualPage: hasVirtualPage, animationStyle: animationStyle, coverImagePath: coverImagePath)
    }

    /// 返回带新 coverImagePath 的副本（用于保存后写回 record.json）
    func withCoverImagePath(_ path: String?) -> SessionRecord {
        SessionRecord(id: id, name: name, createdAt: createdAt, updatedAt: Date(), imageDataList: imageDataList, ocrText: ocrText, ocrTextSegments: ocrTextSegments, audioDataBase64: audioDataBase64, audioFormat: audioFormat, audioSegments: audioSegments, audioDuration: audioDuration, ocrDuration: ocrDuration, llmDuration: llmDuration, ttsDuration: ttsDuration, validImageCount: validImageCount, totalImageCount: totalImageCount, textLength: textLength, audioSize: audioSize, voiceSettings: voiceSettings, avatarImageIndex: avatarImageIndex, storageSize: storageSize, makeStatus: makeStatus, storyHighlights: storyHighlights, hasVirtualPage: hasVirtualPage, animationStyle: animationStyle, coverImagePath: path)
    }

    /// 返回带新 makeStatus 的副本（用于重试时更新状态）
    func withMakeStatus(_ status: MakeStatus?) -> SessionRecord {
        SessionRecord(id: id, name: name, createdAt: createdAt, updatedAt: Date(), imageDataList: imageDataList, ocrText: ocrText, ocrTextSegments: ocrTextSegments, audioDataBase64: audioDataBase64, audioFormat: audioFormat, audioSegments: audioSegments, audioDuration: audioDuration, ocrDuration: ocrDuration, llmDuration: llmDuration, ttsDuration: ttsDuration, validImageCount: validImageCount, totalImageCount: totalImageCount, textLength: textLength, audioSize: audioSize, voiceSettings: voiceSettings, avatarImageIndex: avatarImageIndex, storageSize: storageSize, makeStatus: status, storyHighlights: storyHighlights, hasVirtualPage: hasVirtualPage, animationStyle: animationStyle, coverImagePath: coverImagePath)
    }
    
    // MARK: - 辅助方法
    
    private static let logger = os.Logger.sessionRecord

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

    /// 按需从Base64解码单张图片（用于播放时按需加载，避免全量解码）
    /// - Parameters:
    ///   - index: 图片索引
    ///   - maxDimension: 最大边长（点），超过则等比缩小；nil 表示不缩小
    /// - Returns: 图片，不存在或解码失败返回 nil
    func getImage(at index: Int, maxDimension: CGFloat? = Constants.ImageDisplay.playbackFullScreenMaxDimension) -> UIImage? {
        guard index >= 0, index < imageDataList.count else { return nil }
        guard let data = Data(base64Encoded: imageDataList[index]) else { return nil }
        // 使用 Image I/O 降采样
        let maxPixel: Int?
        if let maxDim = maxDimension, maxDim > 0 {
            maxPixel = Int(maxDim * max(1, UIScreen.main.scale))
        } else {
            maxPixel = nil
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data) // 降采样失败则返回原图
        }
        if let pixel = maxPixel {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixel
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return UIImage(cgImage: cgImage)
            }
        }
        // 无需降采样或降采样失败
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    /// 获取音频数据
    func getAudioData() -> Data? {
        guard !audioDataBase64.isEmpty, let data = Data(base64Encoded: audioDataBase64) else {
            return audioSegments.first?.audioData
        }
        return data
    }

    /// 获取多段音频数据；旧记录回退为单段数组
    func getAudioSegments() -> [TTSAudioSegment] {
        if !audioSegments.isEmpty {
            return audioSegments
        }
        guard let data = getAudioData() else { return [] }
        let endOffset = max(0, ocrText.count - 1)
        return [
            TTSAudioSegment(
                text: ocrText,
                format: audioFormat,
                duration: audioDuration,
                imageStartIndex: 0,
                imageEndIndex: max(0, ocrTextSegments.count - 1),
                textStartOffset: 0,
                textEndOffset: endOffset,
                audioData: data
            )
        ]
    }
    
    /// 获取总处理耗时
    var totalDuration: TimeInterval {
        return ocrDuration + llmDuration + ttsDuration
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

    /// 去掉名称中的日期前缀，仅保留标题部分。
    var nameWithoutDatePrefix: String {
        let prefixLen = Constants.sessionNameDatePrefixFormat.count
        guard name.count >= prefixLen else { return name }

        let prefixWithSpace = String(name.prefix(prefixLen))
        let prefixDateStr = prefixWithSpace.trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.dateFormat = "yy.MM.dd"
        formatter.locale = Locale(identifier: "zh_CN")

        guard formatter.date(from: prefixDateStr) != nil else { return name }

        let suffix = String(name.dropFirst(prefixLen))
        return suffix.isEmpty ? name : suffix
    }

    /// 用于再次制作时恢复的 OCR 分段，不包含 LLM 追加的虚拟要点页。
    var sourceOCRTextSegments: [String] {
        guard totalImageCount > 0 else { return ocrTextSegments }
        guard ocrTextSegments.count > totalImageCount else { return ocrTextSegments }
        return Array(ocrTextSegments.prefix(totalImageCount))
    }

    /// 用于再次制作时恢复的 OCR 原文，不包含 LLM 追加的虚拟要点页。
    var sourceOCRText: String {
        let segments = sourceOCRTextSegments
        guard !segments.isEmpty else { return ocrText }
        return segments.joined(separator: Constants.ocrTextSeparator)
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
    /// 播放方向（翻页动画样式），默认横向翻页（从右到左）
    let animationStyle: AnimationStyle

    /// 是否正在制作中
    var isMaking: Bool { makeStatus == .making }

    /// 是否制作未完成（失败/中断）
    var isIncomplete: Bool { makeStatus == .incomplete }
    
    /// 是否为内置默认会话
    var isDefault: Bool { id == Constants.DefaultSession.id }

    /// 从名称前缀解析的日期（格式 "YY.MM.DD "），解析失败时回退到 createdAt
    /// 用于连播队列等需要按"显示日期"分组的场景
    var namePrefixDate: Date {
        let prefixLen = Constants.sessionNameDatePrefixFormat.count
        guard name.count >= prefixLen else { return createdAt }
        // 日期部分为前缀去掉末尾空格
        let prefixDateStr = String(name.prefix(prefixLen)).trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.dateFormat = "yy.MM.dd"
        formatter.locale = Locale(identifier: "zh_CN")
        if let date = formatter.date(from: prefixDateStr) {
            return date
        }
        return createdAt
    }

    /// 从名称中提取系列名（日期前缀后、第一个 - 前的部分）
    /// 示例："26.03.16 小红帽-第一章" -> "小红帽"
    /// 无法提取时返回 "未分类"
    var seriesName: String {
        let prefixLen = Constants.sessionNameDatePrefixFormat.count
        guard name.count >= prefixLen else { return Constants.GroupDisplay.uncategorizedLabel }
        let afterPrefix = String(name.dropFirst(prefixLen))
        guard let hyphenIndex = afterPrefix.firstIndex(of: "-") else { return Constants.GroupDisplay.uncategorizedLabel }
        let series = String(afterPrefix[afterPrefix.startIndex..<hyphenIndex])
            .trimmingCharacters(in: .whitespaces)
        return series.isEmpty ? Constants.GroupDisplay.uncategorizedLabel : series
    }

    /// 从 namePrefixDate 格式化的月份键（如 "2026年3月"），用于按月份分组
    var monthKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = Constants.GroupDisplay.monthKeyFormat
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: namePrefixDate)
    }

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
        self.animationStyle = record.animationStyle
    }
    
    init(id: String, name: String, createdAt: Date, updatedAt: Date, totalImageCount: Int, validImageCount: Int, textLength: Int, audioDuration: TimeInterval, avatarImageIndex: Int, storageSize: Int64, makeStatus: MakeStatus? = nil, animationStyle: AnimationStyle = .rightToLeft) {
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
        self.animationStyle = animationStyle
    }
    
    /// 返回带新 storageSize 的元数据副本（用于保存后写回 metadata.json）
    func withStorageSize(_ size: Int64) -> SessionRecordMetadata {
        SessionRecordMetadata(id: id, name: name, createdAt: createdAt, updatedAt: updatedAt, totalImageCount: totalImageCount, validImageCount: validImageCount, textLength: textLength, audioDuration: audioDuration, avatarImageIndex: avatarImageIndex, storageSize: size, makeStatus: makeStatus, animationStyle: animationStyle)
    }

    /// 返回带新 makeStatus 的元数据副本
    func withMakeStatus(_ status: MakeStatus?) -> SessionRecordMetadata {
        SessionRecordMetadata(id: id, name: name, createdAt: createdAt, updatedAt: updatedAt, totalImageCount: totalImageCount, validImageCount: validImageCount, textLength: textLength, audioDuration: audioDuration, avatarImageIndex: avatarImageIndex, storageSize: storageSize, makeStatus: status, animationStyle: animationStyle)
    }

    /// 返回带新 animationStyle 的元数据副本
    func withAnimationStyle(_ style: AnimationStyle) -> SessionRecordMetadata {
        SessionRecordMetadata(id: id, name: name, createdAt: createdAt, updatedAt: updatedAt, totalImageCount: totalImageCount, validImageCount: validImageCount, textLength: textLength, audioDuration: audioDuration, avatarImageIndex: avatarImageIndex, storageSize: storageSize, makeStatus: makeStatus, animationStyle: style)
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
        animationStyle = try container.decodeIfPresent(AnimationStyle.self, forKey: .animationStyle) ?? .rightToLeft
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
        try container.encode(animationStyle, forKey: .animationStyle)
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
        case animationStyle
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
