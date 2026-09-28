from __future__ import annotations
#!/usr/bin/env python3
"""
HD Wallpaper Scraper — 高清电脑壁纸爬虫
自动模式优先链：Bing API → toopic.cn → WallpapersWide（需翻墙）
"""

import argparse
import hashlib
import os
import re
import threading
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
MAX_WORKERS = 8
DETAIL_WORKERS = 12       # 并发 fetch detail 页的线程数
REQUEST_TIMEOUT = 20
PAGE_DELAY = 0.3          # 翻页间隔（秒）
DETAIL_DELAY = 0.1        # detail 页请求间隔（秒，并发下已很短）
MIN_FILE_SIZE = 50_000

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    "Referer": "https://www.google.com/",
}

# ── 源配置 ─────────────────────────────────────────────
TOOPIC_BASE = "https://www.toopic.cn"
TOOPIC_LIST = TOOPIC_BASE + "/4kbz/"   # 4K 壁纸总列表，?page=N 翻页
WW_BASE = "https://wallpaperswide.com"
WW_SEARCH = WW_BASE + "/search.html?q={query}&page={page}"

_hash_lock = threading.Lock()

# Bing 市场列表
BING_MARKETS = ["zh-CN", "en-US", "ja-JP", "de-DE", "fr-FR", "ko-KR", "pt-BR"]

# WallpapersWide 分类关键词（URL 模式 / 翻墙备用）
CATEGORY_KEYWORDS: dict[str, list[str]] = {
    "风景":   ["nature landscape", "mountains lake", "ocean sunset", "forest path",
               "waterfall river", "desert dunes", "autumn forest", "snowy winter"],
    "landscape": ["nature landscape", "mountains lake", "ocean sunset", "forest path"],
    "自然":   ["nature landscape", "mountains lake", "ocean sunset", "forest path"],
    "nature": ["nature landscape", "mountains lake", "ocean sunset"],
    "美女":   ["girl model", "beautiful woman", "female portrait", "fashion model"],
    "girl":   ["girl model", "beautiful woman", "female portrait"],
    "城市":   ["city night", "cityscape skyline", "urban street", "architecture modern"],
    "city":   ["city night", "cityscape skyline", "urban street"],
    "抽象":   ["abstract art", "digital art colorful", "fractal pattern", "geometric shapes"],
    "abstract": ["abstract art", "digital art colorful", "fractal pattern"],
    "游戏":   ["video game", "gaming art", "cyberpunk game", "fantasy game"],
    "game":   ["video game", "gaming art", "cyberpunk game"],
    "动漫":   ["anime art", "anime girl", "anime landscape", "japanese anime"],
    "anime":  ["anime art", "anime girl", "anime landscape"],
    "动物":   ["wildlife animal", "cat kitten", "dog puppy", "tiger lion"],
    "animal": ["wildlife animal", "cat kitten", "dog puppy"],
    "汽车":   ["sports car", "luxury car", "racing car", "vintage car"],
    "car":    ["sports car", "luxury car", "racing car"],
    "太空":   ["space stars", "galaxy nebula", "planet space", "milky way"],
    "space":  ["space stars", "galaxy nebula", "planet space"],
    "极简":   ["minimalist gradient", "simple background", "clean minimal"],
    "minimalist": ["minimalist gradient", "simple background"],
    "科技":   ["technology future", "digital technology", "circuit board"],
    "tech":   ["technology future", "digital technology"],
}

DEFAULT_QUERIES = [
    "nature landscape", "city night", "abstract art",
    "mountains lake", "space stars", "ocean sunset",
    "forest path", "minimalist gradient",
]


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


def fetch_page(url: str, session: requests.Session, encoding: str | None = None) -> BeautifulSoup:
    resp = session.get(url, timeout=REQUEST_TIMEOUT, verify=False)
    resp.raise_for_status()
    if encoding:
        resp.encoding = encoding
    elif resp.encoding and resp.encoding.lower() in ("iso-8859-1", "latin-1"):
        resp.encoding = resp.apparent_encoding
    return BeautifulSoup(resp.text, "html.parser")


def is_image_url(url: str) -> bool:
    path = urlparse(url.lower()).path
    return any(path.endswith(ext) for ext in (".jpg", ".jpeg", ".png", ".webp", ".bmp"))


