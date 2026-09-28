---
name: Git Workflow
description: Commit message format (conventional commits), PR workflow
inclusion: always
---

# Git 工作流

## 提交信息格式
```
<type>: <description>

<optional body>
```

类型: feat, fix, refactor, docs, test, chore, perf, ci

注意：归属信息已通过 `~/.claude/settings.json` 全局禁用。

## PR 工作流

创建 PR 时：
1. 分析完整提交历史（不仅是最近一次提交）
2. 使用 `git diff [base-branch]...HEAD` 查看所有变更
3. 撰写全面的 PR 摘要
4. 包含带有 TODO 的测试计划
5. 新分支推送时使用 `-u` 标志

> 完整开发流程见 [development-workflow.md](./development-workflow.md)。
