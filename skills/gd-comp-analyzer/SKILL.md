---
name: gd-comp-analyzer
description: 司机端Flutter业务组件自动化分析及文档生成框架。输入Lomo架构的组件名，输出结构化、标准化的Markdown文档，清晰描述组件的架构、功能和内外交互。支持直接输出或生成文档文件。适用于组件文档生成、架构分析、代码审查等场景。
---

# Flutter 业务组件自动化分析及文档生成框架

司机端 Flutter 项目（Lomo 架构）组件分析工具。自动定位组件文件、分析代码结构、提取 API 信息、分析业务逻辑和 UI 交互，生成结构化组件文档。

## 目标

输入 Lomo 架构组件名，输出结构化 Markdown 文档，描述组件的架构、功能和内外交互。

## 输入参数

### 必需参数

1. **`component_name`**: 组件的蛇形命名 (e.g., `go_online_button_component`)
2. **`component_chinese_name`**: 组件的中文名 (e.g., `出车区域`)

### 可选参数

3. **`output_mode`**: 输出方式，支持两种模式：
   - `console`（默认）：直接输出到对话中，不生成文件
   - `file`：生成 Markdown 文档到指定路径或当前目录
4. **`target_markdown_path`**: 目标文档的绝对路径（仅当 `output_mode=file` 时需要）
5. **`target_header_name`**: 文档中待插入或更新的章节标题 (e.g., `### 5. 出车区域 go_online_button_component`)（仅当 `output_mode=file` 时需要）

## 输入方式支持

### 代码输入方式

三种代码输入方式：

1. 用户提供代码库路径：指定 Flutter 项目根目录路径
2. 用户提供组件名称：从当前工作目录搜索组件
3. 用户通过上下文引入代码：已在上下文中提供相关代码文件

### 输出方式识别

用户可以在初始输入时明确指定输出方式，也可以由系统询问：

1. **用户明确指定**：在输入中包含以下关键词
   - "直接输出" / "输出到对话" / "console" → 设置 `output_mode=console`
   - "生成文件" / "生成文档" / "保存为" / "file" → 设置 `output_mode=file`
   - 如果指定了文件路径（如 `/path/to/doc.md`），自动设置 `output_mode=file`

2. **系统询问**：如果用户未明确指定输出方式，在开始分析前询问：
   ```
   请选择输出方式：
   1. 直接输出到对话中（推荐，可即时查看）
   2. 生成 Markdown 文档到当前目录
   3. 生成 Markdown 文档到指定路径（需提供路径）
   ```

## 特殊参数处理

### -h 参数：显示帮助文档

当用户输入 `-h` 或 `--help` 时：
1. 输出本 Skill 的完整说明文档
2. 不执行任何分析操作
3. 输出帮助内容后，提示用户："请输入组件信息，我将帮你生成组件文档"
4. 等待用户输入正式的分析请求

## 核心工作流程

### Phase 0: 确认输出方式

**在开始分析前，首先确认输出方式**：

1. **检查用户输入**：
   - 是否包含输出方式关键词（"直接输出"、"生成文件"等）
   - 是否提供了文件路径（如 `/path/to/doc.md`）

2. **如果未明确指定**，询问用户：
   ```
   请选择输出方式：
   1. 直接输出到对话中（推荐，可即时查看）
   2. 生成 Markdown 文档到当前目录（文件名：{component_name}_组件文档.md）
   3. 生成 Markdown 文档到指定路径（需提供完整路径）
   ```

3. **根据用户选择设置参数**：
   - 选择 1：`output_mode=console`
   - 选择 2：`output_mode=file`，自动生成文件名为 `{component_name}_组件文档.md` 到当前目录
   - 选择 3：`output_mode=file`，使用用户提供的 `target_markdown_path`

4. **如果选择文件输出**：
   - 如果未提供 `target_header_name`，使用默认标题：`### {component_chinese_name} {component_name}`
   - 如果文件不存在，创建新文件
   - 如果文件存在且指定了章节标题，更新对应章节
   - 如果文件存在但未指定章节标题，追加到文件末尾

