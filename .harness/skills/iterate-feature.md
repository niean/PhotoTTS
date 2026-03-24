---
name: iterate-feature
description: 人工下发功能需求或修改代码时使用
---

# Skill: 迭代功能

触发：人工下发功能需求或修改代码（新 Task 或同一 Task 内的第 2+ 次迭代）。

本 Skill 采用 7 阶段混合流程：harness（知识库加载）→ superpowers（需求探索 → 设计 → 计划 → 实现）→ harness（验收 → 知识回填 → 总结）。

输出规范：遵守 AGENTS.md "流程合规 > 消息输出格式"中定义的全部规则。

---

## Phase 1: 任务调度
- Agent: Orchestrator
- 按 AGENTS.md "上下文管理"要求，首次加载必须读取 `.harness/knowledge/` 全部文件 + `.harness/prd/`（除 03-prd-specs.md）
- 确认约束与产品方向，启动 Phase 2

## Phase 2: 需求探索与设计 `[GATE]`
- 读取 `.harness/skills/superpowers/brainstorming.md`，按其流程执行到 step 7（Spec review loop）后终止；step 8-9 由本 Phase GATE 和 Phase 3 接管（见"流程控制覆盖"节）
- 核心步骤：探索项目上下文 → 逐一提问理解需求 → 提出 2-3 方案含推荐 → 呈现设计 → 用户确认设计 → 写 spec → spec review loop
- spec 落盘到 `.harness/specs/active/spec-{YYMMDD}-{desc}.md`（按 AGENTS.md 执行计划管理 > Spec 文件模板）
- spec 落盘后，向用户输出需求摘要（目标 + 范围 + 方案 + 验收标准），等待确认
- 用户修正时：更新 spec，输出完整摘要再次确认
- 用户修正 ≠ 用户确认：收到修正后必须重新输出完整摘要并重走 GATE 确认流程，禁止将修正视为确认直接进入 Phase 3
- `[GATE]` spec 落盘后（含修正后重新落盘），必须使用 `ask_followup_question` 向用户请求确认，立即结束当前回复；禁止在同一条回复中继续 Phase 3

检查点：`[Phase 2 需求探索与设计] goal: ..., scope: N 文件, 方案: 已确认`

## Phase 3: 计划制定 `[GATE-ENTRY]`
- `[GATE-ENTRY]` 前置条件：用户已在上一条消息中明确确认 spec；若 Phase 2 在当前回复中刚输出，说明 GATE 被违反，必须停止
- 读取 `.harness/skills/superpowers/writing-plans.md`，按其流程执行到 "Plan Review Loop" 后终止；"Execution Handoff" 由本 Phase 自行执行（见"流程控制覆盖"节）
- plan 落盘到 `.harness/plans/active/plan-{YYMMDD}-{desc}.md`（按 AGENTS.md 执行计划管理 > Plan 文件模板）
- plan 落盘后，向用户提供执行方式选择（Subagent-Driven / Inline Execution），用户选择后进入 Phase 4

检查点：`[Phase 3 计划制定] tasks: N 个, steps: M 步, 执行方式: subagent/inline`

## Phase 4: 代码实现
- 按用户在 Phase 3 选择的执行方式，读取对应的 superpowers 文件并按其流程执行：
  - Subagent-Driven: `.harness/skills/superpowers/subagent-driven-development.md`
  - Inline Execution: `.harness/skills/superpowers/executing-plans.md`
- 按 plan 逐 task 实现，不含 git commit
- build 必须 zero warnings（含 IDE 配置警告、工具级警告）
- TDD 适用范围：Manager/Coordinator/Service/Handler 等可独立测试的逻辑层必须 TDD（failing test → implement → verify）；SwiftUI View、App 生命周期、纯 UI 布局等不要求 TDD，直接实现后通过构建验证即可
- superpowers 行为覆盖：见本文件末尾"superpowers 行为覆盖"节

检查点：`[Phase 4 代码实现] 变更: file1.swift(修改), file2.swift(新增), ...; tasks: N/M 完成`

## Phase 5: 结果验收
- Agent: Reviewer，按 `.harness/agents/reviewer.md` 执行
- 职责边界：Phase 4 per-task review 关注 task 级正确性（spec 合规 + 代码质量），Phase 5 关注项目级约束（架构边界、编码约定、安全规范、图片处理、日志规范）及整体验收标准
- 扫描范围：仅本次变更文件
- 每个 Step 必须实际执行并产出独立结果，禁止跳过或虚报
- 代码扫描必须通过 Agent 工具以 subagent_type=general-purpose、model=opus 并行启动 5 个维度 subagent（架构/编码/安全/图片/日志），每个维度独立输出结论；禁止合并为单个 subagent 或内联执行
- 扫描违规或验收不通过时回到 Phase 4 修复

