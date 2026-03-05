# Skill: 回填知识库

触发：人工指令。经过一段时间的功能迭代后，人工触发本 Skill，让 Agent 对比实际代码与知识库文档，修正过时描述并同步 AGENTS.md。

## 步骤

### Step 1 — 读取现状

读取以下内容，了解知识库与实际状态的差异：
- AGENTS.md（当前入口文件）
- .harness/context/agents/ 全部文档（AI 知识库）
- .harness/context/users/ 文档目录（人工定义信息，仅读取目录结构）
- .harness/skills/ 文档目录（Skill 列表）
- .harness/subagents/ 文档目录（Subagent 列表）
- 按需扫描源码目录结构

### Step 2 — 更新 agents/ 知识库

对比实际代码与 .harness/context/agents/ 文档，修正过时的、不符合事实的描述。简化、压缩文档内容，降低上下文负担。

### Step 3 — 提取 AGENTS.md 候选变更

对比 AGENTS.md 内容与实际状态（含 Step 2 的更新），识别需要同步的内容，例如：
- 仓库结构描述与实际文件不一致
- Skills 表中缺少新增 Skill 或包含已删除 Skill
- 知识回填规则与实际知识库文档不匹配
- 上下文知识库索引表与实际文档不一致
- 代码生成、架构边界、质量守护、安全规范等摘要与 03-conventions.md 不同步
- 文件与文档规则需要补充或修正

列出候选变更清单，每项注明：变更位置、当前描述、建议新描述、变更原因。

### Step 4 — 等待人工确认

通过 ask_followup_question 工具向用户展示候选清单。候选清单必须写在 question 参数内部（用户只能看到 question 参数的内容），不要放在 ask_followup_question 调用之外的上下文中。等待用户确认哪些需要落盘，哪些不需要。

### Step 5 — 更新 AGENTS.md

按用户确认的候选项，最小化修改 AGENTS.md：保持既有文风，只更新有实质变化的条目。

### Step 6 — 输出变更摘要

向用户输出：
- agents/ 知识库：修正了什么、压缩了多少
- AGENTS.md：修改了哪几处、变更原因
