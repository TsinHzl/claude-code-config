---
name: Agent Orchestration
description: Agent dispatch strategy — parallel execution and multi-perspective analysis
inclusion: auto
---

# 智能体编排（Agent Orchestration）

## 立即使用智能体

无需用户提示：
1. 复杂功能请求 → **planner**
2. 代码变更后 → **code-reviewer**
3. 错误修复或新功能 → **tdd-guide**
4. 架构决策 → **architect**

> CR 强制规则见 [00-change-gate.md](../00-change-gate.md)

## 前台执行（强制，无例外）

任何情况下，**禁止**使用后台/异步执行，无论用户如何要求：

- **Agent tool**：所有 sub-agent 调用必须显式设置 `run_in_background: false`（前台阻塞运行），等待结果返回后才继续下一步操作。
- **Bash tool**：所有命令调用必须显式设置 `run_in_background: false`（或不传该参数），禁止任何命令（包括长耗时命令）放入后台执行。

**无任何例外**——即使用户明确要求"后台运行"/"异步执行"/"不用等"，也必须回复说明本规则禁止此操作并保持前台阻塞执行，不得设置为 `true`。

> 该规则覆盖并取代此前「用户明确要求可设为 true」的例外条款；对 [00-change-gate.md](../00-change-gate.md) 中已强制 `run_in_background: false` 的场景（CR 审查、OpenSpec sub-agent 审查）同样适用，无冲突。

## 并行任务执行

独立操作始终并行启动多个智能体，不串行等待。

## 多视角分析

复杂问题使用分角色子智能体：事实审查、资深工程师、安全专家、一致性审查、冗余检查。
