#!/usr/bin/env bash
# code-review-single 环境解析与 Diff 提取脚本
# 用法: bash code-review-single-env.sh [PARAM] [COMMIT_COUNT_RAW] [COMMIT_HASH_RAW] [DATE_SINCE]
#   $1 - PARAM: 用户输入参数（组件路径等），无则留空
#   $2 - COMMIT_COUNT_RAW: 从自然语言提取的 commit 数量，无则留空
#   $3 - COMMIT_HASH_RAW: commit hash（7-40位十六进制），无则留空
#   $4 - DATE_SINCE: 已规范化的 git --since 字符串（midnight / N days|weeks|hours ago），无则留空

set -euo pipefail
IFS=$'\n\t'

PARAM="${1:-}"
COMMIT_COUNT_RAW="${2:-}"
COMMIT_HASH_RAW="${3:-}"
DATE_SINCE="${4:-}"

# pathspec 排除：编译产物 / lock / 常见 codegen 后缀，统一应用到所有 git diff 调用
EXCLUDES=(
    ':(exclude,glob)**/*.g.dart'
    ':(exclude,glob)**/*.freezed.dart'
    ':(exclude,glob)**/*.pb.dart'
    ':(exclude,glob)**/*.gr.dart'
    ':(exclude,glob)**/*.mocks.dart'
    ':(exclude,glob)**/*.generated.*'
    ':(exclude,glob)**/pubspec.lock'
    ':(exclude,glob)**/package-lock.json'
    ':(exclude,glob)**/yarn.lock'
    ':(exclude,glob)**/Cargo.lock'
    ':(exclude,glob)**/Podfile.lock'
    ':(exclude,glob)**/Pods/**'
    ':(exclude,glob)**/build/**'
    ':(exclude,glob)**/.dart_tool/**'
    ':(exclude,glob)**/.idea/**'
    ':(exclude,glob)**/node_modules/**'
    ':(exclude,glob)**/Generated.swift'
    ':(exclude,glob)**/.claude/**'
    ':(exclude,glob)**/openspec/**'
    ':(exclude,glob)**/Example/**'
    ':(exclude,glob)**/docs/**'
)

# 按扩展名统计 diff 涉及的文件数，输出 "ext:count ext:count ..."（按文件数降序）
detect_languages() {
    local diff_file="$1"
    grep '^diff --git ' "$diff_file" 2>/dev/null \
        | sed -E 's#^diff --git a/.+ b/(.+)$#\1#' \
        | awk -F. '{ if (NF > 1 && $1 != "") print $NF; else print "noext" }' \
        | sort | uniq -c | sort -rn \
        | awk '{ printf "%s:%s ", $2, $1 }' || true
}

# 1. 路径解析：剔除 @ 和 /，并尝试进入目录
if [ -n "$PARAM" ]; then
    CLEAN_PATH=$(echo "$PARAM" | sed -e 's/^@//' -e 's/\/$//')
    [ -d "$CLEAN_PATH" ] && cd "$CLEAN_PATH" || echo "未找到目录 $CLEAN_PATH，保持当前目录"
else
    CLEAN_PATH=$(basename "$(pwd)")
fi

# 安全拦截，判断当前目录是否是有效的 Git 仓库
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "BLOCK: 当前目录不是有效的 Git 仓库，结束操作。"
    exit 0
fi

REPO_NAME=$(basename "$(pwd)")

# 2. 获取当前分支与源头分支
C_BR=$(git branch --show-current)

# 尝试通过 reflog 获取源头分支
O_BR=$(git reflog show "$C_BR" 2>/dev/null | awk '/Created from/ {print $NF; exit}')
O_BR_COMPARE="${O_BR#refs/remotes/origin/}"
O_BR_COMPARE="${O_BR_COMPARE#remotes/origin/}"
O_BR_COMPARE="${O_BR_COMPARE#origin/}"

