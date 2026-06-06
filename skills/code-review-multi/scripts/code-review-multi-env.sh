#!/bin/bash
# code-review-multi 批量扫描与 Diff 提取脚本
# 用法: bash code-review-multi-env.sh
# 自动扫描当前目录下所有含 .git 的子仓库，输出聚合 Diff 日志

ROOT_DIR=$(pwd)
ROOT_DIR_NAME=$(basename "$ROOT_DIR")
ALL_DIFFS_TMP="/tmp/batch_git_diff_$(date +%s).txt"
REPO_DIFF_TMP="/tmp/single_repo_diff_$(date +%s).txt"

echo "ROOT_DIRECTORY_NAME: $ROOT_DIR_NAME" > "$ALL_DIFFS_TMP"
echo "=========================================" >> "$ALL_DIFFS_TMP"

TOTAL_SCANNED=0

for d in */; do
    [ -d "$d" ] || continue

    cd "$d" || continue

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        cd "$ROOT_DIR"
        continue
    fi

    TOTAL_SCANNED=$((TOTAL_SCANNED + 1))
    REPO_NAME=$(basename "$d")

    C_BR=$(git branch --show-current)

    if [ -z "$C_BR" ]; then
        echo "========== SKIP: $REPO_NAME (原因：当前处于 Detached HEAD 游离状态，无明确分支) ==========" >> "$ALL_DIFFS_TMP"
        cd "$ROOT_DIR"
        continue
    fi

    O_BR=$(git reflog show "$C_BR" | awk '/Created from/ {print $NF; exit}')
    O_BR_COMPARE="${O_BR#remotes/}"
    O_BR_COMPARE="${O_BR_COMPARE#origin/}"

    # 处理 reflog 返回 HEAD 字面量或为空的情况，fallback 到默认主分支
    if [ -z "$O_BR" ] || [ "$O_BR" == "HEAD" ] || [ "$C_BR" == "$O_BR_COMPARE" ]; then
        DEFAULT_BR=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
        if [ -z "$DEFAULT_BR" ]; then
            for br in main master develop; do
                if git rev-parse --verify "origin/$br" >/dev/null 2>&1; then
                    DEFAULT_BR="$br"
                    break
                fi
            done
        fi
        if [ -n "$DEFAULT_BR" ]; then
            O_BR="origin/$DEFAULT_BR"
            O_BR_COMPARE="$DEFAULT_BR"
        else
            echo "========== SKIP: $REPO_NAME (原因：未找到源分支且无法匹配默认主分支) ==========" >> "$ALL_DIFFS_TMP"
            cd "$ROOT_DIR"
            continue
        fi
    fi

    if [ "$C_BR" == "$O_BR_COMPARE" ]; then
        echo "========== SKIP: $REPO_NAME (原因：当前分支与源分支一致，无新提交) ==========" >> "$ALL_DIFFS_TMP"
        cd "$ROOT_DIR"
        continue
    fi

    git diff "$O_BR" HEAD > "$REPO_DIFF_TMP"

    if [ -s "$REPO_DIFF_TMP" ]; then
        echo "========== REPOSITORY: $REPO_NAME | BRANCHES: $O_BR -> $C_BR ==========" >> "$ALL_DIFFS_TMP"
        cat "$REPO_DIFF_TMP" >> "$ALL_DIFFS_TMP"
        echo -e "\n\n" >> "$ALL_DIFFS_TMP"
    else
        echo "========== SKIP: $REPO_NAME (原因：分支不同但代码无有效改动) ==========" >> "$ALL_DIFFS_TMP"
    fi

    rm -f "$REPO_DIFF_TMP"
    cd "$ROOT_DIR"
done

echo "TOTAL_SCANNED_REPOS: $TOTAL_SCANNED" >> "$ALL_DIFFS_TMP"

cat "$ALL_DIFFS_TMP"
rm -f "$ALL_DIFFS_TMP"
