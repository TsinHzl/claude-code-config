---
name: flutter-code-formatter
description: 扫描和优化 Flutter 代码以符合司机端代码规范。检测硬编码色值、MediaQuery 性能问题、Image.asset 用法。适用于 Flutter 代码审查、git diff 分析、代码片段检查、color formatting、GOColors 标准化、MediaQuery 优化、DiDiImage 迁移。
---

# Flutter 代码规范化工具

这是一个专为司机端 Flutter 项目设计的代码规范检查工具。它能够自动扫描代码并识别不符合规范的写法，提供详细的修改建议。

## 支持的输入方式

- **完整文件路径**：直接分析指定的 Dart 文件
- **Git 仓库路径**：分析 git 仓库的变更内容（使用临时文件机制）
- **目录扫描**：批量检查整个目录下的所有 Dart 文件

## 特殊参数处理

### -h 参数：显示帮助文档

当用户输入 `-h` 或 `--help` 时：
1. 读取并输出 `[readme.md](reference/readme.md)` 的完整内容,**不要总结归纳，原文输出**。
2. 不执行任何代码检查操作
3. 输出帮助内容后，提示用户："请输入你的代码或文件路径，我将帮你检查代码规范"
4. 等待用户输入正式的检查请求

## 核心检查规则

### 规则 1: 色值标准化检查

**目标**：将硬编码的色值替换为 `GOColors` 标准色库，提高代码可维护性和设计一致性。

**触发条件**：代码中包含以下任一模式
- `Color(0xffXXXXXX)` 或 `Color(0xFFXXXXXX)`
- `ColorHelper.fromHex('#XXXXXX')`
- `ThemeManager.instance.getResNightMode` 中包含硬编码色值

**检查方法**：
1. 使用 `grep` 工具搜索色值模式（正则：`Color\(0x[0-9a-fA-F]{8}\)` 或 `ColorHelper\.fromHex`）
2. 提取所有硬编码色值
3. 参照 [色值扫描规范化手册](./reference/color_fomattor.md) 中的映射表查找对应的标准色值
4. 生成详细的检查报告（包含行号、当前色值、建议替换值、匹配状态）

**排除项**（不需要标记）：
- 已使用标准色：`GOColors.xxx`、`GlobalColorsDefine.xxx`、`BRColorsDefine.xxx`
- Flutter 预定义常量：`Colors.white`、`Colors.transparent` 等
- 动态色值：从服务端或变量解析的颜色

**输出示例**（仅当发现问题时输出）：
```markdown
| 文件 | 行号 | 当前代码 | 问题类型 | 建议替换/修改 |
|------|------|---------|---------|-------------|
| lib/pages/income_page.dart | 45 | Color(0xff666666) | 色值标准化 | GOColors.mediumBlack |
| lib/pages/income_page.dart | 78 | ColorHelper.fromHex('#999999') | 色值标准化 | GOColors.mediumGray |
```

**详细映射规则**：请查阅 [reference/color_fomattor.md](./reference/color_fomattor.md)

---

### 规则 2: MediaQuery 性能优化

**目标**：避免因 `MediaQuery.of(context)` 导致的不必要的 Widget 重建。

**问题说明**：
`MediaQuery.of(context)` 内部使用 `dependOnInheritedWidgetOfExactType`，会在 element 与 MediaQuery 之间建立依赖关系。当 MediaQuery Data 变更时（如屏幕旋转、键盘弹出），会导致依赖的 Widget 树重刷，影响性能。

**检查方法**：
1. 使用 `grep` 搜索 `MediaQuery.of(context)` 模式
2. 识别所有使用场景
3. 给出性能警告和优化建议

**不规范写法**：
```dart
// ❌ 会建立依赖，导致不必要的重建
double width = MediaQuery.of(context).size.width;
double height = MediaQuery.of(context).size.height;
EdgeInsets padding = MediaQuery.of(context).padding;
```

**推荐写法**：
```dart
// ✅ 避免建立依赖关系
double width = MediaQueryData.fromView(View.of(context)).size.width;
double height = MediaQueryData.fromView(View.of(context)).size.height;
EdgeInsets padding = MediaQueryData.fromView(View.of(context)).padding;
```

**输出示例**（仅当发现问题时输出）：
```markdown
| 文件 | 行号 | 当前代码 | 问题类型 | 建议替换/修改 |
|------|------|---------|---------|-------------|
| lib/pages/income_page.dart | 67 | double width = MediaQuery.of(context).size.width; | MediaQuery性能优化 | double width = MediaQueryData.fromView(View.of(context)).size.width; |
| lib/pages/income_page.dart | 89 | EdgeInsets padding = MediaQuery.of(context).padding; | MediaQuery性能优化 | EdgeInsets padding = MediaQueryData.fromView(View.of(context)).padding; |
```

---

### 规则 3: Image.asset 迁移至 DiDiImage.asset

**目标**：统一使用项目自定义的 `DiDiImage` 组件，获得更好的性能和功能支持。

