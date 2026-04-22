# AX — 项目知识沉淀插件

AX 是一个 Claude Code plugin。它把 agent 在编码、排障、设计过程里产生的可复用经验，沉淀到项目仓库里，再通过 git 共享给团队和其他 coding agent。

## 为什么需要 AX

Coding agent 每次对话都在产生有价值的知识——架构分析、排障结论、设计决策——但这些知识在对话结束后就消失了。没有 AX 时，每次 agent 接触同一个模块都要重新读文件、重新推理，重复消耗 token。团队里一个人踩过的坑，其他人还会再踩一遍。

AX 补上了从"产生知识"到"团队共享"的闭环：自动检测哪些对话值得沉淀，生成预览让人确认，写入 git 可追踪的通用路径，所有 agent 和所有团队成员都能消费。

### 知识管理能力对比

| 能力 | AX | Claude Code | Codex | Hermes Agent | OpenClaw |
|------|:---:|:---:|:---:|:---:|:---:|
| **自动检测值得沉淀的对话** | ✅ | — | — | ✅ | — |
| **知识写入 git 共享路径** | ✅ | — | — | — | — |
| **团队成员可消费** | ✅ | — | — | — | ✅ |
| **跨 agent 通用格式** | ✅ | — | ✅ | — | ✅ |
| **设计/探索类对话也能触发** | ✅ | — | — | — | — |
| **项目技能沉淀（git tracked）** | ✅ | — | — | — | — |
| **个人记忆** | — | ✅ | — | ✅ | ✅ |
| **agent 自我进化（私有 skill）** | — | — | — | ✅ | ✅ |
| **跨会话历史搜索** | — | — | — | ✅ | ✅ |
| **作为插件无侵入集成** | ✅ | — | — | — | — |

**关键区别：**

- **Hermes Agent / OpenClaw** 的知识闭环是"agent 自己学、自己用"——skill 和 memory 存在 agent 私有目录，换个人、换个 agent 就失效
- **Claude Code / Codex** 有一定的记忆能力，但不会主动检测和提示沉淀
- **AX** 的定位是**项目知识资产管理**：知识属于项目而非个人，通过 git 共享给整个团队和所有 agent，写入由后台 LLM 自动完成

核心原则：

- 知识是项目资产，不是某个 agent 的私有记忆
- 项目知识只写入 `AGENTS.md`、`docs/ai-context/`、`.agents/skills/`
- 沉淀在 session 中自动触发，后台 LLM 判断并直接写入
- 沉淀产物使用通用格式，任何 coding agent 都能消费

## 安装

```bash
# 1. 添加 marketplace
/plugin marketplace add lukelmouse-github/AgentX

# 2. 安装插件（选择 project scope 以便团队共享）
/plugin install ax@lukelmouse-github

# 3. 开启自动更新（可选，推荐）
#    /plugin → Marketplaces → 选择 lukelmouse-github → Enable auto-update
```

本地开发测试：

```bash
claude --plugin-dir /path/to/ax
```

安装后 AX 提供 skill 和自动 hook，无需改动项目文件。

### 启用状态栏（可选，推荐）

安装后运行 `/ax:setup` 即可在终端底部显示沉淀进度指示器。也可以手动配置 `~/.claude/settings.json`：

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash <AX_PLUGIN_ROOT>/scripts/status-line.sh",
    "refreshInterval": 3
  }
}
```

启用后效果：

```text
AX  heavy ●○○  brain ○○○        ← 积累中，距离触发还差
AX  heavy ●●○  brain ●●○        ← 接近触发，颜色变亮
AX ● triggered · debounce 42s   ← 已触发，等待冷却
AX ⟳ reviewing transcript…      ← 后台 LLM 正在审查
AX ✓ sediment written            ← 沉淀完成
AX · nothing to save             ← 审查后无需沉淀
```

## 提供的能力

### Skills

| Skill | 调用方式 | 用途 |
|-------|---------|------|
| **ax** | `/ax:ax` 或 `/ax:ax <prompt>` | 从当前对话中提取知识，沉淀到项目知识库 |
| **setup** | `/ax:setup` | 启用 AX 状态栏，显示沉淀进度 |

### Hooks

| 事件 | 行为 |
|------|------|
| **PostToolUse** | 异步追踪工具调用，满足触发条件后 debounce 1 分钟，后台启动 `claude -p` 读取 transcript 判断并写入知识 |

## 使用方式

### 初次设置

无需配置。安装后 AX 自动在 session 中追踪工具调用模式，检测到深度工作后由 LLM 判断是否沉淀。

### 日常使用

```text
/ax:ax                           # 全量扫描当前任务，推荐值得沉淀的内容
/ax:ax 刚才排查的内存泄漏流程      # 围绕特定主题提炼
/ax:ax architecture              # 仅更新架构知识
/ax:ax skill debug-build-cache   # 创建或更新指定项目技能
```

### 自动沉淀

PostToolUse hook 在每次工具调用后异步追踪 session 状态。满足以下任一条件即触发沉淀检查（OR）：

- 检测到 3 次 brainstorming skill 调用
- 检测到 3 轮重对话（单轮工具调用 >= 10 次）

触发后 debounce 1 分钟——如果用户仍在密集操作则延后，确保不打断工作。debounce 到期后，后台启动 `claude -p --bare` 读取当前 session 的完整 transcript，由 LLM 判断是否有值得沉淀的知识并直接写入项目。用户可以通过 `git diff` 查看、`git checkout -- <file>` 撤销不需要的内容。

## 沉淀产物

所有知识只写入通用路径，不依赖任何 agent 专属目录：

```text
{project}/
├── AGENTS.md               # 项目主入口（所有 agent 可读）
├── CLAUDE.md -> AGENTS.md  # Claude Code 入口（软链接）
├── docs/ai-context/        # 架构、约定、排障结论
├── .agents/skills/         # 可复用项目技能
└── .ax/
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

### 3. 两种触发方式

- **自动**：PostToolUse hook 检测到深度工作后，后台 `claude -p` 读取 transcript 并直接写入
- **手动**：用户执行 `/ax:ax`，在当前对话中预览并确认后写入

## Plugin 目录结构

```text
ax/
├── .claude-plugin/
│   └── plugin.json                    # Plugin manifest
├── hooks/
│   └── hooks.json                     # PostToolUse only
├── skills/
│   ├── ax/SKILL.md                    # 主沉淀 skill（/ax:ax）
│   └── setup/SKILL.md                 # 状态栏启用 skill（/ax:setup）
├── scripts/
│   ├── post-tool-use.sh               # PostToolUse hook（状态追踪 + 触发检测 + debounce）
│   ├── ax-review.sh                   # 后台 claude -p 审查执行体
│   └── status-line.sh                 # 状态栏渲染脚本
├── RULES.md                           # 沉淀规则
└── README.md
```

## 开发与验证

```bash
bash tests/plugin_smoke.sh
```
