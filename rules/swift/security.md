---
paths:
  - "**/*.swift"
  - "**/Package.swift"
---
# Swift 安全规范 (Swift Security)

> 本文件扩展了 [common/security.md](../common/security.md)，增加了 Swift 特定的安全内容。

## 密钥管理 (Secret Management)

- 对于敏感数据（令牌、密码、密钥），请使用 **Keychain 服务 (Keychain Services)** —— 严禁使用 `UserDefaults`
- 使用环境变量或 `.xcconfig` 文件管理构建时密钥 (Build-time secrets)
- 严禁在源码中硬编码密钥 —— 反编译工具可以轻易提取它们

```swift
let apiKey = ProcessInfo.processInfo.environment["API_KEY"]
guard let apiKey, !apiKey.isEmpty else {
    fatalError("API_KEY not configured")
}
```

## 传输安全 (Transport Security)

- App 传输安全 (ATS) 默认强制开启 —— 请勿禁用
- 对关键端点使用证书固定 (Certificate Pinning)
- 验证所有服务器证书

## 输入验证 (Input Validation)

- 在显示前清理所有用户输入，以防止注入 (Injection)
- 使用 `URL(string:)` 并进行验证，而不是强制解包 (Force-unwrapping)
- 在处理来自外部源（API、深层链接、剪贴板）的数据前进行有效性验证
