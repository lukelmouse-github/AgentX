---
name: init
description: "为项目生成声明式沉淀评估配置 .ax/profile.yaml，替代默认的工具调用计数"
---

# AX Init — 项目沉淀评估 Profile 初始化

为当前项目生成一个 `.ax/profile.yaml` 配置文件。该文件在每轮对话结束时被 AX 的 Stop hook 读取，用于判断本次工作是否值得通过 `/ax:ax` 沉淀到项目知识库。

## 何时使用

- 项目首次安装 AX 后的初始化
- 默认的触发策略太频繁或太安静
- 项目结构发生重大变更，需要重新定义沉淀策略

## Profile 规范

生成的配置必须遵守以下格式：

```yaml
project:
  name: my-project
  type: web-api

signals:
  key_paths:
    - src/core/
    - src/api/
  test_patterns:
    - pytest
    - "npm test"

triggers:
  - when: "key_path_edits >= 1 and tool_count >= 5"
    reason: "修改了核心逻辑"
  - when: "test_runs >= 1 and write_count >= 3"
    reason: "跑了测试且改了多个文件"
```

| 字段 | 说明 |
|------|------|
| `project.name` | 项目名称 |
| `project.type` | 项目类型（CLI / Web API / Agent 框架 / SDK 库 / 移动端等） |
| `signals.key_paths` | 关键目录前缀列表，匹配的 Write/Edit 会计入 `key_path_edits` |
| `signals.test_patterns` | 测试命令子串列表，匹配的 Bash 命令会计入 `test_runs` |
| `triggers` | 触发规则列表，任一条件满足即建议沉淀 |

### 可用变量

| 变量 | 含义 |
|------|------|
| `tool_count` | 总工具调用数 |
| `write_count` | Write + Edit 次数 |
| `read_count` | Read 次数 |
| `bash_count` | Bash 次数 |
| `key_path_edits` | 命中 `key_paths` 的 Write/Edit 次数 |
| `test_runs` | Bash 命令匹配 `test_patterns` 的次数 |
| `debug_signals` | Bash 命令中含 error/traceback/debug/fix 等关键词的次数 |

### when 表达式语法

支持：`>=`、`<=`、`>`、`<`、`==`、`and`、`or`。示例：

- `key_path_edits >= 1 and tool_count >= 5`
- `test_runs >= 1 and write_count >= 3`
- `debug_signals >= 5`
- `tool_count >= 8 or key_path_edits >= 2`

## 步骤

严格按照以下步骤执行，不要跳步。

### 第一步：理解项目

阅读以下内容，建立对项目的基本认知：

1. `README.md`（或项目根目录的主要文档）
2. 项目根目录的文件/目录列表（`ls` 即可）
3. 源码入口目录的结构（如 `src/`、`lib/`、`app/` 等）
4. 已有的 `AGENTS.md`（如果存在）

从中识别：

- **项目类型**：CLI 工具 / Web 应用 / Agent 框架 / SDK 库 / 移动端 / 其他
- **关键目录**：放核心业务逻辑的目录路径（3-5 个）
- **开发模式**：这个项目上最常见的工作类型（新功能开发 / bug 修复 / 重构 / 集成调试 …）
- **测试方式**：项目用什么命令跑测试

### 第二步：设计 Profile

根据第一步的分析，向用户展示拟定的配置：

```
项目名: xxx
项目类型: xxx

关键路径 (key_paths):
  - path/to/core/    — 理由
  - path/to/api/     — 理由

测试模式 (test_patterns):
  - "pytest"         — 理由
  - "npm test"       — 理由

触发规则 (triggers):
  1. when: "..."  — 理由：什么场景会触发
  2. when: "..."  — 理由：什么场景会触发
  3. when: "..."  — 理由：什么场景会触发
```

确保向用户解释每个选择的理由，等用户确认后再进入下一步。

### 第三步：预览 Profile

基于确认的配置，生成完整的 `.ax/profile.yaml` 内容并展示预览。说明：

1. 完整的 YAML 内容
2. 预期效果：什么样的工作会触发沉淀建议，什么不会
3. 如何调整：直接编辑 YAML 或重新运行 `/ax:init`

明确说："确认后我将写入 `.ax/profile.yaml`。"

**等待用户明确确认后才能继续。**

### 第四步：写入与验证

1. 创建 `.ax/` 目录（如果不存在）
2. 将 profile 写入 `.ax/profile.yaml`
3. 运行验证：

```bash
python3 path/to/ax/scripts/eval_profile.py .ax/profile.yaml /dev/null /dev/null
```

应输出 `false`（没有信号时不应触发）。

4. 如果项目存在旧的 `.ax/eval-sedimentation` 脚本，提醒用户可以删除它（已被 profile.yaml 替代）。

5. 告知用户：
   - profile 已生成，可以提交到 git
   - 之后每轮对话结束时，AX 会自动根据此 profile 评估是否建议沉淀
   - 如果触发太频繁或太安静，可以直接编辑 YAML 调整，或重新运行 `/ax:init`

## 不同项目类型示例

### 示例 A：Python CLI 工具

```yaml
project:
  name: my-cli
  type: cli

signals:
  key_paths:
    - src/commands/
    - src/cli/
    - src/parsers/
  test_patterns:
    - pytest
    - "python -m pytest"

triggers:
  - when: "key_path_edits >= 1 and tool_count >= 5"
    reason: "改了命令处理器且工作量足够"
  - when: "test_runs >= 1 and write_count >= 3"
    reason: "跑了测试且改了多个文件"
```

### 示例 B：Agent 框架

```yaml
project:
  name: hermes-agent
  type: agent-framework

signals:
  key_paths:
    - src/agent/
    - src/tools/
    - prompts/
  test_patterns:
    - pytest
    - "go test"

triggers:
  - when: "key_path_edits >= 1 and write_count >= 2"
    reason: "修改了 agent 核心逻辑"
  - when: "debug_signals >= 5 and write_count >= 1"
    reason: "大量调试，可能有排障经验"
  - when: "test_runs >= 1 and tool_count >= 8"
    reason: "跑了测试且工作量大"
```

### 示例 C：Web API 应用

```yaml
project:
  name: my-api
  type: web-api

signals:
  key_paths:
    - src/api/
    - src/routes/
    - src/models/
    - src/middleware/
  test_patterns:
    - pytest
    - "npm test"
    - jest
    - vitest

triggers:
  - when: "key_path_edits >= 1 and test_runs >= 1"
    reason: "改了 API 层且有测试"
  - when: "bash_count >= 10 and key_path_edits >= 1"
    reason: "大量 Bash 操作（部署/迁移类工作）"
  - when: "debug_signals >= 5"
    reason: "大量调试，可能有排障经验"
```
