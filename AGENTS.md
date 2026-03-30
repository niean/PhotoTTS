# AGENTS.md -- PhotoTTS

PhotoTTS（拍照阅读）是一款 iOS 应用：拍照或选图，经 OCR 识别文字，再由 TTS 合成语音播放，面向 3~10 岁儿童绘本听读。

---

# 一、通用规范（项目无关）

## 流程合规

### 任务执行入口（AI-READONLY）

任务开始时首先进行 任务分类和Skill路由（新 Task 或同一 Task 内的第 2+ 次迭代均需分类），必须立即执行以下步骤，禁止跳过：

1. 任务分类：判断任务类型。优先匹配：用户明确指定已注册 Skill 名称（如"治理代码"等）时，直接路由到对应 Skill，跳过步骤 2-3。否则：功能需求或修改代码 -> `Skill: 迭代功能`，Bug修复或异常行为修复 -> `Skill: 修复Bug`，修改文档需求 -> `Skill: 迭代Harness文档`，其它任务按需路由到已注册 Skill 或直接执行
2. 读取 Skill 定义：立即读取对应的 Skill 文件（如 `.harness/skills/iterate-feature.md`）
3. 遵循 Skill 流程：按 Skill 文件定义的 Phase 顺序执行；特别强调，`[GATE]` 标记的 Phase 必须在消息框展示意图、等待人工确认，否则禁止执行后续 Phase

执行约束：
- 必须先读取 Skill 定义，再开始代码实现
- 必须按 Skill 文件定义的 Phase 顺序完整执行，不跳过、不简化、不改编、不拆分、不合并
- 必须遵守 `[GATE]` 门禁（见下方 GATE 规则），在 GATE 点等待用户确认后再继续
- 必须按 Phase 定义的消息输出格式输出，不简化、不改动
- superpowers 插件（形如 `superpowers:skill-x`）仅在用户明确指令时调用，不主动调起


### Phase 门禁（GATE）规则（AI-READONLY）

- `[GATE]` 标记的 Phase 结束后，必须立即结束当前回复，使用 `AskUserQuestion` 工具向用户请求确认；禁止在同一条回复中继续后续 Phase
- `[GATE]` Phase 收到用户修正时：更新内容后必须重新输出完整摘要并重走 GATE 确认流程；用户修正 ≠ 用户确认，禁止将修正视为确认直接进入后续 Phase
- `[GATE-ENTRY]` 标记的 Phase 开始前，必须执行前置条件检查：(1) 上一条用户消息包含明确确认（如"确认""Yes""ok""继续"等），(2) 前置 GATE Phase 不在当前回复中输出。任一条件不满足则停止并提示用户
- 当前 GATE 点：迭代功能 Phase 2 -> Phase 3, 迭代Harness文档 Phase 2 -> Phase 3
- 非 GATE Phase 禁止使用 `AskUserQuestion` 等待用户确认后再继续后续 Phase；AI 应按 Skill 定义自主推进流程


### 受保护章节规则（AI-READONLY）

- 标记为 `AI-READONLY` 的章节，AI 发现其内容存在问题时只能以消息方式提示用户；AI 不得自动修改，也不得索要用户确认后代为修改（防止误授权）

### 消息输出格式（AI-READONLY）

任务开始时声明类型和架构，每个 Phase 使用标题 + 角色标注 + 正文的三行结构。格式如下：

```
任务类型：功能需求；调度架构：多Agent

## Phase 1: 任务调度
[Agent: Orchestrator]
正文内容...

## Phase 4: 代码审查
[Agent: Reviewer (subagent)]
正文内容...
```

- 同一 Task 内第 2+ 次迭代，声明追加：`同一 Task 内第 N 次迭代`
- Phase 名称严格对齐 Skill 定义
- 约束类术语（"硬性门禁""流程违规"等）不输出到用户消息框


## Agents（角色 Agent）

