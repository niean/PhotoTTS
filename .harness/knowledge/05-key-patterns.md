<!-- SUMMARY: 关键模式：跨Tab协调/PlayView横竖屏/图片按需加载/OCR并发/全屏覆盖/多任务后台制作(OCR闸门)/默认会话保护/iPad适配/错误分层/防息屏/日志双写/播放记录传输/传输空间预检 -->
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

### 多段音频连续播放
PlayView 通过 `PlaybackTimeline` 将多个 `TTSAudioSegment.duration` 抽象成统一全局时间轴，再把全局时间映射为“当前段索引 + 段内时间”。段结束时自动切到下一段继续播放，进度条、自动翻页、暂停后手势翻页都始终基于全局时间工作，因此用户感知仍是一条连续朗读。旧记录 `audioSegments` 为空时回退到单 `AVAudioPlayer` 路径。

### 要点媒体视觉层
要点虚拟页的 EndPicts 媒体由 PlayView 在记录进入播放后预加载并且每条记录只消费一次轮询队列，PlayerImageView 只渲染 PlayView 传入的 highlightsImage 或 highlightsPlayer。图片按播放全屏尺寸降采样；视频使用静音 AVPlayer 预先等待 ready，要点 TTS 段覆盖虚拟页索引时，如视频未 ready 则延迟该段 TTS 启动，ready 后同步启动 TTS 与静音循环视频。AVPlayer 必须 isMuted=true，不展示系统控制，不接管音频会话；TTS 的 AVAudioPlayer 仍是唯一有声播放源。暂停/恢复、进度跳转、连播切换或退出视图时，PlayView 负责同步暂停/seek 视频并移除 KVO、循环 observer 与 player。

要点媒体池变化由 SessionRecordManager 重置轮询队列，并通过 Constants.NotificationNames.endPictQueueDidReset 携带 direction 通知管理页队列子视图刷新。通知必须在主线程发布；EndPictQueueSectionView 只响应 direction 匹配的通知，避免横向/纵向队列互相刷新。

### 控制层
PlayerControlLayer 悬浮在图片之上（isOverlayVisible 控制显隐），通过回调与 PlayView 交互。用户横屏 bottom-left：播放/暂停 + 进度条（PlayerProgressBar）。用户横屏 top-right：退出 + "播完本集"开关（autoStopEnabled，默认开启）。

### 连播队列
queueRecordIds 参数（默认空），由 HomePageView 根据播放计划开关和记录是否在计划内选择不同策略：
- 播放计划关闭或记录不在计划内：queueRecordIds = [id]（仅单条播放）
- 播放计划开启且记录在计划内：通过 buildPlanQueue 构建（仅包含排序在起始记录之后的播放计划内记录，todoRecordIds 来自首页播放计划排序逻辑）
播完后 advanceToNextRecord：过渡页面 -> 预加载 -> 自动播放。MakeView 不传队列。UI 文本显示为"计划内连播"。PlayHistoryManager 记录播放后发送 playHistoryDidUpdate，HomePageView 需刷新可见卡片播放统计并重算播放计划状态，避免首页卡片播放次数和计划黄底依赖 Tab 重建才更新。

### 播放互斥
AppState.isPlayViewActive 全局标志，任意时刻只允许一个记录播放。三个触发点打开前检查，为 true 时拒绝。

### 手势分层隔离
底层 Color `.simultaneousGesture(DragGesture)` 响应滑动，`.onTapGesture` 响应单击/双击。图片层 allowsHitTesting(false)。控制层可见时两层隔离：(1) 底层 guard `!isOverlayVisible`；(2) 控制层 `.contentShape(Rectangle())` 阻止穿透。滑动方向受 animationStyle 管控。浮层 3s 无操作自动隐藏。

### 翻页动画
AnimationStyle 枚举控制方向（rightToLeft/topToBottom），@State isForwardTransition 记录方向。.transition 根据 (animationStyle, isForwardTransition) 二维组合选择插入/移除边缘。.animation(.easeInOut(duration: 0.3)) 驱动。

## 模式三：图片按需加载与缓存

用于 PlayView 全屏播放翻页。调用链：FullScreenImageContent(useOnDemand) -> OnDemandImagePage。onAppear 先查 NSCache（countLimit=6），命中同步显示；未命中后台调 loadImage（1024pt），主线程动画更新。切页 preloadAdjacentImages 预加载前后一张。loadImage 内部用 Image I/O 直接生成目标尺寸。

