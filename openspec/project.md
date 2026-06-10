# 项目上下文

## 技术栈
- Claude Code Skills（~/.claude/skills/）
- Python 3.11（faster-whisper 所在环境）/ Python 3.14（系统默认 python3）
- yt-dlp：视频元数据 + 字幕提取
- faster-whisper（Systran/faster-whisper）：本地语音转录，无需 API Key
- ffmpeg：音频格式转换

## 架构约定
- Skill 入口：SKILL.md（元数据 + 指令层）
- 数据提取：scripts/analyze_video.py（Python 脚本，输出 JSON）
- 报告生成：由 Claude 模型完成，写入 ~/Downloads/

## 目录结构
```
~/.claude/skills/video-analyzer/
├── SKILL.md               # skill 定义与工作流指令
├── scripts/
│   └── analyze_video.py   # 视频数据提取脚本
└── install.sh             # 依赖安装脚本
```

## 开发约定
- 脚本必须用 python3.11 执行（faster-whisper 仅在 3.11 下可用）
- Whisper 模型通过 --model 参数指定，默认 medium
- 字数统计使用字符数（len()），不用 .split()