# 无论 reflog 是否有结果，都用提交距离法校验标准祖先分支（develop/main/master）。
# 防止 reflog 返回过时记录（如 rebase 后 Created from 仍指向旧分支）导致 diff 基线错误。
BEST_BR=""
BEST_COUNT=9999999
for br in develop main master; do
    if git rev-parse --verify "origin/$br" >/dev/null 2>&1; then
        COUNT=$(git rev-list --count HEAD ^"origin/$br" 2>/dev/null || echo "9999999")
        if [ "$COUNT" -lt "$BEST_COUNT" ]; then
            BEST_COUNT="$COUNT"
            BEST_BR="$br"
        fi
    fi
done

if [ -n "$BEST_BR" ]; then
    if [ -z "$O_BR" ] || [ "$O_BR" == "HEAD" ] || [ "$C_BR" == "$O_BR_COMPARE" ]; then
        # reflog 无有效结果：直接用距离法结果
        O_BR="origin/$BEST_BR"
        O_BR_COMPARE="$BEST_BR"
    else
        # reflog 有结果：比较距离，若距离法更近则覆盖（容忍 reflog 指向旧/错误分支的情况）
        REFLOG_COUNT=$(git rev-list --count HEAD ^"$O_BR" 2>/dev/null || echo "9999999")
        if [ "$BEST_COUNT" -lt "$REFLOG_COUNT" ]; then
            O_BR="origin/$BEST_BR"
            O_BR_COMPARE="$BEST_BR"
        fi
    fi
fi

# 3. 阻断逻辑
if [ -z "$O_BR" ] || [ -z "$O_BR_COMPARE" ]; then
    echo "BLOCK: 未找到源分支且无法匹配默认主分支，结束操作。"
    exit 0
fi

if [ "$C_BR" == "$O_BR_COMPARE" ]; then
    echo "BLOCK: 当前分支($C_BR)即为源分支($O_BR_COMPARE)，无需审查，结束操作。"
    exit 0
fi

# 4. 获取 Diff 与上下文组装
SAFE_TS="$(date +%s)_$$_${RANDOM}"
DIFF_TMP="/tmp/git_diff_raw_${SAFE_TS}.txt"
FINAL_TMP="/tmp/git_diff_final_${SAFE_TS}.txt"

if [ -n "$COMMIT_HASH_RAW" ]; then
    # commit hash 模式：diff 指定 commit 的 parent 到 HEAD
    if ! git rev-parse --verify "$COMMIT_HASH_RAW" >/dev/null 2>&1; then
        echo "BLOCK: commit hash 不存在（$COMMIT_HASH_RAW）"
        exit 0
    fi
    PARENT=$(git rev-parse "${COMMIT_HASH_RAW}^" 2>/dev/null || echo "")
    if [ -n "$PARENT" ]; then
        git diff "$PARENT" HEAD -- "${EXCLUDES[@]}" > "$DIFF_TMP" || true
    else
        git diff 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD -- "${EXCLUDES[@]}" > "$DIFF_TMP" || true
    fi

elif [ -n "$COMMIT_COUNT_RAW" ]; then
    # commit count 模式：取最近 N 次 first-parent 提交，diff 最老一条的 parent 到 HEAD
    if ! echo "$COMMIT_COUNT_RAW" | grep -qE '^[0-9]+$'; then
        echo "BLOCK: COMMIT_COUNT_RAW 不是合法正整数（$COMMIT_COUNT_RAW）"
        exit 0
    fi
    COMMITS=$(git log --first-parent -n "$COMMIT_COUNT_RAW" --format="%H" HEAD 2>/dev/null)
    if [ -z "$(echo "$COMMITS" | tr -d '[:space:]')" ]; then
        echo "BLOCK: 当前分支无提交记录"
        exit 0
    fi
    OLDEST=$(echo "$COMMITS" | tail -1)
    PARENT=$(git rev-parse "${OLDEST}^" 2>/dev/null || echo "")
    if [ -n "$PARENT" ]; then
        git diff "$PARENT" HEAD -- "${EXCLUDES[@]}" > "$DIFF_TMP" || true
    else
        git diff 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD -- "${EXCLUDES[@]}" > "$DIFF_TMP" || true
    fi