新增全屏图片浏览应复用 FullScreenImageContent + OnDemandImagePage。

## 模式四：OCR 并发分批处理

ImageToSpeechCoordinator.performConcurrentOCR：按 ocr_concurrent_count（config sys 节）分批 chunked，每批 withTaskGroup 并发执行 OCRService.recognizeText。失败返回 ""（保持索引）。每批完成更新进度（OCR 0~50%，LLM 50~70%，TTS 70~100%）。拼接时剔除 ocrEmptyResultIndicator，检查总长度不超 tts_text_max_length。

扩展 OCR 应在此函数修改，不在 UI 层自行并发。

## 模式六：全屏覆盖层（fullScreenKind）

AppState.fullScreenKind 控制，CustomZStack 根层渲染：fullScreenKind != .loading 时显示 MainTabView，有 kind 时叠加 FullScreenPageContainer（zIndex 100）。

新增全屏场景加 FullScreenPageKind case + FullScreenPageContainer switch 处理。PlayView 例外（通过 fullScreenCover 弹出）。

## 模式七：多任务后台制作 + OCR 跨任务串行闸门

BackgroundMakeManager 以 `tasks: [String: MakeTask]` 字典按 sessionId 索引多个并发任务，上限 `Constants.BackgroundMake.maxConcurrentTasks`（默认 10）。`hasCapacity` 判定是否可再启动；`activeTaskCount` 只统计 `!isCompleted` 任务（完成/失败不占额）。`task(for:)` 按 id 精准定位（含已完成供 UI 消费结果），`activeTask(for:)` 仅返回未完成任务，`removeTask/cancelTask` 按 id 原子清理。

启动流程：MakeView.processImages() 调 `startMaking(images:startingFrom:...reuseSessionId:)` 返回 sessionId。startMaking 先校验 `reuseSessionId` 指向的任务是否仍活跃（是则拒绝重入）、再校验 `hasCapacity`，通过后创建 MakeTask（持有独立 Coordinator，`ownerTaskId=sessionId`）写入 tasks 字典；重 I/O（草稿保存 + jpegData 转换 + Coordinator 启动）移到 `DispatchQueue.global(qos: .userInitiated)`，主线程立即返回。

OCR 跨任务串行：独立 `actor OCRGlobalSerialGate`（Core/Handlers/Image/OCRGlobalSerialGate.swift）持有 FIFO 队列。`ImageToSpeechCoordinator.performConcurrentOCR` 首行 `await OCRGlobalSerialGate.shared.acquire(taskId: ownerTaskId)`，`defer { Task { await release(taskId:) } }` 保证抛错/取消路径释放。单任务内仍按 `ocr_concurrent_count` 分批并发；跨任务 OCR 阶段整体互斥，满足 OCR API 并发配额限制。LLM/TTS 不获取闸门，跨任务自由并行。

TTS 分段制作：`ImageToSpeechCoordinator.buildTTSSegments` 以单张图片文本为最小原子，按 `Constants.TTS.segmentCharacterLimit` 聚合多个 OCR 段，并为每段分配稳定 `sequenceNumber`。`synthesizeSegmentedSpeech` 再按 `Constants.TTS.segmentConcurrentLimit`=5 分批并发调用 TTS；日志必须包含段编号、图片范围、字符数、耗时和成功/失败状态。进度通过 `StageResults.ttsSegmentCount/ttsCompletedSegmentCount/ttsCurrentSegmentNumber/...` 透传到 `BackgroundMakeManager.IntermediateResults`，MakeView 展示“音频分段 X/Y”和当前图片范围。

前台绑定：MakeView 通过 `@State observingTaskId` 绑定当前前台任务，`.onReceive(bgMakeManager.objectWillChange)` 同步进度/结果。新发起任务后 `observingTaskId = sessionId` 立即覆写；从管理页点"制作"按钮切前台，经 `appState.makeTaskIdToReconnect` 或 `sessionIdToLoadIntoMake` 路径触发 `reconnectToBackgroundTask()`。其中，管理页对活跃 `isMaking` 记录的左滑按钮为"前台"，写入 `makeTaskIdToReconnect`；未完成但非活跃记录仍走"制作"按钮，写入 `sessionIdToLoadIntoMake`。任意时刻制作页仅观察 1 个前台任务，其它任务在后台继续运行，通过管理页记录卡"制作中 XX%"展示（`task(for: metadata.id).progress` 按 id 精准匹配）。

