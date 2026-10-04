---
name: gd-ai-coding
description: Use when starting a full Flutter client development cycle — from Cooper PRD extraction through feature planning, design spec parsing, code generation, and AI code review. Trigger for any new requirement that needs end-to-end automated development.
user-invocable: true
metadata:
  openclaw:
    emoji: "🚀"
    requires:
      bins:
        - mcporter
---

# gd-ai-coding — Flutter 客户端 AI 全流程主编排

触发命令：`/gd-ai-coding`

## When to Use

- 收到新的 Cooper 需求文档，需要从 PRD 到代码的完整开发流程
- 已有 PRD 但需要走完功能拆分 → 代码生成 → CR 的闭环
- 上次流程中断，需要恢复继续（会自动检测 .dac/state.json）

## When NOT to Use

- 单文件 bug fix、typo 修正或小范围重构（直接修改即可）
- 仅需需求澄清 / 功能拆分 / 设计稿获取 / 代码审查等单项能力：本插件子 skill 已收编到 `skills/` 目录，不注册为顶层命令，可按 `references/` 中对应流程文档的指引 Read `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/skills/<name>/SKILL.md` 单独执行（注意单项执行需自行补齐 `.dac/` 状态与产物前置条件）

## 职责

驱动 Cooper PRD → 功能拆分 → 代码生成 → CR 的完整开发循环。本 skill 不直接生成代码，只负责流程编排、状态管理和用户交互节点。

## 全流程行为规则
规则见 `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/rules/dac-notes.md`。
交互规则（AskUserQuestion 插件模式）见 `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/rules/plugin-interaction.md`。
跨平台交互降级（Codex / DSH 等无 AskUserQuestion 的环境）见 `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/rules/interaction-degradation.md`：无该工具时，所有「必须调用 AskUserQuestion」的交互点按纯文本一次一问执行。Codex 的需求核验、代码生成、测试和 CR 必须遵循 `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/references/codex-agent-orchestration.md`，角色能力、定义或认证缺失时输出 `BLOCKED` 并停止，禁止降级为主会话自审。

## 执行步骤

### 初始化

**进度清单（贯穿全流程）：** 执行下方第 1 步之前，先用当前环境可用的会话任务清单工具（标准 Claude Code 为 `TodoWrite`，否则 `TaskCreate`；Codex / DSH 等无任务工具的环境降级为纯文本阶段声明，见 `rules/interaction-degradation.md`）建立 4 条顶层条目：`初始化`、`阶段1：需求分析`、`阶段2：项目级规划与功能拆分`、`阶段3：功能开发 (0/N)`；将 `初始化` 置 `in_progress`。此后每进入一个阶段即置 `in_progress`、产物达成即置 `completed`。规则详见 `rules/progress-tracking.md`。进度清单仅为展示层，不参与任何流程判定（权威状态见 `rules/state-authority.md`）。

1. **环境依赖检查**（初始化工作目录前执行，后续子 skill 不再重复检查）

   ```bash
   bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/env-checks.sh
   ```

   检查项：mcporter（含 Cooper 配置）、openspec CLI（必选）；graphify（可选，不阻断）。
   - 失败（❌）：必选项缺失，阻断流程，展示修复指引
   - **bash 输出即最终展示，不要用文字复述一遍 bash 输出的内容。** 直接根据 `GRAPHIFY_STATUS` 处理：
     - `available` → 直接设置 `GRAPHIFY_DECISION=use`，无需询问
     - `unavailable` → **直接调用** `AskUserQuestion` 工具，**调用前后均不得输出任何文字**（包括"请选择"、选项列表、状态描述等一切文字）：
       ```json
       {
         "questions": [{
           "question": "graphify 未安装/未生成知识图谱。Phase 2 功能拆分可使用知识图谱提升规划精准度，是否现在安装？",
           "header": "Graphify 知识图谱",
           "options": [
             { "label": "现在安装并生成", "description": "执行 /graphify，需要几分钟" },
             { "label": "跳过，不使用工程知识图谱" }
           ]
         }]
       }
       ```
       **⚠️ Plugin 模式重要处理**：`AskUserQuestion` 在 VS Code 插件（`-p` 模式）下会返回
       `is_error=true`（内容 "Answer questions?"）——这是**预期行为**，插件 UI 已展示了选项卡给用户。
       收到 `is_error=true` 后：
       - **绝对不要**输出"用户未回答"/"用户未选择"/"默认跳过"/"请在上方选项中选择"等任何提示性文字
       - **绝对不要**擅自做决策或继续执行
       - **静默等待**下一条用户消息，**无论其格式**（`用户选择了：{选项}` 或自由文本），均作为选择结果：
         - 含"现在安装"或"install" → 执行 `/graphify`，完成后设置 `GRAPHIFY_DECISION=use`
         - 含"跳过"/"已跳过"/"不使用"/"skip" 或任何明确跳过意图 → 设置 `GRAPHIFY_DECISION=skip`，**立即继续后续流程**，不再输出任何提示
   - `GRAPHIFY_DECISION` 传递给 phase 2（feature-plan），不再二次询问。

   通过后**直接继续步骤 2**。禁止输出「即将执行全流程」编号列表，禁止在此处结束本轮等人。

