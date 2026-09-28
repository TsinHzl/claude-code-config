---
name: Common Patterns
description: Skeleton projects, repository pattern, API response format
inclusion: auto
---

# 通用模式 (Common Patterns)

## 骨架项目 (Skeleton Projects)

在实现新功能时：
1. 寻找经过实战检验的骨架项目 (Skeleton projects)
2. 使用并行智能体 (Agents) 来评估选项：
   - 安全性评估 (Security assessment)
   - 可扩展性分析 (Extensibility analysis)
   - 相关性评分 (Relevance scoring)
   - 实施计划 (Implementation planning)
3. 克隆最匹配的项目作为基础
4. 在经过验证的结构中进行迭代

## 设计模式 (Design Patterns)

### 仓储模式 (Repository Pattern)

将数据访问封装在一致的接口背后：
- 定义标准操作：`findAll`、`findById`、`create`、`update`、`delete`
- 具体实现处理存储细节（数据库、API、文件等）
- 业务逻辑依赖于抽象接口，而不是存储机制
- 支持轻松切换数据源，并通过模拟对象 (Mocks) 简化测试

### API 响应格式 (API Response Format)

为所有 API 响应使用一致的外壳 (Envelope)：
- 包含成功/状态指示器 (Success/status indicator)
- 包含数据负载 (Data payload)（出错时可为空）
- 包含错误消息字段 (Error message field)（成功时可为空）
- 包含分页响应的元数据（`total`、`page`、`limit`）
