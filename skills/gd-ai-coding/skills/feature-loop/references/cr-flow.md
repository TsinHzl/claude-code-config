# 步骤 5：AI CR 校验（Sub-agent 独立执行）

> 使用 Sub-agent 的原因是**角色隔离**（审查者不应看到实现过程和重试历史），而非上下文管理。参见 subagent_design.md §10.3。
>
> **状态写入边界**：CR sub-agent **仅写入** `cr-report.md`（唯一产物）。`knowledge/extract-constraints.sh`、`audit-log.sh`、`state-update.sh` 均在 sub-agent 返回后由主会话执行。**唯一例外**：极小变更分支用户选择「跳过 CR」时不启动 sub-agent，由主会话直接写入 `cr-report.md`（仅含 skipped 标记，不含 🔴/🟡 问题项）。参见 DESIGN.md §七（补）。

## 启动前置检查

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/pre-skill-check.sh code-review $FEAT_ID
```

## 极小变更分支（< 10 行净改动时询问是否 CR）

前置检查通过后，统计 codegen 实际净改动行数：

```bash
CODEGEN_BASE=$(jq -r '.base_commit // empty' "openspec/changes/$REQ_NAME/features/$FEAT_ID/.codegen_checkpoint" 2>/dev/null)
CODEGEN_BASE="${CODEGEN_BASE:-HEAD~1}"

CHANGED_FILES=()
while IFS= read -r _f; do
  [[ -n "$_f" && "$_f" != *.md ]] && CHANGED_FILES+=("$_f")
done < <(git diff --name-only "$CODEGEN_BASE" 2>/dev/null)

if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
  NET_LINES=0
else
  STAT_OUTPUT=$(git diff --shortstat "$CODEGEN_BASE" -- "${CHANGED_FILES[@]}" 2>/dev/null)
  INS=$(echo "$STAT_OUTPUT" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)
  DEL=$(echo "$STAT_OUTPUT" | grep -oE '[0-9]+ deletion'  | grep -oE '[0-9]+' || echo 0)
  NET_LINES=$(( ${INS:-0} + ${DEL:-0} ))
fi
```

> 净改动行数 = 新增行 + 删除行（绝对值之和），排除纯文档文件（`.md`）不计入。

**若 NET_LINES < 10：** 使用 `AskUserQuestion` 主动询问用户：

```
改动文件：{code-scope.md 中列出的文件}
净增/改行数：{NET_LINES} 行
摘要：{feat_name} codegen 产物

选项：
  ◉ 跳过 CR（推荐，改动量小）
  ○ 仍然执行 CR