2. 初始化工作目录 `.dac/`：

   ⚠️ **交互规则（贯穿本节所有 AskUserQuestion）**：调用 `AskUserQuestion` 后本轮禁止再输出任何文字（含编号选项、"请选择"、"已xxx"），静默等待下一条用户消息作为选择结果，见 `rules/plugin-interaction.md`。插件在 `-p` 模式下该工具会返回 `is_error=true`（用户可能已通过按钮作答）——**不得**据此改用纯文本重新询问。**严禁**在调用 AskUserQuestion 之前输出任何"已xxx"/"正在xxx"等状态描述。

   - 先执行 `bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/init-dac.sh --status` 获取当前状态（JSON）。
     **只认这个 JSON，禁止用 git dirty、工作区文件、或缺失的 phase 字段推断「上次未完成」。**
   - 判定优先级（从上到下，命中即停）：
     0. **多人协作发现**：若 `resumable` 不为 `true`（本机无 `.dac/`），检查 `openspec/changes/*/collab.json` 是否存在。若存在至少一份且对应目录含 `feature-plan.json`：
        ```bash
        ls -d openspec/changes/*/collab.json 2>/dev/null
        ```
        用 `AskUserQuestion` 询问（**禁止**改用纯文本）：
        ```json
        {
          "questions": [{
            "question": "检测到可加入的多人协作规划：{req_name 列表}，如何处理？",
            "header": "加入或新任务",
            "options": [
              { "label": "加入该需求", "description": "跳过 Phase 1/2，直接进入指派给我的 feature（走 join.sh）" },
              { "label": "开始新任务", "description": "忽略已有规划，走标准 init 流程" }
            ]
          }]
        }
        ```
        - 「加入该需求」→ 询问选哪份（若多份）→ 执行：
          ```bash
          bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/collab/join.sh --req {req_name}
          ```
          join 成功后本机 `.dac/state.json` 就绪（`phase=feature-planned`、`collab_mode=true`、`owner_committer=当前 git email`）。**跳过后续 init**，直接进入阶段 3（协作模式下按 assignee 过滤）。
          若 `git config user.email` 为空，`join.sh` 会 exit 1 提示先配置身份。
        - 「开始新任务」→ 落入下方规则 1，执行普通 init。
     1. `resumable` 不为 `true`（含 `exists: false`、残留空 `.dac/`、无 `state.json`、损坏 JSON、phase 缺失/`unknown`/非法值）：
        **视为无 DAC 进度。禁止弹出「继续 or 重新开始」。**
        直接执行 `bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/init-dac.sh` 初始化（脚本会自行清掉不可恢复的残留 `.dac/`）。
     2. `resumable` 为 `true` 且 `phase` 为 `feature-done` 或 `done`（上次已完成）：走下方「已完成」分支。
     3. `resumable` 为 `true` 且 `phase` 为其他已知阶段（上次未完成）：走下方「未完成」分支。此时才检查 `git status --porcelain`。
   - 如果 `resumable` 为 `true` 且 phase 为 `feature-done` 或 `done`（上次已完成）：
     先检查 `openspec/changes/` 下是否存在未归档的 change 目录（排除 `archive/` 子目录）。
     - 如果存在未归档的 change，使用 `AskUserQuestion` 询问（**禁止**改用纯文本列出选项）：
       ```json
       {
         "questions": [{
           "question": "检测到 openspec 变更尚未归档，如何处理？",
           "header": "OpenSpec 归档",
           "options": [
             { "label": "立即归档后开始新任务", "description": "推荐：归档当前 change，再开始新需求" },
             { "label": "跳过归档，开始新任务", "description": "保留未归档 change，直接开始" },
             { "label": "退出", "description": "不做任何操作" }
           ]
         }]
       }
       ```
       - 「立即归档后开始新任务」：使用 Skill 工具调用 `/opsx:archive`，归档完成后更新状态：
         ```bash
         bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/state-update.sh --phase done --force
         ```
         然后执行**重新开始流程**（见下方）
       - 「跳过归档，开始新任务」：直接执行**重新开始流程**
       - 「退出」：退出
     - 如果没有未归档的 change，使用 `AskUserQuestion` 询问（**禁止**改用纯文本列出选项）：
       ```json
       {
         "questions": [{
           "question": "上次任务已完成，是否开始新任务？",
           "header": "开始新任务",
           "options": [
             { "label": "是，开始新任务" },
             { "label": "否，退出" }
           ]
         }]
       }
       ```
       - 「是，开始新任务」 → 执行**重新开始流程**（见下方）
       - 「否，退出」 → 退出
   - 如果 `resumable` 为 `true` 且 phase 为其他已知阶段（上次未完成）：
     **先执行** `git status --porcelain` 检查是否有未提交的变更，**然后**使用 `AskUserQuestion` 一次性询问（**禁止**改用纯文本列出选项，**禁止**分两次询问）：
     - **若无未提交变更**：
       ```json
       {
         "questions": [{
           "question": "检测到上次任务未完成（phase: {当前phase}），如何处理？",
           "header": "继续 or 重新开始",
           "options": [
             { "label": "继续上次", "description": "从上次中断处恢复" },
             { "label": "重新开始", "description": "清空 .dac/ 状态，重新开始新任务" }
           ]
         }]
       }
       ```
       - 「继续上次」 → 执行 `bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/init-dac.sh --resume`
         → 恢复后按 `state.json` 的 phase 重建进度清单（见 `rules/progress-tracking.md` phase 映射表）：已越过的阶段标 `completed`、当前阶段标 `in_progress`；已完成 feature 补建 1 条 `completed` 条目，当前 feature 建 1 条 `in_progress` 条目（从步骤 0 重新执行）。
       - 「重新开始」 → 直接执行 `bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/init-dac.sh --force`
     - **若有未提交变更**（将两次判断合并为一次选择）：
       ```json
       {
         "questions": [{
           "question": "检测到上次任务未完成（phase: {当前phase}），且工作区有未提交变更，如何处理？",
           "header": "继续 or 重新开始",
           "options": [
             { "label": "继续上次", "description": "从上次中断处恢复，保留所有文件变更" },
             { "label": "重新开始（保留文件）", "description": "仅重置 .dac 状态，保留当前工作区文件" },
             { "label": "重新开始（回滚变更）", "description": "stash 暂存所有变更后重置，可通过 git stash pop 恢复" }
           ]
         }]
       }
       ```
       - 「继续上次」 → 执行 `bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/init-dac.sh --resume`
         → 恢复后按 `state.json` 的 phase 重建进度清单（同上）
       - 「重新开始（保留文件）」 → 直接执行 `bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/init-dac.sh --force`
       - 「重新开始（回滚变更）」 →
         ```bash
         git stash push -u -m "dac-reset: $(date +%Y%m%d-%H%M%S)"
         bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/init-dac.sh --force
         ```
         完成后告知用户：`已将所有变更（含未跟踪文件）暂存到 git stash，可通过 git stash pop 恢复`

   **重新开始流程（仅供 phase=done/feature-done 分支调用）：**

   执行 `git status --porcelain` 检查是否有未提交的变更：
   - 无变更 → 直接执行 `bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/init-dac.sh --force`
   - 有变更 → 使用 `AskUserQuestion` 询问（**禁止**改用纯文本列出选项）：
     ```json
     {
       "questions": [{
         "question": "工作区有未提交的文件变更，如何处理？",
         "header": "处理未提交变更",
         "options": [
           { "label": "回滚（stash 暂存）", "description": "暂存所有变更后恢复到最新 commit，可通过 git stash pop 恢复" },
           { "label": "保留当前文件", "description": "仅重置 .dac 状态，工作区文件不变" }
         ]
       }]
     }
     ```
     - 「回滚（stash 暂存）」：
       ```bash
       git stash push -u -m "dac-reset: $(date +%Y%m%d-%H%M%S)"
       bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/init-dac.sh --force
       ```
       完成后告知用户：`已将所有变更（含未跟踪文件）暂存到 git stash，可通过 git stash pop 恢复`
     - 「保留当前文件」：
       ```bash
       bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/init-dac.sh --force
       ```

