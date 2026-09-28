---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
---
# TypeScript/JavaScript 安全规范 (Security)

> 本文件是对 [common/security.md](../common/security.md) 的补充，包含针对 TypeScript/JavaScript 的特定内容。

## 密钥管理 (Secret Management)

```typescript
// 严禁：硬编码密钥
const apiKey = "sk-proj-xxxxx"

// 推荐：使用环境变量
const apiKey = process.env.OPENAI_API_KEY

if (!apiKey) {
  throw new Error('OPENAI_API_KEY not configured')
}
```

## 智能体支持 (Agent Support)

- 使用 **security-reviewer** 技能（Skill）进行全面的安全审计
