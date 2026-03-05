# Harness 工程模板

本目录包含项目无关的 Harness 工程模板，供新项目快速接入 AI 协作工程体系。所有 `{{占位符}}` 需根据项目实际情况替换。

## 约束

本模板系通过 `claude-opus-4.6`模型调教，可能使用了专有的函数、方法等，如遇问题请自行修正

## 项目初始化

请参考 `docs/02-harness-dev.md`中的 `## 项目初始化`章节

## 开发流程

请参考 `docs/02-harness-dev.md`中的 `## 人机协作开发`章节


## 模板文件清单

| 路径 | 用途 |
|------|------|
| AGENTS.md | AI Agent 入口文件，定义通用规范和项目规范 |
| .harness/README.md | 本文件，模板说明与开发流程指引 |
| .harness/docs/00-harness-ops.md | Harness 项目维护操作入口（人工维护） |
| .harness/docs/01-harness-desc.md | 通用 AI 协作工程方法论（项目无关，可直接复用） |
| .harness/docs/02-harness-dev.md | Harness 开发流程（初始化、人机协作开发，人工维护） |
| .harness/skills/iterate-feature.md | Skill: 迭代功能 |
| .harness/skills/verify-build.md | Skill: 验证构建 |
| .harness/skills/governance-code.md | Skill: 治理代码 |
| .harness/skills/backfill-knowledge.md | Skill: 回填知识库 |
| .harness/skills/backfill-prd.md | Skill: 回填产品文档 |
| .harness/skills/extract-harness-tpl.md | Skill: 提取-Harness模板 |
| .harness/skills/governance-capability.md | Skill: 治理技能 |
| .harness/skills/governance-all.md | Skill: 治理全部 |
| .harness/skills/summarize-task.md | Skill: 总结任务 |
| .harness/subagents/scan-example.md | Subagent 示例模板（按维度拆分为多个文件） |
| .harness/subagents/scan-dead-code.md | Subagent: 废弃代码扫描 |
| .harness/context/agents/.gitignore | agents 目录 gitignore（忽略临时 spec 文件） |
| .harness/context/agents/01-overview.md | 知识库: 项目概览 |
| .harness/context/agents/02-architecture.md | 知识库: 架构与模块边界 |
| .harness/context/agents/03-conventions.md | 知识库: 约定与约束（权威定义） |
| .harness/context/agents/04-glossary.md | 知识库: 术语表 |
| .harness/context/agents/05-data-boundaries.md | 知识库: 数据与类型边界 |
| .harness/context/agents/06-file-map.md | 知识库: 功能与文件映射 |
| .harness/context/agents/07-key-patterns.md | 知识库: 关键代码模式 |
| .harness/context/users/01-prd-sense.md | 产品定位、体验原则与判断准则（人工维护） |
| .harness/context/users/01-prd-baseline.md | 稳定的产品需求基线（人工维护） |
| .harness/context/users/01-prd-specs.md | 产品需求演进记录（人工维护） |
