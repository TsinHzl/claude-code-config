---
paths:
  - "**/*.py"
  - "**/*.pyi"
---
# Python 钩子（Hooks）

> 本文件在 [common/hooks.md](../common/hooks.md) 的基础上扩展了 Python 特定的内容。

## 工具调用后钩子（PostToolUse Hooks）

在 `~/.claude/settings.json` 中配置：

- **black/ruff**: 编辑后自动格式化 `.py` 文件
- **mypy/pyright**: 编辑 `.py` 文件后运行类型检查（Type Checking）

## 警告（Warnings）

- 对已编辑文件中的 `print()` 语句发出警告（建议改用 `logging` 模块）