Skill 定义"做什么"，Agent 定义"谁来做"。多 Agent Skill 的每个 Phase 指定执行角色，Phase 间通过"检查点摘要"（不超过 10 行）交接上下文。详细定义见 `.harness/agents/` 目录。

| Agent | 运行形态 | 模板文件 | 职责 |
|-------|---------|---------|------|
| Orchestrator | 主 Agent | .harness/agents/orchestrator.md | 任务路由、流程编排、上下文管理 |
| Designer | 主 Agent | .harness/agents/designer.md | 需求探索、方案设计、spec 产出 |
| Planner | 主 Agent | .harness/agents/planner.md | 计划拆分、plan 产出 |
| Coder | subagent + 主 Agent | .harness/agents/coder.md | 代码实现 |
| Reviewer | subagent + 主 Agent | .harness/agents/reviewer.md | 代码扫描、构建验证、验收 |

## Skills（可复用操作）

触发后读取对应文件、按步骤执行。详细定义见 `.harness/skills/` 目录。

| Skill | 触发 | 文件 |
|-------|------|------|
| 迭代功能 | 人工下发功能需求或修改代码 | .harness/skills/iterate-feature.md |
| 修复Bug | 人工下发Bug修复或异常行为修复需求 | .harness/skills/fix-bug.md |
| 回填知识库 | 人工指令 | .harness/skills/harness-ops/backfill-knowledge.md |
| 从教训回填知识库 | 人工指令 | .harness/skills/harness-ops/backfill-knowledge-from-lessons.md |
| 回填产品文档 | 人工指令 | .harness/skills/harness-ops/backfill-prd.md |
| 迭代Harness文档 | 人工下发修改文档需求 | .harness/skills/iterate-harness-docs.md |
| 治理代码 | 人工指令 | .harness/skills/harness-ops/governance-code.md |
| 验证构建 | 功能迭代完成后自动执行，或人工指令 | .harness/skills/verify-build.md |
| 治理技能 | 人工指令 | .harness/skills/harness-ops/governance-capability.md |
| 提取Harness模板 | 人工指令 | .harness/skills/harness-ops/extract-harness-tpl.md |
| 治理全部 | 人工指令 | .harness/skills/harness-ops/governance-all.md |
| 总结任务 | AI自动触发（任务完成后） | .harness/skills/summarize-task.md |

自动触发：标注"AI自动触发"的 Skill 必须在对应时机自动执行。当前仅 Skill: 总结任务（适用于按迭代功能或修复Bug完整流程执行的任务）。

## Subskills（并行扫描任务）

通过 `use_subagents` 启动，各自独立上下文窗口，由 Reviewer 或 Skill 按需调用。详细定义见 `.harness/skills/subskills/` 目录。

| Subskill | 文件 | 调用方 |
|----------|------|--------|
| 扫描架构边界 | .harness/skills/subskills/scan-architecture.md | Reviewer Step 1, 治理代码 Phase 2 |
| 扫描编码约定 | .harness/skills/subskills/scan-conventions.md | Reviewer Step 1, 治理代码 Phase 2 |
| 扫描安全规范 | .harness/skills/subskills/scan-security.md | Reviewer Step 1, 治理代码 Phase 2 |
| 扫描图片处理 | .harness/skills/subskills/scan-image-handling.md | Reviewer Step 1, 治理代码 Phase 2 |
| 扫描日志规范 | .harness/skills/subskills/scan-logging.md | Reviewer Step 1, 治理代码 Phase 2 |
| 扫描废弃代码 | .harness/skills/subskills/scan-dead-code.md | 治理代码 Phase 2, Reviewer Step 1（可选） |

## 文件与文档

