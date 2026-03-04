# Skill: 回填-AGENTS更新

触发：人工指令。经过一段时间的功能迭代后，人工触发本 Skill，让 Agent 从知识库和实际代码中自动提取变化，经人工确认后更新 AGENTS.md。

## 步骤

### Step 1 — 读取现状

读取以下内容，了解当前 AGENTS.md 与实际状态的差异：
- AGENTS.md（当前入口文件）
- .harness/context/agents/ 全部文档（AI 知识库）
- .harness/context/users/ 文档目录（人工定义信息）
- .harness/skills/ 文档目录（Skill 列表）
- .harness/subagents/ 文档目录（Subagent 列表）
- 按需扫描源码目录结构

### Step 2 — 提取候选变更

对比 AGENTS.md 内容与实际状态，识别可能需要更新的内容，例如：
- 仓库结构描述与实际文件不一致
- Skills 表中缺少新增 Skill 或包含已删除 Skill
- 知识回填规则与实际知识库文档不匹配
- 上下文知识库索引表与实际文档不一致
- 代码生成、架构边界、质量守护、安全规范等摘要与 03-conventions.md 不同步
- 文件与文档规则需要补充或修正

列出候选变更清单，每项注明：变更位置、当前描述、建议新描述、变更原因。

### Step 3 — 等待人工确认

通过 ask_followup_question 工具向用户展示候选清单（候选内容必须写在 question 参数中，不能写在工具调用之前的文本里，否则用户看不到）。等待用户确认哪些需要落盘，哪些不需要。

### Step 4 — 更新 AGENTS.md

按用户确认的候选项，最小化修改 AGENTS.md：
- 保持既有文风（普通文字，禁止 emoji/加粗/斜体）
- 只更新有实质变化的条目，不改变整体结构
- 摘要类内容（代码生成、质量守护等）以 03-conventions.md 为权威来源

### Step 5 — 输出变更摘要

向用户输出：修改了哪几处、变更原因。