### Phase 1: 文件定位与代码分析 (Analysis Framework)

#### 步骤 1: 定位组件核心文件

**目标**：在代码库中找到与 `component_name` 匹配的组件目录及其核心文件。

**执行方法**：
1. 使用 `glob_file_search` 搜索包含 `component_name` 的目录
   - 搜索模式：`**/*{component_name}*/**/*.dart`
   - 优先匹配完全包含 `component_name` 的目录路径
2. 在找到的组件目录中，定位并读取以下核心文件和目录：
   - `{component_name}_comp.dart` - 组件入口与抽象接口（可能使用 `part` 机制包含其他文件）
   - `impl/` 目录下的所有 `.dart` 文件 - 组件具体实现类（如 `{component_name}_comp_impl.dart`）
   - `view/` 目录下的所有 `.dart` 文件 - UI 视图与用户交互（可能是主文件的 `part`）
   - `controller/` 目录下的所有 `.dart` 文件 - 业务逻辑与状态管理（可能是主文件的 `part`）
   - `repo/` 目录下的所有 `.dart` 文件 - 数据仓库与 API 请求
   - `model/` 目录下的所有 `.dart` 文件 - 数据模型定义
   - `event/` 目录下的所有 `.dart` 文件 - 事件定义
   - `channel/` 目录下的所有 `.dart` 文件 - 原生通道相关实现
   - `track/` 目录下的所有 `.dart` 文件 - 埋点相关代码
   - `state/` 或 `view_model/` 等子目录下的所有 `.dart` 文件 - 状态机、视图模型等
   - `util/` 等子目录下的所有 `.dart` 文件 - 工具类。包括埋点上报、整合的重复逻辑等功能。
3. **注意文件组织方式**：
   - 某些组件使用 `part` 和 `part of` 机制，将 controller、impl、view 作为主文件的 part
   - 如果主文件包含 `part 'controller/...'` 等声明，需要同时读取对应的 part 文件
   - 如果文件是独立的，直接读取即可
4. 使用 `read_file` 读取所有找到的核心文件内容

**输出**：组件目录路径和所有核心文件的完整内容

#### 步骤 2: 分析 `repo` 文件 (获取 API 信息)

**目标**：从 repo 文件中提取 API 接口信息。

**执行方法**：
1. 在 repo 文件中搜索 API 路径字符串常量：
   - 使用 `grep` 搜索模式：`(?:const\s+\w+\s*=\s*|static\s+String\s+repoPath\s*=\s*)['"](.*?)['"]`
   - 支持两种常见格式：
     - `const dailyReceiptsGet = '...'` - 常量定义
     - `static String repoPath = "..."` - 静态字符串（更常见，如 `DGetOnlineRepo`、`DSetOnlineRepo`）
   - 记录所有独立调用的接口路径
2. 检查网络请求方法（如 `sendBffRequest`、`get`、`post` 等）：
   - 查找方法调用中的 `params` 参数
   - 记录参数的键值对结构
   - 分析参数的数据类型和用途
   - 注意：某些 repo 可能接收字符串参数（如 `requestParamsString`），需要解析 JSON
3. 记录 Repo 类名：
   - 查找 `class\s+(\w+Repo)` 或类似模式（通常继承自 `DRepo`）
   - 记录完整的类名

**输出**：
- 接口名列表（或注明"无"）
- 关键入参列表（键名和简要说明）
- Repo 类名

#### 步骤 3: 分析 `controller` / `view_model` / `state` 文件 (业务逻辑分析)

**目标**：分析组件的业务功能、事件监听和状态管理。

**执行方法**：

