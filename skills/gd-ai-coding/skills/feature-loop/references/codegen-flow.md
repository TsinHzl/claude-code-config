# 步骤 4：代码生成（Per-platform Sub-agent 模式）

## 架构说明

codegen 使用独立 sub-agent 执行，原因：
1. **API 缓存**：规则文件作为 prompt 前缀，跨 feature 复用缓存（token 成本降 90%）
2. **Context 隔离**：每个 feature 的 codegen 上下文干净，不受前序 feature 残留影响
3. **Platform 隔离**：跨平台 feature 按 platform 分组，每组独立 sub-agent 只加载自己的 rules

Sub-agent 拥有 Read/Write/Edit/Bash 工具权限，可直接操作工程文件。

### Per-platform 上下文隔离

当 `group_files_by_platform` 输出多个 platform 组时，每个 sub-agent 只接收：
- 该 platform 的 rules（从 `platform/{name}/rules/` 加载）
- 该 platform 对应的文件列表（code-scope 的子集）
- 共享的 spec-slice.md / design-slice.md / constraints.md

不同 platform 的 sub-agent 互不可见，token 各算各的。单平台 feature 退化为一个 sub-agent（与改造前行为一致）。每个 feature 重新启动 sub-agent，不跨 feature 复用。

> **状态写入边界**：codegen sub-agent **不写入** `state.json`、`feature-plan.json`、`.dac/knowledge/*`、`.dac/logs/*`。所有状态更新和 Harness 脚本（audit-log、extract-constraints）在 sub-agent 返回后由本步骤（主会话）执行。

> **注意：** `ui_dsl.json` / `ui_tree.txt` 不是硬性前置条件。当步骤 3 用户选择跳过设计稿，或 `flow_profile.skip_mastergo=true` 时，codegen 基于 code-scope.md + spec-slice.md 生成代码，不阻断。`assemble-codegen-prompt.sh` 已包含文件存在性判断：`ui_dsl.json` 不存在时不注入设计稿上下文。

## 4.1 前置门禁 + 骨架生成

```bash
# 统一调用：scaffold-feature + pre-skill-check + pre-codegen-check + audit-log
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/feature/feature-harness.sh $FEAT_ID pre-codegen
```

> 内部执行顺序：`scaffold-feature.sh`（零 LLM token 预生成骨架文件）→ `pre-skill-check` → `pre-codegen-check` → `audit-log START`。
> 骨架文件含类声明、生命周期壳、DI 注册、`part of` 声明，标记 `// TODO: business logic` 供 sub-agent Edit 填充。
>
> **skip_scaffold 模式**：当 `flow_profile.skip_scaffold=true` 时，`feature-harness.sh` 跳过 `scaffold-feature.sh` 调用（输出 `⏭ 跳过骨架`）。此时 sub-agent 应使用 **Write 模式**（创建完整文件）而非 Edit 模式（编辑骨架 `// TODO` 占位）。`assemble-codegen-prompt.sh` 检测到无骨架文件时自动在 prompt 中指示 sub-agent 使用 Write。

## 4.2 Git Checkpoint（pre-codegen 已写入，禁止覆盖）

`.codegen_checkpoint` 由 **4.1 `feature-harness.sh pre-codegen`** 在门禁通过后写入（`git rev-parse HEAD`）。主会话 **禁止** 再 `echo` 覆盖该文件：codegen 中途重跑 pre-codegen 时 harness 也会跳过已有文件，避免基准漂到代码生成之后。

读取（回滚 / CR diff / 完整性检查）用：

```bash
CODEGEN_BASE=$(jq -r '.base_commit // empty' "openspec/changes/$REQ_NAME/features/$FEAT_ID/.codegen_checkpoint")
```

> **时序保证**：checkpoint 在 scaffold + pre-check 通过后创建，因此骨架文件已存在于工作区。回滚时用 `git checkout $CODEGEN_BASE -- <files>` 恢复到骨架状态（而非清除骨架），再从 4.3 重新启动 sub-agent。

> **中断恢复逻辑**：`recovery.sh --diagnose` 检测到 `.codegen_checkpoint` 存在但代码不完整时，提示用户执行回滚命令：
> `git checkout $(jq -r .base_commit .codegen_checkpoint) -- <code-scope 中列出的文件>`
> 然后从 4.3 干净重试。

## 4.3 确认 → 组装 Prompt → 启动 Sub-agent

**禁止** `CODEGEN_PROMPT=$(bash assemble-codegen-prompt.sh …)`：脚本 stdout 是完整 ZONE A/B/C prompt（规则+切片，可达数十～上百 KB），灌进主会话会让本轮在 `post:Bash` 之后长时间无 AskUserQuestion / 无 Agent，插件看起来像卡住。

**确认前检查 batch_confirmed：**

```bash
BATCH=$(jq -r '.batch_confirmed // false' .dac/state.json)
```

若 `$BATCH != "true"`，**先**用 `AskUserQuestion`（本轮禁止输出任何文字，禁止写成 `yes / yes-all` 纯文本等待）：

