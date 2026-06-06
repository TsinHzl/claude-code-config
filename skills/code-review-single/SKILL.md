---
name: code-review-single
description: 单仓库 Code Review 专家。对当前仓库/分支的代码变更执行深度审查，输出结构化报告。触发关键词：code review、代码审查、审查代码、review、代码质量检查。支持指定 commit hash、commit 数量、时间范围、组件路径四种模式。
---

# 单仓库 Code Review

## 输入参数

`$ARGUMENTS` 支持四种模式（优先级：commit hash > 时间范围 > commit 数量 > 源分支全量）：
- 组件路径：`@组件名/`
- commit hash：7-40 位十六进制
- commit 数量：自然语言数字（如"最近两次commit"→2）【⚠️ 暂未实现，传入时静默忽略，等效于源分支全量】
- 时间范围：自然语言时间描述（如"今天内的提交"、"最近三天"）

## Workflow

### Step 1: 环境解析与 Diff 提取

从 `$ARGUMENTS` 提取四参数后，**单次 Bash 调用**执行：

```bash
bash "${HOME}/.claude/skills/code-review-single/scripts/code-review-single-env.sh" "<PARAM>" "<COMMIT_COUNT_RAW>" "<COMMIT_HASH_RAW>" "<DATE_SINCE>"
```

**参数提取规则：**

| 参数 | 提取方式 |
|---|---|
| `PARAM` | `@组件名/` 格式，无则留空 |
| `COMMIT_COUNT_RAW` | 自然语言数字，如"最近两次"→`2`；暂未实现，留空 |
| `COMMIT_HASH_RAW` | 7-40 位十六进制；暂未实现，留空 |
| `DATE_SINCE` | 见下方时间范围解析规则；无时间范围时传空字符串 `""` |

**时间范围解析规则（DATE_SINCE）：**

| 用户输入示例 | 传入 DATE_SINCE |
|---|---|
| 今天内 / 今天的提交 | `midnight` |
| 最近 N 天 / 近 N 天 | `N days ago`（如"最近三天" → `3 days ago`） |
| 最近一周 / 最近两周 | `1 week ago` / `2 weeks ago` |
| 最近两小时 / 最近一小时 | `2 hours ago` / `1 hour ago` |

**数字转换：** 中文数字须先转为阿拉伯数字（"三" → 3，"两" → 2，"一" → 1），再拼接时间单位。

**Fallback（无法映射时必须执行）：** 若用户输入无法映射到以上格式（如"上周五之后"、"本月初"），**立即停止**，向用户提出澄清问题："请确认时间范围，例如：今天内、最近 3 天、1 周前至今。"不得猜测或将模糊值传入脚本。

### Step 2: 深度审查与输出报告

若 Step 1 输出含 `BLOCK:` → 向用户简述阻断原因，结束。

否则逐文件（字母序）、逐 `+` 行变更，按以下 6 项顺序扫描：
1. 安全漏洞（OWASP Top 10）
2. 崩溃与异常（零容忍：空指针、越界、未捕获异常、死锁、栈溢出等）
3. 逻辑错误与边界遗漏
4. 性能问题
5. 代码规范与可读性
6. 重构机会

**分类规则**：
- 🚫 严重问题：崩溃/安全漏洞/数据损坏/构建失败（第 1、2 项一律归此类）
- ⚠️ 改进建议：第 3、4、5 项发现
- 💡 优雅重构：第 6 项发现

**输出**：调用 Write 工具写入 `<工作目录>/<TARGET_COMPONENT>-code-review.md`，报告模板见 [references/report-template.md](references/report-template.md)。

## Constraints

- 强制中文输出
- 仅报告 diff 中明确存在的问题
- 略过自动生成文件（package-lock.json 等）
- 同类别内按文件名字母序、行号升序排列
- 每个独立代码位置对应一条意见，不合并、不拆分
- **时间范围模式限制：** 在含 merge commit 或 cherry-pick 的非线性历史仓库中，diff 结果为"最老 in-range commit 的父节点到 HEAD 的累积变更"，可能包含少量时间范围外的提交内容。若报告使用了时间范围模式，在变更概述中注明此限制。
