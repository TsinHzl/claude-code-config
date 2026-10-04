---
name: dac-cooper-check
description: 校验 mcporter 中 Cooper 配置是否可用（pre-trim.sh 关键路径）。不可用时引导用户配置。
---

# Cooper MCP 校验

校验 mcporter 中 Cooper 配置，确保 pre-trim.sh 可正常拉取 Cooper 文档。

## 校验流程

### 步骤 1：检查 mcporter Cooper 配置

读取 `~/.mcporter/mcporter.json`，检查 `mcpServers.Cooper` 配置：
- 存在且包含有效 `url`（或 `baseUrl`）和 `Authorization` header → **校验通过，结束**
- 不存在或配置不完整 → 进入步骤 2

### 步骤 2：引导用户配置

#### 2.1 检查 mcporter 是否安装

```bash
command -v mcporter
```

未安装则提示：`请运行: npm install -g mcporter`

#### 2.2 引导添加 Cooper

提示用户：

```
mcporter 中未配置 Cooper MCP，需要添加。请提供：

1. Cooper MCP URL（默认：http://127.0.0.1:28582/v1/hub/cooper_mcp）
2. API-KEY（Bearer token）

API-KEY 获取帮助：https://cooper.didichuxing.com/knowledge/share/page/uRaZEPYXmPfm
```

获取后编辑配置：

```bash
jq '.mcpServers["Cooper"] = {
  "type": "http",
  "url": "<url>",
  "headers": {
    "Authorization": "Bearer <API_KEY>"
  }
}' ~/.mcporter/mcporter.json > ~/.mcporter/mcporter.json.tmp && mv ~/.mcporter/mcporter.json.tmp ~/.mcporter/mcporter.json
```

#### 2.3 验证

```bash
mcporter call Cooper.readContent resourceId="test" appId=4 range="" --output json 2>&1
```

连接失败则提示用户检查 URL 和网络。

## 输出格式

```
✅ Cooper 校验通过（mcporter Cooper 已配置）
```

```
❌ Cooper 未配置，pre-trim.sh 将无法拉取文档。
```
