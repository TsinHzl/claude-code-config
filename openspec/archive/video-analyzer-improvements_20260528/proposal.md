# 变更提案：video-analyzer-improvements

## 背景
video-analyzer skill 在实际使用中暴露了 7 个问题，涵盖正确性缺陷、信息错误和体验短板。
其中 Python 版本问题和模型 hardcode 导致 Whisper 转录在默认路径下完全失效。

## 目标范围

**在范围内：**
- 修复 SKILL.md 中 python3 → python3.11 的版本调用问题
- analyze_video.py 添加 --model 参数（默认 medium）
- 修复中文字数统计（.split() → len() 字符数）
- 更新 SKILL.md 依赖表：openai-whisper → faster-whisper
- 报告 metadata 表新增 transcript_source 和 model 字段
- 音频文件缓存（按 video_id hash 缓存，避免重复下载）
- HF mirror 改为环境变量可覆盖，不强制设置

**不在范围内：**
- 更换 yt-dlp 以外的元数据提取方案
- 修改报告分析的 12 个章节结构
- 支持批量 URL

## 技术方案

### Python 版本探测（SKILL.md + 脚本）
SKILL.md 中所有 python3 调用改为：
```bash
PYTHON=$(python3.11 -c 'import sys; print(sys.executable)' 2>/dev/null || python3 -c 'import sys; print(sys.executable)')
$PYTHON /path/to/analyze_video.py ...
```
脚本内部 transcribe_audio() 中的 CLI fallback 也相应使用探测结果。

### --model 参数
argparse 新增 `--model`（默认 `medium`），透传给：
- CLI 调用：`faster-whisper audio_file --model MODEL`
- Python API：`WhisperModel(model_name, ...)`

### 字数统计
`len(transcript.split())` → `len(transcript)` 字符数，输出改为 `N chars`。

### 音频缓存
缓存目录：`~/.cache/video-analyzer-skill/audio/<video_id>.mp3`
- video_id 从 yt-dlp metadata 的 `id` 字段取
- 命中缓存则跳过下载
- 缓存文件超过 30 天自动跳过（不删除，让用户自行清理）

### HF Mirror
移除 `os.environ.setdefault("HF_ENDPOINT", "https://hf-mirror.com")`。
改为读取环境变量：若 `HF_ENDPOINT` 已设置则尊重，否则不注入。

### 报告 metadata 新增字段
| 字段 | 值 |
|------|-----|
| 转录来源 | subtitles / whisper / none |
| Whisper 模型 | medium / base / （N/A） |

## 预期影响
- 默认路径下 Whisper 转录从「静默失败」变为「正常工作」
- 报告质量可追溯（能看出是字幕还是 Whisper 转录）
- 同一视频二次分析速度显著提升（跳过音频下载）

## 风险
- 缓存目录占用磁盘空间：medium 模型转录一个 17 分钟视频的 mp3 约 8MB，可接受
- Python 版本探测链若两个版本都没有 faster-whisper，降级行为与现在一致（返回 None）
