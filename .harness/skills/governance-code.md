# Skill: 治理代码

触发：人工指令。对项目代码进行一轮完整的质量治理，包括规范扫描和废弃代码清理。

## 步骤

### Step 1 -- 读取规范

读取 AGENTS.md 中的代码生成、质量守护、安全规范，提取检查规则。

### Step 2 -- 并行扫描

使用 `use_subagents` 并行启动 subagent，每个聚焦一个检查维度。读取 `.harness/subagents/` 目录下对应 prompt 模板文件的内容，作为各 subagent 的 prompt 参数。如超出单次并行上限，自动分批执行。

| Subagent | 维度 | prompt 模板 |
|----------|------|------------|
| 1 | 日志规范 | .harness/subagents/scan-logging.md |
| 2 | 安全规范 | .harness/subagents/scan-security.md |
| 3 | 图片处理规范 | .harness/subagents/scan-image-handling.md |
| 4 | 架构边界 | .harness/subagents/scan-architecture.md |
| 5 | 编码约定 | .harness/subagents/scan-conventions.md |
| 6 | 废弃代码 | .harness/subagents/scan-dead-code.md |

### Step 3 -- 汇总报告

合并 Step 2 全部 subagent 的结果，输出统一违规清单。按严重程度排序：安全 > 架构 > 图片 > 日志 > 编码 > 废弃代码。每项注明：文件、位置、违规类型、原因。

### Step 4 -- 人工确认

通过 ask_followup_question 工具向用户展示违规清单，等待用户确认哪些需要修复。

### Step 5 -- 执行修复

按用户确认的清单逐项修复，包括：
- 代码规范违规的修复
- 废弃代码的删除
- 同步更新 .harness/context/agents/06-file-map.md（如有文件删除）

### Step 6 -- 构建验证

执行 Skill: 验证构建（`.harness/skills/verify-build.md`），确认修复不引入编译错误或警告。
