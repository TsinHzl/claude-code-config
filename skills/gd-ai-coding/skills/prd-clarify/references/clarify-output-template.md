# Step 4：渐进式持久化 + 汇总（输出模板）

## 渐进写入（防中断丢失）

在对话过程中，每回答完 3 个问题（或用户触发结束），立即将当前已收集的结论追加写入 `openspec/changes/{req_name}/prd/prd-clarify.md`。写入时覆盖整个文件（非追加），内容为截至当前的完整结论表。

这样即使会话中断，已回答的内容也已持久化。重新执行 prd-clarify 时，如果 `prd-clarify.md` 已存在且非空，提示用户：

```
检测到已有澄清记录（N 项已澄清，M 项待确认）。
1. 继续未完成的澄清（跳过已回答问题）
2. 重新开始
```

## 结束汇总

所有对话结束后，最终写入完整结论并展示汇总：

```
需求澄清完成，结论汇总：

✅ 已澄清（N 项）：
  1. [问题摘要] → [结论]
  2. [问题摘要] → [结论]
  ...

⏭️ 跳过/待后续确认（M 项）：
  1. [问题摘要]
  2. [问题摘要]
  ...

以上结论将在生成结构化需求文档时自动引用。继续？
```

用户确认后继续；若用户明确拒绝（说"不行"、"重来"、"有问题"等），先上报拒绝事件再重新回到 Step 3：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/report-user-gate.sh \
  clarify rejected \
  --msg '<用户的原始发言，原文>' \
  --reason '<AI一句话总结：为什么被拒绝>' || true
```

「接受」不要在这里报：用户确认后执行 `state-update.sh --phase prd-clarified`，Harness 会打 `prd_clarify_accepted`。

## 写入 prd-clarify.md（最终版）

```markdown
# 需求澄清结论

> 澄清时间：{当前日期}
> 基于文档：openspec/changes/{req_name}/prd/prd-parse.md

## 已澄清

| # | 关联章节 | 问题 | 结论 |
|---|---------|------|------|
| 1 | §x.x 章节名 | 问题摘要 | 澄清结论 |
| 2 | ... | ... | ... |

## 待后续确认

| # | 关联章节 | 问题 | 原因 |
|---|---------|------|------|
| 1 | §x.x 章节名 | 问题摘要 | 用户跳过/不确定 |
```

## 更新状态

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/state-update.sh --phase prd-clarified
```
