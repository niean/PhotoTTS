import Foundation
import SwiftUI

// MARK: - 应用常量
struct Constants {
    
    // MARK: - 应用信息
    static let appName = "Photo TTS"
    static let appVersion = "1.0.0"
    
    // MARK: - 文件配置
    static let maxImageSize: Int64 = 10 * 1024 * 1024 // 10MB
    
    // MARK: - 用户界面配置
    static let cornerRadius: CGFloat = 12
    static let shadowRadius: CGFloat = 4
    
    // MARK: - OCR配置
    static let defaultOCRConcurrentCount = 8
    
    // MARK: - 系统保留字符
    /// OCR识别结果中的系统保留字符，表示未识别到有效内容
    /// 当OCR返回此字符串时，表示该图片没有识别到任何文字内容
    static let ocrEmptyResultIndicator = "空字符串"
    
    // MARK: - 文本分隔符
    /// 多张图片OCR文本拼接时的分隔符
    /// 用于在拼接多张图片的识别结果时，在每张图片的文本之间插入分隔符
    static let ocrTextSeparator = "\n\n"
    
    // MARK: - 权限配置
    static let cameraPermissionMessage = "需要相机权限才能拍照"
    static let cameraPermissionDeniedMessage = "请在设置中允许访问相机"
    static let cameraPermissionUnknownMessage = "相机权限未知状态"
}

// MARK: - 颜色扩展
extension Color {
    static let label = Color.black
}

// MARK: - 向后兼容性别名
typealias AppConstants = Constants

// MARK: - 扩展Constants
extension Constants {

    // MARK: - 布局常量
    struct Layout {
        static let defaultMargin: CGFloat = 10
        static let topNavigationBarPadding: CGFloat = 55
    }

    // MARK: - 会话详情
    struct SessionDetail {
        static let contentWidthMax: CGFloat = 700
        static let contentHorizontalPadding: CGFloat = 20
    }

    /// 播放/查看时全屏图按需加载的最大边长（pt），超过则等比缩小以控制内存
    struct ImageDisplay {
        static let playbackFullScreenMaxDimension: CGFloat = 1024
        /// 记录头像最大边长
        static let recordAvatarMaxDimension: CGFloat = 96
        /// 记录单张图片最大边长
        static let saveImageMaxPixel: CGFloat = 2048
    }

    // MARK: - 手势识别
    struct Gesture {
        /// 手势识别区域宽度
        static let gestureThreshold: CGFloat = 30
        /// 左边缘滑返回：触摸起始 x 小于此值视为从左侧边缘开始（pt）
        static let leftEdgeStartZoneWidth: CGFloat = 30
        /// 左边缘滑返回：最小横向位移，超过此值触发返回（pt）
        static let swipeBackMinTranslation: CGFloat = 80
    }

    // MARK: - 网络配置扩展
    struct Network {
        static let baseURL = "https://api.phototts.com"
        static let requestTimeout: TimeInterval = 30
        static let resourceTimeout: TimeInterval = 60
        static let maxRetryCount = 3
        static let retryDelay: TimeInterval = 1.0
    }
    
    // MARK: - 缓存配置扩展
    struct Cache {
        static let maxCacheSize: Int64 = 100 * 1024 * 1024 // 100MB
        static let defaultAutoCleanupEnabled = true
    }
    
    // MARK: - 语音配置扩展
    struct VoiceRange {
        static let speedMin: Double = 0.5
        static let speedMax: Double = 2.0
        static let pitchMin: Double = -12.0
        static let pitchMax: Double = 12.0
        static let volumeMin: Double = 0.0
        static let volumeMax: Double = 1.0
    }
    
    // MARK: - 语言配置扩展
    struct Language {
        static let defaultLanguages = ["zh-CN", "en-US", "ja-JP"]
        static let defaultCurrent = "zh-CN"
    }
    
    // MARK: - API配置扩展
    struct API {
        static let minKeyLength = 32
        static let keyPrefix = "sk-"
    }
    
    // MARK: - 服务默认配置
    struct ServiceDefaults {
        static let ttsBaseURL = "https://openspeech.bytedance.com/api/v1/tts"
        static let ocrBaseURL = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
    }
    
    // MARK: - API端点配置
    struct APIEndpoints {
        static let ttsSynthesize = "/v1/tts/synthesize"
        static let test = "/v1/test"
        static let testConnection = "/v1/test/connection"
    }
    
    // MARK: - 钥匙串键值
    struct KeychainKeys {
        static let doubaoAPIKey = "doubao_api_key"
        static let ttsAccessKey = "tts_access_key"
    }
    
    // MARK: - 身份名称
    struct Identity {
        /// 身份名称最大字符数
        static let nameMaxLength = 20
    }

    // MARK: - UserDefaults键值
    struct UserDefaultsKeys {
        static let identityName = "identity_name"
        static let ttsAppId = "tts_app_id"
        static let ttsCluster = "tts_cluster"
        static let ttsUid = "tts_uid"
        static let voiceSettings = "voice_settings"
        static let supportedLanguages = "supported_languages"
        static let currentLanguage = "current_language"
        static let isFirstLaunch = "is_first_launch"
        static let appLaunchCount = "app_launch_count"
        static let lastLaunchDate = "last_launch_date"
        static let maxCacheSize = "max_cache_size"
        static let autoCleanupEnabled = "auto_cleanup_enabled"
        static let siriPendingSessionId = "siriPendingPlaySessionId"
    }
    
    // MARK: - 通知名
    struct NotificationNames {
        static let updatePhotoCount = NSNotification.Name("UpdatePhotoCount")
        static let configUpdated = NSNotification.Name("ConfigUpdated")
        /// 远程播放控制命令（MPRemoteCommandCenter -> PlayView），userInfo["action"]: "play"/"pause"/"toggle"
        static let remotePlaybackCommand = NSNotification.Name("RemotePlaybackCommand")
    }
    
    // MARK: - TTS限制
    static let defaultTTSMaxLength = 10240
    
    // MARK: - 批量处理限制
    static let maxBatchImageCount = 100
    
    // MARK: - 播放历史限制
    static let maxPlayHistoryRecords = 500
    
    // MARK: - 制作历史限制
    static let maxMakeHistoryRecords = 500
    
    // MARK: - 相册选择器
    static let maxPhotoPickerSelectionCount = 50
    
    // MARK: - 默认会话名称
    static let defaultSessionName = "未命名会话"
    
    // MARK: - 后台制作
    /// 草稿会话默认名称后缀（前缀为 "YY.MM.DD "）
    static let draftSessionNameSuffix = "未命名"
}
