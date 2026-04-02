# PROJECT.md -- PhotoTTS

PhotoTTS（拍照阅读）是一款 iOS 应用：拍照或选图，经 OCR 识别文字，再由 TTS 合成语音播放，面向 3~10 岁儿童绘本听读。

---

# Harness 框架适配

本节为 Harness 框架提供项目级配置，框架文件通过 `.harness/PROJECT.md` 直接引用。

## 任务类型加载矩阵

首次加载时，根据任务类型选择性读取知识库文件（所有文件首行 SUMMARY 始终必读）：

| 任务类型 | 必读（完整读取） | 按需读取 |
|---------|----------------|---------|
| 功能需求 | .harness/knowledge/01-overview.md, .harness/knowledge/02-architecture.md, .harness/knowledge/22-file-map.md, .harness/prd/01-prd-sense.md, .harness/prd/02-prd-baseline.md | .harness/knowledge/03-conventions.md, .harness/knowledge/04-data-boundaries.md, .harness/knowledge/05-key-patterns.md, .harness/knowledge/21-glossary.md |
| Bug修复 | .harness/knowledge/01-overview.md, .harness/knowledge/03-conventions.md, .harness/knowledge/22-file-map.md | .harness/knowledge/02-architecture.md, .harness/knowledge/04-data-boundaries.md, .harness/knowledge/05-key-patterns.md, .harness/knowledge/21-glossary.md |
| 治理/扫描 | .harness/knowledge/01-overview.md, .harness/knowledge/03-conventions.md, .harness/knowledge/22-file-map.md | .harness/knowledge/02-architecture.md, .harness/knowledge/05-key-patterns.md |
| 文档维护 | .harness/knowledge/01-overview.md, .harness/knowledge/22-file-map.md | 按涉及文档内容按需读取 |

## 知识回填文件映射

知识回填的回填目标：
- 架构变化 -> .harness/knowledge/02-architecture.md
- 新术语 -> .harness/knowledge/21-glossary.md
- 数据结构/存储变化 -> .harness/knowledge/04-data-boundaries.md
- 新源文件 -> .harness/knowledge/22-file-map.md
- 新跨文件模式 -> .harness/knowledge/05-key-patterns.md
- 产品方向调整 -> 提示用户，人工更新 .harness/prd/01-prd-sense.md 或触发 Skill: 回填产品文档-人工

## 教训库加载路径

本项目教训库分布在两个位置：
- `.harness/framework/lessons/general.md`（Harness 通用教训）
- `.harness/lessons/project.md`（项目教训）

## 构建与测试

### 构建
```bash
xcodebuild -project PhotoTTS.xcodeproj -scheme PhotoTTS -destination 'platform=iOS Simulator,name=iPhone 17 Pro,arch=arm64' build
```

### 单元测试
单元测试执行策略：
- 用户明确要求时：必须执行
- 变更文件包含逻辑层（需测试模块/目录见"质量守护"章节）时：必须执行
- 其他场景：跳过

```bash
xcodebuild -project PhotoTTS.xcodeproj -scheme PhotoTTSTests -only-testing:PhotoTTSTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro,arch=arm64' test
```

## 扫描维度

代码扫描使用的维度及规则来源。下表路径均相对于 `.harness/knowledge/` 目录：

| # | 维度 | 规则来源 |
|---|------|---------|
| 1 | 架构边界 | "架构边界", "质量守护"; 02-architecture.md, 05-key-patterns.md |
| 2 | 编码约定 | "代码生成"; 03-conventions.md |
| 3 | 安全规范 | "安全规范"; 03-conventions.md 安全章节 |
| 4 | 图片处理 | "质量守护" 图片条目, "代码生成" 图片条目, "安全规范" 图片外发条目; 05-key-patterns.md |
| 5 | 日志规范 | "代码生成" 日志条目, "质量守护" 错误分层条目; 03-conventions.md 日志章节 |

可选（涉及文件删除时）：

| # | 维度 | 规则来源 |
|---|------|---------|
| 6 | 废弃代码 | 通用规则（未使用的类型/函数/变量/文件/导入/过期注释）；语言特定排除见 03-conventions.md |

## 项目知识索引

| 文件 | 何时查阅 |
|------|---------|
| .harness/prd/01-prd-sense.md | 功能迭代前，确认产品定位和判断准则 |
| .harness/knowledge/01-overview.md | 任务开始时，了解项目边界 |
| .harness/knowledge/02-architecture.md | 涉及模块新增、跨层调用、全屏控制、数据流向时 |
| .harness/knowledge/03-conventions.md | 涉及编码/UI/质量/安全/文件管理约定细节时 |
| .harness/knowledge/04-data-boundaries.md | 涉及数据结构、存储格式时 |
| .harness/knowledge/05-key-patterns.md | 实现跨文件协作模式时（跨Tab/PlayView/图片加载/OCR/Siri/后台制作/iPad适配/错误分层/防息屏等） |
| .harness/knowledge/21-glossary.md | 对术语不清楚时 |
| .harness/knowledge/22-file-map.md | 确定功能对应源文件时 |
| .harness/prd/02-prd-baseline.md | 确认功能需求与产品约束时 |
| .harness/lessons/project.md | 用户指令或当前根因与 SUMMARY 高度相关时按需读取 |

