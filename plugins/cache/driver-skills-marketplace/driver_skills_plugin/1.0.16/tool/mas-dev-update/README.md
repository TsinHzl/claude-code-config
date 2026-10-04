# MAS 开发环境快速更新工具

根据 MAS 任务 ID 自动查询关联的开发分支，帮助快速定位需要切换/更新的本地仓库。

## 初始化配置

首次使用前，需要配置你的 MAS Cookie：

1. 打开浏览器，登录 [MAS](https://mas.intra.xiaojukeji.com)
2. 打开开发者工具 (F12) → Network 标签
3. 找到任意 `mas.intra.xiaojukeji.com` 域名的请求
4. 复制 **Cookie** 请求头的完整值
5. 保存到配置文件：

```bash
echo 'YOUR_COOKIE_VALUE' > ~/.claude/mas-cookie.txt
```

> Cookie 会定期过期，需要重新获取。

## 使用方式

### 基本用法

```
请帮我查询 MAS 任务 MAS-1-132303 的开发分支
```

```
查询 132303 的分支
```

```
/mas-dev-update MAS-1-132303
```

### 带调试信息

```
查询 MAS-1-132303 的开发分支 --debug
```

## 输出示例

```
✅ 任务 MAS-1-132303 共找到 3 个开发分支：

1. 仓库：DGDriver
   Git URL：git@git.xiaojukeji.com:mobile/DGDriver.git
   分支：feature/order-optimize-20240101

2. 仓库：DGDriver-iOS
   Git URL：git@git.xiaojukeji.com:mobile/DGDriver-iOS.git
   分支：feature/order-optimize-20240101

3. 仓库：DGBase
   Git URL：git@git.xiaojukeji.com:mobile/DGBase.git
   分支：feature/order-optimize-20240101
```

## 常见问题

**Q: 返回空数据或 errno != 0**
A: Cookie 可能已过期，重新获取后更新 `~/.claude/mas-cookie.txt`

**Q: 如何确认是"开发分支"？**
A: 工具会筛选 `branchType` 对应开发分支类型的记录，或 `branchTypeName` 包含"开发"的分支

**Q: 需要连 VPN 吗？**
A: 是的，需要连接公司内网或 VPN 才能访问 MAS API
