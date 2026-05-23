# claude-code-config

> **注：** 本文档由 **claude-sonnet-4-6** 模型自动生成。

A modular Claude Code configuration for mobile/cross-platform developers. Provides behavior rules, workflow gates, and platform-specific coding standards via `~/.claude/CLAUDE.md` and `~/.claude/rules/`.

## What's Included

### Global Rules (`inclusion: always`)

| File | Purpose |
|------|---------|
| `rules/code-change-gate.md` | Confirmation gate before any file mutation + post-change review |
| `rules/task-execution.md` | TaskCreate/TaskUpdate workflow for multi-step tasks |
| `rules/document-generation.md` | Auto-insert model ID header in generated Markdown |
| `rules/git-workflow.md` | Conventional commits, branch naming, dangerous op gates |
| `rules/repo-discovery.md` | Never invent commands/paths; read real project files first |
| `rules/file-writing.md` | Incremental writes for large files (>500 lines / >50KB) |

### Platform Rules (auto-loaded by file type)

| File | Trigger | Purpose |
|------|---------|---------|
| `rules/flutter-dart.md` | `*.dart` | Dart style, BLoC/Riverpod, Flutter specifics |
| `rules/ios-swift.md` | `*.swift` | Swift style, MVVM/Coordinator, SwiftUI vs UIKit |
| `rules/ios-objc.md` | `*.m`, `*.h`, `*.mm` | ObjC style, ARC, Swift interop |
| `rules/mobile-general.md` | always | Battery, network, storage, security, release rules |

## Installation

### Quick Install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/claude-code-config/main/install.sh | bash
```

### Manual Install

```bash
git clone https://github.com/YOUR_USERNAME/claude-code-config.git
cd claude-code-config
./install.sh
```

### What the installer does

1. Backs up your existing `~/.claude/CLAUDE.md` (if present)
2. Copies `CLAUDE.md` to `~/.claude/CLAUDE.md`
3. Copies all `rules/*.md` to `~/.claude/rules/`
4. Skips files you already have (use `--force` to overwrite)

## Setup After Install

Edit `~/.claude/CLAUDE.md` and replace the Developer Profile placeholder with your own:

```markdown
## Developer Profile

**[Your Role & Expertise]**
- [Primary tech stack and platforms]
- [Architecture patterns you use]
```

## Customization

**Keep only what you need.** If you don't write Flutter, skip `flutter-dart.md`. If you don't write ObjC, skip `ios-objc.md`.

**Override per-project.** Create a `CLAUDE.md` at your project root to add project-specific context. It takes precedence over the global config.

**Add your own rules.** Drop any `.md` file into `~/.claude/rules/` with frontmatter:

```markdown
---
name: My Rule
description: What this rule does
inclusion: always   # or: auto (with fileMatchPattern)
---

Your rule content here.
```

## Enforcement Model

| Mechanism | Enforcement | Used for |
|-----------|-------------|---------|
| `settings.json` deny | 100% — model can't see blocked tools | Dangerous git commands |
| `PreToolUse` hooks | 100% — shell-level block | File size detection |
| `rules/` + `CLAUDE.md` | ~95% — advisory | Behavior, workflow, style |

Rules files are **advisory**, not deterministic. For true enforcement, use hooks in `~/.claude/settings.json`.

## File Structure

```
claude-code-config/
├── CLAUDE.md                    # Global config template
├── install.sh                   # Installer
├── README.md
└── rules/
    ├── code-change-gate.md
    ├── task-execution.md
    ├── document-generation.md
    ├── git-workflow.md
    ├── repo-discovery.md
    ├── file-writing.md
    ├── flutter-dart.md
    ├── ios-swift.md
    ├── ios-objc.md
    └── mobile-general.md
```

## License

MIT
