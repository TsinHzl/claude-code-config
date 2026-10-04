# 状态权威源规则

## 唯一权威源：`.dac/state.json`

以下字段是全局状态的唯一真实来源：

| 字段 | 含义 | 类型 |
|------|------|------|
| `phase` | 当前工作流阶段 | string |
| `current_feature_id` | 正在处理的功能 ID | string \| null |
| `completed_features` | 已完成的功能 ID 列表 | array |
| `skipped_features` | 已跳过/失败的功能 ID 列表 | array |

## 派生源：`feature-plan.json`

`feature-plan.json` 中每个 feature 的 `status` 字段是从 `state.json` **派生**的：

| state.json 条件 | feature-plan.json status |
|----------------|---------------------|
| feat_id 在 `completed_features` 中 | `done` |
| feat_id == `current_feature_id` | `in_progress` |
| feat_id 在 `skipped_features` 中 | `failed` |
| 其他 | `pending` |

## 变更机制

所有状态变更**必须**通过 `scripts/state-update.sh` 执行：

```bash
bash ~/.claude/skills/gd-ai-coding/scripts/state-update.sh <feat_id> <status>
```

该脚本保证：
1. 先更新 `state.json`（权威源）
2. 再同步 `feature-plan.json`（派生源）
3. Lock 文件防止部分更新

## 冲突解决

当两个文件状态不一致时：**state.json 获胜**。

运行以下命令从 state.json 强制同步 feature-plan.json：

```bash
bash ~/.claude/skills/gd-ai-coding/scripts/recovery.sh --reconcile
```

## 进度清单：展示层，非权威状态

运行时的**会话进度清单**（见 [progress-tracking.md](./progress-tracking.md)）只是给使用者看的
**展示层**，**不属于权威状态**：

- 任何 phase 流转、门禁判定、`--resume` 恢复决策**一律读 `.dac/state.json`**，**绝不读进度清单条目状态**
- 进度清单与 state.json 冲突时（如崩溃发生在写 state 与更新条目之间）：**以 state.json 为准**
- 进度清单更新失败（清单工具不可用等）：静默跳过，不阻断流程

## 禁止行为

- 不得直接用 jq/python 修改 feature-plan.json 的 status 字段
- 不得绕过 state-update.sh 直接写 state.json 的 completed_features
- 不得在 SKILL.md 中内联状态更新逻辑（必须调用脚本）
- 不得基于进度清单条目状态做任何流程 / 门禁 / 恢复判定（进度清单仅展示）
