<!-- SUMMARY: 编码约定权威源：UI交互/图片尺寸/字体/常量/质量/安全规范，零警告/零Mock/Keychain -->
# 约定与约束（实现细节）

本文件是项目规范约定的权威来源，`.harness/PROJECT.md` "项目规范"各节为摘要引用，以本文件为准。

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

## 字体

- 全项目字体统一通过 `Constants.Fonts` 引用，禁止在视图中硬编码 `.font(.system(size:))` 或 `.font(.headline)` 等
- Constants.Fonts 分三类：语义字体（static let，如 headline/body）、iPad自适应字体（computed static var，内部调 `s()` = `DeviceScale.adaptiveSize`）、固定字体（static let，不随设备缩放）
- 视图私有的动态计算字体（如 `iconSize * 0.6`、`avatarSize`）允许保留在视图内，需加注释说明原因
- 新增字体场景优先复用已有常量，确需新增时按命名规则（驼峰，语义化）添加到 Constants.Fonts

## 常量

- 统一收归 `PhotoTTS/Sources/Constants.swift`，已有分类：DeviceScale/Layout/SessionDetail/ImageDisplay/Gesture/Network/PeerTransfer/Cache/Language/API/APIEndpoints/ServiceDefaults/ErrorInfo/UI/SearchBar/Pagination/HomeCard/Monitor/DebugLog/Playback/KeychainKeys/Identity/UserDefaultsKeys/NotificationNames/Fonts/DefaultSession/CameraTip/GroupDisplay/LLM/EndPicts/Links
- 新增优先归入已有分类；不属于任何分类可新建 struct（PascalCase）
- 禁止业务文件硬编码魔法值
- 运行时可变配置通过 config_local.json + SettingsManager

## 禁止 Mock 造假

生产代码禁止以硬编码假数据冒充真实实现。具体规则：

- 禁止返回硬编码零值/固定值伪装为真实采集结果（如 `return (0, 0)` 冒充网络计数器、`value: 0` 冒充磁盘 IO）
- 系统 API 不可用或受沙箱限制时，必须在代码中明确标注不可用原因（注释 `// [Unavailable]` + 原因），并在返回值或 UI 上体现"不可用"状态（如显示 "N/A"、返回 nil/Optional），禁止静默返回零值让调用方误以为正常
- Stub/占位实现必须满足以下全部条件：(1) 函数名或注释包含 `stub`/`placeholder` 标识；(2) 运行时通过日志（os.Logger warning 级别）输出提示；(3) 返回值使用 Optional nil 或专用枚举 case 表达"未实现"，禁止返回业务合法值
- Code Review 检查项：凡新增采集/监控/统计类函数，必须验证数据来源为真实系统 API 调用，不接受无数据源的常量返回

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
- 分类定义在 PhotoTTSApp.swift `extension os.Logger`（app/audioPlayer/camera/makeView/appPages/ttsService/networkService/settingsManager/ocrService/coordinator/debugLog/sessionRecord/playHistory/backgroundMake/makeHistory/llmService/peerTransfer），subsystem "com.photoTTS.PhotoTTS"
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
- PhotoTTSTests/FunctionalTests/ 端到端测试调真实 API，CI 中 XCTSkip

## 代码扫描

代码扫描（Reviewer 代码扫描能力）发现的问题处理规则：

- **本次变更新引入的问题**：必须修复，修复后重新扫描验证
- **既存问题（非本次引入）**：记录到技术债跟踪文件 `.harness/plans/debt-tracker.md`，不强制在本次迭代修复
- **判定方法**：对比变更前后的代码，若问题代码行未在变更范围内（非新增/修改行），则为既存问题
- **例外情况**：高危安全问题（密钥泄露、注入漏洞等）无论是否本次引入均需立即修复

---

# 四、文件管理约定

- 禁止主动创建 README（包括为新建目录添加 README.md 说明文件）
- 禁止自主删除项目文件；治理/升级等场景允许经用户确认后删除
- 文件名：小写英文 kebab-case，动词-名词语序
- 知识库编号分段：同一目录下按文件性质分段编号（如 knowledge/ 01~05 认知约束类、21~22 工具索引类），新增文件归入对应段的下一个序号
- 执行计划文件落盘到 `.harness/plans/active/plan-{YYMMDD}-{desc}.md`（模板见 `.harness/framework/skills/superpowers/writing-plans.md`），任务完成后移动到 `completed/`
- 命令行超过 10 行时，必须先将脚本写入 `locals/harness_tmp/` 再执行，防止 Terminal 异常阻塞流程；AI 自主维护该目录（创建、清理均无需用户确认）

---

# 五、安全约定

- 密钥：只存 Keychain（SettingsManager），键名 Constants.KeychainKeys；config_local.json 仅首次导入用；UserDefaults 只存非敏感配置
- 网络：全 HTTPS，不降级，不开 ATS 例外；响应校验状态码+Content-Type，JSON 解码失败按错误处理；OCR 图片经降采样不发原图
- 隐私：数据仅存设备本地 Documents/Sessions/；OCR 发降采样图片 Base64，TTS 发纯文本，不发其他用户数据；导出 zip 由用户自行分享；config_local.json 在 .gitignore
