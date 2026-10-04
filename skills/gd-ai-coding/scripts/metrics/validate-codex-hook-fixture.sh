#!/usr/bin/env bash
# validate-codex-hook-fixture.sh — 校验 Codex Hook 脱敏 fixture 的稳定配对与 schema
set -euo pipefail

fixture_path="${1:-}"
[[ $# -eq 1 && -f "$fixture_path" ]] || exit 1
command -v jq >/dev/null 2>&1 || exit 1
command -v shasum >/dev/null 2>&1 || exit 1

require() {
  jq -e "$1" "$fixture_path" >/dev/null 2>&1 || exit 1
}

require '.contract.codex_cli_version == "0.153.4"'
require '(.contract.event_key | type == "object" and ([.session_id, .turn_id, .tool_use_id] | all(.[]; type == "string" and length > 0)))'
require '(.pre_tool_use.hook_event_name == "PreToolUse" and .post_tool_use.hook_event_name == "PostToolUse")'
require '(.pre_tool_use.cwd | type == "string" and startswith("/"))'
require '(.post_tool_use.cwd == .pre_tool_use.cwd and .contract.cwd == .pre_tool_use.cwd)'
require '(.pre_tool_use.tool_name == "apply_patch" and .post_tool_use.tool_name == "apply_patch" and .contract.tool_name == .pre_tool_use.tool_name)'
require '(.pre_tool_use.tool_input.command | type == "string" and length > 0)'
require '(.post_tool_use.tool_input.command | type == "string" and length > 0)'
require '(.contract.affected_files as $files | ($files | type == "array" and length > 0 and all(.[]; type == "string" and startswith("/"))) and (($files | unique | length) == ($files | length)))'
require '(. as $payload | ["session_id", "turn_id", "tool_use_id"] | all(.[]; . as $key | $payload.pre_tool_use[$key] == $payload.post_tool_use[$key] and $payload.contract.event_key[$key] == $payload.pre_tool_use[$key]))'

schema=$(jq -cS '
  def field_schema:
    to_entries | map({
      key: .key,
      type: (.value | type),
      fields: (if (.value | type) == "object"
               then (.value | to_entries | map({key: .key, type: (.value | type)}))
               else null
               end)
    });
  [.pre_tool_use, .post_tool_use] | map(field_schema)
' "$fixture_path")
actual_fingerprint="sha256:$(printf '%s' "$schema" | shasum -a 256 | cut -d ' ' -f 1)"
expected_fingerprint=$(jq -r '.contract.schema_fingerprint // empty' "$fixture_path")
[[ "$actual_fingerprint" == "$expected_fingerprint" ]] || exit 1

patch_files() {
  jq -r "$1.tool_input.command | split(\"\\n\")[] | select(test(\"^\\\\*\\\\*\\\\* (Add|Update|Delete) File: /\")) | sub(\"^\\\\*\\\\*\\\\* (Add|Update|Delete) File: \"; \"\")" "$fixture_path" | LC_ALL=C sort -u
}

pre_files=$(patch_files '.pre_tool_use')
post_files=$(patch_files '.post_tool_use')
expected_files=$(jq -r '.contract.affected_files[]? | select(type == "string" and startswith("/"))' "$fixture_path" | LC_ALL=C sort -u)
[[ -n "$pre_files" && "$pre_files" == "$post_files" && "$pre_files" == "$expected_files" ]] || exit 1
