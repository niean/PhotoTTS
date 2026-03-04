# Skill: 提取-Subagent

触发：人工指令。经过一段时间的 AI Coding 后，人工触发本 Skill，让 Agent 从近期编码活动中发现适合并行化的检查或任务，抽象为新的 Subagent prompt 模板。

## 步骤

### Step 1 — 分析近期活动

回顾近期 git 提交历史和编码活动（`git log --oneline -20` 等），识别适合拆分为 subagent 的场景，例如：
- 多次出现的独立检查维度（如新增的规范类别、新的扫描需求）
- 已有 Skill 中可并行化但尚未拆分为 subagent 的步骤
- AGENTS.md 中新增的约束规则，尚无对应的自动化扫描

### Step 2 — 提出候选 Subagent

列出候选 Subagent 清单，每个候选项包含：
- 名称（用于文件命名）
- 聚焦维度：检查或执行什么任务
- 扫描范围：涉及哪些目录或文件
- 关键检查规则概要
- 预计关联的 Skill（如有）

输出候选清单，等待用户确认哪些需要落盘。

### Step 3 — 读取参考格式

读取 `.harness/subagents/` 目录下 1~2 个现有 prompt 模板文件，确认格式规范：
- 标题：`# Subagent: <名称>`
- 任务描述
- 扫描范围（使用绝对路径）
- 检查规则（逐条编号，每条可判定）
- 输出格式（Markdown 表格模板）

### Step 4 — 生成 Subagent prompt 模板

按用户确认的候选项，在 `.harness/subagents/` 目录下创建 `.md` 文件，文件名格式为 `<功能标识>.md`。内容包含：
- 标题和任务描述
- 明确的扫描范围（绝对路径）
- 逐条检查规则
- 输出格式模板

### Step 5 — 关联 Skill（如需要）

如果该 subagent 被某个 Skill 调用：
- 在对应 Skill 文件的步骤中注明 prompt 模板路径
- 在 Skill 的 subagent 调用表格中新增一行

如果尚无关联 Skill，跳过此步。

### Step 6 — 输出确认

向用户输出：新建文件路径、各 Subagent 摘要、关联的 Skill 变更（如有）。
