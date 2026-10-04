# DAC 统一错误码目录

## 格式规范

所有脚本输出的错误信息必须以 `[DAC-{PHASE}-{NNN}]` 前缀开头，便于机器解析和自动恢复。

```
[DAC-PLAN-003] ❌ feature-plan.json schema 校验失败
       ↑              ↑
   错误码前缀      人类可读描述
```

---

## DAC-SPEC — 需求提取阶段

| 错误码 | 描述 | 触发位置 | 恢复步骤 |
|--------|------|---------|---------|
| DAC-SPEC-001 | mcporter 配置文件不存在 | env-checks.sh | 安装 mcporter 并配置 Cooper |
| DAC-SPEC-002 | Cooper Authorization 长度不足 | env-checks.sh | 刷新 API-KEY |
| DAC-SPEC-003 | Cooper baseUrl 配置不正确 | env-checks.sh | 修正 mcporter.json 中的 baseUrl |
| DAC-SPEC-004 | 未识别需求列表 7 个标准列，或解析失败 | parse-standard-prd.py | ingest 走 pre-trim；输入文件缺失则检查路径 |
| DAC-SPEC-005 | 尚未确认标准 PRD（无 prd_source） | record-prd-source.sh / ingest-prd.sh | 先 AskUserQuestion，再 record-prd-source.sh --kind … |
| DAC-SPEC-006 | 用户确认本次无 PRD 仍去下载 Cooper | ingest-prd.sh | 不要 ingest --url；走 skip_prd_parse / 轻量 spec |
| DAC-SPEC-007 | PRD 链接不是带 knowledge 的知识库地址 | record-prd-source.sh | 改贴 Cooper 知识库链接 |
| DAC-SPEC-008 | ingest --url 与已确认的 prd_source 不一致 | ingest-prd.sh | 使用 record 过的 URL，禁止改塞 DDP 产品文档 |

---

## DAC-PLAN — 规划阶段

| 错误码 | 描述 | 触发位置 | 恢复步骤 |
|--------|------|---------|---------|
| DAC-PLAN-001 | prd-spec.md 不存在 | pre-skill-check.sh (feature-plan) | 先完成 /gd-ai-coding 阶段 1 |
| DAC-PLAN-002 | graphify-out/graph.json 不存在 | pre-skill-check.sh (feature-plan) | 先运行 graphify 生成知识图谱 |
| DAC-PLAN-003 | feature-plan.json schema 校验失败 | feature-plan-schema-check.sh | 重新执行 feature-plan 或手动修复 JSON |
| DAC-PLAN-004 | state.json phase 不满足前置条件 | pre-skill-check.sh (feature-plan) | 确认已完成 prd-spec 阶段 |
| DAC-PLAN-005 | 需求覆盖率校验失败（正向或反向 gap） | coverage-check.sh | 补充 feature 的 related_requirements 或新增 feature |
| DAC-PLAN-006 | 协作模式下与其他 in_progress feature 的 proposal_scope 文件集合有交集 | collab/guard.sh | 串行执行；或调整 feature-plan.json 边界降低耦合 |
| DAC-PLAN-007 | feature-plan.json 缺失（非 schema 校验失败） | collab/plan-split.sh 等 | 先执行 feature-plan 生成 plan |

---

## DAC-GEN — 代码生成阶段

| 错误码 | 描述 | 触发位置 | 恢复步骤 |
|--------|------|---------|---------|
| DAC-GEN-001 | code-scope.md 不存在 | pre-skill-check.sh (codegen) | 先完成 feature-loop 步骤 2 |
| DAC-GEN-002 | index.json 中关联的设计稿目录不存在 | pre-skill-check.sh (codegen) | 重新执行 dac-ui-spec 补充设计稿或修正 index.json |
| DAC-GEN-003 | proposal.md 不存在 | pre-skill-check.sh (codegen/feature-loop) | 先执行 feature-plan |
| DAC-GEN-004 | code-scope.md 中 modified_files 未被实际修改 | post-codegen-check.sh | 检查 codegen 是否遗漏了文件修改 |
| DAC-GEN-005 | openspec 操作超时 | timeout-wrapper.sh | 重试或减小功能范围 |
| DAC-GEN-006 | dart analyze 发现 error | post-codegen-check.sh | 修复 Dart 编译错误后重试 |
| DAC-GEN-007 | dart format 检查未通过 | post-codegen-check.sh | 运行 dart format 修复 |
| DAC-GEN-008 | 新增文件未生成 | post-codegen-check.sh | 检查 codegen 输出 |
| DAC-GEN-009 | Layer 2 重试超过 3 次 | feature-loop 步骤 4 | 人工介入修复 |
| DAC-GEN-012 | pubspec.yaml 缺失测试依赖声明（flutter_test/mocktail） | pre-test-env-check.sh | 在 pubspec.yaml 的 dev_dependencies 中补充声明后重试 |
| DAC-GEN-013 | 生成的逻辑/数据类测试执行失败或文件缺失 | run-generated-tests.sh | 修复失败用例或补齐缺失的测试文件后重试 |

