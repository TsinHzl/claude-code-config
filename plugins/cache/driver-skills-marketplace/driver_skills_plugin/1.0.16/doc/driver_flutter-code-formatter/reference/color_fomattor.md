
# Flutter 色值标准化指南

## 目标
扫描 Flutter 代码中的硬编码色值，并将其替换为 `GOColors` 标准库中的预置颜色，以提高代码可维护性和设计一致性。

---

## ⚠️ 重要前置要求

### 必需的包导入

使用标准色值库前，**必须**在文件顶部导入以下包：

```dart
import 'package:go_uikit/global_one_uikit.dart';
```

此包包含所有标准色值定义：
- `GOColors.*` - 通用色值常量
- `GlobalColorsDefine.*` - Global 标准色系
- `BRColorsDefine.*` - Brazil (99) 标准色系

## 一、色值映射表

### 1.1 GOColors 暗夜模式常量
```dart
// 来自 go_colors.dart
GOColors.lightGray      = Color(0xffCCCCCC)
GOColors.mediumGray     = Color(0xff999999)
GOColors.mediumBlack    = Color(0xff666666)
GOColors.boldBlack      = Color(0xff333333)
GOColors.backgroundDark = Color(0xff141414)
```

### 1.2 Global 标准色系（GlobalColorsDefine）
```dart
// 中性色（灰色系）
global_grey_1 = Color(0xffFFFFFF)  // 白色（界面底色）
global_grey_2 = Color(0xffF2F2F5)  // 灰_2（卡片底色/按钮底色）
global_grey_3 = Color(0xffD9D9DE)  // 灰_3（控件/选中态）
global_grey_4 = Color(0xffBABABF)  // 灰_4（三级文本/控件）
global_grey_5 = Color(0xff8A8A91)  // 灰_5（二级文本）
global_grey_6 = Color(0xff0C0C0D)  // 灰_6（一级文本、图标、控件）

// 主色（橙色系）
global_1  = Color(0xffFFE5D9)
global_2  = Color(0xffFFC9B0)
global_3  = Color(0xffFFAF8A)
global_4  = Color(0xffFF9563)
global_5  = Color(0xffFF793B)
global_6  = Color(0xffFF5F14)  // 主题色
global_7  = Color(0xffCC490C)
global_8  = Color(0xff993608)
global_9  = Color(0xff662303)
global_10 = Color(0xff331101)

// 橙黄色系（中危/等待）
global_orange_1  = Color(0xffFFF1D4)
global_orange_2  = Color(0xffFFE3AB)
global_orange_3  = Color(0xffFFD580)
global_orange_4  = Color(0xffFFC654)
global_orange_5  = Color(0xffFFB82B)
global_orange_6  = Color(0xffFFAA00)
global_orange_7  = Color(0xffCC8800)
global_orange_8  = Color(0xff996600)
global_orange_9  = Color(0xff664400)
global_orange_10 = Color(0xff332200)

// 绿色系（优惠/通过/成功）
global_green_1  = Color(0xffD0F5E9)
global_green_2  = Color(0xffA4EBD3)
global_green_3  = Color(0xff7ADEBD)
global_green_4  = Color(0xff55D4A9)
global_green_5  = Color(0xff32C997)
global_green_6  = Color(0xff13BF86)
global_green_7  = Color(0xff069968)
global_green_8  = Color(0xff03734E)
global_green_9  = Color(0xff024D34)
global_green_10 = Color(0xff00261A)

// 蓝色系（安全）
global_blue_1  = Color(0xffDEE3FF)
global_blue_2  = Color(0xffBAC6FF)
global_blue_3  = Color(0xff99AAFF)
global_blue_4  = Color(0xff788EFF)
global_blue_5  = Color(0xff5471FF)
global_blue_6  = Color(0xff3355FF)
global_blue_7  = Color(0xff213DCC)
global_blue_8  = Color(0xff122999)
global_blue_9  = Color(0xff081866)
global_blue_10 = Color(0xff020A33)

// 紫色系（特殊）
global_purple_1  = Color(0xffEDD4FA)
global_purple_2  = Color(0xffDAAAF2)
global_purple_3  = Color(0xffCA82ED)
global_purple_4  = Color(0xffB85CE6)
global_purple_5  = Color(0xffA838E0)
global_purple_6  = Color(0xff9816D9)
global_purple_7  = Color(0xff780EAD)
global_purple_8  = Color(0xff590882)
global_purple_9  = Color(0xff3B0357)
global_purple_10 = Color(0xff1D012B)

// 紫红色系（警示/失败）
global_plum_1  = Color(0xffFCD7DD)
global_plum_2  = Color(0xffFAAFBC)
global_plum_3  = Color(0xffF7889B)
global_plum_4  = Color(0xffF7637C)
global_plum_5  = Color(0xffF53D5C)
global_plum_6  = Color(0xffF2183D)
global_plum_7  = Color(0xffC2102E)
global_plum_8  = Color(0xff910920)
global_plum_9  = Color(0xff610414)
global_plum_10 = Color(0xff300109)
```

