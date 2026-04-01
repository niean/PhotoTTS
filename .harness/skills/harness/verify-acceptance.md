---
name: verify-acceptance
description: 结果验收，功能迭代或Bug修复完成后自动执行，或人工指令触发
---

# Skill: 结果验收

## 输入参数

| 参数 | 必需 | 说明 |
|------|------|------|
| scope | 否 | 执行范围：`full`（默认，构建+扫描+验收）、`build_only`（仅构建，用于代码治理等场景） |
| changed_files | scope=full 时必需 | 本次变更文件列表 |
| spec_criteria | scope=full 时必需 | 验收标准（由调用方提供，如 spec.test_criteria、回归验证条件） |

## 约束

- 扫描范围：仅本次变更文件
- 每个 Step 必须实际执行并产出独立结果，禁止跳过或虚报
- 不通过时返回调用方修复（反馈环路）

## 步骤

```
Task Progress:
- [ ] Step 1: 构建验证
- [ ] Step 2: 代码扫描（scope=full）
- [ ] Step 3: 验收检查（scope=full）
```

### Step 1: 构建验证

执行构建，确认零警告零错误：
```
xcodebuild -project PhotoTTS.xcodeproj -scheme PhotoTTS -destination 'platform=iOS Simulator,name=iPhone 17 Pro,arch=arm64' build
```

单元测试执行策略：
- 用户明确要求时：必须执行
- 变更文件包含 Manager/Coordinator/Service/Handler 时：必须执行
- 其他场景：跳过
```
xcodebuild -project PhotoTTS.xcodeproj -scheme PhotoTTSTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro,arch=arm64' test
```

scope=build_only 时，Step 1 完成后输出结果摘要并结束。

### Step 2: 代码扫描

按变更范围选择相关维度 subagent 并行扫描，每个维度独立输出结论。

扫描模板：

| # | 模板 | 维度 |
|---|------|------|
| 1 | .harness/skills/harness/subskills/scan-architecture.md | 架构边界 |
| 2 | .harness/skills/harness/subskills/scan-conventions.md | 编码约定 |
| 3 | .harness/skills/harness/subskills/scan-security.md | 安全规范 |
| 4 | .harness/skills/harness/subskills/scan-image-handling.md | 图片处理 |
| 5 | .harness/skills/harness/subskills/scan-logging.md | 日志规范 |

可选：scan-dead-code.md（涉及文件删除时）。超 5 个分批执行。

### Step 3: 验收检查

对照 spec_criteria 逐项验证，输出每项通过/不通过。

如果调用方已通过 subagent spec review（如 subagent-driven-development 的 spec compliance reviewer），本步骤可简化为抽查（验证关键验收标准 + 跨 task 集成正确性），无需逐项重复全量 spec 合规检查。

## 严重程度分级

| 级别 | 判断标准 | 处理方式 |
|------|---------|---------|
| Blocking | 安全漏洞、构建失败、架构边界违规、验收标准不通过 | 必须修复后重新验收 |
| Warning | 编码约定偏离、图片处理可优化、日志格式不规范 | 本次任务中修复 |
| Info | 废弃代码、可选优化、非本次引入的既存问题 | 记录到 .harness/plans/debt-tracker.md |

- 新发现的既存问题（非本次引入）记录到技术债跟踪文件 `.harness/plans/debt-tracker.md`，不强制在本次迭代修复
- 本次任务新引入的技术债，必须修复、修复后重新扫描验证

## 输出

通过：
```
[结果验收] 构建: 通过, 扫描: N维度/0违规, 验收标准: M项通过
```

不通过时输出违规清单（级别/build_issues/scan_issues/criteria_check），Blocking 和 Warning 交回修复后重新验收，Info 记录技术债。

scope=build_only 时：
```
[结果验收] 构建: 通过/失败
```