1. **业务功能分析（重点）**：
   - 阅读 controller 文件，识别核心业务方法：
     - 查找 public 方法和关键 private 方法
     - 分析方法命名（如 `getOnlineStatus`、`setOnlineStatus`、`toStart`、`toStop` 等）
     - 理解方法的业务含义，而非仅技术实现
   - 分析业务流程：
     - 追踪方法调用链，理解完整的业务流程
     - 识别业务状态变化（如：离线 -> 在线、待接单 -> 接单中）
     - 识别业务规则和条件判断（如：出车前检查、状态校验）
   - 识别业务数据模型：
     - 查找 controller 中使用的 model 类
     - 理解数据模型在业务中的含义（如：`GetOnlineStatusModel` 表示在线状态数据）
   - 分析业务异常处理：
     - 查找 try-catch 块和错误处理逻辑
     - 识别业务失败场景和用户提示
   - 记录业务功能点：
     - 用业务语言描述功能（如："出车功能"、"收车功能"、"状态查询"）
     - 避免仅描述技术实现（如："调用 API"、"更新状态"）

2. **事件监听分析（受外部控制）**：
   - 使用 `grep` 搜索：`DEventBus\.instance(?:\.eventBus)?\.on` 或 `\.listen\(`
   - 支持两种格式：
     - `DEventBus.instance.eventBus.on<EventType>().listen(...)`
     - `DEventBus.instance.on(...)`
   - 提取事件类型和业务目的：
     - 分析监听的事件在业务中的含义（如：监听出车状态变化事件）
     - 记录事件触发的业务行为
   - 记录格式：`事件名: 业务目的`

3. **状态管理分析**：
   - 识别 GetX 状态变量：
     - 查找 `RxBool`、`RxString`、`RxInt` 等响应式变量
     - 理解状态变量的业务含义（如：`isOnline` 表示是否在线）
   - 状态机识别（复杂组件）：
     - 如果存在 `state` 目录或状态管理类（如 `ControlPanelStateManager`）：
       - 识别所有业务状态（如：`offline`、`online`、`busy`）
       - 识别状态转换条件和业务规则
       - 分析状态转换的业务含义
   - 分析状态更新时机：
     - 查找状态变量的赋值位置
     - 理解状态变化触发的业务逻辑

4. **业务依赖分析**：
   - 识别依赖的其他组件或服务：
     - 查找 `Lomo.get` 或 `Lomo.find` 获取的其他组件
     - 理解组件间的业务关系（如：依赖订单组件获取订单状态）
   - 识别原生能力调用：
     - 查找 `UniNative` 或 `UniFlutter` 调用
     - 理解原生能力在业务中的作用（如：调用原生出车接口）

**输出**：
- 业务功能列表（用业务语言描述，非技术实现）
- 业务流程描述（关键业务步骤和状态变化）
- 事件监听列表（事件名和业务目的）
- 状态管理信息（状态变量和状态机）
- 业务依赖关系（依赖的组件和服务）

#### 步骤 4: 分析 `view` 文件 (UI 交互与结构)

**目标**：分析组件的 UI 实现和用户交互。

**执行方法**：
1. **用户操作分析（控制外部）**：
   - 使用 `grep` 搜索：`onTap`、`onPressed`、`onChanged` 等回调函数
   - 分析回调中的业务行为：
     - 外部组件调用（`Lomo.get<...CompImpl>()` 或 `Lomo.find<...CompImpl>()`）
     - 原生通道调用（`UniNative` 或 `UniFlutter`）
     - 状态机调用
     - 事件发布（`DEventBus.instance.postEvent` 或 `DEventBus.instance.eventBus.fire`）
   - 记录用户操作触发的业务行为（如：点击出车按钮 -> 调用出车接口）
2. **UI 特性识别**：
   - 搜索 `AnimationController`、`Animation` - 动画
   - 搜索 `Lottie` - Lottie 动画
   - 搜索 `LayoutBuilder` - 响应式布局
   - 搜索 `GetBuilder`、`Obx` - GetX 状态绑定
