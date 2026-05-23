---
name: File Writing Strategy
description: Incremental write strategy for large files to avoid write failures
inclusion: always
---

Large files (>500 lines / >50KB): always use incremental writes:
1. Initial Write with skeleton/structure only
2. Follow with Edit/append operations for content blocks
3. Never attempt single-pass writes for large documents

If Write tool fails, immediately switch to incremental strategy without asking.
Applies to ALL file types: code, Markdown, config, generated documents.
