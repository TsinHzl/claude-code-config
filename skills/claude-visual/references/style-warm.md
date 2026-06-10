# 概念型范式（warm主题）

适用：Tool Use契约、Agent循环、消息流向、角色分工等"是什么/谁负责什么/流程怎么走"类机制。
参考成品：`053_tool_use/visual_section2.html`

## 整体框架

- 全局背景：`#fdf6ec`（浅奶油色，温暖低饱和）
- 主卡片：`#ffffff`，圆角28px，阴影 `0 30px 80px rgba(120, 70, 20, 0.12)`
- 左侧渐变竖条：8px宽，`linear-gradient(180deg, #ff8a3d 0%, #ffb070 100%)`
- 内容宽度：1280px（比dark稍宽，因为单视图，且要装下二分布局）
- 卡片内padding：`80px 90px 70px`（上稍大、下稍小，留呼吸感）

```css
body {
  font-family: -apple-system, "PingFang SC", "Helvetica Neue", sans-serif;
  background: #fdf6ec;
  min-height: 100vh;
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding: 60px 40px;
  color: #1a1a1a;
}
.stage {
  width: 1280px;
  background: #ffffff;
  border-radius: 28px;
  padding: 80px 90px 70px;
  box-shadow: 0 30px 80px rgba(120, 70, 20, 0.12);
  position: relative;
}
.stage::before {
  content: "";
  position: absolute;
  left: 0; top: 0; bottom: 0;
  width: 8px;
  border-radius: 28px 0 0 28px;
  background: linear-gradient(180deg, #ff8a3d 0%, #ffb070 100%);
}
```

## Hero Quote（顶部一句话概括）

最关键的视觉锚点。结构是 `<黑底白字术语pill> + 中文对仗描述`。

```html
<div class="quote">
  <span class="term">Tool Use</span><span class="colon">：</span><span class="l">模型负责说</span><span class="sep">，</span><span class="r">客户端负责做</span>
</div>
```

```css
.quote {
  text-align: center;
  font-size: 56px;
  font-weight: 800;
  line-height: 1.2;
  letter-spacing: -1px;
  color: #0d0d0d;
  margin-bottom: 70px;
}
.quote .term {
  color: #fff;
  background: #1a1a1a;
  font-family: "JetBrains Mono", "SF Mono", monospace;
  font-size: 46px;
  letter-spacing: -1px;
  padding: 6px 20px;
  border-radius: 14px;
  display: inline-block;
  vertical-align: 6px;
  margin-right: 10px;
}
.quote .colon { color: #c8b8a8; font-weight: 600; margin: 0 10px 0 0; }
.quote .l { color: #c75a1f; }   /* 左角色色 */
.quote .r { color: #2c5d8c; }   /* 右角色色 */
.quote .sep { color: #c8b8a8; font-weight: 600; margin: 0 14px; }
```

**关键**：
- 术语 pill 字号比正文略小（46 vs 56）保持视觉层级
- 左右两边的核心动词用各自角色颜色（橙 vs 蓝）
- 分隔符 `:` 和 `,` 用淡色 `#c8b8a8`，让重点字突出
- **不要副标题**（用户明确反对过 "The model never executes anything on its own."— Anthropic Tool Use 文档 这种装饰）

## 二分对仗布局

```html
<div class="split">
  <div class="actor left">…左角色卡…</div>
  <div class="protocol">…中间协议箭头…</div>
  <div class="actor right">…右角色卡…</div>
</div>
```

```css
.split {
  display: grid;
  grid-template-columns: 1fr 220px 1fr;
  gap: 24px;
  align-items: stretch;
}
```

中间协议区固定220px，左右用 `1fr` 自动等分。

## 角色卡（左右对称）

```css
.actor {
  background: #fbf4ea;
  border: 2px solid #f1e3d0;
  border-radius: 18px;
  padding: 32px 30px;
  position: relative;
}
.actor.left  { background: #fff4e8; border-color: #ffd9b3; }  /* 暖橙系 */
.actor.right { background: #f1f6fb; border-color: #cfe0f0; }  /* 冷蓝系 */
```

**关键**：左右用色温区分（暖vs冷），不是用同色不同深度——同色不同深度观众难分辨。

### 角色标题

```html
<div class="actor-title">
  <span class="actor-name l">大模型</span>
  <span class="actor-tag">Claude / LLM</span>
</div>
<div class="actor-sub">只会"说话"</div>
```

```css
.actor-name { font-size: 30px; font-weight: 800; letter-spacing: -0.3px; }
.actor-name.l { color: #c75a1f; }
.actor-name.r { color: #2c5d8c; }
.actor-tag {
  font-size: 14px;
  background: rgba(0,0,0,0.05);
  padding: 3px 10px;
  border-radius: 6px;
  color: #555;
  font-family: "JetBrains Mono", "SF Mono", monospace;
}
.actor-sub { font-size: 16px; color: #98886e; margin-bottom: 22px; }
```

