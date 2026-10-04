#!/usr/bin/env bash
# platform.sh — Platform 加载库（library，被其他脚本 source）
# 提供平台配置加载、脚本路径解析、仓库扫描、文件分组等功能。
# 不可直接执行。

PLATFORMS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../platform" && pwd)"

# 加载指定平台的 config.json，输出到 stdout
# 用法：load_platform_config <platform_name>
# Exit: 0=成功, 1=平台不存在或 config 无效
load_platform_config() {
  local plat="${1:?Usage: load_platform_config <platform>}"
  local config_path="${PLATFORMS_DIR}/${plat}/config.json"

  if [[ ! -f "$config_path" ]]; then
    echo "[DAC-GEN-011] platform '${plat}' not found" >&2
    return 1
  fi

  local missing=""
  for field in platform language file_ext src_root; do
    local val
    val=$(jq -r ".${field} // empty" "$config_path" 2>/dev/null)
    if [[ -z "$val" ]]; then
      missing="${missing} ${field}"
    fi
  done

  if [[ -n "$missing" ]]; then
    echo "[DAC-GEN-010] platform config invalid: missing${missing}" >&2
    return 1
  fi

  cat "$config_path"
}

# 解析 platform 脚本路径
# 用法：resolve_platform_script <platform> <script_name>
# 输出：可执行脚本的绝对路径，不存在则输出空字符串
resolve_platform_script() {
  local plat="$1" script_name="$2"
  local path="${PLATFORMS_DIR}/${plat}/scripts/${script_name}"
  if [[ -x "$path" ]]; then
    echo "$path"
  else
    echo ""
  fi
}

# 获取 platform rules 目录路径
# 用法：resolve_platform_rules_dir <platform>
resolve_platform_rules_dir() {
  local plat="$1"
  echo "${PLATFORMS_DIR}/${plat}/rules"
}