elif [ -n "$DATE_SINCE" ]; then
    # 时间范围模式：白名单格式校验（第二道防线）
    if ! echo "$DATE_SINCE" | grep -qE '^(midnight|[0-9]+ (day|days|week|weeks|hour|hours) ago)$'; then
        echo "BLOCK: DATE_SINCE 格式不合法（$DATE_SINCE），仅接受：midnight / N days ago / N weeks ago / N hours ago"
        exit 0
    fi

    GIT_LOG_EXIT=0
    COMMITS=$(git log --since="$DATE_SINCE" --format="%H" HEAD 2>/dev/null) || GIT_LOG_EXIT=$?

    if [ $GIT_LOG_EXIT -ne 0 ]; then
        echo "BLOCK: git log 执行失败（since: $DATE_SINCE），请检查 git 版本或时间格式"
        exit 0
    fi

    if [ -z "$(echo "$COMMITS" | tr -d '[:space:]')" ]; then
        echo "BLOCK: 时间范围内无新提交（since: $DATE_SINCE）"
        exit 0
    fi

    OLDEST=$(echo "$COMMITS" | tr -d ' ' | grep -v '^$' | tail -1)
    PARENT=$(git rev-parse "${OLDEST}^" 2>/dev/null)

    if [ -n "$PARENT" ]; then
        git diff "$PARENT" HEAD -- "${EXCLUDES[@]}" > "$DIFF_TMP" || true
    else
        git diff 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD -- "${EXCLUDES[@]}" > "$DIFF_TMP" || true
    fi
else
    git diff "$O_BR" HEAD -- "${EXCLUDES[@]}" > "$DIFF_TMP" || true
fi

# Autogen 头注释过滤：按 file block 检测前 30 行内是否含 autogen 标记
FILTERED_TMP="/tmp/git_diff_filtered_${SAFE_TS}.txt"
awk '
function is_autogen(b,    n, i, line, lines) {
    n = split(b, lines, "\n")
    for (i = 1; i <= n && i <= 30; i++) {
        line = lines[i]
        if (line ~ /Autogenerated/ ||
            line ~ /AUTO-GENERATED/ ||
            line ~ /auto-generated/ ||
            line ~ /DO NOT EDIT/ ||
            line ~ /GENERATED CODE/ ||
            line ~ /Code generated/ ||
            line ~ /do not modify by hand/ ||
            line ~ /This file is automatically generated/) {
            return 1
        }
    }
    return 0
}
BEGIN { block = ""; in_block = 0 }
/^diff --git / {
    if (in_block && !is_autogen(block)) printf "%s", block
    block = $0 "\n"
    in_block = 1
    next
}
in_block { block = block $0 "\n" }
END {
    if (in_block && !is_autogen(block)) printf "%s", block
}
' "$DIFF_TMP" > "$FILTERED_TMP"

mv "$FILTERED_TMP" "$DIFF_TMP"

if [ ! -s "$DIFF_TMP" ]; then
    echo "BLOCK: 当前分支($C_BR)与源分支($O_BR)不同，但暂无代码实质改动（或仅自动生成文件变更），结束操作。"
    rm -f "$DIFF_TMP"
    exit 0
fi

# 5. 分片决策（基于过滤后 diff 行数 + 文件数兜底）
DIFF_LINES=$(wc -l < "$DIFF_TMP" | tr -d ' ')
FILE_COUNT=$(grep -c '^diff --git ' "$DIFF_TMP" 2>/dev/null || echo 0)
if [ "$DIFF_LINES" -le 1200 ] || [ "$FILE_COUNT" -le 1 ]; then
    SHARDS=1
elif [ "$DIFF_LINES" -le 2500 ]; then
    SHARDS=2
elif [ "$DIFF_LINES" -le 4000 ]; then
    SHARDS=3
else
    SHARDS=4
