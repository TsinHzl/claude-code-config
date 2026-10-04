# 阶段 1.1：收集输入（完整交互细节）

按以下**固定顺序**逐步收集。DDP ID 为必填起点，验证通过后自动填充 req_name 和版本号。**不要**用 DDP 返回的 `prd` 字段自动当 PRD 去读；先问有没有标准 PRD。

## 第一步（必填）：DDP 需求

使用 `AskUserQuestion` 工具收集（真实的 DDP 链接/ID 由用户在插件内联输入框粘贴，预置选项本身不携带链接内容）：
- question："请提供本次开发关联的 DDP 需求，用于自动填充 req_name、版本号（例如：T-IBT-626806 或 R-IBG-689979）；若不关联 DDP，选「本次无 DDP 需求」。DDP 上的产品文档链接不会自动当作 PRD 去读"
- header："DDP 需求"
- 选项 1「有 DDP 需求」，description："在下一条消息中粘贴 DDP 链接或需求 ID——任务链接优先（T-IBT-xxx，如 T-IBT-626806 或 https://ddp.intra.xiaojukeji.com/issue/story/T-IBT-626806），只有任务能取到版本号；也支持 R-IBG-689979 或纯数字 689979"
- 选项 2「本次无 DDP 需求」，description："降级走手动流程 —— 由我协助确认一个 kebab-case req_name，随后仍会询问是否有标准 PRD"

### 处理选择

AskUserQuestion 的返回值只可能是所选选项的标签、或用户在插件内联输入框输入的自定义文本：
- 用户在插件内联输入框填写了自定义文本 → 取该文本作为 DDP 链接/ID，进入下方「验证流程」
- 返回值为「本次无 DDP 需求」标签 → 先收集 `req_name`（见下方「无 DDP 时的 req_name」），再进入**第二步**（标准 PRD）
- 返回值为「有 DDP 需求」标签本身（即用户点了跳过却未填内容）→ 视为无效输入，提示"请粘贴具体 DDP 链接或需求 ID"，重新询问 1 次；仍为空则降级：先收集 `req_name`，再进入**第二步**

### 验证流程

