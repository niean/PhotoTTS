---
name: archive-task-files
description: 归档当前 Task 的 spec 和 plan 文件，从 active/ 移到 completed/，不影响其他 Task 的活跃文件
---

# Skill: 归档任务文件

触发：任务完成后自动调用（Workflow 归档阶段），或人工指令。将当前 Task 的 spec 和 plan 从 active/ 移到 completed/。

## 输入

| 参数 | 必需 | 说明 |
|------|------|------|
| spec_file | 否 | spec 文件路径（如 `specs/active/spec-260331-xxx.md`）；未提供则跳过 spec 归档 |
| plan_file | 否 | plan 文件路径（如 `plans/active/plan-260331-xxx.md`）；未提供则跳过 plan 归档 |

两个参数均未提供时，输出"无需归档"并结束。

## 步骤

### Step 1 -- 更新文件状态

对每个输入文件，将文件内的状态字段更新为 `completed`（如有）。

### Step 2 -- 移动文件

执行归档移动：
- `specs/active/{file}` -> `specs/completed/{file}`
- `plans/active/{file}` -> `plans/completed/{file}`

使用 `git mv` 移动（文件已在版本控制中时），否则使用 `mv`。

### Step 3 -- 输出归档摘要

输出格式：

```
归档完成：
- spec: {文件名} -> specs/completed/
- plan: {文件名} -> plans/completed/
```

未归档的文件类型省略对应行。
