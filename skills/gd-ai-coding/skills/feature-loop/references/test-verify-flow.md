# 步骤 4.5：测试用例生成与验证（Sub-agent，角色隔离）

> Layer 2.5（design.md 决策5：不重排现有三层编号，插入在 Layer2 静态分析与 Layer3 CR 之间）。
> 逻辑/数据类需求点生成真实可执行测试并跑 `flutter test`；UI/交互类需求点生成结构化场景清单，
> 由**独立** sub-agent 推理判断 pass/fail（design.md 决策4：与生成场景清单的 sub-agent 角色隔离，
> 防止自证偏差）。任一分支失败 → 打回步骤 4 codegen 重试，独立计数器与 Layer2 的 3 次重试互不影响
> （design.md 决策3）。

## 4.5.0 前置环境检查

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/pre-test-env-check.sh $FEAT_ID
```

- exit 0：目标 Flutter 项目 `pubspec.yaml` 已声明 `flutter_test`，且声明 `mocktail` 或 `mockito` → 继续 4.5.1
- exit 1：缺失依赖声明（`[DAC-GEN-012]`）→ 向用户报告缺失的具体依赖名，终止当前功能循环
  （不计入 test_verify 重试计数——这是环境问题，不是代码缺陷，避免误判触发无效重试）

## 4.5.1 生成测试用例（Sub-agent）

> 与步骤 4.3/5.1 的 codegen/CR prompt 不同，本环节输入体量小（预切片后的需求章节 + code-scope 表格 +
> 本次改动的代码文件），不需要 ZONE A/B/C 分层与前缀缓存优化，主 agent 直接 Read 后拼装 Agent prompt
> 即可，无需新增专用 assemble 脚本。

读取 `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/prompts/test-case-generator.md` 定义的角色，连同以下文件完整内容一并作为 prompt 传入。Claude Code 使用 `Agent`；Codex 必须先由当前 feature 的测试产出计划生成精确 allowlist（`test-cases.md`、每一个计划测试文件与 code-scope 中明确允许的测试文件），不得使用 `test/**` 等目录通配，再按 `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/references/codex-agent-orchestration.md` 启动 `test-case-generator`；角色门禁失败、输出 `BLOCKED` 或 allowlist 外写入时终止，禁止主会话生成测试用例：
- `features/{feat_id}/spec-slice.md`（关联需求点）
- `features/{feat_id}/code-scope.md`
- 本次 codegen 实际生成/修改的代码文件完整内容

```
Agent({
  description: "TestGen: {feat_name}",
  prompt: "<test-case-generator.md 角色定义 + 上述文件内容>",
  agentType: "general-purpose",
  run_in_background: false
})
```

产出写入 `features/{feat_id}/`：
- `test-cases.md` — 需求点类型判定表 + 生成的逻辑类测试文件清单 + UI/交互类场景清单（WHEN/THEN）
- 逻辑/数据类的实际测试文件写入目标 Flutter 项目 `test/` 目录（路径见 `test-cases.md` 清单）

## 4.5.2 逻辑/数据类：实际执行

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/run-generated-tests.sh $FEAT_ID
```

对 4.5.1 清单中列出的每个测试文件执行 `flutter test <path>`，汇总退出码：
- exit 0：全部通过
- exit 1：存在失败用例（`[DAC-GEN-013]`），输出捕获的 `flutter test` 失败详情

> 若本 feature 无逻辑/数据类需求点（`test-cases.md` 清单为空），跳过本节，视为通过。

## 4.5.3 UI/交互类：独立 Sub-agent 推理判断

**仅当 4.5.1 判定表中存在 UI/交互类场景时执行**，否则跳过本节视为通过。

读取 `${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/prompts/test-case-verifier.md` 定义的角色（Claude Code 必须是与 4.5.1 不同的 `Agent` 调用；Codex 必须是不同的 `test-case-verifier` 独立会话），不得复用生成角色的会话或传入 4.5.1 的推理历史。Codex 门禁失败或输出 `BLOCKED` 时终止，禁止主会话验证替代。两种运行时均连同以下文件完整内容一并作为 prompt 传入：
- `features/{feat_id}/test-cases.md` 中的 UI/交互类场景清单部分（仅场景清单，不传入判定表其余内容，
  避免验证者看到生成者的类型判定理由而产生锚定）
- 本次 codegen 实际生成/修改的代码文件完整内容

```
Agent({
  description: "TestVerify: {feat_name}",
  prompt: "<test-case-verifier.md 角色定义 + 上述文件内容>",
  agentType: "general-purpose",
  run_in_background: false
})
```

sub-agent 返回的 `Verdict`：
- `PASS`：全部场景 pass → 视为通过
- `FAIL`：存在 fail 或"无法判断" → 视为失败，记录具体场景

## 4.5.4 汇总产出 `test-report.md`

无论 4.5.2/4.5.3 结果如何，写入 `features/{feat_id}/test-report.md`：

```markdown
## 测试验证报告

### 逻辑/数据类（flutter test 实际执行）
- 结果：PASS / FAIL
- （FAIL 时列出失败用例文件:行号 + 错误摘要）

### UI/交互类（sub-agent 推理判断）
- 结果：PASS / FAIL / 无适用场景
- （FAIL 时列出未通过场景名称 + 判定依据）

### Verdict
PASS（两轨均通过或均无适用项）/ FAIL（任一轨失败）
```

## 4.5.5 失败处理：打回步骤 4 重试

若 `test-report.md` 的 Verdict 为 `FAIL`：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/test-verify-loop-guard.sh increment $FEAT_ID
```

- exit 0（未超限，≤3次）：将 `test-report.md` 中的失败详情作为独立上下文追加进重新执行的步骤 4.3
  codegen sub-agent prompt（**不复用** `assemble-codegen-prompt.sh --retry` 的 `.retry_context.json`
  通道——该通道的错误码提取逻辑是 Layer2 dart analyze 专用格式，语义不兼容），修复后回到 4.5.0 重新
  跑一遍环境检查+生成+执行+验证
- exit 2（超限，第4次）：`test-verify-loop-guard.sh` 内部已通过 `state-update.sh` 将该 feature 状态
  置为 `failed`，向用户展示最后一次 `test-report.md` 的失败详情，终止当前功能循环，**不进入步骤 5**

若 Verdict 为 `PASS`：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/checks/test-verify-loop-guard.sh reset $FEAT_ID
```

重置计数后进入步骤 5（CR）。
