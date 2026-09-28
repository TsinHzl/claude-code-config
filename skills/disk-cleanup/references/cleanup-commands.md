# 清理命令参考

Step 4 执行时读取，按 AskUserQuestion 所选分类执行对应区块。

## 选项 A — 🔴 全部安全清理

```bash
# 1. CocoaPods 缓存（优先用 pod 命令，fallback 直接删目录）
pod cache clean --all 2>/dev/null || rm -rf ~/Library/Caches/CocoaPods

# 2. npm 缓存
npm cache clean --force

# 3. pip 缓存
pip cache purge 2>/dev/null || rm -rf ~/Library/Caches/pip

# 4. Homebrew 旧版本与下载缓存
brew cleanup -s

# 5. Playwright 浏览器缓存（逐目录，避免通配符误删）
for d in ms-playwright ms-playwright-mcp ms-playwright-go ms-playwright-mcp-server; do
  p="$HOME/Library/Caches/$d"
  [ -d "$p" ] && rm -rf "$p" && echo "已删除: $p"
done

# 6. Chrome 缓存（仅 Caches 下的，不含 Application Support Profile）
rm -rf ~/Library/Caches/Google/Chrome

# 7. Go build 缓存
go clean -cache 2>/dev/null

# 8. Flutter pub-cache 旧版本
dart pub cache clean 2>/dev/null

# 9. Xcode ModuleCache（DerivedData 子项，重建仅需几分钟）
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex

# 10. Gradle 构建缓存（重新构建时自动重建）
rm -rf ~/.gradle/caches

# 11. Cargo registry / git 缓存
cargo cache --autoclean 2>/dev/null || rm -rf ~/.cargo/registry ~/.cargo/git

# 12. Maven 本地仓库（重新构建时自动重新下载）
rm -rf ~/.m2/repository

# 13. node-gyp 编译缓存
rm -rf ~/Library/Caches/node-gyp

# 14. Swift Package Manager 缓存
swift package purge-cache 2>/dev/null || rm -rf ~/Library/Caches/org.swift.swiftpm

# 15. JetBrains IDE 缓存
rm -rf ~/Library/Caches/JetBrains

# 16. Bun 缓存
bun pm cache rm 2>/dev/null || rm -rf ~/Library/Caches/bun
```

## 选项 B — 🟡 Xcode DerivedData

**影响**：清理后首次编译耗时增加 10–30 分钟（视项目大小），后续编译恢复正常。

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
```

验证：
```bash
[ ! -d ~/Library/Developer/Xcode/DerivedData ] \
  && echo "✅ DerivedData 已清理" || echo "❌ 目录仍存在"
```

## 选项 C — 🟡 iOS 模拟器

**影响**：删除后可通过 Xcode ▸ Window ▸ Devices and Simulators 重新添加。

```bash
# 预演：展示将被删除的设备
xcrun simctl list devices | grep -E "(Shutdown|Unavailable)"

# 执行删除
xcrun simctl delete unavailable
```

## 选项 D — 🟡 Android 模拟器 (AVD)

**影响**：删除后可通过 Android Studio ▸ AVD Manager 重新创建。

```bash
# 预演：展示将被删除的 AVD
ls ~/.android/avd/ 2>/dev/null | grep '\.avd$' | sed 's/\.avd$//'

# 执行删除全部 AVD
rm -rf ~/.android/avd
```

验证：
```bash
[ ! -d ~/.android/avd ] && echo "✅ Android AVD 已清理" || echo "❌ 目录仍存在"
```

## 选项 E — 🟡 Xcode DeviceSupport & Archives

**DeviceSupport 影响**：删除后连接真机调试时 Xcode 自动重新下载对应版本符号（需联网）。  
**Archives 影响**：历史打包产物，删除后需重新打包才能恢复。

```bash
# 展示各 iOS 版本大小（建议仅删除不再使用的旧版本）
du -sh ~/Library/Developer/Xcode/"iOS DeviceSupport"/* 2>/dev/null | sort -rh

# 删除全部 DeviceSupport（保留当前真机 iOS 版本更安全，可改为按版本精确删除）
# rm -rf ~/Library/Developer/Xcode/"iOS DeviceSupport"/<版本号>
rm -rf ~/Library/Developer/Xcode/"iOS DeviceSupport"

# 删除全部 Archives
rm -rf ~/Library/Developer/Xcode/Archives
```

验证：
```bash
echo "DeviceSupport: $( [ -d ~/Library/Developer/Xcode/'iOS DeviceSupport' ] && echo '❌ 仍存在' || echo '✅ 已清理' )"
echo "Archives:      $( [ -d ~/Library/Developer/Xcode/Archives ] && echo '❌ 仍存在' || echo '✅ 已清理' )"
```

## Gotchas

- `pod cache clean --all` 需要 CocoaPods 已安装；若报 `command not found` 则直接 `rm -rf` 目录
- `brew cleanup -s` 删除所有旧版 formula，不可撤销；如有多版本管理需求先确认
- `dart pub cache clean` 在旧版 Flutter SDK 中命令为 `flutter pub cache repair`
- **Chrome 路径易混淆**：`~/Library/Caches/Google/Chrome`（缓存，安全清理）≠ `~/Library/Application Support/Google/Chrome`（用户 Profile，含书签/密码/扩展/历史记录）
- 删除 DerivedData 后，所有 Xcode 工程都需重新索引，在 Xcode 打开时自动触发
- `gradle --stop` 应在删除 `~/.gradle/caches` 前执行，防止 Gradle daemon 持有文件锁
- `cargo cache` 命令需先 `cargo install cargo-cache`；否则直接 `rm -rf ~/.cargo/registry ~/.cargo/git`
- DeviceSupport 建议按版本精确删除，不要用通配符一次性清空；保留当前真机所对应的 iOS 版本
