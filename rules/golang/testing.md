---
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
---
# Go 测试（Testing）

> 本文件扩展了 [common/testing.md](../common/testing.md)，增加了针对 Go 语言的特定内容。

## 测试框架

使用标准的 `go test` 并采用**表驱动测试（Table-driven tests）**。

## 竞态检测（Race Detection）

运行测试时务必带上 `-race` 标志：

```bash
go test -race ./...
```

## 测试覆盖率（Coverage）

```bash
go test -cover ./...
```

## 参考

请参阅技能（Skill）：`golang-testing` 以获取详细的 Go 测试模式与辅助工具。
