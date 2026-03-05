# Harness 工程模板

本目录包含项目无关的 Harness 工程模板，供新项目快速接入 AI 协作工程体系。所有 `{{占位符}}` 需根据项目实际情况替换。

## 约束

本模板系通过 `claude-opus-4.6`模型调教，可能使用了专有的函数、方法等，如遇问题请自行修正

## 项目初始化

请参考 `docs/02-harness-dev.md`中的 `## 项目初始化`章节

## 开发流程

请参考 `docs/02-harness-dev.md`中的 `## 人机协作开发`章节

## 知识库层级关系
```
Layer 0  AGENTS.md（顶层入口、注册表、规则摘要）
            |
            |-- 注册 --> agents/、skills/、subagents/ 全部文件
            |-- 索引 --> context/agents/、context/users/ 全部文件
            |-- 摘要引用 --> context/agents/03-conventions.md（权威源）
            |
Layer 1  .harness/agents/（Agent 角色定义）
            |
            |-- orchestrator.md  读取 AGENTS.md，引用 iterate-feature.md、reviewer.md
            |-- analyst.md       读取 AGENTS.md，读取 context/users/、context/agents/
            |-- coder.md         读取 AGENTS.md，按需读取 context/agents/03、07
            |-- reviewer.md      引用 subagents/scan-*.md（调度扫描）
            |
Layer 2  .harness/skills/（Skill 执行计划）
            |
            |-- iterate-feature.md    引用 agents/analyst.md、coder.md、reviewer.md
            |-- governance-code.md    引用 agents/coder.md、reviewer.md，调度 subagents/
            |-- governance-capability.md  读取 AGENTS.md 注册表
            |-- governance-all.md     编排 governance-code、governance-capability、backfill-knowledge、backfill-prd
            |-- backfill-knowledge.md 读取 AGENTS.md、context/agents/、skills/目录、subagents/目录
            |-- backfill-prd.md       读取 context/users/ 三个产品文档
            |-- verify-build.md       独立（仅含构建命令）
            |-- summarize-task.md     独立（仅含报告模板）
            |-- extract-harness-tpl.md 读取全部 .harness/ 文件
            |
Layer 3  .harness/subagents/（扫描模板）
            |
            |-- scan-*.md  引用源码路径，检查规则来自 AGENTS.md/03-conventions.md
            |              被 reviewer.md 和 governance-code.md 调用
            |
Layer 4  .harness/context/（知识库，数据层）
            |
            |-- agents/01-overview.md     反向引用 AGENTS.md（"操作约束见 AGENTS.md"）
            |-- agents/03-conventions.md  反向引用 AGENTS.md（声明自己是权威源，AGENTS.md为摘要）
            |-- agents/02,04,05,06,07     独立数据文档，不引用其他 .harness 文件
            |-- users/01-prd-*.md         独立数据文档，AI只读
```