3. **平台扫描 + 欢迎**（初始化后立即执行）

   ```bash
   source ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/platform.sh
   AVAILABLE_PLATFORMS=$(scan_available_platforms .)
   bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/state-update.sh --set-json available_platforms "$AVAILABLE_PLATFORMS"
   ```

   将检测到的平台及 src_root 映射写入 state.json。单平台仓库后续 codegen 无需分组逻辑；
   Mono-repo（多平台）则在 codegen 阶段按 code-scope 文件路径自动分组。

   完成后最多用**一句**说明已检测平台（例如「检测到 Flutter」），**同一条回复必须立刻调用步骤 1.1 的 `AskUserQuestion`**。
   **禁止**输出「即将执行全流程」编号列表，**禁止**只写「初始化完成 / 进入阶段 1」后结束本轮。
   用户看到的收集入口必须是插件弹出的 DDP 输入框。

---

### 阶段 1：需求分析 + 设计稿获取

> **进度清单：** 进入本阶段即把顶层 `阶段1` 置 `in_progress`，并追加 3 条子步条目：`阶段1 › 数据收集`（覆盖 1.1~1.3）、`阶段1 › LLM 处理`（覆盖 1.4~1.5）、`阶段1 › Spec 确认`（覆盖 1.6）。每完成对应小节组即置 `completed`。详见 `rules/progress-tracking.md`。

**执行模型：** 纯 bash I/O（Task A PRD 下载 + Task B 设计稿获取）并发执行（两个 Bash 工具调用放在同一条响应中并行发出），等待两者均完成后，再按顺序执行步骤 1.4（PRD LLM 处理）和步骤 1.5（需求澄清）。

**1.1 收集输入**

> 完整交互细节见 [`references/input-collection-flow.md`](references/input-collection-flow.md)。

进入本阶段后的**第一个动作**必须是调用下面的 `AskUserQuestion`（可与步骤 3 的一两行总览写在同一回合，但总览之后不得停住等人）。**禁止**以纯文本询问 DDP / PRD，**必须**调用工具——插件会把该问题渲染成内联输入框（可填 DDP 链接/ID，或点「本次无 DDP 需求」跳过）。

按固定顺序收集输入：

1. **DDP 需求（必填起点）** — 直接调用 `AskUserQuestion` 工具（**禁止**以纯文本形式询问用户，**必须**调用工具）：
   ```json
   {
     "questions": [{
       "question": "请提供本次开发关联的 DDP 需求，用于自动填充 req_name、版本号（例如：T-IBT-626806 或 R-IBG-689979）；若不关联 DDP，选「本次无 DDP 需求」。DDP 上的产品文档链接不会自动当作 PRD 去读",
       "header": "DDP 需求",
       "options": [
         { "label": "有 DDP 需求", "description": "在下一条消息中粘贴 DDP 链接或需求 ID——任务链接优先（T-IBT-xxx），只有任务能取到版本号；也支持 R-IBG-xxx 或纯数字" },
         { "label": "本次无 DDP 需求", "description": "降级走手动流程——由我协助确认 req_name，随后仍会询问是否有标准 PRD" }
       ]
     }]
   }
   ```
   收到用户输入后，按 `references/input-collection-flow.md` 的验证流程处理。验证失败或用户选「本次无 DDP 需求」则先确认 `req_name`，再进入第 2 步。**禁止**在第 2 步得到回答之前下载或打开 DDP 返回的 `prd` 链接。