fi
if [ "$SHARDS" -eq 1 ]; then
    LANGUAGES=$(detect_languages "$DIFF_TMP")
else
    LANGUAGES=""
fi

TS="$SAFE_TS"
if [ "$SHARDS" -gt 1 ]; then
    # 第一遍：统计每个 file block 的行数
    BLOCKS_TMP="/tmp/cr_blocks_${TS}.txt"
    awk '
        BEGIN { idx = 0; cnt = 0 }
        /^diff --git / {
            if (idx > 0) print idx "\t" cnt
            idx++; cnt = 1; next
        }
        { cnt++ }
        END { if (idx > 0) print idx "\t" cnt }
    ' "$DIFF_TMP" > "$BLOCKS_TMP"

    # 贪心装箱：按行数降序，依次塞入当前最小 bucket
    ASSIGN=$(awk -v shards="$SHARDS" '
        { idx[NR] = $1; sz[NR] = $2; n = NR }
        END {
            for (s = 1; s <= shards; s++) load[s] = 0
            for (i = 1; i <= n; i++) order[i] = i
            for (i = 1; i < n; i++) {
                for (j = i + 1; j <= n; j++) {
                    if (sz[order[i]] < sz[order[j]]) {
                        t = order[i]; order[i] = order[j]; order[j] = t
                    }
                }
            }
            for (k = 1; k <= n; k++) {
                fi = order[k]
                min_s = 1
                for (s = 2; s <= shards; s++) if (load[s] < load[min_s]) min_s = s
                assign[fi] = min_s
                load[min_s] += sz[fi]
            }
            for (i = 1; i <= n; i++) printf "%d:%d ", i, assign[i]
        }
    ' "$BLOCKS_TMP")
    rm -f "$BLOCKS_TMP"

    # 第二遍:按分配把 file block 写入对应 shard 文件
    awk -v assign_str="$ASSIGN" -v ts="$TS" '
        BEGIN {
            n = split(assign_str, pairs, " ")
            for (i = 1; i <= n; i++) {
                if (pairs[i] == "") continue
                split(pairs[i], kv, ":")
                assign[kv[1]] = kv[2]
            }
            idx = 0; cur = 0
        }
        /^diff --git / {
            idx++
            cur = assign[idx]
            shard_file = "/tmp/cr_shard_" ts "_" cur ".txt"
        }
        cur > 0 { print > shard_file }
    ' "$DIFF_TMP"
fi

echo "REPOSITORY_NAME: $REPO_NAME" > "$FINAL_TMP"
echo "TARGET_COMPONENT: $CLEAN_PATH" >> "$FINAL_TMP"
if [ -n "$DATE_SINCE" ]; then
    echo "BRANCHES: $O_BR -> $C_BR [since: $DATE_SINCE]" >> "$FINAL_TMP"
else
    echo "BRANCHES: $O_BR -> $C_BR" >> "$FINAL_TMP"
fi
echo "DIFF_LINES: $DIFF_LINES" >> "$FINAL_TMP"
echo "LANGUAGES: $LANGUAGES" >> "$FINAL_TMP"
echo "SHARDS: $SHARDS" >> "$FINAL_TMP"
if [ "$SHARDS" -gt 1 ]; then
    for s in $(seq 1 "$SHARDS"); do
        shard_path="/tmp/cr_shard_${TS}_${s}.txt"
        echo "SHARD_${s}: ${shard_path}" >> "$FINAL_TMP"
        if [ -s "$shard_path" ]; then
            echo "SHARD_${s}_LANGUAGES: $(detect_languages "$shard_path")" >> "$FINAL_TMP"
        else
            echo "SHARD_${s}_LANGUAGES: (empty)" >> "$FINAL_TMP"
        fi
    done
fi
echo "=========================================" >> "$FINAL_TMP"
cat "$DIFF_TMP" >> "$FINAL_TMP"

cat "$FINAL_TMP"
rm -f "$DIFF_TMP" "$FINAL_TMP"
# 注: shard 文件由主 agent 在合并完成后清理
