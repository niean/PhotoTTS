import Foundation
import SwiftUI

// MARK: - 应用常量
struct Constants {
    
    // MARK: - 应用信息
    static let appName = "Photo TTS"
    static let appVersion = "1.0.0"
    static let appBuild = "1"
    
    // MARK: - 网络配置
    static let defaultTimeout: TimeInterval = 30
    static let maxRetryCount = 3
    
    // MARK: - 文件配置
    static let maxImageSize: Int64 = 10 * 1024 * 1024 // 10MB
    static let supportedImageFormats = ["jpg", "jpeg", "png", "heic"]
    static let supportedAudioFormats = ["mp3", "wav", "aac"]
    
    // MARK: - 缓存配置
    static let maxCacheSize: Int64 = 100 * 1024 * 1024 // 100MB
    static let cacheExpirationDays = 7
    
    // MARK: - 用户界面配置
    static let cornerRadius: CGFloat = 12
    static let shadowRadius: CGFloat = 4
    static let animationDuration: Double = 0.3
    
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
    static let cameraPermissionMessage = "需要相机权限来拍摄照片"
    static let photoLibraryPermissionMessage = "需要相册权限来选择照片"
    static let microphonePermissionMessage = "需要麦克风权限来录制音频"
}

// MARK: - 颜色扩展
extension Color {
    static let primaryBlue = Color.blue
    static let secondaryGray = Color.gray
    static let background = Color.white
    static let secondaryBackground = Color.gray.opacity(0.1)
    static let label = Color.black
    static let secondaryLabel = Color.gray
}

// MARK: - 字体扩展
extension Font {
    static let titleLarge = Font.largeTitle
    static let titleMedium = Font.title
    static let titleSmall = Font.title2
    static let headline = Font.headline
    static let bodyLarge = Font.body
    static let bodyMedium = Font.body
    static let bodySmall = Font.caption
    static let caption = Font.caption2
}

// MARK: - 向后兼容性别名
typealias AppConstants = Constants

// MARK: - 扩展Constants
extension Constants {

    // MARK: - 布局常量
    struct Layout {
        static let defaultMargin: CGFloat = 10
        static let screenPadding: CGFloat = 20
        static let itemSpacing: CGFloat = 16
        static let sectionSpacing: CGFloat = 24
        static let buttonHeight: CGFloat = 44
        static let iconSize: CGFloat = 24
        static let avatarSize: CGFloat = 40
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
        static let maxMemoryCost: Int64 = 50 * 1024 * 1024 // 50MB
        static let defaultAutoCleanupEnabled = true
    }
    
    // MARK: - 相机配置扩展
    struct Camera {
        static let maxPhotoCount = 10
        static let maxPhotoSize: Int64 = 10 * 1024 * 1024 // 10MB
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
    
    // MARK: - 时间配置扩展
    struct Time {
        static let defaultDailyLimit: TimeInterval = 3600 // 1小时
        static let maxDailyUsage: TimeInterval = 7200 // 2小时
        static let secondsPerHour: TimeInterval = 3600
        static let minutesPerHour: TimeInterval = 60
    }
    
    // MARK: - 语言配置扩展
    struct Language {
        static let defaultLanguages = ["zh-CN", "en-US", "ja-JP"]
        static let defaultCurrent = "zh-CN"
    }
    
    // MARK: - API配置扩展
    struct API {
        static let maxBatchSize = 5
        static let minKeyLength = 32
        static let keyPrefix = "sk-"
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
    
    // MARK: - UserDefaults键值
    struct UserDefaultsKeys {
        static let ttsAppId = "tts_app_id"
        static let ttsCluster = "tts_cluster"
        static let ttsUid = "tts_uid"
        static let voiceSettings = "voice_settings"
        static let supportedLanguages = "supported_languages"
        static let currentLanguage = "current_language"
        // 家长控制功能已移除
        static let isFirstLaunch = "is_first_launch"
        static let appLaunchCount = "app_launch_count"
        static let lastLaunchDate = "last_launch_date"
        static let maxCacheSize = "max_cache_size"
        static let autoCleanupEnabled = "auto_cleanup_enabled"
    }
}
