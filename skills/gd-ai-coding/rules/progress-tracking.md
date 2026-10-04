# 进度清单规范（运行时可视化）

面向**目标 Flutter 项目运行时**：`/gd-ai-coding` 主编排执行全流程时，维护一份常驻的**会话进度清单**，
让使用者随时看到「有哪些步骤、当前在哪一步、哪些已完成」。

> 本规范仅服务运行时 UX，与本仓库自身元开发的 OpenSpec `tasks.md` 追踪、以及 `dac-notes.md`
> （Implementation Notes 记录）**无关**，勿混淆。

## 一、工具无关

用**当前环境可用的会话任务清单工具**建条目并流转状态：

- 标准 Claude Code / superpowers 环境 → `TodoWrite`
- 否则（如 FleetView 环境）→ `TaskCreate` / `TaskUpdate`
- Codex / DSH 等无任务工具的环境 → 纯文本阶段声明（每阶段开始/完成各一行，如 `> ✅ 阶段1/3 完成`）

两者语义等价：都是**扁平单会话清单**，都渲染 `pending` / `in_progress` / `completed`。
指令中不硬编码单一工具名，按当前环境可用者调用。若两者都不可用，静默跳过（不阻断流程）。

## 二、条目结构（精简扁平）

顶层 4 条 + 阶段 1 子步 3 条 + 每 feature 1 条。总条目数 = 7 + N（N 为功能数）。

- 顶层阶段：`初始化` / `阶段1：需求分析` / `阶段2：项目级规划与功能拆分` / `阶段3：功能开发 (x/N)`
- 阶段 1 子步：前缀 `阶段1 › `，共 3 条：`数据收集`、`LLM 处理`、`Spec 确认`
- feature 条目：前缀 `F{feat_id} › `，**每 feature 仅 1 条**，通过更新 subject/activeForm 反映当前步骤

示例：

```
✓ 初始化
● 阶段1：需求分析
  ✓ 阶段1 › 数据收集
  ● 阶段1 › LLM 处理
  ○ 阶段1 › Spec 确认
○ 阶段2：项目级规划与功能拆分
○ 阶段3：功能开发 (0/3)
```

阶段 3 进行中：

```
✓ 阶段3：功能开发 (1/3)
  ✓ F1 › shared-network
  ● F2 › login-page [代码生成中]
  ○ F3 › home-page
```

## 三、顶层条目与 phase 映射

启动时（初始化阶段，执行第一个实质步骤前）一次性建 4 条顶层条目。`--resume` 时按下表把已越过的
标 `completed`、当前阶段标 `in_progress`：

| `.dac/state.json` 的 phase | 顶层阶段条目 |
|---|---|
| `init` | 初始化 |
| `prd-parsing` / `prd-parsed` / `prd-clarified` / `prd-specing` / `prd-speced` | 阶段1 |
| `proposal-approved` / `feature-planned` | 阶段2 |
| `feature-loop` / `feature-done` / `done` | 阶段3 |

## 四、各阶段追加与更新规则

| 阶段 | 追加规则 |
|---|---|
| 初始化 | 顶层条目本身，无子步 |
| 阶段1 | 置 `in_progress` 时追加 3 条子步：`阶段1 › 数据收集`（覆盖 1.1~1.3）/ `阶段1 › LLM 处理`（覆盖 1.4~1.5）/ `阶段1 › Spec 确认`（覆盖 1.6） |
| 阶段2 | **委托** feature-plan 子 skill（Read 执行）→ **保持单条目**，不追加内部步骤；主 SKILL.md 硬校验通过后置 `completed` |
| 阶段3 | 开始某 feature 时追加 **1 条**：`F{id} › {feat_name}`；通过 **TaskUpdate 修改 subject/activeForm** 反映当前步骤（如 `[代码生成中]`、`[CR 校验中]`）；完成时 status=`completed`；顶层条目 subject 随完成数更新 `(x/N)` |

### Feature 条目 subject 变化示例

| feature-loop 步骤 | subject / activeForm |
|---|---|
| 步骤 0~1 | `F2 › login-page` / activeForm: `加载上下文` |
| 步骤 2~3 | `F2 › login-page` / activeForm: `准备 code-scope` |
| 步骤 4 | `F2 › login-page [代码生成中]` / activeForm: `代码生成中` |
| 步骤 5 | `F2 › login-page [CR 校验中]` / activeForm: `CR 校验中` |
| 步骤 6（完成） | `F2 › login-page [完成]` / status: `completed` |
| 失败 | `F2 › login-page [失败]` / 与 `skipped_features` 对齐 |

## 五、状态流转时机

- 进入某阶段/子步：置 `in_progress`
- 该步产物/动作实际完成（依「产物即事实」判定）：立即置 `completed`，再开始下一步
- **每步单独流转，禁止批量补勾**
- 重试（codegen 最多 3 次、CR 校验）期间：该 feature 条目**保持 `in_progress`，只更新 subject 文案**，不为每次重试新建条目
- 重试超限失败：更新 subject 标注失败，与 state.json 的 `skipped_features` 对齐

## 六、恢复粒度

state.json 只记录 phase 与 feature 级别状态，**不记录 feature 内部步骤级状态**。
`--resume` 重建到「阶段 + feature」粒度：

- 已越过的阶段标 `completed`
- 已完成 feature 补建 1 条 `completed` 条目
- 当前 feature 建 1 条 `in_progress` 条目（从步骤 0 重新执行）

## 七、展示层约束（不可越界）

进度清单是**展示层**，不属于权威状态（权威源见 [state-authority.md](./state-authority.md)）：

- 任何 phase 流转、门禁判定、恢复决策**一律读 `.dac/state.json`**，**绝不读进度清单条目状态**
- 进度清单与 state.json 冲突时：**以 state.json 为准**
- 进度清单更新失败（工具不可用等）：静默跳过，不阻断流程