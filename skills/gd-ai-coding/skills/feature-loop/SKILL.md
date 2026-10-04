---
name: dac-feature-loop
description: Use when executing a single feature's development cycle within the gd-ai-coding workflow — triggered by the main orchestrator (single-session or sub-agent mode) after feature-plan is confirmed.
argument-hint: "[feature_id]"
user-invocable: false
metadata:
  openclaw:
    emoji: "🔄"
---

# dac-feature-loop — 单功能开发循环

触发方式：由主编排 Read 执行（不可直调），参数 `[feature_id]`

## When to Use

- 主编排 skill（gd-ai-coding）进入阶段 3 后，对每个待执行功能调用
- 用户手动对某个功能重新执行开发循环（如中断恢复、CR 修复后重跑）

## When NOT to Use

- 需求尚未拆分为功能列表（先完成 feature-plan 拆分）

## 职责

执行单个功能的完整开发循环：设计解析 → 代码范围派生 → 代码生成 → 测试用例生成与验证 → CR 校验。
由主编排 skill 按拓扑排序串行调用，每个功能完成后 context compression 自动回收中间 token，为下一个功能腾出上下文空间。使用 sub-agent 的环节是步骤 4.5（测试用例生成/验证）与步骤 5（CR），原因均为角色隔离。

## 前置条件

- `openspec/changes/{req_name}/feature-plan.json` 存在
- `openspec/changes/{req_name}/prd/prd-spec.md` 存在（`skip_prd_parse=true` 时为主编排生成的轻量 spec，仍作为需求记录；仅文件确实缺失时才降级 `ddp_title`）
- 如未传入 `feature_id`：
  - **单人模式**（无 `openspec/changes/{req_name}/collab.json`）→ 读取 feature-plan.json 中第一个 `status: "pending"` 的功能（原行为）
  - **协作模式**（有 `collab.json`）→ 按拓扑序选第一个通过 `scripts/collab/guard.sh` 且 `assignee` 匹配当前 `git config user.email` 的 pending feature；无可跑时展示等待原因（列出缺哪些依赖、需 git pull 谁的提交），不启动、不标 skipped

## 执行步骤

> **进度清单（运行时可视化）：** 进入某个 feature 时，用当前环境可用的会话任务清单工具追加 **1 条**条目 `F{FEAT_ID} › {feat_name}`，status=`in_progress`。每进入新步骤时通过 **TaskUpdate 修改 subject/activeForm** 反映当前动作（如 `[代码生成中]`、`[CR 校验中]`），不新建条目。完成时 status=`completed`，subject 追加 `[完成]`；失败时标注 `[失败]` 并与 `state.json` 的 `skipped_features` 对齐。重试期间保持 `in_progress`，只更新文案。进度清单仅为展示层、不参与流程判定，规则详见 `rules/progress-tracking.md`。

### 步骤 0：Harness 初始化

执行以下 shell 命令（顺序执行，任何失败则终止）：

```bash
# 0. 协作模式门禁（单人模式短路 exit 0；有 collab.json 或 assignee 非空时走 assignee/deps/文件交叉校验）
#    非 0 立即终止，不做任何后续副作用（不建目录、不写 snapshot、不改状态）
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/collab/guard.sh $FEAT_ID || exit 1

# 1. 创建功能工作目录（各子 skill 写产物的前置条件）
mkdir -p openspec/changes/$REQ_NAME/features/$FEAT_ID

# 2. 锁定 knowledge 文件快照（仅首个 feature 执行，确保 codegen prompt 前缀稳定以利用 API cache）
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/knowledge/snapshot-knowledge.sh

# 3. 记录功能循环开始
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/audit-log.sh $FEAT_ID "STEP:START" "feature-loop"
```

> `guard.sh` 错误码：`[DAC-STATE-020]` 非 assignee / `[DAC-STATE-021]` 他人 in_progress / `[DAC-DEP-003]` 依赖未完成 / `[DAC-PLAN-006]` 文件交集。详见 `rules/error-catalog.md`。

