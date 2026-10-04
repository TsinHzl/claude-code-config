#!/usr/bin/env bash
# paths.sh — Canonical path helpers for openspec/changes/{req_name}/ directory structure.
# Source this file from any script that needs to locate artifacts.

get_change_dir() {
  local req_name="${1:-}"
  if [[ -z "$req_name" ]]; then
    req_name=$(jq -r '.req_name // empty' .dac/state.json 2>/dev/null)
  fi
  if [[ -z "$req_name" ]]; then
    echo "ERROR: req_name not found" >&2
    return 1
  fi
  echo "openspec/changes/$req_name"
}

get_prd_dir() {
  echo "$(get_change_dir "$1")/prd"
}

get_design_dir() {
  echo "$(get_change_dir "$1")/ui"
}

get_features_dir() {
  echo "$(get_change_dir "$1")/features"
}

get_feat_dir() {
  local req_name="$1"
  local feat_id="$2"
  echo "$(get_features_dir "$req_name")/$feat_id"
}
