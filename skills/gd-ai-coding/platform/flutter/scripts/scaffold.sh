#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scaffold-feature.sh — 零 LLM token 预生成 Flutter 骨架文件
# ─────────────────────────────────────────────────────────────────────────────
#
# 为什么需要骨架预生成：
#
#   1. 省 token — 把确定性模板从 LLM 输出中剥离
#      Comp/Controller/Repo/Model/View 的类声明、part of、DI 注册、生命周期壳
#      是 100% 确定的（由文件名和项目架构规范决定），让 LLM 生成纯属浪费输出
#      token。骨架约占一个 feature 总代码量的 30-40%，全部零 token 产出。
#
#   2. 让 sub-agent 用 Edit 而非 Write — 提升准确率 + 降低破坏性
#      - 有骨架 → sub-agent 用 Edit 在 // TODO: business logic 标记处填充逻辑
#      - 无骨架 → sub-agent 必须用 Write 从零创建整个文件
#      Edit 模式下 LLM 只输出 diff，类结构/import/DI 注册不会被"创造性发挥"
#      搞错；失败时只需回滚业务逻辑段，骨架结构不受影响。
#
# ─────────────────────────────────────────────────────────────────────────────
# 调用时机：feature/feature-harness.sh pre-codegen 阶段，codegen sub-agent 启动前
# 作用：根据 feature-plan.json 的 proposal_scope.new_files 列表，按文件角色
#       (comp/comp_impl/controller/repo/model/view) 生成带类声明和生命周期壳的
#       Dart 骨架文件。Sub-agent 随后以 Edit 模式填充业务逻辑。
#
# 输入：
#   $1 — feat_id（必填）
#   feature-plan.json — 从中读取 type、proposal_scope.new_files
#
# 输出：在 Flutter 项目工作目录中按 new_files 路径创建骨架 .dart 文件
#
# 退出码：0=成功生成, 1=错误(plan不存在/feature找不到/孤儿part), 2=无 new_files 可生成
# 幂等性：已存在的文件跳过不覆盖
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

FEAT_ID="${1:?Usage: scaffold-feature.sh <feat_id>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$SKILL_ROOT/scripts/paths.sh"

CHANGE_DIR="$(get_change_dir)"
PLAN_FILE="$CHANGE_DIR/feature-plan.json"

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "ERROR: $PLAN_FILE not found" >&2
  exit 1
fi

# Extract feature metadata
FEAT_JSON=$(jq --arg id "$FEAT_ID" '
  (if type == "array" then . else .features end)
  | map(select(.id == $id)) | .[0] // empty
' "$PLAN_FILE")

if [[ -z "$FEAT_JSON" || "$FEAT_JSON" == "null" ]]; then
  echo "ERROR: feature $FEAT_ID not found in $PLAN_FILE" >&2
  exit 1
fi

FEAT_TYPE=$(echo "$FEAT_JSON" | jq -r '.type // "page"')

# FEAT_TYPE 白名单 — 未知类型默认按 page 处理但 warn,便于及早发现 plan schema 漂移
case "$FEAT_TYPE" in
  page|service|refactor|widget|dialog|component) ;;
  *) echo "WARN: unknown feat_type '$FEAT_TYPE', falling back to page semantics" >&2 ;;
esac

# Get new_files list (bash 3.2 compatible — no mapfile)
NEW_FILES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && NEW_FILES+=("$line")
done < <(echo "$FEAT_JSON" | jq -r '.proposal_scope.new_files[]? // empty')

if [[ ${#NEW_FILES[@]} -eq 0 ]]; then
  echo "SKIP: no new_files in proposal_scope for $FEAT_ID" >&2
  exit 2
fi

# ── Helpers ──────────────────────────────────────────────────────────────────

# Convert snake_case filename to PascalCase class name (macOS compatible)
to_pascal_case() {
  local input="$1"
  echo "$input" | perl -pe 's/(^|_)([a-z])/uc($2)/ge'
}

# Detect role from filename suffix.
# 注意:*_comp_impl 必须在 *_comp 之前匹配。
detect_role() {
  local base
  base=$(basename "$1" .dart)
  case "$base" in
    *_comp_impl) echo "comp_impl" ;;
    *_comp)      echo "comp" ;;
    *_controller) echo "controller" ;;
    *_repo)      echo "repo" ;;
    *_model)     echo "model" ;;
    *_view)      echo "view" ;;
    *)           echo "unknown" ;;
  esac
}

