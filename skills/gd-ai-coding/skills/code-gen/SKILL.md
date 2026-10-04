---
name: dac-code-gen
description: Flutter code generation — forwarding entry, actual logic lives in dac-feature-loop step 4.
argument-hint: "[feature_id]"
user-invocable: false
metadata:
  openclaw:
    emoji: "⚡"
---

# dac-code-gen — 转发入口

代码生成由 `dac-feature-loop` 步骤 4 内联执行（Sub-agent 模式）。

如需生成或重新生成某功能代码，请对主编排说「执行 feature-loop {feat_id}」（dac-code-gen 为内部转发入口，不可直调）。

→ 执行细节见 `skills/feature-loop/references/codegen-flow.md`