3. **子模块/视图识别（复杂组件）**：
   - 列出 `view` 目录下的核心视图文件
   - 描述每个视图的业务功能（如 `go_online_button_wrapper_view.dart` 负责出收车动画）
4. **原生通道分析（如果存在 `channel/` 目录）**：
   - 分析 `channel/` 目录下的实现文件
   - 识别原生通道接口和实现（如 `ControlPanelUniFlutterImpl`）
   - 记录通道的业务用途

**输出**：
- 用户操作列表（操作和业务行为）
- UI 特性列表
- 子模块/视图列表（如果存在）
- 原生通道信息（如果存在）

#### 步骤 5: 分析父子组件关系

**目标**：分析组件在组件树中的位置和数据流。

**执行方法**：
1. **寻找父组件**：
   - 使用 `codebase_search` 搜索：`Lomo.put<...CompImpl>({component_name})`
   - 或在 `ListView.builder` 中搜索创建该组件实例的地方
   - 记录父组件名称和位置
2. **寻找子组件**：
   - 在当前组件的 `view` 文件中，搜索 `Lomo.put` 或直接实例化方式创建的其他组件
   - 如果是容器类组件（如 `home_bottom_drawer_component`），分析数据分发逻辑：
     - 查找根据 `type` 字段动态加载的子组件
     - 记录所有子组件的名称和类型
3. **数据交互分析**：
   - **父 -> 子**：
     - 检查父组件是否通过 `updateData(data)` 或类似方法向子组件传递数据
     - 记录传递的数据模型和业务含义
   - **子 -> 父**：
     - 检查子组件是否通过发布事件（`DEventBus.instance.postEvent`）通知父组件
     - 或通过回调函数通知父组件
     - 记录事件名或回调方法及其业务含义

**输出**：
- 父组件信息（如果存在）
- 子组件列表（如果存在）
- 数据流描述（父->子、子->父）

### Phase 2: 文档生成与输出 (Generation Steps)

根据 Phase 1 分析所得的信息，严格按照以下结构生成 Markdown 内容。

**输出处理**：
- **如果 `output_mode=console`**：直接将生成的 Markdown 内容输出到对话中
- **如果 `output_mode=file`**：
  - 使用 `write` 或 `search_replace` 工具将内容写入或更新到 `target_markdown_path` 文件
  - 如果指定了 `target_header_name`，更新对应章节
  - 如果未指定章节标题，追加到文件末尾
  - 完成后告知用户文件路径

#### 文档模板结构

```markdown
{{target_header_name}}

##### 概述 (针对复杂组件)

(如果组件逻辑复杂，在此处添加一段1-3句话的概述，说明其核心职责和架构特点，例如是否为状态机。)

##### 接口

- **接口名**: {{从repo分析出的接口名，或注明"无"}}

- **关键入参**:

    - `{{key}}`: ({{value的简要说明}})

- **调用repo**: `{{Repo类名}}`


##### 核心子模块与视图 (针对复杂组件)

- **`{{Controller/ViewModel/State Name}}`**: (简要描述其职责)

- **`{{View Name}}`**: (简要描述其功能)

##### 功能点

- **核心功能**:

    - **功能点1：[功能名称]**（用业务语言描述具体的核心功能点，如"出车功能"、"收车功能"、"状态查询"等）
      - **实现逻辑**：精确说明该功能的代码实现
        - 核心类/方法：`ClassName.methodName()` 做了什么
        - 关键字段：涉及哪些字段（`fieldName1`, `fieldName2`）
        - 原生调用：调用了哪些 `uniNative.xxx()` 或 `UniFlutter.xxx()`
        - 数据链路：数据从哪里来 → 如何处理 → 传递到哪里
    
    - **功能点2：[功能名称]**
      - **实现逻辑**：...（每个功能点都必须紧跟其具体实现细节）

##### 父子组件数据交互 (可选)

(如果存在明确的父子关系，则添加此章节)

- **数据流**: 父组件 `{{ParentComponent}}` 通过 `{{method}}` 方法，将 `{{DataModel}}` 数据传递给 `{{ComponentName}}`。

- **事件流**: 子组件 `{{ComponentName}}` 通过发布 `{{EventName}}` 事件来通知父组件。

##### 与外部组件(Component)的交互

| 交互方向 | 外部组件 (Component) / 原生通道 | 交互方式 | 目的 |
| :--- | :--- | :--- | :--- |
| 控制外部 | `{{目标Component/UniNative}}` | 调用 `{{方法或状态机}}` | {{目的}} |
| 受外部控制 | `{{来源Component/UniNative}}` | 监听 `{{事件名}}` 或由原生调用 | {{目的}} |
| 提供数据 | `{{目标Component}}` | 调用 `{{comp暴露的方法}}` | {{目的}} |
```