收到 DDP 链接/ID 后**必须且只能**走下面这条 bash（禁止直接调用 `mcp__ddp__getRequirementDetail` / `mcp__ddp__getIssueDetail` 或 `/ddp` skill）：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/ddp/fetch-ddp-detail.sh --ddp-id "{用户输入}"
```

脚本内部自动识别输入格式（URL / R-IBG-xxx / T-IBT-xxx / 纯数字），格式不合法时 exit 1。`T-IBT-` 走任务详情（`getIssueDetail` + 任务字段 `dpmVersion`），不要对任务 ID 调需求详情接口。

根据 exit code 和 stdout 处理：

- **exit 0**（验证通过）→ 解析 stdout JSON（`{"title","prd","requirementId","releaseVersion","resolvedKind"}`）：
  - 设置 `req_name`（**必须是 PRD 需求英文名，严禁用 DDP id 作为 req_name**）：将中文需求标题 `{title}` 概括为 3-5 词的 kebab-case 英文 slug（去掉 `[MMDD]` 日期前缀、版本号、"司机端/司乘/端"等冗余修饰词，取语义核心），用 `AskUserQuestion` 让用户确认——选项 1「自行命名」(description："在下一条消息中输入自定义 kebab-case 名称（2-51字符，例如：{slug}）")，选项 2「使用建议名称：{slug}」(description："接受 AI 根据需求标题〈{title}〉建议的名称")；用户在输入框中输入名称或点击「使用建议名称」跳过。校验 `^[a-z0-9][a-z0-9]*(-[a-z0-9]+)*$`（2-51字符，kebab-case），未通过则重新收集
  - 记录 `DDP_ID = requirementId`（与 req_name **分离**保存，后续步骤 1.2 中通过 `state-update.sh --ddp-id` 写入 `state.json`，并作为 `report-ddp-binding.sh --ddp-req` 的绑定目标；绝不作为 req_name）。`fetch-ddp-detail.sh` 默认按任务优先解析，`resolvedKind` 为 `"issue"` 时此值已是 `T-IBT-xxx` 任务级 ID
  - `resolvedKind` 为 `"requirement"`（需求暂无关联任务，见 exit 0 处理逻辑）时，追加提示："该需求暂无关联任务，已按需求绑定（暂无法获取版本号）"，不阻断流程
  - 记录 `releaseVersion`（可能为空），后续步骤 1.2 中写入 `state.json`
  - **记下** `prd` 字段（可空），仅供第三步「没有标准 PRD」时展示给用户选。**禁止**此时下载、打开或解析该链接，**禁止**把它当作已确认的 PRD 地址。展示：「需求：{title}，req_name：{req_name}」（不要写「PRD：{prd} 已采用」）
  - req_name 确认后进入**第二步**（标准 PRD）
- **exit 1**（MCP 不可用/网络错误/格式无效）→ 展示 stderr 错误信息，提示重试 1 次；仍失败则降级：先收集 `req_name`，再进入**第二步**
- **exit 2**（需求不存在/无权限）→ 展示「需求 ID 不存在或无权限」，允许重输 1 次或降级：先收集 `req_name`，再进入**第二步**
- **exit 3**（需求关联多个任务，需消歧）→ 解析 stdout JSON（`{"requirementTitle","candidates":[{"id","title"}]}`），用 `AskUserQuestion` 展示候选任务列表（label=任务标题，description=候选的 `id` 即 `T-IBT-xxx`），用户选定后以 `fetch-ddp-detail.sh --ddp-id "{选定的 T-IBT-ID}"` 重新调用一次（此时输入已是明确的 T-IBT，直接命中 exit 0 分支，无需二次消歧），按上方 **exit 0** 分支处理其返回结果

### 无 DDP 时的 req_name

用户选「本次无 DDP 需求」、或 DDP 验证失败降级、且尚未确定 `req_name` 时，使用 `AskUserQuestion` 收集（无选项，直接弹出文本输入框）：
```json
{
  "questions": [{
    "question": "请输入本次需求名称（kebab-case 英文，2-51字符，例如：driver-login）",
    "header": "需求名称"
  }]
}
```

校验格式：`^[a-z0-9][a-z0-9]*(-[a-z0-9]+)*$`（2-51字符，kebab-case）。未通过 → 重新收集。收集完成后进入**第二步**。

## 第二步（必问）：标准 PRD

`req_name` 确认之后**必须**询问。**禁止**因为 DDP 返回了 `prd` 就去读该链接。**禁止**因对话里已有 Cooper 链接而跳过本问。**禁止**在本问得到回答之前调用 `ingest-prd.sh` / `pre-trim.sh` / 读取 Cooper PRD 正文。

使用 `AskUserQuestion`：
- question："本次是否有标准 PRD（Cooper「需求文档梳理」，含司机端需求列表等四段表）？有则在输入框粘贴该知识库链接（须含 knowledge）；没有则选「没有标准 PRD」。不要用 DDP 上的产品文档链接代替"
- header："标准 PRD"
- 选项 1「有标准 PRD」，description："在下一条消息中粘贴 Cooper「需求文档梳理」知识库链接"
- 选项 2「没有标准 PRD」，description："走旧 PRD / 手动贴文档；若要用 DDP 关联链接，下一步再确认，现在不会去读"

### 处理选择

- 用户在输入框粘贴了 Cooper 知识库链接（带 `knowledge`）→ 作为本次 PRD 地址（标准路径候选），**不要**再去读 DDP `prd`；进入**第四步**（MasterGo）。1.2 初始化后必须调用 `scripts/prd/record-prd-source.sh --kind standard --url "{该链接}"`。
- 返回值为「有标准 PRD」标签本身（点了选项却未贴链接）→ 提示粘贴知识库地址，重问 1 次；仍空则视为「没有标准 PRD」，进入**第三步**
- 返回值为「没有标准 PRD」→ 进入**第三步**

`ingest-prd.sh --url` 在 `.dac/state.json` 存在时**硬依赖**这份记录：未调用 `record-prd-source.sh` → `[DAC-SPEC-005]`；`--kind none` 仍去下载 → `[DAC-SPEC-006]`；`--url` 与记录不一致（例如改塞 DDP 产品文档）→ `[DAC-SPEC-008]`。AskUserQuestion 仍由 LLM 弹出，Harness 保证不确认就不能下载。

## 第三步（仅「没有标准 PRD」）：PRD 地址

仅在用户明确没有标准 PRD 时执行。此时才允许使用 DDP 的 `prd`，且须用户确认或另贴，**禁止**静默下载。

若 DDP `prd` 有值，调用 `AskUserQuestion`：
- question："没有标准 PRD。DDP 关联了一篇产品文档，要用它走旧路径，还是另贴 Cooper 链接，或本次不读 PRD？"
- header："PRD 地址"
- 选项 1「使用 DDP 关联的 PRD」，description：展示该 URL（仅展示，用户选此项之前不要去读正文）
- 选项 2「另贴 Cooper 链接」，description："在下一条消息中粘贴带 knowledge 的知识库地址（地址后可追加关键字，默认司机端）"
- 选项 3「本次无 PRD」，description："不下载 Cooper，后续 1.2b 可推断 skip_prd_parse"

处理：
- 「使用 DDP 关联的 PRD」→ 才把 DDP `prd` 当作 Task A 地址；1.2 后 `record-prd-source.sh --kind legacy --url "{该链接}"`；进入**第四步**
- 用户另贴了 knowledge 链接 / 选「另贴 Cooper 链接」后贴了链接 → 作为 Task A 地址；`--kind legacy` 记下该链接；进入**第四步**
- 「本次无 PRD」→ 不下载；1.2 后 `record-prd-source.sh --kind none`；进入**第四步**（供 1.2b 推断 `skip_prd_parse`）

若 DDP `prd` 为空（含无 DDP），询问 Cooper 地址：

```
请输入需求文档地址（地址后可追加关键字，默认司机端）；若本次无 PRD 文档，选「本次无 PRD」：

