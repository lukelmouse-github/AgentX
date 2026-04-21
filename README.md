# AX — 项目知识沉淀插件

AX 是一个 Claude Code plugin。它把 agent 在编码、排障、设计过程里产生的可复用经验，沉淀到项目仓库里，再通过 git 共享给团队和其他 coding agent。

核心原则：

- 知识是项目资产，不是某个 agent 的私有记忆
- 项目知识只写入 `AGENTS.md`、`docs/ai-context/`、`.agents/skills/`
- 沉淀自动触发分析和预览，写入需要人工确认
- 沉淀产物使用通用格式，任何 coding agent 都能消费

## 安装

```bash
# 1. 添加 marketplace
/plugin marketplace add lukelmouse-github/AgentX

# 2. 安装插件
/plugin install ax@lukelmouse-github
```

本地开发测试：

```bash
claude --plugin-dir /path/to/ax
```

安装后 AX 提供两个 skill 和四个自动 hook，无需改动项目文件。

## 提供的能力

### Skills

| Skill | 调用方式 | 用途 |
|-------|---------|------|
| **ax** | `/ax:ax` 或 `/ax:ax <prompt>` | 从当前对话中提取知识，沉淀到项目知识库 |
| **init** | `/ax:init` | 为项目生成自定义的沉淀评估配置 `.ax/profile.yaml` |

### Hooks

| 事件 | 行为 |
|------|------|
| **SessionStart** | 注入沉淀提醒到 agent 上下文，清理旧信号文件 |
| **PostToolUse** | 每次工具调用后异步记录信号到 `/tmp/ax-signals-{session_id}.jsonl` |
| **Stop** | 读取积累的信号 + 项目 profile，达标时自动执行 `/ax:ax` 分析和预览 |
| **UserPromptSubmit** | 检测用户拒绝沉淀建议，注入反思提示帮助优化 profile |

## 使用方式

### 初次设置

安装 plugin 后，在项目里运行 `/ax:init`。它会分析项目结构，生成 `.ax/profile.yaml` 配置，定义什么样的工作值得触发沉淀。

### 日常使用

```text
/ax:ax                           # 全量扫描当前任务，推荐值得沉淀的内容
/ax:ax 刚才排查的内存泄漏流程      # 围绕特定主题提炼
/ax:ax architecture              # 仅更新架构知识
/ax:ax skill debug-build-cache   # 创建或更新指定项目技能
```

### 自动提示

PostToolUse hook 在每次工具调用后异步积累信号（工具类型、文件路径、命令等）。Stop hook 在对话结束时读取这些信号，结合项目的 `.ax/profile.yaml`（通过 `/ax:init` 生成）评估是否达标。达标后 Claude 会自动执行 `/ax:ax` 分析并生成预览，用户确认后才写入。如果用户拒绝，UserPromptSubmit hook 会在下一轮注入反思提示，帮助识别误触发并优化 profile。没有 profile 时，使用保守的内置默认规则（如 `tool_count >= 50 and write_count >= 5`），确保只有深度工作才触发。运行 `/ax:init` 生成项目定制 profile 后可以大幅降低阈值。

## 沉淀产物

所有知识只写入通用路径，不依赖任何 agent 专属目录：

```text
{project}/
├── AGENTS.md               # 项目主入口（所有 agent 可读）
├── CLAUDE.md -> AGENTS.md  # Claude Code 入口（软链接）
├── docs/ai-context/        # 架构、约定、排障结论
├── .agents/skills/         # 可复用项目技能
└── .ax/
    └── profile.yaml        # 项目自定义的沉淀评估配置（/ax:init 生成）
```

| 产物 | 路径 | 说明 |
|------|------|------|
| 项目入口 | `AGENTS.md` | 所有 agent 通过 `AGENTS.md` 或 `CLAUDE.md` 读取 |
| 架构知识 | `docs/ai-context/{topic}.md` | 通过 `@` 引用被发现 |
| 项目技能 | `.agents/skills/{name}/SKILL.md` | 通用 skill 格式，git tracked |
| 模块上下文 | `{module}/AGENTS.md` | 目录遍历发现 |

## `/ax:ax` 的工作方式

### 1. 只使用当前 agent 对应的历史 adapter

- **Claude Code**：当前会话 + git 变更 + `~/.claude/projects` 下最近会话
- **Codex**：当前会话 + git 变更 + 本次任务读写过的文件

同一次运行中，不混读另一个 agent 的本地历史。

### 2. 只输出到通用知识路径

- 架构/约定/排障结论 → `docs/ai-context/{topic}.md`
- 可复用流程 → `.agents/skills/{name}/SKILL.md`
- 模块上下文 → `{module}/AGENTS.md`

### 3. 永远先预览再写入

Stop hook 达标后自动执行分析和预览。展示目标路径、完整内容预览、为什么值得沉淀，然后等待用户确认。没有确认不落盘。

## Plugin 目录结构

```text
ax/
├── .claude-plugin/
│   └── plugin.json                    # Plugin manifest
├── hooks/
│   └── hooks.json                     # SessionStart + PostToolUse + UserPromptSubmit + Stop
├── skills/
│   ├── ax/SKILL.md                    # 主沉淀 skill
│   └── init/SKILL.md                  # Profile 初始化 skill
├── scripts/
│   ├── session-start.sh               # SessionStart hook（上下文注入 + 清理）
│   ├── post-tool-use.sh               # PostToolUse hook（信号积累）
│   ├── stop-check.sh                  # Stop hook（评估 + 自动触发）
│   ├── user-prompt-submit.sh          # UserPromptSubmit hook（拒绝检测 + 反思）
│   └── eval_profile.py                # 核心评估引擎（读 profile + 信号）
├── RULES.md                           # 沉淀规则
└── README.md
```

## 开发与验证

```bash
bash tests/plugin_smoke.sh
```
