---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
---
# TypeScript/JavaScript 钩子 (Hooks)

> 本文件扩展了 [common/hooks.md](../common/hooks.md)，增加了 TypeScript/JavaScript 特有的内容。

## 工具调用后钩子 (PostToolUse Hooks)

在 `~/.claude/settings.json` 中配置：

- **Prettier**: 编辑后自动格式化 JS/TS 文件
- **TypeScript 检查**: 编辑 `.ts`/`.tsx` 文件后运行 `tsc`
- **console.log 警告**: 对已编辑文件中的 `console.log` 发出警告

## 停止钩子 (Stop Hooks)

- **console.log 审计**: 在会话结束前检查所有已修改文件中的 `console.log`
