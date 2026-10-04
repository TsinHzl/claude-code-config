# Flutter 架构规范（强制）

本规则定义了目标 Flutter 项目的架构模式、分层约束和通信规范。
codegen 生成的代码必须遵循以下架构约定。

---

## 一、分层架构

```
┌─────────────────────────────────────────────────┐
│ View 层（Widget）                                │
│  └─ DrvBaseViewWrapper 包裹                      │
│     └─ GetView<XxxController> / Obx             │
├─────────────────────────────────────────────────┤
│ Controller 层（逻辑）                            │
│  └─ extends DBaseController<XxxModel>           │
│     └─ 持有 Repository 实例                      │
├─────────────────────────────────────────────────┤
│ Repository 层（数据获取）                        │
│  └─ extends DRepo                               │
│     └─ 通过 DNetwork / UniNative 调用           │
├─────────────────────────────────────────────────┤
│ Model 层（数据模型）                             │
│  └─ @JsonSerializable / decode 工厂              │
├─────────────────────────────────────────────────┤
│ Platform Channel 层（Native 通信）               │
│  └─ driver_uni_business / driver_uni_foundation  │
│     └─ UniAPI 自动生成，禁止手动修改             │
└─────────────────────────────────────────────────┘
```

---

## 二、组件结构（Component Pattern）

每个功能组件遵循 Lomo 组件化模式：

```
feature_name_component/
├── feature_name_comp.dart       # 组件入口（library + abstract class + factory）
├── controller/
│   └── feature_name_controller.dart  # GetxController（part of）
├── impl/
│   └── feature_name_comp_impl.dart   # 组件实现（part of）
├── view/
│   └── feature_name_view.dart        # Widget（part of）
├── repo/
│   └── feature_name_repo.dart        # Repository（part of 或独立）
└── model/
    └── feature_name_model.dart       # 数据模型
```

### 组件入口模板

```dart
library feature_name_comp;

import 'package:lomo/lomo.dart';
// ... 其他 imports

part 'controller/feature_name_controller.dart';
part 'impl/feature_name_comp_impl.dart';
part 'view/feature_name_view.dart';

abstract class FeatureNameComp extends Component {
  Map? routeArgs;
  FeatureNameComp({this.routeArgs});

  /// 单实例
  factory FeatureNameComp.getInstance({String? tag, Map? routeArgs}) {
    if (Lomo.isRegistered<FeatureNameComp>(tag: tag)) {
      return Lomo.find<FeatureNameComp>(tag: tag);
    }
    return Lomo.put<FeatureNameComp>(FeatureNameCompImpl(routeArgs: routeArgs), tag: tag);
  }

  /// 多实例
  factory FeatureNameComp.newInstance({String? tag, Map? routeArgs}) {
    return Lomo.putNewInstance(() => FeatureNameCompImpl(routeArgs: routeArgs), tag: tag);
  }
}
```

---

## 三、状态管理

### 强制规范

| 场景 | 方案 | 说明 |
|------|------|------|
| 页面/组件状态 | `GetxController` + `Obx` | 通过 `DBaseController<T>` 基类 |
| 依赖注入 | `Lomo.put<T>()` / `Lomo.find<T>()` | Lomo 为项目标准 DI |
| 跨组件通信 | `DEventBus` | 三端联动事件总线 |
| 全局状态 | `DrvDVMCacheBridge` | 适用于 DVM/Flutter 切换场景 |

### 禁止

- ❌ `Provider` — 项目不使用
- ❌ `BLoC / Cubit` — 除非已有模块使用（passport_module 例外）
- ❌ `Riverpod` — 项目不使用
- ❌ `setState()` — 除非极简场景（<10 行 Widget）

### Controller 模板

`DBaseController<T>` 内部封装：
- `T? get model` / `void setModel(T?)` / `void updateModel(T?)`（后者会触发 `update()`）
- `DIndicatorStatus get status` / `void setStatus(...)` / `void updateStatus(...)`（后者触发 `update()`）
- 基于 GetX `update()` 通知，**View 层使用 `GetBuilder`**；若需细粒度响应式则在 Controller 内显式声明 `Rx<T>` 字段。

```dart
part of feature_name_comp;

class FeatureNameController extends DBaseController<FeatureNameModel> {
  final FeatureNameRepo _repo = FeatureNameRepo();

  @override
  void onInit() {
    super.onInit();
    _loadData();
  }

  @override
  void onClose() {
    _repo.exit();
    super.onClose();
  }

  Future<void> _loadData() async {
    updateStatus(DIndicatorStatus.loading);
    try {
      final result = await _repo.fetchData();
      updateModel(result);  // 同时刷新 UI（不要直接 model = result）
      updateStatus(DIndicatorStatus.success);
    } catch (e) {
      updateStatus(DIndicatorStatus.error);
    }
  }
}
```

---

## 四、页面包裹（强制）

**每个页面/组件的根 Widget 必须被 `DrvBaseViewWrapper` 包裹**，否则不具备：
- 暗黑模式自动切换
- 大字体适配
- 横竖屏刷新响应

```dart
@override
Widget build(BuildContext context) {
  return DrvBaseViewWrapper(
    scaffoldBgDarkColor: Colors.black,
    scaffoldBgLightColor: Colors.white,
    isThemeUpdate: true,
    isScreenOrientationUpdate: false,
    builder: (wrapperContext) {
      return Scaffold(
        appBar: GDAppBar(title: '...'),
        body: _buildBody(wrapperContext),
      );
    },
  );
}
```

---

## 五、网络请求

### 强制约束

