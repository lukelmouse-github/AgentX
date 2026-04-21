# AX — 知识沉淀规则

## 核心约束

**所有知识沉淀必须通过 `/ax:ax` 流程完成。** 不允许 agent 自行直接写入 `docs/ai-context/`、`.agents/skills/` 或 `AGENTS.md` 中的沉淀内容。`/ax:ax` 负责预览、验证、确认和落盘。

项目知识的 canonical 路径只有三类：

- `docs/ai-context/`：架构、约定、排障结论
- `.agents/skills/`：可复用工作流
- `{module}/AGENTS.md`：模块上下文

不要把知识写入任何 agent 专属路径（如 `.claude/`、`.codex/`）。所有沉淀只使用上述通用路径，确保跨 agent 可读。

## 自动沉淀规则

Stop hook 会在对话结束时自动评估是否达到沉淀条件。达标后 Claude 自动执行 `/ax:ax` 分析和预览，用户确认后写入。

触发条件（由 `.ax/profile.yaml` 或内置默认规则决定）：

- 多步骤调试（5+ 次工具调用）并最终定位到 root cause
- 发现代码中非显而易见的约定、陷阱或架构约束
- 实现了可复用的工作流（部署、排错、集成、迁移等）
- 修改了项目关键路径的核心文件

如果项目已配置 `.ax/profile.yaml`（通过 `/ax:init` 生成），Stop hook 按项目策略判断。否则使用默认规则。

当用户拒绝沉淀预览时，UserPromptSubmit hook 会在下一轮注入反思提示，帮助分析为什么这种信号组合不值得沉淀，以及如何调整 profile 避免类似误触发。

### 不应沉淀

- 简单问答、单行修改、显而易见的用法
- 已在现有 AGENTS.md 或 Skill 中记录过的内容
- 一次性的临时 workaround（不具备复用价值）
- 通用编程知识（语言语法、标准库用法等）
- 仅与当前 PR/任务相关、不会再遇到的上下文

### 沉淀流程

1. **判断类型**：
   - **Skill**（可复用流程）→ `.agents/skills/{name}/SKILL.md`
   - **架构/设计知识** → `docs/ai-context/{topic}.md`
   - **模块上下文** → `{module}/AGENTS.md`（追加）

2. **写入规范**：
   - 每个 md 文件 **< 200 行**，超出时拆分并用 `@` 引用关联
   - 写入后更新最近的父级 AGENTS.md，添加 `@` 引用

3. **确认后写入**：展示目标路径和内容预览，用户确认后才写入

4. **不自动 commit**：git 操作由用户控制

## 维护规则

读取已有 Skill 或 AGENTS.md 时，如果发现内容过时、不完整或有误，**先通过 `/ax:ax` 准备更新提案**，再经用户确认后写入。不要直接修改知识文件。

## 多 Agent 范围

当前 `/ax:ax` 适配两类 agent：

- **Claude Code**：允许读取当前会话与 `~/.claude/projects` 下的本地历史
- **Codex**：只读取当前会话上下文、git 变更和本次任务涉及的文件；不要猜测私有 transcript 路径

在一次运行中，只能使用与**当前 agent**匹配的那一个历史 adapter，不能混读另一个 agent 的本地日志。

## 输出格式

### AGENTS.md 模板

```markdown
# {模块名}

## Overview
模块职责简述。

## Module Index
- @{子模块}/AGENTS.md — 说明

## Deep Dive Docs
- @docs/ai-context/{topic}.md — 说明
```

### Skill 模板

```markdown
---
name: {skill-name}
description: "{什么场景下使用}"
---

# {Skill Title}

## When to Use
触发条件。

## Steps
1. 步骤一
2. 步骤二

## Examples
具体示例。
```

## 跨 Agent 兼容

沉淀产物使用通用格式，不依赖任何特定 agent 的私有机制：

| 产物 | 路径 | 消费方式 |
|------|------|---------|
| 项目入口 | `AGENTS.md` | 所有 agent 读取；Claude Code 通过 `CLAUDE.md → AGENTS.md` 软链接 |
| 架构知识 | `docs/ai-context/*.md` | 通过 `@` 引用被任何 agent 发现 |
| 项目技能 | `.agents/skills/*/SKILL.md` | 通用 skill 格式，各 agent 按自身机制发现 |
| 模块上下文 | `{module}/AGENTS.md` | 目录遍历发现，任何 agent 可读 |
