#!/usr/bin/env bash
# init-config.sh — 自动扫描目标 Flutter 项目，生成 openspec/config.yaml
#
# 行为：
#   - openspec/config.yaml 已存在 → 直接 exit 0（幂等，不覆盖用户已修改内容）
#   - pubspec.yaml 不存在 → exit 1（非 Flutter 项目根目录）
#   - 否则：扫描 pubspec.yaml 依赖 + lib/ 目录结构 → 生成 openspec/config.yaml
#
# 调用：bash ~/.claude/skills/gd-ai-coding/scripts/openspec/init-config.sh
# 工作目录：必须在目标 Flutter 项目根目录执行

set -euo pipefail

CONFIG_FILE="openspec/config.yaml"
PUBSPEC="pubspec.yaml"

# 显式打印工作目录到 stderr，便于调用方验证 cwd 未漂移
echo "ℹ init-config: cwd=$(pwd)" >&2

# ──────────────────────────────────────────────────
# 幂等：已存在则跳过
# ──────────────────────────────────────────────────
if [[ -f "$CONFIG_FILE" ]]; then
  echo "✓ $CONFIG_FILE 已存在，跳过自动生成（幂等）"
  exit 0
fi

# ──────────────────────────────────────────────────
# 前置：必须在 Flutter 项目根目录
# ──────────────────────────────────────────────────
if [[ ! -f "$PUBSPEC" ]]; then
  echo "❌ 当前目录无 ${PUBSPEC}，无法识别 Flutter 项目" >&2
  echo "   请在目标 Flutter 项目根目录执行此脚本" >&2
  exit 1
fi

mkdir -p "$(dirname "$CONFIG_FILE")"

# ──────────────────────────────────────────────────
# 工具：检查依赖是否存在于 pubspec.yaml dependencies / dev_dependencies 区
#   匹配 "  <name>:" 行（顶层缩进 2 空格的依赖项）
# ──────────────────────────────────────────────────
has_dep() {
  local name="$1"
  awk -v n="$name" '
    /^(dependencies|dev_dependencies|dependency_overrides):[[:space:]]*$/ { in_block=1; next }
    /^[a-zA-Z]/ && !/^[[:space:]]/ { in_block=0 }
    in_block && $0 ~ "^[[:space:]]+"n":" { found=1; exit }
    END { exit !found }
  ' "$PUBSPEC"
}

# ──────────────────────────────────────────────────
# 检测状态管理（按优先级返回第一个命中的）
# ──────────────────────────────────────────────────
STATE_MGMT="Unknown / not detected"
if has_dep "flutter_bloc"; then
  STATE_MGMT="BLoC (flutter_bloc)"
elif has_dep "hooks_riverpod"; then
  STATE_MGMT="Riverpod (hooks_riverpod)"
elif has_dep "flutter_riverpod"; then
  STATE_MGMT="Riverpod (flutter_riverpod)"
elif has_dep "riverpod"; then
  STATE_MGMT="Riverpod"
elif has_dep "get"; then
  STATE_MGMT="GetX"
elif has_dep "provider"; then
  STATE_MGMT="Provider"
elif has_dep "mobx"; then
  STATE_MGMT="MobX"
fi

# ──────────────────────────────────────────────────
# 检测路由
# ──────────────────────────────────────────────────
ROUTING="Navigator 1.0 / not detected"
if has_dep "go_router"; then
  ROUTING="GoRouter"
elif has_dep "auto_route"; then
  ROUTING="AutoRoute"
elif has_dep "nacho"; then
  ROUTING="Nacho (内部框架)"
fi

# ──────────────────────────────────────────────────
# 检测依赖注入
# ──────────────────────────────────────────────────
DI="not detected"
if has_dep "get_it" && has_dep "injectable"; then
  DI="GetIt + Injectable"
elif has_dep "get_it"; then
  DI="GetIt"
elif has_dep "lomo"; then
  DI="Lomo (内部 DI 框架)"
elif [[ "$STATE_MGMT" == Riverpod* ]]; then
  DI="Riverpod (内置 DI)"
fi

# ──────────────────────────────────────────────────
# 检测架构（feature-first vs layer-first）
# ──────────────────────────────────────────────────
ARCH="Unknown"
if [[ -d "lib/features" ]]; then
  ARCH="feature-first (lib/features/)"
