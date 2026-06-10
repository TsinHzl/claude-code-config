#!/usr/bin/env python3
"""
HD Wallpaper Scraper — 高清电脑壁纸爬虫
支持指定 URL 或自动从默认源爬取，目标每次 ~60 张 1920x1080+ 壁纸。
"""

import argparse
import hashlib
import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

# ── 常量 ───────────────────────────────────────────────
DEFAULT_OUTPUT_DIR = os.path.expanduser("~/Downloads/Wallpapers")
MIN_WIDTH = 1920
MIN_HEIGHT = 1080
TARGET_COUNT = 60
MAX_WORKERS = 6
REQUEST_TIMEOUT = 30
PAGE_DELAY = 1.0
MIN_FILE_SIZE = 10240
DEFAULT_ASPECT_RATIO = "16:10"  # MacBook 全系 16:10

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Referer": "https://www.google.com/",
}

# 默认多关键词搜索（覆盖不同风格壁纸）
DEFAULT_QUERIES = [
    "nature landscape",
    "city night",
    "abstract art",
    "mountains lake",
    "space stars",
    "ocean sunset",
    "forest path",
    "minimalist gradient",
]

# 分类关键词映射（中文/英文 → 英文搜索词列表）
CATEGORY_KEYWORDS: dict[str, list[str]] = {
    # ── 风景类 ──
    "风景": ["nature landscape", "mountains lake", "ocean sunset", "forest path",
             "waterfall river", "desert dunes", "autumn forest", "snowy winter",
             "meadow flowers", "tropical beach", "countryside field", "canyon valley"],
    "landscape": ["nature landscape", "mountains lake", "ocean sunset", "forest path",
                  "waterfall river", "desert dunes", "autumn forest", "snowy winter"],
    "自然": ["nature landscape", "mountains lake", "ocean sunset", "forest path",
             "waterfall river", "tropical beach", "meadow flowers", "autumn forest"],
    "nature": ["nature landscape", "mountains lake", "ocean sunset", "forest path",
               "waterfall river", "tropical beach", "meadow flowers", "autumn forest"],

    # ── 美女 / 人物类 ──
    "美女": ["girl model", "beautiful woman", "female portrait", "fashion model",
             "actress celebrity", "bride wedding", "woman beach", "girl outdoor"],
    "girl": ["girl model", "beautiful woman", "female portrait", "fashion model",
             "actress celebrity", "bride wedding", "woman beach"],
    "女孩": ["girl model", "beautiful woman", "female portrait", "fashion model",
             "actress celebrity", "woman beach", "girl cute"],
    "人物": ["girl model", "beautiful woman", "female portrait", "fashion model",
             "actress celebrity", "bride wedding", "man portrait"],

    # ── 城市 / 建筑类 ──
    "城市": ["city night", "cityscape skyline", "urban street", "architecture modern",
             "bridge river night", "new york city", "tokyo night", "dubai city"],
    "city": ["city night", "cityscape skyline", "urban street", "architecture modern",
             "bridge river night", "new york city", "tokyo night"],
    "建筑": ["architecture modern", "building design", "skyscraper glass",
             "interior design", "historical architecture", "bridge construction"],

    # ── 抽象 / 艺术类 ──
    "抽象": ["abstract art", "abstract design", "digital art colorful", "fractal pattern",
             "geometric shapes", "colorful gradient", "liquid abstract", "wave abstract"],
    "abstract": ["abstract art", "abstract design", "digital art colorful", "fractal pattern",
                 "geometric shapes", "colorful gradient"],
    "艺术": ["abstract art", "digital art", "oil painting", "watercolor art",
             "fantasy art", "surreal art", "impressionist painting"],

    # ── 游戏 ──
    "游戏": ["video game", "game wallpaper", "gaming art", "cyberpunk game",
             "fantasy game", "game character", "game landscape"],
    "game": ["video game", "game wallpaper", "gaming art", "cyberpunk game",
             "fantasy game", "game character"],
    "games": ["video game", "game wallpaper", "gaming art", "cyberpunk game",
              "fantasy game", "game character"],

    # ── 动漫 ──
    "动漫": ["anime art", "anime girl", "anime landscape", "anime city",
             "japanese anime", "anime fantasy", "anime night sky"],
    "anime": ["anime art", "anime girl", "anime landscape", "anime city",
              "japanese anime", "anime fantasy"],

    # ── 卡通 ──
    "卡通": ["cartoon art", "cartoon character", "cartoon cute", "animated cartoon",
             "cartoon illustration", "comic art", "disney cartoon", "pixar animation"],
    "cartoon": ["cartoon art", "cartoon character", "cartoon cute", "animated cartoon",
                "cartoon illustration", "comic art", "disney cartoon"],

    # ── 动物 ──
    "动物": ["wildlife animal", "cat kitten", "dog puppy", "bird wildlife",
             "tiger lion", "horse running", "eagle flying", "underwater fish"],
    "animal": ["wildlife animal", "cat kitten", "dog puppy", "bird wildlife",
               "tiger lion", "horse running"],
    "animals": ["wildlife animal", "cat kitten", "dog puppy", "bird wildlife",
                "tiger lion", "horse running"],

    # ── 汽车 ──
    "汽车": ["sports car", "luxury car", "racing car", "vintage car",
             "car night", "lamborghini ferrari", "bmw mercedes"],
    "car": ["sports car", "luxury car", "racing car", "vintage car",
            "car night", "lamborghini ferrari"],
    "cars": ["sports car", "luxury car", "racing car", "vintage car",
             "car night", "lamborghini ferrari"],

    # ── 太空 ──
    "太空": ["space stars", "galaxy nebula", "planet space", "outer space",
             "night sky stars", "milky way", "astronaut space"],
    "space": ["space stars", "galaxy nebula", "planet space", "outer space",
              "night sky stars", "milky way"],

    # ── 极简 ──
    "极简": ["minimalist gradient", "minimalist design", "simple background",
             "clean minimal", "solid color gradient", "dark minimal", "white minimal"],
    "minimalist": ["minimalist gradient", "minimalist design", "simple background",
                   "clean minimal", "solid color gradient"],

    # ── 科技 ──
    "科技": ["technology future", "science fiction", "digital technology",
             "circuit board", "data center", "artificial intelligence", "robotics"],
    "tech": ["technology future", "science fiction", "digital technology",
             "circuit board", "data center"],
    "technology": ["technology future", "science fiction", "digital technology",
                   "circuit board", "data center"],
}

