#!/usr/bin/env bash
# write-lite-spec.sh — skip_prd_parse 时仍产出 prd-spec.md，记录「这个需求是做什么」
#
# 跳过 Cooper 裁剪 / 需求澄清，但不跳过需求记录。材料来自：
#   DDP 标题、用户说明、PRD 链接、未跳过步骤已有产物（调用方写入 --summary）。
#
# 用法：
#   bash write-lite-spec.sh \
#     --out openspec/changes/<req>/prd/prd-spec.md \
#     --req-name driver-login \
#     --title "司机端登录优化" \
#     --summary "跳过 MasterGo，做登录页错误态" \
#     [--ddp-id T-IBT-123] [--prd-url URL]
#
# 若 --out 已存在且非空，不覆盖（LLM 已写入更完整版本）。
set -euo pipefail

OUT=""
REQ_NAME=""
TITLE=""
SUMMARY=""
DDP_ID=""
PRD_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)      OUT="${2:-}"; shift 2 ;;
    --req-name) REQ_NAME="${2:-}"; shift 2 ;;
    --title)    TITLE="${2:-}"; shift 2 ;;
    --summary)  SUMMARY="${2:-}"; shift 2 ;;
    --ddp-id)   DDP_ID="${2:-}"; shift 2 ;;
    --prd-url)  PRD_URL="${2:-}"; shift 2 ;;
    *) echo "[write-lite-spec] ❌ 未知参数: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$OUT" ]]; then
  echo "[write-lite-spec] ❌ 必须提供 --out" >&2
  exit 1
fi

if [[ -s "$OUT" ]]; then
  echo "[write-lite-spec] ⏭ 已存在非空 $OUT，不覆盖"
  exit 0
fi

REQ_NAME="${REQ_NAME:-unnamed}"
TITLE="${TITLE:-$REQ_NAME}"
SUMMARY="${SUMMARY:-$TITLE}"
DATE_STR=$(date +%Y-%m-%d)
PRD_LINE="${PRD_URL:-无（skip_prd_parse，未拉取 Cooper 原文）}"
DDP_LINE="${DDP_ID:-无}"

mkdir -p "$(dirname "$OUT")"

python3 - "$OUT" "$REQ_NAME" "$TITLE" "$SUMMARY" "$PRD_LINE" "$DDP_LINE" "$DATE_STR" <<'PY'
import sys
from pathlib import Path

out, req_name, title, summary, prd, ddp, date = sys.argv[1:8]
feat = title.strip() or req_name
body = summary.strip() or feat
# 单行概述，避免把用户整段说明打进表格撑破
feat_brief = body.splitlines()[0][:80]

text = f"""# {feat} - 结构化需求规范

> 原始文档：{prd}
> DDP：{ddp}
> 适用端：司机端
> 生成时间：{date}
> 生成方式：轻量 spec（skip_prd_parse，根据 DDP 标题 / 用户输入 / 未跳过步骤合成，未经 Cooper 裁剪与澄清）

<!-- 输出规则：所有字段均需输出，无实质内容时填"无"，保持结构完整 -->

---

## 1. 需求概述

{body}

## 2. 功能清单

| # | 功能点 | 类型 | 设计稿 | 说明 |
|---|--------|------|--------|------|
| 1 | {feat_brief} | 修改 | 无 | 由 DDP / 用户说明概括，未经 PRD 精裁 |

## 3. 详细需求

### 3.1 {feat}

**类型：** 修改

**需求描述：**
{body}

**交互流程：**
1. 无（轻量 spec，未做需求澄清）

**UI 状态：**
- 加载中：无
- 空态：无
- 错误态：无

**异常/边界情况：**
- 无

**设计稿：** 无

**埋点需求：**
- 无

**开关/配置：**
- 无

## 4. 非功能需求

- **性能要求：** 无
- **兼容性：** 无

## 5. 待确认项

> 已澄清项已直接体现在各功能点 §3.x 描述中；仅保留尚未确认的开放问题。

- 无
"""
Path(out).write_text(text, encoding="utf-8")
print(f"[write-lite-spec] ✓ 已写入 {out}")
PY
