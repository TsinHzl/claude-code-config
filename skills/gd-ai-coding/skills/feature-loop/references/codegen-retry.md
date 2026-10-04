# 步骤 4.4 补充：Layer 2 硬性失败（exit 1）重试流程

1. 保存 `post-codegen-check.sh` 的完整输出到变量 `$POST_CHECK_OUTPUT`

2. 回滚出错文件到 codegen 前的状态（`git checkout -- <files>`），避免在错误基础上叠加修复

3. 构建重试上下文并组装裁剪后的 prompt：

   ```bash
   # 解析错误信息，生成 .retry_context.json
   bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/feature/build-retry-context.sh $FEAT_ID "$POST_CHECK_OUTPUT"
   # 组装重试 prompt（ZONE C 自动裁剪：省略 ui_dsl/spec-slice/design，追加错误上下文）
   RETRY_PROMPT=$(bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/feature/assemble-codegen-prompt.sh $FEAT_ID --retry)
   ```

   > **裁剪策略**：当错误类型为 dart analyze / 命名违规时，ZONE C 省略 spec-slice、design.md、ui_dsl.json（节省 5-12K tokens）。
   > 当错误类型包含文件缺失（DAC-GEN-008）或未修改（DAC-GEN-004）时，保留完整 ZONE C（`needs_full_context: true`）。
   > ZONE A+B 始终不变 → 前缀缓存命中。

4. 启动新的 codegen sub-agent（Edit 修复模式：Read 出错文件 → 定位错误行 → Edit 修复，不重写整个文件。相同 ZONE A+B 前缀 → 缓存命中）

5. 修复完成后重新运行 Layer 2 验证：`feature/feature-harness.sh $FEAT_ID post-codegen`

6. 记录本次重试：`audit-log.sh $FEAT_ID "RETRY:N" "codegen-fix"`

7. 重试次数由 Harness `--check-retry-count` 统一控制（exit 2 阻断），本流程不做独立计数。收到 exit 2 时：
   - 更新 feature-plan.json：`"status": "failed"`
   - 记录：`audit-log.sh $FEAT_ID "STATUS:FAILED" "Layer2 exceeded max retries"`
   - 向用户展示最后一次的错误详情，等待人工介入
