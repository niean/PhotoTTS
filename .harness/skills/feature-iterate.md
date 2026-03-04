# Skill: 功能迭代

触发：人工下发功能需求（新Task 或同一Task内的第2+次反馈）。

步骤：
1. 读取 AGENTS.md + 01-prd-sense.md，确认约束与产品方向
2. 按需读取 AI上下文知识库（.harness/context/agents/）和 人工定义文档（.harness/context/users/），了解现状
3. 将临时 spec 落盘到 `.harness/context/agents/agent-specs-${事项}.md`，记录：目标、影响范围、关键行为（${事项} 用简短英文或拼音标识本次迭代内容）
4. 向用户输出"意图理解"摘要，包含：本次迭代的目标、影响范围、实现思路要点；等待用户确认或修正后，再进入下一步。如用户有修正，需要重新完整的"意图理解"摘要、输出到消息框，同步更新临时 spec 文件、防止与消息框不一致；等待用户确认后、再进入下一步
5. 实现代码
6. 将稳定知识回填到 .harness/context/agents/ 对应文件；有变化时才写，因无变化而未写也要告知情况
7. 删除临时 spec 文件 `.harness/context/agents/agent-specs-${事项}.md`（AI 可自动执行，无需人工确认；使用 `rm -f` 避免交互确认）
