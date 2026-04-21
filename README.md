# AX — 项目知识沉淀插件

AX 是一个项目级知识沉淀插件。它把 agent 在编码、排障、设计过程里产生的可复用经验，沉淀到项目仓库里，再通过 git 共享给团队和其他 agent。

当前版本先收敛支持两类 agent：

- Claude Code
- Codex

核心原则：

- 知识是项目资产，不是某个 agent 的私有记忆
- 项目知识只写入 `AGENTS.md`、`docs/ai-context/`、`.agents/skills/`
- 所有沉淀都必须经过 `/ax` 预览与人工确认
- Claude Code 通过适配层读取项目技能，Codex 直接读取项目知识

## 目录分层

安装到项目后，目录职责是：

```text
{project}/
├── .ax/                    # AX 运行时：hook、/ax skill、安装脚本、规则
│   ├── RULES.md
│   ├── hooks/
│   ├── skills/ax/
│   └── scripts/
├── AGENTS.md               # 项目主入口，Codex 原生读取
├── CLAUDE.md -> AGENTS.md  # Claude Code 入口
├── docs/ai-context/        # 项目知识文档
├── .agents/skills/         # 项目技能，git tracked，跨 agent 共享
└── .claude/skills/         # Claude Code 适配层（相对路径软链接）
```

这几个路径的职责不要混：

- `.ax/`：AX 自己的运行时文件
- `.agents/skills/`：项目技能的 canonical 路径
- `.claude/skills/`：Claude Code 的消费适配层，不是项目知识的真实归属

## 安装

### 远程安装

```bash
curl -fsSL https://raw.githubusercontent.com/lukelmouse-github/AgentX/main/install.sh | bash

# 或指定项目路径
curl -fsSL https://raw.githubusercontent.com/lukelmouse-github/AgentX/main/install.sh | bash -s -- /path/to/project
```

### 本地开发安装

```bash
AX_SOURCE_DIR=$(pwd) bash install.sh /path/to/project
```

脚本会做这几件事：

1. 将 AX payload 嵌入目标项目的 `.ax/`
2. 创建 `docs/ai-context/` 和 `.agents/skills/`
3. 为 Claude Code 写入 SessionStart hook
4. 将 `.claude/skills/ax` 指向 `.ax/skills/ax`
5. 将 `.claude/skills/*` 同步到 `.agents/skills/*`
6. 创建或补齐 `AGENTS.md` 与 `CLAUDE.md`

如果项目里已经有 `.claude/settings.json`，AX 在第一次改写前会把原文件备份到 `.git/ax-backups/settings.json`。

提交时请把完整入口一起提交：

```bash
git add .ax .agents .claude AGENTS.md CLAUDE.md docs/ai-context
git commit -m 'chore: add AX knowledge sedimentation'
```

## 使用方式

`/ax` 是 AX 自带的沉淀 skill。

```text
/ax
/ax <prompt>
/ax architecture
/ax skill <name>
```

典型用法：

- `/ax`：全量扫描当前任务，推荐值得沉淀的内容
- `/ax 刚才排查的内存泄漏流程`：围绕特定主题提炼
- `/ax architecture`：仅更新架构知识
- `/ax skill debug-build-cache`：创建或更新指定项目技能

## `/ax` 的工作方式

### 1. 只使用当前 agent 对应的历史 adapter

- **Claude Code**：读取当前会话、git 变更、`~/.claude/projects` 下最近会话
- **Codex**：读取当前会话、git 变更、本次任务读写过的文件

同一次 `/ax` 运行中，不混读另一个 agent 的本地历史。

### 2. 只输出到项目知识路径

- 架构/约定/排障结论 → `docs/ai-context/{topic}.md`
- 可复用流程 → `.agents/skills/{name}/SKILL.md`
- 模块上下文 → `{module}/AGENTS.md`

### 3. 永远先预览再写入

`/ax` 应该先展示：

- 目标路径
- 完整内容预览
- 为什么值得沉淀

然后等待用户确认。没有确认，不允许落盘。

## Claude Code 与 Codex 的区别

AX 不再试图让不同工具各自维护一份知识副本，而是让它们消费同一份项目知识。

| 工具 | 入口 | 技能读取 |
|------|------|---------|
| Claude Code | `CLAUDE.md` + SessionStart hook | `.claude/skills/` 软链接到 `.ax/skills/ax` 和 `.agents/skills/*` |
| Codex | `AGENTS.md` | `.agents/skills/` |

这意味着：

- 项目技能只写一次：`.agents/skills/`
- Claude Code 通过 adapter 看到它们
- Codex 直接读项目知识

## 规则入口

安装后，项目根 `AGENTS.md` 会通过 `@.ax/RULES.md` 引用 AX 规则。

规则文件定义了：

- 什么时候该沉淀
- 哪些内容不值得沉淀
- 沉淀到哪种路径
- `/ax` 的确认与验证约束
- Claude Code / Codex 两类 adapter 的边界

## 开发与验证

本仓库带了一个最基本的 smoke test，覆盖：

- 安装
- 重复安装幂等
- Claude settings 合并
- `.agents/skills` 到 `.claude/skills` 的同步
- 卸载

运行：

```bash
bash tests/install_smoke.sh
```
