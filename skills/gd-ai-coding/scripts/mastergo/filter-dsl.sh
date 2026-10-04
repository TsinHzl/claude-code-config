#!/usr/bin/env bash
#
# MasterGo DSL 噪音过滤脚本（Shell + jq 实现）
#
# 用法:
#   ./filter-dsl.sh --input <dsl文件路径> --output <输出目录>
#
# 依赖: jq (https://stedolan.github.io/jq/)
#
# 输入格式支持:
#   - MCP 工具结果文件: [{type: "text", text: "...json..."}]
#   - 普通 DSL JSON 文件: {"dsl": {...}, ...} 或 {"nodes": [...], ...}
#
# 输出文件:
#   - ui_dsl.json : 精简后的 compact JSON（体积减少约 75%）
#   - ui_tree.txt        : 树形 UI 层级文本，AI 可直接阅读
#
# 过滤内容:
#   - SVG 贝塞尔路径 data（通常占 DSL 体积 50%+）
#   - 空 effect 引用（全部为 {"value": []}）
#   - 蒙版 LAYER 节点（整体删除）
#   - componentId / flexShrink / strokeAlign 等次要字段
#   - 顶层 rules / componentDocumentLinks 字段
# 内联处理:
#   - paint_* 颜色引用 → 实际颜色值（#FFFFFF）
#   - font_* 字体引用 → {size, family, weight, lineHeight}
#   - layoutStyle.relativeX/Y/width/height → layout.x/y/w/h
#   - flexContainerInfo.flexDirection → flex

set -euo pipefail

usage() {
  cat <<'EOF'
用法: filter-dsl.sh --input <dsl文件路径> --output <输出目录>

过滤 MasterGo DSL 噪音数据，生成 ui_dsl.json 与 ui_tree.txt。
依赖: jq
EOF
}

INPUT=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$INPUT" || -z "$OUTPUT" ]]; then
  echo "❌ 必须指定 --input 与 --output" >&2
  usage >&2
  exit 1
fi

if [[ ! -r "$INPUT" ]]; then
  echo "❌ 输入文件不可读: $INPUT" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ 未找到 jq，请先安装: https://stedolan.github.io/jq/" >&2
  exit 1
fi

# ── 前置校验 ──────────────────────────────────────────────────────────────────

# 读取输入到变量（支持进程替换 /dev/fd/xx）
INPUT_DATA=$(cat "$INPUT")

if [[ -z "$INPUT_DATA" ]]; then
  echo "❌ 输入为空: $INPUT" >&2
  exit 1
fi

if ! echo "$INPUT_DATA" | jq empty 2>/dev/null; then
  echo "❌ 输入不是有效 JSON: $INPUT" >&2
  echo "   前 200 字符: $(echo "$INPUT_DATA" | head -c 200)" >&2
  exit 1
fi

# ── 主流程 ────────────────────────────────────────────────────────────────────

ORIG_SIZE=$(echo -n "$INPUT_DATA" | wc -c | tr -d ' ')

