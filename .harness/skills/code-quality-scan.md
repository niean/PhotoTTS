# Skill: 代码质量扫描

触发：人工指令。

## 步骤

### Step 1 — 读取规范

读取 AGENTS.md 中的代码生成、质量守护、安全规范，提取检查规则。

### Step 2 — 并行扫描

使用 `use_subagents` 并行启动 5 个 subagent，每个聚焦一个检查维度。读取 `.harness/subagents/` 目录下对应 prompt 模板文件的内容，作为各 subagent 的 prompt 参数。

| Subagent | 维度 | prompt 模板 |
|----------|------|------------|
| 1 | 日志规范 | .harness/subagents/scan-logging.md |
| 2 | 安全规范 | .harness/subagents/scan-security.md |
| 3 | 图片处理规范 | .harness/subagents/scan-image-handling.md |
| 4 | 架构边界 | .harness/subagents/scan-architecture.md |
| 5 | 编码约定 | .harness/subagents/scan-conventions.md |

### Step 3 — 汇总报告

主 agent 汇总 5 个 subagent 的结果，合并为统一违规清单，按严重程度排序（安全 > 架构 > 图片 > 日志 > 编码），输出给用户确认。

### Step 4 — 执行修复

待人工确认后，按清单逐项修复。修复完成后执行构建验证（Skill: 构建验证）。
