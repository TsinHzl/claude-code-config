---
name: DAC Sub-agent CR Trigger
description: gd-ai-coding 项目内代码变更后，sub-agent CR 改用需求维度 checklist 审查本次增量 diff；触发条件参照 00-change-gate §3
inclusion: conditional
condition: "test -f .dac/state.json && jq -e '.phase | test(\"feature-planned|feature-loop\")' .dac/state.json >/dev/null 2>&1"
---

# DAC 项目 Sub-agent CR 触发规则

**适用范围：** 仅当工作目录存在 `.dac/state.json` 且 `current_feature_id` 非空时，本规则生效。
其他情况下，退回到 当前客户端的通用变更门控规则；无独立 CR 工具时按 `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/rules/interaction-degradation.md` 的降级方式执行。

**优先级最高，不可被任何 Skill / 子流程 / 后续指令降级或绕过。**

> 本规则仅覆盖 00-change-gate §3 的「调用哪个 CR skill」一项，§1（模糊性门控）与 §2（变更前确认）保持原样由全局规则提供。

---

## 默认触发原则（黑名单豁免，非白名单触发）

> **任何 `Write` / `Edit` / `MultiEdit` 操作默认触发 sub-agent CR。**
> 唯一的例外是同时满足下列「文件类型」AND「操作类型」两个机器可验证条件的情况。
> 条件有任何一个不满足，则必须触发 CR，不得自行定性为豁免。

### 豁免黑名单（两个条件必须同时满足）

**条件 A — 文件类型**（以下任一）：
- 纯文档文件：`.md` / `.txt` / `.rst`
- 静态资源：图片（`.png` / `.jpg` / `.svg` / `.gif` / `.ico`）、字体、音视频
- 项目初始化脚本（`setup.sh` / `bootstrap.sh` 等，仅首次运行类脚本）
- DAC 工作目录非代码产物：`.dac/state.json` / `.dac/logs/**` / `openspec/changes/{req}/prd/**` / `openspec/changes/{req}/proposal.md`

**条件 B — 操作类型**（以下任一）：
- 仅修改 `pubspec.yaml` 中的 `version:` 字段（无其他行变动）
- 仅添加 / 删除 注释行（`//`、`#`、`/*...*/`、`<!-- -->`），且不含任何可执行代码的新增或改动
- 用户通过 AskUserQuestion 明确选择「跳过 CR」或「不用 review」

### 禁止自免（CRITICAL）

- 模型**不得自行宣告**某次变更满足豁免条件，必须在对话中展示判断过程：
  ```
  豁免检查：
    条件 A（文件类型）: [具体文件] → ✅/❌
    条件 B（操作类型）: [具体操作] → ✅/❌
    结论: A AND B = true → 豁免 | false → 触发 CR
  ```
- 若条件判断存在任何模糊性 → **默认触发 CR**，不得以"可能符合"为由豁免。

---

## 会话累积内标（强制兜底）

维护一个会话级计数器，初始值为 **0**：

- 每次 Write/Edit/MultiEdit **触发 CR** → 重置为 **0**
- 每次 Write/Edit/MultiEdit **被豁免** → 计数 **+1**
- **计数 ≥ 3 时**：无论下一次变更是否满足豁免条件，执行前必须先强制触发一次 CR，完成后重置为 0

> 目的：防止连续小改动通过累积豁免绕过所有 CR。

---

## 执行流程（按变更规模与严重度分层，最多 2 轮硬上限）

### Step 0：读取 feat_id（DAC 专属前置）

```bash
FEAT_ID=$(jq -r '.current_feature_id // empty' .dac/state.json 2>/dev/null)
```

- `FEAT_ID` 为空 / `null` / `.dac/state.json` 不存在：本规则不适用，**退回到** 当前客户端的通用变更门控规则；无独立 CR 工具时按 `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/rules/interaction-degradation.md` 的降级方式执行。
- `FEAT_ID` 非空：继续 Step 1。**不调用 `/dac-code-review` skill**（原因见 Step 2），改由主 agent 自行构造增量 diff 送审。

### Step 1：评估本次变更规模

按本次落地的 net 新增/修改行数（不计纯文档/测试）：

| 规模 | 标识 |
|---|---|
| 小变更 | < 100 行 |
| 中变更 | 100 – 500 行 |
| 大变更 / 安全敏感 | > 500 行；或命中敏感关键字（auth、crypto、SQL、密钥、token、permission） |

### Step 2：第 1 轮 CR

