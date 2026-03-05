# Skill: 迭代功能

触发：人工下发功能需求（新 Task 或同一 Task 内的第 2+ 次反馈）。

本 Skill 采用多 Agent 编排，每个 Phase 指定执行角色。Phase 间通过"检查点摘要"（不超过 10 行）交接上下文。

输出规范：遵守 AGENTS.md "流程合规 > Agent 架构声明与角色标注"中定义的全部规则。

---

## Phase 1: 任务调度
- Agent: Orchestrator
- 读取 AGENTS.md，确认约束与产品方向，启动 Phase 2

## Phase 2: 意图理解
- Agent: Analyst（subagent）
- 读取 `.harness/agents/analyst.md`，将需求填充到 `{user_request}`，通过 `use_subagents` 启动
- Analyst 按需读取知识库和产品文档，输出 spec（JSON）

检查点：`[Phase 2 意图理解] goal: ..., scope: N 文件, M 行为, K 验收标准`

## Phase 3: 意图确认
- Agent: Orchestrator
- spec 落盘到 `.harness/context/agents/agent-specs-${事项}.md`
- 向用户输出完整摘要（目标 + 影响范围 + 实现思路 + 验收标准），等待确认
- 用户修正时：重启 Analyst（`{correction}` 参数），更新 spec，输出完整摘要再次确认

## Phase 4: 代码实现
- Agent: Coder
- 读取 `.harness/agents/coder.md`，按 spec scope 加载源文件并实现
- 涉及 Manager/Coordinator/Service 变更时同步补充单元测试

检查点：`[Phase 4 代码实现] 变更: file1.swift(修改), file2.swift(新增), ...`

## Phase 5: 结果验收
- Agent: Reviewer，按 `.harness/agents/reviewer.md` Step 1-4 执行
- 扫描范围：仅本次变更文件
- 构建失败、扫描违规或验收不通过时回到 Phase 4

检查点：`[Phase 5 结果验收] 构建: 通过/失败, 扫描: N维度/M违规, 测试: 通过/跳过`

## Phase 6: 任务收尾
- Agent: Orchestrator
- 按 AGENTS.md 知识回填规则回填 context/agents/（有变化才写，无变化也告知）
- `rm -f` 删除临时 spec

---

## 上下文管理

1. Phase 2 Analyst subagent 有独立上下文窗口
2. Phase 3 后仅保留 spec，不保留产品文档原文
3. Phase 4 只加载 spec + scope 内源文件
4. Phase 5 扫描 subagent 有独立上下文
5. 上下文紧张时先压缩检查点摘要再继续
