# 功能与文件映射

## 应用入口与全局

- PhotoTTSApp/AppState/AppDelegate/MainTabView/FullScreenPageKind/FullScreenPageContainer/FullScreenImageOverlay/FullScreenCameraOverlay：Sources/UI/PhotoTTSApp.swift
- AppLoadingView/AppIntroView：Sources/UI/AppPagesView.swift
- CustomZStack：Sources/UI/CustomZStack.swift

## 底导各 Tab

- 首页：HomePageView（HomePageView.swift）
- 制作：MakeView（MakeView.swift）
- 管理：SessionRecordListView（SessionRecordListView.swift，isRootTab=true，mode=.manage）
- 我的：MeTabView（MeTabView.swift），含播放历史/制作历史/实时监控/调试日志/更新记录/设置/关于入口

## 全屏与相机

- 全屏 overlay：PhotoTTSApp.swift 内 FullScreenImageOverlay/FullScreenCameraOverlay
- 自定义相机+多选图：CustomCameraView.swift（含 MultiImagePicker 封装 PHPickerViewController）
- 相机横拍提示覆盖层：LandscapeTipOverlay.swift（FullScreenCameraOverlay 叠加，3秒自动消失，含「不再提示」按钮，偏好持久化到 UserDefaults[landscape_tip_dismissed]）

## 播放与记录

- PlayView（播放器，含 PlayerImageView、PlayerControlLayer、PlayerProgressBar）：PlayView.swift
- SessionRecordListView：SessionRecordListView.swift
- SessionRecordUnifiedView（保存/编辑/查看）：SessionRecordDetailView.swift
- SessionRecordManager：Core/Managers/Session/SessionRecordManager.swift

## 后台制作

- BackgroundMakeManager（MakeTask）：Core/Managers/BackgroundMake/BackgroundMakeManager.swift

## OCR 与 TTS

- ImageToSpeechCoordinator：Core/Coordinators/ImageToSpeechCoordinator.swift
- OCRService/OCRServiceFactory（多 Provider：doubao/openai）：Core/Handlers/Image/OCRService.swift
- TTSServiceProtocol/TTSService（火山）/AliqwenTTSService（阿里千问）/TTSServiceFactory（多 Provider：huoshan/aliqwen）：Core/Handlers/Audio/TTSService.swift
- LLMServiceProtocol/LLMServiceFactory/DoubaoLLMService/OpenAILLMService（多 Provider：doubao/openai）：Core/Handlers/LLM/LLMService.swift
- NetworkService：Core/Managers/Network/NetworkService.swift

## Siri

- SessionRecordEntity/Query：Core/Intents/SessionRecordEntity.swift
- PlaySessionIntent/PhotoTTSShortcuts：Core/Intents/PlaySessionIntent.swift

## 设置与历史

- SettingsView/SettingsManager：SettingsView.swift / Core/Managers/Settings/SettingsManager.swift
- PlayHistoryManager+View / MakeHistoryManager+View / DebugLogManager+View
- PerformanceMonitorManager+View（实时监控）：Core/Managers/Monitor/PerformanceMonitorManager.swift / UI/RealTimeMonitorView.swift
- ScheduledTasks（预留，空）

## 模型与常量

- Models/：SessionRecord、AudioResponse（APIResponse.swift）、VoiceSettings
- Constants.swift / CustomNavigationBar.swift
- Monitor 模型：Core/Managers/Monitor/MetricModels.swift

## 配置与资源

- config_example.json（Bundle 内默认配置模板）/ ChangeLogsView+changelogs.md
- Resources/DefaultSession/：内置默认绘本（使用介绍），含 metadata.json/record.json/history.json/audio.mp3/avatar.jpg/images/；由 SessionRecordManager 在用户无记录时从 Bundle 加载展示
- locals/（项目根目录，不在 Xcode PBXFileSystemSynchronizedRootGroup 内，不打包到 App Bundle）：存放 config_local.json 等本地敏感配置；App 首次启动时 SettingsManager.ensureUserConfigExists() 从 Bundle 的 config_example.json 复制到 Documents/config_local.json

## 测试

- 单元测试（PhotoTTSTests/）：PhotoTTSAppTests/SettingsManagerTests/ImageToSpeechCoordinatorTests/DebugLogManagerTests
- 功能测试（FunctionalTests/）：TestPhotoTTSIntegration（真实 API，默认 XCTSkip）、TestAliqwenTTS（阿里千问 TTS 真实 API 测试）
- UI 测试（PhotoTTSUITests/）：启动验证/性能/截图
