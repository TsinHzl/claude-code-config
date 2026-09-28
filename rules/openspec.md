---
name: OpenSpec Workflow
description: Structured 5-phase change management; triggers on complexity (new feature, refactor, cross-subsystem), NOT on file count alone
inclusion: always
---

# OpenSpec 规范驱动开发（强制步进模式）

## 〇、触发评估前置门控（第零动作，先于一切 Skill / 流程）

**收到任何新需求的第一动作（在任何 Skill 调用、任何文件读取、任何提问之前）**：
逐项对照第一节「触发条件」与第二节「不触发」判定本需求落入哪个分支，并在对话中输出判定结论（示例格式：`[OpenSpec 触发评估] 新功能 + 步骤≥5 + 文件≥3 → 触发完整 OpenSpec`）。

**同回合连续执行约束：**
- 输出 `[OpenSpec 触发评估]` 后，必须在同一 assistant 回合内立即执行下一个可行步骤，不得仅输出评估文本后结束回合。
- 明确不触发时，继续执行直接任务所需的读取、分析或确认动作；触发时，继续执行 `project.md`、`config.yaml` 与未完成变更检查。
- 下一步需要用户决策时，必须在该回合调用 `AskUserQuestion`；仅在已实际发起 `AskUserQuestion` 后，才允许等待用户回复。

**输出豁免（防止对纯问答噪音化）：**
- 仅当需求属于**开发 / 变更类任务**（写代码、改文件、执行命令、架构设计等）时，才在对话中输出 `[OpenSpec 触发评估]` 判定文本。
- **纯知识问答、闲聊、翻译、总结、概念解释等非开发诉求**（如"介绍一下忒休斯"）：判定照常在内部完成，结论为「明确不触发」，**静默处理，禁止在对话中输出任何 `[OpenSpec 触发评估]` 判定文本**，直接回答用户问题。
- 若后续对话中该话题升级为开发任务，再补做并输出判定。

- **命中触发条件任意一项** → 直接走 OpenSpec 五阶段，**不得先进入 brainstorming / writing-plans 等其他 Skill 流程**（此时 OpenSpec 自身的阶段 0-4 已完整覆盖澄清、提案、实施、审查，无需求助外部技能链）。
- **明确不触发** → 直接执行，按 `00-change-gate.md` 走 CR。
- **落入灰色地带** → 按第一节·五用 AskUserQuestion 询问。
- **无法判定** → 默认触发，进入阶段 0（需求澄清）。

> **优先级声明**：本门控源自用户规则（CLAUDE.md/rules），优先级高于任何 Skill 的默认流程指令（superpowers 等技能链的「技能优先」约定不得越过本评估）。
> **禁止**：先进入其他 Skill 流程后"想起来"补做评估；判定必须在第一个动作前完成并留痕。
> **记忆纠偏**：历史会话曾出现"superpowers 技能链抢占、OpenSpec 全程未评估"的违规（2026-09-13，agy-cc-proxy API Keys 需求），本节为此类错误的永久性防线。

## 核心行为

遇到复杂需求时，Claude 自动创建并维护 `openspec/` 目录下的所有规范文件，
全程驱动五阶段工作流（阶段 0–4）。

**每个阶段都是独立的门控节点（Phase Gate）：**
- 前一阶段的退出条件未满足，绝对不进入下一阶段
- 每个阶段有明确的「进入声明 → 文件操作 → 对话输出 → 退出条件」四要素
- 用户未通过 AskUserQuestion 明确确认前，禁止推进到下一阶段

---

## 〇.A 本节变更记录

- 2026-09-13：新增第〇节「触发评估前置门控」。起因：历史会话（agy-cc-proxy API Keys 需求）中 superpowers 技能链先于 OpenSpec 启动，导致本应直接触发完整 OpenSpec 的需求（新功能 + 步骤≥5 + 文件≥3）全程未做触发评估。

---

## 一、触发条件（满足任意一项自动启用）

**触发**（满足任意一项）：

- **新功能或新模块** — 引入新的用户可见行为或新的公开 API
- **重构 / 架构调整** — 改变现有代码的组织方式、层次边界或依赖关系
- **接口 / 数据协议变更** — 修改公开 API 签名、数据模型字段或跨系统协议
- **跨子系统协同变更** — 多个相互独立的模块 / 层之间需要同步修改且存在耦合风险
- **大规模代码提取 / 裁剪 / 同步** — 从现有代码中剥离模块或子系统到另一仓库/分支，涉及多处适配（入口文件、构建脚本、模块声明、配置结构等）
- **用户需求包含多个独立子任务** — 明确列出 2 个以上不同功能点或交付物
- **复杂度较高的任意任务** — 预估实施步骤 ≥ 5，或涉及 ≥ 3 个文件的协同适配（非纯复制），或存在容易遗漏的依赖关系 / 顺序约束

**不触发**（直接执行，不走本流程）：

- Bug fix — 即使涉及多个文件，只要改动局限于修复同一问题
- typo / 格式 / 注释修正
- 配置微调（版本号、构建设置、lint 规则等）
- 为现有功能补充测试
- 文档更新
- 单纯命名重构（rename without behavior change）
- 纯文件复制（无需适配集成点的 1:1 镜像同步）

> **判断原则：** 以变更的**复杂度和影响范围**为准，而非文件数量。
> 即使操作目标是「另一个仓库」，只要涉及裁剪适配（删模块、改入口、调构建），复杂度等同于本仓库重构，必须走 OpenSpec。
> 不确定是否触发时，**默认触发**并进入阶段 0（需求澄清）。在阶段 0 经评估确认复杂度不足时，可声明退出 OpenSpec 流程并直接执行。

---

## 一.5、灰色地带主动询问（强制门控）

介于「明确触发」与「明确不触发」之间，存在大量无法直接套用第一节二元判断的改动（典型的「不远不近」场景）。此类改动**既不该默认走完整 OpenSpec**，也不该静默跳过——必须由用户显式决策。

### 触发条件（满足任意一项即进入灰色地带）

- 改动涉及 **2-4 个文件**
- 净改动行数 **50-300 行**（非纯文档/测试）
- 实施步骤 **3-5 步**
- 需求包含 **2 个独立子任务**，但未明确列出 ≥ 3 个

### 不属于灰色地带（直接走既定分支）

- 命中第一节「触发条件」任意一项 → 直接走 OpenSpec，**不询问**
- 命中第二节「不触发」任意一项 → 直接执行并按 `00-change-gate.md` 走 CR，**不询问**