前台隔离：重连后台任务时，MakeView 会先清理 `failedSessionId`、错误态、OCR/TTS 结果和中间结果等前台态，再按当前 `sessionId` 从草稿记录恢复图片并同步进度。页面上的取消、继续制作、重试等操作都只以当前 `observingTaskId` 为目标，不应影响其它后台任务。

入口：管理页（SessionRecordListView）顶导右上角"+"菜单提供"拍照制作/选图制作"作为新任务入口，通过 `appState.openCameraOnNextRecordAppear` / `openPhotoPickerOnNextRecordAppear` 切到制作 Tab 并弹起相机/选图；首页已无制作入口。

完成/失败持久化：完成后后台 `updateSessionWithResults` 更新 record.json/音频/makeStatus=completed，随后 addMakeEvent 写入制作历史事件（直接调用，绕过 recordSave 的名称过滤；loadEntries 聚合时按当前名称过滤）。失败时保留草稿并标记 `makeStatus=incomplete`（通过 updateDraftMakeStatus），不删除草稿；取消时删除草稿。

列表展示：列表中 isMaking 记录显示"制作中"标签，isIncomplete 记录显示"未完成"标签。incomplete 记录允许查看/编辑/重新制作/删除，禁止播放；首页不展示 incomplete 记录（getSessionMetadataPage excludeIncomplete 参数）。

再次制作：管理 Tab 点击"制作"按钮调 loadRecordIntoMake(sessionId:)，从 SessionRecord 还原全量状态（图片/OCR/LLM/TTS 音频/IntermediateResults），设置 isProcessing=true + currentOperation="再次制作" + processingProgress=实际完成进度，不调用 onImagesChanged()、不自动触发制作。用户通过更多菜单选择 OCR/LLM/TTS 环节手动触发。进度计算：有音频1.0/仅OCR+LLM0.7/仅OCR0.5/无OCR0.0。

## 模式九：默认会话只读保护

内置默认会话（Constants.DefaultSession.id）除播放外禁止所有操作，三层协防：

1. Model 层：SessionRecordMetadata.isDefault 计算属性（id == Constants.DefaultSession.id），UI 层统一判断入口
2. UI 层：SessionRecordListView 构建 SessionRecordRow 时，isDefault 为 true 则除 onLoad（播放）外所有闭包传 nil（onView/onEdit/onExport/onDelete/onLoadToMake），更多菜单自动隐藏
3. Manager 层：SessionRecordManager.updateSession/exportSession 开头拦截默认会话（isBundledDefaultSession），返回失败 + 警告日志；loadAllSessionHistories 跳过默认会话，使其不出现在播放历史和制作历史中

新增默认会话限制应在这三层同步添加防护。

## 模式十：iPad 自适应尺寸（DeviceScale）

Constants.DeviceScale 提供 iPadScale 和 adaptiveSize 函数，iPad 上将 iPhone 基准值乘以比例系数。

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

覆盖范围：主要 UI 视图和组件（PlayView/MakeView/SettingsView/HomePageView/SessionRecordListView/MakeHistoryView/PlayHistoryView/DebugLogView/CustomNavigationBar/MeTabView/SessionRecordDetailView/DeviceTransferView/TransferReceiverModifier/PaginationControl/LandscapeTipOverlay/EndPictManagementView/PlaybackSettingsView/RecordAnalysisView/RealTimeMonitorView/CoverEditView/SessionSearchBar 等），新增 UI 文件应沿用同一模式。

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

## 模式十二：日志双写（os.Logger + DebugLogManager）

os.Logger 在非调试环境（设备独立运行、不连接 Xcode）下，`.info` 和 `.debug` 级别日志不输出到 stderr，导致 DebugLogManager 的 stderr 管道捕获机制无法采集这些日志。

双写机制：关键服务通过 `logInfo`/`logError`/`logWarning`/`logDebug` 辅助方法，同时写入 os.Logger（供 Xcode 控制台）和 `DebugLogManager.shared.directLog()`（直写日志文件，绕过管道）。

去重：directLog 写入时将消息存入环形缓冲区（容量 50），processLogData 在管道捕获到相同消息时检查缓冲区并跳过，防止调试环境下重复。

覆盖范围：TTSService（两个实现类 + Factory）、NetworkService、OCRService（+ Factory）、LLMService（DoubaoLLMService + OpenAILLMService + Factory）、ImageToSpeechCoordinator。

