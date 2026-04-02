<!-- SUMMARY: 11个关键模式：跨Tab协调/PlayView横竖屏/图片按需加载/OCR并发/Siri/全屏覆盖/后台制作/默认会话保护/iPad适配/错误分层/防息屏 -->
# 关键代码模式

项目中反复出现但不易从单个文件推断的模式，供新功能实现时参照。

## 模式一：管理页->制作跨 Tab 协调

SessionRecordListView（manage+isRootTab 模式）写入 AppState 标志（openCameraOnNextRecordAppear/openPhotoPickerOnNextRecordAppear），设 selectedTab=1。MakeView 在 .onAppear 和 .onChange(of: selectedTab) 中同时检测并消费（立即置 false）。用户取消且本次从管理页发起时自动回 tab2。

陷阱：不能只在 onAppear 消费，Tab 切换时 onAppear 不一定触发（视图可能已存在），必须同时监听 onChange。

## 模式二：PlayView 竖屏播放器 + 横屏控制层

设备始终竖屏，不做横屏旋转。控制层（PlayerControlLayer）按横屏布局，通过 .rotationEffect(.degrees(90)) 旋转覆盖在竖屏图片之上。旋转映射（+90° CW）：HStack 左→右在用户横屏视角下保持不变。

### 入参
两种互斥入参，均通过 .fullScreenCover 打开：
- recordId：已保存记录，按需 loadImage，禁止 getImages() 全量加载
- preloadedRecord：未保存制作中记录，图片已在内存

### 图片切换
三种方式：(1) 播放中音频进度自动驱动（updateCurrentImageIndex 基于 textSegmentRanges）；(2) 拖动进度条跳转（seekToRatio snap 到最近分割点，维持原播放状态）；(3) 暂停后滑动手势（DragGesture on 底层 Color，方向受 animationStyle 管控）。

### 控制层
PlayerControlLayer 悬浮在图片之上（isOverlayVisible 控制显隐），通过回调与 PlayView 交互。用户横屏 bottom-left：播放/暂停 + 进度条（PlayerProgressBar）。用户横屏 top-right：退出 + "播完本集"开关（autoStopEnabled，默认开启）。

### 连播队列
queueRecordIds 参数（默认空），由 HomePageView 通过 buildSameDateQueue 构建（同日期已完成记录，日期从名称前缀解析）。播完后 advanceToNextRecord：过渡页面 -> 预加载 -> 自动播放。跨天不纳入队列。Siri/MakeView 不传队列。

### 播放互斥
AppState.isPlayViewActive 全局标志，任意时刻只允许一个记录播放。三个触发点打开前检查，为 true 时拒绝。

### 手势分层隔离
底层 Color `.simultaneousGesture(DragGesture)` 响应滑动，`.onTapGesture` 响应单击/双击。图片层 allowsHitTesting(false)。控制层可见时两层隔离：(1) 底层 guard `!isOverlayVisible`；(2) 控制层 `.contentShape(Rectangle())` 阻止穿透。滑动方向受 animationStyle 管控。浮层 3s 无操作自动隐藏。

### 翻页动画
AnimationStyle 枚举控制方向（rightToLeft/topToBottom），@State isForwardTransition 记录方向。.transition 根据 (animationStyle, isForwardTransition) 二维组合选择插入/移除边缘。.animation(.easeInOut(duration: 0.3)) 驱动。

## 模式三：图片按需加载与缓存

用于 PlayView 全屏播放翻页。调用链：FullScreenImageContent(useOnDemand) -> OnDemandImagePage。onAppear 先查 NSCache（countLimit=6），命中同步显示；未命中后台调 loadImage（1024pt），主线程动画更新。切页 preloadAdjacentImages 预加载前后两张。loadImage 内部用 Image I/O 直接生成目标尺寸。

新增全屏图片浏览应复用 FullScreenImageContent + OnDemandImagePage。

## 模式四：OCR 并发分批处理

ImageToSpeechCoordinator.performConcurrentOCR：按 ocr_concurrent_count（config sys 节）分批 chunked，每批 withTaskGroup 并发执行 OCRService.recognizeText。失败返回 ""（保持索引）。每批完成更新进度（OCR 0~50%，LLM 50~70%，TTS 70~100%）。拼接时剔除 ocrEmptyResultIndicator，检查总长度不超 tts_text_max_length。

扩展 OCR 应在此函数修改，不在 UI 层自行并发。

## 模式五：Siri 语音触发播放与控制

触发播放流程：
1. registerAppShortcuts 仅在 scenePhase==.active 时调用（首次+每次回前台），不在 init() 中
2. PlaySessionIntent 将 sessionId 写入 UserDefaults（siriPendingPlaySessionId），openAppWhenRun=true
3. PhotoTTSApp 监听 .active 调 loadPendingSiriSession()，读取并清除 key，后台加载 SessionRecord，主线程赋值 appState.sessionRecordToPlay
4. .fullScreenCover(item: sessionRecordToPlay) 触发 PlayView；冷启动时启动页未结束则延迟 2s 再触发

模糊匹配（SessionRecordEntityQuery）：全名 contains（兜底） -> 跳过日期前缀取内容 -> "-" 分段 -> 去"-"全文 contains。

陷阱：phrase 必须含 \(.applicationName)，否则 appintentsmetadataprocessor halting error。

播放中控制（MPRemoteCommandCenter）：PlayView.startPlayback 注册 play/pause/togglePlayPause 远程命令 -> NotificationCenter 发送 action -> PlayView .onReceive 分发。stop/finish 时 clearRemoteTransportControls。不写 MPNowPlayingInfoCenter（避免系统弹出 Now Playing）。不支持远程 stop 退出 PlayView（Siri 遮罩期间 SwiftUI 无法可靠关闭 fullScreenCover）。

