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
- 读取 `.harness/skills/superpowers-ref/brainstorming.md`，按其流程执行
- 核心步骤：探索项目上下文 → 逐一提问理解需求 → 提出 2-3 方案含推荐 → 呈现设计 → 用户确认设计
- spec 落盘到 `.harness/specs/active/spec-{YYMMDD}-{desc}.md`（按 AGENTS.md 执行计划管理 > Spec 文件模板）
- spec 落盘后，向用户输出需求摘要（目标 + 范围 + 方案 + 验收标准），等待确认
- 用户修正时：更新 spec，输出完整摘要再次确认
- 用户修正 ≠ 用户确认：收到修正后必须重新输出完整摘要并重走 GATE 确认流程，禁止将修正视为确认直接进入 Phase 3
- `[GATE]` spec 落盘后（含修正后重新落盘），必须使用 `ask_followup_question` 向用户请求确认，立即结束当前回复；禁止在同一条回复中继续 Phase 3

检查点：`[Phase 2 需求探索与设计] goal: ..., scope: N 文件, 方案: 已确认`

## Phase 3: 计划制定 `[GATE-ENTRY]`
- `[GATE-ENTRY]` 前置条件：用户已在上一条消息中明确确认 spec；若 Phase 2 在当前回复中刚输出，说明 GATE 被违反，必须停止
- 读取 `.harness/skills/superpowers-ref/writing-plans.md`，按其流程执行
- plan 落盘到 `.harness/plans/active/plan-{YYMMDD}-{desc}.md`（按 AGENTS.md 执行计划管理 > Plan 文件模板）

检查点：`[Phase 3 计划制定] tasks: N 个, steps: M 步`

## Phase 4: 代码实现
- 读取 `.harness/skills/superpowers-ref/executing-plans.md` 或 `.harness/skills/superpowers-ref/subagent-driven-development.md`，按其流程执行
- 按 plan 逐 task 实现，每个 task 遵循 TDD（failing test → implement → verify），不含 git commit
- build 必须 zero warnings（含 IDE 配置警告、工具级警告）
- 涉及 Manager/Coordinator/Service 变更时同步补充单元测试

检查点：`[Phase 4 代码实现] 变更: file1.swift(修改), file2.swift(新增), ...; tasks: N/M 完成`

## Phase 5: 结果验收
- Agent: Reviewer，按 `.harness/agents/reviewer.md` 执行
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

## 上下文管理

1. Phase 2 brainstorming 在主 Agent 上下文中执行（逐一提问需要对话交互）
2. Phase 3 后仅保留 spec + plan，不保留产品文档原文
3. Phase 4 按 plan 逐 task 加载必要源文件
4. Phase 5 扫描 subagent 有独立上下文
5. 上下文紧张时先压缩检查点摘要再继续
