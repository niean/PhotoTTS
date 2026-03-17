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

    // MARK: - 设备缩放
    struct DeviceScale {
        /// iPad 相对于 iPhone 的页面尺寸缩放比例
        static let iPadScale: CGFloat = 1.25

        /// 根据当前设备类型返回适配后的尺寸
        /// - Parameter iPhone: iPhone 上的基准尺寸（pt）
        /// - Returns: iPhone 返回原值，iPad 返回 iPhone * iPadScale
        static func adaptiveSize(iPhone value: CGFloat) -> CGFloat {
            UIDevice.current.userInterfaceIdiom == .pad ? value * iPadScale : value
        }
    }

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
        /// 记录头像最大边长（详情页）
        static let recordAvatarMaxDimension: CGFloat = 96
        /// 记录列表行头像最大边长
        static let listRowAvatarMaxDimension: CGFloat = 120
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
        /// 音量亮度调节单次滑动步长（0.0~1.0）
        static let volumeBrightnessStep: CGFloat = 0.05
        /// 音量亮度调节触发最小滑动距离（pt）
        static let gestureMinDragDistance: CGFloat = 20
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
        
        // MARK: 首页入口按钮
        /// 首页入口按钮最小高度（pt）
        static let homeEntryButtonMinHeight: CGFloat = 80
        /// 首页入口按钮圆角半径（pt）
        static let homeEntryButtonCornerRadius: CGFloat = 12
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
    
    // MARK: - 监控配置
    struct Monitor {
        /// 固定时间范围：5 分钟
        static let fixedTimeRange: TimeInterval = 300
        /// 采集间隔（秒）
        static let collectionInterval: TimeInterval = 1.0
        /// 最大数据点数量
        static let maxPointsCount: Int = 300
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
        /// 播放器控制层无操作自动隐藏间隔（秒）
        static let overlayAutoHideInterval: TimeInterval = 3
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
        static let doubaoLLMAPIKey = "doubao_llm_api_key"
        static let openaiLLMAPIKey = "openai_llm_api_key"
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
        static let landscapeTipDismissed = "landscape_tip_dismissed"
    }
    
    // MARK: - 通知名
    struct NotificationNames {
        static let updateImageCount = NSNotification.Name("UpdateImageCount")
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
    
    // MARK: - 内置默认会话
    struct DefaultSession {
        /// 内置默认会话的 ID
        static let id = "A206CF0C-5461-4BDC-90A1-045C4ACC809A"
        /// Bundle 中资源文件的名称前缀
        static let bundleFilePrefix = "default_session_"
    }
    
    // MARK: - 相机横拍提示
    struct CameraTip {
        /// 提示视图展示时长（秒），等于 animationDuration * rotationRepeatCount
        static let displayDuration: TimeInterval = 3.0
        /// 箭头旋转动画单次时长（秒）
        static let animationDuration: TimeInterval = 1.0
        /// 背景遮罩透明度
        static let overlayOpacity: Double = 0.5
        /// 淡出动画时长（秒）
        static let fadeOutDuration: TimeInterval = 0.5
        /// 箭头旋转起始角度（左上角位置）
        static let rotationStartAngle: Double = -60
        /// 箭头旋转结束角度（右上角位置）
        static let rotationEndAngle: Double = 60
        /// 箭头旋转次数
        static let rotationRepeatCount: Int = 3
    }

    // MARK: - 会话命名
    /// 会话名称日期前缀格式（2 位年份.2 位月份.2 位日期 + 空格）
    static let sessionNameDatePrefixFormat = "yy.MM.dd "
    /// 草稿会话默认名称后缀（前缀为日期格式）
    static let draftSessionNameSuffix = "未命名"

    // MARK: - 要点图片配置（EndPicts）
    struct EndPicts {
        /// 横向动画（rightToLeft）对应的结束图目录名
        static let horizontalDirectoryName = "h"
        /// 纵向动画（topToBottom）对应的结束图目录名
        static let verticalDirectoryName = "z"
        /// 横向目录图片数量
        static let horizontalImageCount = 5
        /// 纵向目录图片数量
        static let verticalImageCount = 4
        /// Bundle 中 EndPicts 根目录名
        static let bundleDirectoryName = "EndPicts"
    }

    // MARK: - 字体常量
    struct Fonts {
        /// iPad 自适应缩放快捷方法
        private static func s(_ value: CGFloat) -> CGFloat {
            DeviceScale.adaptiveSize(iPhone: value)
        }

        // MARK: 语义字体 (SwiftUI Text Style)
        static let largeTitle: Font = .largeTitle
        static let title2: Font = .title2
        static let title3: Font = .title3
        static let headline: Font = .headline
        static let subheadline: Font = .subheadline
        static let body: Font = .body
        static let caption: Font = .caption
        static let caption2: Font = .caption2
        static let captionMonospaced: Font = .caption.monospaced()

        // MARK: 自适应字体 (iPad 缩放)

        /// PlayView 设置标签: 11pt
        static var playSettingsLabel: Font { .system(size: s(11)) }
        /// PlayView 关闭按钮: 11pt bold
        static var playCloseIcon: Font { .system(size: s(11), weight: .bold) }
        /// 记录状态标签、分页文本: 12pt
        static var recordMeta: Font { .system(size: s(12)) }
        /// PlayView 播完提示: 13pt
        static var playNextLabel: Font { .system(size: s(13)) }
        /// 搜索图标: 14pt
        static var searchIcon: Font { .system(size: s(14)) }
        /// 分页箭头、列表操作按钮: 14pt medium
        static var listAction: Font { .system(size: s(14), weight: .medium) }
        /// 搜索输入框: 15pt
        static var searchInput: Font { .system(size: s(15)) }
        /// 搜索无结果文本: 15pt semibold
        static var searchNoResult: Font { .system(size: s(15), weight: .semibold) }
        /// 记录图标、操作图标: 16pt
        static var recordIcon: Font { .system(size: s(16)) }
        /// 导航返回/操作按钮: 16pt medium
        static var navAction: Font { .system(size: s(16), weight: .medium) }
        /// 导航栏标题: 17pt semibold
        static var navTitle: Font { .system(size: s(17), weight: .semibold) }
        /// PlayView 更多按钮: 18pt bold
        static var playMoreIcon: Font { .system(size: s(18), weight: .bold) }
        /// 横拍提示返回: 18pt medium
        static var tipBackIcon: Font { .system(size: s(18), weight: .medium) }
        /// 播放/编辑圆形图标: 20pt
        static var recordActionIcon: Font { .system(size: s(20)) }
        /// 加号图标、复选框: 22pt
        static var listAddIcon: Font { .system(size: s(22)) }
        /// 制作控制按钮: 25pt
        static var makeControlIcon: Font { .system(size: s(25)) }
        /// 制作开始按钮: 25pt semibold
        static var makeStartIcon: Font { .system(size: s(25), weight: .semibold) }
        /// PlayView 播放按钮: 28pt bold
        static var playMainIcon: Font { .system(size: s(28), weight: .bold) }
        /// 横拍提示箭头: 30pt medium
        static var tipArrowIcon: Font { .system(size: s(30), weight: .medium) }
        /// 首页图标: 32pt
        static var homeIcon: Font { .system(size: s(32)) }
        /// 搜索空状态图标: 36pt
        static var searchEmptyIcon: Font { .system(size: s(36)) }
        /// 历史空状态图标: 44pt light
        static var historyEmptyIcon: Font { .system(size: s(44), weight: .light) }
        /// 历史空状态标题: 18pt medium
        static var historyEmptyTitle: Font { .system(size: s(18), weight: .medium) }
        /// 历史日期标签: 11pt medium
        static var historyDate: Font { .system(size: s(11), weight: .medium) }
        /// 历史详情文本: 13pt
        static var historyDetail: Font { .system(size: s(13)) }
        /// 横拍提示手机/列表空状态图标: 60pt
        static var emptyStateIcon: Font { .system(size: s(60)) }
        /// 制作页大图标: 80pt
        static var makeLargeIcon: Font { .system(size: s(80)) }

        // MARK: 固定字体 (不随设备缩放)

        /// 启动页应用图标: 50pt
        static let launchAppIcon: Font = .system(size: 50)
        /// PlayView 时间显示: 14pt medium monospaced
        static let playTimerText: Font = .system(size: 14, weight: .medium, design: .monospaced)
        /// 配置编辑器: 16pt light monospaced
        static let configEditorText: Font = .system(size: 16, weight: .light, design: .monospaced)
        /// ChangeLog/Debug 返回按钮: 16pt medium
        static let fixedNavAction: Font = .system(size: 16, weight: .medium)
        /// 制作页图片移除: 26pt
        static let makeImageRemoveIcon: Font = .system(size: 26)
        /// 制作页图片删除: 28pt
        static let makeImageDeleteIcon: Font = .system(size: 28)
        /// 制作失败图标: 40pt
        static let makeErrorIcon: Font = .system(size: 40)
        /// Debug空状态图标: 60pt
        static let debugEmptyIcon: Font = .system(size: 60)

        // MARK: PlayView 设置面板

        /// PlayView 设置面板标题: 14pt medium
        static var playSettingsTitle: Font { .system(size: s(14), weight: .medium) }
    }
}
