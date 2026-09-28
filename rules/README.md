---
name: Rules README
description: Rules directory structure documentation (for humans only)
inclusion: never
---

# 规则 (Rules)
## 目录结构

规则按层级进行组织，包括一个**通用 (common)** 层以及多个**特定语言 (language-specific)** 目录：

```
rules/
├── 00-change-gate.md       # 最高优先级硬约束：变更前确认 + 变更后 CR
├── document-generation.md  # 文档生成水印（按需启用）
├── flutter-dart.md         # Flutter / Dart 框架规则
├── mobile-general.md       # 跨平台移动端通用准则
├── openspec.md             # OpenSpec 规范驱动开发流程
├── repo-discovery.md       # 仓库探索约定
├── task-execution.md       # 多步骤任务跟踪规则
├── common/                 # 语言无关原则（始终安装）
│   ├── coding-style.md
│   ├── git-workflow.md
│   ├── development-workflow.md
│   ├── testing.md
│   ├── performance.md
│   ├── patterns.md
│   ├── hooks.md
│   ├── agents.md
│   └── security.md
├── typescript/             # TypeScript / JavaScript 相关
├── python/                 # Python 相关
├── golang/                 # Go 相关
└── swift/                  # Swift 相关
```

- **rules/ 根目录**：全局硬约束 + 框架/平台规则（不分语言或跨语言适用）。
- **common/**：通用原则 —— 不包含特定语言的代码示例。
- **特定语言目录**：使用特定于框架的模式、工具和代码示例对通用规则进行扩展。每个文件都会引用其对应的通用文件。

## 规则 (Rules) vs 技能 (Skills)

- **规则 (Rules)** 定义了广泛适用的标准、约定和检查清单（例如，“80% 的测试覆盖率”、“严禁硬编码密钥”）。
- **技能 (Skills)**（`skills/` 目录）为特定任务提供深入且可操作的参考资料（例如，`python-patterns`、`golang-testing`）。

特定语言规则文件会在适当的地方引用相关技能。规则告诉你**该做什么**；技能告诉你**如何去做**。

## 添加新语言

要添加对新语言（例如 `rust/`）的支持：

1. 创建 `rules/rust/` 目录
2. 添加扩展通用规则的文件：
   - `coding-style.md` —— 格式化工具、惯用法、错误处理模式
   - `testing.md` —— 测试框架、覆盖率工具、测试组织
   - `patterns.md` —— 特定语言的设计模式
   - `hooks.md` —— 用于格式化程序、代码检查器和类型检查器的 PostToolUse 钩子 (Hooks)
   - `security.md` —— 密钥管理、安全扫描工具
3. 每个文件应以以下内容开头：
   ```
   > 本文件使用 <Language> 特定内容扩展了 [common/xxx.md](../common/xxx.md)。
   ```
4. 如果已有相关技能，请进行引用，或者在 `skills/` 下创建新技能。

## 规则优先级

当特定语言规则与通用规则发生冲突时，**特定语言规则优先**（具体覆盖一般）。这遵循标准的层级配置模式（类似于 CSS 优先级或 `.gitignore` 优先级）。

- `rules/common/` 定义了适用于所有项目的通用默认值。
- `rules/golang/`、`rules/python/`、`rules/typescript/` 等在语言惯用法不同的地方覆盖这些默认值。

### 示例

`common/coding-style.md` 推荐将不可变性 (Immutability) 作为默认原则。特定于语言的 `golang/coding-style.md` 可以覆盖此项：

> Go 的惯用法对结构体修改使用指针接收器 —— 参见 [common/coding-style.md](../common/coding-style.md) 了解一般原则，但此处优先使用符合 Go 惯用法的修改方式。

### 带有覆盖注释的通用规则

`rules/common/` 中可能被特定语言文件覆盖的规则会标记有：

> **语言提示 (Language note)**：对于该模式不符合惯用法的语言，此规则可能会被特定语言规则覆盖。
