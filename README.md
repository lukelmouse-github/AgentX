# AX — 项目知识沉淀插件

AX 是一个 Claude Code plugin。它把 agent 在编码、排障、设计过程里产生的可复用经验，沉淀到项目仓库里，再通过 git 共享给团队和其他 coding agent。

## 为什么需要 AX

Coding agent 每次对话都在产生有价值的知识——架构分析、排障结论、设计决策——但这些知识在对话结束后就消失了。没有 AX 时，每次 agent 接触同一个模块都要重新读文件、重新推理，重复消耗 token。团队里一个人踩过的坑，其他人还会再踩一遍。

AX 补上了从"产生知识"到"团队共享"的闭环：自动检测哪些对话值得沉淀，后台 LLM 判断并写入 git 可追踪的通用路径，所有 agent 和所有团队成员都能消费。

核心原则：

- 知识是项目资产，不是某个 agent 的私有记忆
- 沉淀产物写入 `AGENTS.md`、`docs/ai-context/`、`.agents/skills/`、模块级 `AGENTS.md`
- 沉淀在 session 中自动触发，后台 LLM 判断并直接写入
- 产物使用通用格式，任何 coding agent 都能消费

## 安装

```bash
# 添加 marketplace 并安装
/plugin marketplace add lukelmouse-github/AgentX
/plugin install ax@lukelmouse-github

# 本地开发测试
claude --plugin-dir /path/to/ax
```

安装后运行 `/ax:setup` 初始化项目配置（创建 `.ax/config`）。

## 提供的能力

### Skills

| Skill | 调用方式 | 用途 |
|-------|---------|------|
| **ax** | `/ax:ax` 或 `/ax:ax <prompt>` | 手动从当前对话中提取知识，预览确认后写入 |
| **setup** | `/ax:setup` | 初始化项目配置，创建 `.ax/config` |

### Hooks

| 事件 | 行为 |
|------|------|
| **Stop** | 每轮对话结束后，对最近 N 轮进行加权评分，达到阈值后启动后台 LLM review |

## 自动沉淀机制

### 加权评分

Stop hook 在每轮结束时，对最近 N 轮对话（默认 3 轮）内的工具调用进行加权打分：

| 信号 | 默认权重 | 说明 |
|------|---------|------|
| Agent/subagent 调用 | 30 | 多步骤重度工作 |
| Edit/Write 调用 | 8 | 文件修改 |
| Bash 调用 | 3 | Shell 操作 |
| Read 调用 | 1 | 文件读取 |
| brainstorming skill | 80 | 设计决策 |
| 每 100 行 transcript | 10 | 对话复杂度 |

总分达到阈值（默认 100）后触发后台 review。

### 两层过滤

1. **评分门槛**（廉价）— 加权打分，低于阈值直接跳过
2. **LLM 判断**（昂贵）— 后台 `claude -p --model sonnet` 读取 transcript，判断是否有可沉淀知识并直接写入

### 防护机制

- 同一 session 已有 review 在运行时不重复触发
- 两次 review 之间有冷却期（默认 600 秒）
- 用户手动执行过 `/ax:ax` 时不再自动触发

### 日志

所有状态记录在 `~/.ax/log.log`（循环 300 行）：

```text
STOP: scoring agents=2(*30) edits=3(*8) ... => score=120/100
STOP: threshold met, checking guards
REVIEW: started ...
REVIEW: completed — changes:
REVIEW:   AGENTS.md                          | 12 ++++
REVIEW:   docs/ai-context/coroutine-model.md | 37 ++++++
REVIEW: completed — new files:
REVIEW:   docs/ai-context/api-gotchas.md
```

## 项目配置

运行 `/ax:setup` 创建 `.ax/config`，直接修改值保存即可生效：

```bash
# 触发阈值（越高越不敏感）
AX_SCORE_THRESHOLD=100

# 各信号权重
AX_WEIGHT_AGENT=30
AX_WEIGHT_EDIT=8
AX_WEIGHT_BASH=3
AX_WEIGHT_READ=1
AX_WEIGHT_BRAIN=80
AX_WEIGHT_LINES=10

# 评分窗口（最近几轮对话）
AX_WINDOW_TURNS=3

# review 冷却时间（秒）
AX_REVIEW_COOLDOWN=600

# 沉淀产物输出语言（默认中文）
AX_REVIEW_LANGUAGE="中文"

# 自定义 review 提示词（追加到 LLM review 提示词末尾）
# AX_REVIEW_INSTRUCTIONS="
# - 重点关注 src/core/ 下的架构变更
# - 忽略测试文件的改动
# "
```

`.ax/` 会被加入 `.gitignore`，配置仅本地生效。

## 沉淀产物

所有知识写入通用路径，不依赖 agent 专属目录：

```text
{project}/
├── AGENTS.md                    # 项目主入口
├── docs/ai-context/             # 架构、约定、排障结论
├── .agents/skills/              # 可复用项目技能
├── {module}/AGENTS.md           # 模块级上下文
└── .ax/config                   # 项目配置（.gitignore）
```

## 手动使用

```text
/ax:ax                           # 全量扫描当前对话，推荐值得沉淀的内容
/ax:ax 刚才排查的内存泄漏流程      # 围绕特定主题提炼
/ax:ax architecture              # 仅更新架构知识
/ax:ax skill debug-build-cache   # 创建或更新指定项目技能
```

手动模式下会预览并等待确认后再写入。

## Plugin 目录结构

```text
ax/
├── hooks/
│   └── hooks.json          # Stop hook 配置
├── skills/
│   ├── ax/SKILL.md         # 主沉淀 skill（/ax:ax）
│   └── setup/SKILL.md      # 项目初始化 skill（/ax:setup）
├── scripts/
│   ├── stop-hook.sh        # Stop hook（加权评分 + 触发检测）
│   ├── ax-review.sh        # 后台 LLM review 执行体
│   └── ax-log.sh           # 日志工具
├── tests/
│   └── plugin_smoke.sh     # 冒烟测试
├── RULES.md                # 沉淀规则
└── README.md
```

## 开发与验证

```bash
bash tests/plugin_smoke.sh
```