### 执行动作（强制）

在开始任何实现前，使用 `AskUserQuestion` 主动询问（至少四选项，顺序固定）：

- **问题头部**：`OpenSpec 决策`
- **问题正文**：`当前改动评估为【灰色地带】（涉及 X 个文件 / Y 行 / Z 步），是否启用 OpenSpec？`
- **选项**：
  1. **启用完整 OpenSpec**（推荐）— 完整走五阶段（阶段 0-4）
  2. **启用轻量 OpenSpec** — 仅产出 `proposal.md` + `tasks.md`，跳过 `spec.md` / `design.md` / 步骤 4.5 自动审查
  3. **跳过 OpenSpec** — 直接执行，按 `00-change-gate.md` 强制 CR 兜底
  4. **重新评估** — 用户补充上下文后回到阶段 0

### 轻量模式约束

- `tasks.md` 不写 `spec.md 引用` 字段
- 阶段 4 归档时直接将 `proposal.md` + `tasks.md` 移入 `archive/`，跳过 `specs/` 合并步骤
- 阶段 3 末尾仍需触发 sub-agent 独立 Code Review（继承完整 OpenSpec 第十一节），**但 CR Prompt 模板移除「Coherence - design.md 架构决策一致性」维度**（因为 design.md 不存在），仅做 Completeness + Correctness 二维验证
- 阶段 0 需求澄清可由用户在同一 AskUserQuestion 中口头补充，**计入阶段 0 但不超过 3 问题上限制**

### 数量化阈值（不可任意放宽）

判定逻辑（伪代码）：

```
grey_zone = (files in 2..4) AND (lines in 50..300) AND (steps in 3..5)
medium     = (files > 4) OR (lines > 300) OR (steps > 5)
large      = (files > 5) OR (lines > 500) OR (steps > 8)
tiny       = (files == 1) AND (lines < 50) AND (steps in 1..2)

if large or medium: trigger_full_openspec()
elif grey_zone:     ask_user()
elif tiny:          skip_openspec()
```

| 区间 | 文件数 | 净改动行 | 步骤数 | 决策分支 |
|------|--------|----------|--------|----------|
| 极小 | 1 | < 50 | 1-2 | 不触发 → 走 00-change-gate |
| **灰色** | **2-4** | **50-300** | **3-5** | **本节主动询问**（全 AND 命中） |
| 中 | > 4 | > 300 | > 5 | 触发 → 完整 OpenSpec（任一 OR 命中） |
| 大 | > 5 | > 500 | > 8 | 触发 → 完整 OpenSpec（任一 OR 命中） |

> 多个区间判定冲突时按**最高级别**分支处理（保守兜底）。
> "灰色"要求三轴**同时**落入区间；只要任一维度越级即直接触发，跳过询问。

### 违规处理

- 命中灰色地带但未询问 → 流程违规，**必须回退到本节执行询问后才可继续**
- 灰色地带已在进行中才发现 → 立即停止当前动作，先询问后继续
- `no-openspec:` commit 前缀详细定义见第十二节 Commit 格式

---

## 二、目录结构（由 Claude 自动创建维护）

```
openspec/
├── project.md              # 项目上下文（优先级最高，所有阶段依赖此文件）
├── config.yaml             # 项目级 schema/context/rules 约束（见三点五节）
├── AGENTS.md                # AI 助手指令说明（由 openspec init/update 生成，人类可读，供工具识别 OpenSpec 已启用）
├── specs/                  # 已归档的最终规范（source of truth）
│   └── <capability-path>/  # 一个或多个目录对应一个聚焦的 capability（可分层，如 identity/user-auth）
│       ├── spec.md         # WHAT + WHY（含 Purpose / Requirement / Scenario）
│       └── design.md       # HOW（可选，仅在该 capability 存在需长期沉淀的固定模式时创建）
├── changes/                # 进行中的变更
│   └── <change-name>/
│       ├── proposal.md     # 变更提案（Why / What Changes / Capabilities / Impact）
│       ├── tasks.md        # 任务清单（含实时状态）
│       ├── design.md       # 技术方案（可选，命中设计触发条件时创建）
│       ├── .openspec.yaml  # 变更级元数据（可选）：schema / created / skip_specs / retire_capabilities
│       └── specs/          # 本次变更的规范增量（delta specs，非完整未来态）
│           └── <capability-path>/
│               └── spec.md # 仅含 ADDED/MODIFIED/REMOVED/RENAMED Requirements（+ 可选 Purpose）
└── changes/archive/         # 已完成归档的变更
    └── YYYY-MM-DD-<change-name>/
```

**`.openspec.yaml`（变更级元数据，可选）关键字段：**

| 字段 | 用途 |
|------|------|
| `schema` | 该变更使用的 artifact 依赖 schema（默认 `spec-driven`） |
| `created` | 变更创建日期 |
| `skip_specs` | 设为 `true` 时允许零 delta 变更通过校验（仅当变更不涉及任何 spec 级行为变化，如纯重构/工具/文档时使用，不得为了通过校验而捏造需求） |
| `retire_capabilities` | 设为 `true` 时，当某 capability 的最后一条 Requirement 被 REMOVED，归档会删除该 capability 整个 spec 文件（退役），而非留空文件 |

> **`AGENTS.md`：** 由 `openspec init` / `openspec update` 生成于 `openspec/` 目录下，向 AI 工具说明 OpenSpec 已在本项目启用及基本使用方式。本规则文件（`~/.claude/rules/openspec.md`）与其功能互补：`AGENTS.md` 是项目级、由 CLI 生成的通用说明；本文件是 Claude Code 的用户级强制门控规则，优先级更高，两者不冲突。

---

## 三、project.md 初始化（所有阶段前置检查）

**在进入任何阶段之前**，检查 `openspec/project.md` 是否存在：
- 不存在 → 使用 AskUserQuestion 提示用户选择：**[运行 /opsx:init]** 或 **[跳过使用空模板]**。等待用户选择后再继续；若用户选择跳过，则按模板手动创建。
- 已存在 → 直接参考其内容，跳过创建

```markdown
# 项目上下文

## 技术栈
<语言、框架、主要依赖>

## 架构约定
<分层结构、命名规范、关键设计决策>

## 目录结构
<项目关键目录说明>

## 开发约定
<代码风格、测试要求、分支策略>
```

---

## 三点五、config.yaml 集成（任何阶段前强制读取）

