# Harness 工程模板

## 约束

本文系Harness工程模板介绍，允许AI蒸馏，但输出必须沿用原文、不得修改内容。


## IDE限制

本模板通过 `IDE:vscode+claude-code` + `LLM:claude-opus-4-6`调教，可能使用了专有函数、方法等，如遇问题请自行修正

## 项目初始化

请参考 `guides/02-harness-dev.md`中的 `## 项目初始化`章节

## 开发流程

请参考 `guides/02-harness-dev.md`中的 `## 人机协作开发`章节

## 知识库层级关系
```
Layer 0  AGENTS.md（顶层入口、注册表、规则摘要）
            |
            |-- 注册 --> agents/、skills/（含 subskills/）全部文件
            |-- 索引 --> knowledge/、prd/、guides/ 全部文件
            |-- 摘要引用 --> knowledge/03-conventions.md（权威源）
            |
Layer 1  .harness/agents/（Agent 角色与能力 -- "谁来做、能做什么"）
            |
            |-- orchestrator.md  读取 AGENTS.md，引用 workflows/iterate-feature.md、coder.md、reviewer.md、designer.md、planner.md
            |-- designer.md     引用 superpowers/brainstorming.md（需求探索与设计）
            |-- planner.md      引用 superpowers/writing-plans.md（计划制定）
            |-- coder.md        引用 superpowers/subagent-driven-development.md、executing-plans.md
            |-- reviewer.md
            |
Layer 1.5  .harness/workflows/（Workflow 端到端编排 -- "按什么顺序做"）
            |
            |-- iterate-feature.md    引用 agents/orchestrator.md、designer.md、planner.md、coder.md、reviewer.md
            |                        Phase 2 引用 agents/designer.md、superpowers/brainstorming.md
            |                        Phase 3 引用 agents/planner.md、superpowers/writing-plans.md
            |                        Phase 4 引用 superpowers/executing-plans.md 或 subagent-driven-development.md
            |-- fix-bug.md           Bug修复流程，引用 agents/orchestrator.md、coder.md、reviewer.md
            |                        Phase 2 引用 superpowers/systematic-debugging.md
            |-- iterate-docs.md     文档迭代流程，单 Agent（Orchestrator），文档体系一致性维护
            |                        Phase 1 引用 skills/harness/load-knowledge.md
            |-- harness-ops/
            |   |-- governance-code-manual.md    引用 agents/reviewer.md，调度 skills/harness/subskills/
            |   |-- governance-capability-manual.md  读取 AGENTS.md 注册表 + agents/、skills/（含 subskills/）、workflows/

            |
Layer 2  .harness/skills/（Skill 流程定义 -- "怎么做"）
            |
            |-- harness-ops/
            |   |-- extract-harness-tpl-manual.md 读取全部 .harness/ 文件
            |   |-- backfill-prd-manual.md       读取 prd/ 三个产品文档
            |   |-- backfill-knowledge-from-lessons-manual.md  将 lessons/ 教训回填到 knowledge/
            |-- harness/
            |   |-- load-knowledge.md       知识库分层加载（Workflow Phase 1 调用）
            |   |-- backfill-knowledge.md   知识回填（读取 AGENTS.md、knowledge/、skills/目录含 subskills/）
            |   |-- archive-task-files.md   归档任务文件（任务完成后调用）
            |   |-- verify-acceptance.md    结果验收（构建验证 + 代码扫描 + 验收检查，通过 scope 参数控制执行范围）
            |   |-- summarize-task.md       任务总结报告（任务完成后调用）
            |-- superpowers/     superpowers 方法论技能参考（开发方法论，英文原版适配）
            |   |-- brainstorming.md              需求探索与设计（iterate-feature Phase 2 调用）
            |   |   |-- brainstorming/spec-document-reviewer-prompt.md   spec 文档审查模板
            |   |   |-- brainstorming/visual-companion.md                可视化脑暴指南
            |   |-- writing-plans.md              计划制定（iterate-feature Phase 3 调用）
            |   |   |-- writing-plans/plan-document-reviewer-prompt.md   plan 文档审查模板
            |   |-- executing-plans.md            串行实现（iterate-feature Phase 4 备选）
            |   |-- subagent-driven-development.md  subagent 串行实现 + 双阶段审查（iterate-feature Phase 4 备选）
            |   |   |-- subagent-driven-development/implementer-prompt.md      实现者 subagent 模板
            |   |   |-- subagent-driven-development/spec-reviewer-prompt.md    spec 合规审查模板
            |   |   |-- subagent-driven-development/code-quality-reviewer-prompt.md  代码质量审查模板
            |   |-- test-driven-development.md    TDD 方法论（被 subagent-driven-development 间接引用）
            |   |   |-- test-driven-development/testing-anti-patterns.md        测试反模式参考
            |   |-- finishing-a-development-branch.md  分支收尾（被 executing-plans、subagent-driven-development 间接引用）
            |   |-- using-git-worktrees.md        工作树隔离（被 executing-plans、subagent-driven-development 间接引用）
            |   |-- requesting-code-review.md     请求代码审查（被 subagent-driven-development 间接引用）
            |   |   |-- requesting-code-review/code-reviewer.md                代码审查者模板
            |   |-- verification-before-completion.md  完成前验证（被 systematic-debugging 间接引用）
            |   |-- systematic-debugging.md       系统化调试（被 fix-bug Workflow Phase 2 调用）
            |   |   |-- systematic-debugging/condition-based-waiting.md         条件等待策略
            |   |   |-- systematic-debugging/defense-in-depth.md               深度防御策略
            |   |   |-- systematic-debugging/root-cause-tracing.md             根因追踪策略
            |   |-- writing-skills.md             技能编写（独立技能，未被主流程调用）
            |   |   |-- writing-skills/anthropic-best-practices.md             Anthropic 最佳实践参考
            |   |   |-- writing-skills/persuasion-principles.md                说服力原则参考
            |   |   |-- writing-skills/testing-skills-with-subagents.md        subagent 测试技能
            |   |-- dispatching-parallel-agents.md  并行 agent 调度（独立技能，未被主流程调用）
            |   |-- receiving-code-review.md      接收代码审查（独立技能，未被主流程调用）
            |   |-- using-superpowers.md          superpowers 入口（CC 插件自动加载）
            |
Layer 3  .harness/skills/harness/subskills/（Subskill 任务模板 -- "做什么"）
            |
            |-- scan-*.md  引用源码路径，检查规则来自 AGENTS.md/03-conventions.md
            |              被 reviewer.md 和 governance-code-manual.md 调用
            |
数据层   .harness/knowledge/（知识库） + .harness/prd/（产品文档） + .harness/guides/（方法论） + .harness/lessons/（教训库）
            |
            |-- knowledge/01-overview.md     指回 AGENTS.md（"操作约束见 AGENTS.md"）
            |-- knowledge/03-conventions.md  指回 AGENTS.md（声明自己是权威源，AGENTS.md为摘要）
            |-- knowledge/02,04,05,21,22     独立数据文档，不引用其他 .harness 文件
            |-- prd/01,02,03-prd-*.md   独立产品文档，AI只读
            |-- guides/00-harness-desc.md         通用方法论，人工维护
            |-- guides/01-harness-ops.md          项目维护手册，人工维护
            |-- guides/02-harness-dev.md          开发流程，人工维护
            |-- lessons/general.md               通用教训（仅 Harness 框架相关），AI自主维护
            |-- lessons/project.md               项目教训（绑定本项目），AI自主维护
            |
辅助层   .harness/specs/（设计文档） + .harness/plans/（执行计划）
            |
            |-- specs/active/          当前活跃 spec
            |-- specs/completed/       已完成 spec 归档
            |-- plans/active/          当前活跃计划
            |-- plans/completed/       已完成计划归档
            |-- plans/debt-tracker.md  技术债追踪
```

