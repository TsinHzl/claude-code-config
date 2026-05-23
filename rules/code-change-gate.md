---
name: Code Change Gate
description: Mandatory confirmation gate before any file mutation, plus post-change review
inclusion: always
---

ALL file mutations require explicit user confirmation before execution:

- **Multi-file / complex changes**: numbered plan → wait for confirmation → full diff → wait for confirmation → execute
- **Single-file / simple changes**: full diff → wait for confirmation → execute

Accepted confirmations: "ok", "yes", "go", "confirmed", "proceed", "do it", "好的", "确认", "可以", "执行", or equivalent affirmative in any language.

Never infer consent from silence or context. Never call Write, Edit, or any file-mutation tool without explicit confirmation.

After every change:
1. Code Review: logic errors, security vulnerabilities, performance issues, edge cases
2. Standards Audit: style consistency, naming conventions, existing project patterns
Report findings; propose fixes for any issues found.
