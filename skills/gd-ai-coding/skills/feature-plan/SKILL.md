---
name: dac-feature-plan
description: Use when a structured PRD (prd-spec.md) is confirmed and the project needs to be decomposed into executable feature units — generating openspec proposal and splitting into a dependency-aware feature list for development.
user-invocable: false
metadata:
  openclaw:
    emoji: "🗺️"
---

# dac-feature-plan — 项目级实现规划

触发方式：由主编排 Read 执行（不可直调）

## When to Use

- prd-spec.md 已确认，需要将需求拆分为可执行的功能任务列表
- 主编排 skill 阶段 2 自动调用

## When NOT to Use

- 需求文档尚未生成或未确认（先完成 `/gd-ai-coding` 阶段 1）
- 功能列表已存在且无需重新规划（直接进入 feature-loop）

## 职责

读取结构化需求文档（`prd-spec.md`），可选结合 Graphify 产物（`graphify-out/`）提供工程上下文，通过 openspec proposal 生成项目级代码变更规划，再从规划中机械拆分功能列表。

**`skip_feature_plan=true` 时：** 步骤 0–2（含 `opsx:propose`）**照常执行**；步骤 3 改为单 feature plan，跳过步骤 4 功能列表确认。禁止跳过 proposal。

**为什么 openspec 先行：**
1. openspec proposal 会分析现有代码库，输出具体的文件变更计划 — 这才是真正的"实现粒度"
2. 从代码变更计划拆任务，天然知道哪些文件有依赖、哪些可并行
3. 不会出现"需求上看着独立，但代码上高度耦合"的误拆

## 执行步骤

