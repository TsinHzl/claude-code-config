# Flutter Widget 替代规范（强制）

本规则定义了项目中**禁止直接使用的 Flutter 原生 Widget**及其对应的内部封装替代品。
codegen 阶段违反本规则视为 Layer 2 硬性失败，必须修复。

---

## 零、组件库选型优先级（重要）

项目存在多套 UI 组件库，**司机端业务代码**遵循以下优先级：

```
drv_uikit (GD*)  ←  司机端首选（含暗黑、字体缩放、横竖屏适配）
   │
   ├─ 缺失对应组件时 fallback →  go_uikit (GO*)
   │
   └─ 仍缺失时 fallback →  uikit (DiDi*/DIDI*)
```

**判断规则**：
1. 优先在 `drv_uikit` 中查找 `GD<ComponentName>`，若存在则使用
2. `drv_uikit` 缺失时，使用 `go_uikit` 的 `GO<ComponentName>`
3. 仅当前两者都缺失时，使用 `uikit` 的 `DiDi*` / `DIDI*`
4. 路由用 `Nacho`（混合栈）+ `DrvNavigator`（责任链）；DI 用 `Lomo`

> 注意：drv_uikit 文件名为 `drv_*.dart`，但**类名前缀是 `GD`**（如 `drv_appbar.dart` 中定义 `class GDAppBar`）。

---

## 一、图片组件

| 禁止使用 | 必须替代为 | 来源包 | 说明 |
|----------|-----------|--------|------|
| `Image.network(...)` | `SafeImage.network(...)` | `package:uikit/uikit.dart` | 内置缓存 + 全局错误兜底（返回空 Container） |
| `NetworkImage(...)` | `ExtendedNetworkImageProvider(...)` | `package:didi_image/extended_image.dart` | 带缓存的 ImageProvider |
| `CachedNetworkImage(...)` | `SafeImage.network(...)` | `package:uikit/uikit.dart` | 项目统一用 didi_image 缓存方案 |
| `FadeInImage.network(...)` | `UIKit.fadeInNetworkImage(url)` | `package:uikit/uikit.dart` | 带品牌占位图的渐入加载 |

**正确用法示例：**
```dart
import 'package:uikit/uikit.dart';

// 网络图片
SafeImage.network(imageUrl, width: 100, height: 100, fit: BoxFit.cover)

// 需要 ImageProvider 时
ExtendedNetworkImageProvider(imageUrl, cache: true)
```

---

## 二、导航栏

| 禁止使用 | 必须替代为 | 来源包 | 说明 |
|----------|-----------|--------|------|
| `AppBar(...)` | `GDAppBar(...)` | `package:drv_uikit/drv_uikit.dart` | 统一样式、暗黑模式支持、返回按钮行为 |
| `SliverAppBar(...)` | `GDAppBar(...)` | `package:drv_uikit/drv_uikit.dart` | 按设计稿使用对应配置 |

**正确用法示例：**
```dart
import 'package:drv_uikit/drv_uikit.dart';

GDAppBar(
  title: '页面标题',
  onBackPressed: () => Nacho.maybePop(),
)
```

---

## 三、按钮

| 禁止使用 | 必须替代为 | 来源包 | 说明 |
|----------|-----------|--------|------|
| `ElevatedButton(...)` | `GOButton(...)` | `package:go_uikit/global_one_uikit.dart` | 支持 main/secondary/text 三种类型 |
| `TextButton(...)` | `GOButton(type: GOButtonType.text)` | 同上 | — |
| `OutlinedButton(...)` | `GOButton(type: GOButtonType.secondary)` | 同上 | — |
| `MaterialButton(...)` | `GOButton(...)` | 同上 | — |

**正确用法示例：**
```dart
import 'package:go_uikit/global_one_uikit.dart';

GOButton(
  config: GOButtonConfig(
    type: GOButtonType.main,
    size: GOButtonSize.large,
    text: '确认',
  ),
  onPressed: () {},
)
```

---

## 四、对话框

| 禁止使用 | 必须替代为 | 来源包 | 说明 |
|----------|-----------|--------|------|
| `showDialog(...)` | `showGODialog(context, GODialog(...))` | `package:go_uikit/components/dialog/show_go_dialog.dart` | 司机端业务**优先用 `GDDialog`/`showDrvDialog`（drv_uikit）**，跨业务通用场景再用 `GODialog` |
| `AlertDialog(...)` | `GODialog(...)` 或 `DrvDialog(...)` | `package:go_uikit/...` 或 `package:drv_uikit/drv_uikit.dart` | — |
| `SimpleDialog(...)` | 同上 | — | — |

