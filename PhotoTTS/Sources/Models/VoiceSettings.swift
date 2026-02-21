import Foundation

// MARK: - 语音设置数据模型
/// 语音设置数据模型，定义了TTS语音合成的各种参数
/// 支持语速、音调、音量和语音类型的调整
struct VoiceSettings: Codable, Equatable {
    /// 语速，范围0.5-2.0，1.0为正常速度
    var speed: Double
    /// 音调，范围0.5-2.0，1.0为正常音调
    var pitch: Double
    /// 音量，范围0.0-1.0，1.0为最大音量
    var volume: Double
    /// 语音类型，如"default"、"child"、"elderly"等
    var voiceType: String
    /// 音频编码格式，如"mp3"、"wav"、"aac"等
    var encoding: String
    
    static let `default` = VoiceSettings(
        speed: 1.0,
        pitch: 1.0,
        volume: 1.0,
        voiceType: "default",
        encoding: "mp3"
    )
}