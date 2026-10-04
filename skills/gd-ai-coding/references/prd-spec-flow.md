# 阶段 1.6：Spec 生成（sub-agent）

`skip_prd_parse=true` 时不要走本节的 Cooper 精裁路径。主编排按 SKILL 1.3：用 DDP / 用户输入生成轻量 `prd-spec.md`；若 **未跳过 MasterGo**，先拉取设计稿，再对照 `ui_tree.txt` / `ui_dsl.json` 与现有代码，不明确的点用 `AskUserQuestion` 向用户确认后回填 spec，再 `--phase prd-speced`。

## 1. 标记 spec 生成启动

供崩溃恢复精确定位：

```bash
<!-- state: prd-specing -->
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/state-update.sh --phase prd-specing
```

## 2. 生成 index.json（如有设计稿）

如果 `openspec/changes/{req_name}/ui/` 存在且包含子目录：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/mastergo/gen-index.sh \
  --ui-dir "openspec/changes/{req_name}/ui"
```

脚本逻辑：遍历 ui/ 下数字子目录，从 `.source_link` 文件读取源链接，检查 `ui_dsl.json` 存在性判定 status（ok/failed/skipped），提取 node_name，输出 `ui/index.json`。

产出结构：

```json
[
  {
    "id": "ds_001",
    "source_link": "<原始链接>",
    "sections": [],
    "features": [],
    "node_name": "<ui_dsl 顶层 name，否则 nodes[0].name，再否则 ui_tree 第一行>",
    "dir": "001",
    "status": "ok|failed|skipped",
    "mapping": "pending"
  }
]
```

无设计稿时跳过此步骤。

## 3. spawn 子代理生成 prd-spec.md

使用 Agent 工具 spawn 子代理生成 prd-spec.md，避免主会话加载 PRD 全文。

**标准路径**（存在 `openspec/changes/{req_name}/prd/prd-extract.json` 且 `dac-prd-mode=standard`）：

读取 `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/prompts/prd-spec-from-extract.md` 作为 Agent prompt（输入 extract + 图 + `ui/index.json`，**不要**再喂精裁散文，**不要**为填满模板去编 UI 状态）。

**旧路径 Agent prompt：**

```
基于以下文件，按 ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/templates/tpl-prd-spec.md 模板生成结构化需求文档：
- openspec/changes/{req_name}/prd/prd-parse.md
- openspec/changes/{req_name}/prd/prd-clarify.md（如存在）
- openspec/changes/{req_name}/ui/index.json（如存在）

生成规则：
- 类型判断："新增/新功能/新建" → 新增；"优化/调整/修改" → 修改；"复用/沿用/保持不变" → 复用
- 结构完整：所有字段均需输出，无实质内容时填"无"
- UI 状态：每个功能点须明确加载中/空态/错误态
- 待确认项自动生成：TBD/待定内容、无交互流程的功能、未定义数值等
- 设计稿关联：如 index.json 存在，根据 id 和 node_name 关联填写功能清单的设计稿列（格式：ds_xxx（节点名称））

写入 openspec/changes/{req_name}/prd/prd-spec.md。
完成后回复"生成完成"即可，无需输出其他内容。
```

## 4. 用户确认

等待 agent 完成后告知用户 spec 已生成：

```
结构化需求文档已生成：openspec/changes/{req_name}/prd/prd-spec.md

请查看后确认：
1. 确认，继续
2. 需要调整（请说明）
```

- 选项 2：根据用户反馈由主 LLM 直接 Edit 修改 prd-spec.md（无需重新 spawn sub-agent），修改后重新展示确认选项

## 5. 状态更新

确认后：

```bash
<!-- state: prd-speced -->
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/state-update.sh --phase prd-speced
```

## 6. 章节映射（如有 index.json）

如果 `index.json` 存在且 `mapping` 为 `"pending"`：
- Read `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/skills/ui-spec/SKILL.md` 并按其内容执行（参数：`--map-sections "openspec/changes/{req_name}/ui"`），不使用 Skill 工具调用
