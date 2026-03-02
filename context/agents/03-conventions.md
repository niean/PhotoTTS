# 约定与约束（实现细节）

本文件是 AGENTS.md 项目规范的实现级补充。通用规则以 AGENTS.md 为准，此处不重复。

---

# 一、UI交互约定

## 页面布局

- 手势：只要顶导左上角支持了返回按钮，就应实现一致的「手势识别」，注释内容为：// 手势识别。
- 手势参数：Constants.Gesture 中有 leftEdgeStartZoneWidth、swipeBackMinTranslation 等，新页面与现有页面保持一致。

## Tab 重置约定

- 离开首页（tab0）、消息（tab2）、我的（tab3）时，`MainTabView` 对应 `tabXResetId` 自增；TabView 内视图通过 `.id(tabXResetId)` 感知变化而销毁重建，清空内部 NavigationStack。
- 制作页（tab1）不参与此重置，因为制作流程有持续状态，不应因 Tab 切换而清空。

---

# 二、编码约定

## 图片尺寸规则

- 拍摄/选图写入：入队前统一降采样到 `Constants.ImageDisplay.saveImageMaxPixel = 2048px`（像素），通过 `SessionRecordManager.downsampleImageToMaxPixel(_:maxPixelLength:)` 执行。
- 播放/全屏查看：按需从文件加载，最大边长限制 `Constants.ImageDisplay.playbackFullScreenMaxDimension = 1024pt`（点），通过 `SessionRecordManager.loadImage(sessionId:index:maxDimension:)` 执行；预加载相邻页用 `preloadImage`。
- 记录头像：保存时生成，最大边长 `Constants.ImageDisplay.recordAvatarMaxDimension = 96pt`，写入 avatar.jpg。
- 不得绕过降采样直接把原图存入 SessionRecord.imageDataList 或写到磁盘，以免大图撑爆内存。

## OCR 结果处理规则

- `Constants.ocrEmptyResultIndicator = "空字符串"` 是系统保留字符，表示 OCR API 认定该图片没有可识别内容；不是真实文字，不应展示给用户，拼接后需用 `replacingOccurrences` 剔除。
- OCR 失败（网络异常等）时返回空字符串 `""`，与空图片保留位置对应，保持索引与图片一一对应关系，不压缩数组。

## 项目本地化配置

- 项目 developmentRegion 设为 `zh-Hans`，knownRegions 包含 `en`、`zh-Hans`、`Base`。
- App Intents 的 SSU（Siri Speech Understanding）训练按 developmentRegion 生成语言模型；中文短语必须配合 `zh-Hans` 作为 developmentRegion，否则 Siri 无法识别中文指令。

## 配置与常量

- 应用级常量与布局、手势、Keychain/UserDefaults 键名集中在 Sources/Constants.swift，新增配置优先在此扩展或使用 config_local.json，避免魔法数字与分散键名。

---

# 三、质量约定

## 错误处理约定

错误信息分两层，面向不同受众：

面向用户的提示：
- 使用中文自然语言，语气平和，不含错误码、类名、HTTP 状态码等技术细节。
- 示例："网络连接失败，请检查网络后重试"、"文字识别未成功，请重新拍照"。
- 通过 SwiftUI Alert 或 Toast 展示，不用 print。

面向开发者的日志：
- 使用 `print` 或 `os.Logger`（已有 `os.Logger.audioPlayer` 等分类），可包含错误码、函数名、上下文变量。
- 示例：`print("OCR 请求失败: status=\(statusCode), sessionId=\(id)")`。
- 禁止在日志中输出完整 API Key / Access Key / Token；如需标识密钥来源，仅输出末四位，格式 `key=***abcd`。

异步错误回调：
- 异步操作（网络、文件 IO）的错误结果必须切回主线程后再更新 UI 或 @Published 属性。
- 网络请求使用 `Constants.defaultTimeout`（30s）作为默认超时；特殊场景（如大文件 TTS）可使用 `Constants.Network.resourceTimeout`（60s），但不允许无超时。

## 日志规范

- 日志文本禁用 emoji、加粗、斜体等格式修饰，使用普通 ASCII/中文文字。
- 日志中禁止输出 API Key、Access Key、Token、密码等敏感字段（见 AGENTS.md 安全规范）。
- 生产级日志使用 `os.Logger`，调试级临时日志使用 `print`；上线前应清理无用的 print。
- 日志示例格式：`"[模块名] 事件描述: key1=value1, key2=value2"`。

## 线程与并发约定

- UI 更新（@Published、@State、SwiftUI 视图修改）必须在主线程执行。
- OCR、TTS、文件 IO 等耗时操作必须在后台线程执行，完成后通过 `DispatchQueue.main.async` 或 `@MainActor` 切回主线程。
- Swift Concurrency（async/await、TaskGroup）用于 Coordinator 层的并发 OCR；UI 层仍以 Combine/@Published + DispatchQueue 为主，两者不混用于同一调用链。
- 网络请求取消：Coordinator 持有 `currentTask: Task<Void, Never>?`，取消时调用 `task.cancel()`；URLSession 任务通过 `session.invalidateAndCancel()` 取消。

## 内存与性能约定

本节记录内存与性能相关的实现细节，规则来源于 prd-specs [260215][260218] 的性能优化迭代。