在触发 OpenSpec 工作流后，**进入任何阶段之前**，检查并读取 `openspec/config.yaml`：

**不存在时：** 使用 AskUserQuestion 提示用户选择：**[继续]** 或 **[先运行 `openspec init`]**（`openspec init` 是官方 CLI 命令，非 slash 命令，需在终端执行）。等待用户选择后再继续。

**已存在时：** 读取并解析以下字段，在后续所有 artifact 生成步骤中作为**约束条件**应用：
- `schema`：本项目使用的 artifact 依赖 schema（默认 `spec-driven`：proposal → {specs, design} → tasks，见第一节·五后的官方 schema 依赖图）
- `context`：项目技术栈、架构、平台信息
- `rules.specs`：spec artifact 生成约束
- `rules.tasks`：tasks artifact 生成约束
- `rules.design`：design artifact 生成约束

> **注意：** `context` 和 `rules` 是约束注入，不得将其内容原文复制到任何 artifact 文件中。
> **字段对照：** 上述四个字段名与官方 OpenSpec 仓库 `openspec/config.yaml` 的真实 schema 完全一致（`schema` / `context` / `rules.specs` / `rules.tasks` / `rules.design`），无需转换映射，可直接按官方文档语义理解。变更级还可能存在 `.openspec.yaml`（见第二节），与本节的项目级 `config.yaml`是两个不同文件，作用范围不同（项目级 vs 单个变更级）。

---

## 四、会话恢复检查（OpenSpec 工作流触发时）

**触发 OpenSpec 工作流后，进入阶段 0 之前**，检查是否存在未完成的变更：

```bash
[ -d "openspec/changes" ] && grep -rl "状态：IN_PROGRESS" openspec/changes/ 2>/dev/null
```

若存在，使用 AskUserQuestion 提示用户选择：**[继续此变更]** 或 **[开始新任务]**。等待用户选择后再继续。

---

## 五、阶段 0 — 需求澄清（按需触发）

收到需求后，**起草提案之前**，优先参考 `openspec/project.md` 中已有的上下文。
若仍存在以下任意情况，先向用户提问：

- 目标用户 / 使用场景不明确
- 存在多个技术方案且各有取舍，无法独立决策
- 验收标准缺失或模糊
- 影响范围不清晰（不知道该排除什么）
- 关键业务规则依赖外部上下文

**规则：**
1. 每次最多提 **3 个关键问题**，优先级排序后只问最重要的
2. 等待用户全部回复后，再进入阶段 1
3. 若需求已足够清晰，跳过本阶段直接进入阶段 1

---

## 六、阶段 1 — 起草提案

> **进入声明：** 在对话中输出 `> 🔵 [阶段 1] 正在起草变更提案：<change-name>`

需求澄清完成后，**严格按以下顺序**执行每一步：

### 步骤 1：确定 change-name
用 kebab-case 命名，例如：`add-ride-filter`、`refactor-payment-flow`

### 步骤 2：创建 proposal.md

创建文件后，**立即在对话中完整展示文件原文**（代码块，不得用摘要替代）：

````
📄 **openspec/changes/<change-name>/proposal.md**

```markdown
[proposal.md 完整内容原文]
```
````

proposal.md 结构：

```markdown
# 变更提案：<change-name>

## 背景
<为什么需要这个变更，解决什么问题>

## 目标范围
**在范围内：**
- <具体包含的内容>

**不在范围内：**
- <明确排除的内容>

## 技术方案
<关键技术决策、依赖、约束>

## 预期影响
<对现有功能的影响、性能、兼容性>

## 风险
<识别的风险及应对策略>
```

### 步骤 3：创建 tasks.md

创建文件后，**立即在对话中完整展示文件原文**（代码块，不得用摘要替代）：

````
📄 **openspec/changes/<change-name>/tasks.md**

```markdown
[tasks.md 完整内容原文]
```
````

tasks.md 结构：

```markdown
# 任务清单：<change-name>

## 状态：DRAFT

## 任务
- [ ] <任务 1 描述>
- [ ] <任务 2 描述>
- [ ] <任务 3 描述>

## 验收标准
- [ ] <验收条件 1>
- [ ] <验收条件 2>
```

> **任务粒度原则：** 每个任务应独立可验证，预计工时不超过 2 小时；过大则拆分，过细则合并。

### 步骤 4：创建 spec.md 和 design.md

**spec.md — 满足以下任意一项则必须创建，否则可跳过：**
- 涉及公开 API 或接口签名变更
- 涉及状态机或业务流程
- 涉及跨系统数据协议
- 行为有明确的"当 X 发生时应产生 Y 结果"的可验证场景

> **等价对照：** 官方 OpenSpec 通过 `proposal.md` 的 **Capabilities** 段落（New Capabilities / Modified Capabilities）判定是否需要 spec；本节判定条件与其行为等价，只是用中文描述触发场景。若变更不涉及任何 spec 级行为变化（纯重构、工具链、文档），等价于官方的 `skip_specs: true`，可在 `tasks.md` 或对话中注明「无 spec 级行为变化」并跳过 spec.md。

**spec.md 是行为契约（behavior contract），不是实施计划：**

| 应写入 spec.md | 不应写入 spec.md（应写入 design.md / tasks.md） |
|---|---|
| 用户或下游系统可观察到的行为 | 内部类 / 函数名 |
| 输入、输出、错误条件 | 具体库或框架选择 |
| 外部约束（安全、隐私、可靠性、兼容性） | 分步实施细节 |
| 可测试或可显式验证的场景 | 详细执行计划 |

> **快速判定法：** 若实现方式可以改变而不影响外部可观察行为，该内容大概率不属于 spec，应移入 design.md 或 tasks.md。

**结构化格式（与官方 OpenSpec 约定一致）：**

