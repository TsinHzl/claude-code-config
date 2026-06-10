# 数据型范式（dark主题）

适用：缓存命中率、token分布、调用次数、上下文增长、累积/滚雪球类机制。
参考成品：`052_claude_cache/prefix_cache_demo.html`

## 整体框架

- 全局背景：`#0f0f0f`
- 文字主色：`#e0e0e0`，强调白：`#fff`
- 卡片背景：`#1a1a1a`，边框：`1px solid #2a2a2a`
- 圆角：常规8-10px
- **内容宽度：`.view { width: 1240-1280px }`**（多 tab + 累积 bar + 末端 bp label 居中需要这个宽度；旧设的 900px 不够）
- **图里所有字 ≥ 14px**（参考 SKILL.md 视觉硬规则 9）

```css
body {
  font-family: -apple-system, "Helvetica Neue", sans-serif;
  background: #0f0f0f;
  color: #e0e0e0;
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 48px 32px;
}
```

## 标题区

只放 h1 主标题，**不要副标题**（实战发现副标题既不传达信息也容易因为色弱跟正文白混淆，删掉更利落）。

```html
<h1>主标题</h1>
```

```css
h1 { font-size: 30px; font-weight: 600; color: #fff; margin-bottom: 32px; }
```

## Tab导航（放在标题下方）

```css
.turns { display: flex; gap: 16px; margin-bottom: 32px; }
.turn-btn {
  padding: 12px 28px;
  border: 2px solid #333;
  border-radius: 10px;
  background: transparent;
  color: #aaa;
  font-size: 15px;
  cursor: pointer;
  transition: all 0.3s;
}
.turn-btn:hover { border-color: #555; color: #fff; }
.turn-btn.active {
  border-color: #059669;
  color: #fff;
  background: rgba(5, 150, 105, 0.1);
}
```

JS 切换用一个 `showView(viewKey)` 函数，根据 view 渲染 bar 内容并 toggle `.active` class。

## 横向条形图（核心视觉）

```css
.section-label {
  font-size: 15px;
  color: #d0d0d0;
  font-weight: 600;
  margin-bottom: 14px;
}
.prefix-bar {
  display: flex;
  height: 64px;       /* 旧 56px 装不下 14px 中文+副字 */
  border-radius: 8px;
  overflow: visible;  /* 让 bp dot/label 能溢出到 bar 上方 */
}
.seg {
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 14px;     /* 底线 ≥14px，旧 12px 录屏看不清 */
  font-weight: 500;
  color: #fff;
  position: relative;
  height: 64px;
}
.seg .inner {
  padding: 0 10px;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  height: 100%;
  line-height: 1.25;
  overflow: hidden;     /* 内文溢出在 inner 内裁，不裁外面的 bp */
  white-space: nowrap;
  width: 100%;
}
.seg .token-count {
  font-size: 14px;
  opacity: 0.7;
  margin-top: 3px;
  font-weight: 400;
}
```

**关键**：所有 `.seg .inner` 用相同 HTML 结构（`<div class="inner"><div>主标</div><div class="token-count">副数</div></div>`），保证baseline对齐。

## Breakpoint dot + label（端点标记）

```css
.bp {
  position: absolute;
  right: 0; top: -4px; bottom: -4px;
  width: 3px;
  z-index: 10;
}
.bp::after {  /* dot 圆头 */
  content: '';
  position: absolute;
  top: -8px; right: -7px;
  width: 17px; height: 17px;
  border-radius: 50%;
  background: inherit;
}
.bp.bp-anchor { background: #38bdf8; box-shadow: 0 0 4px rgba(56,189,248,0.5); }  /* 静/不动，天青蓝 */
.bp.bp-cursor { background: #ff8a3d; box-shadow: 0 0 6px rgba(255,138,61,0.6); }  /* 动/移动，暖橙 */

.bp .lbl {
  position: absolute;
  top: -40px;
  left: 50%; transform: translateX(-50%);  /* 默认居中在 dot 上方 */
  font-size: 14px;
  background: #1a1a1a;
  border: 1px solid #2a2a2a;
  padding: 4px 10px;
  border-radius: 5px;
  font-family: "SF Mono", Menlo, monospace;
  white-space: nowrap;
}
.bp.bp-anchor .lbl { color: #38bdf8; border-color: #38bdf8; }
.bp.bp-cursor .lbl { color: #ff8a3d; border-color: #ff8a3d; }
```

**lblLeft 选项**：bar 末端的 dot label 居中向右延伸时会超出 view 边界。在 `seg()` 函数加 `lblLeft` 选项让 label 反向偏移到 dot 左侧（bar 内侧）：

```js
function seg(cls, w, label, sub, opts = {}) {
  const lblStyle = opts.lblLeft ? ' style="left:auto;right:0;transform:translateX(0);"' : '';
  const bp = opts.bp
    ? `<div class="bp ${opts.bp}">${opts.bpLabel ? `<span class="lbl"${lblStyle}>${opts.bpLabel}</span>` : ''}</div>`
    : '';
  // ...
}
```

bar 容器需要 `padding-top: 52px` 给 label 留出空间（label 在 dot 上方约 40px）。

## 颜色语义（一旦定下不要换）

**前缀结构 segment 色**（一组哑色）：
- tools：`#2d4a3e`（深绿灰）
- system：`#3a3d5c`（深紫灰）
- 用户注入上下文：`#4a3a2e`（深棕）
- 用户输入：`#1a3a5c`（深蓝）
- assistant 回复：`#3a2d4a`（深紫）