```json
{
  "questions": [{
    "header": "即将生成代码",
    "question": "即将启动 codegen sub-agent，按 code-scope 写入或修改文件。确认执行当前功能？",
    "options": [
      { "label": "确认执行", "description": "只生成当前功能" },
      { "label": "全部确认", "description": "当前及后续功能都不再询问" },
      { "label": "取消", "description": "不启动本次代码生成" }
    ]
  }]
}
```

**确认结果处理：**

- `确认执行`：继续组装 prompt 并启动当前 feature 的 sub-agent
- `全部确认`：设置 batch_confirmed 后启动：
  ```bash
  bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/state-update.sh --set-flag batch_confirmed true
  ```
  当前及后续 feature 的 codegen 跳过确认直接执行
- `取消`：不启动 sub-agent，向用户说明已取消后停止本步骤

若 `$BATCH == "true"`，跳过确认，直接组装 prompt（仅输出一行摘要）。

**组装 prompt（写入文件，主会话只看路径）：**

```bash
mkdir -p .dac/tmp
PROMPT_FILE=".dac/tmp/codegen-prompt-${FEAT_ID}.txt"
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/feature/assemble-codegen-prompt.sh $FEAT_ID > "$PROMPT_FILE"
echo "WROTE $PROMPT_FILE ($(wc -c < "$PROMPT_FILE" | tr -d ' ') bytes)"
```

> **subagent_type 强制约束：** 必须显式指定 `agentType: "general-purpose"`，不得使用默认映射的 `code-reviewer`
> （其工具集为 Read/Grep/Glob/Bash，缺少 `Write`/`Edit` 工具，会导致 codegen sub-agent 无法写入任何生成的代码文件）。
> **前台执行强制约束：** sub-agent 调用必须显式设置 `run_in_background: false`。与 Claude Code 默认行为一致（该参数默认即为 `false`，SDK 不依赖外部全局规则文件；Claude Code 的全局规则同样要求前台执行）。显式声明仅为防止后续 skill 作者在快速复制模板时遗漏默认参数。骨架/业务逻辑生成结果必须等 sub-agent 返回后才能进入步骤 4.4 Layer 2 验证。

Claude Code 使用 `Agent` 工具启动 codegen sub-agent。Codex 必须先由 `code-scope.md` 生成仅含允许业务文件的工作区相对 allowlist，再按 `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/references/codex-agent-orchestration.md` 以 `code-generator` 独立运行；门禁失败、角色输出 `BLOCKED`、allowlist 外写入或输出缺失时终止本功能，禁止主会话生成代码或修复构建错误。**prompt 不要粘贴 `$PROMPT_FILE` 全文**（那会再次灌进主会话）；让独立角色自己 Read 该文件：

```
Agent({
  description: "Codegen: {feat_name}",
  prompt: "打开并严格遵循文件 {workspace}/.dac/tmp/codegen-prompt-{feat_id}.txt 中的全部指令生成代码。不要向用户提问，不要省略任何 ZONE。",
  agentType: "general-purpose",
  run_in_background: false
})
```

**Prompt 结构（确保缓存命中）：**

- ZONE A（静态前缀）：platform/{plat}/rules/ 下编码规范（Flutter: flutter-architecture.md + flutter-style.md [+ flutter-performance.md + flutter-widgets.md]）
- ZONE B（半静态）：constraints.snapshot.md + error-patterns.snapshot.md
- ZONE C（动态）：code-scope.md + spec-slice.md + design.md + ui_dsl/ui_tree

同类型 feature（page/component 或 service/refactor）的 ZONE A+B 完全一致 → API 前缀缓存命中。

## 4.4 Layer 2 验证

Sub-agent 返回后，先执行完整性检查，再进入 Layer 2 验证：

**Sub-agent 完整性检查**：对比 code-scope.md 中声明的文件列表与实际变更（`git diff --name-only $CODEGEN_BASE`）。判定逻辑：

- 计算 `code-scope 声明文件 ∩ 实际变更文件`
- 若交集为空（声明的文件一个都没改），视为异常退出，直接进入重试流程（等同 exit 1）
- 额外变更（如 `part of` 导入、barrel export）不算异常

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/feature/feature-harness.sh $FEAT_ID post-codegen
```

> 内部执行：`post-codegen-check.sh --check-retry-count` → `audit-log DONE` → `knowledge/extract-constraints.sh`（仅通过时）。

> `--check-retry-count` 是重试次数的**唯一权威源**：读取 feature-plan.json 的 error_log，重试 ≥3 次时直接 exit 2 阻断。`codegen-retry.md` 中的重试流程不做独立计数。

**Layer 2 退出码语义：**

| Exit Code | 含义 | 本 skill 动作 |
|-----------|------|-------------|
| 0 | 全部通过 | 进入下一步骤（由调用方决定：首次 → 步骤 5；CR 修复重跑 → 步骤 6） |
| 3 | 仅 format 问题，已自动修复 | 自动 `git add` 格式化修复的文件，然后进入下一步骤（路由同 exit 0）。CR 审查范围包含格式化变更。 |
| 1 | 硬性失败（文件缺失/analyze error/命名违规） | 触发 codegen 重试流程 → 详见 `codegen-retry.md` |
| 2 | 重试次数超限 | 标记 failed，等待人工介入 |
