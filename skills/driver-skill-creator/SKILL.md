---
name: driver-skill-creator
description: Use when the user asks to create / scaffold / generate / 写 / 创建 / 生成 a new skill, or to edit / optimize / refactor / 优化 / 重构 an existing skill. Collects user intent, auto-infers metadata and structure, applies content quality patterns from Agent Skills spec, then writes a standards-compliant skill directory under ~/.claude/skills/ following progressive disclosure.
metadata:
  version: "4.0.0"
allowed-tools: Read Write Edit Bash AskUserQuestion Agent
---

# Driver Skill Creator

> 完整 references 索引见 [references/README.md](references/README.md)。

## Workflow

### Step 0: 模式检测 + 前置门控

检查用户意图:
- **新建** → 进入 Step 1
- **编辑已有 skill** → Read 目标 skill 全部文件,识别变更点,跳至 Step 2 生成增量 diff 提案

<HARD-GATE>
新建 Skill 时,必须先获取具体使用例子(用户描述的触发场景 + 输入/输出)。
没有例子 → AskUserQuestion 追问,禁止从抽象能力出发直接生成。
</HARD-GATE>

### Step 1: 知识萃取 + 行为设计

**优先从真实工件提取**,而非凭空生成:
- 对话历史中的成功步骤、纠正、输入输出格式
- 已有内部文档、API 规范、运维手册、Code Review 评论
- 真实故障案例及解决方案

用户用自然语言描述 skill 用途,模型自动推断:

1. `name` — kebab-case 命名(短、可触发、动词优先)
2. `description` — 按 [references/frontmatter-spec.md](references/frontmatter-spec.md) 规范生成(路由器,非教程)
3. workflow 模式 — 按 [references/workflow-patterns.md](references/workflow-patterns.md) 决策表选择
4. references 拆分 — 按 [references/progressive-disclosure.md](references/progressive-disclosure.md) 规则规划(含条件触发设计)
5. `allowed-tools` — 按 [references/tools-inference.md](references/tools-inference.md) 推断
6. 正文模式 — 按 [references/content-patterns.md](references/content-patterns.md) 选择模式(含门控、自由度、对抗合理化)
7. **行为链路 7 点** — 按 [references/content-patterns.md](references/content-patterns.md) §行为链路 7 点逐项确认覆盖

推断结果纳入 Step 2 提案,不单独确认。
若描述过于模糊 → AskUserQuestion 追问**一个**聚焦问题。

### Step 2: 完整提案 + 单次确认

一次性展示:

1. frontmatter 全部字段(含适用的可选字段)
2. 文件结构树(含 references 子文件清单)
3. 每个文件的完整内容(代码块)

正文必须通过 [references/spec-checklist.md](references/spec-checklist.md) §内容质量 + §行为设计 全部检查项。

通过 **AskUserQuestion 单次确认**: [确认写入] / [需要修改] / [取消]

### Step 3: 写入 + 验证

1. `mkdir -p ~/.claude/skills/<name>/references/`(如需)
2. 冲突检测:目标目录已存在 → AskUserQuestion [覆盖] / [改名] / [取消]
3. 单条消息内并行 Write 全部文件
4. 启动 sub-agent 对照 [references/spec-checklist.md](references/spec-checklist.md) 独立验证
5. 验证失败 → 修复后再验证,最多 2 轮

### Step 4: 前向测试 + 输出

1. 输出安装路径、触发关键词、测试调用示例
2. 建议用户用原始任务做前向测试:给子代理原始任务和最少上下文,不泄露诊断和预期答案

## Constraints

- 严禁猜测用户未提供的意图 — 描述模糊时 AskUserQuestion 追问
- SKILL.md 正文 ≤ 80 行(本项目约定,官方规范为 < 500 行 / < 5000 tokens),超过强制拆 references
- Step 2 确认覆盖 Step 3 的批量 Write,Step 3 不再逐文件追问
- 生成产物为裸目录;如需 `.skill` 分发文件,手动运行 `scripts/package_skill.py <skill-dir>`
- **Skill 间引用**:声明关系(Required / Recommended / See Also),不硬编码路径或强制加载
- **平台适配**:写行为规则而非硬编码工具名,工具不存在时应优雅降级
