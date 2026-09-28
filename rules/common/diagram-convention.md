---
name: Diagram Convention
description: Diagrams default to standalone SVG files + relative image refs; inline SVG only for viewers that render inline SVG; Mermaid as fallback with render pipeline
inclusion: always
---

# 文档画图规范

## 渲染环境适配（写图前必须先判断）

**内嵌裸 SVG 并非在所有查看器中都能渲染。** 实测 DSH Web GUI（`@deepseek-ai/dsh` 前端 bundle，v0.1.2-rc.1）：

- Markdown 中的裸 HTML/SVG 块被解析为 `html` 节点后按纯文本返回（React 转义显示，不解析为 DOM）
- `![img](...)` 图片节点仅接受绝对 http(s) URL，相对路径与 `data:` URI 均回退为 alt 文字
- 无 Mermaid 支持、无 rehype-raw

### 默认流程（查看器未知或可能为 DSH Web GUI 时，必须走此流程）

1. 图表写为**独立 .svg 文件**，放文档同级 `diagrams/` 目录，按出现顺序编号命名（如 `01-architecture.svg`）；SVG 内容仍遵守下方"SVG 输出规范"
2. 文档中以 `![图1·系统架构](diagrams/01-architecture.svg)` 形式相对引用（图号·标题与编号文件名同源），alt 必须含图号与标题（渲染失败时兜底可读）
3. 文档头部加一句"图表查看方式"说明：预览器内联显示；不支持时直接打开 svg 文件

### 例外：仅当读者查看器明确支持内嵌 SVG 渲染时才内嵌

| 查看器 | 内嵌裸 SVG | 独立文件 + 相对引用 |
|---|---|---|
| VS Code 预览 / Typora | ✅ | ✅ |
| GitHub / GitLab | ❌（sanitize 剥离） | ✅ |
| DSH Web GUI / 渲染行为未知 | ❌（按文本转义） | ⚠️ 引用行可见，图需打开文件查看 |

## 内嵌方式：直接手写 SVG（仅限支持内嵌 SVG 渲染的查看器）

文档中需要图表时，若已确认读者查看器支持内嵌 SVG 渲染（见上表），可直接手写内嵌 SVG，不使用 Mermaid 代码块。

### SVG 输出规范

```xml
<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg"
     style="width:100%;max-width:{W}px;font-family:sans-serif">
  <!-- 内容 -->
</svg>
```

**必须遵守：**
- `viewBox` 设定画布尺寸，`style` 设定响应式宽度
- 字体用 `sans-serif`，中文标签直接写入 `<text>`
- 颜色方案：浅背景 `#fafafa`，主色用语义色（红=警告/耗时，蓝=正常，绿=成功）
- 使用 `<defs>` 定义箭头 marker、渐变等复用元素
- 圆角矩形 `rx="4"` 以上，避免锐角
- 标签字号：标题 12-14px，正文 10-11px，注释 9px
- 所有尺寸基于 viewBox 坐标，不使用 em/rem

### 适用图表类型

| 类型 | SVG 构建方式 |
|------|-------------|
| 时间轴/甘特 | 横向 `<rect>` 条 + 垂直 `<line>` 分隔 + `<text>` 标签 |
| 流程图 | `<rect>`/`<circle>` 节点 + `<path>`/`<line>` 连接 + `marker-end` 箭头 |
| 架构图 | 分层 `<rect>` 容器 + 内部组件块 + 连线 |
| 时序图 | 垂直 lifeline `<line>` + 水平箭头 `<line marker-end>` + `<text>` 消息 |
| 对比图 | 并排 `<rect>` 列 + 颜色区分 |
| 数据图 | `<rect>` 柱状 / `<path>` 折线 / `<circle>` 散点 |

### 布局原则

- 水平优先：阅读方向从左到右
- 垂直分层：上方为事件/触发点，中间为主体，下方为汇总/标注
- 图例放左上或右上角
- 留白：节点间距 ≥ 节点宽度的 30%

## 备选方式：Mermaid + 渲染管道

仅在以下场景使用 Mermaid：
- 用户明确要求 Mermaid 格式
- 图表需要后续文本化编辑（如在 GitHub README 中）
- 图表极度复杂（>30 节点）手写 SVG 不经济

### 渲染命令

```bash
# 单文件
~/.claude/render_mermaid.sh input.mmd output.svg

# 内联代码
~/.claude/render_mermaid.sh --inline "graph TD; A-->B" /tmp/out.svg

# 批量
~/.claude/render_mermaid.sh --batch ./diagrams/
```

渲染后默认引用生成的文件路径（遵守上方默认流程）；仅在确认查看器支持内嵌 SVG 渲染时嵌入文档。

## 禁止事项

- ❌ 在 Markdown 文档中只留 ```mermaid 代码块而不渲染
- ❌ 使用外部图片链接引用图表（离线不可用）
- ❌ 用 ASCII art 画图（可读性差）
- ❌ SVG 中嵌入 `<foreignObject>` + HTML（兼容性问题）
- ❌ 在面向 DSH Web GUI 或渲染行为未知的 Markdown 文档中内嵌裸 `<svg>` 块（按纯文本转义，必不渲染；改用独立文件 + 相对引用）
