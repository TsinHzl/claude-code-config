---
name: text2mermaid
description: 将文本描述转换为Mermaid图表（流程图或时序图）。当用户提供流程简述、需要生成流程图、时序图、或提到"流程图"、"时序图"、"mermaid"、"sequence"时使用。
---

# 文本转Mermaid图表生成器

## 功能说明

本 Skill 支持将文本描述自动转换为两种类型的 Mermaid 图表：

1. **流程图（Flowchart）**：将缩进格式的流程简述转换为 Mermaid 流程图
2. **时序图（Sequence Diagram）**：将业务链路描述转换为 Mermaid 时序图

## 图表类型识别

在开始转换之前，必须首先识别用户想要生成的图表类型。

### 识别流程图的关键词和特征

**明确关键词**：
- "流程图"、"flowchart"、"流程简述"、"流程描述"
- 用户明确提到要生成流程图

**格式特征**：
- 输入包含缩进格式的文本（使用空格或制表符表示层级）
- 文本描述的是步骤流程，而非交互过程

**示例输入**：
```
应用启动 
    判断当前token是否有效
        跳转首页
```

### 识别时序图的关键词和特征

**明确关键词**：
- "时序图"、"sequence"、"交互链路"、"动作步骤"、"参与者"、"实体"
- 用户明确提到要生成时序图
- 包含"发生场景"、"前置条件"、"交互链路"等结构化描述

**格式特征**：
- 输入包含多个实体/参与者
- 描述的是实体之间的交互、通信或消息传递
- 包含时间顺序的动作序列

**示例输入**：
```
发生场景：...
链路：
1. app冷启动
2. 发送接口请求
...
```

### 识别策略

1. **优先检查明确关键词**：如果用户明确提到"时序图"或"流程图"，直接使用对应类型
2. **检查格式特征**：根据输入格式判断（缩进格式→流程图，交互描述→时序图）
3. **如果无法确定**：询问用户或根据上下文推断，优先使用流程图（向后兼容）

## 转换流程

### 流程图转换

当识别为流程图时：

1. 读取 [流程图转换规则](reference/flowchart.md) 了解详细规则
2. 按照规则进行转换：
   - 解析缩进层级结构
   - 识别节点类型
   - 生成 Mermaid 流程图代码
3. 应用通用语法规则（见下方）

### 时序图转换

当识别为时序图时：

1. 读取 [时序图转换规则](reference/sequence.md) 了解详细规则
2. 按照规则进行转换：
   - 识别参与实体（Participants）
   - 分析动作链路
   - 区分自引用箭头和标准箭头
   - 生成 Mermaid 时序图代码
3. 应用通用语法规则（见下方）

## Mermaid语法规则（必须严格遵守）

以下规则适用于所有类型的 Mermaid 图表。

### 规则1（MERMAID_SYNTAX_001）：强制为所有文本内容添加双引号

**核心指令**：在生成任何 Mermaid 图表代码时，必须为所有用户可见的文本内容（包括节点、子图标题、边标签、注释、参与者别名等）强制添加双引号 ("") 进行包裹。无论该文本内容当前是否包含空格或特殊字符，都应无差别地应用此规则。

**正确示例**：
- 节点文本：`A["Node with spaces"]` ✅
- 判断节点：`B{"Decision Point"}` ✅
- 边标签：`A -- "label text" --> B` ✅
- 子图标题：`subgraph "My Subgraph Title"` ✅
- 参与者别名：`participant APP as "APP(骑手端)"` ✅
- 备注：`Note over APP: "说明文字"` ✅

**错误示例**：
- `A[Node with spaces]` ❌
- `B{Decision Point}` ❌
- `A -- label text --> B` ❌
- `subgraph My Subgraph Title` ❌
- `participant APP as APP(骑手端)` ❌

### 规则2（MERMAID_SYNTAX_003）：禁止在Mermaid文本元素中使用Markdown语法

**核心指令**：当生成 Mermaid 图表代码时，禁止在图表文本元素（节点、标签、标题、备注等）中包含任何 Markdown 语法。反引号的使用是严格禁止的。

**正确示例**：
- `A["Run command uv run"]` ✅
- `subgraph "Project: weather"` ✅
- `A -- "read .python-version" --> B` ✅
- `Note over APP: "状态:offline"` ✅

**错误示例**：
- `A["Run command \`uv run\`"]` ❌（包含反引号）
- `subgraph "Project: \`weather\`"` ❌（包含反引号）
- `A["**Bold text**"]` ❌（包含Markdown格式）
- `Note over APP: "状态:\`offline\`"` ❌（包含反引号）

### 规则3（MERMAID_SYNTAX_004）：列表标记后不能有空格

**核心指令**：在 Mermaid 文本元素中使用列表样式标记（如 1., A., -, *）时，标记后不能有空格，否则会导致渲染失败。

**正确示例**：
- `A["1.Do this"]` ✅
- `A["-Item one"]` ✅
- `A -- "A.Then do that" --> B` ✅
- `Note over APP: "1.步骤一"` ✅

**错误示例**：
- `A["1. Do this"]` ❌（标记后有空格）
- `A["- Item one"]` ❌（标记后有空格）
- `A -- "A. Then do that" --> B` ❌（标记后有空格）
- `Note over APP: "1. 步骤一"` ❌（标记后有空格）

## 转换步骤

### 通用步骤

1. **识别图表类型**：根据关键词和格式特征判断是流程图还是时序图
2. **读取对应规则文档**：
   - 流程图：参考 [reference/flowchart.md](reference/flowchart.md)
   - 时序图：参考 [reference/sequence.md](reference/sequence.md)
3. **解析输入**：理解用户提供的文本描述
4. **生成Mermaid代码**：按照对应类型的规则生成代码
5. **语法检查**：确保所有文本都用双引号包裹，没有Markdown语法，列表标记后无空格

## 参考文档

- **流程图详细规则**：参见 [reference/flowchart.md](reference/flowchart.md)
- **时序图详细规则**：参见 [reference/sequence.md](reference/sequence.md)

## 注意事项

1. **图表类型识别**：必须首先准确识别用户想要生成的图表类型
2. **语法检查**：在生成代码前，必须检查所有文本元素是否符合三条语法规则
3. **文本清理**：移除Markdown语法，处理列表标记后的空格
4. **双引号包裹**：所有文本内容必须用双引号包裹，无论是否包含空格
5. **渐进式披露**：详细规则在 reference 文档中，只在需要时读取
