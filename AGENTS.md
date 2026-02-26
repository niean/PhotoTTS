# AGENTS.md — PhotoTTS

PhotoTTS（拍照阅读）是一款 iOS 应用：拍照或选图，经豆包 OCR 识别文字，再由火山引擎 TTS 合成语音播放，面向 3～10 岁儿童绘本听读。

---

## 仓库结构

```
AGENTS.md           -- AI 知识库入口与操作约束（本文件）
CONTEXT_SPEC.md     -- AI 上下文知识库管理规范
PRODUCT_SENSE.md    -- 产品定位、体验原则与判断准则
PhotoTTS/
  Sources/
    UI/             -- SwiftUI 视图（PhotoTTSApp、HomePageView、MakeView、PlayView 等）
    Core/
      Coordinators/ -- 业务协调（ImageToSpeechCoordinator）
      Handlers/     -- OCR/TTS 服务（OCRService、TTSService）
      Managers/     -- 数据/设置管理（SessionRecordManager、SettingsManager 等）
    Models/         -- 数据模型（SessionRecord、VoiceSettings、APIResponse）
  Resources/        -- 配置（config_local.json）、素材、更新记录
context/            -- AI 知识库（详细说明见下方"上下文知识库"节）
doc/                -- 人工定义的原始信息
  01-prd-baseline.md -- 稳定的产品需求基线
  01-prd-specs.md    -- 原始产品需求规格与演进记录
  02-design.md       -- 概要设计
  09-dev-summary.md  -- 开发总结
PhotoTTSTests/      -- 单元测试
PhotoTTSUITests/    -- UI 测试
```

---

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

---

## 操作约束

以下规则直接生效，无需查阅其他文档：

### 功能迭代约束
- 每次功能迭代，无论是新Task、还是同一Task内的第2+次反馈，必须先读取 CONTEXT_SPEC.md，完全遵守其中`功能迭代工作流`的约定

### 文件与文档
- 不要删除任何项目文件，包括文档、代码等
- doc/ 目录是人工定义的原始信息，AI 可以读取、但不允许自动修改；如遇 doc/ 内容与 AI 知识库（context/）描述冲突，必须提示给用户，经确认后才能修改
- 文档内容禁用 emoji 图标、加粗、斜体等润色，使用普通文字

### 代码生成
- 日志内容禁用 emoji 图标、加粗、斜体等润色，使用普通文字
- 新增页面如果顶导左上角有返回按钮，必须同时实现左边缘手势识别，注释为 `// 手势识别`，参数从 `Constants.Gesture` 读取
- 新增常量优先写入 `PhotoTTS/Sources/Constants.swift`，不要散落在各文件

### 图片处理
- 图片入队前必须降采样到 2048px（使用 `SessionRecordManager.downsampleImageToMaxPixel`）
- 播放时按需加载，最大 1024pt（使用 `SessionRecordManager.loadImage(sessionId:index:maxDimension:)`）
- 不得把原图直接存入 `SessionRecord.imageDataList`

### OCR 结果
- `"空字符串"` 是系统保留字，表示图片无文字内容，不展示给用户，拼接后剔除
- OCR 失败返回 `""`，保持索引与图片一一对应，不压缩数组

### 架构边界
- UI 层不直接调用 OCR/TTS API，通过 `ImageToSpeechCoordinator` 或 Manager
- 全屏页面通过 `AppState.fullScreenKind` 控制，不在局部视图用 `fullScreenCover` 绕过（PlayView 例外）
- 新增 Tab 重置逻辑时，制作页（tab1）不参与重置

---

## 上下文知识库

接到任务时按需查阅 `context/` 目录（不需要全部读完）：

| 文件 | 何时查阅 |
|------|---------|
| CONTEXT_SPEC.md | 了解AI知识库管理规范与功能迭代工作流时 |
| PRODUCT_SENSE.md | 功能迭代前，确认产品定位、体验原则和判断准则 |
| context/01-overview.md | 任何任务开始时，了解项目边界和入口 |
| context/02-architecture.md | 涉及模块新增、依赖关系、跨层调用时 |
| context/03-conventions.md | 涉及代码风格、UI 布局、操作约束时 |
| context/04-glossary.md | 对术语（SessionRecord、fullScreenKind、底导等）不清楚时 |
| context/05-data-boundaries.md | 涉及数据结构、磁盘存储、config 格式、导出格式时 |
| context/06-file-map.md | 确定功能对应哪些源文件时 |
| context/07-key-patterns.md | 实现跨 Tab 跳转、PlayView 打开、图片加载、OCR 并发、全屏覆盖等模式时 |
| doc/01-prd-baseline.md | 实现新功能或页面时，确认功能需求与产品约束 |
| doc/01-prd-specs.md | 需要了解某功能的原始产品需求规格、或处理历史遗留逻辑时 |

---

## 维护

当 Agent 因缺少说明而出错时：
1. 将缺失的说明补充到对应的 context/ 知识库文件
2. 若是普遍性约束，同时在本文件"操作约束"节摘录要点
3. 在上方文档列表中更新对应文件的描述
