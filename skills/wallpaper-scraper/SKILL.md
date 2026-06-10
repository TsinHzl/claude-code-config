---
name: wallpaper-scraper
description: 高清电脑壁纸爬虫 — 从 WallpapersWide、Wallhaven 等站点或用户指定 URL 批量下载高清壁纸（每次约 60 张），支持按类型/分类爬取（风景、美女、城市、动漫、游戏、汽车等），1920×1080+ 分辨率筛选 + SHA-256 去重。当用户提到壁纸、wallpaper、爬壁纸、下载壁纸、桌面壁纸、高清壁纸、电脑壁纸，或提供壁纸站链接时触发。
---

# Wallpaper Scraper — 高清电脑壁纸爬虫

## 依赖

```bash
pip3 install requests beautifulsoup4 lxml Pillow
```

## 参数说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `url` (位置参数) | 目标壁纸站 URL。不提供则自动模式 | 无 |
| `-c, --category` | 壁纸分类（见下方分类表） | 无（混合风格） |
| `-r, --aspect-ratio` | 宽高比，如 `16:10`、`16:9` | `16:10`（MacBook 全系） |
| `--ratio-tolerance` | 宽高比容差 | `0.05`（±5%） |
| `-o, --output` | 保存目录 | `~/Downloads/Wallpapers` |
| `-n, --count` | 下载目标数量 | `60` |
| `--min-width` | 最小宽度 (px) | `1920` |
| `--min-height` | 最小高度 (px) | `1080` |
| `--workers` | 并发线程数 | `6` |
| `--queries` | 自定义英文搜索词列表（覆盖 `-c`） | 无 |
| `--list-categories` | 列出所有可用分类 | — |

## 分类表

用户说中文或英文均可识别。

| 分类 | 别名 | 典型搜索词 |
|------|------|-----------|
| `风景` | landscape, nature, 自然 | nature landscape, mountains lake, ocean sunset, forest path, waterfall river, autumn forest |
| `美女` | girl, 女孩, 人物 | girl model, beautiful woman, female portrait, fashion model, actress celebrity |
| `城市` | city, 建筑 | city night, cityscape skyline, urban street, architecture modern |
| `抽象` | abstract, 艺术 | abstract art, digital art colorful, geometric shapes, fractal pattern |
| `游戏` | game, games | video game, gaming art, cyberpunk game, fantasy game |
| `动漫` | anime | anime art, anime girl, anime landscape, japanese anime |
| `卡通` | cartoon | cartoon art, cartoon character, animated cartoon, disney cartoon, pixar animation |
| `动物` | animal, animals | wildlife animal, cat kitten, dog puppy, bird wildlife, tiger lion |
| `汽车` | car, cars | sports car, luxury car, racing car, vintage car |
| `太空` | space | space stars, galaxy nebula, planet space, night sky stars |
| `极简` | minimalist | minimalist gradient, simple background, clean minimal |
| `科技` | tech, technology | technology future, science fiction, digital technology |

## 使用流程

### 1. 解析用户意图

- 用户说"壁纸" + **未提分类** → 自动模式（混合风格），不传 `-c`
- 用户说"风景壁纸" → `-c 风景`
- 用户说"帮我下载 30 张动漫壁纸" → `-c 动漫 -n 30`
- 用户给 URL → 传为位置参数，忽略 `-c`
- 用户说"美女" → `-c 美女`

### 2. 运行脚本

```bash
python3 <skill-base>/scripts/scrape_wallpapers.py [URL] [选项]
```

### 3. 典型场景

**自动模式（默认，混合风格）：**
```bash
python3 scripts/scrape_wallpapers.py
```

**按分类爬取：**
```bash
python3 scripts/scrape_wallpapers.py -c 风景
python3 scripts/scrape_wallpapers.py -c 美女 -n 30
python3 scripts/scrape_wallpapers.py -c 动漫 -n 100
python3 scripts/scrape_wallpapers.py -c car
```

**指定 URL：**
```bash
python3 scripts/scrape_wallpapers.py "https://wallhaven.cc/search?q=nature"
```

**4K 壁纸：**
```bash
python3 scripts/scrape_wallpapers.py -c 风景 --min-width 3840 --min-height 2160
```

**切换宽高比（外接 16:9 显示器）：**
```bash
python3 scripts/scrape_wallpapers.py -r 16:9
```

## 宽高比说明

默认 `16:10`（容差 ±5%），匹配 MacBook 全系列：
- MacBook Air 13": 2560×1664
- MacBook Air 15": 2880×1864
- MacBook Pro 14": 3024×1964
- MacBook Pro 16": 3456×2234

WallpapersWide 下载链接包含分辨率信息（如 `...wallpaper-3200x2000.jpg`），脚本在下载前就过滤掉比例不符的链接，避免浪费带宽。

## 工作流程

1. **扫描已有文件** → SHA-256 哈希索引，避免重复下载
2. **分类映射** → 中文分类名（风景/美女/动漫...）映射为英文搜索关键词列表
3. **多关键词搜索** → 每个关键词轮询 WallpapersWide 搜索页
4. **详情页解析** → 抓取所有分辨率下载链接 → 宽高比过滤 → 取最大分辨率
5. **下载 + PIL 校验** → 实际尺寸验证分辨率 + 宽高比
6. **哈希去重** → 比对已有文件 SHA-256

## 错误处理

- 网络超时 → 跳过该项，继续下一个
- 图片不合格 → 静默丢弃，不计入
- 源耗尽不足目标 → 打印最终数量和缺额
- 残留 `.tmp` → 脚本结束时自动清理
- 未知分类 → 回退到默认混合模式，并打印可用分类列表
