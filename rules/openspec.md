---
name: OpenSpec Workflow
description: Structured 5-phase change management; triggers on complexity (new feature, refactor, cross-subsystem), NOT on file count alone
inclusion: always
---

# OpenSpec 规范驱动开发（强制步进模式）

## 核心行为

遇到复杂需求时，Claude 自动创建并维护 `openspec/` 目录下的所有规范文件，
全程驱动五阶段工作流（阶段 0–4）。

**每个阶段都是独立的门控节点（Phase Gate）：**
- 前一阶段的退出条件未满足，绝对不进入下一阶段
- 每个阶段有明确的「进入声明 → 文件操作 → 对话输出 → 退出条件」四要素
- 用户未通过 AskUserQuestion 明确确认前，禁止推进到下一阶段

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

## 二、目录结构（由 Claude 自动创建维护）

```
openspec/
├── project.md              # 项目上下文（优先级最高，所有阶段依赖此文件）
├── specs/                  # 已归档的最终规范（source of truth）
├── changes/                # 进行中的变更
│   └── <change-name>/
│       ├── proposal.md     # 变更提案
│       ├── tasks.md        # 任务清单（含实时状态）
│       └── specs/          # 本次变更的规范增量
│           └── <domain>/
│               └── spec.md
└── archive/                # 已完成归档的变更
    └── YYYY-MM-DD-<change-name>/
```

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

**不存在时：** 使用 AskUserQuestion 提示用户选择：**[继续]** 或 **[先运行 /opsx:init]**。等待用户选择后再继续。

**已存在时：** 读取并解析以下字段，在后续所有 artifact 生成步骤中作为**约束条件**应用：
- `context`：项目技术栈、架构、平台信息
- `rules.specs`：spec artifact 生成约束
- `rules.tasks`：tasks artifact 生成约束
- `rules.design`：design artifact 生成约束

> **注意：** `context` 和 `rules` 是约束注入，不得将其内容原文复制到任何 artifact 文件中。

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

使用 WHEN/THEN 场景格式：

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

使用以下结构：

```markdown
## 上下文
## 目标 / 非目标
## 决策
## 风险 / 权衡
```

创建的文件均须在对话中展示完整内容（代码块，不得用摘要替代）。

> **Artifact 依赖约束：** tasks.md 必须在 spec.md 和 design.md 内容确定后才起草，以确保任务与规范完全对齐。

### 步骤 4.5：Sub-agent Proposal 质量审查

在向用户展示提案前，使用 `Agent` tool 启动独立审查 sub-agent。

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
- `NEEDS_REVISION` → 先按 Issues 修正 proposal.md / tasks.md，重新运行，直到 `READY`

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
3. 再次使用 AskUserQuestion 等待用户确认

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
3. 将 `openspec/changes/<change-name>/specs/` 内容合并写入 `openspec/specs/`：
   - 目标路径无同名文件 → 直接写入
   - 存在同名文件 → 展示冲突内容，由用户决定覆盖、追加或跳过
4. 将整个 `openspec/changes/<change-name>/` 目录移至 `openspec/archive/YYYY-MM-DD-<change-name>/`（日期取当日，如 `2026-06-05-add-ride-filter`）
5. 在对话中声明：`> ✅ 归档完成：openspec/archive/YYYY-MM-DD-<change-name>/`

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
3. 使用 `Agent` tool 启动 sub-agent，传入以下 Prompt（**不得包含任何正面定性语句**，不得提及"已经实施者检查"）：

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

| Verdict | 操作 |
|---------|------|
| `PASS`（无 critical/high 问题） | 在对话中完整展示 sub-agent 报告，进入阶段 4 |
| `FAIL` | 必须修复所有 critical/high 问题后，重新启动 sub-agent，循环直到 `PASS` |

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

---

## 十三、强制约束（不可绕过）

| 场景 | 必须执行 | 违反后果 |
|------|---------|---------|
| 阶段 1 结束 | 用户通过 AskUserQuestion 确认前禁止任何业务代码/文件修改 | 视为跳过审查，需告知用户并回滚至阶段 1 |
| 阶段 2 状态流转 | 用户通过 AskUserQuestion 确认后直接 DRAFT → IN_PROGRESS，不得延迟写入 | 视为流程违规，需补充执行缺失步骤 |
| 阶段 3 每个任务 | 单独 Edit tasks.md 更新对应 `[x]` + 对话声明，不得批量 | 视为任务状态不可信，需逐条核对并补充更新 |
| 阶段 4 归档前 | 使用 AskUserQuestion 展示验收标准清单，等待用户确认 | 不得自动归档 |
| 用户指出步骤遗漏 | **立即停止当前操作**，回到遗漏的步骤重新执行，不得"下次注意" | 当前遗漏步骤视为未执行 |
| 任何阶段开始前 | 检查并确保 openspec/project.md 存在；检查并读取 openspec/config.yaml | 不存在则先创建 project.md；config.yaml 缺失则提示运行 /opsx:init |
| 任何 artifact 创建前 | 从 config.yaml 读取 context 和对应 rules，作为生成约束应用 | artifact 内容缺乏项目特定约束，质量下降 |
