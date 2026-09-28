---
name: video-analyzer
description: >
  Analyze a video from a streaming URL (YouTube, Bilibili, Twitter/X, Douyin, etc.) and produce
  a progressive educational article saved to ~/Downloads/video-doc/. The article is written by the current
  Claude model after reading the extracted transcript — no external API key needed.
  Use when the user provides a video link and asks to "analyze", "summarize", "transcribe",
  or "report on" its content. Triggers on phrases like "分析这个视频", "帮我看这个视频", "视频内容分析",
  "analyze this video", "summarize the video at URL", "帮我分析这个链接的视频".
compatibility: Requires Python 3.11+ (for faster-whisper), yt-dlp, and ffmpeg. macOS or Linux.
metadata:
  author: local
  version: "2.0"
  tags: "video,transcript,analysis,education,bilibili,youtube"
---

# Video Analyzer

Extracts video data with a Python script, then uses the **current Claude model** to generate
a detailed educational report saved to `~/Downloads/video-doc/`.

## Input

The skill is invoked with a single required argument — the video URL:

```
/video-analyzer <VIDEO_URL> [--cookies-from-browser chrome] [--no-transcribe]
```

- **`VIDEO_URL`** (required): Any yt-dlp-supported URL. Read it directly from the `ARGUMENTS` line at the top of this skill invocation — **do not ask the user to re-enter it**.
- **`--cookies-from-browser chrome`** (optional): Pass to yt-dlp when the video requires login (e.g. Bilibili members-only content).
- **`--no-transcribe`** (optional): Skip the Whisper fallback; use subtitles only.

> If `ARGUMENTS` is empty or contains no URL, ask the user: "请提供视频链接。"

## Workflow

### Step 1 — Check dependencies

```bash
# Prefer python3.11 (faster-whisper install target); fall back to python3
PYTHON=$(python3.11 -c 'import sys; print(sys.executable)' 2>/dev/null \
  || python3 -c 'import sys; print(sys.executable)')
$PYTHON -m pip show yt-dlp > /dev/null 2>&1 || $PYTHON -m pip install yt-dlp
```

### Step 2 — Run the extractor script

Locate the script:

```bash
find ~/.claude/skills ~/.claude/plugins -name "analyze_video.py" 2>/dev/null | head -1
```

Run it — replace `SKILL_DIR` with the path found above and `VIDEO_URL` with the URL from the skill's `ARGUMENTS`:

```bash
$PYTHON "<SKILL_DIR>/scripts/analyze_video.py" "<VIDEO_URL>" \
  [--cookies-from-browser chrome] \
  [--no-transcribe] \
  [--model medium] \
  [--output /tmp/video_extract.json]
```

The script prints `EXTRACT_JSON=<path>` on completion. Read that file.

**Error handling — validation loop:**
1. If the script exits with a non-zero code, read stderr output
2. Common fixes:
   - `ERROR: Login required` → retry with `--cookies-from-browser chrome`
   - `ERROR: Video unavailable` → inform user the video is geo-blocked or deleted
   - `ModuleNotFoundError` → install missing dependency and retry
3. If Whisper OOM → retry with `--model base` (smaller model)
4. Only proceed to Step 3 after `EXTRACT_JSON=` line appears in stdout

### Step 3 — Read the extracted JSON

```bash
# The JSON contains: title, channel, platform, url, upload_date, duration,
# view_count, like_count, description, tags, categories, chapters[], transcript
```

Use the Read tool on the path printed by the script.

### Step 4 — Generate the educational analysis

Using the transcript and metadata from the JSON, write a **progressive educational article**
in Chinese Markdown. **Writing philosophy: act as a skilled teacher, not a reporter.**
Build understanding layer by layer — start with a compelling hook, establish foundations with
analogies, deepen complexity gradually, then deliver advanced insights. Every section must feel
like a natural next step from the previous one. Insert an **inline SVG diagram** wherever a visual
accelerates comprehension faster than prose.

**Diagram rules (inline SVG):**
- All diagrams MUST be written as inline `<svg>` elements directly in the Markdown.
  Do **not** use Mermaid code blocks.
- **Required diagrams:** (1) concept relationship map at §2, (2) argument/process flowchart or
  sequence/timeline at §5, (3) full logic skeleton at §7
