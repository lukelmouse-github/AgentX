---
name: setup
description: "Initialize AX config in the current project — creates .ax/config with default scoring settings."
---

# AX Setup

Initialize AX configuration for the current project.

## Steps

### 1. Check if already initialized

```bash
test -f .ax/config && echo "EXISTS" || echo "MISSING"
```

If `EXISTS`, tell the user `.ax/config` already exists and ask if they want to reset it to defaults. Stop if they say no.

### 2. Create .ax/config

Create the file `.ax/config` in the project root with the default template below:

```
# AX 评分配置 — 直接修改值即可生效，保存后下次触发自动读取

# 触发后台 review 的总分阈值
# 越高越不敏感（review 越少），越低越敏感
AX_SCORE_THRESHOLD=100

# 每次 Agent/subagent 调用（Explore、general-purpose 等）的分值
# Agent 调用意味着多步骤的重度工作
AX_WEIGHT_AGENT=30

# 每次 Edit 或 Write 调用的分值
# 文件修改是实质性工作的强信号
AX_WEIGHT_EDIT=8

# 每次 Bash 调用的分值
# Shell 命令代表中等复杂度的操作
AX_WEIGHT_BASH=3

# 每次 Read 调用的分值
# 文件读取较轻量，多为探索性操作
AX_WEIGHT_READ=1

# 每次 brainstorming skill 调用的分值
# 头脑风暴几乎总会产出可 review 的决策
AX_WEIGHT_BRAIN=80

# 评分窗口内每 100 行 transcript 的分值
# 长对话通常意味着复杂的交互
AX_WEIGHT_LINES=10

# 评分窗口包含最近几轮用户对话
# 越大捕获越多多轮工作，越小反应越快
AX_WINDOW_TURNS=3

# 同一 session 两次 review 之间的最小间隔（秒）
# 防止持续编码时频繁触发 review
AX_REVIEW_COOLDOWN=600

# ── Review 输出语言 ──
# 生成的 md 文档、skill、AGENTS.md 等内容使用的语言
# 可选值：中文、English、日本語 等
AX_REVIEW_LANGUAGE="中文"

# ── Review 自定义提示词 ──
# 达到评分阈值后，LLM 会判断对话是否包含可沉淀的知识
# 在这里写入项目特定的指令，会追加到 review 提示词末尾
# 例如：关注哪些模块、忽略哪些内容、输出语言偏好等
# 支持多行，用引号包裹（注意结尾引号）
# AX_REVIEW_INSTRUCTIONS="
# - 输出语言使用中文
# - 重点关注 src/core/ 下的架构变更
# - 忽略测试文件和配置文件的改动
# "
```

### 3. Add to .gitignore

Check if `.ax/` is already in `.gitignore`. If not, append it:

```bash
grep -qxF '.ax/' .gitignore 2>/dev/null || echo '.ax/' >> .gitignore
```

### 4. Report

Tell the user:
- `.ax/config` created，默认值已生效
- 直接修改数值保存即可，下次触发自动读取
- `AX_REVIEW_INSTRUCTIONS` 默认注释，取消注释并填写内容即可生效
- `.ax/` added to `.gitignore`（配置仅本地生效，不会提交）
