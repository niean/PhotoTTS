# 功能与文件映射

## 应用入口与全局

- PhotoTTSApp/AppState/AppDelegate/MainTabView/FullScreenPageKind/FullScreenPageContainer/FullScreenImageOverlay/FullScreenCameraOverlay：Sources/UI/PhotoTTSApp.swift
- AppLoadingView/AppIntroView：Sources/UI/AppPagesView.swift
- CustomZStack：Sources/UI/CustomZStack.swift

## 底导各 Tab

- 首页：HomePageView（HomePageView.swift）
- 制作：MakeView（MakeView.swift）
- 消息：MessageTabView（MessageTabView.swift），含播放历史/制作历史/调试日志/更新记录入口
- 我的：MeTabView（MeTabView.swift）

## 全屏与相机

- 全屏 overlay：PhotoTTSApp.swift 内 FullScreenImageOverlay/FullScreenCameraOverlay
- 自定义相机+多选图：CustomCameraView.swift（含 MultiImagePicker 封装 PHPickerViewController）

## 播放与记录

- PlayView（横屏播放器，含 PlayerImageView、PlayerProgressBar）：PlayView.swift
- SessionRecordListView：SessionRecordListView.swift
- SessionRecordUnifiedView（保存/编辑/查看）：SessionRecordDetailView.swift
- SessionRecordManager：Core/Managers/Session/SessionRecordManager.swift

## 后台制作

- BackgroundMakeManager（MakeTask）：Core/Managers/BackgroundMake/BackgroundMakeManager.swift

## OCR 与 TTS

- ImageToSpeechCoordinator：Core/Coordinators/ImageToSpeechCoordinator.swift
- OCRService/OCRServiceFactory（多 Provider：doubao/openai）：Core/Handlers/Image/OCRService.swift
- TTSServiceProtocol/TTSService（火山）/AliqwenTTSService（阿里千问）/TTSServiceFactory（多 Provider：huoshan/aliqwen）：Core/Handlers/Audio/TTSService.swift
- NetworkService：Core/Managers/Network/NetworkService.swift

## Siri

- SessionRecordEntity/Query：Core/Intents/SessionRecordEntity.swift
- PlaySessionIntent/PhotoTTSShortcuts：Core/Intents/PlaySessionIntent.swift

## 设置与历史

- SettingsView/SettingsManager：SettingsView.swift / Core/Managers/Settings/SettingsManager.swift
- PlayHistoryManager+View / MakeHistoryManager+View / DebugLogManager+View
- ScheduledTasks（预留，空）

## 模型与常量

- Models/：SessionRecord、AudioResponse（APIResponse.swift）、VoiceSettings
- Constants.swift / CustomNavigationBar.swift

## 配置与资源

- config_example.json（Bundle 内默认配置模板）/ ChangeLogsView+changelogs.md
- Resources/DefaultSession/：内置默认绘本（使用介绍），含 metadata.json/record.json/history.json/audio.mp3/avatar.jpg/images/；由 SessionRecordManager 在用户无记录时从 Bundle 加载展示
- locals/（项目根目录，不在 Xcode PBXFileSystemSynchronizedRootGroup 内，不打包到 App Bundle）：存放 config_local.json 等本地敏感配置；App 首次启动时 SettingsManager.ensureUserConfigExists() 从 Bundle 的 config_example.json 复制到 Documents/config_local.json

## 测试

- 单元测试（PhotoTTSTests/）：PhotoTTSAppTests/SettingsManagerTests/ImageToSpeechCoordinatorTests/DebugLogManagerTests
- 功能测试（FunctionalTests/）：TestPhotoTTSIntegration（真实 API，默认 XCTSkip）、TestAliqwenTTS（阿里千问 TTS 真实 API 测试）
- UI 测试（PhotoTTSUITests/）：启动验证/性能/截图