### 1.3 Brazil (99) 标准色系（BRColorsDefine）
```dart
// 中性色（与 Global 相同）
br_grey_1 = Color(0xffFFFFFF)  // 白色
br_grey_2 = Color(0xffF2F2F5)  // 灰_2
br_grey_3 = Color(0xffD9D9DE)  // 灰_3
br_grey_4 = Color(0xffBABABF)  // 灰_4
br_grey_5 = Color(0xff8A8A91)  // 灰_5
br_grey_6 = Color(0xff0C0C0D)  // 灰_6

// 主色（黄色系）
br_1  = Color(0xffFFF9D4)
br_2  = Color(0xffFFF4AB)
br_3  = Color(0xffFFEE80)
br_4  = Color(0xffFFE854)
br_5  = Color(0xffFFE32B)
br_6  = Color(0xffFFDD00)  // 99主题色
br_7  = Color(0xffCCB100)
br_8  = Color(0xff998500)
br_9  = Color(0xff665800)
br_10 = Color(0xff332C00)

// 橙色系
br_orange_1  = Color(0xffFFECD9)
br_orange_2  = Color(0xffFFD9B3)
br_orange_3  = Color(0xffFFC68C)
br_orange_4  = Color(0xffFFB366)
br_orange_5  = Color(0xffFF9F40)
br_orange_6  = Color(0xffFF8C19)
br_orange_7  = Color(0xffCC6E10)
br_orange_8  = Color(0xff995109)
br_orange_9  = Color(0xff663504)
br_orange_10 = Color(0xff331A01)

// 绿色系
br_green_1  = Color(0xffD2F7E5)
br_green_2  = Color(0xffA6EDCA)
br_green_3  = Color(0xff7EE6B2)
br_green_4  = Color(0xff59DE9B)
br_green_5  = Color(0xff35D484)
br_green_6  = Color(0xff14CC70)
br_green_7  = Color(0xff0DA358)
br_green_8  = Color(0xff077A41)
br_green_9  = Color(0xff03522A)
br_green_10 = Color(0xff012915)

// 蓝色系
br_blue_1  = Color(0xffD6EBFF)
br_blue_2  = Color(0xffADD6FF)
br_blue_3  = Color(0xff85C2FF)
br_blue_4  = Color(0xff5EAFFF)
br_blue_5  = Color(0xff369AFF)
br_blue_6  = Color(0xff0D86FF)
br_blue_7  = Color(0xff086ACC)
br_blue_8  = Color(0xff054F99)
br_blue_9  = Color(0xff023466)
br_blue_10 = Color(0xff011A33)

// 紫色系
br_purple_1  = Color(0xffF4D4FA)
br_purple_2  = Color(0xffEBADF7)
br_purple_3  = Color(0xffE085F2)
br_purple_4  = Color(0xffD55FED)
br_purple_5  = Color(0xffCD3BEB)
br_purple_6  = Color(0xffC317E6)
br_purple_7  = Color(0xff9B0FB8)
br_purple_8  = Color(0xff74088A)
br_purple_9  = Color(0xff4D045C)
br_purple_10 = Color(0xff26012E)

// 紫红色系
br_plum_1  = Color(0xffFFD6E4)
br_plum_2  = Color(0xffFFADC8)
br_plum_3  = Color(0xffFF85AD)
br_plum_4  = Color(0xffFF5E93)
br_plum_5  = Color(0xffFF3678)
br_plum_6  = Color(0xffFF1965)
br_plum_7  = Color(0xffCC0849)
br_plum_8  = Color(0xff990536)
br_plum_9  = Color(0xff660223)
br_plum_10 = Color(0xff330111)
```