#### 文档更新策略

1. **读取目标文档**：
   - 使用 `read_file` 读取 `target_markdown_path` 文件（如果存在）
   - 如果文件不存在，需要先创建文件（询问用户或使用默认结构）

2. **定位章节**：
   - 在文档中搜索 `target_header_name` 章节
   - 如果章节不存在，在文档末尾添加新章节
   - 如果章节已存在，准备替换内容

3. **生成内容**：
   - 根据 Phase 1 的分析结果，填充文档模板
   - 确保所有字段都有值（如果没有相关信息，使用"无"或"暂无"）

4. **更新文档**：
   - 使用 `search_replace` 工具更新指定章节
   - 如果章节不存在，使用 `search_replace` 在文档末尾追加
   - 保持文档其他部分不变

## 使用指南

### 基本使用示例

#### 示例 1: 直接输出到对话（推荐）

```text
请分析 go_online_button_component 组件（出车区域），直接输出分析结果
```

参数解析：
- `component_name`: `go_online_button_component`
- `component_chinese_name`: `出车区域`
- `output_mode`: `console`（默认）

#### 示例 2: 生成文档到当前目录

```text
请分析 go_online_button_component 组件（出车区域），生成文档到当前目录
```

参数解析：
- `component_name`: `go_online_button_component`
- `component_chinese_name`: `出车区域`
- `output_mode`: `file`
- 文件名自动生成为：`go_online_button_component_组件文档.md`

#### 示例 3: 生成文档到指定路径并更新章节

```text
请分析该组件，生成文档到 /path/to/document.md 的 ### 5. 出车区域 go_online_button_component 章节
组件名: go_online_button_component
中文名: 出车区域
```

参数解析：
- `component_name`: `go_online_button_component`
- `component_chinese_name`: `出车区域`
- `output_mode`: `file`（根据文件路径自动识别）
- `target_markdown_path`: `/path/to/document.md`
- `target_header_name`: `### 5. 出车区域 go_online_button_component`

#### 示例 4: 系统询问输出方式

```text
请分析 go_online_button_component 组件（出车区域）
```

系统会询问：
```
请选择输出方式：
1. 直接输出到对话中（推荐，可即时查看）
2. 生成 Markdown 文档到当前目录（文件名：go_online_button_component_组件文档.md）
3. 生成 Markdown 文档到指定路径（需提供完整路径）
```

#### 示例 5: 使用上下文中的代码

```text
我已经在上下文中提供了 go_online_button_component 的代码文件
请分析该组件，直接输出
```

### 输入参数识别

**识别规则**：
- `component_name`: 查找包含"组件名"、"component_name"、"component" 等关键词，或直接识别蛇形命名格式
- `component_chinese_name`: 查找"中文名"、"名称"等关键词后的文本
- `output_mode`: 
  - 识别"直接输出"、"输出到对话" → `console`
  - 识别"生成文件"、"生成文档"、"保存" → `file`
  - 识别文件路径 → `file`
  - 未明确指定 → 询问用户
- `target_markdown_path`: 查找以 `.md` 结尾的绝对路径
- `target_header_name`: 查找以 `#` 开头的章节标题格式

