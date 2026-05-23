---
name: Task Execution Protocol
description: TaskCreate/TaskUpdate workflow for multi-step tasks, planning, and architecture analysis
inclusion: always
---

For multi-file features, architecture analysis, brainstorming, or any task with 3+ steps:

1. Use `TaskCreate` to build a structured progress tree — no plain-text plans in chat
2. Break into atomic verifiable units; validate (tests/lint/manual check) before marking complete
3. Use `TaskUpdate` as each step completes
4. Use plan mode for architectural decisions; ask clarifying questions upfront
5. Delete temporary plan files (`PLAN.md`, `TODO.md`) after task completion