# 扫描仓库目录，输出 available_platforms JSON 映射
# 用法：scan_available_platforms [repo_root]
# 输出：{"flutter": "lib/", "android": "android/app/src/main/kotlin/"} 等
# 仅输出在 platform/ 目录下有对应 config.json 的平台
scan_available_platforms() {
  local repo_root="${1:-.}"
  local result="{}"

  # Flutter: pubspec.yaml（monorepo 时取最浅路径作为主 src_root）
  local _flutter_src_root=""
  while IFS= read -r pubspec; do
    [[ -z "$pubspec" ]] && continue
    local dir
    dir=$(dirname "$pubspec")
    local rel_dir="${dir#"$repo_root"}"
    rel_dir="${rel_dir#/}"
    local src_root
    if [[ -z "$rel_dir" || "$rel_dir" == "." ]]; then
      src_root="lib/"
    else
      src_root="${rel_dir}/lib/"
    fi
    # 取路径最浅（segment 最少）的作为主入口
    if [[ -z "$_flutter_src_root" ]] || [[ $(echo "$src_root" | tr '/' '\n' | wc -l) -lt $(echo "$_flutter_src_root" | tr '/' '\n' | wc -l) ]]; then
      _flutter_src_root="$src_root"
    fi
  done < <(find "$repo_root" -maxdepth 3 -name "pubspec.yaml" -not -path "*/.*" 2>/dev/null | sort)
  if [[ -n "$_flutter_src_root" ]]; then
    if [[ -f "${PLATFORMS_DIR}/flutter/config.json" ]]; then
      result=$(echo "$result" | jq --arg sr "$_flutter_src_root" '. + {"flutter": $sr}')
    else
      echo "⚠️ 检测到 platform 'flutter' 但无对应 platform，该平台将不可用" >&2
    fi
  fi

  # Android: build.gradle
  while IFS= read -r gradle; do
    [[ -z "$gradle" ]] && continue
    local dir
    dir=$(dirname "$gradle")
    # Make relative to repo_root
    local rel_dir="${dir#"$repo_root"}"
    rel_dir="${rel_dir#/}"
    local src_root=""
    if [[ -d "${dir}/src/main/kotlin" ]]; then
      src_root="${rel_dir:+${rel_dir}/}src/main/kotlin/"
    elif [[ -d "${dir}/src/main/java" ]]; then
      src_root="${rel_dir:+${rel_dir}/}src/main/java/"
    else
      src_root="${rel_dir:+${rel_dir}/}src/main/"
    fi
    if [[ -f "${PLATFORMS_DIR}/android/config.json" ]]; then
      result=$(echo "$result" | jq --arg sr "$src_root" '. + {"android": $sr}')
    else
      echo "⚠️ 检测到 platform 'android' 但无对应 platform，该平台将不可用" >&2
    fi
    break
  done < <(find "$repo_root" -maxdepth 3 -name "build.gradle" -not -path "*/.*" 2>/dev/null | while IFS= read -r f; do
    # Skip build.gradle under a Flutter project (sibling or parent has pubspec.yaml)
    local d; d=$(dirname "$f")
    while [[ "$d" != "$repo_root" && "$d" != "/" ]]; do
      [[ -f "$d/pubspec.yaml" ]] && continue 2
      d=$(dirname "$d")
    done
    echo "$f"
  done | sort | head -1)

  # iOS: *.xcodeproj
  while IFS= read -r xcodeproj; do
    [[ -z "$xcodeproj" ]] && continue
    local dir
    dir=$(dirname "$xcodeproj")
    local rel_dir="${dir#"$repo_root"}"
    rel_dir="${rel_dir#/}"
    local src_root="${rel_dir:+${rel_dir}/}"
    [[ -z "$src_root" ]] && src_root="ios/"
    if [[ -f "${PLATFORMS_DIR}/ios/config.json" ]]; then
      result=$(echo "$result" | jq --arg sr "$src_root" '. + {"ios": $sr}')
    else
      echo "⚠️ 检测到 platform 'ios' 但无对应 platform，该平台将不可用" >&2
    fi
    break
  done < <(find "$repo_root" -maxdepth 3 -name "*.xcodeproj" -not -path "*/.*" 2>/dev/null | sort | head -1)

  # Vue: package.json + src/*.vue
  while IFS= read -r pkgjson; do
    [[ -z "$pkgjson" ]] && continue
    local dir
    dir=$(dirname "$pkgjson")
    if find "$dir/src" -maxdepth 2 -name "*.vue" 2>/dev/null | grep -q .; then
      local rel_dir="${dir#"$repo_root"}"
      rel_dir="${rel_dir#/}"
      local src_root="${rel_dir:+${rel_dir}/}src/"
      if [[ -f "${PLATFORMS_DIR}/vue/config.json" ]]; then
        result=$(echo "$result" | jq --arg sr "$src_root" '. + {"vue": $sr}')
      else
        echo "⚠️ 检测到 platform 'vue' 但无对应 platform，该平台将不可用" >&2
      fi
      break
    fi
  done < <(find "$repo_root" -maxdepth 3 -name "package.json" -not -path "*/node_modules/*" -not -path "*/.*" 2>/dev/null | sort)

  echo "$result"
}

# 从文件列表按 available_platforms 的 src_root 做前缀匹配分组
# 用法：group_files_by_platform <files_json_array> <available_platforms_json>
# 输入：
#   $1 — JSON 数组 ["file1", "file2", ...]
#   $2 — JSON 对象 {"flutter": "lib/", "android": "app/src/main/kotlin/"}
# 输出：{"flutter": ["file1"], "android": ["file2"], "_unmatched": ["file3"]}
group_files_by_platform() {
  local files_json="$1"
  local platforms_json="$2"

  echo "$files_json" | jq --argjson platforms "$platforms_json" '
    def match_platform($f; $plats):
      reduce ($plats | to_entries[]) as $e (
        {key: "_unmatched", len: 0};
        if ($f | startswith($e.value)) and ($e.value | length) > .len
        then {key: $e.key, len: ($e.value | length)}
        else . end
      ) | .key;

    reduce .[] as $file (
      {};
      match_platform($file; $platforms) as $p |
      .[$p] = ((.[$p] // []) + [$file])
    )
  '
}