2. **标准 PRD（必问）** — DDP / `req_name` 确认之后、**必须**调用 `AskUserQuestion`（禁止纯文本问，禁止因 DDP `prd` 有值或对话里已有 Cooper 链接而跳过）。**禁止**主动读取 DDP 关联的产品文档。
   ```json
   {
     "questions": [{
       "question": "本次是否有标准 PRD（Cooper「需求文档梳理」，含司机端需求列表等四段表）？有则在输入框粘贴该知识库链接（须含 knowledge）；没有则选「没有标准 PRD」。不要用 DDP 上的产品文档链接代替",
       "header": "标准 PRD",
       "options": [
         { "label": "有标准 PRD", "description": "在下一条消息中粘贴 Cooper「需求文档梳理」知识库链接" },
         { "label": "没有标准 PRD", "description": "走旧 PRD / 手动贴文档；若要用 DDP 关联链接，下一步再确认，现在不会去读" }
       ]
     }]
   }
   ```
   - 用户粘贴了 Cooper 知识库链接 → 作为本次 PRD 地址（标准路径候选），**不要**再去读 DDP `prd`；进入第 4 步 MasterGo
   - 「有标准 PRD」但未贴链接 → 提示粘贴，重问 1 次；仍空则视为「没有标准 PRD」
   - 「没有标准 PRD」→ 进入第 3 步
3. **PRD 地址（仅「没有标准 PRD」）** — 此时才允许使用 DDP 的 `prd`，且须用户确认或另贴，**禁止**静默下载。若 DDP `prd` 有值，调用 `AskUserQuestion`：选项「使用 DDP 关联的 PRD」/「另贴 Cooper 链接」/「本次无 PRD」。`prd` 为空则询问 Cooper 地址（须含 knowledge）。选「本次无 PRD」则不下载，供 1.2b 推断 `skip_prd_parse`。
4. **MasterGo 设计稿链接（必须询问，用户可跳过）** — 验证 DDP / 确认 req_name 之后、进入 1.2b **之前**，**必须**调用 `AskUserQuestion`（禁止用纯文本问、禁止未询问就当作「用户未提供」）。若本轮对话里用户已经贴过含 `layer_id` 的 MasterGo 容器链接，直接采用、不再问。否则：
   ```json
   {
     "questions": [{
       "question": "请提供 MasterGo 设计稿链接（须含 layer_id，MasterGo 中右键节点 → 复制容器链接；多个用换行或逗号分隔）。若本次无设计稿，选「本次无设计稿」",
       "header": "MasterGo 设计稿",
       "options": [
         { "label": "有设计稿", "description": "在下一条消息中粘贴 MasterGo 容器链接（须含 layer_id）" },
         { "label": "本次无设计稿", "description": "跳过设计稿获取，后续 codegen 不注入 UI DSL" }
       ]
     }]
   }
   ```
   - 用户粘贴了链接 → 记录 `MASTERGO_LINKS`，1.2b 推断 `skip_mastergo=false`
   - 用户选「本次无设计稿」或明确说「跳过」→ 1.2b 推断 `skip_mastergo=true`
   - **禁止**因为 PRD/DDP 正文里没出现 MasterGo URL，就跳过本问、直接 `skip_mastergo=true`

**关键约束：**
- DDP 详情/版本号**只允许**通过 `bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/ddp/fetch-ddp-detail.sh --ddp-id "{用户输入}"` 获取。**禁止**直接调用 `mcp__ddp__*`（含 `getRequirementDetail` / `getIssueDetail` / `getFieldMetas`），也禁止改用 `/ddp` skill。脚本内部已用 mcporter 按前缀分流：`T-IBT-` → `getIssueDetail`，`R-IBG-` → `getRequirementDetail`；版本号由脚本从任务 `dpmVersion` 提取，空则 `releaseVersion=""`，不阻断。
- `req_name` 必须是 PRD 需求英文名（kebab-case，2-51字符），**严禁用 DDP ID 作为 req_name**
- `DDP_ID` 与 `req_name` 分离保存，后续通过 `state-update.sh --ddp-id` 写入 state.json
- req_name 校验：`^[a-z0-9][a-z0-9]*(-[a-z0-9]+)*$`

---

**1.2 初始化目录**

```bash
[[ ! -d "openspec" ]] && openspec init --tools "${DAC_RUNTIME:?DAC_RUNTIME 未解析}"
[[ ! -d "openspec/changes/{req_name}" ]] && opsx new {req_name}
mkdir -p "openspec/changes/{req_name}/prd"
mkdir -p "openspec/changes/{req_name}/ui"
mkdir -p "openspec/changes/{req_name}/features"

<!-- state: prd-parsing -->
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/state-update.sh --phase prd-parsing --req-name "{req_name}" --ddp-id "{DDP_ID}"
```

若 `releaseVersion` 非空，追加写入 state.json（空值则跳过，不阻断）：
```bash
source ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/lib.sh && \
  atomic_jq --compact '.release_version_name = $v' .dac/state.json --arg v "{releaseVersion}"
```

若 DDP 验证通过且 `title` 非空，一并写入（供 skip_prd_parse 时生成轻量 prd-spec）：
```bash
source ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/lib.sh && \
  atomic_jq --compact '.ddp_title = $t' .dac/state.json --arg t "{title}"
```