# ── Single-pass preprocessing of NEW_FILES ───────────────────────────────────
# 一次遍历同时算出:每个文件的 role(ROLES[]) / _comp 路径(COMP_PATH) / feature 名
# (FEATURE_NAME) / 业务剖面(PROFILE) / part-of 文件计数(PART_OF_COUNT)。
# 替代原来三次独立遍历(derive_feature_name / detect_profile / gen_comp 的 parts 循环)。

ROLES=()
COMP_PATH=""
FEATURE_NAME=""
PROFILE_HAS_REPO=0
PROFILE_HAS_MODEL=0
PART_OF_COUNT=0

for f in "${NEW_FILES[@]}"; do
  role=$(detect_role "$f")
  ROLES+=("$role")
  case "$role" in
    comp)
      COMP_PATH="$f"
      base=$(basename "$f" .dart)
      FEATURE_NAME="${base%_comp}"
      ;;
    repo)
      PROFILE_HAS_REPO=1
      PART_OF_COUNT=$((PART_OF_COUNT + 1))
      ;;
    model)
      PROFILE_HAS_MODEL=1
      PART_OF_COUNT=$((PART_OF_COUNT + 1))
      ;;
    comp_impl|controller|view)
      PART_OF_COUNT=$((PART_OF_COUNT + 1))
      ;;
  esac
done

# 无 _comp.dart 库文件时降级为 standalone 模式:各文件作为独立 Dart 文件生成,
# 不产出 part of 指令,避免引用不存在的 library 导致编译失败。
STANDALONE=0
if [[ -z "$COMP_PATH" && $PART_OF_COUNT -gt 0 ]]; then
  STANDALONE=1
  echo "INFO: No *_comp.dart found — switching to standalone mode (no part-of directives)." >&2
fi

# 无 _comp 且无 part-of 角色(纯独立文件场景,例如 refactor):从首个文件剥后缀兜底
if [[ -z "$FEATURE_NAME" ]]; then
  FEATURE_NAME=$(basename "${NEW_FILES[0]}" .dart)
  for suffix in _comp_impl _controller _repo _model _view; do
    FEATURE_NAME="${FEATURE_NAME%$suffix}"
  done
fi

CLASS_NAME=$(to_pascal_case "$FEATURE_NAME")

if [[ $PROFILE_HAS_REPO -eq 1 && $PROFILE_HAS_MODEL -eq 1 ]]; then
  PROFILE="business"
else
  PROFILE="minimal"
fi

# ── Template generators ──────────────────────────────────────────────────────
#
# 模板基线：参考 lomo_component Mason brick
# (git@git.xiaojukeji.com:global-driver/flutter/lomo_component.git)
# 该 brick 是仓库官方组件骨架样板，A 集 import 严格压到 material + lomo。
# business profile 在此基础上叠加 driver_flutter_sdk 的 DBase/DRepo/DrvBaseViewWrapper。

gen_comp() {
  local filepath="$1"
  local comp_dir
  comp_dir=$(dirname "$filepath")

  # part 指令使用预处理好的 ROLES[],避免再次遍历调用 detect_role
  local parts=""
  local i
  for i in "${!NEW_FILES[@]}"; do
    local r="${ROLES[$i]}"
    [[ "$r" == "comp" || "$r" == "unknown" ]] && continue
    local f="${NEW_FILES[$i]}"
    local rel_path
    rel_path=$(perl -e 'use File::Spec; print File::Spec->abs2rel($ARGV[0], $ARGV[1])' "$f" "$comp_dir")
    parts+="part '$rel_path';\n"
  done

  # A 集 import：brick 标准,只保证类声明可编译
  local imports="import 'package:flutter/material.dart';\nimport 'package:lomo/lomo.dart';"

  # business profile 追加的 driver_flutter_sdk imports
  if [[ "$PROFILE" == "business" ]]; then
    imports+="\n\nimport 'package:driver_flutter_sdk/base/controller/drv_base_controller.dart';"
    imports+="\nimport 'package:driver_flutter_sdk/base/model/drv_base_response.dart';"
    imports+="\nimport 'package:driver_flutter_sdk/base/model/drv_indicator_status.dart';"
    imports+="\nimport 'package:driver_flutter_sdk/base/repository/drv_repo.dart';"
    imports+="\nimport 'package:driver_flutter_sdk/base/viwe_wrapper/drv_base_view_widget.dart';"
  fi

  cat <<EOF
library ${FEATURE_NAME}_comp;

$(echo -e "$imports")

$(echo -e "$parts")
abstract class ${CLASS_NAME}Comp extends Component {
  /// 路由带来的参数
  Map? routeArgs;
  ${CLASS_NAME}Comp({this.routeArgs});

  /// 单实例使用
  factory ${CLASS_NAME}Comp.getInstance({String? tag, Map? routeArgs}) {
    if (Lomo.isRegistered<${CLASS_NAME}Comp>(tag: tag)) {
      return Lomo.find<${CLASS_NAME}Comp>(tag: tag);
    }
    return Lomo.put<${CLASS_NAME}Comp>(
      ${CLASS_NAME}CompImpl(routeArgs: routeArgs),
      tag: tag,
    );
  }

  /// 多实例使用
  factory ${CLASS_NAME}Comp.newInstance({String? tag, Map? routeArgs}) {
    return Lomo.putNewInstance(
      () => ${CLASS_NAME}CompImpl(routeArgs: routeArgs),
      tag: tag,
    );
  }
}
EOF
}