def extract_style_url(style: str) -> str | None:
    m = re.search(r'url\(["\']?([^"\'()]+)["\']?\)', style)
    return m.group(1) if m else None


def guess_full_url(img_url: str) -> str:
    img_url = re.sub(r"https?://th\.wallhaven\.cc/small/", "https://w.wallhaven.cc/full/", img_url)
    img_url = re.sub(r"\?.*$", "", img_url)
    img_url = re.sub(r"[-_](small|thumb|thumbnail|preview)(?=\.\w+$)", "", img_url, flags=re.I)
    return img_url


def _parse_aspect_ratio(ar_str: str) -> float | None:
    parts = ar_str.strip().split(":")
    if len(parts) == 2:
        try:
            w, h = float(parts[0]), float(parts[1])
            if h > 0:
                return w / h
        except ValueError:
            pass
    return None


def aspect_ratio_ok(w: int, h: int, target_ratio: float, tolerance: float) -> bool:
    if h == 0:
        return False
    return abs(w / h - target_ratio) <= tolerance


def validate_dimensions(
    filepath: str,
    min_w: int,
    min_h: int,
    target_ratio: float | None,
    ratio_tolerance: float,
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
    target_ratio: float | None,
    ratio_tolerance: float,
    referer: str = "",
) -> bool:
    if os.path.exists(filepath):
        h = file_hash(filepath)
        if h and h in hash_index:
            return False

    tmp = filepath + ".tmp"
    try:
        hdrs = {**HEADERS}
        if referer:
            hdrs["Referer"] = referer
        resp = session.get(img_url, headers=hdrs, timeout=REQUEST_TIMEOUT, stream=True, verify=False)
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

        with _hash_lock:
            if h in hash_index:
                os.remove(tmp)
                return False
            ext = os.path.splitext(filepath)[1] or ".jpg"  # filepath 非 .tmp 路径
            final_path = os.path.join(os.path.dirname(os.path.abspath(filepath)), h + ext)
            hash_index.add(h)
        os.rename(tmp, final_path)
        return True

    except Exception:
        if os.path.exists(tmp):
            os.remove(tmp)
        return False


# ── Bing 壁纸 API ──────────────────────────────────────

def scrape_bing(
    session: requests.Session,
    output_dir: str,
    target: int,
    hash_index: set,
    min_w: int,
    min_h: int,
    target_ratio: float | None,
    ratio_tolerance: float,
    workers: int,
) -> list:
    """Bing 壁纸 API：直接返回 UHD URL，无需解析页面，速度最快。"""
    seen_ids: set = set()
    candidates: list[tuple[str, str]] = []  # (url, label)

    for market in BING_MARKETS:
        for idx in range(0, 48, 8):
            try:
                api = (
                    f"https://www.bing.com/HPImageArchive.aspx"
                    f"?format=js&idx={idx}&n=8&mkt={market}"
                )
                r = session.get(api, timeout=10, verify=False)
                for img in r.json().get("images", []):
                    raw = img["url"]
                    uhd = re.sub(r"\d{3,4}x\d{3,4}", "UHD", raw)
                    uid = re.search(r"id=([^&]+)", uhd)
                    uid_str = uid.group(1) if uid else uhd
                    if uid_str not in seen_ids:
                        seen_ids.add(uid_str)
                        url = "https://www.bing.com" + uhd
                        label = img.get("copyright", "")[:50]
                        candidates.append((url, label))
            except Exception:
                pass

    if not candidates:
        print("  ⚠️  Bing API 无法访问，跳过")
        return []

    print(f"  🔍 Bing: 发现 {len(candidates)} 张候选（已去重）")
    downloaded: list[str] = []

    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures: dict = {}
        for i, (url, label) in enumerate(candidates[:target * 2]):
            uid = re.search(r"id=OHR\.(\w+)_", url)
            fname = (uid.group(1) if uid else f"bing_{i:04d}") + ".jpg"
            filepath = os.path.join(output_dir, fname)
            futures[pool.submit(
                download_one, session, url, filepath, hash_index,
                min_w, min_h, target_ratio, ratio_tolerance
            )] = (fname, label)

        for fut in as_completed(futures):
            fname, label = futures[fut]
            try:
                if fut.result():
                    downloaded.append(fname)
                    print(f"  ✅ [{len(downloaded)}/{target}] {fname}  {label}")
            except Exception:
                pass
            if len(downloaded) >= target:
                break

    return downloaded


