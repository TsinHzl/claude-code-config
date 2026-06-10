# 高清壁纸站点参考

以下为爬虫默认使用和可兼容的壁纸站点。

## 默认源（脚本自动使用）

### Wallhaven (wallhaven.cc)
- **类型**: 专用爬虫
- **画质**: 1080p / 2K / 4K / 8K
- **分类**: 通用 / 动漫 / 游戏 / 风景 / 抽象
- **搜索参数**: `categories=111` (全部) `purity=100` (SFW)
- **限制**: 无 API key 时每页 24 张，频繁访问会限速
- **爬虫**: 两级爬取（搜索页 → 详情页 → 原图）

### WallpapersWide (wallpaperswide.com)
- **类型**: 专用爬虫
- **画质**: 主要为 1080p / 2K
- **分类**: 电影 / 游戏 / 自然 / 城市 / 汽车
- **特点**: 每张壁纸有多个分辨率可选，下载页直接提供全分辨率 JPG 链接

## 可用的备用源（需要时可手动指定 URL）

以下站点通用爬虫可兼容：

| 站点 | URL | 画质 | 备注 |
|------|-----|------|------|
| Wallpaper Cave | wallpapercave.com | 1080p–4K | 搜索页直接显示高清缩略图 |
| HD Wallpapers | hdwallpapers.in | 1080p–4K | 分类清晰，原图在详情页 |
| Wallpaper Flare | wallpaperflare.com | 1080p–4K | 每页大量壁纸，适合批量爬取 |
| Wallpaper House | wallpapershome.com | 1080p–4K | 专业摄影壁纸，质量高 |
| Peakpx | peakpx.com | 1080p–4K | 无广告，直接下载链接 |

## 不推荐爬取的站点

| 站点 | 原因 |
|------|------|
| Unsplash | 需要 API key 或 JS 渲染，反爬严格 |
| Pexels | 同 Unsplash，有官方 API 但限速 |
| DeviantArt | 版权复杂，分辨率参差不齐 |
| Reddit (r/wallpapers) | 需要 OAuth 或 JS 渲染 |

## 新增站点

在 `FALLBACK_SOURCES` 列表中添加 dict 即可：

```python
{
    "name": "站点名",
    "url": "https://example.com/wallpapers?page={page}",
    "type": "generic",  # 或 "wallhaven_search" / "wallpaperswide"
}
```
