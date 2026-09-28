---
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
---
# Go 安全 (Go Security)

> 本文件在 [common/security.md](../common/security.md) 的基础上扩展了 Go 特有的安全内容。

## 凭据管理 (Secret Management)

```go
apiKey := os.Getenv("OPENAI_API_KEY")
if apiKey == "" {
    log.Fatal("OPENAI_API_KEY not configured")
}
```

## 安全扫描 (Security Scanning)

- 使用 **gosec** 进行静态安全分析：
  ```bash
  gosec ./...
  ```

## 上下文与超时 (Context & Timeouts)

始终使用 `context.Context` 进行超时控制：

```go
ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
defer cancel()
```