---

## 二、识别不规范色值的规则

### 2.1 需要识别的模式

✅ **需要标记为不规范的情况：**
```dart
// 模式 1: 直接使用 Color 构造函数
Color(0xffCCCCCC)
Color(0xFF666666)
const Color(0xff999999)

// 模式 2: 使用 ColorHelper.fromHex
ColorHelper.fromHex('#CCCCCC')
ColorHelper.fromHex('#666666')
ColorHelper.fromHex('#999999')

// 模式 3: 在 ThemeManager.getResNightMode 中硬编码
ThemeManager.instance.getResNightMode(
  context,
  lightRes: ColorHelper.fromHex('#666666'),
  darkRes: ColorHelper.fromHex('#999999'),
)
```

❌ **不需要标记的情况（排除项）：**
```dart
// 1. 解析后端下发的动态颜色
Color(int.parse(serverColor))
ColorHelper.fromHex(response.data['color'])
ColorUtils.parseColor(dynamicColorString)

// 2. 已经使用标准色值
GOColors.lightGray
GOColors.grey_6
GlobalColorsDefine.global_grey_5

// 3. Colors 预定义常量
Colors.white
Colors.black
Colors.transparent
```

---

## 三、标准化替换原则

1. **精确匹配原则**：只有色值完全匹配时才替换为标准色
2. **保持原值原则**：没有精确匹配的色值，保持原有引用方式
3. **语义优先原则**：优先选择语义明确的标准色（如 `grey_6` 表示一级文本）
4. **暗夜模式原则**：考虑日间/夜间模式的色值对应关系

### 常用色值快速参考

| 硬编码色值 | 标准色值 | 使用场景 |
|-----------|---------|---------|
| `#FFFFFF` / `0xffFFFFFF` | `GOColors.grey_1` | 白色背景 |
| `#F2F2F5` / `0xffF2F2F5` | `GOColors.grey_2` | 卡片背景 |
| `#D9D9DE` / `0xffD9D9DE` | `GOColors.grey_3` | 控件/选中态 |
| `#BABABF` / `0xffBABABF` | `GOColors.grey_4` | 三级文本 |
| `#8A8A91` / `0xff8A8A91` | `GOColors.grey_5` | 二级文本 |
| `#0C0C0D` / `0xff0C0C0D` | `GOColors.grey_6` | 一级文本 |
| `#CCCCCC` / `0xffCCCCCC` | `GOColors.lightGray` | 夜间文本 |
| `#999999` / `0xff999999` | `GOColors.mediumGray` | 夜间二级文本 |
| `#666666` / `0xff666666` | `GOColors.mediumBlack` | 描述文本 |
| `#333333` / `0xff333333` | `GOColors.boldBlack` | 深色文本 |
| `#141414` / `0xff141414` | `GOColors.backgroundDark` | 夜间背景 |
| `#FF5F14` / `0xffFF5F14` | `GOColors.brand_6` | Global主题色 |
| `#FFDD00` / `0xffFFDD00` | `GOColors.brand_6` | BR主题色(自动) |

