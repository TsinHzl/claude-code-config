# Allowed-Tools 推断规则

根据 skill 的核心动作推断所需工具集,避免过度授权或遗漏。

## 推断决策表

| Skill 类型 | 核心动作 | 推荐 allowed-tools |
|---|---|---|
| 纯分析/报告 | 读代码 → 输出文本报告 | `Read Bash Grep Glob` |
| 代码生成/修改 | 读 → 生成 → 写入文件 | `Read Write Edit Bash` |
| 交互式生成 | 收集输入 → 生成 → 确认 → 写入 | `Read Write Edit Bash AskUserQuestion` |
| 编排/分发 | 判断路由 → 委托子 agent | `Read Bash Agent` |
| 混合型(分析+修改) | 读 → 分析 → 修改 → 验证 | `Read Write Edit Bash Agent` |

## 追加规则

- 含任何文件写入 → 必须包含 `Write` 或 `Edit`
- 含用户确认门控 → 必须包含 `AskUserQuestion`
- 含 shell 命令(git/lint/build) → 必须包含 `Bash`
- 含委托子 agent → 必须包含 `Agent`
- 仅做搜索定位 → `Grep Glob` 优先于 `Bash`
- 支持 glob 模式:如 `Bash(git:*) Bash(uv:*)`

## 格式要求

- **空格分隔**(官方规范),非逗号分隔
- 不声明 `*` 或 `All tools` — 必须逐项列出
- 不声明 skill 流程中未使用的工具
