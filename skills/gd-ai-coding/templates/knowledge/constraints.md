# 项目约束积累

> 本文件由 `knowledge/extract-constraints.sh` 自动追加，每次 CR 发现问题后更新。
> 在每次 `dac-code-gen` 执行前作为上下文前缀注入，确保已知约束不被重复犯错。

<!-- 约束条目将在此处自动追加，格式如下：

## [YYYY-MM-DD] {feature_id} — 问题类别

**问题**：具体问题描述
**约束**：应遵循的规范或修复方式
**来源**：cr-report.md {feature_id}

-->

## [2026-05-20] order_detail — 依赖注入

1. [架构] `lib/features/order/data/order_repository_impl.dart` — 未通过 DI 容器注册 HttpClient，直接 new 实例
   - **约束**：所有外部依赖必须在 `lib/core/di/injection.dart` 中声明并通过 GetIt 注册
   - **来源**：cr-report.md order_detail

2. [命名] `lib/features/order/presentation/pages/order_page.dart` — State 类命名不符合规范
   - **约束**：StatefulWidget 的 State 类必须以 `_${WidgetName}State` 命名
   - **来源**：cr-report.md order_detail