若 `DDP_ID` 非空，向后端注册 trace↔DDP 绑定，使看板起点即把本 trace 合并进对应 DDP 需求卡
（`--ddp-req` 直接沿用 `fetch-ddp-detail.sh` 解析出的 `DDP_ID`——默认任务级 `T-IBT-xxx` 形式，
仅需求无关联任务时才是 `R-IBG-xxx`；须与看板 DDP 卡 req_name 一致；后端未配置时静默跳过，不阻断）：
```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/report-ddp-binding.sh \
  --trace-req "{req_name}" --ddp-req "{DDP_ID}"
```

**1.2 末尾必须落盘 PRD 来源（Harness，禁止跳过）：** 1.1 问完「有没有标准 PRD」之后，在进入 1.2b / 1.3 **之前**调用。没有这份记录时，`ingest-prd.sh --url` 会 `[DAC-SPEC-005]` 直接失败，不能拿 DDP `prd` 偷跑。

```bash
# 有标准 PRD（用户贴了需求文档梳理知识库链接）：
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/prd/record-prd-source.sh \
  --kind standard --url "{用户贴的 knowledge 链接}"
# 没有标准 PRD、用户确认使用 DDP 关联或另贴的旧 Cooper：
#   --kind legacy --url "{用户确认的 knowledge 链接}"
# 本次无 PRD（1.2b 可 skip_prd_parse）：
#   --kind none
```

禁止把 `fetch-ddp-detail.sh` 返回的 `prd` 写进 `--url`，除非用户在 1.1 第 3 步明确选了「使用 DDP 关联的 PRD」且已按 legacy 记录。

---

**1.2b 流程配置推断与确认（flow_profile）**

基于已收集的输入信号，推断本次需求的 flow_profile（哪些步骤可跳过），展示给用户确认后写入 state.json。

**进入本步前必须已完成 1.1 第四步（MasterGo AskUserQuestion）。** 尚未询问设计稿时，先问，禁止把「还没提问」写成「用户未提供 MasterGo 设计稿链接」。尚未询问标准 PRD 时，先回到 1.1 第二步，禁止把 DDP `prd` 写成已确认的 PRD 地址。

**推断规则（LLM 综合判断，以下为参考信号）：**

| 信号 | 推断 |
|------|------|
| 1.1 用户已粘贴 MasterGo 链接 | `skip_mastergo=false`（默认开） |
| 1.1 用户选了「本次无设计稿」或明确「跳过」 | `skip_mastergo=true` |
| 尚未询问 MasterGo | **禁止推断 skip**，回到 1.1 第四步 |
| DDP 标题+描述 < 200 字且用户确认没有 PRD（未贴标准 PRD，且第 3 步选了「本次无 PRD」） | `skip_prd_parse=true` |
| 需求描述为单文件改动 / bug fix / 纯逻辑修改 | `skip_feature_plan=true`, `skip_scaffold=true` |
| 用户主动声明"小需求"/"快速修改" | 建议全部 skip |

**展示确认**：直接调用 `AskUserQuestion`（禁止用纯文本问 yes/修改，禁止只输出「现在确认流程配置」后结束本轮）。MasterGo 为关时，question 里只能写「用户已跳过设计稿」，**禁止**写「未提供链接 / 未检测到链接」。

```json
{
  "questions": [{
    "question": "流程配置（根据需求规模推断）：PRD 裁剪 {开/关}，MasterGo {开/关}，功能拆分 {开/关}，代码骨架 {开/关}。确认采用该配置，还是需要修改？",
    "header": "流程配置",
    "options": [
      { "label": "按推断确认", "description": "采用上面的 skip 组合并写入 flow_profile" },
      { "label": "需要修改", "description": "接着选择一种场景，或自行说明要跳过的步骤" }
    ]
  }]
}
```

- 「按推断确认」→ 按展示的推断写入 state.json：
  ```bash
  bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/state-update.sh --set-json flow_profile \
    '{"skip_prd_parse":false,"skip_mastergo":true,"skip_feature_plan":false,"skip_scaffold":false}'
  ```
- 「需要修改」→ 插件会立刻再弹出场景卡。收到下一条消息 `用户选择了：需要修改；{场景或说明}` 后**立刻**写入 flow_profile，禁止再空等用户打字、禁止只输出「请说明要改哪些」后结束本轮。场景语义：
  - `按刚才的推断确认` → 与「按推断确认」相同
  - `全流程都走` → 四项 skip 均为 false
  - `仅跳过设计稿` → 仅 `skip_mastergo=true`
  - `小改动精简流程` → `skip_prd_parse/skip_feature_plan/skip_scaffold=true`，`skip_mastergo` 仍按推断
  - 其它自由文本 → 按语义映射到四个 skip 字段，不确定的项保持推断值

若所有项均为 false（全流程执行），仍需写入 flow_profile（显式记录决策）。

---

**1.3 并发数据获取**

**flow_profile 跳过检查（PRD 裁剪）：** 若 `skip_prd_parse=true`，跳过 Task A（Cooper 下载+裁剪）及步骤 1.4（LLM 精裁）、**基于 Cooper PRD 的** 1.5 澄清。**不跳过 prd-spec**，也**不因 skip_prd_parse 而跳过 MasterGo**。

1. **MasterGo（仅当 `skip_mastergo=false` 且用户提供了设计稿链接）**
   先跑 Task B（`get-dsl.sh`，见下方 Task B 命令），再：
   ```bash
   bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/mastergo/gen-index.sh \
     --ui-dir "openspec/changes/{req_name}/ui"
   ```
   失败处理同步骤 1.5 的设计稿失败 `AskUserQuestion`（重试 / 跳过设计稿）。`skip_mastergo=true` 或无链接：输出 `⏭ 跳过 MasterGo（flow_profile）`，`record-trace.sh --skip-stage mastergo || true`，不启动 Task B。

