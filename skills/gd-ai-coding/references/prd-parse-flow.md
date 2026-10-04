# 阶段 1.4：PRD LLM 处理

Task A（`ingest-prd.sh`）完成后执行以下步骤。标准路径下载 Cooper 时用 `pre-trim.sh --skip-trim`，**不会**先按关键词裁表。

**标准路径：** 若 `$PRD_TMP/dac-prd-mode`（或 `openspec/changes/{req_name}/prd/dac-prd-mode`）为 `standard`：

1. 拷贝 `prd-extract.json`、`dac-prd-mode`、摘要（`trimmed-prd.md` → `prd-parse.md` 仅作留痕）到 `openspec/changes/{req_name}/prd/`。若 `$PRD_TMP/assets` 非空，一并拷到 `prd/assets/`。
2. **不要** spawn 精裁 sub-agent，不要按 `prd-trim.md` 删段落。
3. 向用户展示摘要中的功能点列表（无开发 / 缺名 / 无效 UI 链）。确认后 `--phase prd-parsed`，进入 1.5 标准分叉。
4. 用户要改抽出结果：说明哪一行/列写错了（表本身的问题），不要在对话里补一篇散文需求。

以下步骤仅 **legacy**（未识别需求列表 7 列、已 fallback 到 pre-trim）。

**前置：** 从 Task A 的 stdout 中提取 `PRD_TMP=<路径>`，后续以 `$_PRD_TMP` 代指该临时目录。

## 0. Task A 失败处理

检查 Task A 的 exit code 和输出文件：

- 成功（exit 0 且 `$_PRD_TMP/trimmed-prd.md` 存在且非空）→ 继续步骤 1
- 失败 → 展示脚本 stderr 输出，提示用户：
  ```
  PRD 下载/裁剪失败：{stderr 摘要}
  1. 重试
  2. 手动提供文档路径（本地 markdown 文件）
  ```
  - 选项 1：重新执行 Task A
  - 选项 2：用户提供路径后，将该文件内容作为 trimmed-prd.md 使用，继续步骤 1

## 1. 拼接 prd-parse.md

将 trimmed-prd.md 复制为工作文件（header 由 sub-agent 在精裁时补充）：

```bash
PRD_PARSE="openspec/changes/{req_name}/prd/prd-parse.md"
cp "$_PRD_TMP/trimmed-prd.md" "$PRD_PARSE"
```

## 2. LLM 语义精裁（sub-agent）

使用 Agent 工具 spawn 一个子代理执行精裁，避免 Edit 痕迹污染主会话上下文。

**Agent prompt：**

```
对 openspec/changes/{req_name}/prd/prd-parse.md 执行两步操作：

1. 在文件最顶部插入 header（读取文档第一个一级标题作为标题）：
   # {文档第一个一级标题}
   
   > 原始文档地址：https://cooper.didichuxing.com/knowledge/{spaceId}/{resourceId}
   > 提取范围：{关键词} 相关内容
   > 提取时间：{当天日期 YYYY-MM-DD}
   
   ---

2. 按 ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/prompts/prd-trim.md 中的规则做纯删除式语义精裁。
   硬性约束：只用 Edit 工具删除段落/行，禁止改写任何保留文案，禁止调整章节顺序或结构。裁剪后的文档结构必须是原文的子集。

完成后回复"精裁完成"即可，无需汇报删除明细。
```

等待 agent 完成后直接进入用户确认。

## 3. 用户确认

```
语义精裁已完成：openspec/changes/{req_name}/prd/prd-parse.md

裁剪内容是否完整准确？
1. 确认，继续
2. 需要调整（请说明）
3. 跳过预裁剪，使用原始文档继续
```

- 选项 2：修改后重新展示
- 选项 3：用 `$_PRD_TMP/raw-prd.md` 内容重新执行 LLM 语义精裁（重新 spawn agent）

## 4. 状态更新

确认后：

```bash
<!-- state: prd-parsed -->
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/state-update.sh --phase prd-parsed
```
