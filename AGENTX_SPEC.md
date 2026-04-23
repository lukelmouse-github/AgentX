# AgentX 自动知识沉淀插件完整设计说明

GitHub 仓库地址：<https://github.com/lukelmouse-github/AgentX>

## 一、定位

AgentX（简称 AX）是一个 Claude Code 插件。

它的目标不是做个人私有记忆，而是把 Claude Code 在编码、排障、设计、探索过程中产生的项目知识，自动沉淀为项目可复用的知识资产。

这些知识最终进入项目仓库中的通用路径，由项目本身长期承载，并通过 Git 自然演化。

AgentX 的核心定位是：

- 自动观察 Claude Code 的工作过程
- 自动判断哪些内容值得沉淀
- 自动把候选知识沉淀到插件私有候选池
- 自动把成熟候选知识晋升到项目正式知识层

AgentX 不依赖运行时人工确认。

## 二、与当前 AX 项目的融合原则

完整 Spec 不重新发明一套全新系统，而是以当前 AX 项目已经存在的稳定模式为骨架，逐步向目标架构演进。

融合原则如下：

- 如果 AX 当前已经存在稳定模式，完整 Spec 直接继承
- 如果 AX 当前还没有实现某个能力，则在 Spec 中作为目标架构保留
- 完整 Spec 是 AgentX 的目标形态，不要求当前仓库一次性全部实现

当前 AX 项目中已经相对稳定、应直接继承到完整 Spec 的模式包括：

- `Stop Hook` 作为自动沉淀主入口
- `Bash + LLM` 混合驱动
- 先硬指标快筛，再后台 LLM 审查
- 正式知识只写项目通用路径
- 插件不感知 Git / MR / 人工 review / commit

## 三、系统边界

AgentX 的边界定义如下：

- AgentX 只感知 Claude Code 插件生命周期
- AgentX 不感知 Git / MR / 人工 review
- AgentX 不负责 commit
- AgentX 不负责项目正式知识的人类治理
- AgentX 只负责从对话到知识的自动沉淀闭环

因此，Git 流程、MR 流程、团队协作流程都属于系统外部，不属于 AgentX 的内部架构。

## 四、核心设计原则

### 1. 自动优先

AgentX 是一套自动化沉淀系统。

它的主流程不依赖运行时人工确认。

人工可以：

- 修改配置
- 在项目仓库中直接修改正式文件
- 通过 Git 自己管理沉淀结果

但这些都不属于 AgentX 的流程节点。

### 2. 候选优先

新知识不应直接进入正式知识层。

完整 Spec 中，所有新沉淀内容应先进入 `.ax` 候选池，再由系统自动判断是否晋升到正式层。

### 3. Markdown 优先于 Skill

Markdown 是知识沉淀基础层，Skill 是更高阶的可复用能力抽象。

因此：

- 对话不能直接生成正式 Skill
- Skill 的生成必须建立在已有 Markdown 沉淀基础之上

这里需要特别区分：

- “Skill 必须建立在已有 Markdown 沉淀基础上”是 **Skill 生成规则**
- “候选 Skill 是否进入正式层”是 **自动晋升规则**

两者不是同一层概念。

### 4. Bash 优先做流程控制

为了提升稳定性，AgentX 的流程控制、状态推进、文件系统操作和确定性判断应尽可能由 Bash 驱动。

LLM 主要负责：

- 语义价值判断
- 候选内容生成
- 候选内容抽象
- 是否具备晋升语义条件的判断

一句话概括：

**AgentX 是一个 Bash 驱动、LLM 辅助的自动知识沉淀系统。**

## 五、完整 Spec 的主流程

完整 Spec 的目标主流程如下：

```text
Stop Hook
  -> Bash 硬指标快筛
  -> 后台 LLM 审查
  -> 生成候选 Markdown 到 .ax
  -> 自动晋升判断
  -> 写入项目正式知识目录
  -> 基于已有 Markdown 基础判断是否生成候选 Skill
  -> 生成候选 Skill 到 .ax
  -> 自动晋升判断
  -> 写入项目正式 Skill 目录
```

