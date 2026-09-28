---
name: disk-cleanup
description: >
  macOS 磁盘垃圾扫描与清理。触发：用户提到磁盘空间不足、"清理垃圾"、
  "磁盘快满了"、"哪些文件占用大"、"帮我清理 Mac"，或 /disk-cleanup。
  扫描 Xcode DerivedData/DeviceSupport/Archives、CocoaPods/npm/pip/pub-cache、
  Homebrew、Gradle、Cargo、Maven、node-gyp、Swift PM、JetBrains、Bun、
  Playwright 浏览器、iOS/Android 模拟器、Chrome 缓存，生成
  🔴/🟡/🔵 分级报告，经用户确认后执行清理。
  不触发：非 macOS 平台、单文件大小查询、用户已指定明确删除路径。
compatibility: 仅适用于 macOS；模拟器清理需已安装 Xcode CLI Tools
allowed-tools: Bash AskUserQuestion Read
---

## Workflow

### Step 1 — 扫描

```bash
bash ~/.claude/skills/disk-cleanup/scripts/scan.sh
```

单次调用获取全部目标大小与磁盘总览，只读操作，无副作用。

### Step 2 — 分级报告

将 scan.sh 输出整理为三级表格：

| 级别 | 含义 |
|------|------|
| 🔴 安全 | 清理后自动重建，零用户数据丢失风险 |
| 🟡 需确认 | 清理后需重新编译或重新下载，影响开发流程 |
| 🔵 用户数据 | 仅展示大小，本 Skill 绝不操作 |

报告末行输出：**预计可释放 X GB**（仅统计 🔴 项合计）。

### Step 3 — 确认选择

<HARD-GATE>
在 AskUserQuestion 获得明确选择前，禁止执行任何清理或删除命令。
不得以"这些目录显然安全"或"上次已经确认过"为由跳过本步骤。
</HARD-GATE>

使用 AskUserQuestion（两个问题）：

**问题 1** — 安全缓存处理（multiSelect: true，2 个选项）：
- **清理全部🔴安全缓存**（推荐）— CocoaPods / npm / pip / Homebrew / Go / Chrome / Flutter / Playwright / Gradle / Cargo / Maven / node-gyp / Swift PM / JetBrains / Bun / Xcode ModuleCache
- **仅生成报告，不执行任何清理**

**问题 2** — 需确认的清理（multiSelect: true，4 个选项）：
- **🟡 Xcode DerivedData** — 下次编译耗时增加 10–30 分钟，自动重建
- **🟡 Shutdown iOS 模拟器** — 可通过 Xcode 重新添加
- **🟡 Android 模拟器 (AVD)** — 可通过 Android Studio 重新创建
- **🟡 Xcode DeviceSupport & Archives** — 调试符号和历史归档，可重下载/重打包

问题 1 选"仅报告" 且 问题 2 无任何勾选 → 结束，不调用任何删除工具。

### Step 4 — 执行与验证

读取 [references/cleanup-commands.md](references/cleanup-commands.md)，按所选分类依次执行：

1. 每项前输出：`> 正在清理：<名称>（预计 X GB）`
2. 执行对应命令
3. 完成后重新运行 `df -h /`，对比 Step 1 的 Avail 值
4. 输出：**实际释放 X GB**

## Constraints

- **🔵 目录绝不操作**：`Application Support/Google/Chrome`、`~/Downloads`、`~/Documents`
- **rm -rf 安全**：执行前用 `echo` 预演路径展开，确认无通配符误扩展后再执行
- **对抗合理化**：
  - "这个缓存肯定是安全的，跳过确认直接删" → 必须通过 Step 3 AskUserQuestion，无例外
  - "已经扫描过了，跳过 Step 1 省时间" → Step 1 每次必须重新运行，获取当前真实状态