```markdown
## Purpose
<一两句话，描述该 capability 是做什么的（新建 capability 时必填，≥ 50 字符）>

## ADDED Requirements

### Requirement: <需求名称，建议 < 50 字符，描述性>
The system SHALL <核心行为，使用 SHALL/MUST 表达强制要求，SHOULD 表达推荐但有例外，避免仅用 should/may 描述规范性要求>。

#### Scenario: <场景名称>
- **GIVEN** <初始状态（可选）>
- **WHEN** <触发条件>
- **THEN** <期望结果>
- **AND** <附加结果或条件（可选）>

## MODIFIED Requirements

### Requirement: <与现有 spec.md 中完全一致的标题（normalize 后大小写/空格敏感匹配）>
<完整的修改后需求内容 —— 必须是完整需求，不是 diff；可用行内注释标注 `← (was X)` 说明变化点>

#### Scenario: <场景名称>
...

## REMOVED Requirements

### Requirement: <标题>
**Reason**: <废弃原因>
**Migration**: <迁移路径，如适用>

## RENAMED Requirements
- FROM: `### Requirement: <旧名称>`
- TO: `### Requirement: <新名称>`
```

**格式硬性规则（关键，容易踩坑）：**
- Requirement 标题：`### Requirement: <名称>`（三级标题），紧跟一句 SHALL/MUST 陈述核心行为，名称建议 < 50 字符
- Scenario 标题：`#### Scenario: <名称>`（**必须是四个 `#`**，用三个 `#` 或改成项目符号会静默失败，不会报错但不会被解析）
- 每条 Requirement 必须至少有一个 Scenario
- Requirement 标题是**跨 spec.md / delta spec 匹配的唯一标识**：归档时按 `normalize(header) = trim(header)` 做大小写敏感比较，标题必须逐字一致（含冒号后的空格）
- 新建 capability（该 capability 尚无主 spec.md）时，delta 才允许以 `## Purpose` 开头；若该 capability 已有主 spec.md，delta **不应**再写 `## Purpose`（会被归档流程忽略，主 spec 的 Purpose 才是权威版本）
- `changes/<change-name>/specs/` 下**只写变更量**（ADDED/MODIFIED/REMOVED/RENAMED），不写完整未来态；MODIFIED 必须粘贴完整需求块再修改，不能只写差异部分，否则归档时会丢细节
- 若只是新增关注点、不改变现有行为，用 ADDED 而不是 MODIFIED

**Progressive Rigor（渐进严谨度，避免过度官僚化）：**

| 级别 | 适用场景 | 要求 |
|------|---------|------|
| **Lite（默认）** | 局部、低风险变更 | 简短的 behavior-first 需求；清晰的范围与非目标；少量具体验收点 |
| **Full（提高严谨度）** | 跨团队/跨仓库、API/协议破坏性变更、迁移类、安全/隐私敏感、歧义可能导致高昂返工的场景 | 增加细节密度与显式验证要求，按比例提高严谨度 |

> 绝大多数变更应保持 Lite 级别；本地强制门控（第一节触发条件、第一节·五灰色地带）已经承担了"要不要走完整流程"的判断，Progressive Rigor 是在**已经决定要写 spec.md 时**，进一步判断该写多详细。

使用 WHEN/THEN 场景格式（简化版，非 delta 场景下的最小可用格式）：

```markdown
## 新增需求
### 需求：<名称>
#### 场景：<名称>
- **WHEN** <条件>
- **THEN** <期望结果>
```

**design.md — 满足以下任意一项则必须创建，否则可跳过：**
- 存在多个可行技术方案需要显式决策
- 涉及架构模式选型（分层、通信机制、数据流向）
- 有需要记录的技术权衡或约束理由
- 跨模块 / 跨服务的变更，或引入新的架构模式
- 引入新的外部依赖，或涉及重大数据模型变更
- 涉及安全、性能或迁移复杂度
- 存在应在编码前解决的技术歧义

使用以下结构：

```markdown
## 上下文
## 目标 / 非目标
## 决策
## 风险 / 权衡
## 迁移方案（如适用）
## 待决问题（Open Questions，如适用）
```

> **待决问题（Open Questions）的边界：** 仅用于记录"可以安全推迟到之后再回答，且不影响 spec / 方案 / 任务拆分"的真正未知项。若某个问题的答案会改变 spec、选定方案或任务拆分，必须现在向用户询问澄清，不得先搭建实现再补答案。

创建的文件均须在对话中展示完整内容（代码块，不得用摘要替代）。

> **Artifact 依赖约束：** tasks.md 必须在 spec.md 和 design.md 内容确定后才起草，以确保任务与规范完全对齐。起草 tasks.md 前，若 design.md 中存在待决问题（Open Questions）且其答案会影响任务拆分，须先与用户澄清，不得将未声明的假设直接写入任务。

> **任务验证要求：** 每个任务应在其复选框描述中说明如何验证完成（测试、命令、可观察行为或交付物），仅在校验跨越多个实现任务的整体集成行为时才拆出单独的验证任务。

### 步骤 4.5：Sub-agent Proposal 质量审查

在向用户展示提案前，使用 `Agent` tool 启动独立审查 sub-agent（**必须设置 `run_in_background: false`**，前台阻塞运行，防止主 session 提前结束）。

**Prompt 模板（不得包含任何正面定性语句）：**

```
请独立审查以下变更提案的质量：

[proposal.md 完整内容]
[tasks.md 完整内容]

评估维度：
1. 背景与目标是否清晰、无歧义？
2. 每个任务是否原子化、可独立验证？
3. 验收标准是否可量化？
4. 风险识别是否有明显遗漏？
5. 范围边界（In / Out of Scope）是否清晰？

输出格式：
- Issues: [需要补充或修正的具体条目，无则填 none]
- Verdict: READY / NEEDS_REVISION

**语言要求：你的所有输出必须使用简体中文。**
```

**收到结果后：**
- `READY` → 直接进入步骤 5
- `NEEDS_REVISION` → 按 Issues 修正 proposal.md / tasks.md，重新运行；**最多重跑 1 次**（即总计最多 2 轮）。第 2 轮仍为 `NEEDS_REVISION` 时，在对话中列出残留问题，进入步骤 5 由用户决定是否继续

### 步骤 4.6：需求回溯核验（阶段 1 产物定稿前）

> **目的：** 在进入实施阶段（阶段 2/3）前，将本次 OpenSpec 产物（proposal.md / spec.md / design.md / tasks.md）与**原始需求**逐点比对，确保没有任何需求点被遗漏、偏离或曲解。这是写代码前的最后一道需求保真门控。

**触发：** 步骤 4.5 通过后、步骤 5 用户确认前执行。本步骤是阶段 1 产物进入实施（阶段 2/3）前的最后一道需求保真门控。**进入阶段 3 写第一句业务代码之前必须完成本步骤，无例外。**

