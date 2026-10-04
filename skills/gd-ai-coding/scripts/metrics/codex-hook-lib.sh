#!/usr/bin/env bash
# codex-hook-lib.sh — Codex apply_patch Hook 的事件解析与 Pre 快照

_dac_codex_parse_event() {
  local input="$1" expected_event="$2"
  DAC_CODEX_SESSION_ID=$(jq -r '.session_id // empty' <<<"$input")
  DAC_CODEX_TURN_ID=$(jq -r '.turn_id // empty' <<<"$input")
  DAC_CODEX_TOOL_USE_ID=$(jq -r '.tool_use_id // empty' <<<"$input")
  DAC_CODEX_CWD=$(jq -r '.cwd // empty' <<<"$input")
  DAC_CODEX_COMMAND=$(jq -r '.tool_input.command // empty' <<<"$input")
  [[ "$(jq -r '.hook_event_name // empty' <<<"$input")" == "$expected_event" ]] || return 1
  [[ "$(jq -r '.tool_name // empty' <<<"$input")" == "apply_patch" ]] || return 1
  [[ -n "$DAC_CODEX_SESSION_ID" && -n "$DAC_CODEX_TURN_ID" && -n "$DAC_CODEX_TOOL_USE_ID" && -n "$DAC_CODEX_COMMAND" ]] || return 1
  [[ "$DAC_CODEX_CWD" == /* ]] || return 1
  local schema actual_fingerprint expected_fingerprint
  schema=$(jq -cS 'def field_schema: to_entries | map({key:.key,type:(.value|type),fields:(if (.value|type)=="object" then (.value|to_entries|map({key:.key,type:(.value|type)})) else null end)}); field_schema' <<<"$input") || return 1
  actual_fingerprint="sha256:$(printf '%s' "$schema" | shasum -a 256 | awk '{print $1}')"
  case "$expected_event" in
    PreToolUse) expected_fingerprint='sha256:5e4b6ba5d10a287e45caba75522c94159e0ac2597400ed8d1556b83283cccf9b' ;;
    PostToolUse) expected_fingerprint='sha256:4f5bf0c9e73e1ddad554663fb1dd8ce798309d7c293cb74656c35db9f17d15b6' ;;
    *) return 1 ;;
  esac
  [[ "$actual_fingerprint" == "$expected_fingerprint" ]] || return 1
  DAC_CODEX_EVENT_ID=$(printf '%s\0%s\0%s' "$DAC_CODEX_SESSION_ID" "$DAC_CODEX_TURN_ID" "$DAC_CODEX_TOOL_USE_ID" | shasum -a 256 | awk '{print $1}')
  DAC_CODEX_COMMAND_SHA=$(printf '%s' "$DAC_CODEX_COMMAND" | shasum -a 256 | awk '{print $1}')
}

_dac_codex_patch_files() {
  printf '%s' "$DAC_CODEX_COMMAND" | grep -E '^\*\*\* (Add|Update|Delete) File: /' | sed -E 's/^\*\*\* (Add|Update|Delete) File: //' | sort -u
}

_dac_codex_cleanup_stale_snapshots() {
  local root="$1" now="$(date +%s)" ttl="${DAC_CODEX_SNAPSHOT_TTL_SECONDS:-300}" candidate created
  [[ "$now" =~ ^[0-9]+$ && "$ttl" =~ ^[0-9]+$ && -d "$root" && ! -L "$root" ]] || return 0
  for candidate in "$root"/* "$root"/.*.tmp "$root"/.*.processing; do
    [[ -d "$candidate" && ! -L "$candidate" ]] || continue
    if [[ ! -f "$candidate/meta.json" || -L "$candidate/meta.json" ]]; then
      find "$candidate" -maxdepth 0 -mmin +5 2>/dev/null | grep -q . && rm -rf "$candidate"
      continue
    fi
    created=$(iso_to_epoch "$(jq -r '.created_at // empty' "$candidate/meta.json" 2>/dev/null)")
    [[ "$created" =~ ^[0-9]+$ && "$created" -gt 0 && "$now" -ge "$created" && $((now - created)) -gt "$ttl" ]] && rm -rf "$candidate"
  done
}

dac_codex_create_pre_snapshot() {
  local input="$1"
  _dac_codex_parse_event "$input" PreToolUse || return 0
  local repo_root
  repo_root=$(git -C "$DAC_CODEX_CWD" rev-parse --show-toplevel 2>/dev/null) || return 0
  repo_root=$(cd "$repo_root" 2>/dev/null && pwd -P) || return 0
  local root="$DAC_STATE_HOME/codex-hook-snapshots/v1"
  local event_dir="$root/$DAC_CODEX_EVENT_ID"
  local temp_dir="$root/.${DAC_CODEX_EVENT_ID}.tmp"
  local consumed="$root/.${DAC_CODEX_EVENT_ID}.consumed"
  local files=() path path_dir existing index=0
  while IFS= read -r path; do
    [[ -n "$path" ]] || return 0
    path_dir=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P) || return 0
    path="$path_dir/$(basename "$path")"
    [[ "$path" == "$repo_root"/* && ! -L "$path" ]] || return 0
    dac_is_code_file "$path" || continue
    for existing in "${files[@]-}"; do
      [[ "$existing" == "$path" ]] && continue 2
    done
    files+=("$path")
  done < <(_dac_codex_patch_files)
  [[ ${#files[@]} -gt 0 ]] || return 0

  umask 077
  mkdir -p "$root"
  _dac_codex_cleanup_stale_snapshots "$root"
  [[ -e "$event_dir" || -e "$temp_dir" || -e "$consumed" ]] && return 0
  mkdir "$temp_dir" || return 0
  mkdir "$temp_dir/files"
  local files_json='[]'
  for path in "${files[@]}"; do
    index=$((index + 1))
    local before="files/$(printf '%06d' "$index").before"
    local existed=false
    if [[ -f "$path" && ! -L "$path" ]]; then
      cp "$path" "$temp_dir/$before" || { rm -rf "$temp_dir"; return 0; }
      existed=true
    else
      : > "$temp_dir/$before"
    fi
    files_json=$(jq --arg path "$path" --arg before "$before" --argjson existed "$existed" '. + [{path:$path,before:$before,existed:$existed}]' <<<"$files_json")
  done
  jq -n \
    --arg session_id "$DAC_CODEX_SESSION_ID" \
    --arg turn_id "$DAC_CODEX_TURN_ID" \
    --arg tool_use_id "$DAC_CODEX_TOOL_USE_ID" \
    --arg cwd "$DAC_CODEX_CWD" \
    --arg repo_root "$repo_root" \
    --arg command_sha256 "$DAC_CODEX_COMMAND_SHA" \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson files "$files_json" \
    '{schema:1,created_at:$created_at,event:{session_id:$session_id,turn_id:$turn_id,tool_use_id:$tool_use_id},cwd:$cwd,repo_root:$repo_root,tool_name:"apply_patch",command_sha256:$command_sha256,files:$files}' > "$temp_dir/meta.json" || { rm -rf "$temp_dir"; return 0; }
  chmod -R go-rwx "$temp_dir"
  mv "$temp_dir" "$event_dir" 2>/dev/null || rm -rf "$temp_dir"
}

_dac_codex_normalize_patch_files() {
  local repo_root="$1" path path_dir
  while IFS= read -r path; do
    [[ -n "$path" ]] || return 1
    path_dir=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P) || return 1
    path="$path_dir/$(basename "$path")"
    [[ "$path" == "$repo_root"/* && ! -L "$path" ]] || return 1
    dac_is_code_file "$path" || continue
    printf '%s\n' "$path"
  done < <(_dac_codex_patch_files)
}

_dac_codex_line_count() {
  [[ -f "$1" && ! -L "$1" ]] || { printf '0'; return 0; }
  awk 'END { print NR }' "$1" 2>/dev/null
}

# 领取并校验已存在的 Pre snapshot。stdout 输出 `正增行数<TAB>文件 JSON`；异常均返回非零。
dac_codex_consume_post_snapshot() {
  local input="$1"
  _dac_codex_parse_event "$input" PostToolUse || return 1
  local repo_root root event_dir processing consumed meta
  repo_root=$(git -C "$DAC_CODEX_CWD" rev-parse --show-toplevel 2>/dev/null) || return 1
  repo_root=$(cd "$repo_root" 2>/dev/null && pwd -P) || return 1
  root="$DAC_STATE_HOME/codex-hook-snapshots/v1"
  event_dir="$root/$DAC_CODEX_EVENT_ID"
  processing="$root/.${DAC_CODEX_EVENT_ID}.processing"
  consumed="$root/.${DAC_CODEX_EVENT_ID}.consumed"
  [[ -d "$event_dir" && ! -L "$event_dir" && ! -e "$processing" && ! -e "$consumed" ]] || return 1
  mv "$event_dir" "$processing" 2>/dev/null || return 1
  (umask 077; : > "$consumed") || { rm -rf "$processing"; return 1; }
  meta="$processing/meta.json"
  if ! jq -e --arg session "$DAC_CODEX_SESSION_ID" --arg turn "$DAC_CODEX_TURN_ID" --arg tool "$DAC_CODEX_TOOL_USE_ID" \
      --arg cwd "$DAC_CODEX_CWD" --arg root "$repo_root" --arg sha "$DAC_CODEX_COMMAND_SHA" '
        .schema == 1 and (.created_at | type == "string") and .tool_name == "apply_patch"
        and .event == {session_id:$session,turn_id:$turn,tool_use_id:$tool}
        and .cwd == $cwd and .repo_root == $root and .command_sha256 == $sha
        and (.files | type == "array" and length > 0)
      ' "$meta" >/dev/null 2>&1; then
    rm -rf "$processing"
    return 1
  fi
  local created now ttl
  created=$(iso_to_epoch "$(jq -r '.created_at' "$meta" 2>/dev/null)")
  now=$(date +%s)
  ttl="${DAC_CODEX_SNAPSHOT_TTL_SECONDS:-300}"
  [[ "$created" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ && "$ttl" =~ ^[0-9]+$ && "$created" -gt 0 && "$now" -ge "$created" && $((now - created)) -le "$ttl" ]] || { rm -rf "$processing"; return 1; }

  local expected actual files_json entry path before existed old_lines new_lines added=0
  expected=$(_dac_codex_normalize_patch_files "$repo_root" | sort -u) || { rm -rf "$processing"; return 1; }
  actual=$(jq -r '.files[].path' "$meta" 2>/dev/null | sort -u) || { rm -rf "$processing"; return 1; }
  [[ -n "$expected" && "$expected" == "$actual" ]] || { rm -rf "$processing"; return 1; }
  files_json=$(jq -c '.files | map({path:.path})' "$meta" 2>/dev/null) || { rm -rf "$processing"; return 1; }
  while IFS= read -r entry; do
    path=$(jq -r '.path' <<<"$entry")
    before=$(jq -r '.before' <<<"$entry")
    existed=$(jq -r '.existed' <<<"$entry")
    [[ "$path" == "$repo_root"/* && ! -L "$path" && "$before" =~ ^files/[0-9]{6}\.before$ && ( "$existed" == true || "$existed" == false ) ]] || { rm -rf "$processing"; return 1; }
    [[ -f "$processing/$before" && ! -L "$processing/$before" ]] || { rm -rf "$processing"; return 1; }
    old_lines=$(_dac_codex_line_count "$processing/$before")
    new_lines=$(_dac_codex_line_count "$path")
    [[ "$old_lines" =~ ^[0-9]+$ && "$new_lines" =~ ^[0-9]+$ ]] || { rm -rf "$processing"; return 1; }
    (( new_lines > old_lines )) && added=$((added + new_lines - old_lines))
  done < <(jq -c '.files[]' "$meta")
  rm -rf "$processing"
  printf '%s\t%s\n' "$added" "$files_json"
}
