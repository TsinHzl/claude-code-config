---
name: wallpaper-scraper
description: 高清电脑壁纸爬虫 — 自动模式优先链 Bing API → toopic.cn，批量下载 4K 壁纸（默认 60 张），SHA-256 去重。当用户提到壁纸、wallpaper、爬壁纸、下载壁纸、桌面壁纸、高清壁纸、电脑壁纸，或提供壁纸站链接时触发。
---

# Wallpaper Scraper — 高清电脑壁纸爬虫

## 依赖

```bash
python3.11 -m pip install requests beautifulsoup4 Pillow
```

> 系统自带 Python 3.7 版本过旧，必须使用 `python3.11`（或更新版本）运行脚本。

## 参数说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `url` (位置参数) | 目标壁纸站 URL。不提供则自动模式 | 无 |
| `-c, --category` | WallpapersWide 搜索词（需翻墙时才有效） | 无 |
| `-r, --aspect-ratio` | 宽高比过滤，如 `16:10`、`16:9` | 不过滤（Bing/toopic 均为 16:9，强过滤会全拦） |
| `--ratio-tolerance` | 宽高比容差 | `0.05`（±5%） |
| `-o, --output` | 保存目录 | `~/Downloads/Wallpapers` |
| `-n, --count` | 下载目标数量 | `60` |
| `--min-width` | 最小宽度 (px) | `1920` |
| `--min-height` | 最小高度 (px) | `1080` |
| `--workers` | 并发下载线程数 | `8` |
| `--source` | 强制指定源：`auto`/`bing`/`toopic`/`wallpaperswide` | `auto` |
| `--queries` | 自定义 WallpapersWide 搜索词（需翻墙） | 无 |
| `--list-categories` | 列出 WallpapersWide 可用分类 | — |

## 使用流程

### 1. 解析用户意图

- 用户说"壁纸" + **未提分类** → 自动模式（Bing + toopic），不传 `-c`
- 用户说"帮我下载 30 张壁纸" → `-n 30`
- 用户给 URL → 传为位置参数
- 用户指定数量 → `-n N`

### 2. 运行脚本

```bash
python3.11 <skill-base>/scripts/scrape_wallpapers.py [URL] [选项]
```

### 3. 典型场景

**自动模式（Bing + toopic 补量）：**
```bash
python3.11 scripts/scrape_wallpapers.py
python3.11 scripts/scrape_wallpapers.py -n 30
```

**只用 toopic（跳过 Bing）：**
```bash
python3.11 scripts/scrape_wallpapers.py --source toopic -n 50
```

**只用 Bing（约 15 张上限）：**
```bash
python3.11 scripts/scrape_wallpapers.py --source bing
```

**指定 URL（支持 toopic / wallhaven / wallpaperswide / 通用）：**
```bash
python3.11 scripts/scrape_wallpapers.py "https://www.toopic.cn/4kbz/"
python3.11 scripts/scrape_wallpapers.py "https://wallhaven.cc/search?q=nature"
```

**4K + 宽高比过滤（如需精确匹配 MacBook 16:10）：**
```bash
python3.11 scripts/scrape_wallpapers.py -r 16:10 --ratio-tolerance 0.1
```

## 工作流程（自动模式）

1. **扫描已有文件** → SHA-256 哈希索引，避免重复下载
2. **Bing API** → 7 市场去重，直接获取 UHD URL，并发下载（约 15 张，~5s）
3. **toopic.cn 补量** → 翻页收集 detail 链接 → **并发 fetch detail 页**（12 线程提取原图 URL）→ **并发下载**（8 线程）
4. **PIL 校验** → 验证实际分辨率（如启用宽高比过滤则同步校验）
5. **哈希去重** → 比对已有文件 SHA-256

## 性能说明

- Bing 阶段：~5s（直接 API，无 HTML 解析，约 15 张）
- toopic 阶段：detail 页并发抓取（12 线程），45 张约 30-40s；原图 3840×2160，均约 1.9-8MB
- 自动模式 60 张总耗时约 50-70s

## 错误处理

- 网络超时 → 跳过该项，继续下一个
- 图片不合格 → 静默丢弃，不计入
- 源耗尽不足目标 → 打印最终数量和缺额
- 残留 `.tmp` → 脚本结束时自动清理
- WallpapersWide/Wallhaven → 在当前网络环境（国内）不可用，仅保留 URL 模式（需翻墙）
