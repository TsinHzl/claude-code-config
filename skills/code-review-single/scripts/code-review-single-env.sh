#!/usr/bin/env bash
# code-review-single 环境解析与 Diff 提取脚本
# 用法: bash code-review-single-env.sh [PARAM] [COMMIT_COUNT_RAW] [COMMIT_HASH_RAW] [DATE_SINCE] [WORKING_TREE_RAW]
#   $1 - PARAM: 用户输入参数（组件路径等），无则留空
#   $2 - COMMIT_COUNT_RAW: 从自然语言提取的 commit 数量，无则留空
#   $3 - COMMIT_HASH_RAW: commit hash（7-40位十六进制），无则留空
#   $4 - DATE_SINCE: 已规范化的 git --since 字符串（midnight / N days|weeks|hours ago），无则留空
#   $5 - WORKING_TREE_RAW: 非空即启用「未提交改动」模式（最高优先级），无则留空

set -euo pipefail
IFS=$'\n\t'

PARAM="${1:-}"
COMMIT_COUNT_RAW="${2:-}"
COMMIT_HASH_RAW="${3:-}"
DATE_SINCE="${4:-}"
WORKING_TREE_RAW="${5:-}"

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

# 1. 路径解析：剔除 @ 和 /，并尝试进入目录
if [ -n "$PARAM" ]; then
    CLEAN_PATH=$(echo "$PARAM" | sed -e 's/^@//' -e 's/\/$//')
    if [ -d "$CLEAN_PATH" ]; then
        cd "$CLEAN_PATH"
    else
        # 注：变量展开后紧跟全角标点（如 $VAR， / $VAR）无 ASCII 分隔时，
        # macOS 自带 bash 3.2 在 `set -u`+`pipefail` 下会静默异常退出
        # （已实测复现，独立于本次新增的未提交改动模式）。此处在变量与
        # 全角标点之间插入 ASCII 空格规避。
        echo "未找到目录 $CLEAN_PATH ，保持当前目录"
    fi
else
    CLEAN_PATH=$(basename "$(pwd)")
fi

# 组件范围 pathspec：cd 进入子目录后，git diff/log 默认仍是全仓库范围，并不会
# 自动限定到当前目录（这与部分其他 VCS 的直觉不同）。始终传入 "." 作为
# pathspec，将所有 diff/log/ls-files 调用限定在当前目录范围内——未指定
# @组件名/ 时当前目录就是仓库根，"." 等价于全仓库范围，不影响原有行为；
# 指定了 @组件名/ 时 cd 已进入该子目录，"." 自然限定为该组件范围，
# 避免把仓库内其它无关目录的改动一并纳入 diff。
#
# 注：不使用空数组 SCOPE_PATHSPEC=()，因为 macOS 自带的 bash 3.2 在 `set -u`
# 下用 "${SCOPE_PATHSPEC[@]}" 展开空数组会产生一个空字符串参数（而不是零个
# 参数），导致 git 报 "empty string is not a valid pathspec"；统一用非空的
# "." 规避这个问题，同时天然满足两种场景下的正确语义。
SCOPE_PATHSPEC=(".")

# 安全拦截，判断当前目录是否是有效的 Git 仓库
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "BLOCK: 当前目录不是有效的 Git 仓库，结束操作。"
    exit 0
fi

REPO_NAME=$(basename "$(pwd)")

# 2. 获取当前分支
C_BR=$(git branch --show-current)

# 是否为「显式基线」模式（未提交改动 / commit hash / commit 数量 / 时间范围）。
# 这四种模式的 diff 基线完全由参数自身决定，与源分支无关，因此不需要解析源分支，
# 也不受「当前分支即源分支」限制——这使得在 main/master 上直接执行「最近 N 次提交」
# 或「审查未提交的改动」等模式成为可能。
EXPLICIT_BASELINE=0
if [ -n "$WORKING_TREE_RAW" ] || [ -n "$COMMIT_HASH_RAW" ] || [ -n "$COMMIT_COUNT_RAW" ] || [ -n "$DATE_SINCE" ]; then
    EXPLICIT_BASELINE=1
fi

O_BR=""
O_BR_COMPARE=""

