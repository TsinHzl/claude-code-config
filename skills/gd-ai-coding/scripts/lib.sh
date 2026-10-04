#!/usr/bin/env bash
# lib.sh — 共享工具函数库
# 由各脚本 source 使用，不可直接执行。

# 原子写入 JSON：jq 表达式 → 临时文件 → 校验 → mv（带跨平台互斥锁）
# 用法：atomic_jq '<jq_expr>' <file> [jq_args...]
#        atomic_jq --compact '<jq_expr>' <file> [jq_args...]
# 示例：atomic_jq '.phase = "done"' .dac/state.json --arg ts "$NOW"
atomic_jq() {
  local compact=false
  if [[ "${1:-}" == "--compact" ]]; then
    compact=true
    shift
  fi
  local expr="$1"
  local file="$2"
  shift 2
  local lockdir="${file}.lock"
  local max_wait=10 waited=0

  # mkdir 作为跨平台互斥锁（macOS 无 flock）
  while ! mkdir "$lockdir" 2>/dev/null; do
    sleep 0.1
    waited=$((waited + 1))
    if [[ $waited -ge $((max_wait * 10)) ]]; then
      echo "[DAC-LIB] ❌ 获取锁超时：$file" >&2
      return 1
    fi
  done

  # 显式 cleanup 替代 trap RETURN（bash 3.2 兼容）
  local _aq_rc=0
  local tmp jq_flags=""
  [[ "$compact" == "true" ]] && jq_flags="-c"
  tmp=$(mktemp)
  if ! jq $jq_flags "$@" "$expr" "$file" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    rmdir "$lockdir" 2>/dev/null
    echo "[DAC-LIB] ❌ jq 表达式执行失败：$expr" >&2
    return 1
  fi
  if ! jq empty "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    rmdir "$lockdir" 2>/dev/null
    echo "[DAC-LIB] ❌ jq 输出不是合法 JSON" >&2
    return 1
  fi
  mv "$tmp" "$file"
  rmdir "$lockdir" 2>/dev/null
}

# DDP ID 标准化：转为大写规范形式（R-IBG-XXXXXX 或纯数字）
# 用法：normalize_ddp_id <id>  → stdout 输出大写形式
normalize_ddp_id() {
  echo "$1" | tr '[:lower:]' '[:upper:]'
}

# DDP ID 格式校验（含标准化）
# 支持输入：纯数字、R-IBG-XXXXXX（需求）、T-IBT-XXXXXX（任务）、DDP URL（自动提取 ID）
# URL 格式：https://ddp.intra.xiaojukeji.com/requirement/story/R-IBG-689979
#            https://ddp.intra.xiaojukeji.com/issue/story/T-IBT-626806
#            https://ddp.intra.xiaojukeji.com/requirement/716631
# 用法：validate_ddp_id <id_or_url>
# 成功返回 0，stdout 输出标准化后的 ID；失败返回 1
validate_ddp_id() {
  local raw="$1" id
  # URL 格式：从 /requirement/story/R-IBG-XXXXXX 中提取 R-IBG 需求 ID
  if [[ "$raw" =~ ddp.*requirement/story/(R-IBG-[0-9]+) ]] || [[ "$raw" =~ ddp.*requirement/story/(r-ibg-[0-9]+) ]]; then
    echo "$(normalize_ddp_id "${BASH_REMATCH[1]}")"
    return 0
  fi
  # URL 格式：从 /issue/story/T-IBT-XXXXXX 中提取 T-IBT 任务 ID
  if [[ "$raw" =~ ddp.*issue/story/(T-IBT-[0-9]+) ]] || [[ "$raw" =~ ddp.*issue/story/(t-ibt-[0-9]+) ]]; then
    echo "$(normalize_ddp_id "${BASH_REMATCH[1]}")"
    return 0
  fi
  # URL 格式：从 /requirement/{纯数字} 中提取数字 ID
  if [[ "$raw" =~ ddp.*requirement/([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  id=$(normalize_ddp_id "$raw")
  if [[ "$id" =~ ^([0-9]{1,20}|R-IBG-[0-9]+|T-IBT-[0-9]+)$ ]]; then
    echo "$id"
    return 0
  fi
  return 1
}

# 校验 JSON 文件格式合法性
# 用法：validate_json <file>
validate_json() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "[DAC-LIB] ❌ 文件不存在：$file" >&2
    return 1
  fi
  if ! jq empty "$file" 2>/dev/null; then
    echo "[DAC-LIB] ❌ JSON 格式损坏：$file" >&2
    return 1
  fi
  return 0
}

# 生成 state.json 初始模板
# 用法：state_json_template <phase> [req_name]
state_json_template() {
  local phase="$1"
  local req_name="${2:-}"
  local now_iso
  now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local rn_val="null"
  if [[ -n "$req_name" ]]; then
    rn_val="\"$req_name\""
  fi

  local owner_committer
  owner_committer=$(git config user.email 2>/dev/null || echo "")

  cat <<EOFSTATE
{"phase": "$phase", "req_name": $rn_val, "current_feature_id": null, "completed_features": [], "skipped_features": [], "available_platforms": {}, "flow_profile": {"skip_prd_parse":false,"skip_mastergo":false,"skip_feature_plan":false,"skip_scaffold":false}, "owner_committer": "$owner_committer", "created_at": "$now_iso", "updated_at": "$now_iso"}
EOFSTATE
}

# 阶段顺序映射（兼容 bash 3.2）
# 命名说明：proposal-approved 语义为"proposal 已审批"，属 feature-plan 产出
# 用法：phase_to_order <phase_name>
phase_to_order() {
  case "$1" in
    init)             echo 0 ;;
    prd-parsing)      echo 1 ;;
    prd-parsed)       echo 2 ;;
    prd-clarified)    echo 3 ;;
    prd-specing)      echo 4 ;;
    prd-speced)       echo 5 ;;
    proposal-approved) echo 6 ;;
    feature-planned)  echo 7 ;;
    feature-loop)     echo 8 ;;
    feature-done)     echo 9 ;;
    done)             echo 10 ;;
    *)                echo -1 ;;
  esac
}