```

处理结果：
- 选择「跳过 CR」→ 直接进入步骤 6，**不启动 sub-agent**，`cr-report.md` 写入一行说明：`verdict: skipped（净改动 < 10 行，用户选择跳过）`，并上报跳过：
  ```bash
  bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/report-cr-verdict.sh $FEAT_ID || true
  ```
- 选择「仍然执行 CR」→ 继续执行下方 5.1

**若 NET_LINES ≥ 10：** 跳过询问，直接进入 5.1（强制 CR）。

## 5.1 组装 Prompt + 启动 Sub-agent

> CR prompt 采用与 codegen 相同的 ZONE A/B/C 分层策略，确保跨 feature 的前缀缓存命中。
> - ZONE A（静态）：角色声明 + cr-checklist.md 完整内容
> - ZONE B（半静态）：constraints.snapshot.md + error-patterns.snapshot.md
> - ZONE C（动态）：spec-slice + code-scope + 设计稿 + 实际代码文件

```bash
# 组装 CR prompt（bash 脚本，零 LLM token）
CR_PROMPT=$(bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/feature/assemble-cr-prompt.sh $FEAT_ID)
```

> **subagent_type 强制约束：** 必须显式指定 `agentType: "general-purpose"`，不得使用默认映射的 `code-reviewer`
> （其工具集为 Read/Grep/Glob/Bash，缺少 `Write` 工具，会导致 sub-agent 无法完成本步骤"仅写入 cr-report.md"的产物职责）。
> **前台执行强制约束：** sub-agent 调用必须显式设置 `run_in_background: false`。与 Claude Code 默认行为一致（该参数默认即为 `false`，SDK 不依赖外部全局规则文件；Claude Code 的全局规则同样要求前台执行）。显式声明仅为防止后续 skill 作者在快速复制模板时遗漏默认参数。CR 报告必须等 sub-agent 返回后才能进入 5.3 Verdict 处理。
> **取数约束边界：** 禁止 git 命令 / 禁止全仓检索 / 改动文件 Read 上限 3 个 / 总工具调用 ≤ 8 次
> 这四条已由 `assemble-cr-prompt.sh` 注入 ZONE A 稳定前缀，主 agent **不得**在调用时额外放宽或重述。
> 实测依据：无此约束时该 sub-agent 中位 490s（工具调用 20 次 / bash 15.5 次），而 prompt 已内联全部代码。

Claude Code 使用 `Agent` 工具启动独立 CR sub-agent；Codex 必须按 `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/references/codex-agent-orchestration.md` 启动 `code-reviewer`，门禁失败、角色输出 `BLOCKED` 或 CR 报告缺失时终止，禁止主会话审查替代。两种运行时均禁止传入 codegen 实现过程、重试历史或任何实现者视角描述：

```
Agent({
  description: "CR: {feat_name}",
  prompt: "$CR_PROMPT",
  agentType: "general-purpose",
  run_in_background: false
})
```

> **缓存说明**：同一轮次内多个 feature 的 CR，ZONE A+B 部分完全一致 → API 前缀缓存命中，token 成本降低。

## 5.2 约束提取

sub-agent 完成后，主 agent 执行约束提取：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/knowledge/extract-constraints.sh $FEAT_ID
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/report-cr-verdict.sh $FEAT_ID || true
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/audit-log.sh $FEAT_ID "STEP:DONE" "code-review"
```

## 5.3 Verdict 处理

根据 sub-agent 返回的 `verdict` 处理：

| verdict | 含义 | 本步骤动作 |
|---------|------|----------|
| `clean` | CR 全部通过，无任何问题 | 直接进入步骤 6 |
| `with_issues` | 有 🔴 严重 或 🟡 一般问题 | 展示发现摘要，由用户逐条选择修复项 |

如果返回 `with_issues`：

（`cr_issue_found` 已在 5.2 由 `report-cr-verdict.sh` 根据 cr-report.md 上报，此处不要再报、不要手填 🔴/🟡 数量。）

1. 在对话中输出发现摘要表格（按 🔴 严重 / 🟡 一般 / 🔵 建议 分组，每条含文件:行号 + 一句描述）
2. 使用 `AskUserQuestion`（**multiSelect: true**）列出所有发现条目，让用户勾选要修复的条目：
   - 选项格式：`[🔴/🟡/🔵] 文件:行号 — 问题描述`
   - 附加选项：`全选 🔴 严重`（推荐）、`跳过所有修复`
   - **互斥规则**：`全选 🔴 严重` 或 `跳过所有修复` 与单条 issue 互斥，选中附加项时忽略单条勾选
3. 仅修复用户选中的条目，其余记录为 known issue，不做任何修改

**修复路径：**
- 有选中修复项：执行修复，重新启动 CR sub-agent 验证
- 选择「跳过所有修复」：记录到 cr-report.md known issues，直接进入步骤 6

## 5.4 修复循环硬限制

CR→修复→重新 CR 最多执行 **2 轮**。超过 2 轮后：

- 向用户展示剩余未解决的问题列表
- 询问：手动修复 / 忽略并继续
- 记录到 audit-log：`audit-log.sh $FEAT_ID "CR_FIX:LIMIT" "2 rounds exhausted, N issues remaining"`
