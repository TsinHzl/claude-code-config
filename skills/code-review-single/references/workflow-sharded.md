# 并行分片流程（SHARDS > 1）

## 1. 单条消息并行启动

启动 `SHARDS` 个 sub-agent（subagent_type=`code-reviewer`），每个传入：

- **行为覆盖（强制，覆盖 code-reviewer 默认人设第 1/3 步，必须放在 prompt 最前）**：
  - 禁止执行 `git diff` / `git log` / `git status` 或任何 git 命令 — 审查依据仅为下方传入的 shard 文件内容，不得自行取数
  - 禁止 Read shard 文件之外的任何文件（包括改动文件完整原文、周边代码、导入/依赖/调用点）— 仅基于 diff 文本本身判断，不做上下文扩展阅读
  - 忽略自身默认审查清单（安全/代码质量/React/Node/性能/最佳实践五类）与默认输出格式，严格套用下方内联的六维扫描规则与三档梯度模板
- 对应 `SHARD_<i>` 文件绝对路径（sub-agent 自行 Read）
- 内联 [review-rules.md](review-rules.md) 六维扫描规则与 [report-template.md](report-template.md) 三档梯度模板（避免每个 sub-agent 重复 Read references）
- 输出约束：
  - 仅输出三类 findings 的 markdown 片段，不输出文件骨架/变更统计/总评
  - 位置字段统一格式：`<相对路径>:L<起>-L<止>`，便于合并排序
  - 不编号（主 agent 统一编号）
  - 中文输出

## 2. 主 agent 合并

收集 N 份 sub-agent 返回，**合格判定**（必须同时满足，否则计入 `failed_shards`，不阻塞主流程）：

- 文本中含至少一个 🚫 / ⚠️ / 💡 标记，或显式输出"本分片无发现"
- 每条 finding 的位置字段匹配正则 `[^:]+:L\d+(-L\d+)?`

三类 findings 各自按 (文件名字母序, 起始行号升序) 排序 → 统一重新编号 → 重新计数。

## 3. 写入最终报告

- **数据源**：变更统计输入是 Step 1 stdout 中 `=====` 分隔线之后的 diff 全文（参见 [review-rules.md](review-rules.md)），不要反向聚合 shard 文件
- 变更统计由主 agent 独立计算（不复用 sub-agent 结果）
- 总评按 [report-template.md](report-template.md) 公式计算
- 套用文件骨架后，按文件命名规则（`cr-result.md`，已存在则依次追加 `-1`、`-2`……取第一个不存在的编号）调用 Write 写入 `<工作目录>`
- 若 `failed_shards` 非空，在文件末尾追加：`> ⚠️ 分片 [<失败编号列表>] 审查失败，以上结果可能不完整，建议重跑或缩小范围`

## 4. 清理 shard 临时文件

从 Step 1 header 中解析所有 `SHARD_<i>:` 后的绝对路径，单次 Bash 调用 `rm -f "<path1>" "<path2>" ...`（路径用引号包裹防止空格）。
