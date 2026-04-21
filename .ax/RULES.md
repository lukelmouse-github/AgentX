# AX — 知识沉淀规则

## 核心约束

**所有知识沉淀必须通过 `/ax` skill 流程。** 不允许 agent 自行直接写入 `docs/ai-context/`、`.agents/skills/` 或 `AGENTS.md` 中的沉淀内容。`/ax` 流程包含物理验证（行数、重复、@ 引用）和用户确认，确保质量。

## 自动沉淀规则

完成以下类型的工作后，**调用 `/ax` 进行沉淀**（不要自行写入）：

- 多步骤调试（5+ 次工具调用）并最终定位到 root cause
- 发现代码中非显而易见的约定、陷阱或架构约束
- 实现了可复用的工作流（部署、排错、集成、迁移等）
- 修复了对团队有参考价值的 tricky bug

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

## 自修复规则

使用已有 Skill 或读取 AGENTS.md 时，如果发现内容**过时、不完整或有误**，立即更新——不要等人要求。不维护的文档会变成误导。

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

## 多工具兼容

| 工具 | 指令文件 | 技能目录 | 兼容方式 |
|------|---------|---------|---------| 
| Claude Code | CLAUDE.md | .claude/skills/ | 软链接 → .agents/skills |
| Codex | AGENTS.md | .agents/skills/ | 原生 |
| Cursor | .cursorrules | — | @ 引用 AGENTS.md |
