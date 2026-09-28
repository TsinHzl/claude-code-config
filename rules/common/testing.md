---
name: Testing Requirements
description: TDD workflow, 80% coverage target, test types
inclusion: auto
---

# 测试要求

## 最低测试覆盖率：80%

测试类型（全部必选）：
1. **单元测试（Unit Tests）** - 独立函数、工具函数、组件
2. **集成测试（Integration Tests）** - API 端点、数据库操作
3. **端到端测试（E2E Tests）** - 关键用户流程（根据语言选择框架）

## 测试驱动开发（Test-Driven Development）

强制工作流：
1. 先写测试（红灯/RED）
2. 运行测试 - 应该失败（FAIL）
3. 编写最简实现（绿灯/GREEN）
4. 运行测试 - 应该通过（PASS）
5. 重构（改进/IMPROVE）
6. 验证覆盖率（80%+）

## 测试失败排查

1. 使用 **tdd-guide** 智能体（Agent）
2. 检查测试隔离性
3. 验证 Mock 是否正确
4. 修复实现代码，而非测试代码（除非测试代码本身有误）

## 智能体（Agent）支持

- **tdd-guide** - 在开发新功能时主动（PROACTIVELY）使用，强制执行“先写测试”原则
