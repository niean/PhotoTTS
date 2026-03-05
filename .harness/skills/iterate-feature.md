# Skill: 迭代功能

触发：人工下发功能需求（新 Task 或同一 Task 内的第 2+ 次反馈）。

本 Skill 采用多 Agent 编排，每个 Phase 指定执行角色。Phase 间通过"检查点摘要"（不超过 10 行）交接上下文，后续 Phase 不回溯前序 Phase 的详细内容。

输出规范：遵守 AGENTS.md "流程合规 > Agent 架构声明与角色标注是强制输出规范"中定义的全部规则。

---

## Phase 1: 任务调度

- Agent: Orchestrator
- 读取 AGENTS.md，确认约束与产品方向
- 准备用户原始需求文本，启动 Phase 2

## Phase 2: 意图理解

- Agent: Analyst（subagent）
- 读取 `.harness/agents/analyst.md` 模板内容，将用户需求填充到 `{user_request}` 参数
- 通过 `use_subagents` 启动 Analyst subagent
- Analyst 按需读取知识库和产品文档，输出结构化 spec（JSON 格式）
- Orchestrator 收到 spec 输出

检查点摘要格式：`[Phase 2 意图理解] goal: ..., scope: N 文件, M 行为, K 验收标准`

## Phase 3: 意图确认

- Agent: Orchestrator
- 将 Analyst 输出的 spec 落盘到 `.harness/context/agents/agent-specs-${事项}.md`（${事项} 用简短英文或拼音标识本次迭代内容）
- 向用户输出"意图理解"摘要，包含：本次迭代的目标、影响范围、实现思路要点
- 等待用户确认或修正后，再进入下一步
- 如用户有修正：重新启动 Analyst subagent（将修正信息填充到 `{correction}` 参数），更新临时 spec 文件，重新输出完整摘要，再次等待确认
- 修正后的摘要必须是完整摘要（目标 + 影响范围 + 全部实现思路要点 + 验收标准），禁止只输出增量变化

## Phase 4: 代码实现

- Agent: Coder（主 Agent 切换到编码角色）
- 读取 `.harness/agents/coder.md` 了解编码约束
- 按 spec 中的 scope 按需加载相关源文件
- 实现代码变更
- 如 spec 中涉及 Manager / Coordinator / Service 层变更，同步补充或更新单元测试

检查点摘要格式：`[Phase 4 代码实现] 变更: file1.swift(修改), file2.swift(新增), ...`

## Phase 5: 结果验收

- Agent: Reviewer（混合形态），按 `.harness/agents/reviewer.md` 定义的 Step 1-4 执行
- 扫描范围限定：仅限本次变更的文件（Phase 4 检查点中列出的变更文件），未变更的文件无需扫描
- 如构建失败、扫描发现违规或验收不通过，回到 Phase 4 修复

检查点摘要格式：`[Phase 5 结果验收] 构建: 通过/失败, 扫描: N维度/M违规, 测试: 通过/跳过`

## Phase 6: 任务收尾

- Agent: Orchestrator
- 将稳定知识回填到 .harness/context/agents/ 对应文件（按 AGENTS.md 知识回填规则）；有变化时才写，因无变化而未写也要告知情况
- 删除临时 spec 文件 `.harness/context/agents/agent-specs-${事项}.md`（使用 `rm -f` 避免交互确认）

---

## 上下文管理

1. Phase 2（Analyst subagent）有独立上下文窗口，不消耗主 Agent 预算
2. Phase 3 结束后，原始产品文档不再保留在主 Agent 上下文中，仅保留 spec
3. Phase 4（Coder）只加载 spec + scope 内源文件，不加载产品文档
4. Phase 5（Reviewer）扫描 subagent 有独立上下文，构建/测试命令输出按需截取
5. 如感知到上下文紧张，先压缩已有检查点摘要（丢弃中间细节），再继续执行
