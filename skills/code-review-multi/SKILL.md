---
name: code-review-multi
description: 批量多仓库 Code Review 专家。自动扫描当前目录下所有含 .git 的子仓库，批量执行深度审查并输出统一报告。触发关键词：批量 review、多仓库、批量审查、所有仓库、批量代码检查。
---

# 批量多仓库 Code Review

## 输入参数

无需参数，自动扫描当前目录下所有含 .git 的子目录。

## Workflow

### Step 1: 批量扫描与 Diff 提取

**单次 Bash 调用**执行：

```bash
bash "${HOME}/.claude/skills/code-review-multi/scripts/code-review-multi-env.sh"
```

### Step 2: 深度审查与批量生成报告

若仅含 `SKIP` 日志无有效 `REPOSITORY` 改动 → 回复"所有仓库均无有效改动"，结束。

否则对每个有效仓库，逐文件（字母序）、逐 `+` 行变更，按以下 6 项扫描：
1. 安全漏洞（OWASP Top 10）
2. 崩溃与异常（零容忍）
3. 逻辑错误与边界遗漏
4. 性能问题
5. 代码规范与可读性
6. 重构机会

**分类规则**：
- 🚫 严重问题：崩溃/安全漏洞/数据损坏/构建失败（第 1、2 项一律归此类）
- ⚠️ 改进建议：第 3、4、5 项发现
- 💡 优雅重构：第 6 项发现

**输出**：调用 Write 工具，在根目录写入 `[ROOT_DIRECTORY_NAME]_code_review.md`（全部仓库汇总单文件）。报告模板见 [references/report-template.md](references/report-template.md)。

## Constraints

- 强制中文输出
- 所有仓库汇总至同一个 Markdown 文件
- 仅报告 diff 中明确存在的问题
- 略过自动生成文件
- SKIP 仓库不在正文出现，仅在末尾汇总体现
- 每个独立代码位置对应一条意见，不合并、不拆分