## 模式六：全屏覆盖层（fullScreenKind）

AppState.fullScreenKind 控制，CustomZStack 根层渲染：fullScreenKind != .loading 时显示 MainTabView，有 kind 时叠加 FullScreenPageContainer（zIndex 100）。

新增全屏场景加 FullScreenPageKind case + FullScreenPageContainer switch 处理。PlayView 例外（通过 fullScreenCover 弹出）。

## 模式七：后台制作（Background Make）

MakeView.processImages() 调 BackgroundMakeManager.shared.startMaking(images:) 返回 sessionId。startMaking 创建草稿会话（图片落盘、makeStatus=making、名称"YY.MM.DD 未命名"），创建 MakeTask（持有独立 Coordinator）启动。

MakeView 通过 @State observingTaskId 跟踪，.onReceive(bgMakeManager.objectWillChange) 同步进度/结果。完成后后台 updateSessionWithResults 更新 record.json/音频/makeStatus=completed，随后 addMakeEvent 写入制作历史事件（直接调用，绕过 recordSave 的名称过滤；loadEntries 聚合时按当前名称过滤）。失败删除草稿。

重连：切回 Tab1 通过 appState.makeTaskIdToReconnect 或自动检测，调 reconnectToBackgroundTask()。列表中 isMaking 记录显示"制作中"标签，仅允许删除。

约束：只允许 1 个后台制作任务（制作页只允许 1 个制作项），已有活跃任务时 startMaking 返回 nil。

## 模式九：默认会话只读保护

内置默认会话（Constants.DefaultSession.id）除播放外禁止所有操作，三层协防：

1. Model 层：SessionRecordMetadata.isDefault 计算属性（id == Constants.DefaultSession.id），UI 层统一判断入口
2. UI 层：SessionRecordListView 构建 SessionRecordRow 时，isDefault 为 true 则除 onLoad（播放）外所有闭包传 nil（onView/onEdit/onExport/onDelete/onLoadToMake），更多菜单自动隐藏
3. Manager 层：SessionRecordManager.updateSession/exportSession 开头拦截默认会话（isBundledDefaultSession），返回失败 + 警告日志；loadAllSessionHistories 跳过默认会话，使其不出现在播放历史和制作历史中

新增默认会话限制应在这三层同步添加防护。

## 模式十：iPad 自适应尺寸（DeviceScale）

Constants.DeviceScale 提供 iPadScale（1.5）和 adaptiveSize(iPhone:) 函数，iPad 上将 iPhone 基准值乘以比例系数。

每个 UI struct（View/组件）添加私有快捷方法：
```swift
private func scaled(_ value: CGFloat) -> CGFloat {
    Constants.DeviceScale.adaptiveSize(iPhone: value)
}
```

嵌套 struct（如 MakeView.LayoutMetrics）无法访问外层方法时，直接调用 `Constants.DeviceScale.adaptiveSize(iPhone: value)`。

使用场景：
- 数值型尺寸：padding/frame/spacing/cornerRadius 等，scaled(iPhone基准值)
- 字体：统一通过 `Constants.Fonts` 引用（详见 ./03-conventions.md 字体章节）。自适应字体内部调 `DeviceScale.adaptiveSize`，固定字体不随设备缩放
- 全项目无 isPad 三元表达式控制尺寸，统一走 adaptiveSize

覆盖范围：全部 15 个 UI 源文件（PlayView/MakeView/SettingsView/HomePageView/SessionRecordListView/MakeHistoryView/PlayHistoryView/DebugLogView/CustomNavigationBar/MeTabView/SessionRecordDetailView/DeviceTransferView/PaginationControl/LandscapeTipOverlay/EndPictManagementView）。

## 模式十一：错误分层（Error Layering）

三层错误架构，确保用户消息友好、开发日志含技术细节：

服务层：OCRError/TTSError 实现 LocalizedError，提供 errorDescription（用户友好中文，无技术细节）+ technicalDescription（含错误码和内部信息，供 os.Logger）。新增服务级错误枚举必须遵循此双属性模式。

协调层：ImageToSpeechProcessingError 包装服务错误（.ocrFailed(Error)/.ttsFailed(Error)），errorDescription 委托给内层服务错误的 errorDescription。

NSError 创建：统一使用 Constants.ErrorInfo.domain / Constants.ErrorInfo.defaultCode，禁止硬编码 domain 字符串。

涉及文件：OCRService.swift（OCRError）、TTSService.swift（TTSError）、ImageToSpeechCoordinator.swift（ImageToSpeechProcessingError）、Constants.swift（ErrorInfo）。

## 模式十二：防息屏（Idle Timer）

两层策略防止屏幕自动熄灭：全局兜底 + 场景级保护。

全局兜底：PhotoTTSApp init() 设置 `UIApplication.shared.isIdleTimerDisabled = true`，scenePhase 变为 .active 时再次设置（应对系统重置）。

场景级保护：关键页面在各自启动入口重新设置 isIdleTimerDisabled = true：
- PlayView：startPlayback()、resumePlayback()
- MakeView：processImages()
- PeerTransferManager：startBrowsing()（传输开始）、session didReceiveStream（传输恢复）

陷阱：系统会在特定时机重置 isIdleTimerDisabled（如 App 回前台），不能只依赖全局 init() 设置。每个需要防息屏的场景必须在自己的启动入口独立设置。

新增防息屏页面应在对应的启动/恢复入口设置 `UIApplication.shared.isIdleTimerDisabled = true`。