**检查方法**：
1. 使用 `grep` 搜索 `Image.asset(` 模式
2. 识别所有 Image.asset 使用场景
3. 提供迁移建议

**不规范写法**：
```dart
// ❌ 使用原生 Image.asset
Image.asset(
  ThemeManager.instance.getResNightMode(context,
    lightRes: "assets/images/icon_permission_camera_normal.webp",
    darkRes: "assets/images_night/icon_permission_camera_night.webp"
  ),
  package: "driver_main",
  width: 20,
  height: 20,
)
```

**推荐写法**：
```dart
// ✅ 使用 DiDiImage.asset
DiDiImage.asset(
  ThemeManager.instance.getResNightMode(context,
    lightRes: "assets/images/icon_permission_camera_normal.webp",
    darkRes: "assets/images_night/icon_permission_camera_night.webp"
  ),
  packageName: "driver_main",        // 参数名变更
  matchTextDirection: false,         // 必传参数
  width: 20,
  height: 20,
)
```

**关键差异**：
- 参数名变更：`package` → `packageName`
- 新增必传参数：`matchTextDirection: false`（控制图片是否根据文本方向镜像）

**输出示例**（仅当发现问题时输出）：
```markdown
| 文件 | 行号 | 当前代码 | 问题类型 | 建议替换/修改 |
|------|------|---------|---------|-------------|
| lib/pages/income_page.dart | 123 | Image.asset(...) | Image.asset迁移 | 迁移至 DiDiImage.asset，注意参数变更：package→packageName，添加 matchTextDirection |
```

---

## 使用指南

### 支持的执行模式

用户可以选择：
1. **执行所有规则**（默认）：完整的代码规范检查
2. **选择性执行**：指定一个或多个规则进行检查

### 输入方式场景

#### 场景 1: 检查单个文件（执行所有规则）
```
请帮我检查 lib/pages/income_page.dart 的代码规范
```

#### 场景 2: 基于 Git 仓库路径检查（执行所有规则）
```
请检查 /path/to/flutter-project 基于 master 分支的 git diff 代码规范
```

#### 场景 3: 分析粘贴的 Git Diff（执行所有规则）
```
请分析这个 git diff 中的代码是否符合规范：
[粘贴 git diff 内容]
```

#### 场景 4: 检查代码片段（执行所有规则）
```
请检查这段代码是否符合规范：
[粘贴代码]
```

#### 场景 5: 批量扫描目录（执行所有规则）
```
请扫描 lib/src/income_module/ 目录下所有文件的代码规范
```

### 选择性执行规则

用户可以明确指定只执行某个或某几个规则：

#### 仅执行规则 1: 色值标准化检查
```
请检查 lib/pages/income_page.dart 的色值标准化问题
请用色值标准化规则检查这个文件
```

#### 仅执行规则 2: MediaQuery 性能优化
```
请检查 lib/pages/income_page.dart 的 MediaQuery 性能问题
请检查这段代码中的 MediaQuery 用法
```

#### 仅执行规则 3: Image.asset 迁移检查
```
请检查 lib/pages/income_page.dart 的 Image.asset 用法
请检查这段代码中是否有 Image.asset 需要迁移
```

#### 组合执行多个规则
```
请检查 lib/pages/income_page.dart 的色值标准化和 MediaQuery 性能问题
请只检查色值和 Image.asset 用法，不检查其他规则
```

### 规则识别说明

**识别用户意图的关键词**：
- **规则 1**：色值、颜色、Color、GOColors、ColorHelper、标准化
- **规则 2**：MediaQuery、性能、优化、重建、Widget 性能
- **规则 3**：Image.asset、DiDiImage、图片组件、迁移

**默认行为**：
- 如果用户没有明确指定规则，执行所有三个规则的完整检查
- 如果用户明确指定了规则（通过关键词），只执行指定的规则

---

## 输出规范

### 输出原则

1. **仅输出发现的问题**：只显示实际检测到的问题点和修改建议
2. **不输出统计信息**：不包含问题统计、时间戳、文件路径等额外信息
3. **无问题不输出**：如果所有检查规则都没有发现问题，不输出任何内容

### 输出格式

当检测到问题时，直接输出问题表格（不包含标题、统计等）：

```markdown
| 文件 | 行号 | 当前代码 | 问题类型 | 建议替换/修改 |
|------|------|---------|---------|-------------|
| lib/pages/income_page.dart | 45 | Color(0xff666666) | 色值标准化 | GOColors.mediumBlack |
| lib/pages/income_page.dart | 78 | ColorHelper.fromHex('#999999') | 色值标准化 | GOColors.mediumGray |
```

多个规则发现问题时，按规则分组输出表格，每个规则只输出有问题的表格。

---

## 输入类型处理指南

### 1. 完整文件路径
- 使用 `Read` 工具直接读取文件内容
- 适用于检查单个 Dart 文件

### 2. Git 仓库路径

