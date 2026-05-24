> **注：** 本文档由 **claude-sonnet-4-6** 模型自动生成。

# claude-code-config

面向移动端/跨平台开发者的模块化 Claude Code 配置。通过 `~/.claude/CLAUDE.md` 和 `~/.claude/rules/` 提供行为规则、工作流门控和平台编码规范。

## 包含内容

### 全局规则（始终加载）

| 文件 | 用途 |
|------|------|
| `rules/code-change-gate.md` | 文件变更前确认门控 + 变更后代码审查 |
| `rules/task-execution.md` | 多步骤任务的 TaskCreate/TaskUpdate 工作流 |
| `rules/document-generation.md` | 生成的 Markdown 文件自动插入模型 ID 头部 |
| `rules/git-workflow.md` | 约定式提交、分支命名、危险操作门控 |
| `rules/repo-discovery.md` | 禁止凭空捏造命令/路径；先读取真实项目文件 |
| `rules/file-writing.md` | 大文件（>500 行 / >50KB）增量写入 |

### 平台规则（按文件类型自动加载）

| 文件 | 触发条件 | 用途 |
|------|---------|------|
| `rules/flutter-dart.md` | `*.dart` | Dart 风格、BLoC/Riverpod、Flutter 规范 |
| `rules/ios-swift.md` | `*.swift` | Swift 风格、MVVM/Coordinator、SwiftUI vs UIKit |
| `rules/ios-objc.md` | `*.m`、`*.h`、`*.mm` | ObjC 风格、ARC、Swift 互操作 |
| `rules/mobile-general.md` | 始终 | 电量、网络、存储、安全、发布规范 |

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
3. 将所有 `rules/*.md` 复制到 `~/.claude/rules/`
4. 跳过已存在的文件（使用 `--force` 强制覆盖）

## 安装后配置

编辑 `~/.claude/CLAUDE.md`，将开发者简介占位符替换为你自己的信息：

```markdown
## Developer Profile

**[你的角色与专长]**
- [主要技术栈和平台]
- [你使用的架构模式]
```

## 自定义

**只保留你需要的。** 不写 Flutter 就跳过 `flutter-dart.md`，不写 ObjC 就跳过 `ios-objc.md`。

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
├── install.sh                   # 安装脚本
├── README.md                    # 英文文档
├── README.zh.md                 # 中文文档
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