# ── toopic.cn 爬虫（并发 detail 页）──────────────────

_TOOPIC_IMG_RE = re.compile(
    r'(?:["\']|url\(|:)\s*('
    + re.escape(TOOPIC_BASE)
    + r'/public/uploads/image/[^"\'()\s,;]+\.(?:jpg|png|webp))',
    re.I,
)

_TOOPIC_DETAIL_RE = re.compile(r'https?://www\.toopic\.cn/4kbz/\d+\.html')
_MAX_TOOPIC_PAGES = 50


def _toopic_img_url(detail_url: str, session: requests.Session) -> str | None:
    """从 toopic detail 页 JS 中提取原图 URL（无需登录）。"""
    try:
        r = session.get(detail_url, timeout=REQUEST_TIMEOUT, verify=False)
        r.raise_for_status()
        m = _TOOPIC_IMG_RE.search(r.text)
        return m.group(1) if m else None
    except Exception:
        return None


def _toopic_collect_links(session: requests.Session, need: int) -> list[str]:
    """翻页收集 toopic detail 链接，直到数量足够或到达末页。"""
    links: list[str] = []
    page = 1
    while len(links) < need and page <= _MAX_TOOPIC_PAGES:
        url = TOOPIC_LIST if page == 1 else f"{TOOPIC_LIST}?page={page}"
        try:
            soup = fetch_page(url, session)
            prev_count = len(links)
            for a in soup.find_all("a", href=True):
                href = a["href"]
                if _TOOPIC_DETAIL_RE.match(href) and href not in links:
                    links.append(href)
            if len(links) == prev_count:  # 本页无新链接，视为末页
                break
            time.sleep(PAGE_DELAY)
            page += 1
        except Exception as e:
            print(f"  ⚠️  toopic 第 {page} 页失败: {e}")
            break
    return links


def scrape_toopic(
    session: requests.Session,
    output_dir: str,
    target: int,
    hash_index: set,
    min_w: int,
    min_h: int,
    target_ratio: float | None,
    ratio_tolerance: float,
    workers: int,
) -> list:
    """
    toopic.cn 并发爬虫（原图无需登录，约 1.9MB/张 4K）：
    1. 翻页收集 detail 链接
    2. 并发 fetch detail 页提取原图 URL（DETAIL_WORKERS 线程）
    3. 并发下载（workers 线程）
    """
    need = int(target * 2.5)
    print(f"  📄 toopic: 收集候选链接（目标 {target} 张）...")
    detail_links = _toopic_collect_links(session, need)
    print(f"  📄 toopic: 共 {len(detail_links)} 个 detail 链接，并发提取图片 URL...")

    # img_urls 仅在主线程（as_completed 迭代中）追加，无并发写入
    img_urls: list[str] = []
    with ThreadPoolExecutor(max_workers=DETAIL_WORKERS) as pool:
        futs = {pool.submit(_toopic_img_url, u, session): u for u in detail_links}
        for fut in as_completed(futs):
            url = fut.result()
            if url:
                img_urls.append(url)

    print(f"  🔍 toopic: 获得 {len(img_urls)} 个原图 URL，开始并发下载...")
    downloaded: list[str] = []

    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures: dict = {}
        for img_url in img_urls[:target * 2]:
            uid = re.search(r"/image/(\d+)/(\d+)", img_url)
            if uid:
                suffix = f"{uid.group(1)}_{uid.group(2)}"
            else:
                parts = [p for p in urlparse(img_url).path.split("/") if p]
                suffix = "_".join(parts[-2:]) if len(parts) >= 2 else f"{abs(hash(img_url)):08x}"
            ext = os.path.splitext(urlparse(img_url).path)[1] or ".jpg"
            fname = f"toopic_{suffix}{ext}"
            filepath = os.path.join(output_dir, fname)
            futures[pool.submit(
                download_one, session, img_url, filepath, hash_index,
                min_w, min_h, target_ratio, ratio_tolerance, TOOPIC_BASE
            )] = fname

        for fut in as_completed(futures):
            fname = futures[fut]
            try:
                if fut.result():
                    downloaded.append(fname)
                    print(f"  ✅ [{len(downloaded)}/{target}] {fname}")
            except Exception:
                pass
            if len(downloaded) >= target:
                break

    return downloaded


