#!/bin/bash
# code-review-single 环境解析与 Diff 提取脚本
# 用法: bash code-review-single-env.sh [PARAM] [COMMIT_COUNT_RAW] [COMMIT_HASH_RAW]
#   $1 - PARAM: 用户输入参数（组件路径等），无则留空
#   $2 - COMMIT_COUNT_RAW: 从自然语言提取的 commit 数量，无则留空
#   $3 - COMMIT_HASH_RAW: commit hash（7-40位十六进制），无则留空

PARAM="${1:-}"
COMMIT_COUNT_RAW="${2:-}"
COMMIT_HASH_RAW="${3:-}"
DATE_SINCE="${4:-}"

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
O_BR_COMPARE="${O_BR#remotes/}"
O_BR_COMPARE="${O_BR_COMPARE#origin/}"

# 处理 reflog 丢失 或 指向远端自身的场景（如重新 clone）
if [ -z "$O_BR" ] || [ "$O_BR" == "HEAD" ] || [ "$C_BR" == "$O_BR_COMPARE" ]; then
    # 用提交距离找最近祖先，比"第一个存在"更准确
    BEST_BR=""
    BEST_COUNT=9999999
    for br in main master develop; do
        if git rev-parse --verify "origin/$br" >/dev/null 2>&1; then
            COUNT=$(git rev-list --count HEAD ^"origin/$br" 2>/dev/null || echo "9999999")
            if [ "$COUNT" -lt "$BEST_COUNT" ]; then
                BEST_COUNT="$COUNT"
                BEST_BR="$br"
            fi
        fi
    done
    DEFAULT_BR="$BEST_BR"

    if [ -n "$DEFAULT_BR" ]; then
        O_BR="origin/$DEFAULT_BR"
        O_BR_COMPARE="$DEFAULT_BR"
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
DIFF_TMP="/tmp/git_diff_raw_$(date +%s).txt"
FINAL_TMP="/tmp/git_diff_final_$(date +%s).txt"

if [ -n "$DATE_SINCE" ]; then
    # 时间范围模式：白名单格式校验（第二道防线）
    if ! echo "$DATE_SINCE" | grep -qE '^(midnight|[0-9]+ (day|days|week|weeks|hour|hours) ago)$'; then
        echo "BLOCK: DATE_SINCE 格式不合法（$DATE_SINCE），仅接受：midnight / N days ago / N weeks ago / N hours ago"
        exit 0
    fi

    # git log 默认从新到旧，tail -1 取最旧 commit；检查退出码区分"命令报错"与"无结果"
    COMMITS=$(git log --since="$DATE_SINCE" --format="%H" HEAD 2>/dev/null)
    GIT_LOG_EXIT=$?

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

    # diff 语义：最老 in-range commit 的父节点到 HEAD 的累积变更
    # 线性历史下等价于"范围内所有 commit 的合并变更"；
    # merge/cherry-pick 非线性历史场景可能包含少量范围外提交，属已知限制
    if [ -n "$PARENT" ]; then
        git diff "$PARENT" HEAD > "$DIFF_TMP"
    else
        # 初始 commit 无父节点：使用 git 规范空树 hash（所有标准 git 实现均有效，无兼容性风险）
        git diff 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD > "$DIFF_TMP"
    fi
else
    git diff "$O_BR" HEAD > "$DIFF_TMP"
fi

if [ ! -s "$DIFF_TMP" ]; then
    echo "BLOCK: 当前分支($C_BR)与源分支($O_BR)不同，但暂无代码实质改动，结束操作。"
    rm -f "$DIFF_TMP"
    exit 0
fi

echo "REPOSITORY_NAME: $REPO_NAME" > "$FINAL_TMP"
echo "TARGET_COMPONENT: $CLEAN_PATH" >> "$FINAL_TMP"
if [ -n "$DATE_SINCE" ]; then
    echo "BRANCHES: $O_BR -> $C_BR [since: $DATE_SINCE]" >> "$FINAL_TMP"
else
    echo "BRANCHES: $O_BR -> $C_BR" >> "$FINAL_TMP"
fi
echo "=========================================" >> "$FINAL_TMP"
cat "$DIFF_TMP" >> "$FINAL_TMP"

cat "$FINAL_TMP"
rm -f "$DIFF_TMP" "$FINAL_TMP"