**正确用法示例：**
```dart
import 'package:go_uikit/components/dialog/go_dialog.dart';
import 'package:go_uikit/components/dialog/show_go_dialog.dart';
import 'package:go_uikit/components/dialog/go_dialog_config.dart';

showGODialog(
  context,
  GODialog(
    title: '提示',
    description: '确认操作？',
    actions: [
      GODialogAction(text: '取消', onTap: () => Navigator.pop(context)),
      GODialogAction(text: '确认', onTap: handleConfirm),
    ],
    dialogConfig: GODialogConfig(
      titleMaxLines: 3,
      descriptionMaxLines: 4,
    ),
  ),
);
```

> `GODialog` 顶层构造参数：`title` / `description` / `banner` / `actions` / `customActions` / `flexibleSpace` / `customContent` / `dialogConfig`。
> `GODialogConfig` 仅承载样式（`titleStyle` / `descriptionStyle` / `bannerHeight` / `darkStyle` 等），**不包含 `title` / `description` / `actions` 字段**。

---

## 五、Toast / 轻提示

| 禁止使用 | 必须替代为 | 来源包 | 说明 |
|----------|-----------|--------|------|
| `ScaffoldMessenger.showSnackBar(...)` | `GDToast.show(...)` | `package:drv_uikit/drv_uikit.dart` | — |
| `SnackBar(...)` | `GDToast.show(...)` | 同上 | — |
| 第三方 toast 包 | `GDToast.showSuccessIcon(...)` / `GDToast.showFailureIcon(...)` | 同上 | 统一 Toast 样式 |

**正确用法示例（注意：方法均为静态，参数为位置参数 `String text`，不接受 `BuildContext`）：**
```dart
import 'package:drv_uikit/drv_uikit.dart';

GDToast.showSuccessIcon('操作成功');
GDToast.showFailureIcon('操作失败');
GDToast.show(text: '普通提示');  // 通用 toast
```

---

## 六、底部弹窗 / Popup

| 禁止使用 | 必须替代为 | 来源包 | 说明 |
|----------|-----------|--------|------|
| `showModalBottomSheet(...)` | `GOBottomPopup` / `GONormalBottomPopup` | `package:go_uikit/global_one_uikit.dart` | 统一动画、安全区、键盘避让 |
| `showCupertinoModalPopup(...)` | `showDiDiPopup(...)` | `package:uikit/uikit.dart` | 带模糊背景 |
| `DraggableScrollableSheet(...)` | `GOSlidingUpPanel(...)` | `package:go_uikit/global_one_uikit.dart` | 三态滑动面板 |

---

## 七、开关 / 选择器

| 禁止使用 | 必须替代为 | 来源包 | 说明 |
|----------|-----------|--------|------|
| `Switch(...)` | `GOSwitch(...)` | `package:go_uikit/global_one_uikit.dart` | 自绘、暗黑模式、RTL |
| `Checkbox(...)` | `GDCheckBox(...)` | `package:drv_uikit/drv_uikit.dart` | — |
| `Radio(...)` | `GOSelect(type: GOSelectType.single)` | `package:go_uikit/global_one_uikit.dart` | — |

---

## 八、文本

| 禁止使用 | 必须替代为 | 来源包 | 说明 |
|----------|-----------|--------|------|
| `Text(...)` | `GOText(...)` | `package:go_uikit/global_one_uikit.dart` | 大字体适配 + StrutStyle 统一 + FontFamily 注入 |
| `TextSpan(...)` | `GOTextSpan(...)` | 同上 | — |
| `TextField(...)` | `DiDiTextField(...)` | `package:uikit/uikit.dart` | 带动画进度条、粘贴检测 |

> **例外**：在组件库内部或不需要大字体适配的场景下，可使用原生 `Text`，但必须在注释中说明理由。

---

## 九、Loading / 空态

| 禁止使用 | 必须替代为 | 来源包 | 说明 |
|----------|-----------|--------|------|
| `CircularProgressIndicator(...)` | `GDCircleIndicator(...)` | `package:drv_uikit/drv_uikit.dart` | 品牌动画 |
| `LinearProgressIndicator(...)` | `PageLoadingAnimation(...)` | `package:uikit/uikit.dart` | 页面顶部渐变进度条 |
| 自定义空态 Widget | `GDEmptyPage(...)` | `package:drv_uikit/drv_uikit.dart` | 统一空态 UI |

