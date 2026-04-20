# AX — 项目知识自动沉淀插件

## 概述

AX 是一个项目级 Claude Code 插件，通过分析会话内容和 claude-mem 历史数据，将有价值的知识沉淀为 Markdown 文档和 Skill 文件，团队通过 git 共享。

**核心原则：**
- 所有写入需人工确认
- 输出兼容 Claude Code / Codex / Cursor
- 分级目录、@ 引用、每文件 <200 行
- claude-mem 可用时增强，不可用时降级
- 全局默认关闭，项目级明确开启

## 安装

### 一键安装（团队中一人执行即可）

```bash
# 在项目目录下运行
curl -fsSL https://raw.githubusercontent.com/lukelmouse-github/AgentX/main/install.sh | bash

# 或指定项目路径
curl -fsSL https://raw.githubusercontent.com/lukelmouse-github/AgentX/main/install.sh | bash -s -- /path/to/project
```

然后提交：

```bash
git add .ax .ax.json .claude
git commit -m 'chore: add AX knowledge sedimentation plugin'
```

**队友只需 `git pull`，之后直接 `claude` 启动即可，无需任何额外操作。**

脚本做了什么：
1. 将 AX 源码嵌入项目 `.ax/` 目录（去掉 git 历史）
2. 在 `.claude/skills/` 建立相对路径软链接
3. 在项目级 `.claude/settings.json` 配置 hooks（不影响用户全局配置）
4. 安装 git `post-commit` hook（手动 commit 后提示是否运行 AX）
5. 创建 `.ax.json` 启用

所有配置都在项目内部，使用相对路径，任何人 clone 后开箱即用。

### 启用/禁用

AX 通过项目根目录的 `.ax.json` 控制开关：

```json
{"enabled": true}
```

没有这个文件或 `enabled` 不为 `true` 的项目，AX 的所有 hooks 和功能都不会生效。

## 触发方式

### 1. 手动触发

```bash
/ax                                  # 全面分析，推荐沉淀内容
/ax 刚才排查的diff渲染bug流程          # 围绕重点提取
/ax architecture                     # 仅更新架构文档
/ax skill debug-diff                 # 创建/更新指定技能
```

prompt 可以是中文或英文自由描述，AX 围绕重点提取。无 prompt 时全面扫描。

### 2. Git Commit 自动提示

在 Claude Code **外部**手动 `git commit` 后，会自动弹出提示：

```
[ax] Commit a1b2c3d: fix: resolve cache invalidation bug
[ax] Run AX to extract knowledge from this session? [y/N]
```

输入 `y` 自动启动 Claude Code 执行 `/ax` 分析并沉淀知识，输入 `n` 或直接回车跳过。

> 在 Claude Code 会话内的 commit 不会触发此提示（由 SessionEnd hook 处理）。

### 3. SessionEnd 自动提示

会话结束时自动检测是否有值得沉淀的内容。通过增量检测 + 价值评估决定是否提示。

### 4. 项目级开关

AX 全局默认关闭。在项目根目录创建 `.ax.json` 启用：

```json
{"enabled": true}
```

设为 `false` 或删除文件即可禁用。

## 架构

```
┌──────────────────────────────────────────────────────────┐
│                     触发入口                              │
│  ├── /ax [prompt]         手动                           │
│  └── SessionEnd hook      自动提示                       │
├──────────────────────────────────────────────────────────┤
│  ax skill (SKILL.md)                                    │
│  ├── 检测 claude-mem 可用性                              │
│  ├── 收集数据                                            │
│  │   ├── 当前会话上下文（始终可用）                        │
│  │   └── claude-mem 历史（增强模式）                      │
│  ├── 分析 & 提取                                         │
│  ├── 预览 → 用户确认                                     │
│  └── 写入文件 + 更新 @ 引用                               │
├──────────────────────────────────────────────────────────┤
│  输出目录（git tracked，团队共享）                         │
│  ├── docs/ai-context/       架构知识                     │
│  ├── .agents/skills/        项目技能                     │
│  ├── {module}/AGENTS.md     模块文档                     │
│  └── ~/.claude/skills/      全局通用技能（可选）          │
└──────────────────────────────────────────────────────────┘
```

## 文件结构

### 项目级（git 同步，团队共享）