- Optional anywhere: flowchart, sequence diagram, timeline — use when a picture beats 300 words
- Keep each diagram focused (5–12 nodes/elements); label connectors with verbs
- After every closing `</svg>`, add an italicized caption: `*▲ [一句话图示说明]*`

**SVG authoring conventions:**
- Every SVG must include `viewBox`, responsive `style`, and `xmlns`:
  ```xml
  <svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg"
       style="width:100%;max-width:{W}px;font-family:sans-serif">
  ```
- Use `<defs>` to define reusable arrow markers:
  ```xml
  <defs>
    <marker id="arrowhead" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
      <path d="M0,0 L8,3 L0,6" fill="#5D6D7E"/>
    </marker>
  </defs>
  ```
- Color palette (apply consistently across all diagrams):
  - Blue `fill:#BDE0FE,stroke:#2980B9` — neutral / core concepts
  - Green `fill:#D5F5E3,stroke:#27AE60` — positive / conclusions / outcomes
  - Red/pink `fill:#FFCCCC,stroke:#CC0000` — problems / costs / risks
  - Amber `fill:#FFF3CD,stroke:#E0A800` — decisions / key claims
  - Background `fill:#FAFAFA` for the outer `<rect>`
- Node shapes: `<rect rx="6">` for concepts; `<polygon>` (diamond) for decision points; `<ellipse>` for inputs/outputs
- Edges: `<line>` or `<path>` with `marker-end="url(#arrowhead)"`; dashed edges use `stroke-dasharray="5,3"`
- Text: `font-size="11"` for labels, `font-size="13" font-weight="bold"` for titles; use `text-anchor="middle"`
- Layout: left-to-right for process flows, top-to-down for hierarchies; minimum 30% spacing between nodes
- Multi-line labels: use multiple `<text>` elements with different `y` offsets (no `<foreignObject>`)
- All SVG content must be self-contained — no external references or embedded HTML

Minimum total length: 3000 Chinese characters. Never truncate or abbreviate sections.

Required sections — follow this order exactly, use `##` for each section heading:

---

**§1 一分钟速览**
用 3–4 句强力 Hook 开篇：直接说出视频最反直觉、最出乎意料或最有价值的核心结论，
让读者产生"我必须继续读"的冲动。不要用平淡的"本视频介绍了……"开头。
末尾用一句话承诺：读完本文你将掌握什么。

**§2 背景铺垫**
在进入主题前，为读者建立 2–4 个必要的基础认知点。每个铺垫用 1–2 句通俗语言说清，
解释为什么它对理解本视频不可缺少。

然后在本节末尾**必须**插入一个 SVG 概念关系图，展示本视频所有核心概念及其相互关系
（以下为格式示例，执行时替换为视频实际内容）：

<svg viewBox="0 0 520 120" xmlns="http://www.w3.org/2000/svg" style="width:100%;max-width:520px;font-family:sans-serif">
  <rect x="0" y="0" width="520" height="120" rx="6" fill="#FAFAFA"/>
  <defs>
    <marker id="arr-s2" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
      <path d="M0,0 L8,3 L0,6" fill="#5D6D7E"/>
    </marker>
  </defs>
  <rect x="30" y="40" width="110" height="40" rx="6" fill="#BDE0FE" stroke="#2980B9" stroke-width="2"/>
  <text x="85" y="65" text-anchor="middle" font-size="12" fill="#1A5276">概念A</text>
  <rect x="205" y="40" width="110" height="40" rx="6" fill="#BDE0FE" stroke="#2980B9" stroke-width="2"/>
  <text x="260" y="65" text-anchor="middle" font-size="12" fill="#1A5276">概念B</text>
  <rect x="380" y="40" width="110" height="40" rx="6" fill="#D5F5E3" stroke="#27AE60" stroke-width="2"/>
  <text x="435" y="65" text-anchor="middle" font-size="12" fill="#1E8449">概念C</text>
  <line x1="140" y1="60" x2="203" y2="60" stroke="#5D6D7E" stroke-width="1.5" marker-end="url(#arr-s2)"/>
  <text x="172" y="52" text-anchor="middle" font-size="9" fill="#7F8C8D">关系</text>
  <line x1="315" y1="60" x2="378" y2="60" stroke="#5D6D7E" stroke-width="1.5" marker-end="url(#arr-s2)"/>
</svg>

*▲ 概念关系图：理解本视频的知识地图*