elif [[ -d "lib/src" ]]; then
  feature_dirs=$(find lib/src -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$feature_dirs" -ge 3 ]]; then
    ARCH="feature-first (lib/src/{feature}/)"
  else
    ARCH="lib/src/ (架构不明确)"
  fi
elif [[ -d "lib/screens" ]] || [[ -d "lib/pages" ]]; then
  ARCH="layer-first (lib/screens|pages + lib/services + ...)"
fi

# ──────────────────────────────────────────────────
# 检测测试栈
# 改用显式 if/then 分支：避免 set -e + && 短路在不同 Bash 版本下行为不一致
# ──────────────────────────────────────────────────
TESTING_PARTS=()
if has_dep "flutter_test"; then TESTING_PARTS+=("flutter_test (unit)"); fi
if has_dep "integration_test"; then TESTING_PARTS+=("integration_test (e2e)"); fi
if has_dep "mocktail"; then TESTING_PARTS+=("mocktail"); fi
if has_dep "mockito"; then TESTING_PARTS+=("mockito"); fi
if [[ -d "test" ]]; then TESTING_PARTS+=("test/ 目录存在"); fi
if [[ -d "integration_test" ]]; then TESTING_PARTS+=("integration_test/ 目录存在"); fi

# 先判长度再展开：macOS Bash 3.2 下 set -u + 空数组 ${arr[*]:-default} 会触发 unbound variable
if [[ ${#TESTING_PARTS[@]} -eq 0 ]]; then
  TESTING="not detected"
else
  TESTING="${TESTING_PARTS[*]}"
fi

# ──────────────────────────────────────────────────
# 提取项目名（pubspec.yaml 顶部 name: 字段）
# 消毒：strip 行内注释 → strip 引号 → 仅保留 [a-z0-9_]，防止 YAML 注入
# ──────────────────────────────────────────────────
RAW_NAME=$(awk '
  /^name:/ {
    sub(/^name:[[:space:]]*/, "")
    sub(/[[:space:]]*#.*$/, "")     # 移除行内注释
    sub(/^["'\'']/, "")              # 移除前导引号
    sub(/["'\'']$/, "")              # 移除尾部引号
    gsub(/[[:space:]]+$/, "")        # 移除尾部空白
    print
    exit
  }
' "$PUBSPEC")
# 仅允许 pubspec 合法字符（lowercase + digit + underscore），其他字符替换为 _
PROJECT_NAME=$(printf '%s' "$RAW_NAME" | tr -c 'a-z0-9_' '_' | sed 's/__*/_/g; s/^_//; s/_$//')
PROJECT_NAME="${PROJECT_NAME:-flutter_project}"

# ──────────────────────────────────────────────────
# 写入 config.yaml
# ──────────────────────────────────────────────────
cat > "$CONFIG_FILE" <<YAML
# OpenSpec config — auto-generated by scripts/openspec/init-config.sh
# 项目：${PROJECT_NAME}
# 生成于：$(date +%Y-%m-%d)
# 如需调整，直接编辑本文件，后续运行将跳过覆盖（幂等）。

schema: spec-driven

context: |
  Project: ${PROJECT_NAME}
  Tech stack: Flutter/Dart
  Architecture: ${ARCH}
  State management: ${STATE_MGMT}
  Routing: ${ROUTING}
  Dependency injection: ${DI}
  Testing: ${TESTING}

rules:
  proposal:
    - What Changes 必须列出每个新增/修改文件的完整路径和用途
    - 文件路径必须符合本项目目录规范
    - 共享层文件（lib/shared/、lib/core/）必须独立标注
  specs:
    - 从 prd-spec.md §3.x 功能点提取场景（正常流程 + 异常/边界）
    - 每个 Requirement 至少包含一个 Scenario
  design:
    - 必须包含状态管理、路由、依赖注入的决策及替代方案
    - 技术决策须与本项目当前架构（${STATE_MGMT} / ${ROUTING} / ${DI}）一致
  tasks:
    - 每个分组对应一个可独立交付的功能单元
    - 分组顺序反映依赖关系（被依赖的排前面）
    - 共享层（service/core）单独分组并排在最前
    - 每个 task 粒度：一个 session 可完成
YAML

echo "✓ 已生成 $CONFIG_FILE"
echo "  - 项目名: $PROJECT_NAME"
echo "  - 架构: $ARCH"
echo "  - 状态管理: $STATE_MGMT"
echo "  - 路由: $ROUTING"
echo "  - DI: $DI"
echo "  - 测试: $TESTING"
