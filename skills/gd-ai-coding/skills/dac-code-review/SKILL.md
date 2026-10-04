---
name: dac-code-review
description: Use when the user asks for code review / 代码审查 / review / 审查代码 on the current repo. Extracts diff from a single repo (by commit hash, time range, commit count, or component path), runs deep multi-dimension scanning, and returns a structured Chinese report directly in the conversation.
version: 2.1.0
allowed-tools: Read, Bash, Edit, Agent
user-invocable: false
---

# 单仓库 Code Review

## 输入参数

`$ARGUMENTS` 支持四种模式（优先级：commit hash > 时间范围 > commit 数量 > 源分支全量）：

- 组件路径：`@组件名/`
- commit hash：7-40 位十六进制（diff 该 commit 到 HEAD 的累积变更）
- commit 数量：自然语言数字（如"最近两次commit"→2，取最近 N 次 first-parent 提交的累积 diff）
- 时间范围：自然语言时间描述（如"今天内的提交"、"最近三天"）

### 四参数提取规则

| 参数 | 提取方式 |
|---|---|
| `PARAM` | `@组件名/` 格式，无则留空 |
| `COMMIT_COUNT_RAW` | 自然语言数字，如"最近两次"→`2`，无则留空 |
| `COMMIT_HASH_RAW` | 7-40 位十六进制，无则留空 |
| `DATE_SINCE` | 见下方时间范围解析规则；无时间范围时传空字符串 `""` |

### 时间范围解析规则（DATE_SINCE）

| 用户输入示例 | 传入 DATE_SINCE |
|---|---|
| 今天内 / 今天的提交 | `midnight` |
| 最近 N 天 / 近 N 天 | `N days ago` |
| 最近一周 / 最近两周 | `1 week ago` / `2 weeks ago` |
| 最近两小时 / 最近一小时 | `2 hours ago` / `1 hour ago` |

**数字转换：** 中文数字须先转为阿拉伯数字（"三" → 3，"两" → 2，"一" → 1），再拼接时间单位。

**Fallback：** 若用户输入无法映射到以上格式（如"上周五之后"、"本月初"），**立即停止**，向用户提出澄清问题："请确认时间范围，例如：今天内、最近 3 天、1 周前至今。"不得猜测。

## Workflow

### Step 1: 环境解析与 Diff 提取

按上述规则提取四参数后，**单次 Bash 调用**：

```bash
bash "${DAC_SKILL_HOME:?}/skills/dac-code-review/scripts/code-review-single-env.sh" "<PARAM>" "<COMMIT_COUNT_RAW>" "<COMMIT_HASH_RAW>" "<DATE_SINCE>"
```

### Step 2: 深度审查与输出报告

- Step 1 输出含 `BLOCK:` → 简述阻断原因结束
- 否则 Read [references/role-mapping.md](references/role-mapping.md)，SHARDS==1 时读取 header
  `LANGUAGES` 字段，取文件数最多的扩展名映射出本次审查角色
- 再读取 header `SHARDS` 字段决定分支：
  - **SHARDS == 1** → 顺序流程：
    1. 声明"本次以 <角色> 视角执行审查"，Read [references/review-rules.md](references/review-rules.md) 计算变更统计 + 执行六维扫描
    2. Read [references/report-template.md](references/report-template.md) 套模板
    3. 直接在对话中完整展示报告内容
  - **SHARDS > 1** → Read [references/workflow-sharded.md](references/workflow-sharded.md) 执行并行流程（角色改由该流程按各 shard 的 `SHARD_<i>_LANGUAGES` 字段独立判定）

## Constraints

- 强制中文输出
- 仅报告 diff 中明确存在的问题
- 同类别内按文件名字母序、行号升序
- 每个独立代码位置对应一条意见，不合并、不拆分
- **空类别整段省略**（含标题与计数），不输出"本次未发现此类问题"占位句
- 时间范围模式下，变更概述需注明 merge/cherry-pick 非线性历史的 diff 边界限制
- 报告输出：完整 Markdown 报告内容直接在对话中展示，不写入本地文件
