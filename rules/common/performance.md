---
name: Performance Optimization
description: Model selection strategy, context window management, extended thinking
inclusion: auto
---

# 性能优化 (Performance Optimization)

## 模型选择策略 (Model Selection Strategy)

**Haiku 4.5** (轻量、低成本、低延迟)：
- 需要频繁调用的轻量级智能体 (Lightweight agents)
- 结对编程与代码生成
- 多智能体系统中的工作智能体 (Worker agents)

**Sonnet 4.6** (主力编程模型)：
- 主要开发工作
- 编排多智能体工作流 (Orchestrating multi-agent workflows)
- 复杂的编程任务

**Opus 4.7 / 4.8** (最深层的推理能力，最新一代)：
- 复杂的架构决策与系统设计
- 极高推理要求的任务（多步规划、复杂调试）
- 研究与分析任务

**Fable 5** (Anthropic 最新非编程模型)：
- 创意写作、内容生成、对话场景
- 非代码相关的开放式生成任务

## 上下文窗口管理 (Context Window Management)

在上下文窗口（Context Window）剩余最后 20% 时，应避免执行：
- 大规模重构 (Large-scale refactoring)
- 跨越多个文件的功能实现
- 复杂交互的调试 (Debugging complex interactions)

低上下文敏感度任务（可在此阶段执行）：
- 单文件编辑
- 独立实用工具创建
- 文档更新
- 简单的错误修复 (Bug fixes)

## 深度思考 (Extended Thinking) + 计划模式 (Plan Mode)

深度思考（Extended Thinking）默认启用，为内部推理预留最高 31,999 个 Token。

控制深度思考的方式：
- **快捷键切换 (Toggle)**：Option+T (macOS) / Alt+T (Windows/Linux)
- **配置文件 (Config)**：在 `~/.claude/settings.json` 中设置 `alwaysThinkingEnabled`
- **预算上限 (Budget cap)**：`export MAX_THINKING_TOKENS=10000`
- **详细模式 (Verbose mode)**：Ctrl+O 查看思考过程输出

对于需要深层推理的复杂任务：
1. 确保已启用深度思考（默认开启）
2. 启用 **计划模式 (Plan Mode)** 以采取结构化方法
3. 进行多轮批判性评审 (Critique rounds) 以确保全面分析
4. 使用角色拆分的子智能体 (Sub-agents) 以获得多元视角

## 构建故障排除 (Build Troubleshooting)

如果构建（Build）失败：
1. 使用 **build-error-resolver** 智能体
2. 分析错误信息
3. 逐步进行修复
4. 每次修复后进行验证
