---
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
---
# Go 编程风格规范（Go Coding Style）

> 本文件是对 [common/coding-style.md](../common/coding-style.md) 的扩展，增加了 Go 语言特定的内容。

## 格式化（Formatting）

- 强制使用 **gofmt** 和 **goimports** —— 不进行代码风格争论。

## 设计原则（Design Principles）

- 接受接口（Interfaces），返回结构体（Structs）。
- 保持接口精简（通常包含 1-3 个方法）。

## 错误处理（Error Handling）

始终通过上下文包装（wrap）错误：

```go
if err != nil {
    return fmt.Errorf("failed to create user: %w", err)
}
```

## 参考资料（Reference）

有关完整的 Go 语言惯用法和模式，请参阅技能（Skill）：`golang-patterns`。