# 站点基础 URL
WW_BASE = "https://wallpaperswide.com"
WW_SEARCH = WW_BASE + "/search.html?q={query}&page={page}"


# ── 工具函数 ────────────────────────────────────────────

def ensure_dir(path: str) -> None:
    Path(path).mkdir(parents=True, exist_ok=True)


def sanitize_filename(name: str) -> str:
    return re.sub(r'[<>:"/\\|?*]', "_", name)[:200]


def file_hash(filepath: str) -> str:
    h = hashlib.sha256()
    try:
        with open(filepath, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
    except OSError:
        return ""
    return h.hexdigest()


def build_hash_index(directory: str) -> set:
    hashes = set()
    if not os.path.isdir(directory):
        return hashes
    for f in os.listdir(directory):
        fp = os.path.join(directory, f)
        if os.path.isfile(fp) and not f.endswith(".tmp"):
            h = file_hash(fp)
            if h:
                hashes.add(h)
    return hashes


def fetch_page(url: str, session: requests.Session) -> BeautifulSoup:
    resp = session.get(url, headers=HEADERS, timeout=REQUEST_TIMEOUT)
    resp.raise_for_status()
    return BeautifulSoup(resp.text, "lxml")


def is_image_url(url: str) -> bool:
    path = urlparse(url.lower()).path
    return any(path.endswith(ext) for ext in (".jpg", ".jpeg", ".png", ".webp", ".bmp"))


def extract_style_url(style: str) -> str | None:
    m = re.search(r'url\(["\']?([^"\'()]+)["\']?\)', style)
    return m.group(1) if m else None


def guess_full_url(img_url: str) -> str:
    # wallhaven: th. → w.
    img_url = re.sub(
        r"https?://th\.wallhaven\.cc/small/",
        "https://w.wallhaven.cc/full/",
        img_url,
    )
    img_url = re.sub(r"\?.*$", "", img_url)
    img_url = re.sub(
        r"[-_](small|thumb|thumbnail|preview)(?=\.\w+$)", "", img_url, flags=re.I
    )
    return img_url


def _parse_aspect_ratio(ar_str: str) -> float | None:
    """解析宽高比字符串如 '16:10' 为浮点数 1.6。"""
    parts = ar_str.strip().split(":")
    if len(parts) == 2:
        try:
            w, h = float(parts[0]), float(parts[1])
            if h > 0:
                return w / h
        except ValueError:
            pass
    return None


def aspect_ratio_ok(w: int, h: int, target_ratio: float, tolerance: float = 0.05) -> bool:
    """检查图片宽高比是否在目标比例 ±tolerance 范围内。"""
    if h == 0:
        return False
    actual = w / h
    return abs(actual - target_ratio) <= tolerance


def validate_dimensions(
    filepath: str,
    min_w: int,
    min_h: int,
    target_ratio: float | None = None,
    ratio_tolerance: float = 0.05,
) -> bool:
    if not HAS_PIL:
        return True
    try:
        with Image.open(filepath) as img:
            w, h = img.size
            if w < min_w or h < min_h:
                return False
            if target_ratio is not None and not aspect_ratio_ok(w, h, target_ratio, ratio_tolerance):
                return False
            return True
    except Exception:
        return False


def download_one(
    session: requests.Session,
    img_url: str,
    filepath: str,
    hash_index: set,
    min_w: int,
    min_h: int,
    target_ratio: float | None = None,
    ratio_tolerance: float = 0.05,
) -> bool:
    if os.path.exists(filepath):
        h = file_hash(filepath)
        if h and h in hash_index:
            return False

    tmp = filepath + ".tmp"
    try:
        resp = session.get(img_url, headers=HEADERS, timeout=REQUEST_TIMEOUT, stream=True)
        resp.raise_for_status()

        ct = resp.headers.get("Content-Type", "")
        if "image" not in ct and not is_image_url(img_url):
            return False

        total = 0
        with open(tmp, "wb") as f:
            for chunk in resp.iter_content(8192):
                f.write(chunk)
                total += len(chunk)
                if total > 50 * 1024 * 1024:
                    f.close()
                    os.remove(tmp)
                    return False

        if total < MIN_FILE_SIZE:
            os.remove(tmp)
            return False

        if not validate_dimensions(tmp, min_w, min_h, target_ratio, ratio_tolerance):
            os.remove(tmp)
            return False

        h = file_hash(tmp)
        if h in hash_index:
            os.remove(tmp)
            return False

        hash_index.add(h)
        os.rename(tmp, filepath)
        return True

    except Exception:
        if os.path.exists(tmp):
            os.remove(tmp)
        return False


# ── WallpapersWide 爬虫（修复版）─────────────────────────

def _parse_resolution_from_url(url: str) -> tuple[int, int]:
    """从 wallpaperswide 下载 URL 中提取分辨率，如 ...-wallpaper-3840x2160.jpg"""
    m = re.search(r"(\d{3,5})x(\d{3,5})", url)
    if m:
        return int(m.group(1)), int(m.group(2))
    return 0, 0


def scrape_wallpaperswide(
    session: requests.Session,
    search_url_template: str,
    output_dir: str,
    target: int,
    hash_index: set,
    min_w: int,
    min_h: int,
    target_ratio: float | None = None,
    ratio_tolerance: float = 0.05,
) -> list:
    """爬取 wallpaperswide.com — 搜索页 → 详情页 → 最高分辨率下载。"""
    downloaded = []
    page = 1
    max_pages = 8  # 每个搜索词最多爬 8 页

    while len(downloaded) < target and page <= max_pages:
        url = search_url_template.format(page=page)
        print(f"  📄 WallpapersWide 第 {page} 页: {url.split('q=')[-1].split('&')[0][:40]}")

        try:
            soup = fetch_page(url, session)
        except Exception as e:
            print(f"  ⚠️  获取失败: {e}")
            break

        # 找到所有壁纸项 <li class="wall">
        wall_items = soup.select("li.wall")
        if not wall_items:
            print(f"  ℹ️  没有更多壁纸")
            break

        detail_urls = []
        for item in wall_items:
            a_tag = item.select_one(".thumb a[href*='-wallpapers.html']")
            if a_tag:
                detail_urls.append(urljoin(WW_BASE, a_tag["href"]))

        if not detail_urls:
            page += 1
            time.sleep(PAGE_DELAY)
            continue

        for detail_url in detail_urls:
            if len(downloaded) >= target:
                break

            try:
                time.sleep(0.3)
                d_soup = fetch_page(detail_url, session)

                # 收集所有下载链接及其分辨率
                candidates = []
                # 优先从 #top-resolutions 取（这是推荐的高分辨率）
                for a in d_soup.select("#top-resolutions a[href*='/download/']"):
                    href = a.get("href", "")
                    if is_image_url(href):
                        w, h = _parse_resolution_from_url(href)
                        full_url = urljoin(WW_BASE, href)
                        candidates.append((w, h, full_url))

                # 也从 .wallpaper-resolutions 取
                for a in d_soup.select(".wallpaper-resolutions a[href*='/download/']"):
                    href = a.get("href", "")
                    if is_image_url(href):
                        w, h = _parse_resolution_from_url(href)
                        full_url = urljoin(WW_BASE, href)
                        candidates.append((w, h, full_url))

                if not candidates:
                    continue

                # 按分辨率降序排列
                candidates.sort(key=lambda x: (x[0], x[1]), reverse=True)

                # 过滤：必须满足分辨率和宽高比（如果指定）
                best_w, best_h, best_url = 0, 0, ""
                for w, h, u in candidates:
                    if w < min_w or h < min_h:
                        continue
                    if target_ratio is not None and not aspect_ratio_ok(w, h, target_ratio, ratio_tolerance):
                        continue
                    best_w, best_h, best_url = w, h, u
                    break  # 取第一个（已排序，最大且比例匹配的）

                if not best_url:
                    continue

                fname = sanitize_filename(os.path.basename(urlparse(best_url).path))
                if not fname:
                    fname = sanitize_filename(detail_url.rstrip("/").rsplit("/", 1)[-1] + ".jpg")
                filepath = os.path.join(output_dir, fname)

                if download_one(session, best_url, filepath, hash_index, min_w, min_h, target_ratio, ratio_tolerance):
                    downloaded.append(filepath)
                    print(f"  ✅ [{len(downloaded)}/{target}] {fname} ({best_w}x{best_h})")

            except Exception as e:
                print(f"  ⚠️  跳过详情页: {e}")
                continue

        page += 1
        time.sleep(PAGE_DELAY)

    return downloaded


# ── Wallhaven 爬虫（保留，需翻墙）────────────────────────

def scrape_wallhaven_search(
    session: requests.Session,
    search_url_template: str,
    output_dir: str,
    target: int,
    hash_index: set,
    min_w: int,
    min_h: int,
    target_ratio: float | None = None,
    ratio_tolerance: float = 0.05,
) -> list:
    downloaded = []
    page = 1

    while len(downloaded) < target and page <= 30:
        url = search_url_template.format(page=page)
        print(f"  📄 Wallhaven 第 {page} 页...")

        try:
            soup = fetch_page(url, session)
        except Exception as e:
            print(f"  ⚠️  获取 Wallhaven 页面失败: {e}")
            break

        links = []
        for a in soup.select("a[href*='/wallpaper/']"):
            href = a.get("href", "")
            if re.search(r"/wallpaper/\w+$", href):
                links.append(urljoin("https://wallhaven.cc", href))
        links = list(dict.fromkeys(links))

        if not links:
            print(f"  ℹ️  没有更多壁纸")
            break

        for wp_url in links:
            if len(downloaded) >= target:
                break
            try:
                time.sleep(0.4)
                wp_soup = fetch_page(wp_url, session)
                img_tag = wp_soup.select_one("#wallpaper")
                if not img_tag:
                    continue
                img_url = img_tag.get("src", "")
                if not img_url:
                    continue

                fname = sanitize_filename(
                    os.path.basename(urlparse(img_url).path)
                    or f"wallhaven_{wp_url.rstrip('/').rsplit('/',1)[-1]}.jpg"
                )
                filepath = os.path.join(output_dir, fname)

                if download_one(session, img_url, filepath, hash_index, min_w, min_h, target_ratio, ratio_tolerance):
                    downloaded.append(filepath)
                    print(f"  ✅ [{len(downloaded)}/{target}] {fname}")
            except Exception as e:
                print(f"  ⚠️  跳过: {e}")
                continue

        page += 1
        time.sleep(PAGE_DELAY)

    return downloaded


# ── 通用爬虫 ────────────────────────────────────────────

def scrape_generic(
    session: requests.Session,
    url: str,
    output_dir: str,
    target: int,
    hash_index: set,
    min_w: int,
    min_h: int,
    target_ratio: float | None = None,
    ratio_tolerance: float = 0.05,
) -> list:
    discovered = set()
    crawled = set()
    pages = [url]

    while pages and len(discovered) < target * 5 and len(crawled) < 15:
        page_url = pages.pop(0)
        if page_url in crawled:
            continue
        crawled.add(page_url)
        print(f"  📄 爬取: {page_url}")

        try:
            soup = fetch_page(page_url, session)
        except Exception as e:
            print(f"  ⚠️  获取失败: {e}")
            continue

        for a in soup.find_all("a", href=True):
            full = urljoin(page_url, a["href"])
            if is_image_url(full):
                discovered.add(guess_full_url(full))

        for img in soup.find_all("img"):
            for attr in ("src", "data-src", "data-original", "data-full"):
                val = img.get(attr, "")
                if val and not val.startswith("data:"):
                    discovered.add(guess_full_url(urljoin(page_url, val)))
            srcset = img.get("srcset", "")
            if srcset:
                candidates = re.findall(r"(\S+)\s+(\d+)w", srcset)
                if candidates:
                    candidates.sort(key=lambda x: int(x[1]), reverse=True)
                    discovered.add(guess_full_url(urljoin(page_url, candidates[0][0])))

        for el in soup.find_all(style=True):
            bg = extract_style_url(el["style"])
            if bg:
                discovered.add(guess_full_url(urljoin(page_url, bg)))

        for meta in soup.find_all("meta"):
            prop = (meta.get("property") or "").lower()
            name = (meta.get("name") or "").lower()
            if prop in ("og:image", "twitter:image") or name in ("og:image", "twitter:image"):
                content = meta.get("content", "")
                if content:
                    discovered.add(guess_full_url(urljoin(page_url, content)))

        if len(discovered) < target * 3 and len(pages) < 10:
            for a in soup.find_all("a", href=True):
                text = a.get_text().strip().lower()
                cls = " ".join(a.get("class", [])).lower()
                if text in ("next", "»", "next page", "older", "›") or "next" in cls:
                    nxt = urljoin(page_url, a["href"])
                    if nxt not in crawled:
                        pages.append(nxt)

        time.sleep(PAGE_DELAY)

    print(f"\n  🔍 发现 {len(discovered)} 个候选 URL，开始下载...")
    urls = list(discovered)[: target * 3]
    downloaded = []

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futures = {}
        for img_url in urls:
            if len(downloaded) >= target:
                break
            parsed = urlparse(img_url)
            fname = sanitize_filename(
                os.path.basename(parsed.path)
                or parsed.path.strip("/").replace("/", "_")
                or "wallpaper"
            )
            if not any(fname.lower().endswith(e) for e in (".jpg", ".jpeg", ".png", ".webp", ".bmp")):
                fname += ".jpg"
            filepath = os.path.join(output_dir, fname)
            futures[
                pool.submit(download_one, session, img_url, filepath, hash_index, min_w, min_h, target_ratio, ratio_tolerance)
            ] = (fname, filepath)

        for fut in as_completed(futures):
            fname, filepath = futures[fut]
            try:
                if fut.result():
                    downloaded.append(filepath)
                    print(f"  ✅ [{len(downloaded)}/{target}] {fname}")
            except Exception as e:
                print(f"  ⚠️  下载失败 {fname}: {e}")
            if len(downloaded) >= target:
                break

    return downloaded


# ── 入口 ────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="🖼️  HD Wallpaper Scraper — 高清电脑壁纸爬虫"
    )
    parser.add_argument(
        "url", nargs="?", default=None,
        help="壁纸站 URL。不提供则自动多关键词搜索。",
    )
    parser.add_argument(
        "-o", "--output", default=DEFAULT_OUTPUT_DIR,
        help=f"保存目录（默认: {DEFAULT_OUTPUT_DIR}）",
    )
    parser.add_argument(
        "-n", "--count", type=int, default=TARGET_COUNT,
        help=f"下载数量（默认: {TARGET_COUNT}）",
    )
    parser.add_argument(
        "--min-width", type=int, default=MIN_WIDTH,
        help=f"最小宽度（默认: {MIN_WIDTH}）",
    )
    parser.add_argument(
        "--min-height", type=int, default=MIN_HEIGHT,
        help=f"最小高度（默认: {MIN_HEIGHT}）",
    )
    parser.add_argument(
        "--workers", type=int, default=MAX_WORKERS,
        help=f"并发数（默认: {MAX_WORKERS}）",
    )
    parser.add_argument(
        "-c", "--category", default=None,
        help=(
            "壁纸分类：风景/landscape, 美女/girl, 城市/city, 抽象/abstract, "
            "艺术, 游戏/game, 动漫/anime, 卡通/cartoon, 动物/animal, 汽车/car, "
            "太空/space, 极简/minimalist, 科技/tech, 自然/nature, 人物"
        ),
    )
    parser.add_argument(
        "-r", "--aspect-ratio", default=DEFAULT_ASPECT_RATIO,
        help=f"宽高比（默认: {DEFAULT_ASPECT_RATIO}，适用 MacBook 全系）。常用: 16:10, 16:9",
    )
    parser.add_argument(
        "--ratio-tolerance", type=float, default=0.05,
        help="宽高比容差（默认: 0.05，即 ±5%）",
    )
    parser.add_argument(
        "--queries", nargs="*", default=None,
        help="自定义搜索关键词列表（覆盖 --category）",
    )
    parser.add_argument(
        "--list-categories", action="store_true",
        help="列出所有可用分类",
    )

    args = parser.parse_args()

    # 列出分类
    if args.list_categories:
        seen = set()
        print("📂 可用分类：")
        for key, keywords in CATEGORY_KEYWORDS.items():
            if key in seen:
                continue
            seen.add(key)
            # 只列英文名（中文名放一起）
        # 按类型分组显示
        groups: dict[str, list[str]] = {}
        for k in CATEGORY_KEYWORDS:
            v = CATEGORY_KEYWORDS[k]
            # 用第一个关键词作为分组标识
            group = v[0].split()[0] if v else "other"
            if group not in groups:
                groups[group] = []
            if k not in groups[group]:
                groups[group].append(k)
        for g, names in sorted(groups.items()):
            print(f"  {g}: {', '.join(names)}")
        return

    # 解析宽高比
    target_ratio = _parse_aspect_ratio(args.aspect_ratio)
    if target_ratio is None:
        print(f"⚠️  无法解析宽高比 \"{args.aspect_ratio}\"，使用默认 16:10")
        target_ratio = _parse_aspect_ratio(DEFAULT_ASPECT_RATIO)

    output_dir = os.path.expanduser(args.output)
    ensure_dir(output_dir)

    print("━" * 50)
    print("🖼️  HD Wallpaper Scraper")
    print(f"📁 保存目录 : {output_dir}")
    print(f"📐 最低分辨率: {args.min_width}x{args.min_height}")
    print(f"📐 宽高比    : {args.aspect_ratio} (±{args.ratio_tolerance:.0%})")
    print(f"🎯 目标数量  : {args.count} 张")
    print(f"🔍 去重方式  : SHA-256 哈希")
    if args.url:
        print(f"🔗 目标 URL  : {args.url}")
    else:
        if args.category:
            print(f"🏷️  分类      : {args.category}")
        else:
            queries = args.queries or DEFAULT_QUERIES
            print(f"🌐 模式      : 自动多关键词 ({len(queries)} 个)")
    print("━" * 50 + "\n")

    print("📊 扫描已有壁纸...")
    hash_index = build_hash_index(output_dir)
    print(f"📊 已存在 {len(hash_index)} 个唯一壁纸\n")

    session = requests.Session()
    session.headers.update(HEADERS)

    all_downloaded = []

    try:
        if args.url:
            # ── URL 模式（不变）──
            parsed = urlparse(args.url)
            domain = parsed.netloc.lower()

            if "wallpaperswide.com" in domain:
                print("🏷️  检测到 WallpapersWide，使用专用爬虫\n")
                if "/search" in args.url:
                    tmpl = re.sub(r"page=\d+", "page={page}", args.url)
                    if "{page}" not in tmpl:
                        tmpl = args.url + ("&" if "?" in args.url else "?") + "page={page}"
                else:
                    tmpl = args.url
                    if "{page}" not in tmpl:
                        tmpl = args.url + ("&" if "?" in args.url else "?") + "page={page}"
                all_downloaded = scrape_wallpaperswide(
                    session, tmpl, output_dir, args.count, hash_index,
                    args.min_width, args.min_height,
                    target_ratio, args.ratio_tolerance,
                )

            elif "wallhaven.cc" in domain and "/search" in args.url:
                print("🏷️  检测到 Wallhaven 搜索页\n")
                tmpl = re.sub(r"page=\d+", "page={page}", args.url)
                if "{page}" not in tmpl:
                    tmpl = args.url + ("&" if "?" in args.url else "?") + "page={page}"
                all_downloaded = scrape_wallhaven_search(
                    session, tmpl, output_dir, args.count, hash_index,
                    args.min_width, args.min_height,
                    target_ratio, args.ratio_tolerance,
                )

            else:
                print("🌐 通用爬取模式\n")
                all_downloaded = scrape_generic(
                    session, args.url, output_dir, args.count, hash_index,
                    args.min_width, args.min_height,
                    target_ratio, args.ratio_tolerance,
                )
        else:
            # ── 自动模式：确定关键词列表 ──
            if args.queries:
                queries = args.queries
                source_label = "自定义关键词"
            elif args.category:
                cat_key = args.category.strip()
                queries = CATEGORY_KEYWORDS.get(cat_key)
                if queries is None:
                    # 模糊匹配：在所有 key 里找包含用户输入的
                    matches = [v for k, v in CATEGORY_KEYWORDS.items() if cat_key in k]
                    if matches:
                        queries = matches[0]
                        cat_key = [k for k, v in CATEGORY_KEYWORDS.items() if cat_key in k][0]
                        print(f"🔍 匹配到分类: \"{cat_key}\"\n")
                if queries is None:
                    print(f"⚠️  未知分类 \"{args.category}\"，回退到默认模式\n")
                    print(f"💡 可用分类: {', '.join(sorted(set(CATEGORY_KEYWORDS.keys())))}\n")
                    queries = DEFAULT_QUERIES
                    source_label = "默认（多关键词）"
                else:
                    source_label = f"分类: {cat_key}"
            else:
                queries = DEFAULT_QUERIES
                source_label = "默认（多关键词）"

            total = args.count
            per_query = max(8, total // len(queries))

            print(f"🔑 {source_label} — {len(queries)} 个关键词，每个目标 ~{per_query} 张\n")

            for i, q in enumerate(queries):
                if len(all_downloaded) >= total:
                    break
                remaining = total - len(all_downloaded)
                q_target = min(per_query, remaining)

                print(f"🔑 [{i+1}/{len(queries)}] 关键词: \"{q}\" (目标 {q_target} 张)")
                search_url = WW_SEARCH.format(query=q.replace(" ", "+"), page="{page}")

                batch = scrape_wallpaperswide(
                    session, search_url, output_dir, q_target, hash_index,
                    args.min_width, args.min_height,
                    target_ratio, args.ratio_tolerance,
                )
                all_downloaded.extend(batch)

                if len(all_downloaded) < total:
                    remaining = total - len(all_downloaded)
                    print(f"  📢 已获取 {len(all_downloaded)}/{total}，还需 {remaining} 张\n")
    finally:
        session.close()

    # 清理残留 .tmp
    for f in os.listdir(output_dir):
        if f.endswith(".tmp"):
            try:
                os.remove(os.path.join(output_dir, f))
            except OSError:
                pass

    print("\n" + "━" * 50)
    print(f"✅ 完成！共下载 {len(all_downloaded)} 张壁纸")
    if all_downloaded:
        print(f"📁 {output_dir}")
    if len(all_downloaded) < args.count:
        print(f"⚠️  未达目标，差 {args.count - len(all_downloaded)} 张（可用源已耗尽）")
    print("━" * 50)


if __name__ == "__main__":
    main()