---

## 四、输出报告格式（简洁表格版）

### 4.1 发现问题时的报告格式

```markdown
## 🎨 色值标准化检查报告

**文件：** `path/to/file.dart`  
**扫描时间：** 2025-11-04 14:30:00  
**发现问题：** 5 处 | **已标准化：** 12 处 | **标准化率：** 70.6%

---

### ⚠️ 不规范色值列表

| # | 行号 | 当前代码 | 硬编码色值 | 建议替换 | 匹配状态 |
|---|------|---------|-----------|---------|---------|
| 1 | 45 | `Color(0xff666666)` | `#666666` | `GOColors.mediumBlack` | ✅ 精确匹配 |
| 2 | 78 | `ColorHelper.fromHex('#999999')` | `#999999` | `GOColors.mediumGray` | ✅ 精确匹配 |
| 3 | 89 | `ColorHelper.fromHex('#CCCCCC')` | `#CCCCCC` | `GOColors.lightGray` | ✅ 精确匹配 |
| 4 | 120 | `Color(0xffFF5F14)` | `#FF5F14` | `GOColors.brandColor` | ✅ 精确匹配 |
| 5 | 156 | `ColorHelper.fromHex('#0B0B0D')` | `#0B0B0D` | 保持原样 | ❌ 无匹配 |

---

### 📝 详细修改建议

#### 问题 1-3：日间/夜间模式色值（第 78-82 行）
```dart
// ❌ 当前代码
color: ThemeManager.instance.getResNightMode(
  context,
  lightRes: ColorHelper.fromHex('#666666'),  // 第78行
  darkRes: ColorHelper.fromHex('#999999'),   // 第79行
)

// ✅ 建议修改
// 1. 确保文件顶部已导入：import 'package:go_uikit/global_one_uikit.dart';
// 2. 替换为标准色值
color: ThemeManager.instance.getResNightMode(
  context,
  lightRes: GOColors.mediumBlack,  // 描述性文本
  darkRes: GOColors.mediumGray,    // 夜间二级文本
)
```

#### 问题 4：主题色（第 120 行）
```dart
// ❌ 当前代码
backgroundColor: Color(0xffFF5F14)

// ✅ 建议修改（需要导入 go_uikit）
backgroundColor: GOColors.brandColor  // 自动适配 Global/BR
```

#### 问题 5：无匹配色值（第 156 行）
```dart
// 当前代码
color: ColorHelper.fromHex('#0B0B0D')

// 建议：保持原样（无精确匹配的标准色）
// 或考虑使用最接近的 GOColors.grey_6 (0xff0C0C0D)
```

---

### ✅ 已正确使用标准色的示例

| 行号 | 代码 | 说明 |
|------|------|------|
| 34 | `GOColors.grey_6` | ✓ 一级文本 |
| 67 | `GOColors.mediumBlack` | ✓ 描述文本 |
| 92 | `GOColors.backgroundDark` | ✓ 夜间背景 |
| 145 | `GOColors.brandColor` | ✓ 主题色 |
```

---

### 4.2 无问题时的报告格式

```markdown
## 🎨 色值标准化检查报告

**文件：** `path/to/file.dart`  
**扫描时间：** 2025-11-04 14:30:00

---

### ✅ 检查通过

- **色值使用次数：** 23
- **标准色使用：** 23 处
- **标准化率：** 100%

所有色值均使用标准色库，无需优化。
```

---

### 4.3 多文件批量扫描报告格式

```markdown
## 🎨 色值标准化批量检查报告

**扫描范围：** `lib/src/income_module/`  
**扫描时间：** 2025-11-04 14:30:00  
**文件总数：** 15 | **问题文件：** 3

---

### 📊 总体统计

| 指标 | 数值 |
|------|------|
| 总色值使用次数 | 245 |
| 不规范色值 | 18 处 |
| 已标准化色值 | 227 处 |
| 整体标准化率 | 92.7% |

