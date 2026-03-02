# 架构与模块边界

## 分层（自顶向下）

- 表现层：Sources/UI，SwiftUI 视图与少量 UIKit 封装（如 CustomCameraView）。主要视图：PhotoTTSApp（根）、MainTabView（底导）、HomePageView（首页）、MakeView（制作，含 PhotoProcessingView）、MessageTabView（消息）、MeTabView（我的）、PlayView（全屏播放）、SessionRecordListView、SessionRecordUnifiedView（保存/编辑会话统一视图，位于 SessionRecordDetailView.swift）、AppLoadingView/AppIntroView（位于 AppPagesView.swift）。
- 业务协调：Sources/Core/Coordinators/ImageToSpeechCoordinator，串联 OCR 与 TTS，上报进度与完成/失败。
- 能力层：Sources/Core/Handlers（OCRService、TTSService）、Sources/Core/Managers（NetworkService、SettingsManager、SessionRecordManager、PlayHistoryManager、MakeHistoryManager、DebugLogManager）。
- 系统集成：Sources/Core/Intents（PlaySessionIntent、SessionRecordEntity、PhotoTTSShortcuts），负责 Siri / App Shortcuts 的意图处理与实体查询，通过 AppState 与 SessionRecordManager 桥接到业务层。
- 数据与模型：Sources/Models（SessionRecord、APIResponse、VoiceSettings 等）；Constants 与配置在 Sources/Constants.swift、Resources/config_local.json。
- 预留：Sources/Core/Managers/ScheduledTasks 目录目前为空，待后续定时任务需求使用。

## 模块边界与依赖

- UI 不直接调 OCR/TTS API，通过 Coordinator 或 ViewModel 调用 ImageToSpeechCoordinator。
- Coordinator 依赖 NetworkService（协议）、SettingsManager、OCRService；OCR 与 TTS 的 URL/Key 来自 SettingsManager（读 config_local.json 与用户覆盖）。
- SessionRecord 由 SessionRecordManager 读写；播放历史、制作历史、调试日志由各自 Manager 管理，UI 仅通过 Manager 或 AppState 访问。
- 跨界面状态（全屏类型、Tab、要加载到制作页的 sessionId）集中在 AppState，由根视图与各 Tab 共享。
- 首页→制作跨 Tab 协调：HomePageView 写入 AppState.openCameraOnNextRecordAppear 或 openPhotoPickerOnNextRecordAppear，同时切换 selectedTab=1；MakeView.onAppear/onChange(selectedTab) 消费这两个标志并立即置 false，避免重复触发。选图用 MultiImagePicker（fullScreenCover 弹出），相机用 appState.fullScreenKind = .camera。
- Tab 导航重置：离开首页/消息/我的时，对应 tabXResetId 自增，TabView 内视图因 .id() 变化而销毁重建，清空内部导航栈，防止切 Tab 后残留子页面。

## 关键约束

- 全屏仅三种：启动页、全屏大图、全屏相机；播放一律用 PlayView 全屏，相机用 CustomCameraView 全屏 overlay。
- 底导四 Tab：首页、制作、消息、我的；全屏时仅 PlayView 与相机 overlay 遮盖底导。
- 数据边界：SessionRecord 为会话的权威结构；与外部 API 的请求/响应形态见 Models/APIResponse 与各 Service，不在 UI 层解析 API 原始格式。
