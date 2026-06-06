# claude-code-config

A modular Claude Code configuration for mobile/cross-platform developers. Provides behavior rules, workflow gates, platform-specific coding standards, curated skills, slash commands, hook scripts, and harness settings via `~/.claude/`.

## What's Included

### `settings.json`

Pre-configured Claude Code harness settings:

- **Permissions**: allow/deny rules (e.g., block `git push --force`, `rm -rf *`)
- **Hooks**: PreToolUse file-size detection, session lifecycle notifications, UserPromptSubmit constraint injection
- **Plugins**: 16+ enabled plugins (superpowers, code-review, figma, frontend-design, document-skills, GitHub, playwright, LSPs, etc.)
- **MCP servers**: code-review MCP server
- **StatusLine**: custom shell-powered status bar

### Global Rules (`inclusion: always`)

| File | Purpose |
|------|---------|
| `rules/code-change-gate.md` | Confirmation gate before any file mutation + post-change review |
| `rules/task-execution.md` | TaskCreate/TaskUpdate workflow for multi-step tasks |
| `rules/document-generation.md` | Auto-insert model ID header in generated Markdown |
| `rules/git-workflow.md` | Conventional commits, branch naming, dangerous op gates |
| `rules/repo-discovery.md` | Never invent commands/paths; read real project files first |
| `rules/file-writing.md` | Incremental writes for large files (>500 lines / >50KB) |
| `rules/openspec.md` | OpenSpec spec-driven development (5-phase gate workflow) |

### Platform Rules (auto-loaded by file type)

| File | Trigger | Purpose |
|------|---------|---------|
| `rules/flutter-dart.md` | `*.dart` | Dart style, BLoC/Riverpod, Flutter specifics |
| `rules/ios-swift.md` | `*.swift` | Swift style, MVVM/Coordinator, SwiftUI vs UIKit |
| `rules/ios-objc.md` | `*.m`, `*.h`, `*.mm` | ObjC style, ARC, Swift interop |
| `rules/mobile-general.md` | always | Battery, network, storage, security, release rules |

### Skills (84 curated skills)

Pre-installed to `~/.claude/skills/`:

| Category | Count | Highlights |
|----------|-------|------------|
| Superpowers | 14 | brainstorming, TDD, systematic debugging, code review, git worktrees, parallel agents |
| Flutter | 22 | state management (BLoC/Riverpod), navigation, testing, platform channels, forms, animations, accessibility |
| Figma | 8 | design generation, code connect, diagrams, design systems, FigJam, slides |
| Document | 17 | pptx, docx, xlsx, pdf, frontend-design, MCP builder, theme factory, brand guidelines |
| Code Analysis | 5 | multi/single code review, architecture analysis, diff pulse, GD component analyzer |
| Other | 18 | AI video, notebooklm, text2mermaid, PPT generation, offline Turing, skill creator, OpenSpec init |

### Commands

Pre-installed slash commands to `~/.claude/commands/`:

| File | Command | Purpose |
|------|---------|---------|
| `commands/code-arch-master-analyzer.md` | `/code-arch-master-analyzer` | Deep architecture analysis |
| `commands/code-diff-pulse.md` | `/code-diff-pulse` | Generate diff-based pulse reports |

### Scripts

Hook/statusline scripts installed to `~/.claude/`:

| File | Purpose |
|------|---------|
| `scripts/global_constraints_hook.sh` | UserPromptSubmit hook — injects global constraints (CLAUDE.md + rules) |
| `scripts/statusline-command.sh` | Custom shell-powered status bar display |

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
3. Copies `settings.json` to `~/.claude/settings.json`
4. Copies all `rules/*.md` to `~/.claude/rules/`
5. Copies all `skills/*/` to `~/.claude/skills/`
6. Copies all `commands/*.md` to `~/.claude/commands/`
7. Copies `scripts/*.sh` to `~/.claude/` (with `chmod +x`)
8. Skips files you already have (use `--force` to overwrite)

## Setup After Install

Edit `~/.claude/CLAUDE.md` and replace the Developer Profile placeholder with your own:

```markdown
## Developer Profile

**[Your Role & Expertise]**
- [Primary tech stack and platforms]
- [Architecture patterns you use]
```

Review `~/.claude/settings.json` and update:

- **Hook command paths** — replace `/Users/MacBook/...` paths with your own
- **StatusLine command** — point to your own statusline script
- **enabledPlugins** — disable any plugins you don't need

## Customization

**Keep only what you need.** If you don't write Flutter, skip `flutter-dart.md`. If you don't write ObjC, skip `ios-objc.md`. Delete unwanted skills from `~/.claude/skills/` and commands from `~/.claude/commands/`.

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
├── settings.json                # Harness settings (permissions, hooks, plugins, MCP)
├── install.sh                   # Installer
├── README.md                    # English docs
├── README.zh.md                 # Chinese docs
├── .gitignore
├── commands/                    # Slash command definitions
│   ├── code-arch-master-analyzer.md
│   └── code-diff-pulse.md
├── rules/                       # Behavior & workflow rules
│   ├── code-change-gate.md
│   ├── task-execution.md
│   ├── document-generation.md
│   ├── git-workflow.md
│   ├── repo-discovery.md
│   ├── file-writing.md
│   ├── openspec.md
│   ├── flutter-dart.md
│   ├── ios-swift.md
│   ├── ios-objc.md
│   └── mobile-general.md
├── scripts/                     # Hook & statusline scripts
│   ├── global_constraints_hook.sh
│   └── statusline-command.sh
└── skills/                      # 84 curated skills
    ├── superpowers-*/
    ├── flutter-*/
    ├── figma-*/
    ├── doc-*/
    ├── code-review-*/
    ├── frontend-design/
    ├── skill-creator/
    ├── text2mermaid/
    └── ... (40+ more)
```

## License

MIT
