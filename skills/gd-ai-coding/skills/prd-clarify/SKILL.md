---
name: dac-prd-clarify
description: Use when a trimmed PRD (prd-parse.md) has been confirmed but contains ambiguous, missing, or contradictory points that need clarification before generating the structured spec — triggered after prd-parse confirmation (phase=prd-parsed).
user-invocable: false
metadata:
  openclaw:
    emoji: "❓"
---

# dac-prd-clarify — 需求澄清对话

触发方式：由主编排 Read 执行（不可直调）

## When to Use

- prd-parse.md 已确认，但存在模糊描述、缺失边界条件或矛盾逻辑需要与用户逐条确认
- prd-spec 步骤 5 确认后自动调用
- 用户手动触发对已有裁剪文档的需求澄清

## When NOT to Use

- prd-parse.md 尚未生成或未确认（先完成 `/gd-ai-coding` 阶段 1.4）
- 需求文档描述已足够清晰，无模糊/缺失/矛盾点（skill 会自动检测并跳过）

## 职责

通过多轮自然对话，对已确认的 prd-parse.md 中的模糊、缺失、矛盾之处逐条澄清，产出澄清结论供后续 prd-spec.md 生成时引用。

<HARD-GATE>
此 skill 全程为对话式探索，不生成代码、不修改已有产物文件（prd-parse.md 保持不变）。写入动作仅限：更新 .dac/state.json 的 phase 字段、生成 prd-clarify.md 澄清结论文件。
</HARD-GATE>

## 前置条件

- `.dac/state.json` 存在且 `phase = "prd-parsed"`
- `openspec/changes/{req_name}/prd/prd-parse.md` 存在且非空

## 可选输入：设计稿上下文

如果 `openspec/changes/{req_name}/ui/` 目录存在且包含 `ui_tree.txt` 文件，读取所有 `*/ui_tree.txt` 作为辅助分析输入。

设计稿上下文可帮助发现：
- 设计稿中存在但 PRD 未描述的状态/元素（如空状态、加载态、错误态）
- 设计稿交互与 PRD 文字描述不一致之处
- 设计稿中的数值（间距、字号、颜色）与 PRD 规格要求的差异

## 执行步骤

### Step 1：分析文档，提取疑问清单

→ 详见 `references/clarify-rules.md`（🔴🟡🔵 三级识别规则 + 设计稿对比规则 + 提取约束）

---

### Step 2：展示疑问清单概览

向用户展示提取结果：

```
基于需求文档分析，发现以下待澄清项：

🔴 必须澄清（N 项）— 影响功能边界
🟡 建议澄清（M 项）— 影响实现细节  
🔵 可选澄清（K 项）— 优化类

接下来逐条确认，你可以随时说"跳过"跳过当前问题，或说"结束"结束澄清。
```

如果无任何疑问（文档本身足够清晰）：

```
需求文档描述清晰，未发现需要澄清的关键问题。直接继续。
```

→ 跳过后续步骤，直接进入 Step 4 结束。

---

### Step 3：逐条对话澄清

→ 详见 `references/clarify-dialog.md`（对话原则 + 单轮对话格式 + 用户响应处理表 + 循环退出条件）

---

### Step 4：渐进式持久化 + 汇总

→ 详见 `references/clarify-output-template.md`（渐进写入策略 + 结束汇总 + prd-clarify.md 模板 + 状态更新）

---

## 产物说明

- **`openspec/changes/{req_name}/prd/prd-clarify.md`** — 澄清结论持久化文件（会话中断后可恢复）

prd-spec 的 Step 6 生成 prd-spec.md 时读取此文件：

- **已澄清项** → 将结论直接填入对应 §3.x 功能点的描述/交互流程/边界情况
- **待后续确认项** → 写入 prd-spec.md §6 待确认项（保持 `[ ]` 格式）

## 关键原则

- **一次一问** — 不要一次抛出多个问题让用户疲于应对
- **提供选项** — 降低回答成本，A/B/C 比开放问题更容易回答
- **尊重跳过** — 用户说跳过就跳过，不追问为什么
- **不改原文** — prd-parse.md 是原始裁剪文档，保持不变
- **渐进式** — 先确保核心问题（🔴）被回答，再处理细节
- **自然退出** — 用户随时可以结束，不强制走完所有问题