为避免 git diff 输出过长被截断，采用临时文件方式处理：

**处理流程**：
1. **生成临时文件**：执行命令生成 diff 文件
   ```bash
   cd <仓库路径> && git diff <target> > "temp_$(basename $(git rev-parse --show-toplevel))_<target>.gitdiff" && echo "✅ 文件已生成: temp_$(basename $(git rev-parse --show-toplevel))_<target>.gitdiff"
   ```
   - `<target>` 为用户输入的目标分支（如 master、develop）
   - 临时文件命名格式：`temp_<项目名>_<target分支>.gitdiff`
   
2. **读取文件内容**：使用 `Read` 工具读取临时文件的完整内容
   - 临时文件中包含所有变更的代码
   - 从临时文件中提取代码内容进行规范检查

3. **删除临时文件**：检查完成后，删除临时文件
   ```bash
   rm "temp_<项目名>_<target分支>.gitdiff"
   ```

**用途**：获取 git diff 内容后，可对变更的代码进行规范检查

### 3. Git diff 内容
- 用户直接粘贴的 git diff 文本
- 直接分析 diff 中的代码片段

### 4. 代码片段
- 用户直接粘贴的代码块
- 可以是完整的类、方法或代码片段

### 5. 目录扫描
- 使用 `Glob` 工具查找目录下所有 `.dart` 文件
- 使用 `Grep` 工具批量搜索模式
- 适用于大规模代码审查

---

## 工作流程

1. **分析用户请求**
   - **首先检查是否为帮助请求**：
     - 如果用户输入包含 `-h` 或 `--help`，执行上述"特殊参数处理"流程
     - 否则，继续以下正常检查流程
   - **识别输入类型**：
     - Git 仓库路径：用户提供的是一个目录路径，并提到 git diff 或分支名
     - 完整文件路径：用户提供的是 `.dart` 文件路径
     - Git diff 内容：用户粘贴的包含 `diff --git` 的文本
     - 代码片段：用户粘贴的 Dart 代码
     - 目录扫描：用户要求扫描整个目录
   - **识别用户想要执行的规则**：
     - 检查用户消息中是否包含规则关键词（色值、MediaQuery、Image.asset 等）
     - 如果有关键词，只执行对应的规则
     - 如果没有明确指定，执行所有规则（默认行为）

2. **获取代码内容**：
   - **如果是 Git 仓库路径**：按照"输入类型处理指南 § 2"执行临时文件流程
   - **如果是文件路径**：使用 `Read` 工具读取文件内容
   - **如果是粘贴的内容**：直接使用用户提供的文本

3. **模式匹配**：使用 `Grep` 工具搜索需要检查的模式（只搜索用户指定的规则相关模式）

4. **规则扫描**：
   - 如果用户指定了规则，只应用指定的规则
   - 如果未指定，依次应用所有三个检查规则

5. **生成报告**：仅输出发现的问题表格，不包含统计信息、时间戳等额外内容

6. **清理工作**：
   - 如果使用了临时文件（Git 仓库路径方式），删除临时 `.gitdiff` 文件
   
7. **无问题处理**：如果所有检查规则都没有发现问题，不输出任何内容

---

## 技术细节

### Grep 搜索模式

```bash
# 色值检查
grep -E "Color\(0x[0-9a-fA-F]{8}\)" target.dart
grep -E "ColorHelper\.fromHex\(['\"]#[0-9a-fA-F]{6}['\"]\)" target.dart

# MediaQuery 检查
grep "MediaQuery\.of\(context\)" target.dart

# Image.asset 检查
grep "Image\.asset\(" target.dart
```

### 处理优先级

1. 首先执行所有 grep 搜索（并行）
2. 收集所有匹配结果
3. 对每种规则进行详细分析
4. 生成综合报告

---

## 注意事项

1. **非破坏性检查**：此 Skill 仅进行代码分析和建议，不会自动修改代码
2. **精确匹配原则**：色值替换仅在完全匹配标准色时才建议替换
3. **业务场景考虑**：某些特殊色值可能是设计要求，需人工判断
4. **性能优化权衡**：MediaQuery 优化建议需根据实际 Widget 重建频率决定是否采纳
5. **临时文件处理**：使用 Git 仓库路径方式时，会在当前目录生成临时 `.gitdiff` 文件，检查完成后会自动删除

---

## 版本信息

- **Version**: 2.1.0
- **最后更新**: 2025-11-05
- **兼容性**: Claude Code 1.0+
- **支持的 Flutter 版本**: 2.0+
- **更新内容**：
  - 新增 Git 仓库路径支持（使用临时文件机制）
  - 新增 -h 参数显示帮助文档
  - 优化输入类型识别和处理流程

---

## 相关资源

- [色值标准化详细手册](./reference/color_fomattor.md) - 完整的 GOColors 映射表和扫描规则
- GOColors 标准色库文档（司机端内部）
- Flutter 性能优化最佳实践