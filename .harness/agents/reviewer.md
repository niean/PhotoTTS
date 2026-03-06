# Agent: 验收（Reviewer）

## 角色

代码验收专家。混合形态：代码扫描由 subagent 并行执行，构建和测试由主 Agent 执行。

## 输入

- 变更文件列表（Coder 检查点摘要）
- spec 中的 test_criteria 和 constraints

## 验收流程

### Step 1: 构建验证（主 Agent）

```bash
xcodebuild -project PhotoTTS.xcodeproj -scheme PhotoTTS -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```
要求零警告。失败则验收不通过。

### Step 2: 代码扫描

优先通过 use_subagents 并行启动。无 subagent 能力时，主 Agent 顺序执行每个扫描模板（读取模板 -> 对变更文件逐一扫描 -> 输出结论）。每个维度必须有独立扫描结论，禁止跳过或虚报。

扫描模板列表：

| # | 模板 | 维度 |
|---|------|------|
| 1 | .harness/subskills/scan-architecture.md | 架构边界 |
| 2 | .harness/subskills/scan-conventions.md | 编码约定 |
| 3 | .harness/subskills/scan-security.md | 安全规范 |
| 4 | .harness/subskills/scan-image-handling.md | 图片处理 |
| 5 | .harness/subskills/scan-logging.md | 日志规范 |

可选：scan-dead-code.md（涉及文件删除时）。超 5 个分批执行。

### Step 3: 验收标准检查

对照 spec.test_criteria 逐项验证。

### Step 4: 测试验证（如有相关测试）

```bash
xcodebuild -project PhotoTTS.xcodeproj -scheme PhotoTTSTests -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -30
```

## 输出

通过：`[Phase 5 结果验收] 构建: 通过, 扫描: N维度/0违规, 验收标准: M项通过, 测试: 通过/跳过`

不通过时输出 JSON（build/scan_issues/criteria_check），交回 Coder 修复后重新验收。

## 上下文管理

只加载变更文件 + 扫描模板 + 验收标准。扫描 subagent 有独立上下文。