**核验依据（原始需求的来源）：**
- 若用户在阶段 0 提供 / 引用了 **PRD 或外部需求文档**（任意文件路径、URL 或对话中粘贴的文本），必须以该文档为权威依据，逐条需求点核验。
- 若无独立 PRD，则以**阶段 0 澄清时用户给出的原始诉求 + 本次对话中明确陈述的需求点**为依据。
- 主 agent 在本步骤开始时，在对话中声明所采用的核验依据来源（PRD 路径 / 对话原始需求摘要），供用户可核对。
- 若依据为「对话原始需求摘要」（非外部 PRD），主 agent 声明后必须使用 AskUserQuestion 让用户显式确认该摘要是否完整、准确反映其原始诉求，选项为：**确认依据完整准确** / **补充需求点** / **修正摘要**；确认通过后才启动核验 sub-agent。外部 PRD 路径无需此确认（以文档为权威锚点）。

**核验执行方式：**

使用 `Agent` tool 启动独立核验 sub-agent（**必须设置 `run_in_background: false`**，前台阻塞运行），传入：
- 原始需求 / PRD 完整内容（或可访问路径说明）
- proposal.md / tasks.md / spec.md / design.md（如有）完整内容

**Prompt 模板（不得包含任何正面定性语句）：**

```
请对以下 OpenSpec 变更产物与原始需求进行逐点回溯核验。

## 原始需求（权威依据）
[PRD 完整内容 / 阶段 0 对话原始需求摘要]

## OpenSpec 产物
[proposal.md 完整内容]
[spec.md 完整内容，如有]
[design.md 完整内容，如有]
[tasks.md 完整内容]

## 核验要求
1. 从原始需求中**逐条提取**每一个独立需求点（功能点、约束、边界、验收点、非功能要求等），不得合并、不得跳过。
   - 提取粒度以「可独立验收的最小行为单元」为准；若原始需求点超过 30 条，先按主题分组归并同类的细粒度点（如同一功能的多个 UI 细节归为一组），再逐组判定，矩阵行数控制在 40 行以内；归并必须在汇总段标注归并规则供用户复核。
2. 对每一条需求点，在产物中定位其落点：
   - proposal.md 的「目标范围 / 技术方案」
   - spec.md 的 Requirement / Scenario
   - tasks.md 的任务条目 / 验收标准
3. 逐条判定覆盖状态：
   - ✅ 一致 — 需求点在产物中有准确、无歧义的对应
   - ⚠️ 偏离 — 产物有对应但语义与原始需求不符（范围收窄、条件改变、约束弱化等）
   - ❌ 缺失 — 产物中找不到对应落点
   - ➕ 超出 — 产物引入了原始需求未提及的内容（需标注，供用户判断是否合理）

## 输出格式

### 逐点对比矩阵
| # | 原始需求点 | 产物落点位置 | 状态 | 说明 |
|---|-----------|-------------|------|------|
| 1 | <需求点原文摘录> | proposal L? / spec §? / task ? | ✅/⚠️/❌/➕ | <偏离或缺失的具体差异> |
| ... | ... | ... | ... | ... |

### 汇总
- 一致: N 条
- 偏离: N 条（列出 #）
- 缺失: N 条（列出 #）
- 超出: N 条（列出 #）

### Verdict
- CONFORMS（零偏离 + 零缺失）→ 可进入步骤 5
- NON_CONFORMS（存在任意偏离或缺失）→ 必须修正后重跑

**语言要求：你的所有输出必须使用简体中文。**
```

**收到结果后：**
- `CONFORMS`（零偏离 + 零缺失）→ 在对话中完整展示对比矩阵，进入步骤 5
- `NON_CONFORMS` → 按「偏离 / 缺失」条目修正 proposal.md / spec.md / tasks.md，重新运行本步骤
  - 轮次硬上限：最多 2 轮（即最多重跑 1 次）
  - 第 2 轮仍为 `NON_CONFORMS` 时，在对话中列出残留的偏离/缺失项，**阻塞进入步骤 5**，使用 AskUserQuestion 向用户展示残留项，选项为：
    - **继续修正**（推荐）— 用户补充说明后再次修正并重跑
    - **接受残留并继续** — 用户显式接受偏离/缺失（会被记录为 known gap，后续在 commit message / spec 中标注）
    - **回退阶段 0** — 需求本身需重新澄清
  - 未经用户显式选择「接受残留并继续」前，**禁止进入步骤 5**

> **「超出」项处理：** 产物引入原始需求未提及的内容不属于阻塞项，但在步骤 5 用户确认时必须单独列出供其判断是否保留；sub-agent 仅负责标注，不自行裁决。
> 若步骤 4.6 产出「超出」项，步骤 5 在展示确认选项前，必须先用一个独立 AskUserQuestion（multiSelect: true）列出所有超出项让用户勾选「保留」或「剔除」；剔除的项需修改产物并**重跑步骤 4.6**，保留的项在 commit message / spec 中标注为「主动超出，经用户确认」。

> **与第十一节 CR 的区别：** 本步骤核验的是「产物 vs 原始需求」的需求保真度，发生在写代码之前；第十一节 CR 核验的是「代码 diff vs 产物」的实现一致性，发生在写代码之后。两者不可互相替代。
> **与步骤 4.5 的区别：** 步骤 4.5 第 2 轮残留采用软阻塞（进入步骤 5 由用户一并裁决），本步骤第 2 轮残留采用硬阻塞 + 独立 AskUserQuestion，原因是需求保真度偏离的成本（整个实现方向错误）远高于产物质量瑕疵，不允许在步骤 5 一并软裁决。

### 步骤 5：硬性门控 — 等待用户确认

使用 AskUserQuestion 向用户展示确认选项：

- **确认实施**（推荐）— 进入阶段 2
- **需要修改** — 用户说明修改内容后重新起草

**在用户通过 AskUserQuestion 选择确认之前，禁止调用任何 Edit / Write / Bash 工具（proposal/tasks 文件创建除外）。**

---

## 七、阶段 2 — 审查确认

> **进入条件：** 用户通过 AskUserQuestion 选择了确认实施

**必须按顺序执行，不得跳步：**

1. 在对话中声明：`> 🟢 [阶段 2] 提案已确认 — 状态更新为 IN_PROGRESS`
2. Edit tasks.md 将状态改为 `IN_PROGRESS`
3. 创建 Git 分支：`feature/<change-name>`（或 `refactor/`、`hotfix/` 视性质而定）

**用户确认后必须立即更新状态，不得延迟到阶段 3 再写入。**

若用户提出修改意见：
1. 更新 `proposal.md` 和 `tasks.md`
2. 在对话中展示修改后的完整内容
3. **重跑步骤 4.6 需求回溯核验**（修改后的产物不得仅凭历史 CONFORMS 结论放行），通过后再次使用 AskUserQuestion 等待用户确认