> 链接必须是带 knowledge 的知识库地址。
```

使用 `AskUserQuestion`，选项「另贴 Cooper 链接」/「本次无 PRD」。若用户已在本步粘贴 knowledge 链接，直接采用。

## 第四步：MasterGo 设计稿链接（必须询问，用户可跳过）

DDP / req_name 确认之后、流程配置（1.2b）之前执行。**禁止**未询问就把「PRD 里没有 MasterGo URL」当成用户无设计稿。

使用 `AskUserQuestion`（与第一步相同的内联输入框模式，禁止纯文本询问）：
- question："请提供 MasterGo 设计稿链接（须含 layer_id，MasterGo 中右键节点 → 复制容器链接；多个用换行或逗号分隔）。若本次无设计稿，选「本次无设计稿」"
- header："MasterGo 设计稿"
- 选项 1「有设计稿」，description："在下一条消息中粘贴 MasterGo 容器链接（须含 layer_id）"
- 选项 2「本次无设计稿」，description："跳过设计稿获取，后续 codegen 不注入 UI DSL"

### 处理选择

- 用户在插件内联输入框粘贴了链接 → 记录为 `MASTERGO_LINKS`，后续 1.2b `skip_mastergo=false`，1.3 启动 Task B
- 返回值为「本次无设计稿」或用户明确说「跳过」→ 1.2b `skip_mastergo=true`，不启动 Task B
- 本轮对话里用户已经贴过含 `layer_id` 的 MasterGo 容器链接 → 直接采用、不再询问