**§3 问题与挑战**
用"设问-悬念"结构：先提出读者可能遇到过的困惑或现实痛点，再说明视频将如何回应这个挑战。
若涉及流程对比或因果链，插入一个简洁的 inline SVG 图示。

**§4 基础层：核心概念入门**
面向零基础读者。用日常类比或生活场景解释每个关键概念，先类比后定义，绝不堆砌术语。格式：

- **[概念名]**：想象一个你熟悉的场景…… → 在视频中，它具体指的是…… → 理解它的重要性在于……

要求：不少于 3 个概念；每个 ≥ 100 字；类比必须具体、可感知。

**§5 进阶层：核心论点深度解析**
严格按视频逻辑顺序，每个主要段落用 `###` 子标题：

```
### [段落主题]
**核心论点**：……（1–2 句，清晰陈述观点）
**逐步推导**：作者如何一步步建立这个论点，保留完整逻辑链条
**具体证据**：案例 / 数据 / 实验 / 类比（详细还原）
**与基础层的连接**：这个论点如何深化了§4 中的某个概念
```

要求：不少于 3 个子段落；每个 ≥ 200 字。
在最关键的论点处**必须**插入一个 inline SVG 流程图或序列图，可视化该论点的推导过程
（以下为格式示例，执行时替换为视频实际逻辑）：

<svg viewBox="0 0 600 140" xmlns="http://www.w3.org/2000/svg" style="width:100%;max-width:600px;font-family:sans-serif">
  <rect x="0" y="0" width="600" height="140" rx="6" fill="#FAFAFA"/>
  <defs>
    <marker id="arr-s5" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
      <path d="M0,0 L8,3 L0,6" fill="#5D6D7E"/>
    </marker>
  </defs>
  <!-- 前提条件 -->
  <rect x="20" y="50" width="100" height="40" rx="6" fill="#BDE0FE" stroke="#2980B9" stroke-width="2"/>
  <text x="70" y="75" text-anchor="middle" font-size="11" fill="#1A5276">前提条件</text>
  <!-- 关键步骤 -->
  <rect x="160" y="50" width="100" height="40" rx="6" fill="#BDE0FE" stroke="#2980B9" stroke-width="2"/>
  <text x="210" y="75" text-anchor="middle" font-size="11" fill="#1A5276">关键步骤</text>
  <!-- 判断节点 (diamond) -->
  <polygon points="340,70 380,50 420,70 380,90" fill="#FFF3CD" stroke="#E0A800" stroke-width="2"/>
  <text x="380" y="74" text-anchor="middle" font-size="10" fill="#2C3E50">判断节点</text>
  <!-- 结论A -->
  <rect x="470" y="20" width="100" height="36" rx="6" fill="#D5F5E3" stroke="#27AE60" stroke-width="2"/>
  <text x="520" y="43" text-anchor="middle" font-size="11" fill="#1E8449">结论A</text>
  <!-- 结论B -->
  <rect x="470" y="84" width="100" height="36" rx="6" fill="#FFCCCC" stroke="#CC0000" stroke-width="2"/>
  <text x="520" y="107" text-anchor="middle" font-size="11" fill="#CC0000">结论B</text>
  <!-- Edges -->
  <line x1="120" y1="70" x2="158" y2="70" stroke="#5D6D7E" stroke-width="1.5" marker-end="url(#arr-s5)"/>
  <line x1="260" y1="70" x2="338" y2="70" stroke="#5D6D7E" stroke-width="1.5" marker-end="url(#arr-s5)"/>
  <line x1="420" y1="58" x2="468" y2="40" stroke="#5D6D7E" stroke-width="1.5" marker-end="url(#arr-s5)"/>
  <text x="448" y="42" font-size="9" fill="#7F8C8D">是</text>
  <line x1="420" y1="82" x2="468" y2="100" stroke="#5D6D7E" stroke-width="1.5" marker-end="url(#arr-s5)"/>
  <text x="448" y="98" font-size="9" fill="#7F8C8D">否</text>
</svg>

*▲ 推导流程图：[该论点名称] 的逻辑链条*

**§6 深度层：洞察与延伸**
超越视频表面内容，提炼 2–3 个深层洞察：
- 这个结论在更大范围内意味着什么
- 视频没有明说但隐含的重要推论
- 与其他领域知识的意外联系或反直觉含义

