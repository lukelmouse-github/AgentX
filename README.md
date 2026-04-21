# AX — 项目知识自动沉淀插件

## 概述

AX 是一个项目级 Claude Code 插件，通过 prompt 注入让 AI agent 自主判断何时沉淀知识，将有价值的技术实践沉淀为 Markdown 文档和 Skill 文件，团队通过 git 共享。

**核心原则：**
- prompt 驱动：agent 自主判断沉淀时机，无需硬编码规则
- 所有写入需人工确认
- 输出兼容 Claude Code / Codex / Cursor
- 分级目录、@ 引用、每文件 <200 行

## 安装

### 一键安装（团队中一人执行即可）

```bash
# 在项目目录下运行
curl -fsSL https://raw.githubusercontent.com/anthropics/ax/main/install.sh | bash

# 或指定项目路径
curl -fsSL https://raw.githubusercontent.com/anthropics/ax/main/install.sh | bash -s -- /path/to/project
```

然后提交：

```bash
git add .ax .claude
git commit -m 'chore: add AX knowledge sedimentation plugin'
```

**队友只需 `git pull`，之后直接 `claude` 启动即可，无需任何额外操作。**

脚本做了什么：
1. 将 AX 源码嵌入项目 `.ax/` 目录（去掉 git 历史）
2. 在 `.claude/skills/` 建立相对路径软链接
3. 在项目级 `.claude/settings.json` 追加 SessionStart hook（不修改已有 hooks）

所有配置都在项目内部，使用相对路径，任何人 clone 后开箱即用。

## 沉淀机制

### 双层架构：规则文件 + Hook 提醒

AX 采用双层方式确保 agent 遵守沉淀规则：

**第一层：`.ax/RULES.md`（核心规则）**
- 定义完整的沉淀触发条件、流程、格式规范
- 通过根 AGENTS.md 的 `@.ax/RULES.md` 引用加载
- 团队可见可改，通过 git 管理和迭代

**第二层：SessionStart hook（轻量提醒）**
- 每次会话启动注入一句话："After complex tasks, evaluate whether to sediment knowledge per @.ax/RULES.md"
- 强化 agent 对沉淀规则的记忆，提高自动沉淀概率

### Prompt 驱动自动沉淀

agent 根据 `.ax/RULES.md` 中的规则自主判断是否需要沉淀：

- 多步骤调试（5+ 次工具调用）并定位到 root cause
- 发现代码中非显而易见的约定或陷阱
- 实现了可复用的工作流（部署、排错、集成等）
- 修复了对团队有参考价值的 tricky bug

agent 沉淀时会：
1. 判断类型：skill（可复用流程）还是 knowledge（架构/约定/陷阱）
2. 写入对应路径，每文件 < 200 行
3. 更新父级 AGENTS.md 的 @ 引用
4. **请求用户确认后才写入**

### 手动触发 (/ax)

```bash
/ax                                  # 全面分析，推荐沉淀内容
/ax 刚才排查的内存泄漏流程             # 围绕重点提取
/ax architecture                     # 仅更新架构文档
/ax skill debug-memory               # 创建/更新指定技能
```

prompt 可以是中文或英文自由描述，AX 围绕重点提取。无 prompt 时全面扫描。

### 自修复

agent 使用已有 skill 或读取 AGENTS.md 时，如果发现内容过时、不完整或有误，会**立即更新**，不等人要求。沉淀的知识随项目迭代持续进化。

## 架构

```
┌──────────────────────────────────────────────────────────┐
│                     触发入口                              │
│  ├── .ax/RULES.md       核心规则（@ 引用加载）            │
│  ├── SessionStart hook  轻量提醒（强化记忆）              │
│  ├── /ax [prompt]       手动触发                         │
│  └── CI Pipeline        定时/PR 触发（见下方 CI 章节）    │
├──────────────────────────────────────────────────────────┤
│  处理流程                                                │
│  ├── 收集数据                                            │
│  │   └── 当前会话上下文 + git 变更                        │
│  ├── 分析 & 提取                                         │
│  ├── 预览 → 用户确认                                     │
│  └── 写入文件 + 更新 @ 引用                               │
├──────────────────────────────────────────────────────────┤
│  输出目录（git tracked，团队共享）                         │
│  ├── docs/ai-context/       架构知识                     │
│  ├── .agents/skills/        项目技能                     │
│  └── {module}/AGENTS.md     模块文档                     │
└──────────────────────────────────────────────────────────┘
```