若用户明确拒绝提案：
1. 将状态改为 `REJECTED`
2. 等待用户给出新方向，修改后重新从阶段 1 起草

---

## 八、阶段 3 — 逐任务实施

**开始实施前，读取 `openspec/config.yaml` 并将 `context` 和对应 `rules` 作为约束应用：**
- 创建 / 修改 spec.md 或 proposal.md 时：应用 `rules.specs` + `context`
- 创建 / 修改 design.md 时：应用 `rules.design` + `context`
- 创建 / 修改 tasks.md 时：应用 `rules.tasks` + `context`

约束体现在 artifact 内容质量上，不得将 config.yaml 原文复制到任何 artifact 文件。

**每个任务必须独立完成，严格按以下四步循环，禁止批量推进：**

```
① 在对话中声明：> ⏳ [任务 N/M] 开始：<任务描述>
② 执行该任务的代码修改
③ Edit tasks.md，将该任务 `- [ ]` 改为 `- [x]`（单独执行，不与其他任务合并）
④ 在对话中声明：> ✅ [任务 N/M] 完成：<一句话说明做了什么>
```

**禁止一次性将多个任务标记为 `[x]`。**

发现超出提案范围的需求 → **立即停止**，先补充提案或创建新变更，不合并进当前范围。

全部任务完成后：
1. Edit tasks.md 将状态改为 `DONE`
2. 启动 Sub-agent 独立 Code Review（见第十一节），**禁止由主 agent 自行自检**

**变更被中断时：** 若用户切换到新需求，当前变更保持 `IN_PROGRESS` 状态暂停；新需求走独立的 change-name 流程；回到此变更时从断点继续。

---

## 九、阶段 4 — 归档

> **进入条件：** 所有任务为 `[x]` 且用户确认验收标准

**禁止在用户确认前自动归档。** 必须使用 AskUserQuestion 向用户展示验收标准清单（含所有验收条件），选项为：**[确认归档]** 或 **[暂不归档]**。

用户选择确认归档后，按顺序执行：

1. 在对话中声明：`> 🔵 [阶段 4] 开始归档`
2. Edit tasks.md 将状态改为 `ARCHIVED`
3. 将 `openspec/changes/<change-name>/specs/` 内容按**标准 delta 合并算法**合并写入 `openspec/specs/`（严格按以下四步顺序执行，不得打乱顺序）：

   **合并顺序（固定，不可调换）：**
   1. **RENAMED** — 先处理重命名：在目标 `openspec/specs/<capability-path>/spec.md` 中，将 `FROM:` 标题对应的 Requirement 标题改为 `TO:` 标题（内容暂不变，内容变化由后续 MODIFIED 用新标题接管）
   2. **REMOVED** — 按 normalized header（`trim(header)`，大小写敏感）匹配并删除对应 Requirement；若该 capability 的**最后一条** Requirement 被移除且变更的 `.openspec.yaml` 声明 `retire_capabilities: true`，则整个 capability 退役，删除其 `spec.md` 文件
   3. **MODIFIED** — 按 normalized header 匹配（若该 Requirement 在本次变更中已被 RENAMED，则用**新标题**匹配），用 delta 中的完整内容替换目标 spec.md 中的对应 Requirement 块
   4. **ADDED** — 将新 Requirement 追加到目标 spec.md；若目标 capability 尚不存在 spec.md（全新 capability），用 delta 的 `## Purpose` 段落作为新 spec.md 的 Purpose 种子；若 delta 未提供 Purpose，则新 spec.md 的 Purpose 写入占位符 `TBD ... 归档后请补充 Purpose`

   **冲突检测规则（合并前逐一核查，发现任一冲突则停止合并，展示冲突详情由用户决定覆盖/追加/跳过）：**
   - `MODIFIED` 标题在目标 spec.md 中不存在 → 冲突（无法定位要修改的需求）
   - `REMOVED` 标题在目标 spec.md 中已不存在 → **视为已移除，仅警告并继续**，不算冲突；但若该标题恰好是同一 delta 中某个 `RENAMED` 的 `FROM` 一侧（大小写/空格不敏感比较），或与已存在的某 Requirement 标题仅大小写/空格不同 → 判定为冲突
   - `ADDED` 标题在目标 spec.md 中已存在：内容完全一致 → **视为已同步，跳过**，不算冲突；内容不一致 → 冲突
   - `RENAMED` 的 `FROM` 已不存在但 `TO` 已存在 → **视为已同步（此前已完成过重命名）**，跳过，不算冲突
   - 目标路径完全无同名文件（全新 capability）→ 直接写入，无冲突可言

4. 将整个 `openspec/changes/<change-name>/` 目录移至 `openspec/changes/archive/YYYY-MM-DD-<change-name>/`（日期取当日，如 `2026-06-05-add-ride-filter`）
5. 在对话中声明：`> ✅ 归档完成：openspec/changes/archive/YYYY-MM-DD-<change-name>/`

> **等价对照：** 本节步骤 3 的四步合并算法与官方 `/opsx:archive`（或 `/opsx:sync`）内部执行的 delta 合并逻辑一致；官方允许在归档前单独运行 `/opsx:sync` 预览合并结果而不归档，本地流程未提供等价的"仅合并不归档"分支 —— 如需预览，可在步骤 3 执行前先展示合并后的 diff 供用户确认，再继续步骤 4。

---

## 十、变更状态流转

```
DRAFT → IN_PROGRESS → DONE → ARCHIVED
    ↘ REJECTED（用户拒绝提案，需修改后重新确认）
```

| 状态 | 触发时机 |
|------|---------|
| DRAFT | 阶段 1 创建 tasks.md 时 |
| IN_PROGRESS | 阶段 2 用户通过 AskUserQuestion 确认后立即更新 |
| DONE | 阶段 3 全部任务完成时 |
| ARCHIVED | 阶段 4 归档完成时 |
| REJECTED | 阶段 2 用户明确拒绝时 |

---

## 十一、Sub-agent 独立 Code Review（强制）

实施完成后，**禁止主 agent 自行自检**，必须按以下步骤执行：

### 步骤

1. 运行 `git diff <base-branch>...HEAD` 获取完整变更 diff
2. 读取 `proposal.md`、`tasks.md`、相关 `spec.md` 内容
3. 使用 `Agent` tool 启动 sub-agent（**必须设置 `run_in_background: false`**，前台阻塞运行，防止主 session 提前结束），传入以下 Prompt（**不得包含任何正面定性语句**，不得提及"已经实施者检查"）：

