# Flutter / Dart 代码风格规范（强制）

本规则定义了目标 Flutter 项目的命名、文件组织、import 和编码风格约束。

---

## 一、命名规范

### 类名前缀体系

项目使用**多层 UI 组件库**，每层有独立前缀：

| 前缀 | 来源包 | 层级 | 示例 |
|------|--------|------|------|
| `GD` | `drv_uikit` | 司机端专用组件（**注意**：文件名为 `drv_*.dart`，类名却是 `GD*`） | `GDAppBar`, `GDToast`, `GDColors`, `GDTextStyles`, `GDIcon` |
| `GO` | `go_uikit` | 全球化通用组件 | `GOButton`, `GODialog`, `GOText`, `GOSwitch`, `GOToast` |
| `DiDi` / `DIDI` | `uikit` | 基础组件（较早期） | `DiDiDialog`, `DiDiTextField`, `DIDIButton` |
| `D` + PascalCase | `driver_flutter_sdk` | SDK 基础类 | `DBaseController`, `DRepo`, `DNetwork`, `DEventBus` |
| `Drv` | `driver_flutter_sdk` | SDK 工具/包裹器 | `DrvBaseViewWrapper`, `DrvNavigator` |
| `Nacho` | `nacho` | 路由框架 | `Nacho.maybePop()`, `Nacho.open()` |
| `Lomo` | `lomo` | DI 容器 | `Lomo.put<T>()`, `Lomo.find<T>()` |

### 业务代码命名

| 元素 | 规范 | 示例 |
|------|------|------|
| 文件名 | `snake_case` | `male_pax_filters_view.dart` |
| 类名 | `PascalCase` | `MalePaxFiltersController` |
| 组件入口文件 | `{feature_name}_comp.dart` | `share_setting_comp.dart` |
| Controller | `{FeatureName}Controller` | `PaymentSettingController` |
| Repository | `{FeatureName}Repo` | `SummaryHighlightReportRepo` |
| Model | `{FeatureName}Model` | `MalePaxFiltersModel` |
| View | `{FeatureName}View` | `MalePaxFiltersView` |
| 事件类 | `{Domain}{Action}Event extends DEBEvent` | `ServingEntregaHandlePickImageEvent` |
| 常量类 | `{Domain}Constants` | `Constants` |

### 禁止

- ❌ 文件名使用 camelCase（如 `myWidget.dart`）
- ❌ 类名缺少语义前缀（如裸 `Button` 而非 `GOButton`）
- ❌ UniAPI 生成文件的类名手动添加前缀

---

## 二、文件组织

### 目录结构（feature-first）

```
lib/
├── src/
│   └── {feature_name}/
│       ├── {feature_name}_comp.dart          # 组件入口（library 声明）
│       ├── controller/
│       │   └── {feature_name}_controller.dart
│       ├── impl/
│       │   └── {feature_name}_comp_impl.dart
│       ├── view/
│       │   └── {feature_name}_view.dart
│       ├── repo/
│       │   └── {feature_name}_repo.dart
│       ├── model/
│       │   └── {feature_name}_model.dart
│       └── widget/                           # 功能内部子 Widget（可选）
│           └── {sub_widget}.dart
├── gen/
│   └── assets.gen.dart                       # 资源代码生成
└── {module_name}.dart                        # 模块入口 export
```

### part 指令约束

- 组件内部 Controller/Impl/View 使用 `part` / `part of` 与入口文件关联
- Repo 和 Model 可独立文件（不 part），便于跨组件复用
- `library` 声明必须在组件入口文件顶部

---

## 三、Import 规范

### 排序（上→下）

```dart
// 1. Dart SDK
import 'dart:io';
import 'dart:async';

// 2. Flutter SDK
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 3. 内部组件库（按层级）
import 'package:nacho/nacho.dart';
import 'package:lomo/lomo.dart';
import 'package:drv_uikit/drv_uikit.dart';
import 'package:go_uikit/global_one_uikit.dart';
import 'package:uikit/uikit.dart';
import 'package:driver_flutter_sdk/...';
import 'package:driver_uni_business/...';
import 'package:driver_uni_foundation/...';

// 4. 第三方包
import 'package:get/get.dart';
import 'package:json_annotation/json_annotation.dart';

// 5. 当前包内部
import 'package:current_package/src/...';

// 6. 相对路径（仅在同模块内使用）
import '../model/xxx_model.dart';
```

### 发现策略（import 路径与组件 API）

项目外部组件的 import 路径和常见用法已在 codegen prompt 的「组件依赖参考」章节预注入（来自 graphify 知识图谱 + 项目代码统计）。

1. **优先**：读取 prompt 中「组件依赖参考」的 import 路径和用法，直接使用
2. **Fallback**：参考表未覆盖时，grep 项目内已有 `.dart` 文件推断
   ```bash
   grep -rn "import.*ComponentName" lib/ --include="*.dart" | head -3
   grep -rn "ComponentName(" lib/ --include="*.dart" -A 2 | head -10
   ```
3. **禁止**：扫描项目根目录以外的任何路径（父目录、sibling 仓库、.pub-cache）

### 约束

- 业务代码禁止直接使用 `package:flutter/cupertino.dart` 中的 UI Widget（如 `CupertinoButton` / `CupertinoAlertDialog`）；如需 iOS 风格组件请改用项目内置封装。底层路由/动画工具（`CupertinoPageRoute` 等）由组件库内部使用，业务无需直接引入。
- 禁止引入未在 pubspec.yaml 声明的第三方包
- 业务代码 import `*UniNative.dart` / `*UniFlutter.dart` 时使用包内具体路径（这些文件无 barrel export）