**Cache 状态色**（一组高饱和）：
- `cache_creation`（写入，橙）：`#d97706`
- `cache_read`（命中，绿）：`#059669`
- `input_tokens`（普通输入，蓝）：`#2563eb`

如果一个色块要从"普通"切到"cache状态"，用 `!important` 覆盖背景：
```css
.cache-creation { background: #d97706 !important; }
.cache-read     { background: #059669 !important; }
.cache-input    { background: #2563eb !important; }
```

## 长度策略：传达累积

固定每个内容段的像素宽度，使相同部分跨视图严格相等，新增部分追加在右侧：

```js
// 14px 字号下的经验 W 表（055_claude_cache2 实测过）
// 每个 segment 必须装下 14px 中文 + 14px monospace 主字 + padding 20px
const W = {
  tools: 210,         // "tools" + "29 个工具"
  sys0: 80,           // "sys[0]"
  sys1: 120,          // "sys[1]" + "身份提示词"
  sys2: 180,          // "sys[2]" + "行为准则"
  inject: 130,        // ".../CLAUDE.md" + "注入上下文"
  userHello: 130,     // '"hello"' — 注意：相邻 bp 间距 < 95px label 必重叠，所以 hello 段不能小
  userFine: 90,       // '"fine"'
  userThanks: 130,    // '"thank you"'
  userContinue: 100,  // '"继续"'
  asst: 100,          // 'asst 回复'
  storm: 18,          // 工具风暴小 block（无字）
};
// 消息1: tools + system + inject + userHello
// 消息2: + asst + userFine（继续向右延伸）
// 消息3: + asst + userThanks
```

bar 容器用 `width: fit-content`，让内容自然撑开。

**关于相邻 bp 间距**：bp dot label 居中（约 95-100px 宽），如果两个相邻 bp 之间 segment 宽度 < 100px，label 会水平重叠。要么扩大 segment 宽度，要么给末端 bp 用 `lblLeft` 反向偏移。

## 对比表格

```css
.compare-table {
  width: 100%;
  border-collapse: separate;
  border-spacing: 0;
  background: #1a1a1a;
  border: 1px solid #2a2a2a;
  border-radius: 10px;
  overflow: hidden;
  font-family: "SF Mono", Menlo, monospace;
}
.compare-table th, .compare-table td {
  padding: 14px 20px;
  text-align: center;
  border-bottom: 1px solid #2a2a2a;
}
.compare-table tbody tr:last-child td { border-bottom: none; }
.compare-table th { background: #222; color: #ddd; font-weight: 600; font-size: 14px; }
.compare-table td.metric { text-align: left; color: #888; font-size: 13px; }
.compare-table td.c-green  { color: #10b981; font-weight: 600; }
.compare-table td.c-orange { color: #f59e0b; font-weight: 600; }
.compare-table td.c-blue   { color: #3b82f6; font-weight: 600; }
```

**列顺序、行命名**：当一个HTML里有多张表（如"对比表" + "成本表"），行的命名和顺序必须对齐，让观众扫的时候能横向匹配。

## 公式盒

```html
<div class="formula-box">
  <div class="formula-title">滚雪球公式</div>
  <div class="formula-expr">cache_read[N+1] = cache_read[N] + cache_creation[N]</div>
  <div class="formula-example">消息 1 → 消息 2: 0 + 48,654 = 48,654</div>
</div>
```

```css
.formula-box {
  background: #1a1a1a;
  border: 1px solid #2a2a2a;
  border-radius: 10px;
  padding: 24px 28px;
  text-align: center;
}
.formula-title {
  font-size: 12px;
  color: #888;
  text-transform: uppercase;
  letter-spacing: 1.5px;
  margin-bottom: 14px;
}
.formula-expr {
  font-size: 18px;
  color: #fff;
  font-family: "SF Mono", Menlo, monospace;
  margin-bottom: 14px;
}
```

## 价格倍率卡片（成本影响tab常用）

横排小卡片，每张写一个倍率：

```css
.rates { display: flex; gap: 14px; margin-bottom: 32px; }
.rate-card {
  flex: 1;
  background: #1a1a1a;
  border: 1px solid #2a2a2a;
  border-radius: 10px;
  padding: 18px 16px;
  text-align: center;
}
.rate-card.highlight {
  border-color: #10b981;
  background: rgba(16, 185, 129, 0.08);
}
.rate-label { font-size: 12px; color: #888; margin-bottom: 10px; }
.rate-value {
  font-size: 28px; color: #fff; font-weight: 600;
  font-family: "SF Mono", Menlo, monospace;
}
```

最便宜/最关键的那张用 `highlight` 类绿色突出。

## tab切换 JS 模式

```js
function showView(view) {
  setActive(view);
  if (view === 'structure') showStructure();
  else if (view === 'compare') showCompare();
  else if (view === 'cost') showCost();
  else showTurn(view);  // turn1/turn2/turn3
}

function setActive(view) {
  document.querySelectorAll('.turn-btn').forEach((btn, i) => {
    const views = ['structure','turn1','turn2','turn3','compare','cost'];
    btn.classList.toggle('active', views[i] === view);
  });
}
```

每个 show 函数控制：哪些 section 显示、bar 内容、formula 文本。

## 反模式（数据型专属）

- ❌ 把所有数据都堆在一页 → 用tab切分认知负担
- ❌ tab数量超过6个 → 录屏切起来太多，观众也记不住
- ❌ 用 `transform: scale` 缩放 bar → 字会糊，直接调宽度
- ❌ 用百分比宽度做"累积感"演示 → 应该用绝对像素，让相同部分严格等长
- ❌ 颜色饱和度不分层级（segment色和cache色一样亮）→ 哑色给"结构"，亮色给"状态"
