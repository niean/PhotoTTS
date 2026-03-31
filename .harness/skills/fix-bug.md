---
name: fix-bug
description: 修复Bug或异常行为修复时使用
---

# Skill: 修复Bug

触发：人工下发 Bug 修复或异常行为修复需求。

本 Skill 采用 5 阶段混合流程：harness（知识库加载）→ superpowers（修复Bug全流程）→ harness（验收 → 知识回填 → 总结）。

与 Skill: 迭代功能 的区别：修复Bug以根因定位为核心，无需求探索和设计阶段；修复范围通常较小，验收侧重回归验证；无 spec/plan 文件管理。

输出规范：遵守 AGENTS.md "流程合规 > 消息输出格式"中定义的全部规则。

---

## Phase 1: 任务调度
- Agent: Orchestrator
- 按 AGENTS.md "上下文管理"要求分层加载知识库：读取所有文件首行 SUMMARY 建立索引，完整读取任务类型加载矩阵中"Bug修复"对应的必读文件
- 确认约束与产品方向，启动 Phase 2

## Phase 2: 修复Bug
- Agent: Orchestrator
- 读取 `.harness/skills/superpowers/systematic-debugging.md`，完整执行其四阶段流程（核心：根因调查 → 模式分析 → 假设验证 → TDD 实现修复）
- 完全遵循 superpowers 流程，不跳过、不简化、不自定义
- build 必须 zero warnings（含 IDE 配置警告、工具级警告）

检查点：`[Phase 2 修复Bug] bug: ..., root_cause: ..., 变更: file1.swift(修改), ...; test: N新增/M通过`

## Phase 3: 结果验收
- 执行 `Skill: 结果验收`（`.harness/skills/harness/verify-acceptance.md`），scope=full，传入变更文件列表和回归验证条件（修复测试通过 + 既有测试无回归 + Bug 现象已消除）
- 不通过时回到 Phase 2 修复

检查点：`[Phase 3 结果验收] 构建: 通过/失败, 扫描: N维度/M违规, 验收标准: K项通过`

## Phase 4: 知识回填
- Agent: Orchestrator
- 按 AGENTS.md 知识回填规则回填 knowledge/（有变化才写，无变化也告知）
- 修复Bug通常不涉及架构变化，但如果修复揭示了新的跨文件模式或数据边界，需要回填

## Phase 5: 任务总结
- Agent: Orchestrator
- 自动触发 Skill: 总结任务（`.harness/skills/harness/summarize-task.md`）
- 执行顺序：输出总结报告 -> 结束任务，在同一条回复中完成

---

## 上下文管理

1. Phase 2 修复Bug在主 Agent 上下文中执行
2. Phase 2 后仅保留根因分析摘要 + 变更文件列表，不保留知识库原文
3. Phase 3 扫描 subagent 有独立上下文
4. 上下文紧张时先压缩检查点摘要再继续