# ── WallpapersWide 爬虫（保留，需翻墙）────────────────

def _parse_resolution_from_url(url: str) -> tuple[int, int]:
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
    target_ratio: float | None,
    ratio_tolerance: float,
) -> list:
    downloaded: list[str] = []
    page = 1

    while len(downloaded) < target and page <= 8:
        url = search_url_template.format(page=page)
        print(f"  📄 WallpapersWide 第 {page} 页: {url.split('q=')[-1].split('&')[0][:40]}")

        try:
            soup = fetch_page(url, session)
        except Exception as e:
            print(f"  ⚠️  获取失败: {e}")
            break

        wall_items = soup.select("li.wall")
        if not wall_items:
            break

        detail_urls = []
        for item in wall_items:
            a_tag = item.select_one(".thumb a[href*='-wallpapers.html']")
            if a_tag:
                detail_urls.append(urljoin(WW_BASE, a_tag["href"]))

        for detail_url in detail_urls:
            if len(downloaded) >= target:
                break
            try:
                time.sleep(0.3)
                d_soup = fetch_page(detail_url, session)
                candidates = []
                for a in d_soup.select("#top-resolutions a[href*='/download/'], .wallpaper-resolutions a[href*='/download/']"):
                    href = a.get("href", "")
                    if is_image_url(href):
                        w, h = _parse_resolution_from_url(href)
                        candidates.append((w, h, urljoin(WW_BASE, href)))

                candidates.sort(key=lambda x: (x[0], x[1]), reverse=True)
                for w, h, u in candidates:
                    if w < min_w or h < min_h:
                        continue
                    if target_ratio is not None and not aspect_ratio_ok(w, h, target_ratio, ratio_tolerance):
                        continue
                    fname = sanitize_filename(os.path.basename(urlparse(u).path)) or f"ww_{page}.jpg"
                    filepath = os.path.join(output_dir, fname)
                    if download_one(session, u, filepath, hash_index, min_w, min_h, target_ratio, ratio_tolerance):
                        downloaded.append(filepath)
                        print(f"  ✅ [{len(downloaded)}/{target}] {fname} ({w}x{h})")
                    break
            except Exception as e:
                print(f"  ⚠️  跳过详情页: {e}")

        page += 1
        time.sleep(1.0)

    return downloaded


# ── Wallhaven 爬虫（需翻墙）───────────────────────────

def scrape_wallhaven_search(
    session: requests.Session,
    search_url_template: str,
    output_dir: str,
    target: int,
    hash_index: set,
    min_w: int,
    min_h: int,
    target_ratio: float | None,
    ratio_tolerance: float,
) -> list:
    downloaded: list[str] = []
    page = 1

    while len(downloaded) < target and page <= 30:
        url = search_url_template.format(page=page)
        print(f"  📄 Wallhaven 第 {page} 页...")
        try:
            soup = fetch_page(url, session)
        except Exception as e:
            print(f"  ⚠️  Wallhaven 页面失败: {e}")
            break

        links = list(dict.fromkeys(
            urljoin("https://wallhaven.cc", a["href"])
            for a in soup.select("a[href*='/wallpaper/']")
            if re.search(r"/wallpaper/\w+$", a.get("href", ""))
        ))

        if not links:
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
                fname = sanitize_filename(os.path.basename(urlparse(img_url).path) or "wallhaven.jpg")
                filepath = os.path.join(output_dir, fname)
                if download_one(session, img_url, filepath, hash_index, min_w, min_h, target_ratio, ratio_tolerance):
                    downloaded.append(filepath)
                    print(f"  ✅ [{len(downloaded)}/{target}] {fname}")
            except Exception as e:
                print(f"  ⚠️  跳过: {e}")

        page += 1
        time.sleep(1.0)

    return downloaded


# ── 通用爬虫（任意 URL）───────────────────────────────

