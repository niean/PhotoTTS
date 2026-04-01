---
name: governance-capability-manual
description: 人工指令触发技能治理
---

# Workflow: 治理技能-人工

本 Workflow 采用多 Agent 编排，每个 Phase 指定执行角色。Phase 间通过"检查点摘要"（按 AGENTS.md 检查点摘要模板，不超过 5 行）交接上下文。

输出规范：遵守 AGENTS.md "消息输出格式"中定义的全部规则。

## 上下文管理

本 Workflow 涉及大量文件读取和跨步骤分析，通过以下策略控制上下文：

- 文件加载：每个 Phase 只加载当前必需的文件，不预加载后续 Phase 所需内容
- 检查点交接：每个 Phase 结束时输出检查点摘要（不超过 5 行，按 AGENTS.md 检查点摘要模板）
- 上下文紧张时先压缩已有内容再继续，禁止跳过 Phase
- 跳过空阶段：如某个 Phase 经扫描无发现，输出"Phase N: 无需变更"即可，继续下一 Phase

## 结构同步规则

.harness/ 文件形成相互引用体系。Phase 2 必须检查结构同步性：目录枚举、AGENTS.md 注册表、能力类别引用是否与实际 .harness/ 目录一致。

---

## Phase 1: 读取现状
- Agent: Orchestrator
- 读取 AGENTS.md 注册表 + .harness/agents/、skills/（含 subskills/）、workflows/ 全部文件 + .harness/README.md + .harness/guides/ 全部文件

## Phase 2: 扫描
- Agent: Reviewer
- 检查：注册表与实际文件不一致、格式不规范、闲置 Agent/Subskill、引用不存在的实体、目录枚举不同步、引用方向违反 AGENTS.md 规则（反向引用上层、使用绝对路径）
- 扫描范围含 .harness/README.md 和 guides/，发现 AI-READONLY 文件问题时记录但不自动修复

检查点：`[Phase 2 扫描] N个文件扫描, 共M项问题 (注册表X, 引用Y, 格式Z, AI-READONLY文件W)`

## Phase 3: 扫描结果确认 `[GATE]`
- Agent: Orchestrator
- 合并 Phase 2 结果，按类别排序展示问题清单（区分可自动修复 vs 需人工处理的 AI-READONLY 问题）
- 结束当前回复，等待用户确认

## Phase 4: 修复 `[GATE-ENTRY]`
- Agent: Orchestrator
- `[GATE-ENTRY]` 前置条件：用户已在上一条消息中明确确认问题清单
- 按确认清单修复非 AI-READONLY 文件；AI-READONLY 文件逐个输出修改 Diff，经用户明确确认后由 AI 执行变更

检查点：`[Phase 4 修复] 修复N项, AI-READONLY待处理M项`

## Phase 5: 输出摘要
- Agent: Orchestrator
- Phase 2~4 均无发现则输出"无需变更"，否则输出变更摘要
