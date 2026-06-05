---
name: OpenSpec Init — 扫描仓库并生成 config.yaml
description: 扫描当前工作目录的仓库，自动检测技术栈和架构模式，生成 openspec/config.yaml 和 openspec/project.md，为所有 OpenSpec artifact 生成步骤提供上下文约束注入。
---

# /opsx:init — 仓库扫描 & Config 生成

## 用途

扫描当前仓库，生成：
- `openspec/config.yaml` — 项目上下文与规则（注入所有 artifact 生成步骤的约束）
- `openspec/project.md` — 项目全景文档

**何时运行：**
- 项目首次使用 OpenSpec 时
- 技术栈或架构发生重大变更后
- `openspec/config.yaml` 缺失或内容过时时
- 本地 openspec rule 触发时发现 config.yaml 不存在

## 执行步骤

### Step 0：声明与准备

在对话中输出：`> 🔍 [opsx:init] 正在扫描仓库，生成 openspec/config.yaml…`

检查 `openspec/` 目录是否存在，不存在则创建。

---

### Step 1：识别项目根文件

按优先级依次检查以下文件是否存在，**存在则读取完整内容**：

| 优先级 | 文件 | 意义 |
|-------|------|------|
| 1 | `Package.swift` | Swift Package Manager 项目 |
| 2 | `*.podspec`（glob 取第一个）| CocoaPods 库 |
| 3 | `pubspec.yaml` | Flutter / Dart 项目 |
| 4 | `package.json` | Node.js / TypeScript 项目 |
| 5 | `Cargo.toml` | Rust 项目 |
| 6 | `go.mod` | Go 项目 |
| 7 | `build.gradle` 或 `build.gradle.kts` | Android / Kotlin 项目 |
| 8 | `pyproject.toml` 或 `setup.py` | Python 项目 |
| 9 | `CMakeLists.txt` | C / C++ 项目 |
| 10 | `Makefile` | 通用构建系统 |

注意 `*.xcodeproj` / `*.xcworkspace` 的存在（只记录存在性，不读取）。

---

### Step 2：读取项目文档

依次读取（存在则读取）：
1. `README.md`（或 `README.rst`）
2. `CHANGELOG.md`
3. `DevGuideline.md`、`CONTRIBUTING.md`、或 `DEVELOPMENT.md`
4. `.swiftlint.yml` 或 `.swiftformat`
5. `.eslintrc*` 或 `biome.json`
6. `.flutter-plugins`
7. 项目级 `CLAUDE.md`（非全局 `~/.claude/CLAUDE.md`）

---

### Step 3：扫描目录结构

运行以下命令：

```bash
find . -maxdepth 3 -type d | grep -v ".git" | grep -v "node_modules" | grep -v ".dart_tool" | grep -v "/build" | grep -v "/.build" | sort
```

```bash
find . -type f \( -name "*.swift" -o -name "*.kt" -o -name "*.dart" -o -name "*.ts" -o -name "*.tsx" -o -name "*.go" -o -name "*.rs" -o -name "*.m" -o -name "*.mm" \) | grep -v ".git" | grep -v "build/" | grep -v ".dart_tool" | sort | head -80
```

从结果识别：
- 主源码目录（`Sources/`、`lib/`、`src/`、`app/` 等）
- 测试目录（`Tests/`、`test/`、`__tests__/` 等）
- 示例 / Demo 目录
- 生成代码目录

---

### Step 4：采样核心源文件

从主源码目录选取 **最多 5 个** 代表性文件读取：
- 优先选文件名暗示为核心模块的文件（如 `KakaJSON.swift`、`Mapper.swift`、`Serializable.swift`）
- 避开 helper、utils、extension 类文件
- 目的：理解命名规范、错误处理风格、公开 API 设计模式

---

### Step 5：读取现有配置（如存在）

若 `openspec/project.md` 已存在，读取内容，提取手工维护的关键信息，在 Step 7 中保留。

---

### Step 6：生成 openspec/config.yaml

基于以上所有收集的信息，生成 `openspec/config.yaml`：

```yaml
# openspec/config.yaml
# 由 /opsx:init 自动生成。可手动编辑以调整约束注入内容。
# context 和 rules 在所有 OpenSpec artifact 生成步骤中作为约束条件注入，
# 不是模板内容，不得直接复制到 artifact 输出文件中。

schema: spec-driven

context: |
  Tech stack: <主要语言、框架、关键依赖>
  Package manager: <检测到的包管理器>
  Architecture: <检测到的架构模式，如 "Protocol-oriented Swift, Value types first">
  Source layout: <关键目录及用途>
  Test framework: <检测到的测试框架>
  Target platform: <iOS/macOS/Android/web/server 等>
  Min deployment target: <若从 podspec/Package.swift 检测到>

rules:
  specs:
    - <项目特定的 spec 编写约定>
    - <第二条规则>
  tasks:
    - <项目特定的任务粒度规则>
    - <第二条规则>
  design:
    - <项目特定的设计决策规则>
    - <第二条规则>
```

**rules 生成指导原则：**
- `specs`：聚焦项目特有的需求描述模式（平台特性、边界条件、协议版本、API 可见性）
- `tasks`：聚焦任务可验证性（是否有对应测试、是否影响公开 API、是否需要迁移说明）
- `design`：聚焦架构约束（现有模式、线程模型、内存管理规则、向后兼容要求）

---

### Step 7：创建 / 更新 openspec/project.md

写入 `openspec/project.md`，内容基于扫描结果：

```markdown
# 项目上下文

## 技术栈
<详细技术栈，含版本信息>

## 架构约定
<架构模式、命名规范、关键设计决策>

## 目录结构
<关键目录说明>

## 开发约定
<代码风格、测试要求、分支策略>

## 关键文件
<核心源文件列表及用途>
```

---

### Step 8：完成报告

在对话中输出：

```
> ✅ [opsx:init] 完成
  📄 openspec/config.yaml — 上下文 & 规则约束（已注入所有 artifact 生成步骤）
  📄 openspec/project.md  — 项目全景文档

检测到的技术栈：<一行摘要>
```

并在对话中展示生成的 `config.yaml` 完整内容供用户确认。

---

## 重要说明

1. `context` 和 `rules` 是 **约束条件**，不是内容模板——不得复制到任何 artifact 文件中
2. 重新运行本 skill 会覆盖 `config.yaml` 和 `project.md`——手动编辑的内容会丢失
3. 每次项目技术栈或架构发生重大变更后，应重新运行 `/opsx:init`