---

## 四、编码约束

### 4.1 JSON 序列化

```dart
// Model 必须提供 fromJson 工厂
@JsonSerializable()
class FeatureNameModel {
  @JsonKey(name: 'field_name')
  final String fieldName;

  FeatureNameModel({required this.fieldName});

  factory FeatureNameModel.fromJson(Map<String, dynamic> json) =>
      _$FeatureNameModelFromJson(json);

  Map<String, dynamic> toJson() => _$FeatureNameModelToJson(this);
}
```

- 接口字段一律 `snake_case` + `@JsonKey` 注解
- Model 文件必须配套 `.g.dart` 生成文件
- 跨端传输实体需实现 `decode(Object data)` 静态工厂（UniAPI 规范）

### 4.2 Null Safety

- 全项目 Null Safety 启用（Dart >=2.12）
- 禁止 `late` 除非真正需要延迟初始化
- nullable 优先于 late：`String? name` > `late String name`
- 网络返回值统一声明为 `Future<T?>` — 永远假设可能为 null

### 4.3 异步

- 所有网络调用异步（`async/await`），禁止阻塞
- `FutureBuilder` / `StreamBuilder` 仅用于简单场景；复杂场景走 Controller + Obx
- 禁止 `Future.then().catchError()` 链式写法（难读），使用 try/catch

### 4.4 状态页面四态

每个页面/组件必须处理四种 UI 状态：

```dart
enum DIndicatorStatus { idle, loading, success, empty, error }
```

`DBaseController.status` 是 `DIndicatorStatus`（**非 `Rx`**），刷新通过 `update()` 触发。
View 层使用 `GetBuilder<XxxController>`：

```dart
GetBuilder<FeatureNameController>(
  builder: (controller) {
    switch (controller.status) {
      case DIndicatorStatus.loading:
        return GDCircleIndicator();
      case DIndicatorStatus.empty:
        return GDEmptyPage(config: GDEmptyPageConfig(...));
      case DIndicatorStatus.error:
        return _buildErrorView();
      case DIndicatorStatus.success:
        return _buildContent(controller.model);
      default:
        return const SizedBox.shrink();
    }
  },
)
```

> **禁止**：`controller.status.value` —— `status` 不是 `Rx<DIndicatorStatus>`，无 `.value` 属性。

### 4.5 暗黑模式颜色

禁止硬编码颜色值，必须使用 ThemeManager 的条件方法：

```dart
// ✅ 正确
color: ThemeManager.instance.getResNightMode(
  context,
  darkRes: GDColors.white,
  lightRes: GDColors.black,
)

// ❌ 错误
color: Colors.black
color: Color(0xFF000000)
```

### 4.6 屏幕适配

- 设计稿尺寸通过 `uikit/uikit.dart` 中的 `ScreenFitHelper` 扩展转换
- 仅有两个 API：`数字.fit()`（按设计稿短边比例缩放）和 `数字.w`（按宽度比例缩放）
- 禁止硬编码 dp 值用于间距/尺寸（需走适配）
- 禁止使用不存在的 `ScreenAdapter.scaleFit(value)` 静态方法

```dart
// ✅ 正确
SizedBox(height: 68.fit(), width: 100.w)

// ❌ 错误
SizedBox(height: 68, width: 100)
SizedBox(height: ScreenAdapter.scaleFit(68))  // 不存在
```

### 4.7 国际化

- 文案禁止硬编码中文/英文
- 通过 `flutter_i18n_helper` 包的 `I18NHelper.translate('key')` 调用（注意是 `I18NHelper`，N 大写）
- 实际项目通常通过 Taco 工具自动生成的 `_I18N` 单例提供 typed accessor，业务直接调用其 getter（如 `_i18n.privacyTitle`）

```dart
import 'package:flutter_i18n_helper/flutter_i18n_helper.dart';

final text = I18NHelper.translate('GDriver_popups_xxx_key');
```

---

## 五、代码审查检查项

codegen 后 Layer 2 验证包含以下检查：

- [ ] `dart analyze` 零 error
- [ ] `dart format` 通过
- [ ] 无 `Image.network` / `Navigator.push` / `showDialog` 等禁用 API
- [ ] 所有页面被 `DrvBaseViewWrapper` 包裹
- [ ] 颜色使用 `GDColors` 或 `ThemeManager.getResNightMode`
- [ ] Model 字段使用 `@JsonKey(name: 'snake_case')`
- [ ] 四态 UI（loading/success/empty/error）覆盖
- [ ] 无硬编码文案（必须走 i18n）

---

## 六、文件大小约束

| 文件类型 | 建议上限 | 硬性上限 |
|----------|---------|---------|
| View | 300 行 | 500 行 |
| Controller | 200 行 | 400 行 |
| Repository | 150 行 | 300 行 |
| Model | 100 行 | 200 行 |
| 组件入口 | 50 行 | 100 行 |

**超过硬性上限即视为 Layer 2 失败，codegen 阶段必须拆分子组件/子 Widget**。

---

## 七、Git 提交约束（目标项目）

```
feat(feature_name): 新增功能描述
fix(feature_name): 修复问题描述
refactor(feature_name): 重构描述
```

- 每个功能组件一个 commit（不跨功能合并）
- 生成的 `.g.dart` 文件与对应 Model 在同一 commit
