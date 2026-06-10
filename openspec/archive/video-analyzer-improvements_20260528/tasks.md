# 任务清单：video-analyzer-improvements

## 状态：ARCHIVED

## 任务
- [x] T1: analyze_video.py — 添加 --model 参数（默认 medium），透传给 CLI 和 Python API 两条路径
- [x] T2: analyze_video.py — 字数统计改为 len(transcript) 字符数
- [x] T3: analyze_video.py — 音频缓存（~/.cache/video-analyzer-skill/audio/<video_id>.mp3，30天有效）
- [x] T4: analyze_video.py — HF_ENDPOINT 改为读取环境变量，不强制注入 mirror
- [x] T5: SKILL.md — Step 1/2 中 python3 改为版本探测链（python3.11 优先）
- [x] T6: SKILL.md — 依赖表 openai-whisper → faster-whisper，补充 --model 选项
- [x] T7: SKILL.md — 报告 metadata 模板新增转录来源和 Whisper 模型字段

## 验收标准
- [ ] python3.11 不存在时脚本能回退到 python3 而不崩溃
- [ ] --model base/medium/large 均能透传到 WhisperModel 和 CLI
- [ ] 中文视频统计输出为「N chars」而非「N words」
- [ ] 同一 URL 第二次运行跳过音频下载，输出 [cache hit]
- [ ] HF_ENDPOINT 未设置时不注入任何 mirror 地址
- [ ] SKILL.md 依赖表无 openai-whisper 字样
- [ ] 生成报告的 metadata 表包含「转录来源」和「Whisper 模型」两行
