---
name: Hooks System
description: Hook types (Pre/PostToolUse, Stop), auto-accept permissions, TodoWrite best practices
inclusion: auto
---

# 钩子系统（Hooks System）

## 钩子类型（Hook Types）

- **PreToolUse**：工具执行前（校验、参数修改）
- **PostToolUse**：工具执行后（自动格式化、检查）
- **Stop**：当会话（Session）结束时（最终验证）

## 自动接受权限（Auto-Accept Permissions）

谨慎使用：
- 为受信任且定义明确的任务计划启用
- 在探索性工作中禁用
- 严禁使用 `dangerously-skip-permissions` 标志
- 应改为在 `~/.claude.json` 中配置 `allowedTools`

## TodoWrite 最佳实践

使用 `TodoWrite` 工具：
- 跟踪多步骤任务的进度
- 验证对指令的理解程度
- 实现实时引导
- 展示细粒度的实现步骤

待办列表（Todo list）可揭示：
- 步骤顺序混乱
- 遗漏项
- 多余的非必要项
- 粒度错误
- 误解需求