---

## DAC-CR — 代码审查阶段

| 错误码 | 描述 | 触发位置 | 恢复步骤 |
|--------|------|---------|---------|
| DAC-CR-001 | codegen 产物文件不存在 | pre-skill-check.sh (code-review) | 先完成 code-gen（feature-loop step 4） |
| DAC-CR-002 | ui_tree.txt 与代码结构不一致 | code-review 步骤 3.5 | 修复 Widget 结构使之匹配设计稿层级 |

---

## DAC-STATE — 状态管理

| 错误码 | 描述 | 触发位置 | 恢复步骤 |
|--------|------|---------|---------|
| DAC-STATE-001 | Lock 文件存在（未完成的状态转换） | state-update.sh | 运行 scripts/recovery.sh --reconcile |
| DAC-STATE-002 | state.json 与 feature-plan.json 状态不一致 | recovery.sh --diagnose | 运行 scripts/recovery.sh --reconcile |
| DAC-STATE-003 | state.json 缺少 req_name 字段 | 各脚本 | 检查 .dac/state.json 完整性 |
| DAC-STATE-004 | state.json JSON 格式损坏 | state-update.sh | 运行 recovery.sh --reconcile 或手动修复 JSON |
| DAC-STATE-005 | 无效 phase 或非法 phase 转换 | state-update.sh | 检查目标 phase 拼写，或使用 recovery.sh --rollback-to 回退 |
| DAC-STATE-010 | 无效 JSON 值（--set-json） | state-update.sh | 检查传入 JSON 语法 |
| DAC-STATE-011 | 未知参数（警告，忽略） | state-update.sh | 检查命令行参数拼写 |
| DAC-STATE-012 | 终态门禁拦截：cr-report.md 不存在 | state-update.sh | 完成 CR 后再流转到 done |
| DAC-STATE-013 | 无效的 feature status | state-update.sh | 检查 status 值是否属于 pending/in_progress/done/failed/skipped |
| DAC-STATE-020 | 协作模式下 assignee 非空且不是当前 git 用户 | collab/guard.sh | 请指派人执行该 feature；或联系发起人改 assignee |
| DAC-STATE-021 | 协作模式下 feature 已被他人 in_progress 认领 | collab/guard.sh | 不要抢认领；等对方完成并 pull 到 status.json=done。`claimed_by == 当前用户` 视为恢复，不触发此码 |

---

## DAC-DEP — 依赖管理

| 错误码 | 描述 | 触发位置 | 恢复步骤 |
|--------|------|---------|---------|
| DAC-DEP-001 | 功能依赖图中存在循环依赖 | dependency-check.sh | 移除或调整依赖关系后重新确认 plan |
| DAC-DEP-002 | 依赖的 feature_id 不存在 | dependency-check.sh | 修正 feature-plan.json 中的 dependencies |
| DAC-DEP-003 | 协作模式下 dependency 的 status.json 不是 done | collab/guard.sh | git pull 依赖方的提交；或等对方完成 |
| DAC-DEP-004 | assign.sh 的目标 feat_id 不存在于 feature-plan.json | collab/assign.sh | 检查 --feat 拼写，或先执行 feature-plan 生成 plan |

---

## 使用规范

1. 所有新建/修改的脚本在输出错误时，**必须**以 `[DAC-XXX-NNN]` 开头
2. 错误码后跟 `❌`（阻断）或 `⚠️`（警告）标识严重程度
3. 错误信息下一行缩进提供恢复建议（以 `   ` 三空格开头）
4. audit-log.sh 记录时使用错误码而非自由文本