图片加载与缓存：
- 播放/浏览使用 `SessionRecordManager.loadImage(sessionId:index:maxDimension:)` 按需加载单帧，最大边长 `Constants.ImageDisplay.playbackFullScreenMaxDimension = 1024pt`。
- 缓存使用 NSCache，countLimit=6（当前帧 + 前后各2帧 + 1帧余量），键为 `"\(sessionId)_\(index)"`。
- 切页时调用 `preloadAdjacentImages`，预加载前后两张到缓存，避免翻页闪白。
- PlayView recordId 路径禁止调用 `getImages()` 全量加载；仅 preloadedRecord 路径（未保存的制作中记录）允许一次性加载所有图片到内存。

图片解码（IOSurface 限制）：
- iOS 对单张图片的 IOSurface 分配有硬上限（取决于设备内存），超大图解码会直接导致 `IOSurface creation failed` 闪退。
- 所有图片解码必须使用 Image I/O 的 `CGImageSourceCreateThumbnailAtIndex`，在解码阶段直接生成目标尺寸缩略图，不先解码全尺寸图像再用 CoreGraphics 缩放。
- 入库时降采样上限 `Constants.ImageDisplay.saveImageMaxPixel = 2048px`，确保磁盘上不存在超大原图。
- 历史遗留的超大图片已通过一次性迁移任务（[260218]）修复为 2048px 以内。

列表页性能：
- 会话记录列表只读 `metadata.json`（包含 id、name、createdAt、imageCount、storageSize 等轻量字段），不加载 `record.json` 或图片。
- 列表头像从磁盘加载预生成的 `avatar.jpg`（96pt），不从原图现场生成。保存会话时由 `SessionRecordManager` 自动生成 avatar.jpg；更换头像时同步重新生成。

record.json 存储分离：
- record.json 编码时将 `imageDataList` 写为 `[]`、`audioDataBase64` 写为 `""`，图片和音频分别以独立文件存储（`images/image_N.jpg`、`audio.mp3`）。
- 加载时由 `SessionRecordManager.loadSession` 从独立文件重组回 SessionRecord 对象。
- 这一设计避免 record.json 体积膨胀（几十张图片的 Base64 可达数百 MB），减少 JSON 解码时的峰值内存。

大数据集合加载上限：
- `DebugLogManager`：内存中最多保留最新 50 条日志，超出时丢弃旧条目。
- 播放历史、制作历史：加载时按最近时间排序，内存中保留全量（当前数据量可控）；如未来数据量增长，应引入分页或条数上限。

已知遗留问题：
- 临时播放（preloadedRecord 路径）每次打开 PlayView 可能造成少量不可逆内存增长，疑似 SwiftUI/UIKit 内部缓存未释放。目前影响可控，后续可考虑通过 Instruments 追踪定位。

## 单元测试约定

- 测试文件位于 `PhotoTTSTests/` 目录，按被测模块命名（如 `SettingsManagerTests.swift`、`ImageToSpeechCoordinatorTests.swift`）。
- 新增或修改 Manager / Coordinator / Service 层逻辑时，应同步补充或更新对应的单元测试。
- 测试中需要的外部依赖（网络、文件系统）应通过协议注入 Mock，不依赖真实 API 调用。
- 功能测试（`PhotoTTSTests/FunctionalTests/`）使用真实测试素材（test_image、test_voice），用于端到端验证；这类测试可能依赖 API 配置，CI 环境中可标记为 skip。

---

# 四、安全约定

## 密钥存储约定

- 敏感凭据（API Key、Access Key）只通过 Keychain 读写，使用 `SettingsManager` 封装的 `saveToKeychain` / `readFromKeychain` / `deleteFromKeychain` 方法。
- Keychain 键名定义在 `Constants.KeychainKeys`（如 `doubaoAPIKey`、`ttsAccessKey`），不在业务代码中硬编码字符串。
- `config_local.json` 中的 api_key / access_key 仅用于首次导入（SettingsManager.loadConfig 读取后写入 Keychain），运行时一律从 Keychain 读取。
- UserDefaults 只存储非敏感配置（如 ttsAppId、ttsCluster、voiceSettings、界面偏好），键名定义在 `Constants.UserDefaultsKeys`。

## 网络安全约定

- 所有外部 API 调用使用 HTTPS，不得降级为 HTTP。
- 不在 Info.plist 中添加 NSAppTransportSecurity 例外（NSAllowsArbitraryLoads 等）。
- API 响应必须校验 HTTP 状态码（200-299 为成功，其余按错误处理）和 Content-Type；JSON 解码失败时抛出错误，不静默忽略。
- 发送到 OCR API 的图片数据必须经过降采样（2048px），不发送原始高分辨率图片。

## 数据隐私约定

- 用户的绘本图片、音频、会话记录仅存储在设备本地 `Documents/Sessions/` 目录，不主动上传到任何服务器。
- OCR 请求向豆包 API 发送降采样后的图片数据（Base64）；TTS 请求向火山引擎 API 发送纯文本。除此之外不向外部发送用户数据。
- 导出功能生成的 zip 包由用户自行决定分享去向，应用不参与上传。
- `config_local.json` 已加入 `.gitignore`；新增包含敏感信息的配置文件时，必须同步加入 `.gitignore`。