- 禁止主动创建 README；不删除项目文件
- 文件名：小写英文 kebab-case，动词-名词 语序（如 governance-code）；标题和描述使用中文，同样动词-名词 语序
- 命名语言约定：Agent 名称使用英文（Orchestrator、Reviewer）；Skill/Subskill 显示名使用中文（迭代功能、扫描架构边界）、文件名使用英文 kebab-case；消息输出中角色标注使用英文（`[Agent: Orchestrator]`）
- AI 只读目录（修改前必须人工确认）：.harness/agents/、.harness/prd/、.harness/guides/
- prd/ 与 knowledge/ 知识库冲突时，提示用户确认
- 文档禁用 emoji/加粗/斜体，使用普通文字
- 执行计划文件管理详见"执行计划管理"章节
- 引用方向自上而下，下层不反向引用上层具体定义（详见 .harness/guides/00-harness-desc.md 3.4 节）
- .harness/ 下引用项目文件路径时，使用项目根目录相对路径，不使用绝对路径

## 命令执行

- 命令行超过 10 行时，必须先将脚本写入 `locals/harness_tmp/` 再执行，防止 Terminal 异常阻塞流程
- `locals/harness_tmp/` 由 AI 自主维护（创建、清理均无需用户确认），已在 `.gitignore` 覆盖范围内

## 上下文管理

- 首次加载（Task 首条消息）分层加载知识库：
  1. 必读：读取 `.harness/knowledge/`、`.harness/prd/`（除 03-prd-specs.md）和 `.harness/lessons/` 每个文件的首行 `<!-- SUMMARY: ... -->` 注释，建立全局索引
  2. 必读：完整读取 `01-overview.md`（项目概览）+ `22-file-map.md`（文件映射）
  3. 按需：根据任务类型完整读取相关文件（见下方"任务类型加载矩阵"）
- 后续迭代（同一 Task 内），按需查阅 `.harness/knowledge/` 和 `.harness/prd/`，不重复加载已知内容，因为每类知识有且只有一个归属文档、不重复维护
- 多步任务：每步完成压缩为检查点摘要（见下方"检查点摘要模板"），后续只携带摘要；每步只加载必需文件
- 所有步骤均为必选项，禁止因上下文压力跳过；上下文紧张时先压缩已有内容再继续
- 委派产出（subagent、跨 Phase 交接）：产出结构化结论（表格、要点），不搬运原文；需要完整内容时直接读取源文件
- 产出超限时：缩小单次任务范围或拆分为多个子任务，不重试相同范围
- 各 Skill 如有更具体的上下文管理要求，以 Skill 文件为准

### 任务类型加载矩阵

首次加载时，根据任务类型选择性读取知识库文件（所有文件首行 SUMMARY 始终必读）：

| 任务类型 | 必读（完整读取） | 按需读取 |
|---------|----------------|---------|
| 功能需求 | 01-overview, 02-architecture, 22-file-map, 01-prd-sense, 02-prd-baseline | 03-conventions, 04-data-boundaries, 05-key-patterns, 21-glossary |
| Bug修复 | 01-overview, 03-conventions, 22-file-map | 02-architecture, 04-data-boundaries, 05-key-patterns, 21-glossary |
| 治理/扫描 | 01-overview, 03-conventions, 22-file-map | 02-architecture, 05-key-patterns |
| 文档维护 | 01-overview, 22-file-map | 按涉及文档内容按需读取 |

### 检查点摘要模板

Phase 间交接使用结构化检查点摘要（不超过 5 行），标准格式：

```
[Phase N: 名称] 目标: {一句话}; 产出: {文件/决策}; 变更: {file1(修改), file2(新增)}; 状态: {完成/部分完成}; 后续依赖: {下一Phase需要的关键信息}
```

各 Skill 可在此模板基础上定义更具体的字段（如 iterate-feature 的 scope/tasks 字段），但必须保持单行格式、不超过 5 行。

## 执行计划管理

AI 通过 `.harness/specs/` 和 `.harness/plans/` 自主管理设计文档和实现计划（目录结构见"仓库结构"）。

### Spec 与 Plan