> `snapshot-knowledge.sh` 幂等，重复执行只会覆盖同一 snapshot 文件。循环结束后由步骤 6 清理。

---

### 步骤 1：加载功能上下文

从 `openspec/changes/{req_name}/feature-plan.json` 读取当前功能的完整信息，输出：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
开始处理功能：{feat_id}
名称：{name}
类型：{type} | 依赖：{dependencies}
描述：{description}

关联需求：{related_requirements}
关联设计稿：（从 index.json 查询，如有）
（验收基准参见 prd-spec.md 对应章节）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

更新功能状态（通过原子状态更新脚本）：

```bash
<!-- state: feature $FEAT_ID → in_progress -->
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/state-update.sh $FEAT_ID in_progress
```

---

### 步骤 2：派生 code-scope.md + 预切片

**flow_profile：** `skip_feature_plan=true` 只表示未做多功能拆分；**只要 `proposal_scope` 里已有文件**（`write-single-feature-plan.sh` 从 proposal 填入），仍须跑 `gen-code-scope.sh`。仅当 new_files 与 modified_files 都为空时才跳过派生，输出 `⏭ 跳过 code-scope 派生（proposal_scope 为空）`。

```bash
REQ=$(jq -r '.req_name // empty' .dac/state.json)
SCOPE_EMPTY=$(jq -r --arg id "$FEAT_ID" '
  (if type == "array" then . else .features end)
  | map(select(.id == $id)) | .[0].proposal_scope
  | ((.new_files // []) + (.modified_files // [])) | length == 0
' "openspec/changes/$REQ/feature-plan.json")
if [ "$SCOPE_EMPTY" = "true" ]; then
  echo "⏭ 跳过 code-scope 派生（proposal_scope 为空）"
  bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/record-trace.sh --skip-stage feature_plan || true
else
  bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/feature/gen-code-scope.sh $FEAT_ID
fi
```

脚本产出（均写入 `openspec/changes/{req_name}/features/{feat_id}/`）：
- `code-scope.md` — 从 `proposal_scope.new_files` / `modified_files` 生成的改动范围表格
- `proposal-slice.md` — 从 `proposal.md` 按 `proposal_scope.proposal_section` 标题提取的对应章节（可选，标题未匹配时跳过）
- `spec-slice.md` — 从 `prd-spec.md` 按 `related_requirements` 提取的关联需求章节（可选，无关联时跳过）

预切片文件供后续 codegen 和 CR 直接读取，避免运行时从大文件 grep 定位。

**失败处理**：脚本 exit 1 时（feature-plan.json 不存在或当前功能的 `proposal_scope` 字段缺失），向用户报告并终止当前功能循环。预切片（proposal-slice/spec-slice/design-slice）生成失败不阻断流程（stderr 输出 warning）。下游 `assemble-codegen-prompt.sh` 对缺失切片文件做优雅降级：缺失 spec-slice.md 时输出"无关联需求章节"占位符，缺失 design-slice.md 时回退读取完整 design.md。

**Graphify 现有组件上下文（可选，零 LLM token）：**

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/feature/gen-graphify-context.sh $FEAT_ID
```

从项目 `graphify-out/graph.json` 中提取与当前 feature 涉及目录相关的现有组件节点和依赖关系，输出 `graphify-context.md`。供 codegen sub-agent 定位已有代码（如"已有 Banner 组件在哪"）。`graphify-out/` 不存在时静默跳过，不阻断流程。

---

### 步骤 3：加载设计资料

**flow_profile 跳过检查：** 若 `skip_mastergo=true`（`jq -r '.flow_profile.skip_mastergo // false' .dac/state.json`），跳过整个步骤 3，输出 `⏭ 跳过 MasterGo（flow_profile）`。记录跳过事件：`bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/record-trace.sh --skip-stage mastergo || true`。直接进入步骤 4。

**3.1 从 index.json 查询并复制设计稿（bash 脚本，不消耗 LLM token）**

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/feature/copy-design-assets.sh $FEAT_ID
```