**默认行为**：
- 如果用户未提供代码库路径，从当前工作目录开始搜索
- 如果组件目录未找到，提示用户并提供搜索建议
- 如果未指定输出方式，默认为 `console`（直接输出）

## 输出规范

### 输出原则

1. 结构化输出：按文档模板结构生成内容
2. 完整性：所有章节都填充，无相关信息时使用"无"或"暂无"
3. 准确性：基于实际代码分析，不猜测或编造信息
4. 业务导向：功能描述使用业务语言，技术术语保持英文

### 输出格式

生成的文档内容应遵循 Markdown 格式规范：
- 使用正确的标题层级（`#####` 用于子章节）
- 列表使用 `-` 标记
- 表格使用标准 Markdown 表格语法
- 代码和类名使用反引号包裹

## 技术细节

### 文件搜索模式

```bash
# 搜索组件目录
glob_file_search: **/*{component_name}*/**/*.dart

# 搜索 API 路径（支持两种格式）
grep: (?:const\s+\w+\s*=\s*|static\s+String\s+repoPath\s*=\s*)['"](.*?)['"]

# 搜索事件监听（支持两种格式）
grep: DEventBus\.instance(?:\.eventBus)?\.on|\.listen\(

# 搜索用户操作
grep: onTap|onPressed|onChanged

# 搜索父子关系
codebase_search: Lomo.put<...CompImpl>({component_name})
```

### 代码分析优先级

1. 首先定位组件目录和核心文件
2. 并行读取所有核心文件内容
3. 依次分析 repo、controller、view 文件
4. 最后分析父子组件关系
5. 汇总所有信息生成文档

## 错误处理

### 常见错误情况

1. **组件目录未找到**：
   - 提示用户检查组件名称是否正确
   - 提供搜索建议（列出相似的目录名）

2. **核心文件缺失**：
   - 如果某些核心文件不存在（如没有 repo 文件），在文档中标注"无"
   - 继续分析其他存在的文件

3. **目标文档路径无效**：
   - 提示用户检查路径是否正确
   - 询问是否创建新文档

4. **章节定位失败**：
   - 如果章节不存在，询问用户是否在文档末尾添加
   - 或提供章节插入位置建议

## 注意事项

1. 非破坏性分析：仅进行代码分析和文档生成，不修改源代码
2. 精确匹配原则：组件名称搜索优先精确匹配，再考虑模糊匹配
3. 上下文优先：如果用户已在上下文中提供代码，优先使用上下文内容
4. 文档更新策略：如果章节已存在，询问用户是替换还是追加内容
5. 业务逻辑优先：重点分析业务功能，而非仅技术实现
6. 复杂组件处理：对于包含状态机的复杂组件，需要深入分析状态转换的业务逻辑


## 执行时todo模版

在分析组件时，按照以下清单逐步执行，并在完成每一步后更新状态：

```
☐ Phase 0: 确认输出方式
   ☐ 检查用户是否明确指定输出方式
   ☐ 如未指定，询问用户选择输出方式
   ☐ 设置 output_mode 参数

☐ Phase 1: 文件定位与代码分析
   ☐ 定位 {component_name} 组件文件
   ☐ 读取组件核心文件内容（comp、impl、view、controller、repo、model 等）
   ☐ 分析 repo 文件获取 API 信息
   ☐ 分析 controller 文件业务逻辑
   ☐ 分析 view 文件 UI 交互
   ☐ 分析父子组件关系

☐ Phase 2: 文档生成与输出
   ☐ 根据模板结构生成 Markdown 内容
   ☐ 如果 output_mode=console：直接输出到对话
   ☐ 如果 output_mode=file：写入或更新到指定文件
   ☐ 告知用户完成情况
```

**使用说明**：
- ☐ 表示待完成
- ☒ 表示已完成
- 在执行过程中，向用户展示当前进度，标记已完成的步骤
- 此清单作为快速参考，详细说明请参考上方"核心工作流程"章节

