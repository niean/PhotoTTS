# Skill: 治理技能

触发：人工指令，或由 Skill: 治理全部 Step 2 调用。对 .harness/agents/、skills/、subskills/ 进行扫描、清理与提取。

本 Skill 采用多 Agent 编排，每个 Step 指定执行角色。Step 间通过"检查点摘要"（不超过 10 行）交接上下文。

输出规范：遵守 AGENTS.md "流程合规 > Agent 架构声明与角色标注"中定义的全部规则。

## 结构同步规则

.harness/ 文件形成相互引用体系。Step 2 必须检查结构同步性：目录枚举、AGENTS.md 注册表、能力类别引用是否与实际 .harness/ 目录一致。

## 步骤

### Step 1 -- 读取现状
- Agent: Orchestrator
- 读取 AGENTS.md 注册表 + .harness/agents/、skills/、subskills/ 全部文件

### Step 2 -- 扫描与修复
- Agent: Reviewer（扫描） -> 用户确认 -> Coder（修复）
- 检查：注册表与实际文件不一致、格式不规范、闲置 Agent/Subskill、引用不存在的实体、目录枚举不同步、引用方向违反 AGENTS.md 规则（反向引用上层、使用绝对路径）

### Step 3 -- 清理与合并
- Agent: Reviewer（识别） -> 用户确认 -> Coder（执行）
- 识别：功能重叠可合并的 Agents/Skills/Subskills、已被覆盖或长期未用的能力

### Step 4 -- 文档压缩
- Agent: Coder（压缩） -> Reviewer（反馈补偿） -> 用户确认 -> Coder（修复）
- 压缩：对 .harness/ 文档提炼、简化、消除冗余，维持 AI 可理解性和信息量
- 反馈补偿：压缩完成后，逐文件对比原文与压缩版，识别被舍弃的特殊标注事项，按影响分级（规则例外/触发条件 > 行为差异 > 实现细节），打印清单到消息框，等待用户确认后补回

### Step 5 -- 提取新能力
- Agent: Analyst（识别） -> 用户确认 -> Coder（生成）
- 回顾 `git log --oneline -20`，识别 Agent/Skill/Subskill 候选（职责拆分、可复用流程、可并行化检查）

### Step 6 -- 输出摘要
- Agent: Orchestrator
- Step 2~5 均无发现则输出"无需变更"，否则输出变更摘要
