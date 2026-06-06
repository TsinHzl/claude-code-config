---
name: Code Change Gate
description: Mandatory confirmation gate before any file mutation, plus post-change review
inclusion: always
---

ALL file mutations require explicit user confirmation before execution. Use `AskUserQuestion` tool with up/down arrow selection to present confirmation prompts — never plain-text prompts like "回复 Y 执行".

- **Multi-file / complex changes**: numbered plan → wait for confirmation → full diff → wait for confirmation → execute
- **Single-file / simple changes**: full diff → wait for confirmation → execute

Never infer consent from silence or context. Never call Write, Edit, or any file-mutation tool without explicit confirmation.

After every change:
1. Code Review: logic errors, security vulnerabilities, performance issues, edge cases
2. Standards Audit: style consistency, naming conventions, existing project patterns
Report findings; propose fixes for any issues found.

## Uncertainty Gate

Before ANY action (not just file mutations): if the requirement, scope, or approach is ambiguous, stop and ask a single focused question. Never guess, assume, or proceed with a "best effort" interpretation.
