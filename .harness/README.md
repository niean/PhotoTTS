# Harness 工程模板

本目录包含项目无关的 Harness 工程模板，供新项目快速接入 AI 协作工程体系。所有 `{{占位符}}` 需根据项目实际情况替换。

## 约束

本模板通过 `IDE:vscode+cline` + `LLM:claude-opus-4.6`调教，可能使用了专有函数、方法等，如遇问题请自行修正

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
Layer 1  .harness/agents/（Agent 角色定义 -- "谁来做"）
            |
            |-- orchestrator.md  读取 AGENTS.md，引用 iterate-feature.md、reviewer.md
            |-- analyst.md       读取 AGENTS.md，读取 prd/、knowledge/
            |-- coder.md         读取 AGENTS.md，按需读取 knowledge/03、05
            |-- reviewer.md      引用 skills/subskills/scan-*.md（调度扫描）
            |
Layer 2  .harness/skills/（Skill 流程定义 -- "怎么做"）
            |
            |-- iterate-feature.md    引用 agents/analyst.md、coder.md、reviewer.md
            |-- iterate-other.md
            |-- governance-code.md    引用 agents/coder.md、reviewer.md，调度 skills/subskills/
            |-- governance-capability.md  读取 AGENTS.md 注册表 + agents/、skills/（含 subskills/）
            |-- governance-all.md     编排 governance-code、governance-capability、backfill-knowledge、backfill-prd
            |-- backfill-knowledge.md 读取 AGENTS.md、knowledge/、skills/目录（含 subskills/）
            |-- backfill-prd.md       读取 prd/ 三个产品文档
            |-- verify-build.md       独立（仅含构建命令）
            |-- summarize-task.md     独立（仅含报告模板）
            |-- extract-harness-tpl.md 读取全部 .harness/ 文件
            |
Layer 3  .harness/skills/subskills/（Subskill 任务模板 -- "做什么"）
            |
            |-- scan-*.md  引用源码路径，检查规则来自 AGENTS.md/03-conventions.md
            |              被 reviewer.md 和 governance-code.md 调用
            |
数据层   .harness/knowledge/（知识库） + .harness/prd/（产品文档） + .harness/guides/（方法论）
            |
            |-- knowledge/01-overview.md     指回 AGENTS.md（"操作约束见 AGENTS.md"）
            |-- knowledge/03-conventions.md  指回 AGENTS.md（声明自己是权威源，AGENTS.md为摘要）
            |-- knowledge/02,04,05,21,22     独立数据文档，不引用其他 .harness 文件
            |-- prd/01,02,03-prd-*.md   独立产品文档，AI只读
            |-- guides/00-harness-desc.md         通用方法论，人工维护
            |-- guides/01-harness-ops.md          项目维护手册，人工维护
            |-- guides/02-harness-dev.md          开发流程，人工维护
            |
辅助层   .harness/plans/（AI 自主管理的执行计划）
            |
            |-- active/                当前活跃计划（原则上 1 个文件）
            |-- completed/             已完成计划归档
            |-- debt-tracker.md        技术债追踪
```

## 知识库设计哲学

knowledge/ 按"知识用途"而非"功能领域"组织，编号分段体现两类文件的不同性质：

- 01~05 认知与约束类：为 AI 建立项目认知（概览、架构、约定、数据、模式），按关注点拆分而非集中为单一 design.md，使 AI 按需加载时能精确命中所需片段
- 21~22 工具与索引类：为 AI 提供快速查找能力（术语字典、文件导航），避免逐文件搜索


## 版本信息

本节由自然人维护，未经人工确认、禁止AI修改。

| 版本 | 日期 | 更新内容 |
|-----|------|---------|
| v0.5.0 | 2026-03-18 | 兼容CC环境 |
| v0.4.0 | 2026-03-17 | 增加Design能力(复用Plan) |
| v0.3.0 | 2026-03-14 | 增加Plan管理 |
| v0.2.0 | 2026-03-12 | 发布多Agent模式 |
| v0.1.0 | 2026-03-05 | 发布单Agent模式 |