2. **轻量 prd-spec（必须产出）**
   记录「这个需求是做什么」。材料优先级：用户说明 > `state.json.ddp_title` > DDP 标题 > `req_name`；若上一步已有 `ui/index.json`，写入功能清单的设计稿列。
   ```bash
   REQ=$(jq -r '.req_name // empty' .dac/state.json)
   TITLE=$(jq -r '.ddp_title // empty' .dac/state.json)
   DDP=$(jq -r '.ddp_id // empty' .dac/state.json)
   bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/prd/write-lite-spec.sh \
     --out "openspec/changes/${REQ}/prd/prd-spec.md" \
     --req-name "$REQ" \
     --title "${TITLE:-$REQ}" \
     --summary "{SUMMARY}" \
     --ddp-id "$DDP"
   ```
   目标文件已有内容时脚本不覆盖。也可按 `templates/tpl-prd-spec.md` 直接 Write 更完整版本。

3. **MasterGo × 代码确认（`skip_mastergo=false` 且存在 `ui_tree.txt` / `ui_dsl.json`）**
   对照设计稿与仓库现有实现（优先 `graphify-out/graph.json`，否则按需求关键词 Grep `lib/`）。只把**不明确**的点拿出来问用户（禁止把已能从设计稿/代码看清的项再问一遍）：
   - 设计稿有、代码无 / 代码有、设计稿无
   - 交互、空态、错误态、文案与现有组件不一致
   - 看不出应复用哪个现有 Widget
   每个不明点用 `AskUserQuestion`（一次一问，选项降低回答成本；可含「按设计稿做」「保持现有代码」「跳过此项」）。收到 `is_error=true` 后静默等待，见 `rules/plugin-interaction.md`。用户回答写入 `prd-clarify.md` 并回填 `prd-spec.md` 对应 §3。若对照后没有不明点，输出 `✓ MasterGo 与现有代码无待确认项`，不问。

4. 收尾：
   ```bash
   bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/record-trace.sh --skip-stage prd_parse || true
   bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/state-update.sh --phase prd-speced --force
   ```
   输出 `⏭ 跳过 PRD 裁剪 + Cooper 澄清（flow_profile）；已用 DDP/用户输入生成轻量 prd-spec.md`，进入阶段 2：项目级规划与功能拆分（先 `opsx:propose` 写提案，再按 flow_profile 决定是否多功能拆分；不要走 1.4）。禁止只说「进入阶段 2 功能拆分」。

**正常路径（skip_prd_parse=false）：** **先跑 Task A，再决定 Task B**（标准表的 DSL 只来自抽出后的有效 UI 链，不能和下载并行）。`skip_mastergo=true` 时不启动 Task B。

**Task A（PRD 下载 + 标准抽出 / 旧裁剪兜底）：** 先 `--check`，再 ingest。`--url` 必须是 `prd_source.url`，**禁止**改填 DDP `prd`。

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/prd/record-prd-source.sh --check
# PRD_SOURCE_KIND=none → 不要调用 ingest，走 skip_prd_parse / 轻量 spec
_PRD_TMP=$(mktemp -d "${TMPDIR:-/tmp}/dac-prd.XXXXXX") && echo "PRD_TMP=$_PRD_TMP" && \
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/timeout-wrapper.sh 120 \
  bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/prd/ingest-prd.sh \
    --url "{prd_source.url} [关键词可选，默认司机端]" \
    --output "$_PRD_TMP/trimmed-prd.md" \
    --raw "$_PRD_TMP/raw-prd.md" \
    --extract "$_PRD_TMP/prd-extract.json" \
    --assets-dir "$_PRD_TMP/assets"
```

> stdout 含 `PRD_TMP=<路径>` 与 `DAC_PRD_MODE=standard|legacy`。步骤 1.4 以 `$PRD_TMP/dac-prd-mode` 为准（与 stdout 一致）。
> 系统临时目录由 OS 自动回收，无需主动清理。
> 超时 120s 由 `timeout-wrapper.sh` 保护，超时后输出 `[DAC-GEN-005]` 错误码。

**Task B（设计稿获取）——必须在 Task A 成功之后：**

- `DAC_PRD_MODE=standard`：从 `$PRD_TMP/prd-extract.json` 收集 `features[].ui_links[]` 中 `valid==true` 的 url（**只要带 `layer_id` 的容器链**）。合作方「设计」文件链、用户随口贴的文件级 MasterGo **不**替代本列。无有效链则不启动 Task B。
- `legacy`：与改造前相同，用户提供了设计稿链接才启动；`skip_mastergo=true` 不启动。

```bash
# standard：把有效 UI 链拼成一段原文交给 get-dsl.sh（脚本会自己抽 http 链接）
_UI_LINKS=$(jq -r '.features[].ui_links[] | select(.valid==true) | .url' "$_PRD_TMP/prd-extract.json" | tr '\n' ' ')
# legacy：仍用用户输入的设计稿链接原文
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/timeout-wrapper.sh 180 \
  bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/mastergo/get-dsl.sh \
    --out-dir "openspec/changes/{req_name}/ui" \
    "<$_UI_LINKS 或用户设计稿链接原文>"