## 知识库设计哲学

knowledge/ 按"知识用途"而非"功能领域"组织，编号分段体现两类文件的不同性质：

- 01~05 认知与约束类：为 AI 建立项目认知（概览、架构、约定、数据、模式），按关注点拆分而非集中为单一 design.md，使 AI 按需加载时能精确命中所需片段
- 21~22 工具与索引类：为 AI 提供快速查找能力（术语字典、文件导航），避免逐文件搜索


## 版本信息（AI-READONLY）

| 版本 | 日期 | 更新内容 |
|-----|------|---------|
| v2.0.0 | 2026-04-01 | 不兼容升级，明确任务调度架构 |
| v1.0.0 | 2026-03-30 | 明确Harness分层理念 |
| v0.9.0 | 2026-03-29 | 新增Lessons库，新增任务文档维护 |
| v0.8.0 | 2026-03-27 | 融入Anthropic最佳实践 |
| v0.7.0 | 2026-03-26 | 新增任务修复Bug |
| v0.6.0 | 2026-03-24 | 融合superpowers |
| v0.5.0 | 2026-03-18 | 兼容CC环境 |
| v0.4.0 | 2026-03-17 | 增加Design能力(复用Plan) |
| v0.3.0 | 2026-03-14 | 增加Plan管理 |
| v0.2.0 | 2026-03-12 | 发布多Agent模式 |
| v0.1.0 | 2026-03-05 | 发布单Agent模式 |

