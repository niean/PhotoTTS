<!-- SUMMARY: 功能文件映射：底导Tab/全屏播放/OCR-TTS-LLM/设置历史/模型常量对应源文件 -->
# 功能与文件映射

## 应用入口与全局

- PhotoTTSApp/AppState/AppDelegate/MainTabView/FullScreenPageKind/FullScreenPageContainer/FullScreenImageOverlay/FullScreenCameraOverlay：PhotoTTS/Sources/UI/PhotoTTSApp.swift
- AppLoadingView/AppIntroView：PhotoTTS/Sources/UI/AppPagesView.swift
- CustomZStack：PhotoTTS/Sources/UI/CustomZStack.swift

## 底导各 Tab

- 首页：HomePageView（PhotoTTS/Sources/UI/HomePageView.swift，双列卡片网格，含 SessionRecordCard）
- 制作：MakeView（PhotoTTS/Sources/UI/MakeView.swift）
- 管理：SessionRecordListView（PhotoTTS/Sources/UI/SessionRecordListView.swift，isRootTab=true，mode=.manage）
- 我的：MeTabView（PhotoTTS/Sources/UI/MeTabView.swift），含播放历史/制作历史/实时监控/调试日志/更新记录/要点图片/设置/关于入口
- 消息（预留）：MessageTabView（PhotoTTS/Sources/UI/MessageTabView.swift），未集成到 MainTabView
- 要点图片管理：EndPictManagementView（PhotoTTS/Sources/UI/EndPictManagementView.swift），从我的 Tab 进入
- 分页控件：PaginationControl（PhotoTTS/Sources/UI/PaginationControl.swift），供 HomePageView/SessionRecordListView 复用
- 搜索栏组件：SessionSearchBar（PhotoTTS/Sources/UI/SessionSearchBar.swift），可复用搜索栏，含系列筛选和关键词搜索

## 全屏与相机

- 全屏 overlay：PhotoTTS/Sources/UI/PhotoTTSApp.swift 内 FullScreenImageOverlay/FullScreenCameraOverlay
- 自定义相机+多选图：PhotoTTS/Sources/UI/CustomCameraView.swift（含 MultiImagePicker 封装 PHPickerViewController）
- 相机横拍提示覆盖层：PhotoTTS/Sources/UI/LandscapeTipOverlay.swift（FullScreenCameraOverlay 叠加，3秒自动消失，含「不再提示」按钮，偏好持久化到 UserDefaults[landscape_tip_dismissed]）

## 播放与记录

- PlayView（播放器，含 PlayerImageView、PlayerControlLayer、PlayerProgressBar）：PhotoTTS/Sources/UI/PlayView.swift
- SessionRecordListView：PhotoTTS/Sources/UI/SessionRecordListView.swift
- SessionRecordUnifiedView（保存/编辑/查看）：PhotoTTS/Sources/UI/SessionRecordDetailView.swift
- SessionRecordManager：PhotoTTS/Sources/Core/Managers/Session/SessionRecordManager.swift

## 后台制作

- BackgroundMakeManager（MakeTask）：PhotoTTS/Sources/Core/Managers/BackgroundMake/BackgroundMakeManager.swift

## 设备传输

- PeerTransferManager（MultipeerConnectivity 设备间直传）：PhotoTTS/Sources/Core/Managers/PeerTransfer/PeerTransferManager.swift
- DeviceTransferView（发送方 UI）：PhotoTTS/Sources/UI/DeviceTransferView.swift
- TransferReceiverModifier（接收方公共 UI，ViewModifier）：PhotoTTS/Sources/UI/TransferReceiverModifier.swift

## OCR 与 TTS