## 模式十三：播放记录传输（复用传输基础设施）

设备间传输复用现有 PeerTransferManager 的 MultipeerConnectivity 基础设施，通过 TransferMode 枚举区分 full / fullWithStats / playOnly 三种模式，避免新增独立的传输通道。

调用链：SessionRecordListView "更多" 菜单 -> 选择"传输播放记录" -> 设置 showPlayOnlyTransfer=true -> DeviceTransferView(transferMode: .playOnly) -> PeerTransferManager.invitePeerPlayOnly() -> 发送端打包 history.json（SessionRecordManager.packageHistoryFilesOnly） -> 接收端收到后识别 playOnly 模式 -> 解包覆盖本地 history.json（SessionRecordManager.applyHistoryPackage） -> 完成提示文本按模式区分（TransferReceiverModifier 根据 receivedTransferMode 切换文案）。

关键设计：
- TransferInvitationContext 携带 mode、totalSize 和 sessionIDs，随邀请信令传递给接收端；totalSize 由发送方邀请前按 TransferMode 预估，接收端在 didReceiveInvitationFromPeer 中设置 receivedTransferMode 并生成 StorageCheckResult
- full/fullWithStats 模式发送端自动去重：接收方通过 TransferConflictDecision 回传 existingIDs，发送方在 didReceive data 回调中过滤后仅打包不存在的记录；全部重复时直接完成不传输；决策超时（Constants.PeerTransfer.decisionTimeout）回退全量传输
- 接收方空间预检失败时不走正常接收：UI 只显示“确定”，PeerTransferManager.confirmInsufficientStorageInvitation 会短暂接受 MCSession，发送 TransferControlMessage.storageInsufficient 后 teardown，发送方收到后展示接收方剩余空间 X/需要 Y 并阻断打包
- 接收方无法读取剩余空间时 availableBytes=nil，StorageCheckResult.isEnough=true，UI 提示“已跳过可用空间检查”并保留正常接收/拒绝按钮
- 发送方处理 storageInsufficient 控制消息必须校验当前处于发送等待状态，且消息来源等于 pendingSendPeer，避免非当前 peer 终止传输
- full 模式传输完整记录但不保留播放统计；fullWithStats 传输完整记录并保留播放统计；playOnly 仅传输播放历史
- playOnly 模式发送端始终传输所有记录（不跳过重复），由接收端覆盖本地历史
- 发送端 playOnly 模式下仅打包 .json 文件（不传输图片/音频，体积显著减小）
- 接收端 didFinishReceivingResourceWithName 中按模式分流：full/fullWithStats 走完整解包流程（重复 session 仅覆盖 history.json），playOnly 走 applyHistoryPackage 覆盖本地历史
- full/fullWithStats 模式的完整记录判断优先依赖导出包或传输快照中的 `integrity.json`：该文件的职责就是供导入、接收时做完整性校验，校验清单覆盖目录内全部文件 MD5（不含自身）；接收到本地后会删除该文件，本地 `Documents/Sessions/{id}/` 仍以结构检查和业务文件为准
- 接收方通过 receiverExistingSessionIDs 在接受邀请时保存本地已有 sessionID，供传输完成后 applyHistoryPackage 使用（pendingInvitation 在接受后即被清除）
- cancelTransfer() / reset() 时清空 currentTransferMode 和 receiverExistingSessionIDs，先 reject 未处理的 pendingInvitation 再置 nil（避免发送方等待超时），同时重置 isIdleTimerDisabled
- 接收方 didReceiveInvitationFromPeer 中检测 transferState 为 .completed/.failed 时，自动清理 stale 状态（teardownSession + createSession + 状态重置），确保同一 MCPeerID 可重新连接
- DeviceTransferView.onDisappear 中 reset() 后延迟重启 startAdvertising()，确保设备可被附近设备发现

涉及文件：PeerTransferManager.swift（TransferMode / mode 字段 / invitePeerWithStats / invitePeerPlayOnly / sendPlayHistory / 模式分支）、SessionRecordManager.swift（packageHistoryFilesOnly / applyHistoryPackage）、SessionRecordListView.swift（菜单入口）、DeviceTransferView.swift（transferMode 参数）、TransferReceiverModifier.swift（按模式切换 UI 文案）。

新增设备间数据同步场景应优先复用 PeerTransferManager 传输通道，通过扩展 TransferMode 或新增上下文字段区分，避免另起独立的 MCP 连接。