gen_comp_impl() {
  if [[ $STANDALONE -eq 1 ]]; then
    # standalone 模式下 comp_impl 无意义,降级为 unknown stub
    cat <<EOF
import 'package:flutter/material.dart';
import 'package:lomo/lomo.dart';

// TODO: business logic - implement ${FEATURE_NAME}_comp_impl
EOF
    return
  fi

  cat <<EOF
part of ${FEATURE_NAME}_comp;

class ${CLASS_NAME}CompImpl extends ${CLASS_NAME}Comp {
  @override
  ${CLASS_NAME}CompImpl({Map? routeArgs}) : super(routeArgs: routeArgs);

  ${CLASS_NAME}Controller get _controller =>
      Lomo.put(${CLASS_NAME}Controller(routeArgs: routeArgs), tag: tag);

  @override
  Widget createView() {
    return GetBuilder(
      init: _controller,
      tag: tag,
      assignId: true,
      builder: (controller) {
        return ${CLASS_NAME}View(tag);
      },
    );
  }

  @override
  void initState() {
    debugPrint('\$this initState');
  }

  @override
  void dispose() {
    debugPrint('\$this dispose');
    Lomo.delete<${CLASS_NAME}Comp>(tag: tag);
  }
}
EOF
}

gen_controller() {
  local part_of_line=""
  local imports=""
  if [[ $STANDALONE -eq 0 ]]; then
    part_of_line="part of ${FEATURE_NAME}_comp;"
  else
    imports="import 'package:flutter/material.dart';"
    if [[ "$PROFILE" == "business" ]]; then
      imports+="\nimport 'package:driver_flutter_sdk/base/controller/drv_base_controller.dart';"
      imports+="\nimport 'package:driver_flutter_sdk/base/model/drv_base_response.dart';"
    else
      imports+="\nimport 'package:get/get.dart';"
    fi
  fi

  if [[ "$PROFILE" == "business" ]]; then
    cat <<EOF
${part_of_line:+$part_of_line
}$(if [[ -n "$imports" ]]; then echo -e "$imports"; echo; fi)class ${CLASS_NAME}Controller extends DBaseController<${CLASS_NAME}Model> {
  final ${CLASS_NAME}Repo _repo = ${CLASS_NAME}Repo();

  Map? routeArgs;
  ${CLASS_NAME}Controller({this.routeArgs});

  @override
  void onInit() {
    super.onInit();
    _repo.enter();
    // TODO: business logic
  }

  @override
  void onReady() {
    if (isClosed) return;
    super.onReady();
    // TODO: business logic - 第一帧渲染后加载数据
  }

  @override
  void onClose() {
    _repo.exit();
    super.onClose();
  }
}
EOF
  else
    cat <<EOF
${part_of_line:+$part_of_line
}$(if [[ -n "$imports" ]]; then echo -e "$imports"; echo; fi)class ${CLASS_NAME}Controller extends GetxController {
  Map? routeArgs;
  ${CLASS_NAME}Controller({this.routeArgs});

  @override
  void onInit() {
    super.onInit();
  }

  @override
  void onReady() {
    if (isClosed) return;
    super.onReady();
  }

  @override
  void onClose() {
    super.onClose();
  }
}
EOF
  fi
}

gen_repo() {
  local part_of_line=""
  local imports=""
  if [[ $STANDALONE -eq 0 ]]; then
    part_of_line="part of ${FEATURE_NAME}_comp;"
  else
    imports="import 'package:driver_flutter_sdk/base/repository/drv_repo.dart';"
  fi

  cat <<EOF
${part_of_line:+$part_of_line
}$(if [[ -n "$imports" ]]; then echo -e "$imports"; echo; fi)class ${CLASS_NAME}Repo extends DRepo {
  @override
  void enter() {
    super.enter();
    // TODO: business logic - 进入页面初始化
  }

  @override
  void exit() {
    super.exit();
    // TODO: business logic - 取消进行中的请求
  }

  // TODO: business logic - 接口方法
}
EOF
}

