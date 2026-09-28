---
name: Security Guidelines
description: Mandatory pre-commit security checks, secret management, response protocol
inclusion: always
---

# 安全指南（Security Guidelines）

## 强制安全检查（Mandatory Security Checks）

在进行任何提交（commit）之前：
- [ ] 无硬编码密钥（API 密钥、密码、令牌/tokens）
- [ ] 所有用户输入均已验证
- [ ] 防止 SQL 注入（使用参数化查询）
- [ ] 防止 XSS 跨站脚本攻击（对 HTML 进行净化/sanitized）
- [ ] 已启用 CSRF 跨站请求伪造保护
- [ ] 身份验证（Authentication）/ 授权（Authorization）已验证
- [ ] 所有端点（endpoints）均设有速率限制（Rate limiting）
- [ ] 错误消息不会泄露敏感数据

## 密钥管理（Secret Management）

- 严禁在源代码中硬编码密钥（secrets）
- 务必使用环境变量（environment variables）或密钥管理器（secret manager）
- 在启动时验证所需密钥是否存在
- 轮换（Rotate）任何可能已泄露的密钥

## 安全响应协议（Security Response Protocol）

如果发现安全问题：
1. 立即停止（STOP）操作
2. 使用 **security-reviewer** 智能体（Agent）
3. 在继续之前修复关键（CRITICAL）问题
4. 轮换任何已泄露的密钥
5. 审查整个代码库以查找类似问题