# ISO 8601 时间戳转 epoch（纯 bash/date 实现，无 python 依赖）
# 用法：iso_to_epoch "2026-05-22T10:00:00Z"
iso_to_epoch() {
  local ts="$1"
  # macOS date -j 和 GNU date 兼容（必须锚定 UTC，否则非 UTC 时区机器上解析偏移导致 TTL 校验错乱）
  if TZ=UTC date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$ts" "+%s" 2>/dev/null; then
    return 0
  fi
  # GNU date fallback（-d 已按 ISO 中的 Z/偏移解析，但 env 清空 TZ 防局部覆盖）
  if TZ=UTC date -d "$ts" "+%s" 2>/dev/null; then
    return 0
  fi
  # python fallback
  python3 -c "
from datetime import datetime
ts = '$ts'.replace('Z', '+00:00')
print(int(datetime.fromisoformat(ts).timestamp()))
" 2>/dev/null || echo "0"
}

# 从 feature-plan.json 提取 features 数组（兼容 v0 纯数组和 v1 包裹对象）
# 用法：read_features_jq <file> [额外 jq 表达式]
read_features_jq() {
  local file="$1"
  local extra="${2:-.}"
  jq "(if type == \"array\" then . else .features end) | $extra" "$file"
}

# ── 行数统计：代码文件白名单（单一来源）────────────────────────────────────────
# 全部 dac-trace 行数统计管道共用此清单，避免多处扩展名列表漂移。五处调用方：
#   - write-trace-hook.sh（需求维度 + 个人总量两条实时管道，用 dac_is_code_file）
#   - setup-hook-wrapper.sh 生成的 post-commit hook（#!/bin/sh，生成期用 dac_numstat_pathspec_quoted 展开字面）
#   - backfill-commit-stats-from-history.sh（运行期用 dac_build_numstat_pathspec 填数组）
#   - aggregate-trace.sh（同上）
#   - settle-codegen-lines.sh（codegen checkpoint diff，用 dac_is_code_file + dac_build_numstat_pathspec）
# 扩展名不含前导点，空格分隔。新增/删减语言只改这一行。
# 含前端组件(vue/svelte/astro)与样式(css/scss/sass/less)：前端项目的主要产出就在这些文件里，
# 漏掉会让整个前端仓库的 vibe coding 与 commit 行数系统性归零。
DAC_CODE_EXTENSIONS="dart java kt kts swift m mm h hpp c cc cpp cxx py js jsx mjs cjs ts tsx html go rs rb php scala sh bash zsh sql groovy gradle cs vue svelte astro css scss sass less"

