#!/usr/bin/env bash
# build-retry-context.sh — Parse post-codegen-check output and generate .retry_context.json
# Usage: build-retry-context.sh <feat_id> <post_check_output_text>
# Output: writes features/{feat_id}/.retry_context.json
# Exit codes: 0=success, 1=missing args
set -euo pipefail

FEAT_ID="${1:?Usage: build-retry-context.sh <feat_id> <post_check_output>}"
POST_OUTPUT="${2:?Usage: build-retry-context.sh <feat_id> <post_check_output>}"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/paths.sh"

FEAT_DIR="$(get_feat_dir "" "$FEAT_ID")"
CONTEXT_FILE="$FEAT_DIR/.retry_context.json"

# Extract error codes from output
ERROR_CODES=()
if echo "$POST_OUTPUT" | grep -q "DAC-GEN-008"; then
  ERROR_CODES+=("DAC-GEN-008")
fi
if echo "$POST_OUTPUT" | grep -q "DAC-GEN-006"; then
  ERROR_CODES+=("DAC-GEN-006")
fi
if echo "$POST_OUTPUT" | grep -q "DAC-GEN-004"; then
  ERROR_CODES+=("DAC-GEN-004")
fi
if echo "$POST_OUTPUT" | grep -qE '文件名不符合|类名不符合'; then
  ERROR_CODES+=("NAMING")
fi

# Extract error file paths (lines starting with "   - lib/" or containing file paths in error messages)
ERROR_FILES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && ERROR_FILES+=("$line")
done < <(echo "$POST_OUTPUT" | grep -oE 'lib/[^ ]+\.dart' | sort -u)

# Determine if full context is needed
# DAC-GEN-008 (file missing) and DAC-GEN-004 (not modified) need spec/design context
NEEDS_FULL=false
for code in "${ERROR_CODES[@]}"; do
  if [[ "$code" == "DAC-GEN-008" || "$code" == "DAC-GEN-004" ]]; then
    NEEDS_FULL=true
    break
  fi
done

# Build JSON
CODES_JSON=$(printf '%s\n' "${ERROR_CODES[@]}" | jq -R . | jq -s .)
FILES_JSON=$(printf '%s\n' "${ERROR_FILES[@]}" | jq -R . | jq -s .)

# Truncate error message to avoid bloating the retry context
ERROR_MSG=$(echo "$POST_OUTPUT" | grep -E '❌|⚠️|error' | head -20)

jq -n \
  --argjson codes "$CODES_JSON" \
  --argjson files "$FILES_JSON" \
  --arg message "$ERROR_MSG" \
  --argjson needs_full "$NEEDS_FULL" \
  '{
    error_codes: $codes,
    error_files: $files,
    error_message: $message,
    needs_full_context: $needs_full
  }' > "$CONTEXT_FILE"

echo "✓ Retry context written: $CONTEXT_FILE"
echo "  错误码: ${ERROR_CODES[*]:-none}"
echo "  出错文件: ${#ERROR_FILES[@]} 个"
echo "  需要完整上下文: $NEEDS_FULL"
