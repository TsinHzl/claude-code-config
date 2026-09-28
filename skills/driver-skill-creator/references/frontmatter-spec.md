> 基于 Agent Skills 官方规范,完整覆盖全部 6 个标准字段。

# Frontmatter 字段规范

## 字段总览

| 字段 | 必填/可选 | 说明 |
|------|-----------|------|
| `name` | **必填** | 唯一标识,小写 kebab-case,与父目录名一致 |
| `description` | **必填** | 描述做什么 + 何时使用,Agent 触发的唯一依据 |
| `license` | 可选 | 许可证名称或文件引用 |
| `compatibility` | 可选 | 环境需求(目标产品、系统依赖、网络访问) |
| `metadata` | 可选 | 任意键值对,存储规范未定义的额外属性(如 author、version、tags) |
| `allowed-tools` | 可选(实验性) | 空格分隔的预批准工具列表 |

## 必填字段

### `name`

- 格式:kebab-case(小写字母 + 数字 + 连字符)
- 长度:1-64 字符
- 起止限制:不得以连字符开头或结尾,不允许连续连字符 `--`
- **必须与 skill 根目录名严格一致**

命名原则:**短、可触发、动词优先**。name 是技能库索引的第一层过滤。

**正例:** `code-review-single`, `driver-skill-creator`, `git-commit-helper`
**反例:** `CodeReviewSingle`(驼峰), `code_review_single`(下划线), `-pdf`(连字符开头)

### `description`

- 长度:1-1024 字符(UTF-8 codepoint 计数,1 汉字 = 1 字符)
- 内容要求:同时描述 skill **做什么**和**何时使用它**
- 必须含至少 3 个触发关键词(中文或英文),用于 skill detection 匹配
- 视角:第三人称(描述 skill 做什么,不是 "I will ...")
- 偏向主动:明确列出适用上下文,包括用户不直接命名领域的情况

**发现层与执行层分离:**

name 和 description 是发现层,正文是执行层。两层不要混在一起。
- description 传达"何时触发",触发条件放在正文里的 `When to Use` Agent 看不到
- description 也不能变成工作流摘要,否则 Agent 读完描述就凭印象执行,跳过正文

**description 是路由器,不是教程:**

```yaml
# 错误 — Agent 可能凭描述执行,跳过正文
description: "创建 Skill 时先收集例子,再规划 scripts,然后运行 init_skill.py,最后 quick_validate.py。"

# 正确 — Agent 知道应该触发,但仍需加载正文
description: "用于创建或更新包含专用工作流、工具集成、领域知识、捆绑脚本、参考资料的 Agent Skill。"
```

**优秀示例:**

```yaml
description: >
  分析 CSV 及表格数据文件——计算汇总统计、添加衍生列、生成图表、
  清洗脏数据。当用户有 CSV、TSV 或 Excel 文件,想要探索、转换或
  可视化数据时使用此 Skill,即使用户没有明确说"CSV"或"分析"。
```

**糟糕示例:**

```yaml
description: 处理 CSV。
```

> 差距:优秀示例列出功能(计算汇总、添加列、图表、清洗)、触发词(CSV/TSV/Excel)、隐式触发(用户未明说 CSV)。糟糕示例全部缺失。

## 可选字段

### `license`

```yaml
license: Apache-2.0
license: 专有许可。完整条款见 LICENSE.txt
```

### `compatibility`

- 长度:1-500 字符
- 仅在 skill 有特定环境需求时包含

```yaml
compatibility: 需要 Python 3.10+ 和 uv
compatibility: 需要 git、docker、jq,并可访问互联网
```

### `metadata`

任意键值对,客户端可存储规范未定义的额外属性。

```yaml
metadata:
  author: example-org
  version: "1.0"
  tags: "pdf,document,forms"
```

### `allowed-tools`

- 格式:**空格分隔**的工具名列表(官方规范)
- 支持 glob 模式,如 `Bash(git:*)`
- 仅声明 skill 实际会用到的工具

**正例:** `Bash(git:*) Read Write Edit`
**反例:** `*`(过度宽松), `Read, Write, Bash`(逗号分隔非官方标准)

## 完整示例

```yaml
---
name: pdf-processing
description: >
  提取 PDF 文本,填充表单,合并文件。当用户处理 PDF 文档,
  或提到文档提取、表单填充、PDF 操作时使用此 Skill。
license: Apache-2.0
compatibility: 需要 Python 3.10+ 和 uv
metadata:
  author: example-org
  version: "1.0"
allowed-tools: Bash(uv:*) Read Write
---
```
