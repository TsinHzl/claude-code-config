# 阶段 1.5：需求澄清

`skip_prd_parse=true` 时**不要**用 `prd-parse.md` 走本节 Cooper 澄清。若同时 `skip_mastergo=false` 且已有 `ui_tree.txt` / `ui_dsl.json`，改走 SKILL 1.3 第 3 步：对照 MasterGo 与现有代码，仅将不明确项用 `AskUserQuestion` 确认，结论写入 `prd-clarify.md` 并回填轻量 `prd-spec.md`。

**标准路径（`dac-prd-mode=standard`）：** 不走下方 Cooper 长清单。可写空的 `prd-clarify.md`，`--phase prd-clarified`，小澄清放到 1.6（`prompts/prd-spec-from-extract.md`）。

`skip_prd_parse=false` 且 **legacy** 时走下方完整流程。

## 1. Task B 完成检查（如有）

如有 Task B，Task B 已在阶段 1.3 前台执行完成，直接检查其产物。

## 2. Task B 结果处理（如有）

Task B 完成后，检查各链接下载状态（目录中是否存在 `ui_dsl.json`）。

- **部分失败：** 展示失败链接及降级选项（重试/截图/跳过）
  - 用户选择"跳过"时：`touch "openspec/changes/{req_name}/ui/{dir}/.skipped"`
- **全部失败：** 告知用户"设计稿全部获取失败，将仅基于 PRD 文本进行需求澄清"，继续步骤 3

## 3. 生成问题清单（sub-agent）

步骤 2 的降级选项全部处理完毕后，使用 Agent 工具 spawn 子代理，避免主会话加载 prd-parse.md。

**Agent prompt：**

```
按 ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/skills/prd-clarify/SKILL.md 中 Step 1 的识别规则，分析以下文件：
- openspec/changes/{req_name}/prd/prd-parse.md
- openspec/changes/{req_name}/ui/*/ui_tree.txt（如存在）

输出结构化问题清单，格式：
---
🔴 必须澄清（N 项）
🟡 建议澄清（M 项）
🔵 可选澄清（K 项）

## 问题列表

### [🔴] Q1: {问题}
📍 相关段落：「{摘录≤2行}」
选项：A. {选项1} / B. {选项2} / C. 其他

### [🟡] Q2: {问题}
...
---

每个问题必须包含足够上下文（摘录相关段落），使用户无需翻阅原文即可理解并回答。
只输出问题清单，不做其他操作。
```

如果 sub-agent 返回"文档描述清晰，无需澄清"→ 跳过步骤 4，直接进入步骤 5。

## 4. 主会话逐条对话澄清

基于 sub-agent 返回的问题清单，按 `skills/prd-clarify/SKILL.md` 中 Step 3 的对话原则逐条向用户确认：

- 一次一问，优先级排序（🔴 → 🟡 → 🔵）
- 提供选项降低回答成本
- 用户可随时"跳过"或"结束"
- 每 3 个问题渐进写入 `prd-clarify.md`（防中断丢失）

**循环退出条件（任一满足）：**

- 用户明确说结束
- 所有问题已遍历完
- 🔴 全部已回答/跳过，且用户对 🟡 连续跳过 3 个或跳过超过 50%

## 5. 最终持久化 + 状态更新

将步骤 4 中尚未写入的剩余 Q&A flush 到 `openspec/changes/{req_name}/prd/prd-clarify.md`，并在文件顶部补充汇总 header（格式见 `skills/prd-clarify/SKILL.md` Step 4）。

若用户对最终 prd-clarify.md 不满意并要求重新生成，**立即上报事件**（接受由随后的 `--phase prd-clarified` 自动报，这里只报拒绝）：
```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/report-user-gate.sh \
  clarify rejected \
  --msg '<用户的原始发言，原文>' \
  --reason '<一句话原因>' || true
```

然后：

```bash
<!-- state: prd-clarified -->
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/state-update.sh --phase prd-clarified
```
