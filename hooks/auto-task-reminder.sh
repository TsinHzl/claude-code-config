#!/bin/bash
cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[TASK-TREE REMINDER] 主 agent 即将启动 sub-agent。按规则操作：1) TaskCreate 创建一个任务记录本次委派工作（subject 简述本次委派目标）；2) 立即 TaskUpdate 该任务 status: in_progress；3) sub-agent 返回后及时 TaskUpdate status: completed。如需拆分子任务，使用 addBlockedBy 建立父子层级。"}}
EOF
