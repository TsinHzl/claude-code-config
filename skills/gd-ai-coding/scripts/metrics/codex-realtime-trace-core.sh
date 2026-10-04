#!/usr/bin/env bash
# codex-realtime-trace-core.sh — 已验证 Codex apply_patch 事件的双维实时统计核心

_dac_codex_trace_safe_key() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

# 共用需求解析：state 通道（owner_committer == committer 取 req_name）优先，
# 其次 bind 通道（branch + committer 双匹配取 req）。输出 req，返回 1 表示无法确定需求。
_dac_codex_trace_resolve_requirement() {
  local state_file="$1" bind_file="$2" committer="$3" req="" branch owner
  if [[ -f "$state_file" ]] && [[ "$(jq -r '.owner_committer // empty' "$state_file" 2>/dev/null)" == "$committer" ]]; then
    req=$(jq -r '.req_name // empty' "$state_file" 2>/dev/null)
  elif [[ -f "$bind_file" ]]; then
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || true)
    owner=$(jq -r '.committer // empty' "$bind_file" 2>/dev/null)
    if [[ -n "$branch" && "$owner" == "$committer" && "$(jq -r '.branch // empty' "$bind_file" 2>/dev/null)" == "$branch" ]]; then
      req=$(jq -r '.req // empty' "$bind_file" 2>/dev/null)
    fi
  fi
  [[ -n "$req" ]] || return 1
  printf '%s' "$req"
}

_dac_codex_trace_requirement_file() {
  local req
  req=$(_dac_codex_trace_resolve_requirement "$2" "$3" "$1") || return 1
  printf '.dac/trace/%s.json' "$(_dac_codex_trace_safe_key "$req")"
}

_dac_codex_trace_initialize_json() {
  local file="$1" initial="$2" waited=0
  local lockdir="${file}.init.lock"
  if [[ -d "$lockdir" ]] && find "$lockdir" -maxdepth 0 -mmin +1 2>/dev/null | grep -q .; then
    rmdir "$lockdir" 2>/dev/null || true
  fi
  while ! mkdir "$lockdir" 2>/dev/null; do
    sleep 0.05
    waited=$((waited + 1))
    [[ "$waited" -lt 200 ]] || return 1
  done
  if [[ ! -e "$file" && ! -L "$file" ]]; then
    (umask 077; printf '%s' "$initial" > "$file") || { rmdir "$lockdir" 2>/dev/null; return 1; }
  fi
  [[ -f "$file" && ! -L "$file" ]] || { rmdir "$lockdir" 2>/dev/null; return 1; }
  rmdir "$lockdir" 2>/dev/null
}

# 用法：dac_record_codex_realtime_trace <repo-root> <event-id> <positive-lines> <files-json>
# 调用方必须已验证并原子领取 snapshot；此函数不处理不可信 Hook stdin。
dac_record_codex_realtime_trace() {
  local repo_root="$1" event_id="$2" added="$3" files_json="$4"
  [[ "$added" =~ ^[0-9]+$ && "$added" -gt 0 ]] || return 0
  git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  (
    cd "$repo_root" || exit 0
    local committer repo had_dac state_file=.dac/state.json bind_file=.dac/req-bind
    committer=$(git config user.email 2>/dev/null || true)
    [[ -n "$committer" ]] || exit 0
    repo=$(_dac_trace_repo_path 2>/dev/null || true)
    [[ -n "$repo" ]] || exit 0
    if [[ -f "$state_file" || -f "$bind_file" ]]; then had_dac=1; else had_dac=0; fi

    local personal_dir="$DAC_STATE_HOME/personal-trace"
    local personal_file="$personal_dir/$(_dac_codex_trace_safe_key "${committer}__${repo}").json"
    mkdir -p "$personal_dir" 2>/dev/null || exit 0
    [[ -d "$personal_dir" && ! -L "$personal_dir" ]] || exit 0
    _dac_codex_trace_initialize_json "$personal_file" '{"committed_total":0,"total":0,"count":0,"unused_total":0,"files":{}}' || exit 0
    if [[ -f "$personal_file" && ! -L "$personal_file" ]]; then
      atomic_jq '.total = ((.total // 0) + $added)
        | .count = ((.count // 0) + 1)
        | .unused_total = (if $had_dac == 1 then (.unused_total // 0) else ((.unused_total // 0) + $added) end)
        | .committed_total = (.committed_total // 0)
        | .files = (.files // {})' \
        "$personal_file" --argjson added "$added" --argjson had_dac "$had_dac" 2>/dev/null || true
      local committed total count unused
      committed=$(jq -r '.committed_total // 0' "$personal_file" 2>/dev/null)
      total=$(jq -r '.total // 0' "$personal_file" 2>/dev/null)
      count=$(jq -r '.count // 0' "$personal_file" 2>/dev/null)
      unused=$(jq -r '.unused_total // 0' "$personal_file" 2>/dev/null)
      [[ "$committed" =~ ^[0-9]+$ && "$total" =~ ^[0-9]+$ && "$count" =~ ^[0-9]+$ && "$unused" =~ ^[0-9]+$ ]] || exit 0
      (_report_personal_trace "$((committed + total))" "$count" "$unused" 2>/dev/null) >/dev/null 2>&1 &
    fi

    local trace_file
    trace_file=$(_dac_codex_trace_requirement_file "$committer" "$state_file" "$bind_file" 2>/dev/null || true)
    [[ -n "$trace_file" ]] || exit 0
    [[ -d .dac && ! -L .dac ]] || exit 0
    mkdir -p .dac/trace 2>/dev/null || exit 0
    [[ -d .dac/trace && ! -L .dac/trace ]] || exit 0
    local trace_root
    trace_root=$(cd .dac/trace 2>/dev/null && pwd -P) || exit 0
    [[ "$trace_root" == "$repo_root/.dac/trace" ]] || exit 0
    trace_file="$trace_root/${trace_file##*/}"
    local req_name
    req_name=$(_dac_codex_trace_resolve_requirement "$state_file" "$bind_file" "$committer" 2>/dev/null) || exit 0
    _dac_codex_trace_initialize_json "$trace_file" '{}' || exit 0
    atomic_jq '.req_name = $req
      | .write_events = ((.write_events // []) + [{tool:"apply_patch", event_id:$event_id, files:$files, ts:(now * 1000 | floor)}])
      | .write_lines_added = ((.write_lines_added // 0) + $added)' \
      "$trace_file" --arg event_id "$event_id" --argjson files "$files_json" --argjson added "$added" \
      --arg req "$req_name" 2>/dev/null || exit 0
    (_report_progress "$trace_file" 2>/dev/null) >/dev/null 2>&1 &
  )
}