**§7 论证结构全景图**
**必须**用 inline SVG 图展示全片的逻辑骨架（核心命题 → 支撑论点 → 结论）
（以下为格式示例，执行时替换为视频实际论证结构）：

<svg viewBox="0 0 400 220" xmlns="http://www.w3.org/2000/svg" style="width:100%;max-width:400px;font-family:sans-serif">
  <rect x="0" y="0" width="400" height="220" rx="6" fill="#FAFAFA"/>
  <defs>
    <marker id="arr-s7" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
      <path d="M0,0 L8,3 L0,6" fill="#5D6D7E"/>
    </marker>
  </defs>
  <!-- 核心命题 -->
  <rect x="140" y="20" width="120" height="40" rx="6" fill="#FFF3CD" stroke="#E0A800" stroke-width="2"/>
  <text x="200" y="45" text-anchor="middle" font-size="12" font-weight="bold" fill="#2C3E50">核心命题</text>
  <!-- 论点A -->
  <rect x="50" y="100" width="110" height="40" rx="6" fill="#BDE0FE" stroke="#2980B9" stroke-width="2"/>
  <text x="105" y="125" text-anchor="middle" font-size="11" fill="#1A5276">论点A</text>
  <!-- 论点B -->
  <rect x="240" y="100" width="110" height="40" rx="6" fill="#BDE0FE" stroke="#2980B9" stroke-width="2"/>
  <text x="295" y="125" text-anchor="middle" font-size="11" fill="#1A5276">论点B</text>
  <!-- 结论 -->
  <rect x="140" y="170" width="120" height="40" rx="6" fill="#D5F5E3" stroke="#27AE60" stroke-width="2"/>
  <text x="200" y="195" text-anchor="middle" font-size="12" font-weight="bold" fill="#1E8449">结论</text>
  <!-- Edges -->
  <line x1="170" y1="60" x2="120" y2="98" stroke="#5D6D7E" stroke-width="1.5" marker-end="url(#arr-s7)"/>
  <line x1="230" y1="60" x2="280" y2="98" stroke="#5D6D7E" stroke-width="1.5" marker-end="url(#arr-s7)"/>
  <line x1="105" y1="140" x2="165" y2="168" stroke="#5D6D7E" stroke-width="1.5" marker-end="url(#arr-s7)"/>
  <line x1="295" y1="140" x2="235" y2="168" stroke="#5D6D7E" stroke-width="1.5" marker-end="url(#arr-s7)"/>
</svg>

*▲ 论证结构图：全片逻辑骨架一览*

然后用 2–3 句文字评价论证的严密程度（哪里最有力、哪里存在逻辑跳跃）。

**§8 关键数据与事实**
用表格列出视频引用的所有具体数据、统计数字、研究结论、历史事件：

| 数据 / 事实 | 来源（如有） | 视频中的作用 |
|------------|-------------|-------------|

若视频无量化数据，改为列出所有引用的具体事例（不少于 3 条）。

**§9 精华金句摘录**
逐字引用视频中最具价值的 3–8 句话（用引号），每条注明：
- 出现的上下文 / 大概时间节点
- 为什么值得摘录（核心洞察 / 反直觉观点 / 论点锚点）

若字幕缺失，改为提炼 3–5 个最有价值的观点并用引号标注。

**§10 批判性视角**
- ✅ 视频的独到见解与优点（各 ≥ 2 句）
- ⚠️ 可能的局限性或未充分考虑的因素
- 🔄 存在的替代观点或反驳角度
- 📌 信息可能存在的立场偏差（若有）

**§11 你的收获清单**
- 🧠 理解了哪些概念
- 🛠 掌握了哪些方法 / 框架
- 💡 可能改变的认知
- ✅ 可以立即应用的知识点

**§12 继续探索**
3–5 个开放性深度问题（引导进一步思考，非视频已答的问题）。
3–5 个延伸学习方向（书籍 / 领域 / 关键词 / 课程），说明与本视频内容的具体关联。

### Step 5 — Write the report to ~/Downloads/video-doc/

First ensure the output directory exists:

```bash
mkdir -p ~/Downloads/video-doc
```

Then use the Write tool to save the full Markdown file:

```
~/Downloads/video-doc/video-analysis-<safe-title>.md
```

Report structure:

