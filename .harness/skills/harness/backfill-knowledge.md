---
name: backfill-knowledge
description: 知识库回填，支持完整模式（人工指令）和增量模式（Workflow 自动调用）
---

# Skill: 回填知识库

## 输入参数

| 参数 | 必需 | 说明 |
|------|------|------|
| mode | 否 | `incremental`（默认）增量模式，`full`完整模式 |
| changed_files | 增量模式必需 | 本次任务变更文件列表（来自 Phase 4 检查点） |
| task_summary | 增量模式必需 | 任务摘要（来自 spec/plan，含目标和范围） |


## 执行模式

### 增量模式（mode=incremental）

任务知识回填阶段自动调用。聚焦本次变更范围，按 AGENTS.md 知识回填规则回填 knowledge/，不扫描 AGENTS.md 一致性，不等待人工确认。

按下方"增量模式步骤"执行。


### 完整模式（mode=full）

人工指令触发。全量扫描知识库与代码的一致性，含 AGENTS.md 同步和人工确认。

按下方"完整模式步骤"执行。


---

## 增量模式步骤

### Step 1 -- 接收输入
从调用方获取 changed_files（变更文件列表）和 task_summary（任务摘要）。

### Step 2 -- 读取现状
- 读取 AGENTS.md "知识回填规则" 章节，确认回填映射关系
- 读取 .harness/knowledge/ 全部文件首行 SUMMARY，建立索引
- 根据变更内容，完整读取可能需要更新的 knowledge 文件

### Step 3 -- 增量回填 knowledge/
按 AGENTS.md 知识回填规则，对照变更文件和任务摘要，逐条判断并更新：
- 架构变化 -> 02-architecture.md
- 新术语 -> 21-glossary.md
- 数据结构/存储变化 -> 04-data-boundaries.md
- 新源文件 -> 22-file-map.md
- 新跨文件模式 -> 05-key-patterns.md
- 产品方向调整 -> 提示用户，人工更新 prd/

有变化才写，无变化不修改。

### Step 4 -- 输出回填摘要
有变化：列出具体变更（文件、变更内容）。无变化：告知"本次无需回填"。


---

## 完整模式步骤

### Step 1 -- 读取现状
读取 AGENTS.md + .harness/knowledge/ 全部 + prd/ 目录结构 + skills/ 目录（含 subskills/）+ README.md文件，按需扫描源码目录。

### Step 2 -- 更新 knowledge/ 知识库
对比实际代码与文档，修正过时描述，简化压缩内容。

### Step 3 -- 提取 AGENTS.md 候选变更
识别：仓库结构不一致、Skills/Subskills 表过时、知识库索引不一致、摘要与 03-conventions.md 不同步等。列出候选清单（位置、当前描述、建议描述、原因）。

### Step 4 -- 等待人工确认 `[CONFIRM]`
展示候选清单，结束当前回复，等待用户确认。

### Step 5 -- 更新 AGENTS.md
按确认项最小化修改。

### Step 6 -- 输出变更摘要