**Prompt 模板：**

```
请对以下代码变更进行独立审查。

## 变更规范
[proposal.md 内容]
[tasks.md 内容]
[spec.md 内容，如有]

## 实际代码变更（git diff）
[git diff 输出]

审查维度（三维验证）：

**1. Completeness（完整性）**
- tasks.md 中所有任务是否均为 `- [x]`？
- spec.md 中每条需求是否在代码变更中有对应实现？
- proposal.md In Scope 内的内容是否全部落地？

**2. Correctness（正确性）**
- 实现是否与 spec.md 每个 Scenario 的 WHEN/THEN 完全一致？
- 是否存在逻辑错误、安全漏洞、性能问题？
- 变更是否超出 proposal.md 定义的 In Scope 范围？

**3. Coherence（一致性）**
- 实现是否遵循 design.md 中的架构决策？
- 是否与 openspec/config.yaml `context` 所描述的项目模式一致？
- 是否有意外副作用或未预期的依赖变更？

输出格式：
- Findings: [每条含：文件位置、维度(completeness/correctness/coherence)、严重程度(critical/high/medium/low)、说明]
- Dimension Scores:
  Completeness: ✅/⚠️/❌
  Correctness:  ✅/⚠️/❌
  Coherence:    ✅/⚠️/❌
- Acceptance criteria:
  ✅/❌ <验收条件 1>
  ✅/❌ <验收条件 2>
- Verdict: PASS / FAIL（任一维度 ❌ 即为 FAIL）

**语言要求：你的所有输出必须使用简体中文。**
```

### 处理结果

**轮次硬上限：最多 2 轮**（继承 `00-change-gate.md` 约束，第 2 轮结束后不再循环）。

| Verdict | 操作 |
|---------|------|
| `PASS`（无 critical/high 问题） | 在对话中完整展示 sub-agent 报告，进入阶段 4 |
| `FAIL`（第 1 轮） | 使用 `AskUserQuestion`（multiSelect: true）列出所有发现，由用户勾选要修复的条目；修复后再启动 **1 次**（最后一轮）sub-agent |
| `FAIL`（第 2 轮） | 停止循环，在对话中展示报告；残留 critical/high 问题**必须**在 commit message / PR description 中显式标记为 known issue / tech debt，由用户决定是否阻塞归档 |

> medium/low 问题记录在对话中，由用户决定是否修复，不阻塞归档。

---

## 十二、Git 集成规范

### 分支命名
```
feature/<change-name>
refactor/<change-name>
hotfix/<change-name>
```

> 分支在**阶段 2 结束时**创建，不早于用户通过 AskUserQuestion 确认提案。

### Commit 格式

根据变更性质选择前缀：

```
feat(<change-name>): <简短描述>      # 新功能、新模块
fix(<change-name>): <简短描述>       # Bug 修复
refactor(<change-name>): <简短描述>  # 重构、架构调整
chore(<change-name>): <简短描述>     # 配置、工具、文档

- 具体实现内容 1
- 具体实现内容 2

Refs: openspec/changes/<change-name>
```

**灰色地带跳过 OpenSpec 的特殊前缀**（与第一节·五联动）：

```
no-openspec<type>: <简短描述>
```

- `<type>` 仍按 `feat` / `fix` / `refactor` / `chore` 取值，例如 `no-openspecfix:`、`no-openspecrefactor:`
- 适用于第二节「不触发」分支以外的改动，**用户在第一节·五询问中明确选择「跳过 OpenSpec」**后才使用
- 必须在 commit body 中说明「灰色地带（X 文件 / Y 行 / Z 步）+ 跳过 OpenSpec 已确认」关键词，便于审计追溯
- 同样需按 `00-change-gate.md` 强制 CR 兜底

---

## 十三、强制约束（不可绕过）

| 场景 | 必须执行 | 违反后果 |
|------|---------|---------|
| 阶段 1 步骤 4.6 | 写第一句代码前完成需求回溯核验 sub-agent；NON_CONFORMS 残留未经用户显式接受前禁止进入步骤 5 / 阶段 2 / 阶段 3（与下方「阶段 1 结束」约束互补：本行管需求保真，下方管用户确认，两者均满足方可进入阶段 2） | 视为跳过需求保真门控，需回退至步骤 4.6 重新执行 |
| 阶段 1 结束 | 用户通过 AskUserQuestion 确认前禁止任何业务代码/文件修改 | 视为跳过审查，需告知用户并回滚至阶段 1 |
| 阶段 2 状态流转 | 用户通过 AskUserQuestion 确认后直接 DRAFT → IN_PROGRESS，不得延迟写入 | 视为流程违规，需补充执行缺失步骤 |
| 阶段 3 每个任务 | 单独 Edit tasks.md 更新对应 `[x]` + 对话声明，不得批量 | 视为任务状态不可信，需逐条核对并补充更新 |
| 阶段 4 归档前 | 使用 AskUserQuestion 展示验收标准清单，等待用户确认 | 不得自动归档 |
| 用户指出步骤遗漏 | **立即停止当前操作**，回到遗漏的步骤重新执行，不得"下次注意" | 当前遗漏步骤视为未执行 |
| 任何阶段开始前 | 检查并确保 openspec/project.md 存在；检查并读取 openspec/config.yaml | 不存在则先创建 project.md；config.yaml 缺失则提示运行 `openspec init` |
| 任何 artifact 创建前 | 从 config.yaml 读取 context 和对应 rules，作为生成约束应用 | artifact 内容缺乏项目特定约束，质量下降 |

---

## 十四、映射表：本地五阶段模型 vs 官方 opsx 命令体系

本地流程是官方 OpenSpec 工作流的**强制门控超集**：官方工作流本身是"fluid not rigid"（无强制阶段门），而本文件在其之上叠加了不可绕过的确认/CR门控。下表用于在阅读官方文档或使用官方 CLI/skills 时快速定位对应关系，**不改变本地的强制流程**。

