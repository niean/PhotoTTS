# 功能与文件映射

## 应用入口与全局

- PhotoTTSApp、AppState、AppDelegate、MainTabView、FullScreenPageKind、FullScreenPageContainer、FullScreenImageOverlay、FullScreenCameraOverlay：PhotoTTS/Sources/UI/PhotoTTSApp.swift
- AppLoadingView、AppIntroView、AppPageView、IntroAvatarImage：PhotoTTS/Sources/UI/AppPagesView.swift
- CustomZStack：PhotoTTS/Sources/UI/CustomZStack.swift

## 底导各 Tab

- 首页：HomePageView（Sources/UI/HomePageView.swift）
- 制作：MakeView（Sources/UI/MakeView.swift）
- 消息：MessageTabView（Sources/UI/MessageTabView.swift），内含播放历史、制作历史、调试日志、更新记录入口
- 我的：MeTabView（Sources/UI/MeTabView.swift）

## 全屏与相机

- 全屏大图内容、全屏相机：PhotoTTSApp.swift 内 FullScreenImageOverlay、FullScreenCameraOverlay；CustomCameraView：Sources/UI/CustomCameraView.swift

## 播放与记录

- 全屏播放：PlayView（Sources/UI/PlayView.swift）
- 会话记录列表：SessionRecordListView（Sources/UI/SessionRecordListView.swift）
- 会话记录保存/编辑统一视图（SessionRecordUnifiedView）：Sources/UI/SessionRecordDetailView.swift
- 会话记录存储：SessionRecordManager（Sources/Core/Managers/Session/SessionRecordManager.swift）

## OCR 与 TTS

- 协调器：ImageToSpeechCoordinator（Sources/Core/Coordinators/ImageToSpeechCoordinator.swift）
- OCR：OCRService（Sources/Core/Handlers/Image/OCRService.swift）
- TTS：TTSService（Sources/Core/Handlers/Audio/TTSService.swift）
- 网络：NetworkService（Sources/Core/Managers/Network/NetworkService.swift）

## Siri 语音控制

- 绘本实体与查询（SessionRecordEntity、SessionRecordEntityQuery）：Sources/Core/Intents/SessionRecordEntity.swift
- 播放意图与 Siri 短语注册（PlaySessionIntent、PhotoTTSShortcuts）：Sources/Core/Intents/PlaySessionIntent.swift

## 选图

- 多选图组件（MultiImagePicker）：目前内联于 MakeView.swift，以 fullScreenCover 方式弹出

## 设置与历史

- 设置页：SettingsView（Sources/UI/SettingsView.swift）
- 设置存储：SettingsManager（Sources/Core/Managers/Settings/SettingsManager.swift）
- 播放历史：PlayHistoryManager（Sources/Core/Managers/PlayHistory/PlayHistoryManager.swift）、PlayHistoryView（Sources/UI/PlayHistoryView.swift）
- 制作历史：MakeHistoryManager（Sources/Core/Managers/MakeHistory/MakeHistoryManager.swift）、MakeHistoryView（Sources/UI/MakeHistoryView.swift）
- 调试日志：DebugLogManager（Sources/Core/Managers/Debug/DebugLogManager.swift）、DebugLogView（Sources/UI/DebugLogView.swift）
- 定时任务（预留）：Sources/Core/Managers/ScheduledTasks/（目录为空，待后续需求填充）

## 模型与常量

- 模型：Sources/Models/（SessionRecord、APIResponse、VoiceSettings）
- 常量与扩展：Sources/Constants.swift
- 顶导通用：CustomNavigationBar（Sources/UI/CustomNavigationBar.swift）

## 配置与资源

- 配置示例与本地配置：PhotoTTS/Resources/config_example.json、config_local.json
- 更新记录展示：ChangeLogsView、Resources/changelogs.md