```

> 脚本自动从原文中提取 http/https 链接，多链接时自动并行（最多 3 并发）。
> **部分成功不算 Task B 失败**：至少一条写出 `ui_dsl.json` 则 exit 0，失败目录见各 `ui/NNN/.fetch.log`。全部失败才 exit 1。
> 无有效链接时不要调用（standard 无 `layer_id` 链 = 合法空，不是失败）。

---

**1.4 PRD LLM 处理**

Task A 已在步骤 1.3 完成（Task B 在 A 成功且需要设计稿时随后启动）。先处理 Task A 结果，执行错误检测：

1. 检查 stdout 是否包含 `PRD_TMP=` — 缺失则任务未正常启动
2. 检查 `$PRD_TMP/raw-prd.md` 与 `$PRD_TMP/trimmed-prd.md` 是否存在且非空 — 不存在则 ingest-prd.sh 失败
3. 若失败，展示 stderr 内容，然后使用 `AskUserQuestion` 询问（**禁止**改用纯文本列出选项）：
   ```json
   {
     "questions": [{
       "question": "PRD 下载/裁剪失败，如何处理？",
       "header": "PRD 失败",
       "options": [
         { "label": "重试", "description": "重新启动 Task A" },
         { "label": "提供本地文件路径", "description": "跳过下载，请在下一条消息中提供 markdown 文件路径；用 ingest-prd.sh --input 再走抽出/裁剪" }
       ]
     }]
   }
   ```
   收到 `is_error=true` 后**静默等待**用户消息（见 `rules/plugin-interaction.md`），通过语义理解判断后执行对应分支。

通过后读取 `$PRD_TMP/dac-prd-mode`（`standard` | `legacy`）：

- **standard**：把 `prd-extract.json` / `dac-prd-mode` / 摘要 `trimmed-prd.md` 拷到 `openspec/changes/{req_name}/prd/`（extract 文件名保持 `prd-extract.json`）。**不要** spawn 精裁 sub-agent。向用户展示摘要里的功能点列表（缺名 / 无开发 / 无效 UI 链），确认后 `--phase prd-parsed`，进入 1.5 标准分叉。
- **legacy**：详见 `references/prd-parse-flow.md`（拼接 prd-parse.md → sub-agent 精裁 → 用户确认 → 状态更新）

---

**1.5 需求澄清**

`skip_prd_parse=true` 时不走本节 Cooper 澄清（见 1.3 第 3 步 MasterGo × 代码确认）。

**标准路径（`dac-prd-mode=standard`）：**

1. Task B 若已启动：有任意 `ui_dsl.json` → 继续（即使部分目录失败；列出失败项，**不要**当成整段设计稿失败去阻断）。零条 `ui_dsl.json` → 与下方「设计稿失败」相同选项（重试 / 跳过设计稿）。未启动 Task B（无有效 UI 链）→ 直接继续。
2. **不要**走 `prd-clarify-flow.md` 长清单。写空的 / 极短的 `prd-clarify.md`，`--phase prd-clarified`，小澄清放到 1.6（`prompts/prd-spec-from-extract.md`）。条数 >5 先判「表没写清」，不要开长对话补需求。
3. 进入 1.6。

**旧路径（legacy）：** Task B 已在 Task A 之后完成（如已启动），执行错误检测：

1. 检查 `openspec/changes/{req_name}/ui/` 下是否存在任何 `ui_dsl.json` 文件（`find openspec/changes/{req_name}/ui -name ui_dsl.json | head -1`）— 不存在则设计稿获取失败
2. 若失败且用户提供了设计稿链接，展示错误后使用 `AskUserQuestion` 询问（**禁止**改用纯文本列出选项）：
   ```json
   {
     "questions": [{
       "question": "设计稿获取失败，如何处理？",
       "header": "设计稿失败",
       "options": [
         { "label": "重试", "description": "重新启动 Task B" },
         { "label": "跳过设计稿", "description": "feature-loop 步骤 3 有用户级 fallback" }
       ]
     }]
   }
   ```
   收到 `is_error=true` 后**静默等待**用户消息（见 `rules/plugin-interaction.md`），通过语义理解判断后执行对应分支。
3. 无设计稿链接时（未启动 Task B），直接跳过

旧路径通过后 → 详见 `references/prd-clarify-flow.md`（Task B 结果处理 → sub-agent 出问题清单 → 主会话逐条对话 → 写入 `prd-clarify.md` → 状态更新）

---

**1.6 Spec 生成（sub-agent）**

→ 详见 `references/prd-spec-flow.md`。标准路径输入是 `prd-extract.json`（prompt：`prompts/prd-spec-from-extract.md`）；旧路径仍从 `prd-parse.md` 生成。

---

### 阶段 2：项目级规划与功能拆分

> **进度清单：** 进入本阶段把顶层 `阶段2：项目级规划与功能拆分` 置 `in_progress`；硬校验通过后置 `completed`。本阶段含「提案创建」+（可选）「功能拆分」，不含功能开发（那是阶段 3）。

`skip_feature_plan=true` **只跳过「拆成多个 feature」**，**不跳过 OpenSpec proposal**（与 skip_prd_parse 仍写轻量 spec 同理：跳过的是裁剪/拆分，不是「把这次要改什么记下来」）。

无论 skip 与否，阶段 2 **都必须**执行 feature-plan 流程（Read `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/skills/feature-plan/SKILL.md` 并按其内容执行，不使用 Skill 工具调用）：

- 步骤 2 仍执行 `opsx:propose`，写出 `proposal.md` / `specs/` / `design.md` / `tasks.md`
- `skip_feature_plan=true` 时该 skill **不再**走 LLM 多功能拆分与功能列表确认，改为 `write-single-feature-plan.sh` 把整份 proposal 收成 `feat-01`
- `skip_feature_plan=false` 时走完整拆分（步骤 3–4）

禁止在 skip 时用空 `proposal_scope` 直接 `--phase feature-planned`（那样 codegen 没有文件变更计划）。

按上述 Read 加载的 feature-plan SKILL.md 执行（skip 与否都走这一步，拆分逻辑在其内部判断）。

**feature-plan 流程返回后必须运行硬校验**（不能仅凭描述判定完成）：

```bash
REQ=$(jq -r '.req_name // empty' .dac/state.json)
PHASE=$(jq -r '.phase' .dac/state.json)
if [ -z "$REQ" ] || [ "$PHASE" != "feature-planned" ] || [ ! -s "openspec/changes/$REQ/feature-plan.json" ] || [ ! -s "openspec/changes/$REQ/proposal.md" ]; then
  echo "❌ feature-plan 未完成：phase=$PHASE, feature-plan.json 或 proposal.md 缺失/为空"
  echo "   skip_feature_plan 仍须完成 opsx:propose。若卡在 propose 返回后，见 feature-plan/SKILL.md 步骤 2.2 回流锚点。"
  echo "   请重新 Read ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/skills/feature-plan/SKILL.md 继续步骤 2.3 起的后续动作。"
  exit 1
