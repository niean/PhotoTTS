---
name: extract-harness-tpl
description: 人工指令触发 Harness 模板提取
---

# Skill: 提取Harness模板

触发：人工指令。从当前 Harness 工程蒸馏出项目无关的通用模板。

本 Skill 采用单 Agent 架构，由主 Agent 直接执行。

自动执行约束：在用户指定目标目录下，新建/修改文件无需逐一确认。

## 上下文管理

禁止通过 use_subagents 读取（易截断），禁止一次性全读。必须分批流水线：按目录分组，每组"读取 -> 蒸馏 -> 写入"后再处理下一组。

## 步骤

### Step 1 -- 更新Harness文档
检查Harness知识库，包括 入口文件AGENTS.md/CLAUDE.md、知识库目录.harness/下的所有文档，修复错误、过时的描述。如遇AI只读的文档，让用户确认后再修改

### Step 2 -- 确认输出目录
默认目录：./locals/harness_tpl/

### Step 3 -- 分批蒸馏写入
分 8 组：CLAUDE.md / AGENTS.md+README / agents/ / guides/ / skills/（含 subskills/） / plans/（含 active/、completed/、debt-tracker.md） / knowledge/ / prd/

蒸馏规则：
1. CLAUDE.md：直接拷贝，无需修改内容（兼容Claude Code项目环境）
2. AGENTS.md+README：剥离项目专属信息，替换为 `{{占位符}}`
3. 保留通用框架/结构/流程
4. 通用规范原文保留；项目规范保留骨架，专属条目替换占位符
5. Subskills 合并为 scan-example.md
6. knowledge/ 和 prd/ 文件保留结构，正文替换占位符；特例：prd/03-prd-specs.md也需要蒸馏为模板
7. Plans 保留目录结构；特例：debt-tracker.md 也需要蒸馏为模板
8. 禁用 emoji/加粗/斜体

### Step 4 -- 清理多余文件
比对目标目录，排除 .git/LICENSE 等，多余文件经确认后删除。

### Step 5 -- 验证
搜索项目专属关键词确认零泄露。

### Step 6 -- 输出报告
文件清单、验证结果、占位符汇总。
