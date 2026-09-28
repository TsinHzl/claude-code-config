---
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
---
# Go 钩子（Go Hooks）

> 本文件在 [common/hooks.md](../common/hooks.md) 的基础上扩展了 Go 特定的内容。

## 工具使用后钩子（PostToolUse Hooks）

在 `~/.claude/settings.json` 中进行配置：

- **gofmt/goimports**：在编辑后自动格式化 `.go` 文件
- **go vet**：在编辑 `.go` 文件后运行静态分析
- **staticcheck**：在修改后的包上运行扩展静态检查
