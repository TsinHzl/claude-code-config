#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Cache directory for today's stats
CACHE_DIR="$HOME/.claude/cache"
mkdir -p "$CACHE_DIR"

# Function to format token counts with K/M/B units
format_tokens() {
    local value=$1
    local result

    if [ $value -lt 1000 ]; then
        echo "$value"
    elif [ $value -lt 1000000 ]; then
        if command -v bc >/dev/null 2>&1; then
            result=$(echo "scale=4; $value / 1000" | bc)
            if [[ "$result" == .* ]]; then
                result="0${result}"
            fi
            result=$(echo "$result" | sed 's/0*$//' | sed 's/\.$//')
        else
            result=$(awk "BEGIN {printf \"%.4f\", $value / 1000}" | sed 's/0*$//' | sed 's/\.$//')
        fi
        echo "${result}K"
    elif [ $value -lt 1000000000 ]; then
        if command -v bc >/dev/null 2>&1; then
            result=$(echo "scale=4; $value / 1000000" | bc)
            if [[ "$result" == .* ]]; then
                result="0${result}"
            fi
            result=$(echo "$result" | sed 's/0*$//' | sed 's/\.$//')
        else
            result=$(awk "BEGIN {printf \"%.4f\", $value / 1000000}" | sed 's/0*$//' | sed 's/\.$//')
        fi
        echo "${result}M"
    else
        if command -v bc >/dev/null 2>&1; then
            result=$(echo "scale=4; $value / 1000000000" | bc)
            if [[ "$result" == .* ]]; then
                result="0${result}"
            fi
            result=$(echo "$result" | sed 's/0*$//' | sed 's/\.$//')
        else
            result=$(awk "BEGIN {printf \"%.4f\", $value / 1000000000}" | sed 's/0*$//' | sed 's/\.$//')
        fi
        echo "${result}B"
    fi
}

# Function to calculate today's total stats using session accumulator
# Uses the same data source as the Session display (stdin JSON)
# Args: $1=session_id $2=session_tokens $3=session_cost
calculate_today_stats() {
    local session_id="$1"
    local sess_tokens="$2"
    local sess_cost="$3"
    local today_date=$(date +%Y-%m-%d)
    local acc_file="$CACHE_DIR/today_accumulator.json"

    # Initialize or reset accumulator if date changed
    local acc_date=""
    if [ -f "$acc_file" ]; then
        acc_date=$(jq -r '.date // ""' "$acc_file" 2>/dev/null)
    fi

    if [ "$acc_date" != "$today_date" ]; then
        echo "{\"date\":\"$today_date\",\"sessions\":{},\"total_tokens\":0,\"total_cost\":0}" > "$acc_file"
    fi

    # Get previously recorded values for this session
    local prev_tokens=$(jq -r --arg sid "$session_id" '.sessions[$sid].tokens // 0' "$acc_file" 2>/dev/null)
    local prev_cost=$(jq -r --arg sid "$session_id" '.sessions[$sid].cost // "0"' "$acc_file" 2>/dev/null)

    # Ensure numeric defaults
    prev_tokens=${prev_tokens:-0}
    prev_cost=${prev_cost:-0}

    # Only update if current values are greater (cumulative values only grow)
    local needs_update=0
    if [ "$sess_tokens" -gt "$prev_tokens" ] 2>/dev/null; then
        needs_update=1
    elif [ "$(awk "BEGIN {print ($sess_cost > $prev_cost) ? 1 : 0}")" = "1" ]; then
        needs_update=1
    fi

    if [ "$needs_update" = "1" ]; then
        local delta_tokens=$((sess_tokens - prev_tokens))
        local delta_cost=$(awk "BEGIN {printf \"%.6f\", $sess_cost - $prev_cost}")

        # Update accumulator atomically
        local tmp_file="${acc_file}.tmp.$$"
        jq --arg sid "$session_id" \
           --argjson st "$sess_tokens" \
           --arg sc "$sess_cost" \
           --argjson dt "$delta_tokens" \
           --arg dc "$delta_cost" \
           '.sessions[$sid] = {tokens: $st, cost: $sc} |
            .total_tokens = (.total_tokens + $dt) |
            .total_cost = (.total_cost + ($dc | tonumber))' \
           "$acc_file" > "$tmp_file" 2>/dev/null && mv "$tmp_file" "$acc_file"
    fi

    # Read current totals
    local total_tokens=$(jq -r '.total_tokens // 0' "$acc_file" 2>/dev/null)
    local total_cost=$(jq -r '.total_cost // 0' "$acc_file" 2>/dev/null)

    echo "${total_tokens}|${total_cost}"
}

# Extract model info
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')

# Extract total tokens for session (cumulative)
input_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
output_tokens=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
total_tokens=$((input_tokens + output_tokens))

# Extract session cost from the cost field (matches /cost command)
session_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# Extract session ID for today's accumulator
session_id=$(echo "$input" | jq -r '.session_id // "unknown"')

