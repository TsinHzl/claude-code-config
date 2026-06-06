> **注：** 本文档由 **deepseek-v4-pro** 模型自动生成。

# claude-code-config

面向移动端/跨平台开发者的模块化 Claude Code 配置。通过 `~/.claude/` 提供行为规则、工作流门控、平台编码规范、精选技能、斜杠命令、hook 脚本和 harness 设置。

## 包含内容

### `settings.json`

预配置的 Claude Code harness 设置：

- **权限**：allow/deny 规则（如屏蔽 `git push --force`、`rm -rf *`）
- **Hooks**：PreToolUse 文件大小检测、会话生命周期通知、UserPromptSubmit 约束注入
- **插件**：16+ 已启用插件（superpowers、code-review、figma、frontend-design、document-skills、GitHub、playwright、LSP 等）
- **MCP 服务器**：code-review MCP 服务器
- **StatusLine**：自定义 shell 驱动的状态栏

### 全局规则（始终加载）

| 文件 | 用途 |
|------|------|
| `rules/code-change-gate.md` | 文件变更前确认门控 + 变更后代码审查 |
| `rules/task-execution.md` | 多步骤任务的 TaskCreate/TaskUpdate 工作流 |
| `rules/document-generation.md` | 生成的 Markdown 文件自动插入模型 ID 头部 |
| `rules/git-workflow.md` | 约定式提交、分支命名、危险操作门控 |
| `rules/repo-discovery.md` | 禁止凭空捏造命令/路径；先读取真实项目文件 |
| `rules/file-writing.md` | 大文件（>500 行 / >50KB）增量写入 |
| `rules/openspec.md` | OpenSpec 规范驱动开发（五阶段门控工作流） |

### 平台规则（按文件类型自动加载）

| 文件 | 触发条件 | 用途 |
|------|---------|------|
| `rules/flutter-dart.md` | `*.dart` | Dart 风格、BLoC/Riverpod、Flutter 规范 |
| `rules/ios-swift.md` | `*.swift` | Swift 风格、MVVM/Coordinator、SwiftUI vs UIKit |
| `rules/ios-objc.md` | `*.m`、`*.h`、`*.mm` | ObjC 风格、ARC、Swift 互操作 |
| `rules/mobile-general.md` | 始终 | 电量、网络、存储、安全、发布规范 |

### 技能（84 个精选技能）

预装到 `~/.claude/skills/`：

| 分类 | 数量 | 亮点 |
|------|------|------|
| Superpowers | 14 | 头脑风暴、TDD、系统调试、代码审查、git worktrees、并行 agent |
| Flutter | 22 | 状态管理（BLoC/Riverpod）、导航、测试、Platform Channels、表单、动画、无障碍 |
| Figma | 8 | 设计生成、Code Connect、图表、设计系统、FigJam、幻灯片 |
| 文档 | 17 | pptx、docx、xlsx、pdf、前端设计、MCP 构建器、主题工厂、品牌指南 |
| 代码分析 | 5 | 多/单文件代码审查、架构分析、diff pulse、GD 组件分析器 |
| 其他 | 18 | AI 视频、notebooklm、text2mermaid、PPT 生成、离线 Turing、skill 创建器、OpenSpec 初始化 |

### 命令

预装到 `~/.claude/commands/` 的斜杠命令：

| 文件 | 命令 | 用途 |
|------|------|------|
| `commands/code-arch-master-analyzer.md` | `/code-arch-master-analyzer` | 深度架构分析 |
| `commands/code-diff-pulse.md` | `/code-diff-pulse` | 生成 diff 驱动的 pulse 报告 |

### 脚本

安装到 `~/.claude/` 的 hook/statusline 脚本：

| 文件 | 用途 |
|------|------|
| `scripts/global_constraints_hook.sh` | UserPromptSubmit hook — 注入全局约束（CLAUDE.md + rules） |
| `scripts/statusline-command.sh` | 自定义 shell 驱动的状态栏显示 |

## 安装

### 快速安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/claude-code-config/main/install.sh | bash
```

### 手动安装

```bash
git clone https://github.com/YOUR_USERNAME/claude-code-config.git
cd claude-code-config
./install.sh
```

### 安装脚本做了什么

1. 备份已有的 `~/.claude/CLAUDE.md`（如存在）
2. 将 `CLAUDE.md` 复制到 `~/.claude/CLAUDE.md`
3. 将 `settings.json` 复制到 `~/.claude/settings.json`
4. 将所有 `rules/*.md` 复制到 `~/.claude/rules/`
5. 将所有 `skills/*/` 复制到 `~/.claude/skills/`
6. 将所有 `commands/*.md` 复制到 `~/.claude/commands/`
7. 将 `scripts/*.sh` 复制到 `~/.claude/`（并 `chmod +x`）
8. 跳过已存在的文件（使用 `--force` 强制覆盖）

## 安装后配置

编辑 `~/.claude/CLAUDE.md`，将开发者简介占位符替换为你自己的信息：

```markdown
## Developer Profile

**[你的角色与专长]**
- [主要技术栈和平台]
- [你使用的架构模式]
```

检查 `~/.claude/settings.json` 并更新：

- **Hook 命令路径** — 将 `/Users/MacBook/...` 路径替换为你自己的路径
- **StatusLine 命令** — 指向你自己的 statusline 脚本
- **enabledPlugins** — 禁用你不需要的插件

## 自定义

**只保留你需要的。** 不写 Flutter 就跳过 `flutter-dart.md`，不写 ObjC 就跳过 `ios-objc.md`。从 `~/.claude/skills/` 和 `~/.claude/commands/` 中删除不需要的技能和命令。

**按项目覆盖。** 在项目根目录创建 `CLAUDE.md` 添加项目专属上下文，优先级高于全局配置。

**添加自定义规则。** 在 `~/.claude/rules/` 中放入任意带 frontmatter 的 `.md` 文件：

```markdown
---
name: 我的规则
description: 规则说明
inclusion: always   # 或：auto（配合 fileMatchPattern）
---

规则内容
```

## 执行机制

| 机制 | 执行力度 | 用途 |
|------|---------|------|
| `settings.json` deny | 100% — 模型无法看到被屏蔽的工具 | 危险 git 命令 |
| `PreToolUse` hooks | 100% — shell 级拦截 | 文件大小检测 |
| `rules/` + `CLAUDE.md` | ~95% — 建议性 | 行为、工作流、风格 |

规则文件是**建议性**的，非确定性执行。如需强制执行，请在 `~/.claude/settings.json` 中使用 hooks。

## 文件结构

```
claude-code-config/
├── CLAUDE.md                    # 全局配置模板
├── settings.json                # Harness 设置（权限、hooks、插件、MCP）
├── install.sh                   # 安装脚本
├── README.md                    # 英文文档
├── README.zh.md                 # 中文文档
├── .gitignore
├── commands/                    # 斜杠命令定义
│   ├── code-arch-master-analyzer.md
│   └── code-diff-pulse.md
├── rules/                       # 行为与工作流规则
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
├── scripts/                     # Hook 与 statusline 脚本
│   ├── global_constraints_hook.sh
│   └── statusline-command.sh
└── skills/                      # 84 个精选技能
    ├── superpowers-*/
    ├── flutter-*/
    ├── figma-*/
    ├── doc-*/
    ├── code-review-*/
    ├── frontend-design/
    ├── skill-creator/
    ├── text2mermaid/
    └── ...（40+ 更多）
```

## License

MIT