这条链路体现了两个阶段：

- 第一阶段：对话沉淀为 Markdown
- 第二阶段：Markdown 演化为 Skill

## 六、端到端状态机

为了让流程可串联、可持续推进，完整 Spec 将 AgentX 看作两条自动链路首尾相接的状态机。

### 1. 对话到 Markdown 的状态机

```text
turn_observed
  -> trigger_filtering
  -> ignored | selected
  -> candidate_md_generating
  -> candidate_md_ready
  -> md_promotion_judging
  -> formal_md_written | candidate_md_retained
```

这条链负责把每一轮对话沉淀为文档。

其中：

- `ignored` 表示本轮没有沉淀价值
- `candidate_md_ready` 表示候选 Markdown 已进入 `.ax`
- `formal_md_written` 表示已经写入项目正式知识层
- `candidate_md_retained` 表示暂时保留在候选池中，等待后续自动演化

### 2. Markdown 到 Skill 的状态机

```text
md_basis_scanning
  -> skill_not_ready | skill_ready
  -> candidate_skill_generating
  -> candidate_skill_ready
  -> skill_promotion_judging
  -> formal_skill_written | candidate_skill_retained
```

这条链不直接从对话开始，而是从“已有 Markdown 基础”开始。

它负责把已经足够稳定的文档知识进一步演化为 Skill。

## 七、`.ax` 私有候选池的角色

`.ax` 是 AgentX 的私有工作区，不属于项目正式知识层。

它的角色是：

- 候选知识缓冲区
- 自动流水线内部工作区
- 配置区
- 状态区
- 日志区

完整 Spec 中，`.ax` 下将逐步承担这些职责：

- 候选 Markdown
- 候选 Skill
- 状态记录
- 运行日志

`.ax` 的关键性质如下：

- `.ax` 是插件私有区
- `.ax` 不属于项目正式知识树
- `.ax` 默认不跟项目正式知识一起提交
- `.ax` 由每个使用者本地维护

## 八、正式知识层

正式知识层是项目长期知识资产所在的位置。

这一层沿用当前 AX 项目已经明确的 canonical 路径，不重新定义新路径。

正式知识层包括：

- 架构、约定、排障结论：`docs/ai-context/`
- 可复用项目技能：`.agents/skills/`
- 模块上下文：`{module}/AGENTS.md`

正式知识层的特点是：

- 属于项目本身
- 可以被 Git 管理
- 可以被项目团队长期维护
- 可以被不同 coding agent 消费

## 九、文档与 Skill 的演化关系

在完整 Spec 中，Markdown 和 Skill 不是平行关系，而是分层关系。

可以概括为：

- Markdown 是一阶沉淀
- Skill 是二阶抽象

因此：

- AgentX 先沉淀文档
- Skill 的生成必须建立在已有 Markdown 基础上
- bug 排查、日志查看、疑难定位、环境问题等内容，必须先形成对应 Markdown，再考虑是否演化为 Skill

这意味着：

- 文档沉淀链可以独立存在
- Skill 演化链依附于文档沉淀链

## 十、失败与恢复原则

完整 Spec 当前对失败恢复的高层原则很简单：

- 静默失败
- 记录日志
- 不打断用户主流程

也就是说，AgentX 的默认行为不是把异常抛给用户，而是：

- 尽量自动跳过
- 尽量记录现场
- 由后续迭代逐步增强恢复能力

## 十一、配置与可观测性

### 1. 配置

配置是 AgentX 的外部输入之一。

当前 AX 项目已经存在 `.ax/config` 作为私有配置入口，完整 Spec 直接继承这一点。

配置的高层职责包括：

- 控制触发敏感度
- 控制审查行为
- 控制项目特定的沉淀偏好

### 2. 可观测性

当前阶段，完整 Spec 只要求最基础的可观测能力：

- 日志

也就是说，AgentX 至少必须能回答：

- 有没有触发
- 有没有进入审查
- 有没有生成候选
- 有没有晋升成功
- 失败时发生了什么

