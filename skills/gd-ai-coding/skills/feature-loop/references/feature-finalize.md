# 步骤 6：完成收尾

## 终态门禁（全量产物验证）

标记 done 前，执行：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/state-transition-check.sh $FEAT_ID
```

**门禁失败处理**：向用户展示缺失的产物或不满足的条件，询问：
- 自动补全缺失产物（重新执行对应步骤）
- 手动处理后告知继续
- 强制标记完成（需说明原因，记录到 audit-log）

## 1. 原子状态更新（state.json + feature-plan.json 一致性保证）

```bash
<!-- state: feature $FEAT_ID → done -->
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/state-update.sh $FEAT_ID done
```

## 2. 收尾脚本

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/audit-log.sh $FEAT_ID "STATUS:DONE" "$FEAT_ID completed"

# 如果是最后一个 feature，清理 knowledge snapshot。
# 判定改用 state.json.completed_features + skipped_features（单人/协作模式统一权威）：
#   - 单人：feature-plan.json.status 也会同步，但 state.json 是 state-update.sh 的第一手写入
#   - 协作：state-update.sh 显式跳过写 feature-plan.json.status（避免跨人 git 冲突），
#           原来用 feature-plan.status==pending 计数会导致 REMAINING 恒 > 0，snapshot 永远不清理
REQ_NAME=$(jq -r '.req_name // empty' .dac/state.json)
PLAN_FILE="openspec/changes/$REQ_NAME/feature-plan.json"
REMAINING=$(jq --slurpfile state .dac/state.json '
  ((if type == "array" then . else .features end) | [.[].id]) as $all
  | ($all | length) - ((($state[0].completed_features // []) + ($state[0].skipped_features // [])) | unique | length)
' "$PLAN_FILE" 2>/dev/null || echo "0")
if [[ "$REMAINING" == "0" ]]; then
  bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/knowledge/snapshot-knowledge.sh --clean
fi
```

## 3. 输出当前功能完成摘要

```
✅ 功能完成：{name}

生成文件：
  {新增/修改的文件列表}

CR 报告：openspec/changes/{req_name}/features/{feat_id}/cr-report.md
```

## 3.5. 协作模式提示（如启用）

**触发条件：** `openspec/changes/{req_name}/collab.json` 存在。

**必须** 提示用户提交 `status.json` 与代码，否则协作者的 `guard.sh` 仍会判定依赖未完成：

```
🔗 协作提示：feature 已完成，请提交跨人产物让对方看到

需 git add / commit 的路径：
  openspec/changes/{req_name}/features/{feat_id}/status.json
  （以及本次代码变更）

对方 git pull 后即可跑依赖此 feature 的下游 feature；系统不自动 commit。
```

`status.json` 由 `state-update.sh` 在 collab.json 存在时自动同步，无需手工写。

## 4. 向主 skill 返回本次功能完成状态

- `clean`：代码生成 + CR 全部通过，无任何问题 → 主 skill 自动进入下一个功能
- `with_issues`：CR 有问题或流程中用户手动暂停过 → 主 skill 询问用户是否继续
