# Skill: 治理代码

触发：人工指令。对项目代码进行一轮完整的质量治理，包括规范扫描和废弃代码清理。

本 Skill 采用多 Agent 编排，每个 Phase 指定执行角色。Phase 间通过"检查点摘要"（不超过 10 行）交接上下文。

---

## Phase 1: 调度

- Agent: Orchestrator
- 读取 AGENTS.md 中的代码生成、质量守护、安全规范，确认检查规则
- 启动 Phase 2

## Phase 2: 扫描

- Agent: Reviewer（subagent 并行）
- 通过 `use_subagents` 并行启动扫描 subagent，读取 `.harness/subagents/` 目录下对应 prompt 模板文件的内容作为 prompt
- 如超出单次并行上限（5），自动分批执行
- 第一批：`.harness/agents/reviewer.md` Step 2 中定义的 5 个扫描维度
- 第二批：额外执行扫描废弃代码（`.harness/subagents/scan-dead-code.md`）

检查点摘要格式：`[Phase 2 扫描] N个维度完成, 共M项违规 (安全X, 架构Y, ...)`

## Phase 3: 汇总与确认

- Agent: Orchestrator
- 合并 Phase 2 全部 subagent 的结果，输出统一违规清单
- 按严重程度排序：安全 > 架构 > 图片 > 日志 > 编码 > 废弃代码
- 每项注明：文件、位置、违规类型、原因
- 通过 ask_followup_question 工具向用户展示违规清单（违规清单必须写在 question 参数内部）
- 等待用户确认哪些需要修复

## Phase 4: 修复

- Agent: Coder（主 Agent 切换到编码角色）
- 读取 `.harness/agents/coder.md` 了解编码约束
- 按用户确认的清单逐项修复，包括：
  - 代码规范违规的修复
  - 废弃代码的删除
  - 同步更新 .harness/context/agents/06-file-map.md（如有文件删除）

检查点摘要格式：`[Phase 4 修复] 修复N项, 删除M个废弃项, 更新file-map: 是/否`

## Phase 5: 验证

- Agent: Reviewer（混合形态）

### Step 5a: 构建验证（主 Agent 执行）

```bash
xcodebuild -project PhotoTTS.xcodeproj \
           -scheme PhotoTTS \
           -destination 'platform=iOS Simulator,name=iPhone 16' \
           build 2>&1 | tail -20
```

要求零警告。如构建失败，回到 Phase 4 修复。

### Step 5b: 回归扫描（可选，如修复涉及面广）

针对修复涉及的维度，重新启动对应扫描 subagent 验证修复效果。

检查点摘要格式：`[Phase 5 验证] 构建: 通过/失败, 回归扫描: 通过/N项残留`

## Phase 6: 收尾

- Agent: Orchestrator
- 输出治理报告摘要：扫描了多少维度、发现多少违规、修复了多少、剩余多少

---

## 上下文管理

1. Phase 2 的 6 个扫描 subagent 各有独立上下文，不消耗主 Agent 预算
2. Phase 3 只需汇总扫描结果文本，不加载源码
3. Phase 4（Coder）只加载需要修复的文件，不加载全部扫描源文件
4. 所有 Phase 均为必选项，禁止因上下文压力跳过
