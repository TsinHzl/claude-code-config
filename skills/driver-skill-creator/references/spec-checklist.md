# Skill 规范自检清单

Step 3 写入后对照逐项验证,任一 ❌ 必须修复或询问用户。

## 目录结构

- [ ] skill 根目录名 == frontmatter `name` 字段(kebab-case, 1-64 字符)
- [ ] SKILL.md 位于 skill 根目录(非子目录)
- [ ] 辅助文件分类:`references/` 文档,`scripts/` 脚本,`assets/` 静态资源

## Frontmatter

- [ ] 含必填 `name`(kebab-case, 不以连字符开头/结尾, 无连续连字符 `--`)
- [ ] `name` 与 skill 根目录名严格一致
- [ ] 含必填 `description`(第三人称, 1-1024 字符)
- [ ] `description` 同时描述"做什么"和"何时使用"
- [ ] `description` 含至少 3 个触发关键词(中文或英文)
- [ ] `allowed-tools` 用**空格分隔**(非逗号),工具名与 Agent 实际工具名一致
- [ ] 可选字段(`license`/`compatibility`/`metadata`)格式正确(如有)

## 内容结构

- [ ] SKILL.md ≤ 80 行(本项目约定,官方为 < 500 行)/ < 5000 tokens(超过必须拆 references)
- [ ] 主 workflow 用 markdown 标题层级:`## Workflow` → `### Step N`
- [ ] 每个 references 子文件被 SKILL.md 至少引用一次(无孤儿文件)
- [ ] 每个 SKILL.md 引用的 references 路径都真实存在(无死链)

## 内容质量

- [ ] 不内联超过 30 行的业务流程(应拆到 references)
- [ ] 不出现"覆盖全局规则"措辞(skill 不得越权)
- [ ] 强制约束写在 `## Constraints` 节
- [ ] 每段内容通过"没有这条指令 Agent 会搞错吗?"测试
- [ ] 至少应用一种高价值正文模式(Gotchas / 输出模板 / 检查清单 / 验证循环 / 计划-验证-执行)
- [ ] 对 references 标注了具体触发关键词(非"如果需要则读取"式模糊条件)
- [ ] 提供默认值和具体步骤,而非选项菜单

## 脚本规范(含 scripts/ 时)

- [ ] 无交互式提示(缺参数 → 输出错误和用法示例,非挂起等待)
- [ ] 复杂脚本提供 `--help` 文档
- [ ] 输出结构化(JSON/CSV 到 stdout,诊断到 stderr)

## 行为设计

- [ ] 脆弱操作有门控(`<HARD-GATE>` 或加粗禁令),而非仅"建议"
- [ ] 门控放置在 `### Step N` 内部或 `## Constraints` 中,而非 frontmatter 或 references/ 内
- [ ] 自由度分级与任务脆弱度匹配(高/中/低)
- [ ] 含至少 2 条对抗合理化条目(Agent 借口 + Skill 反驳)
- [ ] 用真实任务做过前向测试(子代理模拟,不泄露诊断)
- [ ] 信息只放一个地方,SKILL.md 与 references/ 无重复规则
- [ ] 跨平台工具名用行为规则描述,而非硬编码特定平台工具

## 格式

- [ ] 中英文/数字之间用半角空格分隔
