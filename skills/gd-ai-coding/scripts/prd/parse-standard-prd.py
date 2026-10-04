#!/usr/bin/env python3
"""Parse a standard「需求文档梳理」Cooper Markdown into prd-extract.json.

Exit 0: wrote extract (需求列表 7 标准列齐全)
Exit 2: not standard — caller should fall back to pre-trim
Exit 1: usage / IO error
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

FEATURE_COLS = [
    "功能/页面名",
    "线上图",
    "需求图",
    "UI 链接",
    "需求详情",
    "API 接口名",
    "API 字段",
]
COLLAB_COLS = ["方向", "负责人", "文档", "备注"]
SCOPE_COLS = ["维度", "范围说明"]
TRACK_COLS = [
    "页面中文名称",
    "埋点中文名称",
    "图片",
    "上报时机",
    "是否老点位",
    "event_id",
    "参数",
]
ALL_STD_COLS = tuple(
    dict.fromkeys(FEATURE_COLS + COLLAB_COLS + SCOPE_COLS + TRACK_COLS)
)
# Longer names first so "API 接口名" wins over a hypothetical shorter prefix.
_STD_COLS_BY_LEN = tuple(sorted(ALL_STD_COLS, key=len, reverse=True))

BR_RE = re.compile(r"<br\s*/?>", re.I)
BOLD_RE = re.compile(r"\*\*")
TICK_RE = re.compile(r"`")
IMG_MD_RE = re.compile(r"!\[([^\]]*)\]\(([^)]+)\)")
IMG_HTML_RE = re.compile(r"<img[^>]+src=['\"]([^'\"]+)['\"]", re.I)
MD_LINK_RE = re.compile(r"\[([^\]]*)\]\((https?://[^)]+)\)")
BARE_URL_RE = re.compile(r"https?://[^\s<>\]）]+")
SEP_ROW_RE = re.compile(r"^[\s|:\-]+$")

YES_VALS = {"是", "y", "yes", "true", "1"}
NO_VALS = {"否", "n", "no", "false", "0"}


def norm_header(raw: str) -> str:
    s = BR_RE.sub("", raw)
    s = BOLD_RE.sub("", s)
    s = TICK_RE.sub("", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def _header_suffix_ok(rest: str) -> bool:
    """True if remainder is empty or an annotation, not a glued-on word.

    `UI 链接 「Mastergo…」` / `需求详情（和端相关）` match; `需求详情补充` does not.
    """
    return rest == "" or not (rest[0].isalnum() or rest[0] == "_")


def canonical_header(raw: str) -> str:
    """Map a normalized header to a standard column name.

    Exact equality still wins. Otherwise the header may start with a standard
    name followed by a quote / paren / space + explanation.
    """
    h = norm_header(raw) if raw else ""
    if not h:
        return h
    if h in ALL_STD_COLS:
        return h
    for col in _STD_COLS_BY_LEN:
        if h.startswith(col) and _header_suffix_ok(h[len(col) :]):
            return col
    return h


def br_to_nl(raw: str) -> str:
    return BR_RE.sub("\n", raw)


def cell_empty(raw: str) -> bool:
    s = BR_RE.sub("", raw or "")
    s = re.sub(r"\s+", "", s)
    return s == "" or s == "无"


def cell_text(raw: str) -> str:
    if cell_empty(raw):
        return ""
    s = br_to_nl(raw)
    s = s.replace("\t", "    ")
    s = re.sub(r"\n{3,}", "\n\n", s)
    return s.strip()


def norm_name(raw: str) -> str:
    return re.sub(r"\s+", " ", cell_text(raw)).strip()


def split_row(line: str) -> list[str]:
    line = line.rstrip("\n")
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [c.strip() for c in line.split("|")]


def iter_tables(md: str) -> list[dict[str, Any]]:
    lines = md.splitlines()
    tables: list[dict[str, Any]] = []
    i = 0
    last_heading = ""
    while i < len(lines):
        m = re.match(r"^#{1,6}\s+(.*)$", lines[i])
        if m:
            last_heading = m.group(1).strip()
        if not lines[i].lstrip().startswith("|"):
            i += 1
            continue
        block = []
        while i < len(lines) and lines[i].lstrip().startswith("|"):
            block.append(lines[i])
            i += 1
        if len(block) < 2:
            continue
        headers = [canonical_header(c) for c in split_row(block[0])]
        if not any(headers):
            continue
        start = 1
        if SEP_ROW_RE.match(block[1].replace("|", "").replace(" ", "")) or set(
            block[1].replace(" ", "")
        ) <= {"|", "-", ":"}:
            start = 2
        rows = []
        for raw in block[start:]:
            cells = split_row(raw)
            if all(not c.strip() or SEP_ROW_RE.match(c.replace(" ", "")) for c in cells):
                continue
            while len(cells) < len(headers):
                cells.append("")
            row = {}
            extra = {}
            for idx, h in enumerate(headers):
                val = cells[idx] if idx < len(cells) else ""
                if h:
                    if h in row:
                        extra[f"{h}#{idx}"] = val
                    else:
                        row[h] = val
                else:
                    extra[f"col_{idx}"] = val
            if extra:
                row["_extra"] = extra
            rows.append(row)
        tables.append({"heading": last_heading, "headers": headers, "rows": rows})
    return tables


def classify_table(headers: list[str]) -> str | None:
    hset = set(headers)
    if set(FEATURE_COLS) <= hset:
        return "features"
    if set(COLLAB_COLS) <= hset:
        return "collaborators"
    if set(SCOPE_COLS) <= hset:
        return "scope"
    if set(TRACK_COLS) <= hset:
        return "trackings"
    return None


def extract_images(cell: str) -> tuple[list[dict[str, str]], str]:
    note_parts = []
    images: list[dict[str, str]] = []
    seen = set()

    def add(url: str, alt: str = "") -> None:
        url = url.strip()
        if not url or url in seen:
            return
        seen.add(url)
        images.append({"url": url, "alt": alt})

    rest = cell
    for m in IMG_MD_RE.finditer(cell):
        add(m.group(2), m.group(1))
    rest = IMG_MD_RE.sub("", rest)
    for m in IMG_HTML_RE.finditer(cell):
        add(m.group(1))
    rest = IMG_HTML_RE.sub("", rest)
    text = cell_text(rest)
    if text and images:
        note_parts.append(text)
    return images, "\n".join(note_parts).strip()


def layer_id_of(url: str) -> str:
    try:
        parsed = urllib.parse.urlparse(url)
        qs = urllib.parse.parse_qs(parsed.query)
        for key in ("layer_id", "layerId"):
            if qs.get(key) and qs[key][0]:
                return urllib.parse.unquote(qs[key][0])
    except ValueError:
        return ""
    return ""


def extract_links_generic(cell: str) -> tuple[list[dict[str, str]], str]:
    links: list[dict[str, str]] = []
    seen = set()
    for m in MD_LINK_RE.finditer(cell):
        url = m.group(2).rstrip(").,，")
        if url not in seen:
            seen.add(url)
            links.append({"label": m.group(1) if m.group(1) != url else "", "url": url})
    rest = MD_LINK_RE.sub("", cell)
    for m in BARE_URL_RE.finditer(rest):
        url = m.group(0).rstrip(").,，")
        if url not in seen:
            seen.add(url)
            links.append({"label": "", "url": url})
    text = cell_text(MD_LINK_RE.sub("", BARE_URL_RE.sub("", cell)))
    return links, text


def extract_ui_links(cell: str) -> list[dict[str, Any]]:
    if cell_empty(cell):
        return []
    text = br_to_nl(cell)
    hits: list[tuple[int, int, str]] = []
    occupied: list[tuple[int, int]] = []
    for m in MD_LINK_RE.finditer(text):
        url = m.group(2).rstrip(").,，")
        hits.append((m.start(), m.end(), url))
        occupied.append((m.start(), m.end()))
    for m in BARE_URL_RE.finditer(text):
        start, end = m.start(), m.end()
        if any(s <= start < e for s, e in occupied):
            continue
        url = m.group(0).rstrip(").,，")
        hits.append((start, end, url))
    hits.sort(key=lambda x: x[0])
    out: list[dict[str, Any]] = []
    prev_end = 0
    seen_url = set()
    for start, end, url in hits:
        if url in seen_url:
            prev_end = end
            continue
        seen_url.add(url)
        prefix = text[prev_end:start]
        prefix = BR_RE.sub("\n", prefix)
        prefix = MD_LINK_RE.sub("", prefix)
        lines = [ln.strip(" ：:").strip() for ln in prefix.splitlines()]
        lines = [ln for ln in lines if ln and ln != "无"]
        label = ""
        if lines:
            cand = lines[-1]
            if len(cand) <= 40 and not cand.startswith("http"):
                label = cand
        lid = layer_id_of(url)
        out.append({"label": label, "url": url, "layer_id": lid, "valid": bool(lid)})
        prev_end = end
    return out


def extract_detail(cell: str) -> dict[str, Any]:
    images, _note = extract_images(cell)
    links, _ = extract_links_generic(cell)
    text_src = IMG_MD_RE.sub("", cell)
    text_src = IMG_HTML_RE.sub("", text_src)
    text_src = MD_LINK_RE.sub(lambda m: m.group(1) if m.group(1) and not m.group(1).startswith("http") else "", text_src)
    text = cell_text(text_src)
    return {
        "detail_text": text,
        "detail_images": images,
        "detail_links": links,
    }


def split_api_fields(raw: str) -> Any:
    text = cell_text(raw)
    if not text:
        return ""
    if "\n" in text:
        parts = [p.strip().strip("-").strip() for p in re.split(r"[\n,，]", text)]
        parts = [p for p in parts if p]
        return parts if parts else text
    if "," in text or "，" in text:
        parts = [p.strip() for p in re.split(r"[,，]", text) if p.strip()]
        return parts
    return text


def row_all_empty(values: list[str]) -> bool:
    return all(cell_empty(v) for v in values)


def normalize_boolish(raw: str) -> Any:
    text = cell_text(raw)
    if not text:
        return ""
    key = text.strip().lower()
    # 中文是否不 lower 成 latin；单独比
    if text in YES_VALS or key in YES_VALS:
        return True
    if text in NO_VALS or key in NO_VALS:
        return False
    return text


def extract_background(md: str) -> str:
    m = re.search(r"^##\s+背景\s*$", md, re.M)
    if not m:
        return ""
    rest = md[m.end() :]
    nxt = re.search(r"^##\s+", rest, re.M)
    body = rest[: nxt.start()] if nxt else rest
    return body.strip()


def merge_images(dst: list[dict[str, str]], src: list[dict[str, str]]) -> None:
    seen = {img["url"] for img in dst}
    for img in src:
        if img["url"] not in seen:
            dst.append(img)
            seen.add(img["url"])


def merge_ui_links(dst: list[dict[str, Any]], src: list[dict[str, Any]]) -> None:
    seen = {x["url"] for x in dst}
    for link in src:
        if link["url"] not in seen:
            dst.append(link)
            seen.add(link["url"])


def download_remote(url: str, assets_dir: str) -> str | None:
    if not url.startswith("http://") and not url.startswith("https://"):
        return None
    os.makedirs(assets_dir, exist_ok=True)
    parsed = urllib.parse.urlparse(url)
    base = os.path.basename(parsed.path) or "image"
    base = re.sub(r"[^A-Za-z0-9._-]", "_", base)
    dest = os.path.join(assets_dir, base)
    n = 1
    stem, ext = os.path.splitext(dest)
    while os.path.exists(dest):
        dest = f"{stem}_{n}{ext}"
        n += 1
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "gd-ai-coding-prd-parse"})
        with urllib.request.urlopen(req, timeout=20) as resp, open(dest, "wb") as f:
            f.write(resp.read())
        return dest
    except (urllib.error.URLError, OSError, TimeoutError):
        return None


def resolve_images(
    images: list[dict[str, str]], input_dir: str, assets_dir: str | None
) -> None:
    for img in images:
        url = img["url"]
        path = None
        if url.startswith("http://") or url.startswith("https://"):
            if assets_dir:
                path = download_remote(url, assets_dir)
        else:
            cand = url[2:] if url.startswith("./") else url
            abs_path = cand if os.path.isabs(cand) else os.path.normpath(os.path.join(input_dir, cand))
            if os.path.isfile(abs_path):
                path = abs_path
        if path:
            img["path"] = path


def parse(md: str, input_dir: str, assets_dir: str | None) -> dict[str, Any]:
    tables = iter_tables(md)
    feat_table = None
    collab_rows: list[dict[str, str]] = []
    scope_rows: list[dict[str, str]] = []
    track_rows: list[dict[str, str]] = []
    for t in tables:
        kind = classify_table(t["headers"])
        if kind == "features" and feat_table is None:
            feat_table = t
        elif kind == "collaborators":
            collab_rows.extend(t["rows"])
        elif kind == "scope":
            scope_rows.extend(t["rows"])
        elif kind == "trackings":
            track_rows.extend(t["rows"])

    if feat_table is None:
        raise StandardPrdMiss()

    raw_features: list[dict[str, Any]] = []
    for row in feat_table["rows"]:
        cols = [row.get(c, "") for c in FEATURE_COLS]
        extra = row.get("_extra")
        if row_all_empty(cols) and not extra:
            continue
        name = norm_name(row.get("功能/页面名", ""))
        online, online_note = extract_images(row.get("线上图", ""))
        req_imgs, req_note = extract_images(row.get("需求图", ""))
        ui_links = extract_ui_links(row.get("UI 链接", ""))
        detail = extract_detail(row.get("需求详情", ""))
        api_name = cell_text(row.get("API 接口名", ""))
        api_fields = split_api_fields(row.get("API 字段", ""))
        has_content = bool(
            name
            or online
            or req_imgs
            or ui_links
            or detail["detail_text"]
            or detail["detail_images"]
            or api_name
            or api_fields
        )
        if not has_content:
            continue
        raw_features.append(
            {
                "name": name,
                "online_images": online,
                "online_images_note": online_note,
                "req_images": req_imgs,
                "req_images_note": req_note,
                "ui_links": ui_links,
                "detail": detail,
                "api_name": api_name,
                "api_fields": api_fields,
                "extra": extra or {},
            }
        )

    features: list[dict[str, Any]] = []
    index_by_name: dict[str, int] = {}
    for src_i, row in enumerate(raw_features, start=1):
        name = row["name"]
        if name and name in index_by_name:
            feat = features[index_by_name[name]]
            merge_images(feat["online_images"], row["online_images"])
            merge_images(feat["req_images"], row["req_images"])
            if row["online_images_note"] and row["online_images_note"] not in feat["online_images_note"]:
                feat["online_images_note"] = (
                    (feat["online_images_note"] + "\n" + row["online_images_note"]).strip()
                )
            if row["req_images_note"] and row["req_images_note"] not in feat.get("req_images_note", ""):
                feat["req_images_note"] = (
                    (feat.get("req_images_note", "") + "\n" + row["req_images_note"]).strip()
                )
            merge_ui_links(feat["ui_links"], row["ui_links"])
            feat["detail_segments"].append(
                {"source_row": src_i, **row["detail"]}
            )
            if row["api_name"]:
                feat["_api_names"].append(row["api_name"])
            if row["api_fields"]:
                feat["_api_fields"].append(row["api_fields"])
            continue

        feat = {
            "name": name,
            "missing_name": not bool(name),
            "no_dev": False,
            "online_images": list(row["online_images"]),
            "online_images_note": row["online_images_note"],
            "req_images": list(row["req_images"]),
            "req_images_note": row["req_images_note"],
            "ui_links": list(row["ui_links"]),
            "detail_segments": [{"source_row": src_i, **row["detail"]}],
            "api_name": "",
            "api_fields": "",
            "api_conflict": False,
            "trackings": [],
            "issues": [],
            "_api_names": [row["api_name"]] if row["api_name"] else [],
            "_api_fields": [row["api_fields"]] if row["api_fields"] else [],
        }
        if feat["missing_name"]:
            feat["issues"].append("missing_name")
        features.append(feat)
        if name:
            index_by_name[name] = len(features) - 1

    for feat in features:
        names = feat.pop("_api_names")
        fields = feat.pop("_api_fields")
        uniq_names = list(dict.fromkeys(names))
        # fields may be list or str — stringify for compare
        field_keys = []
        uniq_fields: list[Any] = []
        for f in fields:
            key = json.dumps(f, ensure_ascii=False, sort_keys=True) if not isinstance(f, str) else f
            if key not in field_keys:
                field_keys.append(key)
                uniq_fields.append(f)
        if len(uniq_names) > 1 or len(uniq_fields) > 1:
            feat["api_conflict"] = True
            feat["issues"].append("api_conflict")
            feat["api_name"] = "\n".join(uniq_names)
            feat["api_fields"] = uniq_fields if len(uniq_fields) != 1 else uniq_fields[0]
        elif uniq_names:
            feat["api_name"] = uniq_names[0]
            feat["api_fields"] = uniq_fields[0] if uniq_fields else ""
        elif uniq_fields:
            feat["api_fields"] = uniq_fields[0]
        if any("无开发" in (seg.get("detail_text") or "") for seg in feat["detail_segments"]):
            feat["no_dev"] = True
        if any(not link["valid"] for link in feat["ui_links"]):
            feat["issues"].append("invalid_ui_link")
        resolve_images(feat["online_images"], input_dir, assets_dir)
        resolve_images(feat["req_images"], input_dir, assets_dir)
        for seg in feat["detail_segments"]:
            resolve_images(seg["detail_images"], input_dir, assets_dir)

    collaborators: list[dict[str, Any]] = []
    for row in collab_rows:
        direction = cell_text(row.get("方向", ""))
        owner = cell_text(row.get("负责人", ""))
        doc_cell = row.get("文档", "")
        remark = cell_text(row.get("备注", ""))
        if row_all_empty([direction, owner, doc_cell, remark]):
            continue
        links, leftover = extract_links_generic(doc_cell)
        item = {
            "direction": direction,
            "owner": owner,
            "doc_links": links,
            "doc_text": leftover,
            "remark": remark,
            "issues": [],
        }
        if not direction:
            item["issues"].append("missing_direction")
        collaborators.append(item)

    scope: list[dict[str, Any]] = []
    seen_dims: set[str] = set()
    for row in scope_rows:
        dim = cell_text(row.get("维度", ""))
        expl = cell_text(row.get("范围说明", ""))
        if not dim and not expl:
            continue
        item = {
            "dimension": dim,
            "value": normalize_boolish(row.get("范围说明", "")),
            "value_text": expl,
            "duplicate": dim in seen_dims if dim else False,
        }
        if dim:
            seen_dims.add(dim)
        scope.append(item)

    trackings_attached = 0
    trackings_unmatched: list[dict[str, Any]] = []
    name_map = {f["name"]: f for f in features if f["name"]}
    for row in track_rows:
        page = norm_name(row.get("页面中文名称", ""))
        ev_name = cell_text(row.get("埋点中文名称", ""))
        imgs, _ = extract_images(row.get("图片", ""))
        resolve_images(imgs, input_dir, assets_dir)
        when = cell_text(row.get("上报时机", ""))
        old = normalize_boolish(row.get("是否老点位", ""))
        event_id = cell_text(row.get("event_id", ""))
        params = cell_text(row.get("参数", ""))
        if row_all_empty(
            [
                row.get("页面中文名称", ""),
                row.get("埋点中文名称", ""),
                row.get("event_id", ""),
            ]
        ) and not imgs:
            continue
        item = {
            "page_name": page,
            "name": ev_name,
            "images": imgs,
            "when": when,
            "legacy": old,
            "event_id": event_id,
            "params": params,
            "issues": [],
        }
        if not page and not ev_name and not event_id:
            item["issues"].append("missing_tracking_identity")
        if page and page in name_map:
            name_map[page]["trackings"].append(item)
            trackings_attached += 1
        else:
            trackings_unmatched.append(item)

    ddp_ids: list[str] = []
    for c in collaborators:
        blob = " ".join(x["url"] for x in c["doc_links"]) + " " + c["doc_text"]
        for m in re.finditer(r"(?:T|R)-[A-Z]+-\d+", blob):
            if m.group(0) not in ddp_ids:
                ddp_ids.append(m.group(0))

    return {
        "schema_version": 1,
        "standard": True,
        "background": extract_background(md),
        "ddp_ids": ddp_ids,
        "collaborators": collaborators,
        "scope": scope,
        "features": features,
        "trackings_unmatched": trackings_unmatched,
        "stats": {
            "feature_count": len(features),
            "merged_from_rows": len(raw_features),
            "trackings_attached": trackings_attached,
            "trackings_unmatched": len(trackings_unmatched),
            "no_dev_count": sum(1 for f in features if f["no_dev"]),
        },
    }


class StandardPrdMiss(Exception):
    pass


def render_summary(data: dict[str, Any]) -> str:
    lines = ["# 标准 PRD 抽出摘要", ""]
    st = data["stats"]
    lines.append(f"- 功能点 **{st['feature_count']}** 个（原始 {st['merged_from_rows']} 行）")
    names = "、".join(f["name"] or "（缺功能名）" for f in data["features"])
    lines.append(f"- 名称：{names}")
    no_dev = [f["name"] or "（缺功能名）" for f in data["features"] if f["no_dev"]]
    if no_dev:
        lines.append(f"- 无开发：{'、'.join(no_dev)}")
    missing = [f"#{i+1}" for i, f in enumerate(data["features"]) if f["missing_name"]]
    if missing:
        lines.append(f"- 缺功能名：{', '.join(missing)}")
    invalid = []
    for f in data["features"]:
        bad = [u["url"] for u in f["ui_links"] if not u["valid"]]
        if bad:
            invalid.append(f"{f['name'] or '（缺功能名）'}（{len(bad)}）")
    if invalid:
        lines.append(f"- 无效 UI 链：{'、'.join(invalid)}")
    if data["trackings_unmatched"]:
        um = "、".join(t["name"] or t["event_id"] or t["page_name"] or "?" for t in data["trackings_unmatched"])
        lines.append(f"- 未挂上埋点：{um}")
    lines.append("")
    lines.append("抽出 JSON 供理解写 spec 用，本文不是需求正文。")
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Parse standard driver PRD tables into JSON")
    ap.add_argument("--input", required=True, help="Cooper Markdown")
    ap.add_argument("--out", required=True, help="prd-extract.json")
    ap.add_argument("--summary", default="", help="optional markdown summary")
    ap.add_argument("--assets-dir", default="", help="download remote images here")
    args = ap.parse_args()

    if not os.path.isfile(args.input):
        print(f"[DAC-SPEC-004] ❌ 输入文件不存在：{args.input}", file=sys.stderr)
        return 1
    with open(args.input, encoding="utf-8") as f:
        md = f.read()
    input_dir = os.path.dirname(os.path.abspath(args.input)) or "."
    assets_dir = args.assets_dir or None
    try:
        data = parse(md, input_dir, assets_dir)
    except StandardPrdMiss:
        print(
            "[DAC-SPEC-004] 未识别到需求列表 7 个标准列名，走旧裁剪",
            file=sys.stderr,
        )
        return 2
    except Exception as exc:  # noqa: BLE001 — surface parse bugs
        print(f"[DAC-SPEC-004] ❌ 标准 PRD 解析失败：{exc}", file=sys.stderr)
        return 1

    out_dir = os.path.dirname(os.path.abspath(args.out))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    if args.summary:
        sdir = os.path.dirname(os.path.abspath(args.summary))
        if sdir:
            os.makedirs(sdir, exist_ok=True)
        with open(args.summary, "w", encoding="utf-8") as f:
            f.write(render_summary(data))
    print(f"DAC_PRD_MODE=standard")
    print(f"DAC_EXTRACT={os.path.abspath(args.out)}")
    print(f"features={data['stats']['feature_count']} no_dev={data['stats']['no_dev_count']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
