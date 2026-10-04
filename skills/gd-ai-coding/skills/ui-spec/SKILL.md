---
name: dac-ui-spec
description: Use when a MasterGo design link is available and needs to be fetched as structured DSL — triggered during feature-loop (step 3) or manually to fetch/refresh design data.
argument-hint: "<feature_id> [MasterGo链接] [--out-dir <目录>]"
user-invocable: false
metadata:
  openclaw:
    emoji: "🎨"
    requires:
      bins: [mcporter]
      mcpServers: [mastergo-proxy]
---

# dac-ui-spec — 设计稿获取

触发方式：由主编排 Read 执行（不可直调），参数 `<feature_id> [链接]`  
映射模式：参数 `--map-sections <ui目录>`

## When to Use

- feature-loop 步骤 3.2：用户选择"提供设计稿链接"时调用（单链接模式）
- 主编排同步点：`--map-sections` 补充设计稿→章节映射关系
- 用户手动调用：补充/重新获取某功能的设计稿（中断恢复、链接更换）

## When NOT to Use

- 无 MasterGo 设计稿（用户选择基于 PRD 描述生成代码时跳过）
- 设计稿已获取且无需刷新（skill 内置幂等检查会自动跳过）
- 批量获取多个设计稿（主编排阶段 1.3 已通过前台 bash 处理，脚本内部自动并发下载）

## 职责

获取 MasterGo 设计稿 DSL 并生成精简后的 `ui_dsl.json` + `ui_tree.txt`，作为单链接设计稿获取的入口。

## 参数

| 参数 | 说明 |
|------|------|
| `feature_id` | 功能 ID，决定默认输出路径 `openspec/changes/{req_name}/features/{feat_id}/` |
| `链接` | MasterGo 链接（可选，未传则询问用户） |
| `--out-dir <目录>` | 可选，覆盖默认输出目录 |
| `--map-sections <目录>` | 章节映射模式：补充 index.json 中的 sections 字段 |

## 前置条件

- `.dac/state.json` 存在且包含 `req_name`
- 输出目录的父目录存在

## 执行步骤

### 步骤 1：确定输出目录

- 传入 `--out-dir`：使用指定目录
- 未传入：使用 `openspec/changes/{req_name}/features/{feat_id}/`

### 步骤 2：获取链接

- 已传入链接 → 直接使用
- 否则使用 `AskUserQuestion` 询问（**禁止**改用纯文本等待输入）：
  ```json
  {
    "questions": [{
      "question": "请提供 MasterGo 设计稿链接（shortLink 或完整链接均可）：",
      "header": "设计稿链接"
    }]
  }
  ```
  收到 `is_error=true` 后**静默等待**用户消息（见 `rules/plugin-interaction.md`）：
  - 含链接 → 继续步骤 3
  - 明确表示无设计稿 → 结束，无产物输出

### 步骤 3：获取 DSL（幂等）

检查 `{out_dir}/ui_dsl.json` 是否已存在：

- **已存在且用户未要求重新获取**：跳过网络请求，直接完成
- **不存在或用户要求重新获取**：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/mastergo/get-dsl.sh --out-dir "{out_dir}" "<链接>"
```

脚本内置超时重试（2 次）、D2C 优先 + DSL 回退、噪音过滤，产物：
```
{out_dir}/
├── ui_dsl.json          精简后 JSON（颜色/字体已内联解析）
└── ui_tree.txt          树形 UI 层级（带布局/属性标注）
```

失败时使用 `AskUserQuestion` 提供降级选项（**禁止**改用纯文本列出选项后等待输入）：
```json
{
  "questions": [{
    "question": "设计稿获取失败，如何处理？",
    "header": "设计稿失败",
    "options": [
      { "label": "重试" },
      { "label": "提供截图路径", "description": "通过视觉解析生成 UI 描述" },
      { "label": "手动描述页面结构", "description": "请在下一条消息中描述" },
      { "label": "跳过" }
    ]
  }]
}
```
收到 `is_error=true` 后**静默等待**用户消息（见 `rules/plugin-interaction.md`），通过语义理解判断意图后执行对应分支。

### 步骤 4：完成

输出摘要（含节点信息，供上游写入 index.json）：

```
✅ ui-spec 完成
产物：{out_dir}/ui_dsl.json + ui_tree.txt
```

## 输出产物

```
{out_dir}/
├── ui_dsl.json          精简后 JSON（颜色/字体已内联，噪音已过滤）
└── ui_tree.txt          树形 UI 层级文本
```

---

## 章节映射模式（`--map-sections`）

触发：Read 执行本 SKILL.md，参数 `--map-sections "openspec/changes/{req_name}/ui"`

→ 详见 `references/map-sections-mode.md`（前置条件 + M-1 加载数据 / M-2 确认映射 / M-3 更新 index.json）