RESULT=""
if ! RESULT="$(echo "$INPUT_DATA" | jq -n --rawfile raw /dev/stdin --argjson orig "$ORIG_SIZE" '
  def round1: (.*10 | round) / 10;

  def resolve_paint($map; $ref):
    if $ref == null or $ref == "" then null else ($map[$ref] // null) end;

  def resolve_font($map; $ref):
    if $ref == null or $ref == "" then null else ($map[$ref] // null) end;

  def build_style_maps:
    . as $styles
    | reduce ($styles | keys[]) as $k (
        { paint: {}, font: {} };
        . as $acc | $styles[$k] as $v
        | if ($k | startswith("paint_")) then
            ($v.value // []) as $vals
            | $acc | .paint[$k] = (if ($vals | type) == "array" then
                if ($vals | length) == 1 then $vals[0]
                elif ($vals | length) == 0 then null else $vals end
              else $vals end)
          elif ($k | startswith("font_")) then
            ($v.value // {}) as $fv
            | if ($fv | keys | length) > 0 then
                (($fv.style // "") | tostring) as $style_str
                | $acc | .font[$k] = {
                    size: ($fv.size // 0),
                    family: ($fv.family // ""),
                    weight: (if ($style_str | test("bold|Bold|粗体|加粗|中粗|semibold|SemiBold")) then "bold" else "normal" end),
                    lineHeight: ($fv.lineHeight // "")
                  }
              else $acc end
          else $acc end
      );

  def filter_node($paint; $font):
    if .mask then empty
    else
      . as $node | ($node.type // "") as $ntype | ($node.layoutStyle // {}) as $layout
      | {
          type: $ntype, name: ($node.name // ""),
          layout: {
            x: (($layout.relativeX // 0) | round1), y: (($layout.relativeY // 0) | round1),
            w: (($layout.width // 0) | round1), h: (($layout.height // 0) | round1)
          }
        }
      | if ($node.flexContainerInfo // {} | keys | length) > 0
        then . + { flex: ($node.flexContainerInfo.flexDirection // "row") } else . end
      | if $node.fill then (resolve_paint($paint; $node.fill)) as $c
        | if $c != null then . + { fill: $c } else . end else . end
      | if $node.borderRadius then . + { borderRadius: $node.borderRadius } else . end
      | if $node.strokeColor then (resolve_paint($paint; $node.strokeColor)) as $c
        | if $c != null then . + { stroke: { color: $c, width: ($node.strokeWidth // 1) } } else . end
        else . end
      | if $ntype == "TEXT" then
          ($node.text // []) as $texts
          | (reduce $texts[] as $t (""; . + ($t.text // ""))) as $content
          | (if $content != "" then . + { content: $content } else . end)
          | if ($texts | length) > 0 then (resolve_font($font; $texts[0].font)) as $fi
            | if $fi != null then . + { font: $fi } else . end else . end
          | if ($node.textColor // []) | length > 0 then (resolve_paint($paint; $node.textColor[0].color)) as $tc
            | if $tc != null then . + { textColor: $tc } else . end else . end
          | if ($node.textAlign // "left") != "left" then . + { textAlign: $node.textAlign } else . end
          | if $node.textMode then . + { textMode: $node.textMode } else . end
        else . end
      | if $ntype == "PATH" then
          . + { _note: "图形/图标" }
          | [ ($node.path // [])[] | (resolve_paint($paint; .fill)) as $pf
              | if $pf != null then { fill: $pf } else empty end ] as $simplified
          | if ($simplified | length) > 0 then . + { pathFills: $simplified } else . end
        else . end
      | if $node.componentInfo then . + { componentInfo: $node.componentInfo } else . end
      | ($node.children // [] | map(filter_node($paint; $font))) as $kids
      | if ($kids | length) > 0 then . + { children: $kids } else . end
    end;

  def count_nodes:
    if type != "array" then 0
    else reduce .[] as $n (0; . + 1 + (($n.children // []) | count_nodes)) end;

  def count_by_type:
    if type != "array" then {}
    else reduce .[] as $n (
      {};
      ($n.type // "UNKNOWN") as $t
      | .[$t] = ((.[$t] // 0) + 1)
      | (($n.children // []) | count_by_type) as $child
      | reduce ($child | to_entries[]) as $e (.; .[$e.key] = ((.[$e.key] // 0) + $e.value))
    ) end;

  def truncate30: if length > 30 then .[0:30] + "…" else . end;

  def node_attrs($node):
    [] | if $node.flex then . + ["flex:\($node.flex)"] else . end
    | if $node.fill then . + ["fill:\($node.fill)"] else . end
    | if $node.borderRadius then . + ["r:\($node.borderRadius)"] else . end
    | if $node.stroke then . + ["border:\($node.stroke.color)/\($node.stroke.width)"] else . end
    | if $node.content then . + ["\"\($node.content | truncate30)\""] else . end
    | if $node.textColor then . + ["color:\($node.textColor)"] else . end
    | if $node.font then . + ["font:\($node.font.size)sp\(if $node.font.weight == "bold" then "/bold" else "" end)"] else . end
    | if $node._note then . + [$node._note] else . end;

  def node_line($prefix; $is_last; $node):
    (if $is_last then "└── " else "├── " end) as $conn
    | ($node.layout // {}) as $layout
    | (node_attrs($node)) as $attrs
    | "\($prefix)\($conn)[\($node.type // "")] \($node.name // "") (\($layout.w // 0)×\($layout.h // 0) @\($layout.x // 0),\($layout.y // 0))\(if ($attrs|length)>0 then " [\($attrs|join(", "))]" else "" end)";

  def build_tree_lines($prefix; $nodes):
    if ($nodes | length) == 0 then []
    else reduce range(0; $nodes | length) as $i ([]; ($nodes[$i]) as $node | ($i == ($nodes|length - 1)) as $is_last
      | . + [node_line($prefix; $is_last; $node)]
      | if ($node.children // []) | length > 0
        then . + build_tree_lines($prefix + (if $is_last then "    " else "│   " end); $node.children)
        else . end) end;

  ($raw | try fromjson catch $raw) as $parsed
  | (if ($parsed | type) == "string" then ($parsed | fromjson) else $parsed end) as $obj
  | (if ($obj | type) == "array" and ($obj | length) > 0 and ($obj[0].text? != null)
      then ($obj[0].text | if type == "string" then fromjson else . end)
      elif ($obj.content? // null) != null and ($obj.content | type) == "array" and ($obj.content | length) > 0 and ($obj.content[0].text? != null)
      then ($obj.content[0].text | if type == "string" then fromjson else . end)
      else $obj end) as $dsl_obj
  | (($dsl_obj.dsl // $dsl_obj).styles // {}) as $styles
  | ($styles | build_style_maps) as $maps
  | ($maps.paint) as $paint_map
  | ($maps.font) as $font_map
  | (($dsl_obj.dsl // $dsl_obj).nodes // [] | map(filter_node($paint_map; $font_map))) as $nodes
  | ({ nodes: $nodes }) as $filtered
  | ($filtered | tojson) as $result_json
  | {
      orig_size: $orig,
      filtered_size: ($result_json | length),
      reduction: (if $orig > 0 then (100 * ($orig - ($result_json|length)) / $orig | floor) else 0 end),
      node_count: ($nodes | count_nodes),
      type_counts: ($nodes | count_by_type | to_entries | sort_by(-.value) | from_entries),
      result_json: $result_json,
      tree_text: (build_tree_lines(""; $nodes) | join("\n"))
    }
' 2>&1)"; then
  echo "❌ jq 过滤处理失败" >&2
  echo "   错误信息: $(echo "$RESULT" | head -c 200)" >&2
  exit 1
fi

if ! echo "$RESULT" | jq empty 2>/dev/null; then
  echo "❌ 过滤结果不是有效 JSON" >&2
  exit 1
fi

FILTERED_JSON="$(echo "$RESULT" | jq -r '.result_json')"
if [[ -z "$FILTERED_JSON" || "$FILTERED_JSON" == "null" ]]; then
  echo "❌ 过滤后 JSON 为空" >&2
  exit 1
fi

TREE_TEXT="$(echo "$RESULT" | jq -r '.tree_text')"
ORIG_SIZE_OUT="$(echo "$RESULT" | jq -r '.orig_size')"
FILTERED_SIZE="$(echo "$RESULT" | jq -r '.filtered_size')"
REDUCTION="$(echo "$RESULT" | jq -r '.reduction')"
NODE_COUNT="$(echo "$RESULT" | jq -r '.node_count')"
TYPE_COUNTS="$(echo "$RESULT" | jq -c '.type_counts')"

mkdir -p "$OUTPUT"
JSON_PATH="${OUTPUT%/}/ui_dsl.json"
TREE_PATH="${OUTPUT%/}/ui_tree.txt"

printf '%s' "$FILTERED_JSON" >"$JSON_PATH"
printf '%s' "$TREE_TEXT" >"$TREE_PATH"

echo "✅ DSL 过滤完成"
echo "   原始大小  : ${ORIG_SIZE_OUT} 字符"
echo "   过滤后大小: ${FILTERED_SIZE} 字符（减少 ${REDUCTION}%）"
echo "   节点总数  : ${NODE_COUNT}"
echo "   节点类型  : ${TYPE_COUNTS}"
echo "   JSON 输出 : ${JSON_PATH}"
echo "   Tree 输出 : ${TREE_PATH}"
