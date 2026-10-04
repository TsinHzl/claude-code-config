#!/usr/bin/env bash
# audit-log.sh [feat_id] [event_type] [detail]
# audit-log.sh --summary
#
# 向 .dac/logs/execution.log 写入一条结构化日志，或输出统计报告。
#
# event_type 取值：
#   STEP:START   步骤开始
#   STEP:DONE    步骤完成（可附 "duration: Xm Xs"）
#   GATE:CHECK   门禁检查开始
#   GATE:PASS    门禁通过
#   GATE:FAIL    门禁失败（附错误摘要）
#   RETRY:N      第 N 次重试
#   CONSTRAINT:ADDED  约束已写入 constraints.md
#   STATUS:DONE  功能整体完成（附 "total: Xm Xs"）
#   STATUS:FAILED 功能失败

set -euo pipefail

LOG_FILE=".dac/logs/execution.log"

# --summary 模式：单次 awk 遍历，完成所有统计（兼容 macOS awk）
if [[ "${1:-}" == "--summary" ]]; then
  if [[ ! -f "$LOG_FILE" ]] || [[ ! -s "$LOG_FILE" ]]; then
    echo "ℹ️  无执行日志"
    exit 0
  fi

  awk '
  BEGIN {
    done_feats = 0
    failed_feats = 0
    retry_count = 0
    gate_fails = 0
    gate_fail_count_kept = 0
  }

  # 解析 ISO timestamp 为秒数（简化：假设同月内，仅计算日时分秒差）
  function parse_ts(line,    y, mo, d, h, m, s) {
    # 格式：[YYYY-MM-DDTHH:MM:SSZ]
    if (substr(line, 1, 1) != "[") return 0
    y  = substr(line, 2, 4) + 0
    mo = substr(line, 7, 2) + 0
    d  = substr(line, 10, 2) + 0
    h  = substr(line, 13, 2) + 0
    m  = substr(line, 16, 2) + 0
    s  = substr(line, 19, 2) + 0
    # 近似 epoch（忽略闰年/月天数，仅用于同一运行内的差值计算）
    return ((y * 365 + mo * 30 + d) * 86400) + (h * 3600) + (m * 60) + s
  }

  # 提取 [X] [Y] 格式中的字段
  function extract_field(line, n,    pos, count, start, end) {
    pos = 1
    count = 0
    while (count < n) {
      start = index(substr(line, pos), "[")
      if (start == 0) return ""
      pos = pos + start
      count++
    }
    start = pos
    end = index(substr(line, start), "]")
    if (end == 0) return ""
    return substr(line, start, end - 1)
  }

  {
    epoch = parse_ts($0)

    # 提取 feat_id（第 2 个 [...] 字段）和 event_type（第 3 个）
    feat_id = extract_field($0, 2)
    event_type = extract_field($0, 3)
    if (feat_id == "" || event_type == "") next

    # STATUS 统计
    if (event_type == "STATUS:DONE") {
      done_feats++
      finished[feat_id] = 1
    } else if (event_type == "STATUS:FAILED") {
      failed_feats++
      finished[feat_id] = 1
    }

    # RETRY 统计
    if (index(event_type, "RETRY:") == 1) {
      retry_count++
      retry_feats[feat_id] = 1
    }

    # GATE:FAIL 统计
    if (event_type == "GATE:FAIL") {
      gate_fails++
      if (gate_fail_count_kept < 5) {
        detail = $0
        sub(/.*\[GATE:FAIL\] ?/, "", detail)
        gate_fail_arr[gate_fail_count_kept] = detail
        gate_fail_count_kept++
      }
    }

    # STEP:START — 记录开始时间
    if (event_type == "STEP:START") {
      step_name = $0
      sub(/.*\[STEP:START\] ?/, "", step_name)
      gsub(/[[:space:]]+$/, "", step_name)
      step_starts[feat_id, step_name] = epoch
    }

    # STEP:DONE — 计算耗时
    if (event_type == "STEP:DONE") {
      step_name = $0
      sub(/.*\[STEP:DONE\] ?/, "", step_name)
      gsub(/[[:space:]]+$/, "", step_name)
      if ((feat_id, step_name) in step_starts && epoch > 0 && step_starts[feat_id, step_name] > 0) {
        dur = epoch - step_starts[feat_id, step_name]
        step_total[step_name] += dur
        step_count[step_name] += 1
      }
    }

    # 跟踪已启动的功能
    if (event_type == "STEP:START" && index($0, "feature-loop") > 0) {
      started_feats[feat_id] = 1
    }
  }

  END {
    # 统计进行中
    in_progress = 0
    for (fid in started_feats) {
      if (!(fid in finished)) in_progress++
    }

    printf "═══ DAC 执行统计 ═══\n\n"
    printf "功能统计：\n"
    printf "  完成：%d | 失败：%d | 进行中：%d | 总计：%d\n\n", done_feats, failed_feats, in_progress, done_feats + failed_feats + in_progress

    # 重试统计
    retry_feat_count = 0
    for (f in retry_feats) retry_feat_count++
    total_feats = done_feats + failed_feats + in_progress
    retry_rate = (total_feats > 0) ? int(retry_feat_count * 100 / total_feats) : 0
    printf "重试统计：\n"
    printf "  重试次数：%d | 涉及功能：%d | 重试率：%d%%\n\n", retry_count, retry_feat_count, retry_rate

    # 步骤平均耗时（按预定义顺序输出）
    split("ui-spec,codegen,code-review,feature-loop", order, ",")
    has_steps = 0
    for (i = 1; i <= 4; i++) {
      s = order[i]
      if (s in step_count && step_count[s] > 0) {
        if (!has_steps) { printf "步骤平均耗时：\n"; has_steps = 1 }
        avg = int(step_total[s] / step_count[s])
        avg_min = int(avg / 60)
        avg_sec = avg % 60
        printf "  %s：%dm %ds（%d 次）\n", s, avg_min, avg_sec, step_count[s]
      }
    }

    # 门禁失败
    if (gate_fails > 0) {
      printf "\n门禁失败：%d 次\n", gate_fails
      for (i = 0; i < gate_fail_count_kept; i++) {
        printf "  %s\n", gate_fail_arr[i]
      }
    }
  }
  ' "$LOG_FILE"

  exit 0
fi

# 正常写入模式
FEAT_ID=${1:-"_global"}
EVENT_TYPE=${2:?"用法: audit-log.sh <feat_id> <event_type> [detail]"}
DETAIL="${3:-}"

mkdir -p ".dac/logs"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [[ -n "$DETAIL" ]]; then
  echo "[$TIMESTAMP] [$FEAT_ID] [$EVENT_TYPE] $DETAIL" >> "$LOG_FILE"
else
  echo "[$TIMESTAMP] [$FEAT_ID] [$EVENT_TYPE]" >> "$LOG_FILE"
fi
