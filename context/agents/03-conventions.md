# 约定与约束（实现细节）

本文件是 AGENTS.md 项目规范的实现级补充。通用规则以 AGENTS.md 为准，此处不重复。

---

# 一、UI交互约定

## 页面布局

- 手势：只要顶导左上角有返回按钮，就应实现左边缘滑动返回（注释 `// 手势识别`），参数从 Constants.Gesture 读取。

## Tab 重置约定

- 离开首页（tab0）、消息（tab2）、我的（tab3）时，tabXResetId 自增，视图通过 .id() 销毁重建清空导航栈。
- 制作页（tab1）不参与重置，因制作流程有持续状态。

---

# 二、编码约定

## 图片尺寸规则

- 入队写入：降采样到 2048px（像素），通过 `SessionRecordManager.downsampleImageToMaxPixel`。
- 播放/查看：按需加载，最大 1024pt（点），通过 `SessionRecordManager.loadImage(sessionId:index:maxDimension:)`；预加载相邻页用 `preloadImage`。
- 记录头像：保存时生成 avatar.jpg，最大 96pt。
- 不得绕过降采样直接存原图。

## OCR 结果处理规则

- `Constants.ocrEmptyResultIndicator = "空字符串"` 是系统保留字，表示图片无可识别内容，拼接后需剔除。
- OCR 失败返回空字符串 `""`，保持索引与图片一一对应，不压缩数组。

## 项目本地化配置

- developmentRegion 为 zh-Hans，knownRegions 含 en、zh-Hans、Base。
- App Intents SSU 训练按 developmentRegion 生成语言模型，中文短语必须配合 zh-Hans。

## 配置与常量

所有编译期常量统一收归 Sources/Constants.swift：

- 已有分类：Layout、SessionDetail、ImageDisplay、Gesture、Network、Cache、Camera、VoiceRange、Time、Language、API、APIEndpoints、KeychainKeys、UserDefaultsKeys。
- 新增常量优先归入已有分类；不属于任何分类可新建 struct，命名 PascalCase。
- 不允许在业务文件中硬编码魔法值。
- 运行时可变配置（API 密钥、TTS 音色等）通过 config_local.json + SettingsManager 管理。

---

# 三、质量约定

## 编译规范

- 项目必须零警告（含 Xcode IDE 项目配置警告），每次提交前 xcodebuild build 验证。

## 错误处理约定

- 面向用户：中文自然语言，不含技术细节，通过 Alert/Toast 展示。
- 面向开发者：os.Logger，可含错误码和上下文，禁止输出完整密钥（仅末四位 `key=***abcd`）。
- 异步错误回调切回主线程后再更新 UI。
- 网络超时默认 Constants.defaultTimeout（30s），大文件可用 Constants.Network.resourceTimeout（60s），不允许无超时。

## 日志规范

- 禁止 print()，统一 os.Logger。
- 日志分类定义在 PhotoTTSApp.swift 的 extension os.Logger 中（app/siri/audioPlayer/camera/makeView/appPages/ttsService/networkService/settingsManager），subsystem 统一 "com.photoTTS.PhotoTTS"。
- 级别：debug（调试）、info（里程碑）、warning（非致命）、error（失败）。
- 日志文本禁用 emoji/加粗/斜体，禁止输出敏感字段。

## 线程与并发约定

- UI 更新必须在主线程。
- OCR/TTS/文件IO 在后台线程，完成后 DispatchQueue.main.async 或 @MainActor 切回。
- Coordinator 层用 Swift Concurrency（async/await、TaskGroup）并发 OCR；UI 层以 Combine/@Published + DispatchQueue 为主。
- 取消：Coordinator 持有 currentTask，调 task.cancel()；URLSession 通过 session.invalidateAndCancel()。

## 内存与性能约定

图片加载与缓存：
- 播放用 loadImage 按需加载，缓存 NSCache countLimit=6（当前帧+前后各2帧+1余量），键 "\(sessionId):\(index):\(maxDimension)"。
- 切页 preloadAdjacentImages 预加载前后两张。
- PlayView recordId 路径禁止 getImages() 全量加载；仅 preloadedRecord 路径允许一次性加载。

图片解码（IOSurface 限制）：
- 所有解码必须用 Image I/O CGImageSourceCreateThumbnailAtIndex 直接生成目标尺寸，禁止先解码全尺寸再缩放。
- 入库降采样上限 2048px，确保磁盘无超大原图。

列表页性能：
- 列表只读 metadata.json，不加载 record.json 或图片。
- 头像从磁盘加载预生成 avatar.jpg（96pt），不从原图现场生成。

record.json 存储分离：
- 编码时 imageDataList=[]、audioDataBase64=""，图片和音频独立文件存储。
- 加载时由 SessionRecordManager.loadSession 从文件重组。

调试日志：
- DebugLogManager 基于文件存储，getLatestLogs(lineCount: 50) 从日志文件读取最近 50 行。

## 单元测试约定

- 测试位于 PhotoTTSTests/，按被测模块命名。
- 新增/修改 Manager/Coordinator/Service 时同步补充测试。
- 外部依赖通过协议注入 Mock。
- FunctionalTests/ 端到端测试调用真实 API，CI 中可 XCTSkip。

---

# 四、安全约定

## 密钥存储

- 敏感凭据只通过 Keychain（SettingsManager 封装），键名在 Constants.KeychainKeys。
- config_local.json 中密钥仅用于首次导入（写入 Keychain），运行时从 Keychain 读取。
- UserDefaults 只存非敏感配置，键名在 Constants.UserDefaultsKeys。

## 网络安全

- 所有外部 API 用 HTTPS，不降级 HTTP，不开 ATS 例外。
- API 响应校验 HTTP 状态码和 Content-Type，JSON 解码失败按错误处理。
- OCR 图片经降采样（2048px），不发原图。

## 数据隐私

- 用户数据仅存设备本地 Documents/Sessions/，不主动上传。
- OCR 请求发送降采样图片 Base64，TTS 请求发送纯文本，此外不向外部发送用户数据。
- 导出 zip 由用户自行决定分享去向。
- config_local.json 已加入 .gitignore。
