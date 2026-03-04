# 架构与模块边界

## 分层

- 表现层：Sources/UI，SwiftUI 视图与 UIKit 封装。主要视图：PhotoTTSApp（根）、MainTabView（底导）、HomePageView（首页）、MakeView（制作，含 PhotoProcessingView）、MessageTabView（消息）、MeTabView（我的）、PlayView（全屏播放）、SessionRecordListView、SessionRecordUnifiedView（保存/编辑会话，位于 SessionRecordDetailView.swift）、AppLoadingView/AppIntroView（位于 AppPagesView.swift）。
- 业务协调：Sources/Core/Coordinators/ImageToSpeechCoordinator，串联 OCR 与 TTS，上报进度与完成/失败。
- 能力层：Sources/Core/Handlers（OCRService、TTSService）、Sources/Core/Managers（NetworkService、SettingsManager、SessionRecordManager、PlayHistoryManager、MakeHistoryManager、DebugLogManager）。PlayHistoryManager 和 MakeHistoryManager 的数据存储委托 SessionRecordManager（会话级 history.json），不再维护独立文件。
- 系统集成：Sources/Core/Intents（PlaySessionIntent、SessionRecordEntity、PhotoTTSShortcuts），Siri / App Shortcuts 意图处理，通过 AppState 与 SessionRecordManager 桥接到业务层。
- 数据与模型：Sources/Models（SessionRecord、APIResponse、VoiceSettings）；Constants.swift、Resources/config_local.json。
- 预留：Sources/Core/Managers/ScheduledTasks/（目录为空）。

## 模块边界

- UI 不直接调 OCR/TTS API，通过 Coordinator 调用。
- Coordinator 依赖 NetworkService（协议）、SettingsManager、OCRService；OCR 与 TTS 的 URL/Key 来自 SettingsManager。
- SessionRecord 由 SessionRecordManager 读写；播放历史、制作历史、调试日志由各自 Manager 管理。
- 跨界面状态集中在 AppState，由根视图与各 Tab 共享。
- 首页->制作跨 Tab 协调：HomePageView 写入 AppState 标志（openCamera/openPhotoPicker），切 selectedTab=1；MakeView 在 onAppear 和 onChange(selectedTab) 中消费并立即置 false。
- Tab 导航重置：离开首页/消息/我的时 tabXResetId 自增，视图因 .id() 变化而销毁重建清空导航栈；制作页不参与重置。

## 关键约束

- 全屏类型三种：启动页、全屏大图、全屏相机；PlayView 通过 fullScreenCover 弹出（不经 fullScreenKind）。
- 底导四 Tab：首页、制作、消息、我的。
- 数据边界：SessionRecord 为会话权威结构；UI 层不解析 API 原始格式。
