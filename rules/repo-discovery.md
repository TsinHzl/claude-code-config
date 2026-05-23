---
name: Repo Discovery
description: Read real project files before proposing commands; never invent paths or commands
inclusion: always
---

- Read real project files before proposing commands
- Prefer existing scripts in `package.json`, `Makefile`, `Taskfile.yml`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `turbo.json`, `nx.json`, `justfile`
- Never invent commands, paths, flags, URLs, or service names
- Verify any remembered file, command, or workflow against current repo before recommending