脚本行为：
- 从 `index.json` 筛选关联当前 `$FEAT_ID` 的设计稿目录
- 单个匹配：直接 `cp` 到功能目录
- 多个匹配：用 `jq` 合并 JSON nodes 数组，拼接 tree 文本（`--- Page: {node_name} ---` 分隔）
- 输出到 `openspec/changes/{req_name}/features/{feat_id}/ui_dsl.json` + `ui_tree.txt`

**脚本退出码：**
- exit 0：复制/合并成功 → 进入 3.3 节点选择
- exit 2：无关联设计稿（index.json 不存在或无匹配） → 进入 3.2 判断
- exit 1：错误 → 报告用户

**3.2 询问用户是否需要设计稿**

使用 `AskUserQuestion` 询问（**禁止**改用纯文本列出选项后等待输入）：
```json
{
  "questions": [{
    "question": "功能「{name}」未关联设计稿，是否需要补充？",
    "header": "设计稿",
    "options": [
      { "label": "提供 MasterGo 设计稿链接", "description": "请在下一条消息中粘贴链接" },
      { "label": "提供截图路径", "description": "视觉解析生成 UI 描述" },
      { "label": "不需要，基于 PRD 生成", "description": "跳过设计稿，仅用 PRD 描述生成代码" }
    ]
  }]
}
```

收到 `is_error=true` 后**静默等待**用户消息（见 `rules/plugin-interaction.md`），通过语义理解判断意图：
- 含 MasterGo 链接或"提供链接"意图 → Read 执行 `skills/ui-spec/SKILL.md`（参数 `{feat_id}`，内部幂等：已有 DSL 产物时跳过网络请求）→ 进入 3.3
- 含截图路径或"截图"意图 → 读取截图文件，通过视觉解析生成 `ui_tree.txt`（文本描述页面层级结构）→ 进入步骤 4
- 含"不需要"/"跳过"/"PRD"或任何跳过意图 → 继续步骤 4，codegen 基于 prd-spec + code-scope 生成代码。**创建设计跳过标记**（供 CR 识别）：

  ```bash
  echo '{"reason":"用户选择基于 PRD 描述生成代码","skipped_at":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}' > "openspec/changes/$REQ_NAME/features/$FEAT_ID/.design_skipped"
  ```

**3.3 节点选择（多根节点时）**

读取 `ui_dsl.json`，检查根节点数量：
- 1 个根节点：直接使用全部内容
- 多个根节点：展示列表让用户选择（支持多选和"全部"），然后过滤 `ui_dsl.json` 只保留选中节点，重新生成 `ui_tree.txt`