def scrape_generic(
    session: requests.Session,
    url: str,
    output_dir: str,
    target: int,
    hash_index: set,
    min_w: int,
    min_h: int,
    target_ratio: float | None,
    ratio_tolerance: float,
    workers: int,
) -> list:
    discovered: set = set()
    crawled: set = set()
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
                cands = re.findall(r"(\S+)\s+(\d+)w", srcset)
                if cands:
                    cands.sort(key=lambda x: int(x[1]), reverse=True)
                    discovered.add(guess_full_url(urljoin(page_url, cands[0][0])))

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

        time.sleep(1.0)

    print(f"\n  🔍 发现 {len(discovered)} 个候选 URL，开始下载...")
    downloaded: list[str] = []

    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures: dict = {}
        for img_url in list(discovered)[:target * 3]:
            parsed = urlparse(img_url)
            fname = sanitize_filename(
                os.path.basename(parsed.path) or parsed.path.strip("/").replace("/", "_") or "wallpaper"
            )
            if not any(fname.lower().endswith(e) for e in (".jpg", ".jpeg", ".png", ".webp", ".bmp")):
                fname += ".jpg"
            filepath = os.path.join(output_dir, fname)
            futures[pool.submit(
                download_one, session, img_url, filepath, hash_index,
                min_w, min_h, target_ratio, ratio_tolerance
            )] = (fname, filepath)

        for fut in as_completed(futures):
            fname, _ = futures[fut]
            try:
                if fut.result():
                    downloaded.append(fname)
                    print(f"  ✅ [{len(downloaded)}/{target}] {fname}")
            except Exception as e:
                print(f"  ⚠️  下载失败 {fname}: {e}")
            if len(downloaded) >= target:
                break

    return downloaded