---

## 十、路由导航

| 禁止使用 | 必须替代为 | 来源包 | 说明 |
|----------|-----------|--------|------|
| `Navigator.push(...)` | `DrvNavigator.jump(NavReq(...))` | `package:driver_flutter_sdk` | 责任链路由，支持 H5/Native/Flutter/DVM |
| `Navigator.pop(...)` | `Nacho.maybePop()` | `package:nacho/nacho.dart` | 静态方法，混合栈安全 pop |
| `Navigator.pushNamed(...)` | `DrvNavigator.jump(NavReq(...))` | `package:driver_flutter_sdk` | — |
| `MaterialPageRoute(...)` | `CustomPageRoute(...)` | `package:uikit/uikit.dart` | 预置 6 种转场动画 |

> **静态 vs 实例区分（极易出错）**：
> - `Nacho.maybePop()` / `Nacho.open(url, params)` / `Nacho.ready(...)` → **静态方法**
> - `Nacho.instance.popSystemNavigator(animated: true)` → **实例方法**，必须通过 `Nacho.instance` 调用，**不可写成 `Nacho.popSystemNavigator()`**

---

## 十一、颜色 / 字体 / 主题

| 禁止使用 | 必须替代为 | 来源包 | 说明 |
|----------|-----------|--------|------|
| 硬编码 `Color(0xFF...)` | `GDColors.xxx` | `package:drv_uikit/drv_uikit.dart` | 品牌色板 + 暗黑自动切换 |
| 硬编码 `TextStyle(...)` | `GDTextStyles.xxx` | `package:drv_uikit/drv_uikit.dart` | 预置字体层级体系 |
| `Theme.of(context)` 获取暗黑判断 | `ThemeManager.instance.isDarkTheme(context)` | `package:drv_uikit/drv_uikit.dart` | 统一暗黑模式 API |
| 暗黑模式条件颜色 | `ThemeManager.instance.getResNightMode(context, darkRes:, lightRes:)` | 同上 | — |

---

## 十二、Platform View

| 禁止使用 | 必须替代为 | 来源包 | 说明 |
|----------|-----------|--------|------|
| `UiKitView(...)` / `AndroidView(...)` | `SafePlatformView(...)` | `package:uikit/uikit.dart` | 处理前后台线程合并问题 |

---

## 十三、通知条 / 徽标

| 禁止使用 | 必须替代为 | 来源包 | 说明 |
|----------|-----------|--------|------|
| `MaterialBanner(...)` | `GONotice(...)` | `package:go_uikit/global_one_uikit.dart` | inform/alert 两种风格 |
| 自定义 Badge Widget | `GOBadge(...)` | `package:go_uikit/global_one_uikit.dart` | 红点/数字/图标 |

---

## 十四、图标

| 禁止使用 | 必须替代为 | 来源包 | 说明 |
|----------|-----------|--------|------|
| `Icon(Icons.xxx)` | `GDIcon(GDIconData.xxx)` | `package:drv_uikit/drv_uikit.dart` | 项目自有图标字体 |
| SVG 手动加载 | `GDSvgHelper.asset(...)` | `package:drv_uikit/drv_uikit.dart` | SVG 工具类 |
| Lottie 手动加载 | `GDLottieHelper.asset(...)` | `package:drv_uikit/drv_uikit.dart` | Lottie 工具类 |

---

## 十五、引导气泡 / Tooltip

| 禁止使用 | 必须替代为 | 来源包 | 说明 |
|----------|-----------|--------|------|
| `Tooltip(...)` | `GOGuide(...)` | `package:go_uikit/global_one_uikit.dart` | 多步骤引导控制器 |
| 自定义 Overlay 气泡 | `GOGuide(...)` | 同上 | 8 方向自动定位 |

---

## 合规检查快速参照

```
❌ Image.network       → ✅ SafeImage.network
❌ AppBar              → ✅ GDAppBar
❌ ElevatedButton      → ✅ GOButton
❌ showDialog          → ✅ showGODialog
❌ SnackBar            → ✅ GDToast
❌ showModalBottomSheet → ✅ GOBottomPopup / GONormalBottomPopup
❌ Switch              → ✅ GOSwitch
❌ Text                → ✅ GOText
❌ Navigator.push      → ✅ DrvNavigator.jump(NavReq(...))
❌ Navigator.pop       → ✅ Nacho.maybePop()
❌ Color(0xFF...)      → ✅ GDColors.xxx
❌ CircularProgress    → ✅ GDCircleIndicator
```