```markdown
# 视频内容分析报告：<标题>

> **注：** 本文档由 **<current-model>** 模型自动生成。

---

## 基本信息

| 字段 | 值 |
|------|-----|
| 标题 | ... |
| 频道 / 作者 | ... |
| 平台 | ... |
| 上传日期 | ... |
| 视频时长 | ... |
| 播放量 | ... |
| 点赞数 | ... |
| 视频链接 | ... |
| 内容类型 | （推断：教程 / 演讲 / 评测 / 纪录片 / 访谈 / Vlog / ...） |
| 内容深度 | （推断：入门 / 进阶 / 专业） |
| 目标受众 | （推断） |
| 转录来源 | （subtitles / whisper / none） |
| Whisper 模型 | （medium / base / large / N/A） |

## 视频简介

（原始 description，保留完整）

## 章节目录

（若有 chapters，逐一列出时间戳 + 标题；无则省略本节）

## 标签 & 分类

（tags 和 categories，逗号分隔）

---

## 内容分析

（Step 4 三层教学架构全部 12 节依次写在这里，§1 一分钟速览 → §12 继续探索，每节用 `##` 标题）

```

### Step 6 — Report the output path to the user

Tell the user the exact saved path.

## Options

| Flag | Effect |
|------|--------|
| `--cookies-from-browser chrome` | Read Chrome cookies (needed for Bilibili AI subtitles) |
| `--no-transcribe` | Skip Whisper fallback, subtitles only |
| `--model MODEL` | Whisper model size: `tiny` / `base` / `medium` / `large` (default: `medium`) |
| `--output PATH` | Custom JSON output path (default `/tmp/video_extract.json`) |

## Subtitle extraction priority

1. Embedded / manual subtitles (`--write-subs`)
2. Auto-generated subtitles (`--write-auto-subs`) — covers Bilibili `ai-zh`
3. Whisper speech-to-text on downloaded audio (requires `faster-whisper` + `ffmpeg`)
4. Metadata-only report if all above fail

## Audio cache

Downloaded audio is cached at `~/.cache/video-analyzer-skill/audio/<video_id>.mp3` (TTL: 30 days).
Re-running the skill on the same URL skips the download step.

## Supported platforms

Any yt-dlp-supported site: YouTube, Bilibili, Twitter/X, Douyin/TikTok, Weibo, Vimeo, and 1000+ others.

## Dependencies

| Tool | Purpose | Install |
|------|---------|---------|
| `yt-dlp` | Metadata + subtitle extraction | `pip install yt-dlp` |
| `faster-whisper` | Audio transcription fallback (Python 3.11) | `python3.11 -m pip install faster-whisper` |
| `ffmpeg` | Audio conversion for Whisper | `brew install ffmpeg` |

## Gotchas

- Bilibili AI 字幕（`ai-zh`）需要登录态。未登录时 yt-dlp 拿不到字幕，必须加 `--cookies-from-browser chrome`。
- YouTube age-restricted 视频同理，需要 cookies 才能下载音频做 Whisper 转录。
- `faster-whisper` 建议使用 Python 3.11 以获得最佳兼容性；3.12+ 环境下 CTranslate2 wheel 可能不可用，需先验证。脚本优先使用 `python3.11`。
- Whisper `medium` 模型首次运行需下载约 1.5GB，耗时较长；后续复用缓存在 `~/.cache/huggingface/`。
- Whisper 对纯音乐 / 无人声片段会产生幻觉文本（hallucination），分析时需对照视频时长判断转录质量。
- 部分 Bilibili 视频的 `duration` 字段返回 0 — 这是 yt-dlp 已知 bug，不影响字幕提取。
- 输出文件名中的特殊字符（`/`、`:`、`?`）会被替换为 `-`，确保文件系统兼容。

## Edge Cases

| 场景 | 降级策略 |
|------|---------|
| 无字幕 + Whisper 不可用 | 生成 metadata-only 报告，§4–§12 标注"转录不可用，仅基于描述和元数据推断" |
| 视频时长 > 3 小时 | Whisper 转录可能超时；建议用 `--model base` 或 `--no-transcribe` 依赖平台字幕 |
| 转录质量差（大量 `[music]` 标记） | 在报告开头声明"转录质量有限"，分析聚焦于可辨识的文本段落 |
| JSON 中 `transcript` 为空字符串 | 等同于"无字幕"场景，走 metadata-only 降级 |
| 网络超时 / 下载中断 | 重试一次；仍失败则告知用户检查网络或 URL 有效性 |