fi
```

校验通过后再进入阶段 3。

---

### 阶段 3：功能开发（串行执行）

> **进度清单：** 进入本阶段把顶层 `阶段3` 置 `in_progress`，subject 用 `(x/N)` 进度计数（N=待开发功能数，x=已完成数）；每个 feature 追加 **1 条**条目 `F{id} › {name}`，通过更新 subject/activeForm 反映当前步骤（见 `rules/progress-tracking.md`）；每完成一个 feature 更新 `(x/N)`，全部完成后把 `阶段3` 置 `completed`。

**协作模式（`openspec/changes/{req_name}/collab.json` 存在）：**

- 队列过滤：**只**排入 `assignee == 当前 git config user.email` 且 `scripts/collab/guard.sh {id}` 返回 0 的 pending feature。他人 feature 不进本会话队列，MUST NOT 标为 `skipped` 或 `failed`。
- 无可跑：若队列为空但仍有 pending，展示等待原因（缺哪些依赖、需 pull 谁的提交），不启动 feature-loop；用户可选择"结束会话"或"手动重试"。
- 当前用户已完成本人所有指派：展示"你的部分已完成，剩余归属他人"，phase **保持** `feature-loop`（**不**自动流转 `feature-done`；后者仍以全局全部 done 为准）；触发一次本人份额 token 汇总：`bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/cal-req-token-cost.sh || true`。

**单人模式（无 `collab.json`）：** 按拓扑序取第一个 `status=pending` 的 feature 执行，直至全部 done → 自动流转 `feature-done`。`status=skipped`（含规划时标的「无开发」）**不**进入 feature-loop 流程。进入本阶段前确认 `state.json.skipped_features` 已由 `scripts/feature/sync-skipped-from-plan.sh` 写入。若没有 pending（全是无开发/已跳过）：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/state-update.sh --phase feature-done
```

不要空转 feature-loop。然后走 `references/feature-orchestration.md` 3.4 摘要。

→ 详见 `references/feature-orchestration.md`（拓扑排序 → 依次 Read 执行 feature-loop/SKILL.md → 异常处理 → archive）

---

### 状态持久化

> **主会话独占写入**：所有 `state.json` / `feature-plan.json` 变更只在本主编排或 feature-loop 主会话中执行（通过 `state-update.sh`）。Sub-agent（codegen、CR、质量审查）不写入状态文件，仅通过产物文件和返回值反馈结果。详见 DESIGN.md §七（补）。

**工作流事件上报：**

> **接受 / CR 结果 / L2 结果由 Harness 打，禁止在 skill 里补报。**
> 只有用户**拒绝或调整**时，主会话立刻调用 `report-user-gate.sh`（带原话），不要自己拼 jq。
>
> | 何时 | 命令 |
> |---|---|
> | 用户拒绝澄清结论 | `report-user-gate.sh clarify rejected --msg '原话' --reason '摘要'` |
> | 用户拒绝/调整 proposal | `report-user-gate.sh proposal rejected --msg '原话' --reason '摘要'` |
> | 用户改功能列表 | `report-user-gate.sh feature_plan adjusted --msg '原话' --reason '摘要' --adjustment '...'` |
>
> 路径：`bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/report-user-gate.sh ... || true`
>
> 用户点确认后只跑 `state-update.sh --phase ...`，接受事件会自动报（`prd_clarify_accepted` / `proposal_accepted` / `feature_plan_accepted`）。

每个阶段完成后将状态写入 `.dac/state.json`：

```json
{
  "phase": "feature-loop",
  "current_feature_id": "login-page",
  "completed_features": ["shared-network"],
  "skipped_features": [],
  "issues_features": [],
  "created_at": "2026-05-22T10:00:00Z",
  "updated_at": "2026-05-22T11:30:00Z"
}
```

---

### 异常处理

- 功能失败时，自动级联跳过所有依赖该功能的下游功能（详见 `references/feature-orchestration.md` §3.3）。
- 用户选择「忽略」CR 问题时，功能标记为 `done_with_issues` 并记录到 `issues_features`。
- 用户随时可以输入「暂停」，保存当前状态，下次运行 `/gd-ai-coding` 时选择「继续上次」恢复（`in_progress` 功能会被重新执行）。
