# Harness 项目维护

## 约束
本文仅供自然人使用，未经人工确认、禁止AI修改。

---

## 蒸馏模板
- 提示词：执行 `提取Harness模板`

## 治理
- 全部
    - 提示词：执行 `治理全部`
- 代码
    - 提示词：执行 `治理代码`
- 技能
    - 提示词：执行 `治理技能`
- 知识
    - 提示词：执行 `回填知识库`
- 产品
    - 提示词：执行 `回填产品文档`

---
## 回填
- 知识
    - 提示词：提炼 `03-prd-specs.md`的核心功能，回填到 `02-prd-baseline.md`中。要求：①和baseline既有内容不重不漏不冲突，②在消息框展示Diff、人工确认后才能修改baseline

---

## 架构-Skills（人工触发）
- 生成
    - 生成Skill：使用Skill `治理技能`，让AI自动提取新的Skill或Subskill
    - 生成Skill：任务名`任务总结`、文件名`task-summary.md`，AI自动触发，总结事项包括但不限于 任务意图、关键步骤、结果验收、合规审计、 资源消耗(如耗时、Token消耗)；要求满足Harness风格
    - 生成Skill：任务名`回填-产品文档更新`、文件名`backfill-prd.md`，人工触发，合并原`回填-产品SENSE更新`和`回填-产品基线更新`
- 修改
    - 更新Skill：重命名，任务名`回填-Skill提取`，Skill重命名为`提取-Skill`、文件重命名为`extract-skill.md`
    - 更新Skill：重命名，任务名`提取Harness模板`，Skill重命名为`提取-Harness模板`、文件名保持不变
    - 更新Skill：功能调整，任务名`提取-Harness模板`，在用户指定的目录下，新建文件/文件夹、更改文件内容时，无需用户确认、AI可自动执行
    - 更新Skill：功能调整，任务名`功能迭代`，4. 向用户输出"意图理解"摘要，包含：本次迭代的目标、影响范围、实现思路要点；等待用户确认或修正后，再进入下一步。如用户有修正，需要重新输出完整的"意图理解"摘要，等待用户确认后、再进入下一步。据此，修正AI知识库
    - 合并Skill：`提取-Skill` + `提取-Subagent` + 更新能力 + 合并能力 → `治理技能`(governance-capability.md)
    - 合并Skill：`回填-知识库更新` + `回填-AGENTS更新` → `回填知识库`(backfill-knowledge.md)
    - 合并Skill：`回填-产品基线更新` + `回填-产品SENSE更新` → `回填产品文档`(backfill-prd.md)

## 架构-Subskills（人工触发）
- 生成
    - 生成Subskill：使用Skill `治理技能`，让AI自动提取新的Subskill
