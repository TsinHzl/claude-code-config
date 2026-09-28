---
paths:
  - "**/*.swift"
  - "**/Package.swift"
---
# Swift 钩子（Hooks）

> 本文件使用 Swift 特定内容扩展了 [common/hooks.md](../common/hooks.md)。

## 工具使用后钩子（PostToolUse Hooks）

在 `~/.claude/settings.json` 中配置：

- **SwiftFormat**：编辑后自动格式化 `.swift` 文件
- **SwiftLint**：编辑 `.swift` 文件后运行 lint 检查
- **swift build**：编辑后对修改后的包（Packages）进行类型检查

## 警告（Warning）

标记 `print()` 语句 —— 生产环境代码应改用 `os.Logger` 或结构化日志（Structured Logging）。