# ── 入口 ────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="🖼️  HD Wallpaper Scraper — 高清电脑壁纸爬虫")
    parser.add_argument("url", nargs="?", default=None, help="壁纸站 URL（不提供则自动模式）")
    parser.add_argument("-o", "--output", default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("-n", "--count", type=int, default=TARGET_COUNT)
    parser.add_argument("--min-width", type=int, default=MIN_WIDTH)
    parser.add_argument("--min-height", type=int, default=MIN_HEIGHT)
    parser.add_argument("--workers", type=int, default=MAX_WORKERS)
    parser.add_argument("-c", "--category", default=None,
        help="分类：风景/landscape/自然/美女/girl/城市/city/动漫/anime/游戏/game/汽车/car/动物/animal/太空/space/抽象/极简/科技"
    )
    parser.add_argument("-r", "--aspect-ratio", default=None,
        help="宽高比过滤，如 16:10、16:9。默认不过滤（Bing/toopic 均为 16:9 4K，强过滤会全拦）"
    )
    parser.add_argument("--ratio-tolerance", type=float, default=0.05)
    parser.add_argument("--queries", nargs="*", default=None,
        help="自定义 WallpapersWide 搜索词（需翻墙）"
    )
    parser.add_argument("--list-categories", action="store_true")
    parser.add_argument("--source", choices=["auto", "bing", "toopic", "wallpaperswide"],
        default="auto", help="强制指定源（默认 auto = bing→toopic）"
    )

    args = parser.parse_args()

    if args.list_categories:
        print("📂 WallpapersWide 分类（需翻墙）：")
        for k in CATEGORY_KEYWORDS:
            print(f"  {k}")
        return

    target_ratio = _parse_aspect_ratio(args.aspect_ratio) if args.aspect_ratio else None

    output_dir = os.path.expanduser(args.output)
    ensure_dir(output_dir)

    print("━" * 52)
    print("🖼️  HD Wallpaper Scraper")
    print(f"📁 保存目录   : {output_dir}")
    print(f"📐 最低分辨率 : {args.min_width}x{args.min_height}")
    if target_ratio:
        print(f"📐 宽高比     : {args.aspect_ratio} (±{args.ratio_tolerance:.0%})")
    else:
        print("📐 宽高比     : 不过滤")
    print(f"🎯 目标数量   : {args.count} 张")
    if args.url:
        print(f"🔗 目标 URL   : {args.url}")
    elif args.category:
        print(f"🏷️  分类       : {args.category}")
    else:
        print(f"🌐 模式       : {args.source}")
    print("━" * 52 + "\n")

    print("📊 扫描已有壁纸...")
    hash_index = build_hash_index(output_dir)
    print(f"📊 已存在 {len(hash_index)} 张\n")

    import warnings
    warnings.filterwarnings("ignore")  # 屏蔽 SSL verify=False 警告

    session = requests.Session()
    session.headers.update(HEADERS)

    all_downloaded: list[str] = []

    try:
        if args.url:
            domain = urlparse(args.url).netloc.lower()
            if "wallpaperswide.com" in domain:
                print("🏷️  WallpapersWide 模式\n")
                tmpl = re.sub(r"page=\d+", "page={page}", args.url)
                if "{page}" not in tmpl:
                    tmpl += ("&" if "?" in tmpl else "?") + "page={page}"
                all_downloaded = scrape_wallpaperswide(
                    session, tmpl, output_dir, args.count, hash_index,
                    args.min_width, args.min_height, target_ratio, args.ratio_tolerance,
                )
            elif "wallhaven.cc" in domain:
                print("🏷️  Wallhaven 模式\n")
                tmpl = re.sub(r"page=\d+", "page={page}", args.url)
                if "{page}" not in tmpl:
                    tmpl += ("&" if "?" in tmpl else "?") + "page={page}"
                all_downloaded = scrape_wallhaven_search(
                    session, tmpl, output_dir, args.count, hash_index,
                    args.min_width, args.min_height, target_ratio, args.ratio_tolerance,
                )
            elif "toopic.cn" in domain:
                print("🏷️  toopic 模式\n")
                all_downloaded = scrape_toopic(
                    session, output_dir, args.count, hash_index,
                    args.min_width, args.min_height, target_ratio, args.ratio_tolerance,
                    args.workers,
                )
            else:
                print("🌐 通用爬取模式\n")
                all_downloaded = scrape_generic(
                    session, args.url, output_dir, args.count, hash_index,
                    args.min_width, args.min_height, target_ratio, args.ratio_tolerance,
                    args.workers,
                )
        else:
            # ── 自动模式 ──
            total = args.count
            cat = (args.category or "").strip()

            use_bing = args.source in ("auto", "bing")
            use_toopic = args.source in ("auto", "toopic")

            if use_bing:
                print("🌐 [1/2] Bing 壁纸 API...")
                bing_batch = scrape_bing(
                    session, output_dir, total, hash_index,
                    args.min_width, args.min_height,
                    target_ratio, args.ratio_tolerance, args.workers,
                )
                all_downloaded.extend(bing_batch)
                print(f"  📊 Bing 获取 {len(bing_batch)} 张，合计 {len(all_downloaded)}/{total}\n")

            if use_toopic and len(all_downloaded) < total:
                remaining = total - len(all_downloaded)
                print(f"🌐 [2/2] toopic.cn 4K 壁纸（还需 {remaining} 张）...")
                tp_batch = scrape_toopic(
                    session, output_dir, remaining, hash_index,
                    args.min_width, args.min_height,
                    target_ratio, args.ratio_tolerance, args.workers,
                )
                all_downloaded.extend(tp_batch)
                print(f"  📊 toopic 获取 {len(tp_batch)} 张，合计 {len(all_downloaded)}/{total}\n")

            if args.source == "wallpaperswide":
                queries = args.queries or CATEGORY_KEYWORDS.get(cat, DEFAULT_QUERIES)
                per_q = max(8, total // len(queries))
                for i, q in enumerate(queries):
                    if len(all_downloaded) >= total:
                        break
                    remaining = total - len(all_downloaded)
                    print(f"🔑 [{i+1}/{len(queries)}] \"{q}\" (目标 {min(per_q, remaining)} 张)")
                    tmpl = WW_SEARCH.format(query=q.replace(" ", "+"), page="{page}")
                    batch = scrape_wallpaperswide(
                        session, tmpl, output_dir, min(per_q, remaining), hash_index,
                        args.min_width, args.min_height, target_ratio, args.ratio_tolerance,
                    )
                    all_downloaded.extend(batch)

    finally:
        session.close()
        for f in os.listdir(output_dir):
            if f.endswith(".tmp"):
                try:
                    os.remove(os.path.join(output_dir, f))
                except OSError:
                    pass

    print("━" * 52)
    print(f"✅ 完成！共下载 {len(all_downloaded)} 张壁纸")
    if all_downloaded:
        print(f"📁 {output_dir}")
    if len(all_downloaded) < args.count:
        print(f"⚠️  未达目标，差 {args.count - len(all_downloaded)} 张")
    print("━" * 52)


if __name__ == "__main__":
    main()
