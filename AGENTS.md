# AGENTS.md -- PhotoTTS

PhotoTTS（拍照阅读）是一款 iOS 应用：拍照或选图，经豆包 OCR 识别文字，再由火山引擎 TTS 合成语音播放，面向 3~10 岁儿童绘本听读。

---

# 一、通用规范（项目无关）

## Skills（可复用操作）

Skills 是可复用的 AI 操作单元。触发后，AI 读取对应文件、按定义步骤执行。触发方式见下表"触发"列。详细定义见 `skills/` 目录。

| Skill | 触发 | 文件 |
|-------|------|------|
| 功能迭代 | 人工下发功能需求 | skills/功能迭代.md |
| 知识库例行检查和更新 | 人工指令 | skills/知识库例行检查和更新.md |
| PRD基线更新 | 人工指令 | skills/PRD基线更新.md |
| 代码质量扫描 | 人工指令 | skills/代码质量扫描.md |
| 废弃代码清理 | 人工指令 | skills/废弃代码清理.md |
| 构建验证 | 功能迭代完成后自动执行，或人工指令 | skills/构建验证.md |

## 文件与文档

- 除非明确要求，不要主动创建 README 文件
- 不要删除任何项目文件，包括文档、代码等
- context/users/ 目录是人工定义的原始信息，AI 可以读取、但不允许自动修改；如遇 users/ 内容与 AI 知识库（context/agents/）描述冲突，必须提示给用户，经确认后才能修改
- 文档内容禁用 emoji 图标、加粗、斜体等润色，使用普通文字

## 上下文知识库管理

- 每类知识有且只有一个归属文档，不重复维护
- 上下文窗口有限，不需要的文档一律不加载
- 接到任务时按需查阅 context/ 目录（不需要全部读完）

## 维护

当 Agent 因缺少说明而出错时：
1. 将缺失的说明补充到对应的 context/agents/ 知识库文件
2. 若是普遍性约束，同时在本文件"项目规范"中摘录要点
3. 在下方"上下文知识库"文档列表中更新对应文件的描述

---

# 二、项目规范（项目相关）

## 仓库结构

```
AGENTS.md              -- AI 知识库入口、操作约束RULES（本文件）
skills/                -- AI 可复用操作定义（功能迭代、构建验证等）
subagents/             -- Subagent prompt 模板（代码质量扫描等并行任务）
docs/
  HE.md                -- 通用 AI 协作工程方法论（项目无关，可跨项目复用）
context/
  agents/              -- AI 知识库
    PRODUCT_SENSE.md   -- 产品定位、体验原则与判断准则
    01-overview.md     -- 项目概览
    02-architecture.md -- 架构与模块边界
    03-conventions.md  -- 约定与约束（实现细节）
    04-glossary.md     -- 术语表
    05-data-boundaries.md -- 数据与类型边界
    06-file-map.md     -- 功能与文件映射
    07-key-patterns.md -- 关键代码模式
  users/               -- 人工定义的原始信息（AI只读）
    01-prd-baseline.md -- 稳定的产品需求基线
    01-prd-specs.md    -- 原始产品需求规格与演进记录
    08-agents-backfill.md -- 人工回填操作指南
    09-dev-summary.md  -- 开发总结
PhotoTTS/
  Sources/
    UI/                -- SwiftUI 视图（PhotoTTSApp、HomePageView、MakeView、PlayView 等）
    Core/
      Coordinators/    -- 业务协调（ImageToSpeechCoordinator）
      Handlers/        -- OCR/TTS 服务（OCRService、TTSService）
      Managers/        -- 数据/设置管理（SessionRecordManager、SettingsManager 等）
    Models/            -- 数据模型（SessionRecord、VoiceSettings、APIResponse）
  Resources/           -- 配置（config_local.json）、素材、更新记录
PhotoTTSTests/         -- 单元测试
PhotoTTSUITests/       -- UI 测试
```

## 构建与测试

```bash
# 用 Xcode 打开项目
open PhotoTTS.xcodeproj

# 命令行构建（模拟器）
xcodebuild -project PhotoTTS.xcodeproj \
           -scheme PhotoTTS \
           -destination 'platform=iOS Simulator,name=iPhone 16' \
           build

# 运行单元测试
xcodebuild -project PhotoTTS.xcodeproj \
           -scheme PhotoTTSTests \
           -destination 'platform=iOS Simulator,name=iPhone 16' \
           test

# API 配置（首次运行前需要）
cp PhotoTTS/Resources/config_example.json PhotoTTS/Resources/config_local.json
# 然后填入 OCR/TTS 密钥
```

## 知识回填规则

Skill: 功能迭代 step 5 的具体回填目标：
- 架构边界变化 -> 02-architecture.md
- 新增术语 -> 04-glossary.md
- 数据结构或存储格式变化 -> 05-data-boundaries.md
- 新增源文件 -> 06-file-map.md
- 新增跨文件模式 -> 07-key-patterns.md
- 产品方向或判断准则调整 -> PRODUCT_SENSE.md

## 代码生成