- ImageToSpeechCoordinator：PhotoTTS/Sources/Core/Coordinators/ImageToSpeechCoordinator.swift
- OCRService/OCRServiceFactory（多 Provider：doubao/openai）：PhotoTTS/Sources/Core/Handlers/Image/OCRService.swift
- TTSServiceProtocol/TTSService（火山）/AliqwenTTSService（阿里千问）/TTSServiceFactory（多 Provider：huoshan/aliqwen）：PhotoTTS/Sources/Core/Handlers/Audio/TTSService.swift
- LLMServiceProtocol/LLMServiceFactory/DoubaoLLMService/OpenAILLMService（多 Provider：doubao/openai）：PhotoTTS/Sources/Core/Handlers/LLM/LLMService.swift
- NetworkService：PhotoTTS/Sources/Core/Managers/Network/NetworkService.swift

## 封面管理

- CoverImageManager：PhotoTTS/Sources/Core/Handlers/Image/CoverImageManager.swift（封面生成、裁剪、旋转）
- CoverEditView：PhotoTTS/Sources/UI/CoverEditView.swift（封面裁剪弹窗）

## Siri

- SessionRecordEntity/Query：PhotoTTS/Sources/Core/Intents/SessionRecordEntity.swift
- PlaySessionIntent/PhotoTTSShortcuts：PhotoTTS/Sources/Core/Intents/PlaySessionIntent.swift

## 设置与历史

- SettingsView/SettingsManager：PhotoTTS/Sources/UI/SettingsView.swift / PhotoTTS/Sources/Core/Managers/Settings/SettingsManager.swift
- PlayHistoryManager+View / MakeHistoryManager+View / DebugLogManager+View
- PerformanceMonitorManager+View（实时监控）：PhotoTTS/Sources/Core/Managers/Monitor/PerformanceMonitorManager.swift / PhotoTTS/Sources/UI/RealTimeMonitorView.swift / PhotoTTS/Sources/UI/RealTimeMonitorChartView.swift（时序图表组件）
- ChangeLogsView（更新记录）：PhotoTTS/Sources/UI/ChangeLogsView.swift（解析 PhotoTTS/Resources/changelogs.md 渲染）
- ReadingReportManager（阅读报告数据聚合）：PhotoTTS/Sources/Core/Managers/ReadingReport/ReadingReportManager.swift
- ReadingReportView（阅读报告页面）：PhotoTTS/Sources/UI/ReadingReportView.swift

## 模型与常量

- Models/：SessionRecord、AudioResponse（PhotoTTS/Sources/Models/APIResponse.swift）、VoiceSettings
- PhotoTTS/Sources/Constants.swift / PhotoTTS/Sources/UI/CustomNavigationBar.swift
- Monitor 模型：PhotoTTS/Sources/Core/Managers/Monitor/MetricModels.swift

## 配置与资源

- `PhotoTTS/Resources/config_example.json`（Bundle 内默认配置模板）/ `PhotoTTS/Resources/changelogs.md`（更新记录数据）
- PhotoTTS/Resources/DefaultSession/：内置默认绘本（使用介绍），含 default_session_metadata.json/default_session_record.json/default_session_history.json/default_session_audio.mp3/default_session_avatar.jpg/default_session_readme.txt/images/default_session_image_*.jpg；由 SessionRecordManager 在用户无记录时从 Bundle 加载展示
- locals/（项目根目录，不在 Xcode PBXFileSystemSynchronizedRootGroup 内，不打包到 App Bundle）：存放本地敏感配置（如 `locals/config/config_local.json`）；App 首次启动时 SettingsManager.ensureUserConfigExists() 从 Bundle 的 `PhotoTTS/Resources/config_example.json` 复制配置到应用沙箱 Documents 目录

## 测试

- 单元测试（PhotoTTSTests/）：PhotoTTSAppTests/SettingsManagerTests/ImageToSpeechCoordinatorTests/DebugLogManagerTests/ContinuousPlaybackTests/PeerTransferManagerTests/ReadingReportManagerTests
- 功能测试（PhotoTTSTests/FunctionalTests/）：TestPhotoTTSIntegration（真实 API，默认 XCTSkip）、TestAliqwenTTS（阿里千问 TTS 真实 API 测试）
- UI 测试（PhotoTTSUITests/）：启动验证/性能/截图