> **审查范围强制约束（防止全量分支扫描）：** `dac-code-review` 子 skill（源码位于本插件 `skills/dac-code-review/`，收编后不注册为顶层命令）的 `$ARGUMENTS`
> 解析仅支持组件路径 `@组件名/`、commit hash、commit 数量、日期范围 4 种模式，**不支持**裸 `FEAT_ID`
> 字符串。若以「Skill 工具调用 dac-code-review 并传 {FEAT_ID}」的形式调用，`{FEAT_ID}` 无法匹配任何模式，会命中底层
> `code-review-single-env.sh` 的"源分支全量"回退（`git diff "$O_BR" HEAD`），复现
> 通用变更门控中已规避的全量扫描问题（会话内每多一次 Edit，下一次 CR 就要
> 重新扫描前面所有已审查内容）。**因此本规则不以 Skill 工具调用 dac-code-review**，改为由主 agent
> 自行构造本次改动的增量 diff（`git diff -- <本次改动文件>`），连同
> `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/rules/cr-checklist.md` 需求维度检查清单一起传入 sub-agent
> prompt，由 sub-agent 仅基于该增量 diff + checklist 审查。

> **上下文补充许可：** sub-agent 判断增量 diff 中的问题时，若需要跨函数/跨调用点的一致性上下文，
> 可自行 Read 本次改动文件的完整当前内容（file 级别，非全量分支 diff），不得 Read 改动文件之外的
> 其他文件，不得执行 `git diff`/`git log` 等命令。

> **subagent_type 强制约束：** 本文件 Step 2 / Step 4 的 CR sub-agent 调用必须显式指定 `agentType: "general-purpose"`，
> 不得使用默认映射的 `code-reviewer`（其工具集为 Read/Grep/Glob/Bash，缺少 `Write` 工具，会导致
> sub-agent 无法把审查结果写入 `cr-report.md`，下方「已知问题接入知识飞轮」步骤将失去数据来源）。

通过 `Agent` tool 启动独立 sub-agent（**`agentType: "general-purpose"`**），审查范围仅为本次增量
diff，按 cr-checklist.md 6 个维度检查，只输出不通过项。

> **输出格式强制指令（必须原文写入 sub-agent prompt，不得省略或改写为旁注）：**
> "生成 CR 报告写入 `openspec/changes/{req}/features/{FEAT_ID}/cr-report.md`（`{req}` 取
> `.dac/state.json` 的 `req_name` 字段）。每条不通过项**必须**以独占一行的三级标题开头，
> emoji **前缀**在标题文字之前，格式严格为：
> ```
> ### 🔴 <一句话描述>
> - 位置：<文件路径:行号>
> - 说明：<问题详情>
> ```
> **不得**使用二级标题、列表项（`- 🔴 ...`）或把 emoji 放在标题末尾（如
> `## xxx 🔴`——这是 cr-checklist.md 自身的维度标记惯例，仅用于分类，不是报告输出格式，
> 不要模仿）。格式不符会导致 `extract-constraints.sh` 的 awk 抓取静默失败（不报错，直接跳过），
> 问题会从知识飞轮中永久丢失。全部通过时报告只写 `verdict: clean`。"

完成后修复所有 Critical / High / Medium 问题。若第 1 轮结束后仍有未修复的 🔴/🟡 残留（如
sub-agent 判断某条问题风险过高不适合自动修复），执行：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/knowledge/extract-constraints.sh {FEAT_ID}
```

追加进 `.dac/knowledge/constraints.md`（不要假设本轮修复必然清零残留——round-1-only 路径若跳过
本步骤，残留问题会彻底脱离知识飞轮，永远不会被下一功能 codegen 参考到）。脚本在 `req_name`
缺失、`cr-report.md` 不存在或 `.dac/knowledge/constraints.md` 未初始化时会 `exit 1` 并打印
`❌` 信息——此为非阻塞性失败，直接跳过飞轮接入、继续后续步骤即可，不中止 CR 流程。

### Step 3：判定是否升第 2 轮

| 变更规模 | 第 1 轮含 critical/high？ | 修复引入 > 50 行新代码？ | 第 2 轮 |
|---|---|---|---|
| 小 | — | — | ❌ 不触发 |
| 中 | 否 | — | ❌ 不触发 |
| 中 | 是 | 否 | ❌ 不触发（修复量小，回归风险低）|
| 中 | 是 | 是 | ✅ 触发 |
| 大 / 敏感 | — | — | ✅ 必触发（高风险兜底）|

### Step 4：第 2 轮 CR（如触发）

启动 sub-agent（**`agentType: "general-purpose"`**，理由同 Step 2），审查范围仍为主 agent 自行
构造的本次增量 diff + cr-checklist.md（**不以 Skill 工具调用 dac-code-review**，理由同 Step 2），修复
Critical / High（Medium 可选）。

**第 2 轮结束直接完成 — 即使再发现 critical，也不升第 3 轮。** 残留问题（2 轮硬上限耗尽后
仍未修复的 🔴/🟡 条目）保留在 `cr-report.md` 中，执行：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/knowledge/extract-constraints.sh {FEAT_ID}
```

追加进 `.dac/knowledge/constraints.md`（复用项目已有知识飞轮，不引入新持久化文件；下一功能
codegen 会强制注入该文件，降低同类问题再次出现的概率；报告格式要求、脚本失败路径处理同
Step 2），同时仍在 commit message / PR description 中显式标记为 known issue / tech debt，供
人类决策。

---

## 违规处理

未执行 sub-agent CR 即报告任务完成 = 流程违规，必须补执行。