---

# 项目规范

## 代码生成

以下各节（代码生成、架构边界、质量守护、安全规范）为快速参考摘要，权威定义见 .harness/knowledge/03-conventions.md。

- 日志：禁止 `print()`，统一 `os.Logger`；内容禁用 emoji/加粗/斜体；禁止输出敏感字段（仅末四位 `key=***abcd`）
- 手势：顶导有返回按钮时必须实现左边缘滑动返回（注释 `// 手势识别`，参数 `Constants.Gesture`）
- 字体：全项目字体统一通过 `Constants.Fonts` 引用，禁止硬编码 `.font(.system(size:))`
- 常量：优先写入 `PhotoTTS/Sources/Constants.swift`
- 图片：入队降采样 2048px（`downsampleImageToMaxPixel`）；播放按需加载 1024pt（`loadImage`）；不得存原图
- OCR：`"空字符串"` 是系统保留字，拼接后剔除；失败返回 `""`，保持索引对应
- 禁止 Mock 造假：生产代码禁止硬编码假数据冒充真实实现；系统 API 不可用时必须标注原因并返回 nil/N/A，禁止静默返回零值

## 架构边界

- UI 不直接调 OCR/TTS API，通过 `ImageToSpeechCoordinator` 或 Manager
- 全屏页面通过 `AppState.fullScreenKind` 控制（PlayView 例外）
- 制作页（tab1）不参与 Tab 重置

## 质量守护

- 零警告：`xcodebuild build` 零警告（含 IDE 配置警告、工具级警告），构建命令必须指定 `arch=arm64`
- 测试：新增/修改 Manager/Coordinator/Service 时同步补充单元测试
- 错误分层：用户提示用中文无技术细节；开发日志用 `os.Logger` 含错误码
- 网络：必须设超时（默认 `Constants.Network.requestTimeout` 30s，大文件 `resourceTimeout` 60s）
- 线程：异步操作非主线程，回调切回主线程更新 UI
- 图片内存：禁止全量加载，按需加载 + NSCache 预加载相邻帧；解码必须用 Image I/O 降采样，禁止先全尺寸再缩放
- 列表性能：只读 metadata.json，不加载 record.json 或图片；头像从预生成 avatar.jpg 加载
- 存储分离：record.json 不存二进制，图片/音频独立存储
- 内存上限：集合超过 100 条时必须设上限（如 NSCache countLimit、数组 prefix），具体值定义在 Constants

## 安全规范

- 密钥只存 Keychain（通过 `SettingsManager`，键名 `Constants.KeychainKeys`），不硬编码、不写 UserDefaults、不写日志
- `config_local.json` 已加入 `.gitignore`，含密钥的配置文件禁止入库
- 强制 HTTPS，不降级，不开 ATS 例外
- 发送到外部 API 的图片必须降采样（2048px）
- API 响应必须校验状态码和 Content-Type，JSON 解码失败按错误处理
- 用户数据仅存设备本地（Documents/Sessions/），不主动上传

---

# 项目附录

## 仓库结构

```
AGENTS.md              -- AI 入口（纯路由）
CLAUDE.md              -- Claude Code 入口
.harness/
  PROJECT.md           -- 项目规范入口（本文件）
  framework/           -- 通用能力（详见 FRAMEWORK.md "Framework 目录结构"）
  knowledge/           -- AI 知识库（01~05 认知约束类, 21~22 工具索引类）
  prd/                 -- 产品文档（AI只读：01-prd-sense、02-prd-baseline、03-prd-specs）
  lessons/
    project.md         -- 项目教训（AI自主维护）
  specs/               -- 设计文档
    active/
    completed/
  plans/               -- 实现计划
    active/
    completed/
    debt-tracker.md    -- 技术债追踪
PhotoTTS/
  Sources/
    UI/                -- SwiftUI 视图
    Core/              -- Coordinators、Handlers、Intents、Managers
    Models/            -- 数据模型
  Resources/           -- 配置、素材（打包到 App Bundle）
locals/                -- 本地敏感配置
PhotoTTSTests/         -- 单元测试
PhotoTTSUITests/       -- UI 测试
```

## 知识层级关系

```
Layer 0   AGENTS.md -> FRAMEWORK.md（通用规范+注册表） + PROJECT.md（项目配置+规则摘要）
Layer 1   framework/agents/（5个角色: Orchestrator/Designer/Planner/Coder/Reviewer）
Layer 1.5 framework/workflows/（迭代功能/修复Bug/迭代文档 + harness-ops/治理类）
Layer 2   framework/skills/（harness/ 核心Skill + harness-ops/ 运维Skill + superpowers/ 方法论）
Layer 3   framework/skills/harness/subskills/（扫描模板）
数据层    knowledge/（权威知识） + prd/（产品文档，AI只读） + guides/（方法论） + lessons/（教训）
辅助层    specs/（设计文档） + plans/（执行计划+技术债）
```

引用方向：Layer 0 -> Layer 1/1.5 -> Layer 2 -> Layer 3 -> 数据层。PROJECT.md 摘要引用 knowledge/03-conventions.md（权威源）。
