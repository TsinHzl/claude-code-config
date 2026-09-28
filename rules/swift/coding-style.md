---
paths:
  - "**/*.swift"
  - "**/Package.swift"
---
# Swift 编程风格 (Coding Style)

> 本文件在 [common/coding-style.md](../common/coding-style.md) 的基础上扩展了 Swift 特有的内容。

## 格式化 (Formatting)

- 使用 **SwiftFormat** 进行自动格式化，使用 **SwiftLint** 进行风格强制。
- `swift-format` 已集成在 Xcode 16+ 中，可作为替代方案。

## 不可变性 (Immutability)

- 优先使用 `let` 而非 `var` —— 默认将所有内容定义为 `let`，仅在编译器要求时才更改为 `var`。
- 默认使用具有值语义（Value Semantics）的 `struct`；仅在需要标识（Identity）或引用语义（Reference Semantics）时才使用 `class`。

## 命名规范 (Naming)

遵循 [Apple API 设计指南 (API Design Guidelines)](https://www.swift.org/documentation/api-design-guidelines/)：

- 在使用点保持清晰 —— 省略不必要的词汇。
- 根据方法和属性的角色而非其类型进行命名。
- 对于常量，优先使用 `static let` 而非全局常量。

## 错误处理 (Error Handling)

使用有类型抛出（Typed Throws，Swift 6+）和模式匹配 (Pattern Matching)：

```swift
func load(id: String) throws(LoadError) -> Item {
    guard let data = try? read(from: path) else {
        throw .fileNotFound(id)
    }
    return try decode(data)
}
```

## 并发 (Concurrency)

启用 Swift 6 严格并发检查。优先选择：

- 使用 `Sendable` 值类型进行跨隔离边界的数据传输。
- 使用 Actors 处理共享的可变状态。
- 优先使用结构化并发 (Structured Concurrency，如 `async let`、`TaskGroup`)，而非非结构化的 `Task {}`。