- Spec 命名：`spec-{YYMMDD}-{desc}.md`，模板见 `.harness/skills/superpowers/brainstorming.md`
- Plan 命名：`plan-{YYMMDD}-{desc}.md`，模板见 `.harness/skills/superpowers/writing-plans.md`
- Spec 触发：用户显式要求，或影响 3+ 模块/涉及新模块创建时建议产出；小型需求可省略 spec 直接创建 plan
- Spec 是一次性产物，实现完成后持久性知识通过 Phase 5 回填 knowledge/
- 同一窗口内第 2+ 次迭代复用同一计划文件

### 生命周期

同一 Task 允许 1 spec + 1 plan；不同 Task 的文件可在 active/ 中并行。

| 阶段 | 操作 | 规则 |
|------|------|------|
| Phase 1 任务调度 | 检测 active/ | 有则复用；completed/ 中有则移回；均无则 Phase 3 创建 |
| Phase 3 意图确认 | 写入 | spec -> `specs/active/`，plan -> `plans/active/` |
| 任务执行中 | 更新 plan | 更新检查清单、记录变更和技术债 |
| Phase 6/7 任务总结 | 归档 | 状态改 completed，移到 `completed/` |

### 技术债管理

- 新引入的技术债必须在本次任务中解决，禁止拖延
- 新发现的技术债必须立即写入 `plans/debt-tracker.md`（获得 ID），再在计划文件中引用该 ID
- 格式：表格（ID/描述/优先级/来源计划/发现时间/状态）

## 维护

修改约束/规范/规则时，检查 AGENTS.md 全局描述确保无矛盾。Agent 因缺少说明出错时：补充到 .harness/knowledge/，普遍性约束摘录到本文件，更新下方知识库索引。

---

# 二、项目规范（项目相关）

## 仓库结构

```
AGENTS.md              -- AI 知识库入口（本文件）
.harness/
  README.md            -- Harness 工程模板说明
  agents/              -- Agent 角色模板（Orchestrator、Reviewer）
  skills/              -- Skill 定义（迭代功能、回填知识库、构建验证、总结任务）
    harness-ops/       -- Harness 运维类 Skill（治理代码、治理技能、治理全部、提取模板、回填产品文档）
    subskills/         -- Subskill 扫描模板
    superpowers/   -- superpowers 方法论技能（开发方法论，本地适配版）
  specs/               -- 设计文档（WHAT：需求、架构、设计决策）
    active/            -- 当前活跃 spec（可多文件并行）
    completed/         -- 已完成 spec 归档
  plans/               -- 实现计划（HOW：具体步骤、代码、验证命令）
    active/            -- 当前活跃计划（可多文件并行）
    completed/         -- 已完成计划归档（不入 git）
    debt-tracker.md    -- 技术债追踪
  guides/              -- 方法论与参考文档（人工维护）
  lessons/             -- 教训库（AI自主维护：general仅Harness相关、project绑定本项目）
  knowledge/           -- AI 知识库（01~05 认知约束类, 21~22 工具索引类）
  prd/                 -- 产品文档（AI只读：01-prd-sense、02-prd-baseline、03-prd-specs）
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

## 构建与测试

```bash
# 构建（模拟器，arch=arm64 消除 destination 匹配歧义）
xcodebuild -project PhotoTTS.xcodeproj -scheme PhotoTTS -destination 'platform=iOS Simulator,name=iPhone 17 Pro,arch=arm64' build
# 单元测试
xcodebuild -project PhotoTTS.xcodeproj -scheme PhotoTTSTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro,arch=arm64' test
# API 配置（首次）
cp PhotoTTS/Resources/config_example.json locals/config_local.json
```

## 知识回填规则

知识回填 Phase（迭代功能 Phase 6）的回填目标：
- 架构变化 -> 02-architecture.md
- 新术语 -> 21-glossary.md
- 数据结构/存储变化 -> 04-data-boundaries.md
- 新源文件 -> 22-file-map.md
- 新跨文件模式 -> 05-key-patterns.md
- 产品方向调整 -> 提示用户，人工更新 prd/01-prd-sense.md 或触发 Skill: 回填产品文档

## 教训库维护规则

AI 自主维护 `.harness/lessons/`，人工可通过提示或建议触发新增/修正。
教训是原始素材，knowledge/ 是提炼后的权威知识；教训通过人工触发的回填流程沉淀为知识。

- 写入时机：Bug修复完成后，根因非显而易见时，自动提取教训写入；功能迭代中踩坑时同理
- 分级：仅与 Harness 框架相关、不绑定具体语言/框架/项目的通用经验 -> general.md；绑定本项目的具体经验 -> project.md
- 条目格式：`### L/P{序号}: 标题`，含现象/根因/教训/来源四字段
- 编号：general 用 L001 递增，project 用 P001 递增
- 去重：写入前检查是否已有同类教训，有则更新而非新增
- 加载策略：任务启动只读 SUMMARY 索引，不完整加载；仅用户明确指令或当前根因与 SUMMARY 高度相关时按需读取详情
- 回填：人工触发 `Skill: 回填知识库` 时，将已沉淀的教训抽象为通用规则写入 knowledge/，回填后删除原教训条目
- 提取：`Skill: 提取Harness模板` 时 general.md 随模板带走，project.md 留在项目内

