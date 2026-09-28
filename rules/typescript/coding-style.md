---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
---
# TypeScript/JavaScript 编码规范

> 本文件扩展了 [common/coding-style.md](../common/coding-style.md)，增加了 TypeScript/JavaScript 特有的内容。

## 不可变性（Immutability）

使用展开运算符（spread operator）进行不可变更新：

```typescript
// 错误：直接修改（Mutation）
function updateUser(user, name) {
  user.name = name  // 直接修改了对象！
  return user
}

// 正确：不可变性（Immutability）
function updateUser(user, name) {
  return {
    ...user,
    name
  }
}
```

## 错误处理（Error Handling）

结合 try-catch 使用 async/await：

```typescript
try {
  const result = await riskyOperation()
  return result
} catch (error) {
  console.error('Operation failed:', error)
  throw new Error('Detailed user-friendly message')
}
```

## 输入校验（Input Validation）

使用 Zod 进行基于模式（schema）的校验：

```typescript
import { z } from 'zod'

const schema = z.object({
  email: z.string().email(),
  age: z.number().int().min(0).max(150)
})

const validated = schema.parse(input)
```

## 控制台日志（Console.log）

- 生产代码中禁止使用 `console.log` 语句
- 应改用专业的日志库
- 参见相关钩子（hooks）以了解如何自动检测
