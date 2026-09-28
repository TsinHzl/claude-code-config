---
name: Development Workflow
description: Feature implementation pipeline — research, plan, TDD, code review, commit
inclusion: auto
---

# 开发工作流（Development Workflow）

> 本文件是对 [common/git-workflow.md](./git-workflow.md) 的扩展，涵盖了在执行 Git 操作之前进行的完整功能开发流程。

功能实现工作流（Feature Implementation Workflow）描述了开发流水线：调研（Research）、规划（Planning）、测试驱动开发（TDD）、代码审查（Code Review），最后提交至 Git。

## 功能实现工作流（Feature Implementation Workflow）

0. **调研与复用（Research & Reuse）** _（在开始任何新实现之前必须执行）_
   - **首先进行 GitHub 代码搜索：** 在编写任何新内容之前，运行 `gh search repos` 和 `gh search code` 来查找现有的实现、模板和模式。
   - **检查软件包注册表（Registries）：** 在编写工具代码之前，搜索 npm、PyPI、crates.io 和其他注册表。优先选择经过实战检验的库，而非手写方案。
   - **搜索可适配的实现：** 寻找能解决 80% 以上问题、且可以被 Fork、移植（Ported）或封装（Wrapped）的开源项目。
   - 当能够满足需求时，优先考虑采用或移植已验证的方法，而非编写全新的代码。

1. **规划先行（Plan First）**
   - 使用 **planner** 智能体（Agent）创建实现计划。
   - 在编码前生成规划文档：PRD、architecture、system_design、tech_doc、task_list。
   - 识别依赖项和风险。
   - 拆分为多个阶段（Phases）。

2. **测试驱动开发（TDD）方法**
   - 使用 **tdd-guide** 智能体（Agent）。
   - 先写测试（RED）。
   - 实现代码以通过测试（GREEN）。
   - 重构（IMPROVE）。
   - 验证 80% 以上的覆盖率。

3. **代码审查（Code Review）**
   - 编写完代码后立即使用 **code-reviewer** 智能体（Agent）。
   - 解决 CRITICAL（严重）和 HIGH（高）级别的问题。
   - 尽可能修复 MEDIUM（中）级别的问题。

4. **提交与推送（Commit & Push）**
   - 编写详细的提交信息。
   - 遵循约定式提交（Conventional Commits）格式。
   - 有关提交信息格式和 PR 流程，请参阅 [git-workflow.md](./git-workflow.md)。
