#!/usr/bin/env bash
# disk-cleanup: macOS 垃圾扫描脚本（只读，无副作用）
# 输出供 Agent 读取后生成分级报告

_s() {
  [ -d "$1" ] || { echo "-"; return; }
  local r
  r=$(du -sh "$1" 2>/dev/null | cut -f1)
  echo "${r:--}"
}

echo "=== DISK_OVERVIEW ==="
df -h /

echo ""
echo "=== RED_SAFE ==="
echo "CocoaPods缓存|$(_s ~/Library/Caches/CocoaPods)"
echo "npm缓存|$(_s ~/.npm)"
echo "pip缓存|$(_s ~/Library/Caches/pip)"
echo "Homebrew缓存|$(_s ~/Library/Caches/Homebrew)"
echo "Go-build缓存|$(_s ~/Library/Caches/go-build)"
echo "Chrome缓存|$(_s ~/Library/Caches/Google/Chrome)"
echo "Flutter-pub-cache|$(_s ~/.pub-cache)"
echo "Xcode-ModuleCache|$(_s ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex)"
echo "Gradle-Cache|$(_s ~/.gradle/caches)"
echo "Cargo-Registry|$(_s ~/.cargo/registry)"
echo "Cargo-Git|$(_s ~/.cargo/git)"
echo "Maven-LocalRepo|$(_s ~/.m2/repository)"
echo "node-gyp-Cache|$(_s ~/Library/Caches/node-gyp)"
echo "Swift-PM-Cache|$(_s ~/Library/Caches/org.swift.swiftpm)"
echo "JetBrains-Cache|$(_s ~/Library/Caches/JetBrains)"
echo "Bun-Cache|$(_s ~/Library/Caches/bun)"
for d in ms-playwright ms-playwright-mcp ms-playwright-go ms-playwright-mcp-server; do
  p="$HOME/Library/Caches/$d"
  [ -d "$p" ] && echo "Playwright-${d}|$(du -sh "$p" 2>/dev/null | cut -f1)"
done

echo ""
echo "=== YELLOW_CONFIRM ==="
echo "Xcode-DerivedData|$(_s ~/Library/Developer/Xcode/DerivedData)"
echo "Android-AVD|$(_s ~/.android/avd)"
echo "Xcode-iOS-DeviceSupport|$(_s ~/Library/Developer/Xcode/iOS\ DeviceSupport)"
echo "Xcode-Archives|$(_s ~/Library/Developer/Xcode/Archives)"
SHUTDOWN=$(xcrun simctl list devices 2>/dev/null | grep -c "Shutdown")
echo "Shutdown模拟器数|${SHUTDOWN}"
echo "--- iOS DeviceSupport各版本大小 ---"
du -sh ~/Library/Developer/Xcode/"iOS DeviceSupport"/* 2>/dev/null | sort -rh
echo "--- Android AVD列表 ---"
ls ~/.android/avd/ 2>/dev/null | grep '\.avd$' | sed 's/\.avd$//'

echo ""
echo "=== BLUE_USER_DATA ==="
echo "Chrome用户配置|$(_s ~/Library/Application\ Support/Google/Chrome)"
echo "Downloads|$(_s ~/Downloads)"
echo "iOS设备备份|$(_s ~/Library/Application\ Support/MobileSync/Backup)"
TM_SNAPS=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "\.local$" || echo "0")
echo "TimeMachine本地快照数|${TM_SNAPS}"
echo "--- Application Support Top10 ---"
du -sh ~/Library/Application\ Support/* 2>/dev/null | sort -rh | head -10