# Calculate per-message delta (current session cumulative - last recorded)
LAST_FILE="$CACHE_DIR/last_session_${session_id}.json"
last_tokens=0
last_cost="0"
if [ -f "$LAST_FILE" ]; then
    last_tokens=$(jq -r '.tokens // 0' "$LAST_FILE" 2>/dev/null)
    last_cost=$(jq -r '.cost // "0"' "$LAST_FILE" 2>/dev/null)
fi
last_tokens=${last_tokens:-0}
last_cost=${last_cost:-0}

msg_tokens=$((total_tokens - last_tokens))
msg_cost=$(awk "BEGIN {printf \"%.4f\", $session_cost - $last_cost}")

# Save current cumulative for next round
printf '{"tokens":%d,"cost":"%s"}\n' "$total_tokens" "$session_cost" > "$LAST_FILE"

# Per-window request counter (increments each time a new API response is detected)
REQ_COUNT_FILE="$CACHE_DIR/req_count_${session_id}.txt"
if [ "$msg_tokens" -gt 0 ] 2>/dev/null; then
    req_count=$(cat "$REQ_COUNT_FILE" 2>/dev/null || echo 0)
    req_count=$((req_count + 1))
    echo "$req_count" > "$REQ_COUNT_FILE"
else
    req_count=$(cat "$REQ_COUNT_FILE" 2>/dev/null || echo 0)
fi

# Get today's stats (accumulates across all sessions, resets at midnight)
today_stats=$(calculate_today_stats "$session_id" "$total_tokens" "$session_cost")
today_tokens=$(echo "$today_stats" | cut -d'|' -f1)
today_cost=$(echo "$today_stats" | cut -d'|' -f2)

# Format output
output="${model}"

# Add per-message delta stats
if [ $msg_tokens -gt 0 ]; then
    msg_tokens_formatted=$(format_tokens $msg_tokens)
    # Remove trailing zeros from msg_cost
    msg_cost_formatted=$(echo "$msg_cost" | sed 's/0*$//' | sed 's/\.$//')
    output="${output} | 消息: ${msg_tokens_formatted} \$${msg_cost_formatted}"
fi

# Add session stats (cumulative)
if [ $total_tokens -gt 0 ]; then
    tokens_formatted=$(format_tokens $total_tokens)

    # Remove trailing zeros from session_cost
    if command -v bc >/dev/null 2>&1; then
        cost_formatted=$(echo "scale=4; $session_cost / 1" | bc)
        if [[ "$cost_formatted" == .* ]]; then
            cost_formatted="0${cost_formatted}"
        fi
        cost_formatted=$(echo "$cost_formatted" | sed 's/\.0*$//' | sed 's/\(\.[0-9]*[1-9]\)0*$/\1/')
    else
        cost_formatted=$(awk "BEGIN {printf \"%.4f\", $session_cost}")
        cost_formatted=$(echo "$cost_formatted" | sed 's/0*$//' | sed 's/\.$//')
    fi
    output="${output} | 会话: ${tokens_formatted} \$${cost_formatted}"
fi

# Add today's stats (ALWAYS show, even if 0)
today_tokens_formatted=$(format_tokens $today_tokens)

# Format today's cost
if command -v bc >/dev/null 2>&1; then
    today_cost_formatted=$(echo "scale=4; $today_cost / 1" | bc)
    if [[ "$today_cost_formatted" == .* ]]; then
        today_cost_formatted="0${today_cost_formatted}"
    fi
    today_cost_formatted=$(echo "$today_cost_formatted" | sed 's/\.0*$//' | sed 's/\(\.[0-9]*[1-9]\)0*$/\1/')
else
    today_cost_formatted=$(awk "BEGIN {printf \"%.4f\", $today_cost}")
    today_cost_formatted=$(echo "$today_cost_formatted" | sed 's/0*$//' | sed 's/\.$//')
fi
output="${output} | 今日: ${today_tokens_formatted} \$${today_cost_formatted}"

# Append per-window request count
output="${output} | #${req_count}"

# Append context usage percentage
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used_pct" ]; then
    used_pct_int=$(printf "%.0f" "$used_pct")
    if [ "$used_pct_int" -le 20 ]; then
        ctx_color="\033[32m"
    elif [ "$used_pct_int" -le 50 ]; then
        ctx_color="\033[36m"
    elif [ "$used_pct_int" -le 70 ]; then
        ctx_color="\033[33m"
    elif [ "$used_pct_int" -le 85 ]; then
        ctx_color="\033[91m"
    else
        ctx_color="\033[1;31m"
    fi
    output="${output} | ${ctx_color}Ctx: ${used_pct_int}%\033[0m"
fi

# Append current working directory (rightmost element)
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')
if [ -n "$cwd" ]; then
    output="${output} | \033[32m${cwd}\033[0m"
fi

printf "%b\n" "$output"