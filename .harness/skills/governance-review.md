# Skill: 治理巡检

触发：人工指令。对项目进行一轮完整的代码治理和知识库校正，编排多个现有 Skill 按顺序执行。

## 步骤

### Step 1 — 代码质量扫描

执行 Skill: 代码质量扫描（`.harness/skills/code-quality-scan.md`）。完成并行 5 维度扫描、输出违规清单、经用户确认后执行修复。

### Step 2 — 废弃代码清理

执行 Skill: 废弃代码清理（`.harness/skills/dead-code-cleanup.md`）。识别并清理未使用的代码、无效导入、过期注释等。

### Step 3 — 构建验证

执行 Skill: 构建验证（`.harness/skills/build-verify.md`）。确认 Step 1~2 的修改不引入编译错误或警告。

### Step 4 — 知识库回填

执行 Skill: 回填-知识库更新（`.harness/skills/backfill-knowledge.md`）。对比实际代码与 `.harness/context/agents/` 文档，修正过时描述、压缩冗余内容。

### Step 5 — AGENTS.md 校正

执行 Skill: 回填-AGENTS更新（`.harness/skills/backfill-agents.md`）。确保 AGENTS.md 中的规则、表格、描述与知识库和代码现状一致。

### Step 6 — 巡检报告

向用户输出巡检报告，包含：
- 代码质量：扫描发现的违规数、已修复数
- 废弃代码：清理的文件/代码段数量
- 构建状态：是否零警告零错误
- 知识库变更：修正和压缩的文档列表
- AGENTS.md 变更：更新的规则或表格行
