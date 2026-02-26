# AI 上下文知识库管理规范

本文定义 AI 上下文知识库的 分级策略、内容分类、功能迭代工作流、更新触发规则，基本遵循 Harness Engineering风格的AI Coding范式。

---

## 顶级入口

项目级操作约束与知识库入口，见根目录 AGENTS.md。


---

## 文档内容分类规则

每类知识有且只有一个归属文档，不重复维护：

| 内容类型 | 归属层级 |
|---------|--------|
| 操作约束、构建命令、知识库入口 | AGENTS.md |
| 项目的产品定位、体验原则、判断准则 | 产品方向文档 PRODUCT_SENSE.md |
| 项目的概览、技术栈、核心流程 | 概览文档 context/01-overview.md |
| 项目的架构分层、模块边界、依赖关系 | 架构文档 context/02-architecture.md |
| 项目的代码风格、UI 约定、操作规则 | 约定文档 context/03-conventions.md |
| 项目的关键术语与概念 | 术语表 context/04-glossary.md |
| 项目的数据结构、存储格式、配置结构 | 数据边界文档 context/05-data-boundaries.md |
| 项目的功能与源文件的对应关系 | 文件映射文档 context/06-file-map.md |
| 项目的跨文件的关键代码模式 | 代码模式文档 context/07-key-patterns.md |
| 临时功能 spec | context/feat-xxx.md（迭代中存在，完成后删除） |
| 项目的稳定功能需求基线 | 产品需求基线 doc/01-prd-baseline.md |
| 项目的原始产品需求规格 | 原始需求规格 doc/01-prd-specs.md |


---

## 文档分级加载策略

按加载频率分为四级：

| 级别 | 典型文档 | 加载时机 |
|------|--------|--------|
| 自动加载 | AGENTS.md | 每次任务，由 IDE/Agent(如Cline/Cursor) 自动注入 |
| 任务前读 | PRODUCT_SENSE.md、context/01-overview.md | 功能迭代前，确认项目边界和产品方向 |
| 按需加载 | context/02-07上下文知识库、doc/01-prd-baseline.md | 涉及特定领域时 |
| 历史参考 | doc/01-prd-specs.md | 仅在需要理解历史决策时 |

原则：上下文窗口有限，不需要的文档一律不加载。


---

## 功能迭代工作流

每次实现新功能时，遵循以下步骤：

```
1. 读取 AGENTS.md + PRODUCT_SENSE.md，确认约束与产品方向
2. 按需读取 AI上下文知识库（context/）和 人工定义文档（doc/），了解现状
3. 新建 context/feat-xxx.md（临时 spec），记录：
      - 目标：这个功能要做什么
      - 影响范围：涉及哪些文件/模块
      - 关键行为：边界条件、与现有模式的关系
4. 实现代码
5. 将稳定知识回填到 context/ 对应文件：
      - 架构边界变化 → context/02-architecture.md
      - 新增术语 → context/04-glossary.md
      - 新增源文件 → context/06-file-map.md
      - 新增跨文件模式 → context/07-key-patterns.md
6. 删除 context/feat-xxx.md
```


---

## 文档更新触发条件

以下情况发生时，必须更新对应的知识库文档：

| 触发条件 | 更新目标 |
|---------|--------|
| AI 行为偏离预期，缺少某类说明 | 补充到对应 context/ 文件 |
| 新增源文件或视图组件 | context/06-file-map.md |
| 出现新的跨文件代码模式 | context/07-key-patterns.md |
| 引入新术语或概念 | context/04-glossary.md |
| 数据结构或存储格式变化 | context/05-data-boundaries.md |
| 普遍性约束或操作规则变化 | AGENTS.md 的"操作约束"节 |
| 产品方向或判断准则调整 | PRODUCT_SENSE.md |
