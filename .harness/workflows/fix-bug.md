---
name: fix-bug
description: Bug修复端到端工作流，编排 Orchestrator/Coder/Reviewer 完成从根因定位到验收的全流程
---

# Workflow: 修复Bug

5 阶段混合编排：harness（知识库加载）-> superpowers（修复Bug全流程）-> harness（验收 -> 知识回填 -> 总结）。

与 Workflow: 迭代功能 的区别：修复Bug以根因定位为核心，无需求探索和设计阶段；修复范围通常较小，验收侧重回归验证；无 spec/plan 文件管理。

输出规范：遵守 AGENTS.md "消息输出格式"中定义的全部规则。

---

## 进度清单

执行时复制此清单追踪进度：

```
Workflow Progress:
- [ ] Phase 1: 知识加载（知识库加载、约束确认）
- [ ] Phase 2: 修复Bug（根因调查 -> 模式分析 -> 假设验证 -> TDD 实现修复）
- [ ] Phase 3: 结果验收（构建 + 扫描 + 回归验证）
- [ ] Phase 4: 知识回填
- [ ] Phase 5: 任务总结
```

---

## Phase 1: 知识加载
- Agent: Orchestrator
- 执行 `Skill: 加载知识库`（`.harness/skills/harness/load-knowledge.md`），参数 task_type=bugfix, is_first_load=true
- 确认约束与产品方向

检查点：`[Phase 1 知识加载] 索引: N个文件, 必读: 已加载M个, 按需: K个可查阅`

## Phase 2: 修复Bug
- Agent: Coder
- 执行 `Skill: systematic-debugging`（`.harness/skills/superpowers/systematic-debugging.md`），完整执行其四阶段流程（核心：根因调查 -> 模式分析 -> 假设验证 -> TDD 实现修复）
- build 必须 zero warnings（含 IDE 配置警告、工具级警告）

检查点：`[Phase 2 修复Bug] bug: ..., root_cause: ..., 变更: file1.swift(修改), ...; test: N新增/M通过`

## Phase 3: 结果验收
- Agent: Reviewer，主 Agent 内联执行；可传入 model 参数指定扫描 subagent 使用的 LLM 模型
- 执行 `Skill: 结果验收`（`.harness/skills/harness/verify-acceptance.md`），scope=full，传入变更文件列表和回归验证条件（修复测试通过 + 既有测试无回归 + Bug 现象已消除）
- 不通过时回到 Phase 2 修复（反馈环路），最多重试 3 次；超限时中断流程，向用户输出错误报告（未通过项 + 已尝试的修复方案），等待人工介入决策

检查点：`[Phase 3 结果验收] 构建: 通过/失败, 扫描: N维度/M违规, 验收标准: K项通过`

## Phase 4: 知识回填
- Agent: Orchestrator
- 执行 `Skill: 回填知识库`（`.harness/skills/harness/backfill-knowledge.md`），增量模式
- 输入：Phase 2 变更文件列表（changed_files）+ Phase 2 检查点摘要（task_summary，含 bug 描述和 root_cause）（有变化才写，无变化也告知）
- 修复Bug通常不涉及架构变化，但如果修复揭示了新的跨文件模式或数据边界，需要回填

检查点：`[Phase 4 知识回填] 回填: N个文件, 状态: 有变化/无变化`

## Phase 5: 任务总结
- Agent: Orchestrator
- 执行 `Skill: 总结任务`（`.harness/skills/harness/summarize-task.md`）
- 执行顺序：输出总结报告 -> 结束任务，在同一条回复中完成

检查点：`[Phase 5 任务总结] 状态: 完成`

---

## 上下文管理

1. Phase 2 修复Bug在主 Agent 上下文中执行
2. Phase 2 后仅保留根因分析摘要 + 变更文件列表，不保留知识库原文
3. Phase 3 扫描 subagent 有独立上下文
4. 上下文紧张时先压缩检查点摘要再继续
