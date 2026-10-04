# 步骤 4：展示功能列表并确认（输出格式）

以表格形式展示拆分结果：

```
功能拆分结果（共 N 个，从 tasks.md + proposal.md 分组）

No. | ID              | 名称           | 类型      | 新增文件 | 修改文件 | 依赖
----|-----------------|---------------|-----------|---------|---------|------
1   | shared-network  | 网络层/数据模型 | service   | 5       | 1       | -
2   | login-page      | 登录模块       | page      | 4       | 2       | shared-network
3   | home-page       | 首页模块       | page      | 6       | 1       | shared-network
...

执行顺序：shared-network → login-page → home-page → ...
```

> 设计稿关联关系已回填至 `index.json`，feature-loop 步骤 3 直接从 index.json 查询。

使用 `AskUserQuestion` 询问（**禁止**改用纯文本列出选项后等待输入）：

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

收到 `is_error=true` 后**静默等待**用户消息（见 `rules/plugin-interaction.md`），通过语义理解判断意图：
- 含"确认"/"开始"/"一人开发" → 进入一人开发（Phase 3 全量串行）
- 含"多人"/"协作"/"分给"/"两个人一起" → 进入**多人协作分叉**（见下方）
- 含调整/合并/拆分/增删意图 → 按用户说明修改后重新展示，直到确认

---

## 多人协作分叉（选择"确认，进入多人协作"后执行）

严格顺序（禁止调换）：**A 展示分层 → B 收集协作者 → C 建议指派 → D 落盘并暂停**。理由：`guard.sh` 以 `openspec/changes/{req}/collab.json` 存在判定协作模式；反过来先写 `assignee` 后写 `collab.json` 会踩「有 assignee 但 guard 当单人处理」的窗口期。

### A. 展示分层（只读分析）

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/collab/plan-split.sh
```

把 JSON 里的 `layers` / `overlaps` / `chain_depth` / `overlap_ratio` / `recommendation` / `reason` 一起展示给用户。`recommendation == serial_only` 或 `fix_plan` 时直接把 `reason` 原文当作劝退依据（阈值来自 `thresholds`：`chain_depth_serial=4`、`overlap_ratio_fix=0.5`），但**允许用户坚持**继续多人。

### B. 收集协作者 email

先展示发起人（当前 `git config user.email`，即 `initiated_by`），再用 `AskUserQuestion`：

```json
{
  "questions": [{
    "question": "规划发起人 initiated_by = <当前 email>。除你以外还有谁一起做？（填写对方 git user.email，与看板 committer 一致）",
    "header": "协作者",
    "options": [
      { "label": "只有我自己", "description": "取消多人协作，改走一人开发" },
      { "label": "Other", "description": "输入一个或多个 email（逗号或换行分隔）" }
    ]
  }]
}
```

- 若选"只有我自己"→ 回到一人开发路径，不写 collab.json。
- Other 输入的每个 token MUST 含 `@`；无 `@` 则重问。

候选邮箱集合 = `{initiated_by} ∪ 用户输入`。

### C. 按层建议指派

规则（LLM 只展示不擅改）：

| 规则 | 建议 |
|------|------|
| Layer 0 | 全部默认 `initiated_by`，说明"须先做完并合入" |
| 有文件交叉的一组 | 整组建议给同一个人 |
| 其余同层、无交叉 | 在候选邮箱间轮询分摊 |
| 下游 Layer | 建议给消费它的人 |

用表格展示，AskUserQuestion "按建议写入" / "我来改（Other：每行 `feature-id email`）"。发起人 git email 为空时 Layer 0 不得默认，必须手填。

### D. 落盘并暂停（严格顺序）

1. **先写 collab.json**（`openspec/changes/{req_name}/collab.json`）：
   ```json
   {"mode":"multi","initiated_by":"<发起人 email>","ddp_id":"<state.json.ddp_id 或空>"}
   ```

2. **再对每个 feature 调 assign.sh**：
   ```bash
   bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/collab/assign.sh --feat <feat_id> --to <email>
   ```

3. `state-update.sh --phase feature-planned` 照常执行。

   > 不再写 `state.json.collab_mode`：所有读侧（guard.sh / state-update.sh / recovery.sh / extract-constraints.sh / snapshot-knowledge.sh）都以 `openspec/changes/{req}/collab.json` 存在为准。

4. 用 `AskUserQuestion` 展示**交接卡片**（必须弹，禁止只打字后 end-of-turn）：

   ```
   已进入多人协作，不会自动跑完全部功能。

   请先提交规划（人 B 才能 git pull 后加入）：
     git add openspec/changes/{req_name}/
     git commit   # 含 feature-plan.json / collab.json，不要提交 .dac/

   建议分支布局（各自独立分支 + 一条集成分支）：
     origin/feat/{req_name}          规划/集成分支
       ├── feat/{req_name}-alice     人 A 工作分支（Layer 0 + 指派给 A）
       └── feat/{req_name}-bob       人 B 从集成分支拉出（join 后做指派给 B）

   交接：
     人 A <email>  先做 Layer 0
       执行 feature-loop <Layer 0 feat_id>
     人 B <email>  等 Layer 0 合入后
       1. git pull（同步集成分支）
       2. /gd-ai-coding → 选「加入该需求」
       3. 执行 feature-loop <指派给自己的 feat_id>

   选项：
   ```

   ```json
   {
     "questions": [{
       "question": "接下来如何处理？",
       "header": "协作暂停",
       "options": [
         { "label": "本会话继续做我的可跑功能", "description": "只启动 assignee=当前 email 且 guard.sh 为 0 的 feature（通常是 Layer 0）" },
         { "label": "结束会话，我先去提交规划", "description": "本会话不再执行 feature-loop；进度已在 collab.json / assignee 中" }
       ]
     }]
   }
   ```

   - 「本会话继续」→ Read `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/references/feature-orchestration.md` 并走其 Phase 3 协作模式过滤（3.2 章节）。
   - 「结束会话」→ 停在此处；下次 `/gd-ai-coding` 走"继续上次"或人 B 走"加入"。

**Skill 禁止**自动 `git add` / `git commit`。