- 日志内容禁用 emoji 图标、加粗、斜体等润色，使用普通文字
- 日志输出禁止使用 `print()`，统一使用 `os.Logger`（Apple Unified Logging），分类定义在 PhotoTTSApp.swift 的 `extension os.Logger` 中
- 新增页面如果顶导左上角有返回按钮，必须同时实现左边缘手势识别，注释为 `// 手势识别`，参数从 `Constants.Gesture` 读取
- 新增常量优先写入 `PhotoTTS/Sources/Constants.swift`，不要散落在各文件
- 图片入队前必须降采样到 2048px（使用 `SessionRecordManager.downsampleImageToMaxPixel`）
- 播放时按需加载，最大 1024pt（使用 `SessionRecordManager.loadImage(sessionId:index:maxDimension:)`）
- 不得把原图直接存入 `SessionRecord.imageDataList`
- `"空字符串"` 是系统保留字，表示图片无文字内容，不展示给用户，拼接后剔除
- OCR 失败返回 `""`，保持索引与图片一一对应，不压缩数组

## 架构边界

- UI 层不直接调用 OCR/TTS API，通过 `ImageToSpeechCoordinator` 或 Manager
- 全屏页面通过 `AppState.fullScreenKind` 控制，不在局部视图用 `fullScreenCover` 绕过（PlayView 例外）
- 新增 Tab 重置逻辑时，制作页（tab1）不参与重置

## 质量守护

- 代码提交前必须通过 `xcodebuild build`，零警告（包括代码警告和 Xcode IDE 项目配置警告），不允许遗留任何 Warning
- 新增或修改 Manager / Coordinator / Service 层逻辑时，应同步补充或更新单元测试（PhotoTTSTests/）
- 错误信息分两层：面向用户的提示使用中文自然语言、不含技术细节；面向开发者的日志使用 `os.Logger`，可包含错误码和上下文
- 日志中禁止输出 API Key、Access Key、Token 等敏感字段；如需标识密钥，仅输出末四位（如 `key=***abcd`）
- 网络请求必须设置超时（默认见 `Constants.defaultTimeout`），不允许无限等待
- 异步操作（OCR/TTS/文件IO）必须在非主线程执行，回调结果切回主线程更新 UI
- 图片禁止一次性全量加载到内存；播放和浏览必须按需加载当前帧，并通过有限缓存（NSCache）预加载相邻帧
- 图片解码必须使用 Image I/O 降采样（CGImageSourceCreateThumbnailAtIndex），禁止先解码全尺寸再缩放，否则 IOSurface 分配失败会导致闪退
- 列表页只读 metadata.json，禁止加载 record.json 或图片原数据
- record.json 不存储音频和图片二进制数据，大文件（图片、音频）必须独立存储
- 大数据集合（调试日志、历史记录）加载到内存时必须设置条数上限，不允许全量驻留
- 头像必须在保存时预生成缩略图（avatar.jpg），列表展示时从磁盘加载预生成文件，不得现场从原图生成

## 安全规范

- API Key、Access Key 等密钥只允许存储在 Keychain（通过 `SettingsManager`），不得硬编码在源码中、不得写入 UserDefaults、不得写入日志
- `config_local.json` 已加入 `.gitignore`，包含密钥的配置文件禁止提交到版本库；新增配置文件如含敏感信息，必须同步加入 `.gitignore`
- 所有外部 API 调用必须使用 HTTPS；不得降级为 HTTP，不得在 Info.plist 中开启 App Transport Security 例外
- 发送到外部 API（OCR/TTS）的图片数据必须经过降采样（2048px），不发送原图，减少数据泄露面
- API 响应必须校验 HTTP 状态码和数据完整性，不信任未经校验的外部输入；JSON 解码失败时按错误处理，不静默忽略
- 用户的绘本图片、音频、会话记录仅存储在设备本地（Documents/Sessions/），不主动上传到任何服务器（OCR/TTS 请求除外）

## 上下文知识库

| 文件 | 何时查阅 |
|------|---------|
| context/agents/PRODUCT_SENSE.md | 功能迭代前，确认产品定位、体验原则和判断准则 |
| context/agents/01-overview.md | 任何任务开始时，了解项目边界和入口 |
| context/agents/02-architecture.md | 涉及模块新增、依赖关系、跨层调用时 |
| context/agents/03-conventions.md | 涉及UI交互约定、编码约定、质量约定、安全约定的实现细节时 |
| context/agents/04-glossary.md | 对术语（SessionRecord、fullScreenKind、底导等）不清楚时 |
| context/agents/05-data-boundaries.md | 涉及数据结构、磁盘存储、config 格式、导出格式时 |
| context/agents/06-file-map.md | 确定功能对应哪些源文件时 |
| context/agents/07-key-patterns.md | 实现跨 Tab 跳转、PlayView 打开、图片加载、OCR 并发、全屏覆盖等模式时 |
| context/users/01-prd-baseline.md | 实现新功能或页面时，确认功能需求与产品约束 |
| context/users/01-prd-specs.md | 需要了解某功能的原始产品需求规格、或处理历史遗留逻辑时 |