当前 AX 项目已经具备基础日志能力，完整 Spec 延续这一点。

## 十二、渐进式演化策略

完整 Spec 是 AgentX 的目标架构，不代表当前 AX 仓库已经全部实现。

这份 Spec 的意义是：

- 作为目标方向
- 与现有 AX 项目保持连续性
- 让后续迭代逐步逼近

因此，AgentX 的演化策略是：

- 不要求一次性实现完整架构
- 优先继承现有稳定模式
- 逐步把“直接写正式层”演化为“候选优先 + 自动晋升”
- 逐步把“可复用经验写 Skill”演化为“基于文档基础自动生成 Skill”

## 十三、AgentX 架构演进 TODO

下面这份 TODO List 用来描述当前 AX 项目相对于完整 Spec 的位置。

状态说明：

- `[x]` 已完成
- `[-]` 部分完成 / 已有雏形
- `[ ]` 尚未完成

### 1. 系统边界

- `[x]` AX 只感知 Claude Code 插件生命周期
- `[x]` AX 不感知 Git / MR / 人工 review
- `[x]` AX 不负责 commit
- `[x]` AX 不负责项目正式知识的人类治理
- `[x]` AX 只负责从对话到知识的自动沉淀闭环

### 2. 自动触发主流程

- `[x]` 使用 Stop Hook 作为自动沉淀主入口
- `[x]` 使用 Bash 进行第一层硬指标快筛
- `[x]` 使用后台 LLM 进行第二层语义判断
- `[x]` 自动流程以异步方式运行，避免阻塞主对话
- `[-]` 当前已能直接写入项目正式知识目录
- `[ ]` 完整目标为先写入 `.ax` 候选池，再自动晋升到正式层

### 3. `.ax` 私有工作区

- `[x]` `.ax/config` 已存在，作为插件私有配置入口
- `[ ]` `.ax` 下建立候选 Markdown 池
- `[ ]` `.ax` 下建立候选 Skill 池
- `[ ]` `.ax` 下建立状态目录
- `[ ]` `.ax` 下建立日志目录
- `[ ]` `.ax` 成为完整自动流水线的正式候选池

### 4. 正式知识层

- `[x]` 正式知识路径限制为项目通用路径
- `[x]` 支持写入 `docs/ai-context/`
- `[x]` 支持写入 `.agents/skills/`
- `[x]` 支持写入 `{module}/AGENTS.md`
- `[x]` 正式知识层与项目一起被 Git 管理

### 5. Markdown 沉淀能力

- `[x]` 已具备自动识别“是否值得沉淀”的能力
- `[x]` 已具备自动生成项目知识文档的能力
- `[-]` 当前默认直接写正式层
- `[ ]` Markdown 候选与正式层分离
- `[ ]` Markdown 自动晋升链路形成闭环

### 6. Skill 演化能力

- `[x]` 当前已支持把可复用流程写成项目 Skill
- `[ ]` Skill 生成明确依赖已有 Markdown 沉淀基础
- `[ ]` Skill 不再允许从单轮对话直接跳过 Markdown 基础生成
- `[ ]` 候选 Skill 与正式 Skill 分离
- `[ ]` Skill 自动晋升链路形成闭环

### 7. 配置与日志

- `[x]` 已有 `.ax/config` 配置入口
- `[x]` 已支持项目级自定义 review 指令
- `[x]` 已有日志记录能力
- `[ ]` 配置统一覆盖候选生成与自动晋升阶段
- `[ ]` 日志与状态记录完全收敛到 `.ax` 私有工作区

### 8. 完整架构目标

- `[x]` AX 已形成自动沉淀的基本闭环
- `[-]` AX 正在从“直接写正式层”演化到“候选优先”
- `[ ]` 完整目标架构为：候选沉淀 -> 自动晋升 -> 正式知识
- `[ ]` 完整目标架构中，Markdown 是 Skill 的基础层
- `[ ]` AgentX 最终成为 Bash 驱动、LLM 辅助的自动知识沉淀系统