**3.4 DSL 按 feature 裁剪（bash 脚本，零 LLM token）**

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/feature/slice-dsl-by-scope.sh $FEAT_ID
```

脚本行为（三级匹配策略，逐级 fallback）：
1. **优先**：读取 `feature-plan.json` 的 `design_nodes` 字段（LLM 在规划阶段标注的关联节点名）
2. **Fallback 1**：从本地 `ui_tree.txt` 提取根节点名（`copy-design-assets.sh` 已按 feature 过滤，根节点即相关页面/组件）
3. **Fallback 2**：从 `code-scope.md` 提取 widget 文件名，转 PascalCase 后模糊匹配 DSL 节点
4. **兜底**：无匹配时保留全量 DSL（不破坏流程）

> `design_nodes` 在 Phase 2 feature-plan 中为 best-effort 填写（允许为空）。实际运行时，步骤 3.1 的 `copy-design-assets.sh` 已将关联设计稿复制到功能目录，Fallback 1 从本地 `ui_tree.txt` 根节点自动补偿，无需等待或阻断。

输出：覆写 `features/{feat_id}/ui_dsl.json` + `ui_tree.txt`，仅保留相关子树 + 祖先路径。

> 此步骤可将 DSL 注入量减少 20-60%（取决于页面复杂度和 feature 覆盖范围）。

> **中断恢复**：如果步骤 3 中途会话断开，用户可直接说「执行 dac-ui-spec {feat_id}」补充设计稿，再重新执行 feature-loop {feat_id} 继续。

---

### 步骤 4：代码生成（Per-platform Sub-agent 模式）

**Step 4.0 Platform 识别与文件分组**

从 state.json 读取 `available_platforms`（`jq '.available_platforms // {}'`），然后调用：

```bash
source ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/platform.sh
# 从 code-scope.md 提取文件列表为 JSON 数组
FILES_JSON=$(grep -oE '[^ |]+\.(dart|kt|java|swift|vue|ts)' "$FEAT_DIR/code-scope.md" | jq -R . | jq -s .)
AVAILABLE_PLATFORMS=$(jq -r '.available_platforms // {}' .dac/state.json)
FILE_GROUPS=$(group_files_by_platform "$FILES_JSON" "$AVAILABLE_PLATFORMS")
```

- 单平台（FILE_GROUPS 只有一个 key）→ 退化为单 sub-agent，行为与改造前一致
- 多平台 → per-platform 循环执行 4.1-4.4
- `_unmatched` 组非空 → 使用 AskUserQuestion 询问用户归属

**Step 4.1-4.4 Per-platform 循环**

对 FILE_GROUPS 中每个 platform 组执行：

```
for each platform in FILE_GROUPS (exclude _unmatched):
  4.1 scaffold:  PLATFORM=$platform bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/feature/scaffold-feature.sh $FEAT_ID
  4.2 pre-check: PLATFORM=$platform bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/pre-codegen-check.sh $FEAT_ID
  4.3 codegen:   先 AskUserQuestion 确认（确认执行/全部确认/取消；batch_confirmed 则跳过）
                 → assemble-codegen-prompt.sh 重定向到 .dac/tmp/codegen-prompt-$FEAT_ID.txt
                   （禁止 CODEGEN_PROMPT=$(...) 把全文灌进主会话）
                 → Agent 只引用该文件路径，sub-agent 自行 Read
  4.4 post-check: PLATFORM=$platform bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/post-codegen-check.sh $FEAT_ID
```

每个 sub-agent 的上下文只包含：
- 该 platform 的 rules（`platform/{name}/rules/`）
- 该 platform 对应的文件组（非全量 code-scope）
- 共享的 spec-slice.md / design-slice.md

→ 详见 `references/codegen-flow.md`（前置门禁 → git checkpoint → 组装 prompt + 启动 sub-agent → Layer 2 验证 + 退出码语义）

Layer 2 exit=1 时进入重试流程 → 详见 `references/codegen-retry.md`

---

### 步骤 4.5：测试用例生成与验证（Sub-agent，角色隔离）

→ 详见 `references/test-verify-flow.md`（前置环境检查 → 生成测试用例 → 逻辑/数据类实际执行
`flutter test` / UI/交互类独立 sub-agent 推理判断 → 汇总 `test-report.md` → 失败打回步骤 4 重试，
独立计数器 `test-verify-loop-guard.sh`，上限 3 次，超限则 feature status = `failed`）

---

### 步骤 5：AI CR 校验（Sub-agent 独立执行）

→ 详见 `references/cr-flow.md`（组装 CR prompt + 启动 sub-agent → 约束提取 → verdict 处理 → 修复循环硬限制 2 轮）

---

### 步骤 6：完成收尾

→ 详见 `references/feature-finalize.md`（终态门禁 → 原子状态更新 → 收尾脚本 → 输出摘要 → 返回状态）

## 输出产物（每个功能一个子目录）

```
openspec/changes/{req_name}/features/{feat_id}/
├── code-scope.md            代码改动范围（从 proposal.md 派生）
├── ui_dsl.json              精简后设计稿 JSON（步骤 3 获取，page/component 类型）
├── ui_tree.txt              树形 UI 层级文本（步骤 3 获取）
├── test-cases.md            测试用例判定表 + UI/交互类场景清单（步骤 4.5.1 生成）
├── test-report.md           测试验证报告（步骤 4.5.4 汇总，PASS/FAIL）
└── cr-report.md             CR 校验报告（by dac-code-review）
```
