# Codex 独立角色编排

Codex 运行时必须通过 `scripts/agents/codex-agent-gate.sh` 验证角色定义、`multi_agent` 能力与认证状态，再通过 `scripts/agents/run-codex-role.sh` 启动独立 `codex exec` 会话。任何门禁失败都必须输出 `BLOCKED` 并停止当前步骤，禁止由主会话自审、自测或代写角色结论。

## 角色映射

| 流程职责 | Codex 角色 | 运行权限 |
|---|---|---|
| PRD / OpenSpec 需求回溯与规划核验 | `requirement-gap-checker` | `read-only` |
| 范围内代码生成与构建错误修复 | `code-generator` | `workspace-write` |
| TDD 测试用例与场景生成 | `test-case-generator` | `workspace-write`（仅 allowlist） |
| UI / 交互场景独立验证 | `test-case-verifier` | `read-only` |
| 代码、需求符合性和安全审查 | `code-reviewer` | `read-only` |

## 调用协议

Codex 主会话必须先将任务输入写入工作区内的临时 prompt 文件，再按以下方式运行目标角色：

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/agents/run-codex-role.sh \
  --role <role> \
  --cwd "$(pwd)" \
  --prompt-file <workspace-prompt-file> \
  --output-file <workspace-output-file> \
  --allowed-paths-file <workspace-allowlist-file>
```

`code-generator` 与 `test-case-generator` 的调用必须提供 allowlist：每行是工作区相对文件路径或以 `/**` 结尾的目录前缀。执行器会在运行前后拒绝 allowlist 外的任何工作树改动。角色的输出文件是主会话后续解析的唯一结果；主会话不得基于自身推理补写 `PASS`、`clean` 或需求覆盖结论。`BLOCKED`、命令非零退出或缺失输出文件均表示当前流程不可继续。

## 角色边界

`requirement-gap-checker` 不修改代码。`test-case-generator` 不验证自身生成的 UI 场景。`test-case-verifier` 不修改测试或业务代码。`code-reviewer` 不修改代码、提交或推送。`code-generator` 只可写入已明确的 `code-scope`，构建错误不能定位时必须 `BLOCKED`。