## 文件结构

### 项目级（git 同步，团队共享）

```
{project}/
├── .ax/                            # AX 插件源码（install.sh 嵌入）
│   ├── RULES.md                    # 沉淀规则（核心）
│   ├── hooks/                      # hook 脚本
│   ├── skills/                     # skill 源文件
│   └── install.sh
├── .claude/
│   ├── settings.json               # hooks 配置（相对路径，跨机器可用）
│   └── skills/
│       └── ax → ../../.ax/skills/ax
├── AGENTS.md                       # 主入口（含 @.ax/RULES.md 引用）
├── CLAUDE.md → AGENTS.md           # 软链接兼容 Claude
└── docs/ai-context/                # 知识输出目录
```

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

## CI 集成：文档过时检测

文档过时检测适合放在 CI 流程中，而非本地 hooks，原因：
- 不干扰本地开发体验
- 覆盖所有团队成员的变更
- 结果可追溯，与 PR 流程结合

### 设计方案

#### 触发时机

在 PR 合并到主分支后，或定时（如每日/每周）运行。

#### 检测逻辑

```yaml
# .github/workflows/ax-stale-check.yml
name: AX Stale Docs Check
on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'lib/**'
  schedule:
    - cron: '0 9 * * 1'  # 每周一早 9 点

jobs:
  check-stale:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Detect stale docs
        run: |
          # 找出所有 AGENTS.md 和 docs/ai-context/*.md
          # 对每个文档，提取其中引用的源文件路径
          # 比对：源文件最近修改时间 vs 文档最近修改时间
          # 输出过时的文档列表

          stale_docs=""
          for doc in $(find . -name "AGENTS.md" -o -path "*/docs/ai-context/*.md"); do
            # 提取文档中 @ 引用的文件路径和代码块中的文件路径
            refs=$(grep -oP '@[\w/.,-]+\.\w+' "$doc" 2>/dev/null || true)
            doc_time=$(git log -1 --format=%ct -- "$doc" 2>/dev/null || echo 0)

            for ref in $refs; do
              ref_path="${ref#@}"
              if [ -f "$ref_path" ]; then
                ref_time=$(git log -1 --format=%ct -- "$ref_path" 2>/dev/null || echo 0)
                if [ "$ref_time" -gt "$doc_time" ]; then
                  stale_docs+="- $doc (referenced $ref_path changed)\n"
                  break
                fi
              fi
            done
          done

          if [ -n "$stale_docs" ]; then
            echo "::warning::Stale docs detected"
            printf "$stale_docs"
            # 可选：创建 issue 或发通知
          fi

      - name: Create issue if stale
        if: failure() || steps.check-stale.outputs.stale_docs != ''
        uses: actions/github-script@v7
        with:
          script: |
            // 自动创建 issue 提醒团队更新过时文档
            // 或在 Slack/飞书 发通知
```

#### 进阶：CI 中自动更新

```yaml
# 使用 claude CLI 在 CI 中自动更新过时文档并提 PR
- name: Auto-update stale docs
  run: |
    claude -p "/ax update stale docs based on recent code changes"
  env:
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

这样形成完整闭环：
```
开发者写代码 → CI 检测文档过时 → 自动/手动更新 → PR review → 合并
```

## 命令清单

| 命令 | 功能 |
|------|------|
| `/ax` | 全面分析，推荐沉淀内容 |
| `/ax {prompt}` | 围绕重点提取（支持中英文） |
| `/ax architecture` | 仅更新架构文档 |
| `/ax skill {name}` | 创建/更新指定技能 |
