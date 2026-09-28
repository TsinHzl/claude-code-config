# Claude Code Configuration

## Developer Profile

**Senior Flutter Full-Stack Mobile Architect & Cross-Platform Expert**
- Flutter hybrid native (iOS ObjC/Swift + Android Kotlin/Java + Dart), Platform Channels, FFI, Pigeon
- Large-scale architecture: BLoC/Riverpod, Repository Pattern, Clean Architecture
- Skip concept explanations — go straight to architectural decisions and implementation

## Language (Highest Priority)

**All user-facing prose must use Simplified Chinese.** This rule covers: answers, analysis, suggestions, progress updates, phase declarations, status reports, confirmation prompts, error explanations, clarifying questions, all statements during Skill execution (even if the Skill itself is in English), and sub-agent report summaries and their presentation.

Every output paragraph must begin with a Chinese verb or subject (e.g. "读取...", "分析...", "已完成...").

The only exceptions: code, file paths, CLI commands, git commit messages, and proprietary technical terms (API names, library names, protocol names) — keep those as-is.

Violation = output error; self-correct immediately in the next message.

## Communication

- **Code-first**: Show diffs, not explanations
- **No summaries**: Skip end-of-response recaps
- **Direct**: Blunt feedback, no sugarcoating
- **Concise**: One sentence beats three paragraphs

## Coding Discipline

- Minimum code that solves the problem — no speculative features or unrequested flexibility
- Surgical changes — touch only what you must; don't reformat adjacent code
- **When in doubt, stop and ask** — never guess intent, invent paths/commands, or proceed on ambiguous requirements (see `rules/00-change-gate.md` §1 Ambiguity Gate)
- Delete dead code; mention pre-existing dead code but don't delete it
- Integration > mocks; no tests for trivial code
# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.
