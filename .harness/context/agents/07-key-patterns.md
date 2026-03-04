# 关键代码模式

项目中反复出现但不易从单个文件推断的模式，供新功能实现时参照。

## 模式一：首页->制作跨 Tab 协调

场景：首页点击"拍照制作"或"选图制作"，跳转到制作 Tab 并自动打开相机或选图。

要点：
1. HomePageView 写入 AppState 标志（openCameraOnNextRecordAppear 或 openPhotoPickerOnNextRecordAppear），再设 selectedTab=1。
2. MakeView 在 .onAppear 和 .onChange(of: selectedTab) 中同时检测并消费（立即置 false）。
3. 用户取消且本次从首页发起时，自动回首页（selectedTab=0）。

陷阱：不能只在 onAppear 消费，Tab 切换时 onAppear 不一定触发（视图可能已存在），必须同时监听 onChange。

## 模式二：PlayView 两种打开路径

两种互斥入参：
- recordId：已保存记录，onAppear 后台加载，按需 loadImage，禁止 getImages() 全量加载。
- preloadedRecord：未保存的制作中记录，图片已在内存，使用 getImages()。

均通过 .fullScreenCover 打开。关闭时调用 onDismiss（onDisappear 中也调用，支持左滑关闭）；PlayHistoryManager 在正常播放结束时记录。

播放互斥：AppState.isPlayViewActive 全局标志，任意时刻只允许一个记录播放。三个触发点（HomePageView、MakeView.togglePlayback、loadPendingSiriSession）在打开 PlayView 前检查该标志，为 true 时拒绝并记录日志；触发时设 true，onDismiss 回调中设 false。新增播放触发点必须遵守此防御。

双击手势：FullScreenImageContent 支持可选 onDoubleTapBackground 回调。PlayView 传入 togglePlayback，双击切换暂停/播放。通过 optionalDoubleTapGesture 扩展条件添加双击手势，handler 为 nil 时不引入单击识别延迟。

滑动控制：FullScreenImageContent 支持 isSwipeDisabled 参数。播放时禁止手动左右滑动翻页（OnDemand 路径在 DragGesture.onEnded 中 guard，TabView 路径叠加 highPriorityGesture 拦截），暂停时允许。播放自动翻页不受影响。

翻页动画：OnDemand 路径通过 .transition(.opacity) + .animation(.easeInOut(duration: 0.3), value: currentIndex) 实现平滑淡入淡出。手动滑动和自动翻页均在修改 currentIndex 时用 withAnimation 包裹。

## 模式三：图片按需加载与缓存

用于 PlayView 全屏播放翻页，避免全量加载大图。

调用链：
- FullScreenImageContent（useOnDemand 路径）-> OnDemandImagePage。
- OnDemandImagePage.onAppear：先查 NSCache（countLimit=6），命中同步显示；未命中则后台调 SessionRecordManager.loadImage（maxDimension=1024pt），完成后主线程动画更新。
- 切页时 preloadAdjacentImages 预加载前后两张。
- loadImage 内部用 Image I/O CGImageSourceCreateThumbnailAtIndex 直接生成目标尺寸。

新增全屏图片浏览应复用 FullScreenImageContent + OnDemandImagePage。

## 模式四：OCR 并发分批处理

ImageToSpeechCoordinator.performConcurrentOCR：
1. 按 ocr_concurrent_count（config_local.json sys 节）分批（chunked）。
2. 每批内用 withTaskGroup 并发执行 OCRService.recognizeText。
3. 失败返回空字符串 ""，保持索引对应。
4. 每批完成更新进度（OCR 占 0~70%，TTS 占 70~100%）。
5. 拼接时剔除 ocrEmptyResultIndicator，检查总长度不超 tts_text_max_length。

扩展 OCR 能力应在此函数上修改，不在 UI 层自行实现并发。

## 模式五：Siri 语音触发播放与控制

### 触发播放