# 生成/依赖锁/构建产物排除清单（也匹配白名单扩展名，如 *.g.dart 命中 *.dart，须显式剔除）。
# 不含 .arb 本地化；**/generated/** 目录单独用 glob magic 追加。扩展名/文件名含前导点或全名。
DAC_GENERATED_EXCLUDE="*.g.dart *.freezed.dart *.gr.dart *.config.dart *.mocks.dart *.pb.dart *.pbenum.dart *.pbjson.dart *.pbserver.dart *.pbgrpc.dart *.g.kt pubspec.lock *.lock"

# 构建产物/依赖目录排除清单（目录名，非扩展名）。前端项目的 dist/ 与 dist-single/ 按项目约定
# 随 src/ 一起提交，其压缩后的 .js/.css 若计入会让行数系统性虚高（实测本仓库历史累计 1151 行
# ≈ src 的 15%）；node_modules 为依赖目录，同样不属个人产出。实时口径（dac_is_code_file）与
# 提交后精确口径（numstat pathspec）共用此清单，避免两口径漂移。
DAC_EXCLUDE_DIRS="dist dist-single node_modules"

# 判定路径是否为代码文件（大小写无关，POSIX：case + tr，不依赖 bash4 ${,,} 或 bash3.2 shopt nocasematch）。
# 命中白名单 return 0，否则（含无扩展名）return 1。用法：dac_is_code_file <path>
dac_is_code_file() {
  local base ext e d
  # 构建产物/依赖目录内的文件一律不计（与 numstat pathspec 的 exclude 口径保持一致）
  for d in $DAC_EXCLUDE_DIRS; do
    case "$1" in */"$d"/*|"$d"/*) return 1 ;; esac
  done
  base="${1##*/}"
  case "$base" in
    *.*) ext="${base##*.}" ;;
    *)   return 1 ;;
  esac
  ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
  for e in $DAC_CODE_EXTENSIONS; do
    [ "$ext" = "$e" ] && return 0
  done
  return 1
}

# 构造 git show --numstat 的 pathspec 参数数组（include 代码白名单 + exclude 生成文件），
# 结果放入全局数组 DAC_NUMSTAT_PATHSPEC，供 bash 运行期调用方：
#   dac_build_numstat_pathspec
#   git show --numstat --format="" HEAD -- "${DAC_NUMSTAT_PATHSPEC[@]}"
# 数组元素带引号扩展，git 收到字面 *.dart，不会被 shell glob 误展开为当前目录文件名。
dac_build_numstat_pathspec() {
  DAC_NUMSTAT_PATHSPEC=()
  local e g d
  # 用 read -ra 按 IFS 分词，绝不用 `for x in $unquoted_var`：DAC_GENERATED_EXCLUDE 的词本身
  # 含 * 通配符，未加引号的变量展开会触发 pathname expansion，若 cwd（总是目标项目根目录）
  # 存在匹配文件（如 pubspec.lock / *.g.dart），*.lock 会被展开成当时的具体文件名，导致通用
  # exclude 通配符丢失、后续新增的生成文件不再被排除。read -ra 只做分词、不做 glob，结果为纯字面。
  local -a _exts=() _excl=() _dirs=()
  read -ra _exts <<< "$DAC_CODE_EXTENSIONS"
  read -ra _excl <<< "$DAC_GENERATED_EXCLUDE"
  read -ra _dirs <<< "$DAC_EXCLUDE_DIRS"
  for e in "${_exts[@]}"; do DAC_NUMSTAT_PATHSPEC+=("*.$e"); done
  for g in "${_excl[@]}"; do DAC_NUMSTAT_PATHSPEC+=(":(exclude)$g"); done
  for d in "${_dirs[@]}"; do DAC_NUMSTAT_PATHSPEC+=(":(exclude,glob)**/$d/**"); done
  DAC_NUMSTAT_PATHSPEC+=(":(exclude,glob)**/generated/**")
}

# 输出上述 pathspec 的单引号字面串（如：'*.dart' '*.java' … ':(exclude)*.g.dart' …），
# 供 setup-hook-wrapper.sh 在生成 #!/bin/sh 的 post-commit hook 时展开写入 hook 文本
# （hook 运行期自包含，不 source 含 bashism 的 lib.sh）。
dac_numstat_pathspec_quoted() {
  dac_build_numstat_pathspec
  local p out=""
  for p in "${DAC_NUMSTAT_PATHSPEC[@]}"; do
    out="$out '$p'"
  done
  printf '%s' "${out# }"
}