### 检查项列表

```html
<ul class="items">
  <li><span class="check">✓</span><span>决定调哪个工具</span></li>
  <li><span class="check">✓</span><span>决定参数怎么填</span></li>
  <li><span class="check">✓</span><span>读懂结果继续说</span></li>
</ul>
```

```css
ul.items { list-style: none; padding: 0; }
ul.items li {
  font-size: 19px;
  line-height: 1.5;
  padding: 6px 0;
  display: flex;
  align-items: flex-start;
  gap: 12px;
}
.check { color: #2d8f5a; font-weight: 800; font-size: 20px; min-width: 18px; }
.cross { color: #c14d3a; font-weight: 800; font-size: 20px; min-width: 18px; }
```

**关键**：左右两栏的 `<li>` 数量必须相等（如各3条），字数大致对仗。这是最重要的视觉对称。

## 中间协议区（双向箭头）

```html
<div class="protocol">
  <span class="pill from-l">tool_use →</span>
  <svg class="arrow-svg" viewBox="0 0 180 80">
    <defs>
      <marker id="arrR" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto">
        <path d="M0,0 L10,5 L0,10 Z" fill="#c75a1f"/>
      </marker>
      <marker id="arrL" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto">
        <path d="M0,0 L10,5 L0,10 Z" fill="#2c5d8c"/>
      </marker>
    </defs>
    <line x1="20" y1="22" x2="160" y2="22" stroke="#c75a1f" stroke-width="3" marker-end="url(#arrR)"/>
    <line x1="160" y1="58" x2="20" y2="58" stroke="#2c5d8c" stroke-width="3" marker-end="url(#arrL)"/>
  </svg>
  <span class="pill from-r">← tool_result</span>
</div>
```

```css
.protocol {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 10px;
}
.pill {
  font-family: "JetBrains Mono", "SF Mono", monospace;
  font-size: 14px;
  font-weight: 600;
  color: #fff;
  background: #1a1a1a;
  padding: 8px 16px;
  border-radius: 999px;
  letter-spacing: 0.3px;
  white-space: nowrap;
}
.pill.from-l { background: #c75a1f; }
.pill.from-r { background: #2c5d8c; }
.arrow-svg { width: 180px; height: 80px; }
```

**关键**：
- 上行（左→右）用左角色色（橙），下行（右→左）用右角色色（蓝）
- 协议名 pill 跟箭头同色，强化"这条线属于谁"
- 箭头 stroke-width 3 在压缩录屏后仍清晰

## 配色总表

| 用途 | 色值 |
|---|---|
| 背景奶油 | `#fdf6ec` |
| 卡片白 | `#ffffff` |
| 左角色 主色（橙） | `#c75a1f` |
| 左角色 卡片背景 | `#fff4e8` |
| 左角色 卡片边框 | `#ffd9b3` |
| 右角色 主色（蓝） | `#2c5d8c` |
| 右角色 卡片背景 | `#f1f6fb` |
| 右角色 卡片边框 | `#cfe0f0` |
| 渐变竖条 | `#ff8a3d → #ffb070` |
| 黑色 pill / 强调 | `#1a1a1a` |
| 正向 check | `#2d8f5a` |
| 反向 cross | `#c14d3a` |
| 次要文字 | `#98886e`（暖灰） |
| 分隔符灰 | `#c8b8a8` |

## 留白经验值

- 卡片到外边缘：`60px`（上下有时是80px，左右取宽度自适应）
- Hero quote 到下方布局：`margin-bottom: 70px`
- 角色卡内padding：`32px 30px`
- 列表项行间：`padding: 6px 0`

**注意**：用户对留白极敏感。遇到"留白太多/太少"反馈时，先用playwright截图，对照现有成品的边距值调整。`60px` 是user在反复迭代后落定的"白色框上面到地址栏边距"。

## 录屏宽度建议

宽度1280px在大屏录屏后还能zoom展示局部。如果担心整体太宽不能整屏录，可以缩到1080-1100px——但所有内部padding和font-size要按比例缩。

**user已经明确说过**："这张图能不能做的相对窄一点,我想录屏的时候可以zoom"。所以宁可窄一点也不要超过1280px。

## 反模式（概念型专属）

- ❌ 左右两栏内容数量不对称（一边3条一边5条） → 视觉失衡
- ❌ 用同色不同深度区分左右角色 → 录屏压缩后看不出差别
- ❌ 把箭头和pill用同色（都是黑色） → 失去"这条线属于哪个角色"的信息
- ❌ 在底部加"模型说+客户端做=Tool Use"这种重复总结 → 顶部Hero已经讲了，不要重复
- ❌ 加副标题/装饰引言 → 用户明确反对过
- ❌ 蓝色饱和过高的箭头 → 用户反馈"蓝色箭头有点怪"，用 `#2c5d8c` 这种偏深的稳重蓝
