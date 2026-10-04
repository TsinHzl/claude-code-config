#!/usr/bin/env bash
# pre-test-env-check.sh <feat_id>
# Layer 2.5 前置门禁：测试用例生成与验证（feature-loop 步骤 4.5）启动前，检查目标 Flutter 项目
# pubspec.yaml 是否已声明 flutter_test 及既有 mock 框架（mocktail/mockito），避免环境缺失被误判为代码缺陷触发无效重试
# （design.md 迁移方案："目标 Flutter 项目若此前从未配置 flutter_test 与 mock 框架，前置环境检查会
# 阻断并提示用户先补充依赖声明，不会静默跳过"）。
#
# exit code 语义与本仓库其他 harness 脚本一致：0=pass, 1=hard_fail

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "用法: pre-test-env-check.sh <feat_id>" >&2
  exit 1
fi

FEAT_ID=$1
PLATFORM="${PLATFORM:-flutter}"

if [[ "$PLATFORM" != "flutter" ]]; then
  echo "⏭ 非 flutter 平台（${PLATFORM}），本环境检查仅针对 flutter_test/mocktail/mockito，跳过"
  exit 0
fi

PUBSPEC="pubspec.yaml"
if [[ ! -f "$PUBSPEC" ]]; then
  echo "[DAC-GEN-012] ❌ 当前目录无 ${PUBSPEC}，无法检查测试依赖（feat: ${FEAT_ID}）" >&2
  exit 1
fi

# 匹配 dependencies / dev_dependencies / dependency_overrides 顶层区块下的依赖声明行
has_dep() {
  local name="$1"
  awk -v n="$name" '
    /^(dependencies|dev_dependencies|dependency_overrides):[[:space:]]*$/ { in_block=1; next }
    /^[a-zA-Z]/ && !/^[[:space:]]/ { in_block=0 }
    in_block && $0 ~ "^[[:space:]]+"n":" { found=1; exit }
    END { exit !found }
  ' "$PUBSPEC"
}

MISSING=()
has_dep "flutter_test" || MISSING+=("flutter_test")
if ! has_dep "mocktail" && ! has_dep "mockito"; then
  MISSING+=("mocktail 或 mockito")
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "[DAC-GEN-012] ❌ pubspec.yaml 缺失测试依赖声明：${MISSING[*]}（feat: ${FEAT_ID}）" >&2
  echo "   请在 dev_dependencies 中补充上述依赖后重新 Read 执行 feature-loop/SKILL.md（${FEAT_ID}）" >&2
  exit 1
fi

echo "✅ 测试环境检查通过（flutter_test + mocktail/mockito 已声明）"
