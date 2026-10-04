# 环境检查 Prompt

> 环境依赖检查统一由 `scripts/checks/env-checks.sh` 完成，包含必选项（mcporter、openspec CLI）和可选项（graphify-out）。

## 使用方式

在 skill 流程启动前执行：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/env-checks.sh
```

## 检查项

| 检查项 | 用途 | 必选/可选 | 自动修复 |
|---|---|---|---|
| mcporter CLI | MCP 协议桥接 | 必选 | 自动 npm install |
| mcporter Cooper 配置 | pre-trim.sh 拉取 PRD 文档 | 必选 | 报错提示配置方式 |
| mcporter mastergo-proxy 配置 | 设计稿获取 | 必选 | 自动添加配置 |
| openspec CLI | 变更管理 | 必选 | 自动 npm install |
| graphify-out 产物 | 工程知识图谱（提升规划精准度） | 可选 | ⚠️ 警告提示，由用户在 feature-plan 阶段决定 |

## 失败时行为

- 必选项缺失：脚本输出 `❌` 错误列表 + 修复指引，exit 1 阻断后续流程
- graphify 不可用：输出 `⚠️` 警告 + `GRAPHIFY_STATUS=unavailable`，**不阻断流程**，由 gd-ai-coding 初始化 step 1 通过 `AskUserQuestion` 向用户确认是否跳过