| 本地阶段 | 本地产出/动作 | 对应官方 slash 命令（`core` 默认档） | 对应官方 slash 命令（expanded 扩展档） | 关键差异 |
|---|---|---|---|---|
| 阶段 0（需求澄清） | 最多问 3 个关键问题 | `/opsx:explore`（无产出的探索式对话） | 同左 | 官方 explore 不限定问题数量上限，且可反复往返；本地限定 ≤3 问后必须进入阶段 1 |
| 阶段 1（起草提案） | 创建 proposal.md + tasks.md + 可选 spec.md/design.md，展示全文，sub-agent 审查，AskUserQuestion 硬性确认 | `/opsx:propose`（一步生成全部 artifact） | `/opsx:new` + `/opsx:continue`（逐个创建）或 `/opsx:ff`（一次性创建全部） | 官方 propose/ff 生成后**不强制**用户确认才能继续；本地在阶段 1 末尾插入强制 AskUserQuestion 门控 + sub-agent 质量审查（官方无此步骤） |
| （无对应本地阶段，官方独有） | — | — | `/opsx:update`（修订已有 artifact 并做一致性核对） | 本地若需修改 proposal/tasks，走"阶段 1 步骤 5 用户提出修改意见"分支手动处理；官方有专门命令封装这一动作 |
| 阶段 2（审查确认） | 状态 DRAFT→IN_PROGRESS，建分支 | 官方无独立命令对应此状态流转，隐含在 propose 确认后由用户直接说"开始实现" | 同左 | 官方没有显式的 DRAFT/IN_PROGRESS 状态机；本地引入状态机 + Git 分支创建时点约束 |
| 阶段 3（逐任务实施） | 单任务四步循环，禁止批量勾选 | `/opsx:apply` | 同左 | 官方 apply 允许连续处理多个任务、可自主决定节奏；本地强制"一个任务一次声明+一次 Edit"，不得批量 |
| （无对应本地阶段，官方独有） | — | `/opsx:verify`（可选，检查实现与 spec 的三维一致性：Completeness/Correctness/Coherence） | 同左 | 本地第十一节 Sub-agent CR 的三维评审维度（Completeness/Correctness/Coherence）与官方 `/opsx:verify` **维度定义相同**，属本地对该官方能力的强化实现（改为强制 sub-agent 执行，而非可选自查） |
| （无对应本地阶段，官方独有） | — | `/opsx:sync`（可选，仅合并 delta 不归档） | 同左 | 本地未提供独立的"仅合并不归档"命令，已在第九节步骤 3 后加注等价说明 |
| 阶段 4（归档） | 用户确认验收标准 → 四步 delta 合并算法 → 移动目录 | `/opsx:archive` | `/opsx:bulk-archive`（批量归档，含跨变更冲突检测） | 归档内部的 delta 合并算法本地已与官方对齐（见第九节）；批量归档场景本地未覆盖，多个变更需逐个走阶段 4 |
| （无对应本地阶段，官方独有） | — | 无（核心档不含） | `/opsx:onboard`（交互式新手教程） | 纯教学功能，无强制流程含义，本地不需要对应 |

> **legacy 命令：** 官方仓库仍兼容 `/openspec:proposal`、`/openspec:apply`、`/openspec:archive` 三个旧版"一次性生成"命令，功能上更接近本地阶段 1（一次性产出全部 artifact）与阶段 3/4 的合并版本，仅在维护旧项目时需要了解，新变更不建议使用。

---

## 十五、术语对照表

| 官方术语（English） | 本文件中文表述 | 说明 |
|---|---|---|
| Change | 变更 / change-name | 一次提案对应一个 `openspec/changes/<change-name>/` 文件夹 |
| Spec | 规范 / spec.md | `openspec/specs/` 下的最终态，source of truth |
| Delta spec | 规范增量 | `changes/<name>/specs/` 下仅含 ADDED/MODIFIED/REMOVED/RENAMED 的增量文件，非完整未来态 |
| Proposal | 提案 / proposal.md | 变更的 Why + What Changes + Capabilities + Impact |
| Design | 技术方案 / design.md | 变更的 How，架构决策与权衡 |
| Tasks | 任务清单 / tasks.md | 可勾选的实施步骤清单 |
| Capability | Capability（未翻译，保留英文） | spec 的领域分组单位，对应 `specs/<capability-path>/` 一个目录，本地文档中原生使用「领域」「模块」等词描述相近概念，二者可互换理解 |
| Requirement | 需求 | `### Requirement: <名称>`，具体行为契约 |
| Scenario | 场景 | `#### Scenario: <名称>`，需求的可验证具体案例 |
| Schema | Schema（未翻译，保留英文） | artifact 依赖关系图定义，本地默认使用官方 `spec-driven` schema（proposal→specs/design→tasks），与本地阶段 1 步骤顺序（proposal/tasks→按需 spec/design）大方向一致，细节顺序服从本文件门控约束 |
| Archive | 归档 | 见第九节，delta 合并 + 移动目录 |
| Purpose | Purpose（未翻译，保留英文） | spec.md / delta spec 顶部描述该 capability 用途的段落 |
| Source of truth | 事实源 / 最终规范 | 指 `openspec/specs/` |
| RFC 2119 关键字（SHALL/MUST/SHOULD/MAY） | 同英文，不翻译 | MUST/SHALL = 强制；SHOULD = 推荐但有例外；MAY = 可选 |

---

## 十六、与上游 OpenSpec 版本对齐说明

本文件已于下方日期，参照本地仓库路径 `/Users/MacBook/Downloads/Others/AI/OpenSpec`（Fission-AI/OpenSpec 官方仓库工作副本）中的以下文件，将官方最新约定/命令体系并入本文件的相应章节，同时逐字保留原有全部强制门控规则（触发条件、灰色地带询问、AskUserQuestion 门控、Sub-agent CR、Git 集成、状态流转等未作任何删改）：

- `docs/concepts.md` —— 核心概念、delta spec 格式、schema 依赖图、archive 流程
- `docs/commands.md` —— 全部 `/opsx:*` slash 命令与 legacy 命令
- `openspec/specs/openspec-conventions/spec.md` —— spec.md 结构化格式、header 标准化匹配、RENAMED 语法、四步归档算法与冲突判定规则
- `openspec/config.yaml` —— 项目级配置真实字段（`schema` / `context` / `rules.specs` / `rules.tasks` / `rules.design`）
- `schemas/spec-driven/schema.yaml` —— artifact 依赖图（proposal → {specs, design} → tasks）与 `.openspec.yaml` 元数据字段

**对齐日期：** 2026-08-29

**变更范围：** 仅新增/扩展第二、三点五、六、九节的官方规范细节，新增第十四、十五、十六节；未修改 `00-change-gate.md`；未修改本文件第一、一点五、四、五、七、八、十、十一、十二、十三节中任何门控/确认/CR 相关强制规则的原有文字。