## 代码生成

以下各节（代码生成、架构边界、质量守护、安全规范）为快速参考摘要，权威定义见 .harness/knowledge/03-conventions.md。

- 日志：禁止 `print()`，统一 `os.Logger`；内容禁用 emoji/加粗/斜体；禁止输出敏感字段（仅末四位 `key=***abcd`）
- 手势：顶导有返回按钮时必须实现左边缘手势识别（注释 `// 手势识别`，参数 `Constants.Gesture`）
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
- 网络：必须设超时（`Constants.Network.requestTimeout`）
- 线程：异步操作非主线程，回调切回主线程更新 UI
- 图片内存：禁止全量加载，按需加载 + NSCache 预加载相邻帧；解码必须用 Image I/O 降采样，禁止先全尺寸再缩放
- 列表性能：只读 metadata.json，不加载 record.json 或图片；头像从预生成 avatar.jpg 加载
- 存储分离：record.json 不存二进制，图片/音频独立存储
- 内存上限：大数据集合必须设条数上限

## 安全规范

- 密钥只存 Keychain（通过 `SettingsManager`），不硬编码、不写 UserDefaults、不写日志
- `config_local.json` 已加入 `.gitignore`，含密钥的配置文件禁止入库
- 强制 HTTPS，不降级，不开 ATS 例外
- 发送到外部 API 的图片必须降采样（2048px）
- API 响应必须校验状态码和数据完整性，JSON 解码失败按错误处理
- 用户数据仅存设备本地（Documents/Sessions/），不主动上传

## 上下文知识库

| 文件 | 何时查阅 |
|------|---------|
| .harness/prd/01-prd-sense.md | 功能迭代前，确认产品定位和判断准则 |
| .harness/knowledge/01-overview.md | 任务开始时，了解项目边界 |
| .harness/knowledge/02-architecture.md | 涉及模块新增、跨层调用时 |
| .harness/knowledge/03-conventions.md | 涉及编码/UI/质量/安全约定细节时 |
| .harness/knowledge/04-data-boundaries.md | 涉及数据结构、存储格式时 |
| .harness/knowledge/05-key-patterns.md | 实现跨 Tab、PlayView、图片加载、OCR 并发等模式时 |
| .harness/knowledge/21-glossary.md | 对术语不清楚时 |
| .harness/knowledge/22-file-map.md | 确定功能对应源文件时 |
| .harness/prd/02-prd-baseline.md | 确认功能需求与产品约束时 |
| .harness/guides/00-harness-desc.md | 了解 Harness 体系描述时 |
| .harness/guides/01-harness-ops.md | 了解 Harness 运维操作时 |
| .harness/guides/02-harness-dev.md | 了解 Harness 开发流程时 |
| .harness/lessons/general.md | 用户指令或当前根因与 SUMMARY 高度相关时按需读取 |
| .harness/lessons/project.md | 用户指令或当前根因与 SUMMARY 高度相关时按需读取 |