if [ "$EXPLICIT_BASELINE" -eq 0 ]; then
    # 仅「源分支全量」兜底模式才需要解析源分支与执行阻断逻辑
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

    # 3. 阻断逻辑（仅全量模式：无法确定对比基线时才阻断）
    if [ -z "$O_BR" ] || [ -z "$O_BR_COMPARE" ]; then
        echo "BLOCK: 未找到源分支且无法匹配默认主分支，结束操作。"
        exit 0
    fi

    if [ "$C_BR" == "$O_BR_COMPARE" ]; then
        echo "BLOCK: 当前分支($C_BR)即为源分支($O_BR_COMPARE)，无法确定全量对比基线。如需审查该分支上的具体提交，请改用 commit hash / 提交数量（如\"最近 4 次提交\"）/ 时间范围模式，结束操作。"
        exit 0
    fi
fi

# 4. 获取 Diff 与上下文组装
SAFE_TS="$(date +%s)_$$_${RANDOM}"
DIFF_TMP="/tmp/git_diff_raw_${SAFE_TS}.txt"
FINAL_TMP="/tmp/git_diff_final_${SAFE_TS}.txt"

BASELINE_DESC=""

if [ -n "$WORKING_TREE_RAW" ]; then
    # 未提交改动模式：diff 工作区（含已 staged 与未 staged 的改动）相对 HEAD 的差异，
    # 并将未跟踪的新文件以「新增文件」的形式追加进 diff（git diff 默认不包含未跟踪文件）。
    if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
        echo "BLOCK: 当前仓库尚无任何提交（无 HEAD），无法与已提交历史比较，结束操作。"
        exit 0
    fi

    git diff HEAD -- "${SCOPE_PATHSPEC[@]}" "${EXCLUDES[@]}" > "$DIFF_TMP" || true

    # 追加未跟踪文件（新增且未 git add 的文件），排除同一批 EXCLUDES 模式匹配的路径
    UNTRACKED_FILES=$(git ls-files --others --exclude-standard -- "${SCOPE_PATHSPEC[@]}" "${EXCLUDES[@]}" 2>/dev/null || true)
    if [ -n "$UNTRACKED_FILES" ]; then
        while IFS= read -r uf; do
            [ -z "$uf" ] && continue
            # 跳过明显的二进制/大文件误入（依赖 git diff --no-index 自身的二进制检测）
            git diff --no-index /dev/null "$uf" -- >> "$DIFF_TMP" 2>/dev/null || true
        done <<< "$UNTRACKED_FILES"
    fi

    STAGED_COUNT=$(git diff --cached --name-only -- "${SCOPE_PATHSPEC[@]}" "${EXCLUDES[@]}" 2>/dev/null | wc -l | tr -d ' ')
    UNSTAGED_COUNT=$(git diff --name-only -- "${SCOPE_PATHSPEC[@]}" "${EXCLUDES[@]}" 2>/dev/null | wc -l | tr -d ' ')
    UNTRACKED_COUNT=$(echo "$UNTRACKED_FILES" | grep -c '^' 2>/dev/null || echo 0)
    # 注：分多次 += 拼接而非单条长字符串拼接，规避 macOS 自带 bash 3.2 在处理
    # 超长、含多字节 UTF-8 字符的单行字符串拼接时偶发的静默失败（已实测复现）。
    BASELINE_DESC="HEAD -> 工作区未提交改动（当前分支: $C_BR"
    BASELINE_DESC="${BASELINE_DESC}；已 staged: ${STAGED_COUNT} 个文件"
    BASELINE_DESC="${BASELINE_DESC}，未 staged: ${UNSTAGED_COUNT} 个文件"
    BASELINE_DESC="${BASELINE_DESC}，未跟踪: ${UNTRACKED_COUNT} 个文件）"

elif [ -n "$COMMIT_HASH_RAW" ]; then
    # commit hash 模式：diff 指定 commit 的 parent 到 HEAD
    if ! git rev-parse --verify "$COMMIT_HASH_RAW" >/dev/null 2>&1; then
        echo "BLOCK: commit hash 不存在（$COMMIT_HASH_RAW ）"
        exit 0
    fi
    PARENT=$(git rev-parse "${COMMIT_HASH_RAW}^" 2>/dev/null || echo "")
    if [ -n "$PARENT" ]; then
        git diff "$PARENT" HEAD -- "${SCOPE_PATHSPEC[@]}" "${EXCLUDES[@]}" > "$DIFF_TMP" || true
        BASELINE_DESC="${PARENT:0:7}..HEAD (commit hash: $COMMIT_HASH_RAW)"
    else
        git diff 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD -- "${SCOPE_PATHSPEC[@]}" "${EXCLUDES[@]}" > "$DIFF_TMP" || true
        BASELINE_DESC="root..HEAD (commit hash: $COMMIT_HASH_RAW)"
    fi

