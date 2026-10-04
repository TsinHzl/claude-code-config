# 阶段 3：功能开发（串行执行）

读取 `openspec/changes/{req_name}/feature-plan.json`，按依赖拓扑排序确定执行顺序。

## 3.1 拓扑排序

根据各功能的 `dependencies` 字段构建有向无环图（DAG），执行拓扑排序，确定串行执行顺序：

- 无依赖的功能优先
- 有依赖的功能在其依赖完成后执行
- 同层无依赖关系的功能按数组顺序执行（feature-plan.json 数组顺序即执行顺序）

展示执行计划（`skipped` 标「无开发，不出码」，计入 N 但不进 loop）：

```
执行计划（共 N 个功能，串行执行）：

1. shared_network 网络层（无依赖）
2. shared_utils 工具类（无依赖）
3. login_page 登录模块（依赖 shared_network）
4. home_page 首页模块（依赖 shared_network）
5. order_detail 订单详情（依赖 login_page + home_page）
```

## 3.2 依次执行

**恢复逻辑**：遍历功能列表前，先检查每个功能的完成态：
- **单人模式**（无 `collab.json`）：读 `feature-plan.json[].status`
  - `"done"` → 跳过；`"skipped"` → 跳过（规划时无开发，或失败级联）；**不**进入 feature-loop 流程
  - `"in_progress"` → 视为上次中断，重新执行（feature-loop 幂等）；`"pending"` → 正常执行
  - 进入阶段 3 前：`scripts/feature/sync-skipped-from-plan.sh` 必须已把 plan 里的 skipped id 写入 `state.json.skipped_features`（feature-plan 确认时调用）。若没有 `pending`（全是无开发），执行 `state-update.sh --phase feature-done` 后走 3.4，不要空转 loop。
- **协作模式**（有 `collab.json`）：`feature-plan.json[].status` 停留在规划时的 `pending`（跨人权威已落到 `status.json`，`state-update.sh` 不再写 plan 的 status 以避免 git 冲突）；改从 `state.json.completed_features` / `skipped_features` 与 `openspec/changes/{req}/features/{id}/status.json` 判定
  - id ∈ `completed_features` 或 `status.json.status ∈ {done, done_with_issues}` → 跳过
  - `state.json.current_feature_id == id` 或 `status.json.status == "in_progress"` 且 `claimed_by == 当前用户` → 视为中断恢复
  - 其余 → 正常执行；跨人已 done 但本机未 pull 时依赖 `guard.sh` 的 `[DAC-DEP-003]` 兜底

### 协作模式过滤（`openspec/changes/{req_name}/collab.json` 存在时启用）

在把 pending feature 交给 feature-loop 流程之前，MUST 追加两道过滤：

1. **assignee 过滤**：`feature.assignee` 非空且 `!=` 当前 `git config user.email` → 跳过（**不**标 skipped/failed，只是不进本会话队列）。
2. **guard 校验**：对候选 feature 执行 `bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/collab/guard.sh {feat_id}`。exit 非 0 → 跳过；错误码：
   - `[DAC-STATE-020]` assignee 不匹配（通常已被步骤 1 过滤，此处兜底）
   - `[DAC-STATE-021]` 他人 in_progress
   - `[DAC-DEP-003]` 依赖未 done（等待对方 pull）
   - `[DAC-PLAN-006]` 与他人 in_progress 的 feature 有文件交集

**无可运行 feature 的展示**：若本轮无 feature 通过过滤，但仍有 pending：

```
🔗 协作等待：暂无可跑的 feature

你的 pending feature：
  - order-detail  等待依赖 home-page（by bob@…）完成后 git pull

请对方完成并提交 status.json；本会话可结束，稍后 git pull 后再触发 /gd-ai-coding。
```

**当前用户已完成本人所有指派**（assignee=self 的 feature 全部 done）：

```
✅ 你的部分已完成
   完成清单：{已完成 feature 列表}
   剩余归属他人：{他人 pending feature + assignee}

本机 phase 保持 feature-loop（不流转 feature-done）；对方合入后可再次 /gd-ai-coding 继续。
```

本人份额 token 汇总已由 `state-update.sh` 在「assignee=self 全部 done 且未全量 done」时自动触发一次（幂等标记 `state.json.collab_token_summary_at`），不需要 LLM 再手工调用；本机 phase 保持 `feature-loop`。

### 单人模式（无 collab.json）

