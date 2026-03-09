# 关键代码模式

项目中反复出现但不易从单个文件推断的模式，供新功能实现时参照。

## 模式一：首页->制作跨 Tab 协调

HomePageView 写入 AppState 标志（openCameraOnNextRecordAppear/openPhotoPickerOnNextRecordAppear），设 selectedTab=1。MakeView 在 .onAppear 和 .onChange(of: selectedTab) 中同时检测并消费（立即置 false）。用户取消且本次从首页发起时自动回 tab0。

陷阱：不能只在 onAppear 消费，Tab 切换时 onAppear 不一定触发（视图可能已存在），必须同时监听 onChange。

## 模式二：PlayView 两种打开路径

两种互斥入参，均通过 .fullScreenCover 打开：
- recordId：已保存记录，后台加载，按需 loadImage，禁止 getImages() 全量加载
- preloadedRecord：未保存制作中记录，图片已在内存，使用 getImages()

关闭：onDismiss 回调（onDisappear 中也调用，支持左滑关闭）；正常播放结束时 PlayHistoryManager 记录。

播放互斥：AppState.isPlayViewActive 全局标志，任意时刻只允许一个记录播放。三个触发点（HomePageView、MakeView.togglePlayback、loadPendingSiriSession）打开前检查，为 true 时拒绝并记录日志；触发时设 true，onDismiss 设 false。

双击手势：FullScreenImageContent 支持 onDoubleTapBackground 回调，PlayView 传入 togglePlayback。通过 optionalDoubleTapGesture 扩展条件添加，handler 为 nil 时不引入单击延迟。

滑动控制：isSwipeDisabled 参数，播放时禁止手动翻页（OnDemand 在 DragGesture.onEnded guard，TabView 叠加 highPriorityGesture 拦截），暂停时允许。自动翻页不受影响。

翻页动画：OnDemand 路径 .transition(.opacity) + .animation(.easeInOut(duration: 0.3), value: currentIndex)，手动/自动翻页均 withAnimation 包裹。

## 模式三：图片按需加载与缓存

用于 PlayView 全屏播放翻页。调用链：FullScreenImageContent(useOnDemand) -> OnDemandImagePage。onAppear 先查 NSCache（countLimit=6），命中同步显示；未命中后台调 loadImage（1024pt），主线程动画更新。切页 preloadAdjacentImages 预加载前后两张。loadImage 内部用 Image I/O 直接生成目标尺寸。

新增全屏图片浏览应复用 FullScreenImageContent + OnDemandImagePage。

## 模式四：OCR 并发分批处理

ImageToSpeechCoordinator.performConcurrentOCR：按 ocr_concurrent_count（config sys 节）分批 chunked，每批 withTaskGroup 并发执行 OCRService.recognizeText。失败返回 ""（保持索引）。每批完成更新进度（OCR 0~70%，TTS 70~100%）。拼接时剔除 ocrEmptyResultIndicator，检查总长度不超 tts_text_max_length。

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
