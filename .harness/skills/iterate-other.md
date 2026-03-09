# Skill: 迭代其它

触发：人工下发非代码类任务（如 Harness 维护、文档变更、配置调整等）。

本 Skill 采用单 Agent 架构，由主 Agent（Orchestrator）直接执行所有 Phase。Phase 间通过"检查点摘要"（不超过 10 行）交接上下文。

输出规范：遵守 AGENTS.md "流程合规 > 消息输出格式"中定义的全部规则。

与 Skill: 迭代功能 的差异：Phase 4 合并了代码实现与结果验收，适用于不以代码变更为主的任务。

---

## Phase 1: 任务调度
- Agent: Orchestrator
- 读取 AGENTS.md，确认约束与产品方向，启动 Phase 2

## Phase 2: 意图理解
- Agent: Orchestrator
- 按需读取知识库和产品文档，分析需求，输出 spec（JSON，格式参考 `.harness/agents/analyst.md`）

检查点：`[Phase 2 意图理解] goal: ..., scope: N 文件, M 行为, K 验收标准`

## Phase 3: 意图确认
- Agent: Orchestrator
- spec 落盘到 `.harness/context/agents/agent-specs-${事项}.md`
- 向用户输出完整摘要（目标 + 影响范围 + 实现思路 + 验收标准），等待确认
- 用户修正时：更新 spec，输出完整摘要再次确认

## Phase 4: 任务实现
- Agent: Orchestrator
- 按 spec scope 加载相关文件并执行任务
- 执行完成后，对照 spec 验收标准逐项检查，输出每项通过/不通过
- 验收不通过时就地修正并重新检查

检查点：`[Phase 4 任务实现] 变更: file1(修改), file2(新增), ...; 验收标准: K项通过`

## Phase 5: 知识回填
- Agent: Orchestrator
- 按 AGENTS.md 知识回填规则回填 context/agents/（有变化才写，无变化也告知）
- `rm -f` 删除临时 spec

## Phase 6: 任务总结
- Agent: Orchestrator
- 自动触发 Skill: 总结任务（`.harness/skills/summarize-task.md`）
- 执行顺序：输出总结报告（独立消息）-> 用户确认收到 -> attempt_completion
- 总结报告与 attempt_completion 不得合并

---

## 上下文管理

1. Phase 3 后仅保留 spec，不保留产品文档原文
2. Phase 4 只加载 spec + scope 内相关文件
3. 上下文紧张时先压缩检查点摘要再继续
