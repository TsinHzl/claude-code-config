---
name: Coding Style
description: Immutability, file organization, error handling, input validation, quality checklist
inclusion: always
---

# 编码规范

## 不可变性（至关重要）

始终创建新对象，切勿修改现有对象：

```
错误:  modify(original, field, value) → 原地修改原对象
正确: update(original, field, value) → 返回包含更改的新副本
```

原理：不可变数据防止隐藏副作用，简化调试，支持安全并发。

## 文件组织

多个小文件 > 少数大文件：
- 高内聚，低耦合
- 通常 200-400 行，上限 800 行
- 从大型模块中提取工具函数
- 按功能/领域组织，而非按类型

## 错误处理

始终进行全面的错误处理：
- 在每个层级显式处理错误
- UI 代码提供用户友好的错误消息
- 服务端记录详细的错误上下文
- 绝不静默吞掉错误

## 输入验证

始终在系统边界处进行验证：
- 处理前验证所有用户输入
- 尽可能使用 Schema 验证
- 快速失败并提供清晰错误消息
- 永远不信任外部数据

## 代码质量清单

- [ ] 代码可读且命名规范
- [ ] 函数短小 (<50 行)
- [ ] 文件聚焦 (<800 行)
- [ ] 无深度嵌套 (>4 层)
- [ ] 妥善的错误处理
- [ ] 无硬编码值
- [ ] 无 Mutation