```
{project}/
├── .ax/                            # AX 插件源码（install.sh 嵌入）
│   ├── hooks/                      # hook 脚本
│   ├── skills/                     # skill 源文件
│   └── install.sh
├── .ax.json                        # 项目开关 {"enabled": true}
├── .claude/
│   ├── settings.json               # hooks 配置（相对路径，跨机器可用）
│   └── skills/
│       ├── ax → ../../.ax/skills/ax
│       ├── ax-merge → ../../.ax/skills/ax-merge
│       └── ax-status → ../../.ax/skills/ax-status
├── AGENTS.md                       # 主入口（Codex 原生）
├── CLAUDE.md → AGENTS.md           # 软链接兼容 Claude
└── docs/ai-context/                # 知识输出目录
```

### 用户级（不同步，个人私有）

```
~/.claude-ax/
├── {project-hash}/
│   └── {session-id}.json           # 上次 /ax 时间戳
└── config.json                     # 个人配置（阈值等）
```

## 核心流程

### 手动流程 (/ax)

```
/ax [prompt]
    │
    ▼
┌──────────────────────────────────┐
│ 1. 检测环境                       │
│    ├── claude-mem 可用？→ 增强    │
│    └── 不可用？→ 基础模式         │
└──────────────────────────────────┘
    │
    ▼
┌──────────────────────────────────┐
│ 2. 收集数据                       │
│    ├── 当前会话上下文（始终）      │
│    └── claude-mem（如可用）       │
│        └── 语义搜索相关历史       │
└──────────────────────────────────┘
    │
    ▼
┌──────────────────────────────────┐
│ 3. 分析 & 提取                    │
│    ├── 有 prompt → 围绕重点提取   │
│    └── 无 prompt → 全面扫描推荐   │
│    识别知识类型：                  │
│    ├── architecture              │
│    ├── skill                     │
│    └── module-doc                │
└──────────────────────────────────┘
    │
    ▼
┌──────────────────────────────────┐
│ 4. 预览 & 确认                    │
│    ├── 展示将要写入的内容         │
│    ├── 展示目标路径               │
│    └── 用户确认 Y/N              │
└──────────────────────────────────┘
    │
    ▼
┌──────────────────────────────────┐
│ 5. 写入 & 更新引用                │
│    ├── 写入文件                   │
│    ├── 更新父级 AGENTS.md @ 引用  │
│    └── 不自动 commit             │
└──────────────────────────────────┘
```

### 自动流程（SessionEnd）

```
SessionEnd hook 触发
    │
    ▼
读取 last_ax_ts（上次 /ax 时间戳）
    │
    ▼
查询 claude-mem：since=last_ax_ts 的新 observations
    │
    ▼
价值评估
    │
    ├── 得分 < 阈值 → 静默退出
    │
    └── 得分 >= 阈值 → 输出提示
         "检测到 N 个新操作，包含 M 个决策。运行 /ax？"
```

## 增量检测与去重

### 时间戳机制

每次 `/ax` 执行时，记录当前时间戳到 `~/.claude-ax/{project-hash}/{session-id}.json`。

SessionEnd 触发时，读取 last_ax_ts，只分析此后的内容。

### 价值评估规则

| 信号 | 权重 | 说明 |
|------|------|------|
| observation 数量 > 5 | + | 有足够内容 |
| 包含 decision 类型 | ++ | 有决策价值 |
| 包含 bugfix 类型 | ++ | 可沉淀为调试技能 |
| 包含 discovery 类型 | ++ | 新发现 |
| 代码文件变更 > 3 | + | 有实质工作 |
| 会话时长 > 10min | + | 不是简单问答 |
| 仅 read 操作 | - | 低价值 |

得分低于阈值时不提示用户。

## 输出规范

### 文件约束

- 每个 md 文件不超过 200 行
- 使用 @ 引用关联深度文档
- 遵循 AGENTS.md 分级目录结构

### 输出类型与路径

| 类型 | 输出路径 | 示例 |
|------|---------|------|
| 架构知识 | `docs/ai-context/{topic}.md` | `docs/ai-context/cache-strategy.md` |
| 项目技能 | `.agents/skills/{name}/SKILL.md` | `.agents/skills/debug-diff/SKILL.md` |
| 模块文档 | `{module}/AGENTS.md` 追加/更新 | `src/AGENTS.md` |
| 通用技能 | `~/.claude/skills/{name}/SKILL.md` | 可选，需用户确认 |