---

### ⚠️ 问题文件汇总

| 文件 | 问题数 | 可替换 | 无匹配 | 标准化率 |
|------|--------|--------|--------|----------|
| `income_page_banner_container.dart` | 5 | 4 | 1 | 70.6% |
| `reward_card_item_widget.dart` | 8 | 7 | 1 | 65.0% |
| `income_drawer_component.dart` | 5 | 5 | 0 | 60.0% |

---

### 🔍 各文件详细问题

#### 文件 1: `income_page_banner_container.dart`

| 行号 | 硬编码色值 | 建议替换 | 状态 |
|------|-----------|---------|------|
| 45 | `#666666` | `GOColors.mediumBlack` | ✅ 可替换 |
| 78 | `#999999` | `GOColors.mediumGray` | ✅ 可替换 |
| 89 | `#CCCCCC` | `GOColors.lightGray` | ✅ 可替换 |
| 120 | `#FF5F14` | `GOColors.brandColor` | ✅ 可替换 |
| 156 | `#0B0B0D` | 保持原样 | ❌ 无匹配 |

#### 文件 2: `reward_card_item_widget.dart`

| 行号 | 硬编码色值 | 建议替换 | 状态 |
|------|-----------|---------|------|
| 67 | `#8A8A91` | `GOColors.grey_5` | ✅ 可替换 |
| 89 | `#0C0C0D` | `GOColors.grey_6` | ✅ 可替换 |
| 112 | `#F2F2F5` | `GOColors.grey_2` | ✅ 可替换 |
| ... | ... | ... | ... |

---

### 💡 批量修复建议

1. **优先修复高频色值：** `#666666` (5次)、`#999999` (4次)、`#CCCCCC` (3次)
2. **建议批量替换：** 所有可精确匹配的色值 (16/18)
3. **需要人工审核：** 2 个无匹配的色值，建议与设计确认
```

---

## 五、实施步骤（For LLM Agent）

### 扫描和输出流程

1. **读取文件**：使用 `read_file` 工具读取目标 Dart 文件

2. **检查导入**：检查文件是否已导入 `package:go_uikit/global_one_uikit.dart`
   - 如果未导入，在报告中添加警告和导入建议
   - 使用 `grep` 搜索：`import 'package:go_uikit/global_one_uikit.dart'`

3. **提取色值**：使用 `grep` 工具查找色值模式：
   - 正则表达式：`Color\(0x[0-9a-fA-F]{8}\)`
   - 正则表达式：`ColorHelper\.fromHex\(['"]#[0-9a-fA-F]{6}['"]\)`

4. **过滤排除项**：
   - 排除动态色值（变量、函数返回值）
   - 排除已使用标准色（`GOColors.xxx`）
   - 排除 Colors 预定义常量

5. **查找映射**：
   - 提取色值的十六进制表示
   - 在映射表中查找精确匹配
   - 记录匹配结果和建议

6. **生成报告**：
   - 使用表格格式输出问题列表
   - 包含位置、问题、建议、匹配详情
   - 提供统计信息
   - **重要**：如果文件缺少导入，在报告顶部添加醒目提示

7. **执行替换（可选）**：
   - 征得用户确认后
   - **首先**：如果缺少导入，先添加 `import 'package:go_uikit/global_one_uikit.dart';`
   - **然后**：使用 `search_replace` 工具逐个替换不规范的色值
   - 执行 lint 检查验证修改

---

## 六、注意事项

1. **不要过度替换**：设计稿明确的特殊色值可能是合理的
2. **考虑业务场景**：Global 和 BR 的 `brand_6` 会自动切换
3. **夜间模式适配**：不是所有色值都需要夜间模式
4. **性能考虑**：标准色值都是 const，性能更好

---

**版本：** v1.1  
**最后更新：** 2025-11-04  