流程：
1. registerAppShortcuts 仅在 scenePhase==.active 时调用（首次启动和每次回到前台均触发），注册 Siri 短语。不在 init() 中重复注册，避免 Siri 实体查询导致 getAllSessionMetadata 多次磁盘扫描。
2. PlaySessionIntent 将 sessionId 写入 UserDefaults（siriPendingPlaySessionId），设 openAppWhenRun=true。
3. PhotoTTSApp 监听 scenePhase 变为 .active 时调 loadPendingSiriSession()。
4. loadPendingSiriSession 读取并清除 UserDefaults key，后台加载 SessionRecord，主线程赋值 appState.sessionRecordToPlay。
5. WindowGroup 根视图的 .fullScreenCover(item: sessionRecordToPlay) 触发 PlayView。
6. 冷启动时启动页未结束则延迟 2s 再触发。

模糊匹配规则（SessionRecordEntityQuery.entities(matching:)）：
- 全名包含 query（兜底）
- 跳过日期前缀，取空格后内容部分匹配
- 内容按 "-" 分段逐段匹配
- 去掉 "-" 后全文 contains 匹配

陷阱：AppShortcutsProvider 的每条 phrase 必须含 \(.applicationName)，否则 appintentsmetadataprocessor 报 halting error。

### 播放中控制（暂停/继续/音量）

基于 MPRemoteCommandCenter，无需自定义 AppIntent：

1. PlayView.startPlayback 调用 setupRemoteTransportControls()，注册 play/pause/togglePlayPause 三个远程命令。
2. 远程命令处理器通过 NotificationCenter（Constants.NotificationNames.remotePlaybackCommand）发送 action（"play"/"pause"/"toggle"）。
3. PlayView 通过 .onReceive 监听通知，分发到 resumeIfPaused/pauseIfPlaying/togglePlayback。
4. stopAudio / onPlaybackFinished 调 clearRemoteTransportControls()，移除命令处理器。

效果：Siri "暂停"/"继续"/"播放" 自动路由到 MPRemoteCommandCenter；Siri "调高音量"/"调低音量" 通过系统音频会话自动调节。不向 MPNowPlayingInfoCenter 写入播放信息，避免系统在 APP 之上弹出 Now Playing 控件影响体验。

注意：不支持通过 Siri/控制中心 stopCommand 退出全屏 PlayView（Siri 遮罩期间 SwiftUI 无法可靠处理状态变更以关闭 fullScreenCover），退出播放仅通过 PlayView 内的关闭按钮或播放结束自动关闭。

## 模式七：后台制作（Background Make）

场景：用户发起 OCR+TTS 后可切换 Tab，制作在后台继续运行，完成后更新会话记录。

要点：
1. MakeView.processImages() 调用 BackgroundMakeManager.shared.startMaking(images:)，返回 sessionId。
2. startMaking 先创建草稿会话（saveDraftSession：图片落盘、metadata.makeStatus=making、名称"YY.MM.DD 未命名"），再创建 MakeTask（持有独立 Coordinator）启动处理。
3. MakeView 通过 @State observingTaskId 跟踪当前任务，.onReceive(bgMakeManager.objectWillChange) 触发 syncBackgroundTaskState() 同步进度/结果到本地 @State。
4. 任务完成后 BackgroundMakeManager 在后台调 updateSessionWithResults() 更新 record.json、保存音频文件、设 makeStatus=completed。
5. 失败时删除草稿会话。
6. 重连：切回 Tab 1 时通过 appState.makeTaskIdToReconnect 或自动检测，调 reconnectToBackgroundTask() 恢复 UI 状态。
7. 列表展示：SessionRecordRow 对 isMaking 记录显示"制作中"标签，禁用播放/查看/编辑/导出操作，仅允许删除。

约束：只允许1个后台制作任务（因为制作页面只允许存在1个制作项）。已有活跃任务时 startMaking 返回 nil 拒绝启动新任务。

## 模式六：全屏覆盖层（fullScreenKind）

AppState.fullScreenKind 控制全屏覆盖，CustomZStack 根层渲染：

```
CustomZStack {
    if fullScreenKind != .loading { MainTabView }
    if let kind = fullScreenKind { FullScreenPageContainer(kind:) }  // zIndex(100)
}
```

新增全屏场景应新增 FullScreenPageKind case 并在 FullScreenPageContainer 的 switch 中处理，不要在局部视图用 fullScreenCover 绕过。PlayView 例外，它通过 fullScreenCover 在各 Tab 内弹出。