- **Flutter 侧禁止直接使用 `http`、`dio` 或任何 HTTP 客户端发送网络请求**
- 所有网络请求必须通过 `DNetwork`（Platform Channel 委托到 Native HTTP 栈）
- Native 侧统一处理：签名、公共参数、证书 pinning、Host 配置

### Repository 模板

`DBaseRepo.sendBffRequest<T>(String abilityId, T Function(dynamic) fromJsonT, {Map<String, Object>? params})`
返回 `Future<DBaseResponse<T>?>`，其中 `DBaseResponse<T>` 字段：`int errno`、`String errmsg`、`T? data`、`bool netError`。

```dart
class FeatureNameRepo extends DRepo {
  Future<FeatureNameModel?> fetchData() async {
    final response = await DBaseRepo.sendBffRequest<FeatureNameModel>(
      'ability_id_xxx',                          // BFF abilityId（位置参数）
      (json) => FeatureNameModel.fromJson(json), // fromJsonT 反序列化器（位置参数）
      params: {'key': 'value'},                  // 命名参数
    );
    if (response?.errno == 0) {
      return response?.data;
    }
    return null;
  }

  @override
  void enter() { /* 页面进入时初始化 */ }

  @override
  void exit() { /* 页面退出时取消请求 */ }
}
```

**禁止用法**：
- ❌ `sendBffRequest(path: '...', params: {...})` — 第一个参数是位置参数 `abilityId`，不是 `path:`
- ❌ 不传 `fromJsonT` — 它是必填位置参数（接收 `dynamic json` 返回 `T`）

---

## 六、路由

### 强制使用 DrvNavigator（责任链路由）

```dart
import 'package:driver_flutter_sdk/base/new_route/drv_navigator.dart';

// 跳转 Flutter 页面
DrvNavigator.jump(NavReq(url: '/feature_name', params: {'id': '123'}));

// 返回（静态方法）
Nacho.maybePop();

// 关闭 Native 容器（实例方法，必须通过 instance 调用）
Nacho.instance.popSystemNavigator(animated: true);
```

### 路由注册

通过 `DrvLaunchTaskManager` 注册路由表：

```dart
Map<String, WidgetBuilder> getRouteMap() => {
  '/feature_name': (_) => FeatureNameComp.getInstance().buildView(),
};
```

### 禁止

- ❌ `Navigator.push(MaterialPageRoute(...))` — 不走责任链
- ❌ `go_router` — 项目不使用
- ❌ 直接 `Navigator.pop()` — 可能破坏混合栈

---

## 七、事件总线

### 三端联动事件总线（DEventBus）

```dart
// 定义事件
class MyFeatureEvent extends DEBEvent {
  final String data;
  MyFeatureEvent(this.data) : super(uniKey: 'my_feature_event');
}

// 发送（同时广播到 Native 端）
DEventBus().postEvent(MyFeatureEvent('hello'));

// 监听
DEventBus().listenEvent<MyFeatureEvent>((event) {
  // handle
});
```

---

## 八、Native 通信（UniAPI）

### 规范

| 方向 | 类命名 | 调用方式 |
|------|--------|---------|
| Flutter → Native | `XxxUniNative` (static) | `await XxxUniNative.methodName(params)` |
| Native → Flutter | `XxxUniFlutter` (abstract) | 实现接口 + `XxxUniFlutter.setup(impl)` 注册 |

### 约束

- 所有 `*UniNative` / `*UniFlutter` 文件标记为 `Autogenerated from uniAPI`，**禁止手动修改**
- 业务代码不应手写 channel 名；通过 `*UniNative` 静态方法调用即可
- 底层使用 `BasicMessageChannel + StandardMessageCodec`，非 MethodChannel

---

## 九、生命周期管理

| 组件 | 生命周期接口 | 使用方式 |
|------|-------------|---------|
| Repository | `ILifecycle` → `enter()` / `exit()` | 页面进入时创建，退出时取消请求 |
| Controller | `onInit()` / `onClose()` | GetxController 标准生命周期 |
| 页面可见性 | `DPageVisibleDetector` | Nacho 容器生命周期 + Flutter 路由栈判断 |
| App 前后台 | `AppUniFlutter.appWillEnterForeground()` | 由 Native 推送 |

---

## 十、暗黑模式

### 强制规范

- 通过 `ThemeManager.instance` 管理，**不使用** Flutter 原生 `ThemeData` 的 brightness
- 颜色切换使用 `ThemeManager.instance.getResNightMode(context, darkRes:, lightRes:)`
- 判断暗黑使用 `ThemeManager.instance.isDarkTheme(context)`
- 每个组件的 Config 类必须包含 `darkStyle` 或 `darkMode()` 实现

---

## 十一、埋点规范

| 场景 | API | 说明 |
|------|-----|------|
| 事件埋点 | `DOmegaUtil.trackEvent(eventName, params)` | 走 Native Omega SDK |
| 错误上报 | `OmegaUniNative.trackError(...)` | 分 module/type |
| 曝光追踪 | `DExposureTracker` Widget | 可见性触发上报 |
| 性能链路 | `HermesTracker` | init → start → stop |

---

## 十二、禁止事项清单

| 禁止 | 原因 | 替代方案 |
|------|------|---------|
| 直接 HTTP 请求 | Native 统一鉴权签名 | `DNetwork` / `DBaseRepo` |
| SharedPreferences 存敏感数据 | 安全合规 | Native Keychain/Keystore |
| print() 生产环境 | 性能泄漏 | 移除或 DEBUG 宏保护 |
| 手动修改 UniAPI 生成文件 | 会被覆盖 | 修改 .uniapi 定义后重新生成 |
| setState 管理页面状态 | 不可维护 | GetxController + Obx |
| 跨组件直接依赖具体实现 | 耦合 | 通过 Lomo DI 依赖抽象 |