### 步骤 0：前置检查

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/pre-skill-check.sh feature-plan
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/audit-log.sh "" "STEP:START" "feature-plan"
```

返回非零则终止（脚本会输出具体缺失项：phase 不对等）。

---

### 步骤 1：构建项目级设计输入

**1.1 获取代码工程上下文（依据 env-checks 阶段用户决策）**

从 `.dac/state.json` 的 `graphify_decision` 字段读取用户在 env-checks 阶段的选择：

```bash
GRAPHIFY_DECISION=$(jq -r '.graphify_decision // "skip"' .dac/state.json)
```

- **`GRAPHIFY_DECISION=use`**（用户在 env-checks 时已选择使用）→ 直接执行 graphify query：
  ```
  /graphify query "项目整体架构、模块划分、路由结构、依赖注入方式、现有共享组件"
  ```

- **`GRAPHIFY_DECISION=skip`**（用户在 env-checks 时已选择跳过）→ 跳过此步骤，工程结构上下文留空。

**1.2 组合输入上下文**

将以下内容组合为 openspec artifacts 的输入：

1. **需求文档**：优先读取 `openspec/changes/{req_name}/prd/prd-spec.md`（完整内容，含 skip_prd_parse 时的轻量 spec）。若文件不存在，则降级使用 `.dac/state.json` 的 `ddp_title`（及用户说明）作为需求描述，并在 prompt 中注明"原始需求（未经裁剪）"
2. **工程结构**（如步骤 1.1 用户选择使用）：graphify query 返回的代码架构信息
3. **架构规范**：`${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/rules/` 下的 Flutter 规范文件
4. **已知约束**：`.dac/knowledge/constraints.md`（如有内容）
5. **设计稿**：`openspec/changes/{req_name}/ui/`（如有）— 提供 UI 结构和布局参考，辅助判断页面复杂度和组件拆分

---

### 步骤 2：生成 openspec 原生产物（4 artifacts）

使用 openspec OPSX 工作流一次性生成全部 4 个 artifact（`spec-driven` schema：proposal → specs → design → tasks）。所有产物写入 `openspec/changes/{req_name}/`。

---

#### 2.1 确保 openspec 项目配置

调用脚本自动扫描当前 Flutter 项目（pubspec.yaml 依赖 + lib/ 目录结构），生成 `openspec/config.yaml`：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/openspec/init-config.sh
```

**脚本行为：**

- 启动时打印 `cwd=...` 到 stderr，便于核对工作目录未漂移
- 退出码语义：`0` = 已存在跳过 / 新生成成功；`1` = 非 Flutter 项目（无 `pubspec.yaml`）
- 幂等：`openspec/config.yaml` 已存在 → 直接跳过，不覆盖用户已修改内容
- 不存在 → 扫描后生成，自动推断：
  - **状态管理**：flutter_bloc / riverpod / getx / provider / mobx
  - **路由**：go_router / auto_route / nacho
  - **DI**：get_it+injectable / get_it / lomo / Riverpod 内置
  - **架构**：feature-first（`lib/features/`、`lib/src/{≥3 子目录}/`）vs layer-first（`lib/screens|pages/`）
  - **测试栈**：flutter_test / mocktail / mockito / integration_test
- 非 Flutter 项目（无 `pubspec.yaml`）→ exit 1 报错

生成的 `config.yaml` 含 `schema: spec-driven`、推断出的 `context` 块、和默认 `rules` 块（与项目无关的通用 OpenSpec 输出约束）。如需调整，直接编辑文件即可，下次运行脚本不会覆盖。

---

#### 2.2 调用 /opsx:propose 生成全部 artifact

将步骤 1 构建的组合上下文（prd-spec.md + 工程结构[如有] + 架构规范 + 约束 + 设计稿）作为输入，调用 Skill 工具：

```
skill: "opsx:propose"
args: "{req_name} — {需求摘要≤200字} | 技术栈：{state-mgmt/router/DI} | 约束：{constraints 关键条目} | 页面：{设计稿页面列表}"
```

openspec 基于 `config.yaml` 的 context + rules 和传入的上下文，按依赖顺序（proposal → specs → design → tasks）自动生成全部 4 个 artifact。

**args 构造规则**：req_name 之后用 ` — ` 分隔，依次附加需求摘要（≤200 字）、技术栈关键词、constraints.md 中硬性约束、设计稿页面列表。总长度控制在 500 字以内，超出时优先保留需求摘要和约束。

生成的产物：
- `openspec/changes/{req_name}/proposal.md` — 项目级代码变更提案
- `openspec/changes/{req_name}/specs/{capability}/spec.md` — 形式化需求场景
- `openspec/changes/{req_name}/design.md` — 技术设计决策
- `openspec/changes/{req_name}/tasks.md` — 分组实现清单

> 注意：`design.md` 是**技术设计决策**文档，不同于设计稿产物（`ui_dsl.json` + `ui_tree.txt`，MasterGo UI 结构数据）。两者共存，各有用途。

---

> **⚠️ 回流锚点（必读）：opsx:propose 返回 ≠ feature-plan 完成**
>
> opsx:propose 是子 skill，**主会话本身就是 feature-plan 的调度者**，没有"外层"会自动接管。Skill 调用返回后必须：
>
> 1. **立即进入步骤 2.3**，禁止 end-of-turn，禁止输出"由调用方继续执行"或"流程交接给…"类描述性句子后停止。
> 2. **忽略 opsx:propose 返回内容中的下一步建议**（openspec 惯例会提示 `run /opsx:apply` 之类）— 那是 opsx 自身工作流的衔接，**不是** feature-plan 的下一步，本流程**永不调用 `/opsx:apply`**（codegen 由 feature-loop 自有管线完成）。
> 3. **禁止把"接下来运行 X"作为文字结束本轮**。要么真的通过 Skill / Bash 工具调用 X，要么继续执行 2.3 — 文本里的 `/skill-name` 不会被 harness 自动触发。
>
> 直到本 SKILL.md 步骤 5 (state-update.sh --phase feature-planned) 执行完成，feature-plan 才算结束。

---

#### 2.3 验证 openspec 产物

检查 4 个 artifact 文件全部存在且非空：

```bash
for f in proposal.md design.md tasks.md; do
  [ -s "openspec/changes/${req_name}/$f" ] || { echo "MISSING: $f"; exit 1; }
done
# 验证 specs/ 下每个子目录都含 spec.md
[ -d "openspec/changes/${req_name}/specs" ] || { echo "MISSING: specs/"; exit 1; }
for dir in openspec/changes/${req_name}/specs/*/; do
  [ -s "${dir}spec.md" ] || { echo "MISSING: ${dir}spec.md"; exit 1; }
done
echo "4/4 artifacts verified"
```

验证应显示 4/4 artifacts verified。如有缺失，回到步骤 2.2 重新生成对应文件，**最多重试 2 次**；仍缺失则记录日志并终止：
```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/audit-log.sh "" "STEP:FAILED" "feature-plan: openspec 产物验证重试耗尽"
```

---

#### 2.3.5 需求查漏补缺（强制，非条件触发）

**区别于步骤 2.4**：本步骤无论 PRD 章节数多少、是否传入 `--strict`，**一律强制执行**，核验粒度为需求细节（验收标准/边界条件/异常场景/交互态），不是步骤 2.4 的章节存在性检查。

**1. 启动核验 sub-agent**

读取 `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/prompts/requirement-gap-check.md` 定义的角色和核验方法。Claude Code 使用 `Agent` 工具（`run_in_background: false`）启动独立 sub-agent；Codex 必须按 `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/references/codex-agent-orchestration.md` 调用 `requirement-gap-checker`，门禁失败则输出 `BLOCKED` 并终止，禁止主会话核验替代。两种运行时均传入：

- `openspec/changes/{req_name}/prd/prd-spec.md`
- `openspec/changes/{req_name}/proposal.md`
- `openspec/changes/{req_name}/design.md`
- `openspec/changes/{req_name}/tasks.md`
- `openspec/changes/{req_name}/specs/**/spec.md`
- `.dac/state.json` 中的 `flow_profile.skip_prd_parse` 字段值（sub-agent 据此判断是否降低核验粒度期望）

**2. 处理核验结果**

- `CONFORMS`（零偏离 + 零缺失）→ 重置轮次计数，进入步骤 2.4
- `NON_CONFORMS`（存在任意 ⚠️偏离或 ❌缺失）→ 按矩阵中的具体条目修正 `proposal.md`/`design.md`/`tasks.md`/`specs/**/spec.md`，重新执行第 1 步。**不允许仅报告问题不修正就放行，不提供"接受残留"选项**

**3. 轮次计数与安全阀**

每轮核验前先调用轮次计数器：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/gap-check-loop-guard.sh increment
```

- 计数 ≤ 5 → 正常执行第 1-2 步
- 计数 > 5（第 6 轮）→ **不允许自动放行**，改为 `AskUserQuestion` 展示残留矩阵，选项仅包含：
  - **继续修正**（用户补充说明后再修正重跑）→ 调用 `bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/gap-check-loop-guard.sh reset` 重置计数后回到第 1 步
  - **回退 Phase 1 重新澄清需求** → 调用 `bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/recovery.sh --rollback-to prd-clarified`（真实回退 `.dac/state.json.phase`，不允许仅作对话提示），终止本次 feature-plan 执行

  **不提供"接受残留并继续"选项**。

核验通过（`CONFORMS`）后重置计数：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/gap-check-loop-guard.sh reset
```

**4. 超出项处理**

矩阵中的 ➕超出条目不阻塞放行，但在对话中列出，随功能拆分产物一并交由用户在步骤 4 展示功能列表时判断取舍。

---

#### 2.4 质量审查（条件执行）

当满足以下**任一条件**时，启动 Sub-agent 质量审查：
- prd-spec.md 存在且其中功能点（§3.x）≥ 5 个（通过脚本确定性计数）：
  ```bash
  spec_file="openspec/changes/${req_name}/prd/prd-spec.md"
  count=0
  [ -f "$spec_file" ] && count=$(grep -cE '^#{2,4}\s*§?3\.' "$spec_file")
  ```
- 用户显式传入 `--strict` 参数

**不满足条件时**：跳过审查，直接展示 proposal 概览供用户确认（用户确认本身即为质量门禁）。

**满足条件时**：使用 `Agent` 工具启动独立审查 sub-agent，按 `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/prompts/proposal-review.md` 定义的角色和评估维度执行审查。

传入文件：
- `openspec/changes/{req_name}/prd/prd-spec.md`
- `openspec/changes/{req_name}/proposal.md`
- `openspec/changes/{req_name}/design.md`
- `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/platform/flutter/rules/flutter-architecture.md`

收到结果后：
- `READY` → 进入"展示 proposal 概览"
- `NEEDS_REVISION` → 修正对应 artifact 后重新运行审查，最多 2 轮；仍未通过则记录日志并终止：
  ```bash
  bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/audit-log.sh "" "STEP:FAILED" "feature-plan: proposal 审查未通过（2 轮修正后仍 NEEDS_REVISION）"
  ```

展示 proposal 概览（文件变更统计 + 模块划分 + 技术决策摘要）：

```
项目级实现规划已生成：openspec/changes/{req_name}/

openspec artifacts：
  ✓ proposal.md  — 变更提案（新增 X 个文件，修改 Y 个文件，涉及 Z 个模块）
  ✓ specs/       — 形式化需求场景（N 个 capability）
  ✓ design.md    — 技术决策（状态管理：Bloc，路由：GoRouter，...）
  ✓ tasks.md     — 实现清单（M 个任务分组）
```

然后使用 `AskUserQuestion` 询问（**禁止**改用纯文本列出选项后等待输入）。

若 `skip_feature_plan=true`，继续按钮文案改为「确认，使用单功能进入开发」（不拆多 feature）：
```json
{
  "questions": [{
    "question": "以上项目级实现规划是否确认？确认后将整份 proposal 收成一个功能进入开发，不再拆分。",
    "header": "确认 Proposal",
    "options": [
      { "label": "确认，使用单功能进入开发", "description": "已跳过功能拆分：proposal 作为 feat-01 的范围" },
      { "label": "需要调整", "description": "请在下一条消息中说明调整方向" },
      { "label": "重新生成", "description": "调整输入后重新生成 proposal" }
    ]
  }]
}
```

若 `skip_feature_plan=false`：
```json
{
  "questions": [{
    "question": "以上项目级实现规划是否确认？",
    "header": "确认 Proposal",
    "options": [
      { "label": "确认，继续拆分功能", "description": "推荐：规划合理，继续执行功能拆分" },
      { "label": "需要调整", "description": "请在下一条消息中说明调整方向" },
      { "label": "重新生成", "description": "调整输入后重新生成 proposal" }
    ]
  }]
}
```

收到 `is_error=true` 后**静默等待**用户消息（见 `rules/plugin-interaction.md`），通过语义理解判断意图：
- 含"确认"/"继续"/"ok"/"好"/"单功能" → 更新状态并继续
- 含"调整"/"修改" → 等待用户说明调整方向后按 2.5 节执行
- 含"重新生成" → 按 2.5 节重新生成

用户确认后更新状态：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/state-update.sh --phase proposal-approved
```

若用户选择「需要调整」或「重新生成」，**必须按以下顺序执行，禁止跳过第一步直接改文件**：

**第一步 — 上报（先于任何文件修改）：**

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/report-user-gate.sh \
  proposal rejected \
  --msg '<用户的原始发言，原文>' \
  --reason '<AI一句话总结：为什么被拒绝>' || true
```

「接受」不要在这里报：用户确认后的 `--phase proposal-approved` 会打 `proposal_accepted`。

**第二步 — 然后再**按用户意见修改 proposal 或重新生成。

#### 2.5 提取设计决策到 knowledge（自动积累，非阻塞）

从 `design.md` 提取关键技术决策，追加到 `.dac/knowledge/decisions.md`，供后续功能开发参考：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/knowledge/extract-decisions.sh || echo "WARN: 决策提取失败，不影响后续步骤"
```

**此步骤失败不阻塞步骤 3**（decisions.md 服务于后续 req 的 codegen，非当前流程的硬性依赖）。

脚本行为：
- 解析 `design.md` 中的 Decision 条目（通常为 `### Decision: ...` 或 `**Decision:**` 格式）
- 提取决策标题、选择方案、原因
- 去重后追加到 `.dac/knowledge/decisions.md`
- 幂等：同一 req_name 重复执行不会重复追加

---

### 步骤 3：功能拆分（主会话直接执行）

**flow_profile 跳过检查：** 若 `skip_feature_plan=true`（`jq -r '.flow_profile.skip_feature_plan // false' .dac/state.json`）：

1. 步骤 2 的 4 个 artifact **必须已存在**（`proposal.md` 缺失则回到 2.2，禁止用空 plan 糊弄）
2. 写成单 feature（从 proposal 提取文件列表）。脚本会把 `ui/index.json` 里尚未关联的设计稿挂到该 feature（正常拆分路径靠 LLM `design_backfill`，skip 时不会走那步）：
   ```bash
   bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/feature/write-single-feature-plan.sh
   bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/feature-plan-schema-check.sh
   bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/coverage-check.sh
   bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/dependency-check.sh
   ```
3. 输出 `⏭ 跳过功能拆分（flow_profile：proposal 已生成，收成 feat-01）`
4. **跳过步骤 4**（不再展示多功能列表确认），直接进入步骤 5

**正常路径（skip_feature_plan=false）：**

读取 `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/prompts/feature-splitter.md` 的角色定义、分组规则、自检清单，作为本步骤的执行指令。

**3.0 加载输入文件**

读取以下文件完整内容：
- `openspec/changes/{req_name}/proposal.md`
- `openspec/changes/{req_name}/tasks.md`
- `openspec/changes/{req_name}/prd/prd-spec.md`
- `openspec/changes/{req_name}/ui/index.json`（如存在）

**3.1 执行拆分**

按 `feature-splitter.md` 的分组规则和禁止事项，完成：拆分 + 自包含验证 + 需求覆盖自检 + 依赖最小化，输出 feature-plan.json 和设计稿回填数据。

将结果写入 `openspec/changes/{req_name}/feature-plan.json`。如有设计稿回填数据，更新 `index.json` 的 `features` 字段。

**3.2 硬校验（安全兜底）**

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/feature-plan-schema-check.sh
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/coverage-check.sh
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/dependency-check.sh
```

- 三项均通过 → 进入步骤 4
- schema 校验失败 → 修正 JSON 结构（缺少必填字段、类型错误等），最多重试 3 次；仍失败则向用户展示具体 schema 错误，等待人工介入
- coverage/dependency 校验失败 → 根据错误信息修正拆分方案，最多重试 2 次；仍失败则向用户展示具体问题，等待人工介入

任何校验重试耗尽仍失败时，记录日志后终止：
```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/audit-log.sh "" "STEP:FAILED" "feature-plan: 校验重试耗尽 - ${check_name}"
```

---

### 步骤 4：展示功能列表并确认

`skip_feature_plan=true` 时跳过本节。

按 `skills/feature-plan/references/feature-list-display.md` 的表格格式展示拆分结果，**然后必须调用 `AskUserQuestion` 工具**（禁止用纯文本列选项等待输入）：

```json
{
  "questions": [{
    "question": "以上功能拆分是否合理？",
    "header": "确认功能拆分",
    "options": [
      { "label": "确认，开始一人开发", "description": "拆分合理，立即进入 Phase 3 串行开发全部 feature" },
      { "label": "确认，进入多人协作", "description": "拆分合理，暂停开发；先分析分层与文件交叉，按 DAG 指派给多人（走 collab.json + assignee 落盘）" },
      { "label": "调整顺序", "description": "请在下一条消息中说明调整方式" },
      { "label": "合并/拆分/增删功能", "description": "请在下一条消息中说明具体操作" }
    ]
  }]
}
```

收到 `is_error=true` 后**静默等待**用户消息，通过语义理解判断意图：
- 含"确认"/"开始"/"一人开发" → 进入一人开发
- 含"多人"/"协作"/"分给"/"两个人一起" → 进入**多人协作分叉**
- 含调整/合并/拆分/增删意图 → 按用户说明修改后重新展示，直到确认

**选择"确认，进入多人协作"后**，按 `skills/feature-plan/references/feature-list-display.md` 的"多人协作分叉"章节执行（A展示分层 → B收集协作者 → C建议指派 → D落盘并暂停）。

**用户对功能列表提出任何修改意见（含描述调整、结构变更、补充细节等），必须按以下顺序执行，禁止跳过第一步直接改文件**：

**第一步 — 上报（先于任何文件修改）：**

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/report-user-gate.sh \
  feature_plan adjusted \
  --msg '<用户的原始发言，原文>' \
  --reason '<AI一句话总结：做了什么调整>' \
  --adjustment '<merge|split|add|delete|reorder|description|other>' || true
```

用户最终确认后 `--phase feature-planned` 会打 `feature_plan_accepted`，不要在 skill 里再报接受。

**第二步 — 然后再**修改 `feature-plan.json`，重新执行步骤 3.2 的三项校验，校验通过后再次展示更新后的列表供确认。

---

### 步骤 5：保存并更新状态

用户确认后保存：

```
openspec/changes/{req_name}/feature-plan.json
```

把规划时即为 `skipped` 的 feature（无开发）写入 `state.json.skipped_features`（不改变 phase）：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/state-update.sh --phase feature-planned
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/feature/sync-skipped-from-plan.sh
```

---

### 步骤完成

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/audit-log.sh "" "STEP:DONE" "feature-plan"
```

### 输出产物

- `openspec/changes/{req_name}/proposal.md`：项目级代码变更提案（openspec 原生 artifact）
- `openspec/changes/{req_name}/specs/{capability}/spec.md`：形式化需求场景（openspec 原生 artifact）
- `openspec/changes/{req_name}/design.md`：技术设计决策（openspec 原生 artifact）
- `openspec/changes/{req_name}/tasks.md`：分组实现清单（openspec 原生 artifact）
- `openspec/changes/{req_name}/feature-plan.json`：功能列表（从 tasks.md 派生，含 proposal_scope）
- `.dac/state.json`：phase 更新为 `feature-planned`