elif [ -n "$COMMIT_COUNT_RAW" ]; then
    # commit count 模式：取最近 N 次 first-parent 提交，diff 最老一条的 parent 到 HEAD
    if ! echo "$COMMIT_COUNT_RAW" | grep -qE '^[0-9]+$'; then
        echo "BLOCK: COMMIT_COUNT_RAW 不是合法正整数（$COMMIT_COUNT_RAW ）"
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
        git diff "$PARENT" HEAD -- "${SCOPE_PATHSPEC[@]}" "${EXCLUDES[@]}" > "$DIFF_TMP" || true
        BASELINE_DESC="${PARENT:0:7}..HEAD (最近 $COMMIT_COUNT_RAW 次提交, 当前分支: $C_BR)"
    else
        git diff 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD -- "${SCOPE_PATHSPEC[@]}" "${EXCLUDES[@]}" > "$DIFF_TMP" || true
        BASELINE_DESC="root..HEAD (最近 $COMMIT_COUNT_RAW 次提交, 当前分支: $C_BR)"
    fi

elif [ -n "$DATE_SINCE" ]; then
    # 时间范围模式：白名单格式校验（第二道防线）
    if ! echo "$DATE_SINCE" | grep -qE '^(midnight|[0-9]+ (day|days|week|weeks|hour|hours) ago)$'; then
        echo "BLOCK: DATE_SINCE 格式不合法（$DATE_SINCE ），仅接受：midnight / N days ago / N weeks ago / N hours ago"
        exit 0
    fi

    GIT_LOG_EXIT=0
    COMMITS=$(git log --since="$DATE_SINCE" --format="%H" HEAD 2>/dev/null) || GIT_LOG_EXIT=$?

    if [ $GIT_LOG_EXIT -ne 0 ]; then
        echo "BLOCK: git log 执行失败（since: $DATE_SINCE ），请检查 git 版本或时间格式"
        exit 0
    fi

    if [ -z "$(echo "$COMMITS" | tr -d '[:space:]')" ]; then
        echo "BLOCK: 时间范围内无新提交（since: $DATE_SINCE ）"
        exit 0
    fi

    OLDEST=$(echo "$COMMITS" | tr -d ' ' | grep -v '^$' | tail -1)
    PARENT=$(git rev-parse "${OLDEST}^" 2>/dev/null)

    if [ -n "$PARENT" ]; then
        git diff "$PARENT" HEAD -- "${SCOPE_PATHSPEC[@]}" "${EXCLUDES[@]}" > "$DIFF_TMP" || true
        BASELINE_DESC="${PARENT:0:7}..HEAD (since: $DATE_SINCE, 当前分支: $C_BR)"
    else
        git diff 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD -- "${SCOPE_PATHSPEC[@]}" "${EXCLUDES[@]}" > "$DIFF_TMP" || true
        BASELINE_DESC="root..HEAD (since: $DATE_SINCE, 当前分支: $C_BR)"
    fi
else
    git diff "$O_BR" HEAD -- "${SCOPE_PATHSPEC[@]}" "${EXCLUDES[@]}" > "$DIFF_TMP" || true
    BASELINE_DESC="$O_BR -> $C_BR"
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
    echo "BLOCK: 对比基线($BASELINE_DESC)范围内暂无代码实质改动（或仅自动生成文件变更），结束操作。"
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
echo "BRANCHES: $BASELINE_DESC" >> "$FINAL_TMP"
echo "DIFF_LINES: $DIFF_LINES" >> "$FINAL_TMP"
echo "SHARDS: $SHARDS" >> "$FINAL_TMP"
if [ "$SHARDS" -gt 1 ]; then
    for s in $(seq 1 "$SHARDS"); do
        echo "SHARD_${s}: /tmp/cr_shard_${TS}_${s}.txt" >> "$FINAL_TMP"
    done
fi
echo "=========================================" >> "$FINAL_TMP"
cat "$DIFF_TMP" >> "$FINAL_TMP"

cat "$FINAL_TMP"
rm -f "$DIFF_TMP" "$FINAL_TMP"
# 注: shard 文件由主 agent 在合并完成后清理