### 写入后自动更新引用

写入新文件后，自动在最近的父级 AGENTS.md 中添加 @ 引用。例如：

```markdown
## Deep Dive Docs
- @docs/ai-context/cache-strategy.md — 缓存策略设计  ← 新增
```

## 兼容性

### 多工具兼容

| 工具 | 指令文件 | 技能目录 | 兼容方式 |
|------|---------|---------|---------|
| Claude Code | CLAUDE.md | .claude/skills/ | 软链接 → .agents/skills |
| Codex | AGENTS.md | .agents/skills/ | 原生 |
| Cursor | .cursorrules | — | @ 引用 AGENTS.md |

### claude-mem 降级

```
claude-mem 可用：
├── 读取历史 observations
├── 语义搜索相关内容
└── 增量检测（精确时间戳）

claude-mem 不可用：
├── 仅分析当前会话上下文
├── 无历史数据增强
└── 增量检测基于文件修改时间
```

## Git 冲突处理

### /ax-merge 命令

git pull/merge 后检测到知识文件冲突时，提示用户：

```
检测到 docs/ai-context/architecture.md 有冲突，
运行 /ax-merge 用 AI 辅助合并？
```

### 可选 post-merge hook

```bash
# .git/hooks/post-merge
if grep -r "<<<<<<" docs/ai-context/ .agents/skills/ 2>/dev/null; then
    echo "检测到知识文件冲突，运行 /ax-merge 用 AI 辅助合并"
fi
```

## 文档过时检测

沉淀的知识会随代码变更而过时。AX 通过两个机制检测过时文档。

### 机制 1：代码变更关联检测（SessionStart）

每次会话开始时，检查自上次会话以来的代码变更，与已有知识文档关联：

```
SessionStart hook
    │
    ▼
git diff --name-only HEAD~5    ← 最近 5 次提交变更的文件
    │
    ▼
扫描 docs/ai-context/*.md 和 AGENTS.md 中的文件引用
    │
    ▼
匹配：变更文件 ↔ 文档中引用的文件路径/类名
    │
    ├── 无匹配 → 正常
    │
    └── 有匹配 → 注入上下文提示
         "⚠ docs/ai-context/architecture.md 引用的
          PageManager.kt 已在最近提交中被修改，
          文档可能需要更新。"
```

### 机制 2：文档新鲜度检查（/ax-status）

```
/ax-status
    │
    ▼
遍历 docs/ai-context/ 和 .agents/skills/
    │
    ▼
对每个文档：
├── 提取文档中引用的源代码文件路径
├── 对比：文档最后修改时间 vs 源代码最后修改时间
└── 计算新鲜度得分

输出报告：
┌─────────────────────────────────────────────────────┐
│ 文档健康度报告                                        │
├──────────────────────────┬────────┬─────────────────┤
│ 文档                      │ 状态   │ 说明             │
├──────────────────────────┼────────┼─────────────────┤
│ architecture.md          │ ⚠ 过时  │ PageManager 已改 │
│ data-flow.md             │ ✅ 正常  │                  │
│ debug-diff/SKILL.md      │ ⚠ 过时  │ DiffManager 已改 │
│ scarlet.md               │ ✅ 正常  │                  │
└──────────────────────────┴────────┴─────────────────┘
│
└── "运行 /ax architecture 更新过时文档？"
```

### 文档元数据

每个 AX 生成的文档在末尾包含元数据注释，用于过时检测：

```markdown
<!-- ax-meta
sources:
  - src/core/page/PageManager.kt
  - src/common/manager/TaskManager.kt
generated: 2026-04-20
-->
```

- `sources`：该文档描述的源代码文件路径
- `generated`：生成/最后更新时间

过时检测通过比较 sources 中文件的 git 修改时间与 generated 时间来判断。

## 命令清单

| 命令 | 功能 |
|------|------|
| `/ax` | 全面分析，推荐沉淀内容 |
| `/ax {prompt}` | 围绕重点提取（支持中英文） |
| `/ax architecture` | 仅更新架构文档 |
| `/ax skill {name}` | 创建/更新指定技能 |
| `/ax-merge` | AI 辅助解决 md 冲突 |
| `/ax-status` | 查看文档健康度 + 过时检测报告 |
