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
- 按 AGENTS.md "上下文管理"要求分层加载知识库：读取所有文件首行 SUMMARY 建立索引，完整读取任务类型加载矩阵中"功能需求"对应的必读文件
- 确认约束与产品方向，启动 Phase 2

## Phase 2: 需求探索与设计 `[GATE]`
- 读取 `.harness/skills/superpowers/brainstorming.md`，按其流程执行到 step 7（Spec review loop）后终止；step 8-9 由本 Phase GATE 和 Phase 3 接管（见"流程控制覆盖"节）
- 核心步骤：探索项目上下文 → 逐一提问理解需求 → 提出 2-3 方案含推荐 → 呈现设计 → 用户确认设计 → 写 spec → spec review loop
- spec 落盘到 `.harness/specs/active/spec-{YYMMDD}-{desc}.md`（按 AGENTS.md 执行计划管理 > Spec 文件模板）
- spec 落盘后，向用户输出需求摘要（目标 + 范围 + 方案 + 验收标准），等待确认
- 用户修正时：更新 spec，输出完整摘要再次确认
- 用户修正 ≠ 用户确认：收到修正后必须重新输出完整摘要并重走 GATE 确认流程，禁止将修正视为确认直接进入 Phase 3
- `[GATE]` spec 落盘后（含修正后重新落盘），必须使用 `AskUserQuestion` 向用户请求确认，立即结束当前回复；禁止在同一条回复中继续 Phase 3

检查点：`[Phase 2 需求探索与设计] goal: ..., scope: N 文件, 方案: 已确认`

## Phase 3: 计划制定 `[GATE-ENTRY]`
- `[GATE-ENTRY]` 前置条件：用户已在上一条消息中明确确认 spec；若 Phase 2 在当前回复中刚输出，说明 GATE 被违反，必须停止
- 读取 `.harness/skills/superpowers/writing-plans.md`，按其流程执行到 "Plan Review Loop" 后终止；"Execution Handoff" 由本 Phase 自行执行（见"流程控制覆盖"节）
- 核心步骤：读取 spec + 代码 → 拆分 task（含文件结构 + TDD 步骤）→ 写 plan → plan review loop
- plan 落盘到 `.harness/plans/active/plan-{YYMMDD}-{desc}.md`（按 AGENTS.md 执行计划管理 > Plan 文件模板）
- plan 落盘后，确定执行方式（Subagent-Driven / Inline Execution）后直接进入 Phase 4：若用户在输入指令中明确指定了执行方式则遵从；否则 AI 按任务类型自主决策，简单任务使用 Inline Execution、复杂任务使用 Subagent-Driven，无需人工确认。禁止使用 AskUserQuestion 等待确认 -- 本 Phase 无 [GATE] 标记，plan 落盘后必须自主推进

检查点：`[Phase 3 计划制定] tasks: N 个, steps: M 步, 执行方式: subagent/inline`

## Phase 4: 代码实现
- 按 Phase 3 确定的执行方式，读取对应的 superpowers 文件并按其流程执行：
  - Subagent-Driven: `.harness/skills/superpowers/subagent-driven-development.md`（核心：分派独立 task 到 subagent 并行实现，主 Agent 逐 task review）
  - Inline Execution: `.harness/skills/superpowers/executing-plans.md`（核心：主 Agent 按 plan 逐 task 串行实现，每 task 完成后 self-review）
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
- 扫描违规或验收不通过时回到 Phase 4 修复

必须执行的步骤：
1. Step 1 构建验证：执行 `Skill: 验证构建`（`.harness/skills/verify-build.md`），全量构建确认零警告零错误（单元测试仅用户明确要求时执行）
2. Step 2 代码扫描：5 个维度 subagent 并行扫描，每个维度独立输出结论
3. Step 3 验收标准检查：对照 spec 验收标准逐项验证，输出每项通过/不通过

检查点：`[Phase 5 结果验收] 构建: 通过/失败, 扫描: N维度/M违规, 验收标准: K项通过`

## Phase 6: 知识回填
- Agent: Orchestrator
- 按 AGENTS.md 知识回填规则回填 knowledge/（有变化才写，无变化也告知）

## Phase 7: 任务总结
- Agent: Orchestrator
- 自动触发 Skill: 总结任务（`.harness/skills/summarize-task.md`）
- 执行顺序：输出总结报告 -> 归档当前 Task 的文件（spec 移到 `specs/completed/`，plan 移到 `plans/completed/`，不影响其他 Task 的活跃文件）-> 结束任务，在同一条回复中完成

---

## 上下文管理

1. Phase 2 brainstorming 在主 Agent 上下文中执行（逐一提问需要对话交互）
2. Phase 3 后仅保留 spec + plan，不保留产品文档原文
3. Phase 4 按 plan 逐 task 加载必要源文件
4. Phase 5 扫描 subagent 有独立上下文
5. 上下文紧张时先压缩检查点摘要再继续