gen_model() {
  local part_of_line=""
  if [[ $STANDALONE -eq 0 ]]; then
    part_of_line="part of ${FEATURE_NAME}_comp;"
  fi

  cat <<EOF
${part_of_line:+$part_of_line
}class ${CLASS_NAME}Model {
  // TODO: business logic - 字段定义

  ${CLASS_NAME}Model();

  factory ${CLASS_NAME}Model.fromJson(Map<String, dynamic> json) {
    // TODO: business logic - 字段反序列化
    return ${CLASS_NAME}Model();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        // TODO: business logic - 字段序列化
      };
}
EOF
}

gen_view() {
  local part_of_line=""
  local imports=""
  if [[ $STANDALONE -eq 0 ]]; then
    part_of_line="part of ${FEATURE_NAME}_comp;"
  else
    imports="import 'package:flutter/material.dart';"
    imports+="\nimport 'package:get/get.dart';"
    imports+="\nimport 'package:lomo/lomo.dart';"
    if [[ "$PROFILE" == "business" && "$FEAT_TYPE" != "service" && "$FEAT_TYPE" != "refactor" ]]; then
      imports+="\nimport 'package:driver_flutter_sdk/base/viwe_wrapper/drv_base_view_widget.dart';"
    fi
  fi

  if [[ "$PROFILE" == "business" && "$FEAT_TYPE" != "service" && "$FEAT_TYPE" != "refactor" ]]; then
    cat <<EOF
${part_of_line:+$part_of_line
}$(if [[ -n "$imports" ]]; then echo -e "$imports"; echo; fi)class ${CLASS_NAME}View extends GetView<${CLASS_NAME}Controller> {
  @override
  final String? tag;
  const ${CLASS_NAME}View(this.tag, {Key? key}) : super(key: key);

  @override
  ${CLASS_NAME}Controller get controller => Lomo.find<${CLASS_NAME}Controller>(tag: tag);

  @override
  Widget build(BuildContext context) {
    return DrvBaseViewWrapper(
      isThemeUpdate: true,
      isScreenOrientationUpdate: false,
      builder: (wrapperContext) {
        // TODO: business logic - 页面 Widget Tree
        return const SizedBox.shrink();
      },
    );
  }
}
EOF
  else
    cat <<EOF
${part_of_line:+$part_of_line
}$(if [[ -n "$imports" ]]; then echo -e "$imports"; echo; fi)class ${CLASS_NAME}View extends GetView<${CLASS_NAME}Controller> {
  @override
  final String? tag;
  const ${CLASS_NAME}View(this.tag, {Key? key}) : super(key: key);

  @override
  ${CLASS_NAME}Controller get controller => Lomo.find<${CLASS_NAME}Controller>(tag: tag);

  @override
  Widget build(BuildContext context) {
    // TODO: business logic - 在这里编写 View
    return const SizedBox();
  }
}
EOF
  fi
}

gen_unknown() {
  local filepath="$1"
  local base
  base=$(basename "$filepath" .dart)
  cat <<EOF
// TODO: business logic - implement ${base}
EOF
}

# ── Main: generate scaffold for each new file ────────────────────────────────

SCAFFOLDED=0

for i in "${!NEW_FILES[@]}"; do
  filepath="${NEW_FILES[$i]}"
  [[ -z "$filepath" ]] && continue

  # Skip if file already exists (idempotent)
  if [[ -f "$filepath" ]]; then
    echo "SKIP: $filepath (already exists)"
    continue
  fi

  # Ensure parent directory
  mkdir -p "$(dirname "$filepath")"

  role="${ROLES[$i]}"

  case "$role" in
    comp)      gen_comp "$filepath" > "$filepath" ;;
    comp_impl) gen_comp_impl > "$filepath" ;;
    controller) gen_controller > "$filepath" ;;
    repo)      gen_repo > "$filepath" ;;
    model)     gen_model > "$filepath" ;;
    view)      gen_view > "$filepath" ;;
    unknown)   gen_unknown "$filepath" > "$filepath" ;;
  esac

  echo "SCAFFOLDED: $filepath ($role)"
  SCAFFOLDED=$((SCAFFOLDED + 1))
done

echo ""
echo "✓ Scaffold complete: $SCAFFOLDED files generated for $FEAT_ID"
echo "  feature_name: $FEATURE_NAME"
echo "  class_name:   $CLASS_NAME"
echo "  feat_type:    $FEAT_TYPE"
echo "  profile:      $PROFILE"
