<!-- SUMMARY: 分层架构：表现层/协调层/能力层/系统集成/数据层，模块边界与全屏控制规则 -->
# 架构与模块边界

## 分层

- 表现层（PhotoTTS/Sources/UI）：SwiftUI+UIKit 封装。主要视图：PhotoTTSApp（根）、MainTabView（底导）、HomePageView、MakeView（含 PhotoProcessingView）、MeTabView、PlayView（全屏播放）、SessionRecordListView、SessionRecordUnifiedView（保存/编辑/查看，位于 SessionRecordDetailView.swift）、AppLoadingView/AppIntroView（位于 AppPagesView.swift）、PaginationControl（分页控件）、ChangeLogsView（更新记录）、RealTimeMonitorChartView（监控图表）
- 协调层（PhotoTTS/Sources/Core/Coordinators）：ImageToSpeechCoordinator 串联 OCR+LLM+TTS 三阶段流程，上报进度与结果
- 能力层（PhotoTTS/Sources/Core/Handlers+Managers）：OCRService、TTSService、NetworkService、SettingsManager、SessionRecordManager、PlayHistoryManager、MakeHistoryManager、DebugLogManager、BackgroundMakeManager、PerformanceMonitorManager、PeerTransferManager。PlayHistoryManager/MakeHistoryManager 将数据存储委托 SessionRecordManager（会话级 history.json）。BackgroundMakeManager 管理单个后台 MakeTask（持有独立 Coordinator）。PerformanceMonitorManager 负责实时监控 CPU、内存、磁盘、网络指标。PeerTransferManager 封装 MultipeerConnectivity 实现设备间直传（WiFi/蓝牙自动切换）
- 系统集成（PhotoTTS/Sources/Core/Intents）：PlaySessionIntent、SessionRecordEntity、PhotoTTSShortcuts，通过 AppState+SessionRecordManager 桥接
- 数据层（PhotoTTS/Sources/Models）：SessionRecord、APIResponse、VoiceSettings；PhotoTTS/Sources/Constants.swift、config_local.json

## 模块边界

- UI 不直接调 OCR/TTS API，通过 Coordinator
- Coordinator 依赖 NetworkService（协议）、SettingsManager、OCRService；密钥来自 SettingsManager
- SessionRecord 由 SessionRecordManager 读写；各历史/日志由各自 Manager 管理
- 跨界面状态集中 AppState，根视图与各 Tab 共享
- 跨 Tab 协调：HomePageView 写 AppState 标志 -> selectedTab=1 -> MakeView onAppear+onChange 消费
- Tab 重置：离开 tab0/2/3 时 resetId 自增重建；tab1 不参与

## 关键约束

- 全屏类型：启动页/全屏大图/全屏相机（via fullScreenKind）；PlayView 通过 fullScreenCover（不经 fullScreenKind）
- 播放器布局：设备始终竖屏，图片保持拍摄原始方向（aspectRatio .fit）。控制层（PlayerControlLayer）按横屏布局，通过 .rotationEffect(.degrees(90)) 旋转后覆盖在竖屏图片之上（适配手机左侧为底的横屏观看）。横屏 bottom-left 映射到用户横屏 bottom-left（播放+进度条），横屏 top-right 映射到用户横屏 top-right（退出+定时关闭）
- 底导四 Tab：首页/制作/管理/我的
- 数据边界：SessionRecord 为会话权威结构；UI 层不解析 API 原始格式
