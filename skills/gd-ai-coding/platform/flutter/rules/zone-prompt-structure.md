# Codegen Prompt 结构（缓存优化）

```
┌─────────────────────────────────────────────┐
│ ZONE A — 编码规范（静态前缀，跨 feature 缓存） │
│  flutter-architecture.md                     │
│  flutter-style.md                            │
│  flutter-performance.md (page/component)     │
│  flutter-widgets.md     (page/component)     │
├─────────────────────────────────────────────┤
│ ZONE B — 项目约束（snapshot 锁定，同轮次稳定）  │
│  constraints.snapshot.md                     │
│  error-patterns.snapshot.md                  │
├─────────────────────────────────────────────┤
│ ZONE C — 当前功能输入（每 feature 不同）       │
│  code-scope.md                               │
│  spec-slice.md                               │
│  design.md                                   │
│  ui_dsl.json + ui_tree.txt (如有)            │
├─────────────────────────────────────────────┤
│ 执行指令                                      │
└─────────────────────────────────────────────┘
```

同类型 feature 的 ZONE A+B 完全一致 → API 前缀缓存命中（token 成本降 90%）。
