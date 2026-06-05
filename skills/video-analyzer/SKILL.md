---
name: video-analyzer
description: >
  Analyze a video from a streaming URL (YouTube, Bilibili, Twitter/X, Douyin, etc.) and produce
  a detailed educational Markdown report saved to ~/Downloads. The report is written by the current
  Claude model after reading the extracted transcript — no external API key needed.
  Use when the user provides a video link and asks to "analyze", "summarize", "transcribe",
  or "report on" its content. Triggers on phrases like "分析这个视频", "帮我看这个视频", "视频内容分析",
  "analyze this video", "summarize the video at URL", "帮我分析这个链接的视频".
---

# Video Analyzer

Extracts video data with a Python script, then uses the **current Claude model** to generate
a detailed educational report saved to `~/Downloads/`.

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

### Step 3 — Read the extracted JSON

```bash
# The JSON contains: title, channel, platform, url, upload_date, duration,
# view_count, like_count, description, tags, categories, chapters[], transcript
```

Use the Read tool on the path printed by the script.

### Step 4 — Generate the educational analysis

Using the transcript and metadata from the JSON, write a comprehensive educational report
in Chinese Markdown. **Quality bar: a reader who has never watched the video should be able
to fully understand AND teach its content to others after reading this report.**
Minimum total analysis length: 2500 Chinese characters. Never truncate or abbreviate sections.

Required sections — follow this order exactly, use `##` for each section heading:

---

**§1 视频概述**
4–6 句精准概括：核心主题 + 目标受众 + 内容深度 + 视频的核心价值主张。
末尾注明：本视频适合什么类型的读者、预期收获是什么。

**§2 背景与问题导入**
深度展开以下四点（每点至少 2 句）：
- 问题背景：该话题的社会 / 技术 / 文化背景
- 核心痛点：视频要解答的具体问题或矛盾
- 重要性：为什么现在值得关注、忽视会有什么代价
- 作者切入视角：从什么独特角度展开讨论

**§3 核心内容详解**
严格按视频逻辑顺序，每个主要段落 / 章节用 `###` 子标题，格式如下：

```
### [段落主题标题]
**论点**：该段落的核心观点（1–2 句）
**论证过程**：逐步说明作者如何论证，保留逻辑链条
**证据 / 示例**：视频使用的具体案例、实验、数据、类比
**小结**：该段落的结论或与下一段的衔接
```

要求：不少于 3 个子段落；每个子段落 ≥ 150 字；忠实还原视频逻辑，不压缩。

**§4 数据与事实清单**
用表格列出视频引用的所有具体数据、统计数字、研究结论、历史事件：

| 数据 / 事实 | 来源（如有） | 视频中的用途 |
|------------|-------------|-------------|

若视频无量化数据，改为列出所有引用的具体事例（不少于 3 条）。

**§5 关键概念解释**
视频中出现的每个专业术语，逐一解释，格式：
- **[术语]**：通俗定义（≤ 2 句）→ 视频中的具体用法 → 为什么理解它对本话题重要

要求：不少于 3 个术语。

**§6 精彩金句摘录**
逐字引用视频中最具价值的 3–8 句话（用引号），并注明：
- 出现的上下文 / 大概时间节点
- 这句话为什么值得摘录（核心洞察 / 论点锚点 / 反直觉观点）

若字幕缺失，改为提炼 3–5 个最有价值的观点并用引号标注。

**§7 论证结构分析**
用层次大纲展现全片逻辑骨架：

```
核心命题
├── 论点 A（支撑方式：数据 / 案例 / 类比）
│   └── 反驳 / 补充
├── 论点 B
│   └── ...
└── 结论
```

然后用 1–3 句评价论证的严密程度（哪里有力、哪里存在逻辑跳跃）。

**§8 结论与核心观点**
三层递进：
1. 作者的直接结论（视频明确说了什么）
2. 延伸含义（这个结论对更大领域意味着什么）
3. 对读者的具体行动建议（看完后可以做什么）

**§9 批判性视角**
客观、公正地分析（各 ≥ 2 句）：
- 视频的独到见解与优点
- 可能的局限性或未充分考虑的因素
- 存在的替代观点或反驳角度
- 信息可能存在的立场偏差（若有）

**§10 读者收获清单**
分四类列出：
- 🧠 理解的概念
- 🛠 掌握的方法 / 框架
- 💡 可能改变的认知
- ✅ 可立即应用的知识点

**§11 延伸思考**
提出 3–5 个开放性深度问题（不是视频已回答的，而是引导进一步探索的方向）。

**§12 相关主题推荐**
基于视频内容，推荐 3–5 个延伸学习方向（书籍 / 领域 / 关键词 / 课程），说明与本视频的关联。

### Step 5 — Write the report to ~/Downloads/

Use the Write tool to save the full Markdown file:

```
~/Downloads/video-analysis-<safe-title>-<YYYYMMDD_HHMMSS>.md
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

## 字幕 / 转录文本

<details>
<summary>展开完整字幕（点击展开）</summary>

（full transcript here）

</details>

---

## 内容分析

（Step 4 的全部 12 个 sections 依次写在这里，每节用 `##` 标题）

---

*本报告由 video-analyzer skill 自动生成。*
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
