# 约定与约束（实现细节）

本文件是项目规范约定的权威来源，AGENTS.md "二、项目规范"各节为摘要引用，以本文件为准。

---

# 一、UI交互约定

- 手势：顶导有返回按钮时实现左边缘滑动返回（注释 `// 手势识别`，参数 `Constants.Gesture`）
- Tab 重置：离开 tab0/2/3 时 tabXResetId 自增，视图 .id() 销毁重建；tab1（制作）不参与

---

# 二、编码约定

## 图片尺寸

- 入队：降采样 2048px（`SessionRecordManager.downsampleImageToMaxPixel`），不存原图
- 播放：按需加载最大 1024pt（`loadImage(sessionId:index:maxDimension:)`），预加载相邻页用 `preloadImage`
- 头像：保存时生成 avatar.jpg 最大 96pt
- 外发 API 须经降采样

## OCR 结果

- `Constants.ocrEmptyResultIndicator = "空字符串"` 是保留字，表示无可识别内容，拼接后剔除
- 失败返回 `""`，保持索引对应，不压缩数组

## 本地化

- developmentRegion: zh-Hans，knownRegions: en/zh-Hans/Base
- App Intents SSU 按 developmentRegion 生成语言模型，中文短语配合 zh-Hans

## 常量

- 统一收归 `Sources/Constants.swift`，已有分类：Layout/SessionDetail/ImageDisplay/Gesture/Network/Cache/Language/API/APIEndpoints/ServiceDefaults/ErrorInfo/UI/SearchBar/Pagination/DebugLog/Playback/KeychainKeys/Identity/UserDefaultsKeys/NotificationNames
- 新增优先归入已有分类；不属于任何分类可新建 struct（PascalCase）
- 禁止业务文件硬编码魔法值
- 运行时可变配置通过 config_local.json + SettingsManager

---

# 三、质量约定

## 编译

零警告（含 Xcode IDE 配置警告、xcodebuild 工具级警告如 destination 匹配歧义），提交前 xcodebuild build 验证。构建命令必须指定 `arch=arm64` 消除 destination 多匹配警告。

## 错误处理

- 用户：中文自然语言，无技术细节，Alert/Toast
- 开发：os.Logger 含错误码，禁止完整密钥（仅末四位 `key=***abcd`）
- 异步错误切回主线程再更新 UI
- 超时：默认 `Constants.Network.requestTimeout`（30s），大文件 `resourceTimeout`（60s），不允许无超时
- 错误分层模式：服务级错误枚举（OCRError/TTSError）实现 LocalizedError，提供双属性：`errorDescription`（用户友好中文，无技术细节）+ `technicalDescription`（供 os.Logger，含错误码和内部信息）；Coordinator 层 ImageToSpeechProcessingError 包装服务错误，errorDescription 委托给内层
- NSError 创建统一使用 `Constants.ErrorInfo.domain` / `Constants.ErrorInfo.defaultCode`，禁止硬编码 domain 字符串

## 日志

- 禁止 print()，统一 os.Logger
- 分类定义在 PhotoTTSApp.swift `extension os.Logger`（app/siri/audioPlayer/camera/makeView/appPages/ttsService/networkService/settingsManager/ocrService/coordinator/debugLog/sessionRecord/playHistory/backgroundMake/makeHistory），subsystem "com.photoTTS.PhotoTTS"
- 级别：debug/info/warning/error
- 文本禁用 emoji/加粗/斜体，禁止输出敏感字段

## 线程与并发

- UI 更新主线程；OCR/TTS/文件IO 后台线程，完成后 DispatchQueue.main.async 或 @MainActor 切回
- Coordinator 层 Swift Concurrency（async/await/TaskGroup）；UI 层 Combine/@Published + DispatchQueue
- 取消：Coordinator 持有 currentTask 调 cancel()；URLSession 用 session.invalidateAndCancel()

## 内存与性能

图片缓存：NSCache countLimit=6（当前帧+前后各2+1余量），键 "\(sessionId):\(index):\(maxDimension)"。切页 preloadAdjacentImages 前后两张。PlayView recordId 路径禁止 getImages() 全量加载；仅 preloadedRecord 路径允许一次性加载。

图片解码：必须 Image I/O CGImageSourceCreateThumbnailAtIndex 直接目标尺寸，禁止先全尺寸再缩放（IOSurface 限制）。入库上限 2048px。

列表性能：只读 metadata.json，不加载 record.json/图片。头像从磁盘 avatar.jpg（96pt）加载。

存储分离：record.json 中 imageDataList=[]、audioDataBase64=""，图片/音频独立文件。加载由 SessionRecordManager.loadSession 重组。

调试日志：DebugLogManager 基于文件存储，getLatestLogs(lineCount: 50) 读最近 50 行。

## 单元测试

- 位于 PhotoTTSTests/，按被测模块命名
- 新增/修改 Manager/Coordinator/Service 时同步补充
- 外部依赖协议注入 Mock
- FunctionalTests/ 端到端测试调真实 API，CI 中 XCTSkip

---

# 四、文件管理约定

- 禁止主动创建 README（包括为新建目录添加 README.md 说明文件）
- 不删除项目文件
- 文件名：小写英文 kebab-case，动词-名词语序
- 执行计划文件落盘到 `.harness/plans/active/plan-{desc}.md`（按 AGENTS.md 执行计划管理 > 计划文件模板），任务完成后移动到 `completed/`

---

# 五、安全约定

- 密钥：只存 Keychain（SettingsManager），键名 Constants.KeychainKeys；config_local.json 仅首次导入用；UserDefaults 只存非敏感配置
- 网络：全 HTTPS，不降级，不开 ATS 例外；响应校验状态码+Content-Type，JSON 解码失败按错误处理；OCR 图片经降采样不发原图
- 隐私：数据仅存设备本地 Documents/Sessions/；OCR 发降采样图片 Base64，TTS 发纯文本，不发其他用户数据；导出 zip 由用户自行分享；config_local.json 在 .gitignore
