# AX — 知识沉淀规则

## 核心约束

项目知识的 canonical 路径只有三类：

- `docs/ai-context/`：架构、约定、排障结论
- `.agents/skills/`：可复用工作流
- `{module}/AGENTS.md`：模块上下文

不要把知识写入任何 agent 专属路径（如 `.claude/`、`.codex/`）。所有沉淀只使用上述通用路径，确保跨 agent 可读。

## 自动沉淀

AX 使用 Stop hook，在每轮 Claude 回答结束后自动评估沉淀时机。两层过滤：

### 第一层：硬指标快筛（bash 脚本内完成，零成本）

基于**当前 turn** 的指标判断，满足以下任一条件即通过（OR）：

- 本轮 10+ 次工具调用（实质性工作）
- 本轮调用了 brainstorming skill（设计/探索）
- 本轮 100+ 行 transcript（深度回复）

不满足则直接跳过，不消耗 LLM。

### 第二层：LLM 价值判断（后台 sonnet，满足硬指标后启动）

后台启动 `claude -p --model sonnet --bare` 读取提取后的对话内容，判断是否有值得沉淀的项目知识。如果有，直接写入项目。用户可以通过 `git diff` 查看、`git checkout -- <file>` 撤销。

同一 session 内 review 完成后 10 分钟内不重复触发。

用户也可以随时手动执行 `/ax:ax` 触发沉淀，不受自动机制限制。

### 不应沉淀

- 简单问答、单行修改、显而易见的用法
- 已在现有 AGENTS.md 或 Skill 中记录过的内容
- 一次性的临时 workaround（不具备复用价值）
- 通用编程知识（语言语法、标准库用法等）
- 仅与当前 PR/任务相关、不会再遇到的上下文

### 沉淀路径

1. **Skill**（可复用流程）→ `.agents/skills/{name}/SKILL.md`
2. **架构/设计知识** → `docs/ai-context/{topic}.md`
3. **模块上下文** → `{module}/AGENTS.md`（追加）

### 写入规范

- 每个 md 文件 **< 200 行**，超出时拆分并用 `@` 引用关联
- 写入前检查是否已有重复内容（grep 关键词），有则更新而非新建
- 写入后更新最近的父级 AGENTS.md，添加 `@` 引用
- 不自动 commit，git 操作由用户控制

## 维护规则

读取已有 Skill 或 AGENTS.md 时，如果发现内容过时、不完整或有误，通过 `/ax:ax` 准备更新提案或等待自动 review 处理。

## 跨 Agent 兼容

沉淀产物使用通用格式，不依赖任何特定 agent 的私有机制：

| 产物 | 路径 | 消费方式 |
|------|------|---------|
| 项目入口 | `AGENTS.md` | 所有 agent 读取；Claude Code 通过 `CLAUDE.md → AGENTS.md` 软链接 |
| 架构知识 | `docs/ai-context/*.md` | 通过 `@` 引用被任何 agent 发现 |
| 项目技能 | `.agents/skills/*/SKILL.md` | 通用 skill 格式，各 agent 按自身机制发现 |
| 模块上下文 | `{module}/AGENTS.md` | 目录遍历发现，任何 agent 可读 |
