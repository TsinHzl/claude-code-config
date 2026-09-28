---
paths:
  - "**/*.swift"
  - "**/Package.swift"
---
# Swift 模式（Swift Patterns）

> 本文件扩展了 [common/patterns.md](../common/patterns.md)，包含 Swift 特有的内容。

## 面向协议设计（Protocol-Oriented Design）

定义小而集中的协议（Protocols）。使用协议扩展（Protocol Extensions）来提供共享的默认实现：

```swift
protocol Repository: Sendable {
    associatedtype Item: Identifiable & Sendable
    func find(by id: Item.ID) async throws -> Item?
    func save(_ item: Item) async throws
}
```

## 值类型（Value Types）

- 使用结构体（Structs）处理数据传输对象（DTO）和模型（Models）
- 使用带有关联值（Associated Values）的枚举（Enums）来建模不同的状态：

```swift
enum LoadState<T: Sendable>: Sendable {
    case idle
    case loading
    case loaded(T)
    case failed(Error)
}
```

## Actor 模式（Actor Pattern）

使用 Actors 处理共享的可变状态，而不是使用锁（Locks）或调度队列（Dispatch Queues）：

```swift
actor Cache<Key: Hashable & Sendable, Value: Sendable> {
    private var storage: [Key: Value] = [:]

    func get(_ key: Key) -> Value? { storage[key] }
    func set(_ key: Key, value: Value) { storage[key] = value }
}
```

## 依赖注入（Dependency Injection）

通过默认参数注入协议——生产环境使用默认值，测试环境注入 Mock：

```swift
struct UserService {
    private let repository: any UserRepository

    init(repository: any UserRepository = DefaultUserRepository()) {
        self.repository = repository
    }
}
```

## 参考资料（References）

参考技能（Skill）：`swift-actor-persistence` 了解基于 Actor 的持久化模式。
参考技能（Skill）：`swift-protocol-di-testing` 了解基于协议的依赖注入（DI）和测试。
