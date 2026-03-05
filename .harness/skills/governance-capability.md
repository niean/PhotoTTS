# Skill: 治理技能

触发：人工指令，或由 Skill: 治理巡检 的 Step 4 调用。对 .harness/skills/ 和 .harness/subagents/ 进行一轮完整的扫描、清理与提取。

## 步骤

### Step 1 — 读取现状

读取以下内容，了解当前技能体系的全貌：
- AGENTS.md 的 Skills 表
- .harness/skills/ 目录下全部文件
- .harness/subagents/ 目录下全部文件

### Step 2 — 扫描与修复

检查现有 Skills 和 Subagents 是否存在以下问题：
- AGENTS.md Skills 表与实际文件不一致（缺少注册、或注册了已删除的文件）
- 文件格式不符合规范（标题格式、触发说明、步骤编号等）
- Subagent 未被任何 Skill 引用（闲置）
- Skill 引用了不存在的 Subagent 或其他 Skill

列出问题清单，经用户确认后修复。

### Step 3 — 清理与合并

识别可精简的能力：
- 功能重叠或高度相似的 Skills，评估是否可合并
- 功能重叠或高度相似的 Subagents，评估是否可合并
- 长期未使用、已被其他能力覆盖的 Skills 或 Subagents

列出清理/合并候选清单，经用户确认后执行（创建合并文件、删除旧文件、更新引用）。

### Step 4 — 提取新能力

回顾近期 git 提交历史和编码活动（`git log --oneline -20` 等），识别两类候选：

Skill 候选（可复用操作模式）：
- 多次执行的相似流程
- 跨多次 Task 反复出现的步骤组合
- 已有 Skill 未覆盖但频繁发生的操作

Subagent 候选（可并行化检查任务）：
- 多次出现的独立检查维度
- 已有 Skill 中可并行化但尚未拆分为 subagent 的步骤
- AGENTS.md 中新增的约束规则，尚无对应的自动化扫描

列出候选清单，经用户确认后生成文件并注册到 AGENTS.md。

### Step 5 — 输出摘要

如 Step 2~4 均无发现，直接输出"无需变更"。

否则向用户输出变更摘要：修复的问题数、清理/合并的能力数、新增的能力数。