行为与改造前一致：按拓扑序取第一个 `status=pending` 直接执行，不做 assignee/guard 过滤。

对每个待执行功能，Read `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/skills/feature-loop/SKILL.md` 并按其内容执行该功能（传入功能 ID），不使用 Skill 工具调用。

每个功能**开始前**，展示进度：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[{当前序号}/{总数}] 开始：{feat_name}
类型：{type} | 预估文件数：{new_files + modified_files 数}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

每个功能完成后：
1. 更新 `feature-plan.json` 中该功能的 `status: "done"`
2. 展示单功能完成摘要（changed_files + summary）
3. 执行 context compression（`/compact`）回收本轮中间推理 token，为下一个功能腾出上下文空间。如 compact 后 context 仍超限，提示用户需要新会话继续（当前进度已持久化到 state.json）

## 3.3 异常处理

| 结果 | 动作 |
|------|------|
| `clean` | 继续下一个功能 |
| `with_issues` | 展示问题列表，询问用户（见下方处理流） |
| 失败 | 级联跳过依赖链，询问用户是否继续（见下方处理流） |

### `with_issues` 处理流

**CR 事件已由 `report-cr-verdict.sh` 根据 `cr-report.md` 上报（feature-loop 步骤 5.2），进入此分支不要再报一遍。**

展示 CR 报告中的问题列表，询问用户：

```
功能「{name}」CR 报告中有以下问题：
{问题列表摘要}

请选择：
1. 自动修复（status 重置为 `pending` 后重新 Read 执行 feature-loop/SKILL.md，传入 feat_id）
2. 手动修复（修改代码后输入「继续」恢复）
3. 忽略，继续下一个功能（问题将在最终摘要中标注）
```

- 选项 1：将该功能 status 重置为 `pending`，重新 Read 执行 feature-loop/SKILL.md（传入 feat_id）
- 选项 2：等待用户输入"继续"后，重新 Read 执行 feature-loop/SKILL.md（传入 feat_id，feature-loop 幂等）
- 选项 3：标记该功能为 `done_with_issues`（记录到 state.json 的 `issues_features` 列表），继续下一个功能

### 失败处理流（级联跳过）

当某功能失败时：

1. 记录该功能到 `skipped_features`
2. **级联识别**：遍历 feature-plan.json，找出所有直接或间接依赖该功能的下游功能
3. 展示受影响列表：

```
⚠️ 功能「{name}」执行失败。
以下功能依赖它，将被自动跳过：
  - {downstream_1}（直接依赖）
  - {downstream_2}（间接依赖，经 {downstream_1}）

剩余可执行功能（无依赖关系）：
  - {independent_1}
  - {independent_2}

是否继续执行剩余功能？
1. 继续（跳过所有受影响功能）
2. 终止整个流程
```

- 选项 1：将所有受影响功能标记为 `skipped`（reason: "依赖 {failed_id} 失败"），继续执行无依赖关系的剩余功能
- 选项 2：终止流程，当前进度已保存

## 3.4 全部完成

所有功能执行完毕后，展示整体完成摘要：

```
开发完成摘要：

✅ 已完成（{done_count}）：
  {功能列表 + 各自 summary}

⚠️ 有遗留问题（{issues_count}）：
  {功能列表 + CR 报告路径}

❌ 已跳过（{skipped_count}）：
  {功能列表 + 跳过原因}

生成文件清单：
  {全部新增/修改的文件}

提示：执行 `git diff` 查看变更
```

## 3.5 用户确认 + Archive

> 此时 state.json 的 phase 已被 `state-update.sh` 自动设为 `feature-done`（表示所有功能开发完成，但 openspec 尚未归档）。

向用户请求最终确认：

```
所有功能已开发完成，请验证代码逻辑后确认：
1. 确认无误，归档本次变更（推荐）
2. 需要调整（请说明问题）
3. 暂不归档，稍后手动执行 /opsx:archive
```

- 选项 1：使用 Skill 工具调用 `/opsx:archive`，归档本次 change，然后更新状态：

  ```bash
  # feature-done → done：归档完成，标记为终态
  bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/state-update.sh --phase done
  ```

- 选项 2：等待用户修改完成后重新确认，再执行 archive
- 选项 3：phase 保持 `feature-done`，不执行 archive。下次启动 `/gd-ai-coding` 时会再次提醒归档。

> `feature-done` 表示"功能开发完成但未归档"，`done` 表示"已归档的终态"。未归档不影响代码可用性，但下次启动时会提醒用户处理。