必须执行的步骤：
1. Step 1 构建验证：执行 `Skill: 验证构建`（`.harness/skills/verify-build.md`），全量构建 + 全量测试，确认零警告零错误
2. Step 2 代码扫描：5 个维度 subagent 并行扫描，每个维度独立输出结论
3. Step 3 验收标准检查：对照 spec 验收标准逐项验证，输出每项通过/不通过

检查点：`[Phase 5 结果验收] 构建: 通过/失败, 扫描: N维度/M违规, 验收标准: K项通过`

## Phase 6: 知识回填
- Agent: Orchestrator
- 按 AGENTS.md 知识回填规则回填 knowledge/（有变化才写，无变化也告知）

## Phase 7: 任务总结
- Agent: Orchestrator
- 自动触发 Skill: 总结任务（`.harness/skills/summarize-task.md`）
- 执行顺序：输出总结报告 -> 归档（spec 移到 `specs/completed/`，plan 移到 `plans/completed/`）-> attempt_completion，在同一条回复中完成
- 总结报告内容通过 `attempt_completion` 的 result 参数承载

---

## superpowers 行为覆盖

本 Skill 调用 superpowers 方法论（brainstorming、writing-plans、executing-plans/subagent-driven-development），但以下 superpowers 指令在本 Skill 中不执行。AI 读取 superpowers 文件时，遇到下列行为一律跳过。

### git 工作流覆盖

全部 Phase 均不执行 git 操作，由用户在任务完成后自行决定提交时机。

| 被跳过的 superpowers 指令 | 来源文件 | 替代行为 |
|--------------------------|---------|---------|
| using-git-worktrees（创建隔离分支） | executing-plans Integration, subagent-driven-development Integration | 在当前分支工作 |
| brainstorming spec commit（"Commit the design document to git"） | brainstorming.md After the Design | spec 落盘但不 commit |
| writing-plans worktree 前置（"should be run in a dedicated worktree"） | writing-plans.md Context | 忽略，在当前分支工作 |
| plan 模板中的 Step 5: Commit 及 "frequent commits" | writing-plans.md Task Structure, Remember | 生成 plan 时省略 commit 步骤 |
| implementer subagent commit（prompt 模板 `[COMMIT_STEP]`） | implementer-prompt.md Your Job | 派发时移除该步骤 |
| finishing-a-development-branch | executing-plans Step 3, subagent-driven-development 末尾 | 收尾由 Phase 5-7 接管 |

### review 工作流覆盖

| 被覆盖的 superpowers 指令 | 来源文件 | 替代行为 |
|--------------------------|---------|---------|
| `[FINAL_REVIEW_STEP]` 全量 final code reviewer | subagent-driven-development 末尾 | 默认跳过，由 Phase 5 五维度扫描接管；识别到该指令后可选择执行 |

### 流程控制覆盖

superpowers 各 skill 之间有自动流转（brainstorming -> writing-plans -> executing），本 Skill 通过 Phase 边界截断这些流转，由 iterate-feature 自行控制阶段衔接。

| 被跳过的 superpowers 指令 | 来源文件 | 替代行为 |
|--------------------------|---------|---------|
| brainstorming step 8-9（User reviews spec + invoke writing-plans） | brainstorming.md Checklist & Process Flow | 由 Phase 2 `[GATE]` 统一接管用户确认，Phase 3 自行读取 writing-plans.md |
| brainstorming "User Review Gate"（spec 写完后让用户 review） | brainstorming.md After the Design | 由 Phase 2 `[GATE]` 统一接管 |
| brainstorming "Visual Companion"（浏览器服务） | brainstorming.md Visual Companion | 跳过，使用纯文本交互 |
| writing-plans "Execution Handoff"（plan 完成后弹出执行方式选择） | writing-plans.md Execution Handoff | 由 Phase 3 负责向用户提供执行方式选择 |
| subagent-driven-development "Never start on main/master" | subagent-driven-development.md Red Flags | 允许在当前分支（含 main）工作，git 操作由用户自行管理 |

---

## 上下文管理

1. Phase 2 brainstorming 在主 Agent 上下文中执行（逐一提问需要对话交互）
2. Phase 3 后仅保留 spec + plan，不保留产品文档原文
3. Phase 4 按 plan 逐 task 加载必要源文件
4. Phase 5 扫描 subagent 有独立上下文
5. 上下文紧张时先压缩检查点摘要再继续
