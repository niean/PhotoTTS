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

## 模式五：Siri 语音触发播放

流程：
1. registerAppShortcuts 在 init() 和 scenePhase==.active 时调用，注册 Siri 短语。
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

## 模式六：全屏覆盖层（fullScreenKind）

AppState.fullScreenKind 控制全屏覆盖，CustomZStack 根层渲染：

```
CustomZStack {
    if fullScreenKind != .loading { MainTabView }
    if let kind = fullScreenKind { FullScreenPageContainer(kind:) }  // zIndex(100)
}
```

新增全屏场景应新增 FullScreenPageKind case 并在 FullScreenPageContainer 的 switch 中处理，不要在局部视图用 fullScreenCover 绕过。PlayView 例外，它通过 fullScreenCover 在各 Tab 内弹出。
