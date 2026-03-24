# Harness适配superpowers - 修改记录

## 约束
本文仅供自然人使用，未经人工确认、禁止AI修改。

## 用途
记录 Harness 对 superpowers 原版技能的定制化修改，用于后续 Follow superpowers 版本升级时的合并参考。

---

## 一、全局修改（适用于多个文件）

### 1.1 技能间引用路径重映射
- 原版：技能间使用相对路径引用（如 `./finishing-a-development-branch.md`）
- 定制：统一改为 `.harness/skills/superpowers/` 前缀（如 `.harness/skills/superpowers/finishing-a-development-branch.md`）
- 影响文件：brainstorming.md, writing-plans.md, executing-plans.md, subagent-driven-development.md, systematic-debugging.md, writing-skills.md, requesting-code-review.md

### 1.2 AGENTS.md 调用约束
- 在 AGENTS.md 中添加：禁止主动调起 superpowers 插件（形如 `superpowers:skill-x`），仅在用户明确指令时才可调用
- 这是 Harness 层面的约束，不修改 superpowers 文件本身

---

## 二、逐文件修改

### 2.1 brainstorming.md

| 位置 | 原版 | 定制 | 说明 |
|------|------|------|------|
| Checklist Step 5 | 写 spec 到通用路径 | 写 spec 到 `.harness/specs/active/spec-{YYMMDD}-{desc}.md` | 对接 Harness 执行计划管理 |
| After the Design | 同上 | 同上 | |
| Spec document template | 英文字段（Created, Status, Source） | 中文字段（创建时间, 状态, 任务来源） | 模板本地化 |
| Spec document template | 英文章节名 | 中文章节备注（涉及数据结构变更时、涉及界面变更时） | |
| 未迁移标记 | N/A | `<!-- not migrated: elements-of-style skill -->` | 原版子技能未引入 |

### 2.2 writing-plans.md

| 位置 | 原版 | 定制 | 说明 |
|------|------|------|------|
| Save plans to | 通用路径 | `.harness/plans/active/plan-{YYMMDD}-{desc}.md` | 对接 Harness 执行计划管理 |
| Plan Document Header | 英文字段 | 中文字段（创建时间, 状态, 关联 spec） | 模板本地化 |
| Plan Document Footer | 原版无此节 | 新增变更记录表 + 技术债追踪（引用 debt-tracker.md） | Harness 新增，用于任务追踪 |
| Footer 说明段落 | 原版无 | 新增中文说明段落（任务执行中更新...） | |

### 2.3 requesting-code-review.md

| 位置 | 原版 | 定制 | 说明 |
|------|------|------|------|
| PLAN_OR_REQUIREMENTS 示例 | 通用路径 | `.harness/plans/active/plan-{YYMMDD}-{desc}.md` | 路径重映射 |

### 2.4 brainstorming/spec-document-reviewer-prompt.md

| 位置 | 原版 | 定制 | 说明 |
|------|------|------|------|
| Dispatch after | 通用路径 | `.harness/specs/active/` | |

### 2.5 未修改文件（保持原版）

以下文件未发现定制化修改（除全局路径重映射外）：

- using-superpowers.md
- test-driven-development.md
- test-driven-development/testing-anti-patterns.md
- verification-before-completion.md
- receiving-code-review.md
- dispatching-parallel-agents.md
- finishing-a-development-branch.md
- using-git-worktrees.md
- executing-plans.md（仅路径重映射）
- subagent-driven-development.md（仅路径重映射）
- systematic-debugging/root-cause-tracing.md
- systematic-debugging/defense-in-depth.md
- systematic-debugging/condition-based-waiting.md
- writing-skills/anthropic-best-practices.md
- writing-skills/graphviz-conventions.dot
- writing-skills/render-graphs.js
- writing-skills/persuasion-principles.md
- writing-skills/testing-skills-with-subagents.md

---

## 三、未迁移内容汇总

原版 superpowers 中存在但未引入本项目的子技能/资源：

| 原版资源 | 引用位置 | 说明 |
|----------|---------|------|
| elements-of-style skill | brainstorming.md | 写作风格指南（独立插件，非 superpowers 内置） |

---

## 四、升级操作指南

superpowers 版本升级时，按以下步骤合并：

1. 对比原版 diff，识别新增/修改的文件
2. 对照本文"逐文件修改"表格，保留定制化内容（路径、模板、Footer 等）
3. 检查"未迁移内容"是否有需要新引入的子技能
4. 更新本文档，记录新版本引入的变更

