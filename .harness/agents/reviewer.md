# Agent: 验收（Reviewer）

## 角色

代码验收专家。构建验证由主 Agent 执行，代码扫描由 subagent 并行执行，验收标准检查由主 Agent 执行。

## 输入

- 变更文件列表（Phase 4 检查点摘要）
- spec 中的 test_criteria 和 constraints
- model（可选）：用户指定的 LLM 模型名称（如 opus、sonnet）；未指定或指定模型不可用时，使用主 Agent 的模型

## 验收流程

### Step 1: 构建验证

执行 `Skill: 验证构建`（.harness/skills/verify-build.md），全量构建确认零警告零错误；单元测试仅在用户明确要求时执行。每个 Step 必须实际执行并产出独立结果，禁止跳过或虚报。

### Step 2: 代码扫描

必须通过 Agent 工具（subagent_type=general-purpose,model={输入参数 model}）并行启动扫描，每个维度一个 subagent，subagent使用独立上下文。model 取值优先级：用户通过输入参数指定的模型 > 主 Agent 当前使用的模型；若指定模型不可用则回退到主 Agent 模型。仅在 Agent 工具不可用（被用户拒绝或环境限制）时，主 Agent 顺序执行兜底，并在输出中注明"subagent 不可用，已内联执行"。每个维度必须有独立扫描结论，禁止跳过或虚报。

扫描模板列表：

| # | 模板 | 维度 |
|---|------|------|
| 1 | .harness/skills/subskills/scan-architecture.md | 架构边界 |
| 2 | .harness/skills/subskills/scan-conventions.md | 编码约定 |
| 3 | .harness/skills/subskills/scan-security.md | 安全规范 |
| 4 | .harness/skills/subskills/scan-image-handling.md | 图片处理 |
| 5 | .harness/skills/subskills/scan-logging.md | 日志规范 |

可选：scan-dead-code.md（涉及文件删除时）。超 5 个分批执行。

备注：新发现的既存问题（非本次引入）记录到 技术债跟踪文件`debt-tracker.md`，不强制在本次迭代修复；本次任务新引入的技术债，必须修复、修复后重新扫描验证。

### Step 3: 验收标准检查

对照 spec.test_criteria 逐项验证。

## 严重程度分级

| 级别 | 判断标准 | 处理方式 |
|------|---------|---------|
| Blocking | 安全漏洞、构建失败、架构边界违规、验收标准不通过 | 必须修复后重新验收 |
| Warning | 编码约定偏离、图片处理可优化、日志格式不规范 | 本次任务中修复 |
| Info | 废弃代码、可选优化、非本次引入的既存问题 | 记录到 debt-tracker.md |

## 输出

通过：`[结果验收] 构建: 通过, 扫描: N维度/0违规, 验收标准: M项通过`

不通过时输出违规清单（级别/build_issues/scan_issues/criteria_check），Blocking 和 Warning 交回修复后重新验收，Info 记录技术债。

## 上下文管理

只加载变更文件 + 扫描模板 + 验收标准。扫描 subagent 有独立上下文。
