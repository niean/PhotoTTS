import Foundation
import SwiftUI

// MARK: - 应用常量
struct Constants {
    
    // MARK: - 应用信息
    static let appVersion = "1.0.0"
    
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
        static let contentHorizontalPadding: CGFloat = 20
    }

    /// 播放/查看时全屏图按需加载的最大边长（pt），超过则等比缩小以控制内存
    struct ImageDisplay {
        static let playbackFullScreenMaxDimension: CGFloat = 1024
        /// 图片模糊背景缩放比例
        static let blurBackgroundScaleEffect: CGFloat = 1.15
        /// 图片模糊背景模糊半径
        static let blurBackgroundRadius: CGFloat = 10
        /// 图片模糊背景透明度
        static let blurBackgroundOpacity: Double = 0.5
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
        /// 缩略图长按最小持续时间（秒）
        static let longPressDuration: TimeInterval = 0.5
        /// 全屏图左右滑动切换的最小距离（pt）
        static let swipeMinDistance: CGFloat = 40
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
        static let ttsCluster = "volcano_tts"
        static let ttsVoiceType = "zh_female_tianmeixiaoyuan_moon_bigtts"
        static let ttsEncoding = "mp3"
        static let ocrModelName = "doubao-seed-1-6-flash-250715"
        static let aliqwenTTSBaseURL = "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"
        static let aliqwenTTSModel = "qwen3-tts-flash"
        static let aliqwenTTSVoice = "Cherry"
        static let aliqwenTTSLanguageType = "Chinese"
        static let huoshanBitrate = 64
        static let huoshanRate = 16000
        static let huoshanSpeedRatio = 0.9
        static let huoshanTimeout: TimeInterval = 60.0
        static let aliqwenTimeout: TimeInterval = 120.0
    }
    
    // MARK: - 错误信息
    struct ErrorInfo {
        static let domain = "PhotoTTS"
        static let defaultCode = -1
    }
    
    // MARK: - API端点配置
    struct APIEndpoints {
        static let testConnection = "/v1/test/connection"
    }
    
    // MARK: - UI常量
    struct UI {
        /// 状态栏覆盖视图的 tag 标识
        static let statusBarViewTag = 999
        /// 搜索框占位文字
        static let searchPlaceholder = "搜索"
        /// 搜索无结果提示
        static let searchNoResult = "未找到匹配的记录"
        /// 搜索栏行的 ScrollView 锚点 id
        static let searchBarRowId = "searchBarRow"
    }
    
    // MARK: - 搜索栏布局
    struct SearchBar {
        /// 搜索栏内部水平内边距
        static let innerHorizontalPadding: CGFloat = 10
        /// 搜索栏内部垂直内边距
        static let innerVerticalPadding: CGFloat = 8
        /// 搜索栏圆角半径
        static let cornerRadius: CGFloat = 10
        /// 搜索栏外部水平边距
        static let outerHorizontalPadding: CGFloat = 16
        /// 搜索栏顶部边距
        static let topPadding: CGFloat = 8
        /// 搜索栏底部边距
        static let bottomPadding: CGFloat = 4
        /// 搜索栏行最小高度（在 List 中作为独立行时使用）
        static let rowMinHeight: CGFloat = 44
    }
    
    // MARK: - 分页配置
    struct Pagination {
        /// 记录列表每页条数
        static let pageSize = 20
    }
    
    // MARK: - 调试日志配置
    struct DebugLog {
        /// 单个日志文件最大字节数
        static let maxLogFileSize: Int64 = 10 * 1024 * 1024 // 10MB
        /// 最多保留的日志文件数
        static let maxLogFiles = 5
    }
    
    // MARK: - 播放配置
    struct Playback {
        /// 护眼模式背景色
        static let eyeProtectionBackgroundColor = Color(red: 0.85, green: 0.95, blue: 0.88)
        /// 播放页操作栏无操作自动隐藏间隔（秒）
        static let overlayAutoHideInterval: TimeInterval = 5
        /// 进度条轨道高度（pt）
        static let progressBarHeight: CGFloat = 3
        /// 进度条滑块直径（pt）
        static let progressBarThumbSize: CGFloat = 14
        /// 进度条分割点直径（pt）
        static let segmentDotSize: CGFloat = 6
        /// 进度条已播放填充色
        static let progressBarFillColor = Color(red: 0.4, green: 0.85, blue: 0.55)
    }
    
    // MARK: - 钥匙串键值
    struct KeychainKeys {
        static let doubaoAPIKey = "doubao_api_key"
        static let openaiOCRAPIKey = "openai_ocr_api_key"
        static let ttsAccessKey = "tts_access_key"
        static let aliqwenTTSSecretKey = "aliqwen_tts_secret_key"
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
    
    // MARK: - 外部链接
    struct Links {
        static let privacyPolicy = "https://phototts.niean.name/privacy-policy.html"
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
    
    // MARK: - 内置默认会话
    struct DefaultSession {
        /// 内置默认会话的 ID
        static let id = "A206CF0C-5461-4BDC-90A1-045C4ACC809A"
        /// Bundle 中资源文件的名称前缀
        static let bundleFilePrefix = "default_session_"
    }
}
