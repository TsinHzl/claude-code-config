---
name: dashboard
description: DAC 工作流数据看板 — 用默认浏览器打开团队集中部署的看板地址，支持页面内一键刷新 DDP 数据
user-invocable: false
metadata:
  openclaw:
    emoji: "📊"
---

# dashboard — 工作流数据看板（打开团队看板）

触发命令：`/dashboard`

## 职责

用默认浏览器打开团队集中部署的看板地址（`http://172.24.244.18:47890`）。看板由部署机上的
server 提供，页面支持「刷新数据」按钮，点击后由 server 端调用 `claude -p` 重新从 DDP MCP
获取最新需求数据，无需重新执行命令。

## 执行步骤

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/start-dashboard.sh
```

脚本用默认浏览器打开固定地址（macOS `open` / Linux `xdg-open` / Windows `start`）。
地址可通过 `DAC_DASHBOARD_URL` 环境变量覆盖。

成功后输出：
```
打开看板：http://172.24.244.18:47890
```

## 本地起 server（部署机使用）

在部署机上对外提供看板服务时，使用终端命令 `dashboard-gd`（本地起 server → 等就绪 → 打开浏览器）：

```bash
dashboard-gd
# 或直接调用脚本：
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/start-dashboard-local.sh
```

停止本地 server：
```bash
kill $(cat /tmp/dac-dashboard-server.pid) 2>/dev/null && echo "Server 已停止"
```

## 刷新数据流程（server 端）

页面点击「↻ 刷新数据」后，由 server 端执行：

1. 浏览器 `POST /api/refresh` → server 启动后台线程
2. 后台线程运行 `refresh-ddp.sh`：
   - `claude -p "..."` 调用 DDP MCP → Write tool → `/tmp/ddp-raw-items.json`
   - `transform-ddp.py` 转换格式 → `/tmp/dac-metrics-data.json`
3. 浏览器每 2s 轮询 `/api/status`，完成后重新 `GET /api/data` 更新页面

## 错误处理

| 情况 | 行为 |
|------|------|
| 浏览器打开命令缺失 | 脚本打印地址并以 exit 1 退出，手动访问该地址即可 |
| 看板打不开 | 确认部署机（172.24.244.18）上的 server 是否在运行（用 `dashboard-gd` 启动） |
| claude -p 未写文件 | refresh-ddp.sh 以 exit 1 退出，页面显示错误信息 |
| 刷新超时（>3min） | 页面显示超时提示，按钮恢复可点击 |
