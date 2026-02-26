# 关键代码模式

本文档记录项目中反复出现但不易从单个文件推断的"模式"，供实现新功能时参照，避免重复犯错或引入不一致做法。

## 模式一：首页→制作跨 Tab 协调

场景：首页点击"拍照制作"或"选图制作"，需跳转到制作 Tab 并自动打开相机或选图。

实现要点：
1. HomePageView 写入 AppState 标志（openCameraOnNextRecordAppear 或 openPhotoPickerOnNextRecordAppear = true），再设置 selectedTab = 1。
2. MakeView 同时在 .onAppear 和 .onChange(of: appState.selectedTab) 中检测这两个标志。
3. 消费时立即将标志置 false，防止后续 Tab 切换再次触发。
4. 若用户取消相机/选图且此次从首页发起（openedCameraFromHome / openedPickerFromHome = true），关闭后自动回首页（selectedTab = 0）。

陷阱：不能只在 onAppear 里消费，因为 Tab 切换时 onAppear 不一定重新触发（视图可能已存在）；必须同时监听 onChange(selectedTab)。

## 模式二：PlayView 两种打开路径

PlayView 接受两种互斥入参：

- recordId（String?）：已保存记录，onAppear 时后台加载 SessionRecord，再按需加载图片（调用 loadImage）；此路径不会调用 getImages()。
- preloadedRecord（SessionRecord?）：未保存的制作中记录（MakeView 的 currentSessionToPlay），图片已在内存，直接使用 getImages()；仅此路径允许一次性把所有图片加载进内存。

打开方式均为 .fullScreenCover。播放结束或用户关闭后调用 onDismiss，PlayView.onDisappear 中也会调用 onDismiss（支持左滑手势关闭时同步清状态）；PlayHistoryManager 在播放正常结束时记录一次。

## 模式三：图片按需加载与缓存

用于 PlayView 全屏播放时的图片翻页，避免一次性把几十张大图加载进内存。

关键调用链：
- FullScreenImageContent（useOnDemand 路径）渲染 OnDemandImagePage。
- OnDemandImagePage.onAppear：先查 imageLoadCache（NSCache，countLimit=6），命中则同步显示；未命中则后台线程调用 SessionRecordManager.loadImage(sessionId:index:maxDimension:1024pt)，完成后主线程动画更新。
- 切页时 FullScreenImageContent 调用 preloadAdjacentImages，提前把前后两张缓存好，避免切换闪动。
- SessionRecordManager.loadImage 内部用 Image I/O 的 CGImageSourceCreateThumbnailAtIndex 直接生成缩略图，不先解码全尺寸图像。

新增全屏图片浏览功能时应复用 FullScreenImageContent + OnDemandImagePage，不要另起炉灶。

## 模式四：OCR 并发分批处理

ImageToSpeechCoordinator.performConcurrentOCR 的实现：
1. 按 ocr_concurrent_count（来自 config_local.json sys 节）把图片数组分批（chunked）。
2. 每批内用 Swift Concurrency withTaskGroup 并发执行 OCRService.recognizeText。
3. OCR 失败不抛出，返回空字符串 ""，保持索引与图片一一对应。
4. 每批完成后更新进度（0～70%），TTS 阶段占 70～100%。
5. 拼接时剔除 ocrEmptyResultIndicator，检查总长度不超 tts_text_max_length。

扩展 OCR 能力或并发模型时，应在此函数上修改，不要在 UI 层自行实现并发逻辑。

## 模式六：Siri 语音触发播放

场景：用户说「用拍照阅读播放绘本 XX」，Siri 调用 PlaySessionIntent，App 被拉到前台并自动打开 PlayView。

实现要点：
1. PlaySessionIntent（AppIntents 框架）将 sessionId 写入 UserDefaults.standard（key：siriPendingPlaySessionId），并设置 openAppWhenRun = true。
2. PhotoTTSApp（App 根）监听 @Environment(\.scenePhase) 变化，当 phase 变为 .active 时调用 loadPendingSiriSession()。
3. loadPendingSiriSession() 读取并立即清除 UserDefaults 中的 key，后台加载 SessionRecord，主线程赋值 appState.sessionRecordToPlay。
4. WindowGroup 根视图上的 .fullScreenCover(item: $appState.sessionRecordToPlay) 触发 PlayView（preloadedRecord 路径）；PlayView.onDismiss 将 sessionRecordToPlay 置 nil。
5. 若 App 冷启动时启动页（fullScreenKind == .loading）还未结束，延迟 2s 再触发，避免 PlayView 在加载页之前弹出。

模糊匹配规则（SessionRecordEntityQuery.entities(matching:)）：
- 规则1：全名包含 query（兜底）
- 规则2：全名第一个空格之后的内容部分包含 query（跳过日期前缀，如 "26.02.26 贝贝熊-作业的烦恼" afterSpace = "贝贝熊-作业的烦恼"）
- 规则3：内容部分按 "-" 分段后逐段匹配，去除首尾空格后比较（如 "贝贝熊-作业的烦恼" -> ["贝贝熊", "作业的烦恼"]，query "作业的烦恼" 命中第二段）
- 规则4：将内容部分和 query 都去掉 "-" 后再做全文 contains 匹配（如 query "贝贝熊作业的烦恼" 命中 "贝贝熊-作业的烦恼"）

陷阱：AppShortcutsProvider 中每条 phrase 都必须含 \(.applicationName)，否则 appintentsmetadataprocessor 会报 halting error 导致 App Intents 整体失效。

## 模式五：全屏覆盖层（fullScreenKind）

应用内全屏覆盖统一通过 AppState.fullScreenKind 控制，CustomZStack 根层渲染：

```
CustomZStack {
    if fullScreenKind != .loading { MainTabView }
    if let kind = fullScreenKind { FullScreenPageContainer(kind:) }
}
```

FullScreenPageContainer 设置 .zIndex(100) 覆盖底导。新增全屏场景（如全屏预览）应新增 FullScreenPageKind case 并在 FullScreenPageContainer 的 switch 中处理，不要在局部视图内用 fullScreenCover 绕过此机制；PlayView 例外，它通过 fullScreenCover 在各 Tab 内弹出，不经 fullScreenKind。
