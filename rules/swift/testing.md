---
paths:
  - "**/*.swift"
  - "**/Package.swift"
---
# Swift 测试 (Swift Testing)

> 本文件扩展了 [common/testing.md](../common/testing.md)，增加了 Swift 特有的内容。

## 框架 (Framework)

新测试请使用 **Swift Testing** (`import Testing`)。使用 `@Test` 和 `#expect`：

```swift
@Test("User creation validates email")
func userCreationValidatesEmail() throws {
    #expect(throws: ValidationError.invalidEmail) {
        try User(email: "not-an-email")
    }
}
```

## 测试隔离 (Test Isolation)

每个测试都会获得一个全新的实例 —— 在 `init` 中进行设置（Set up），在 `deinit` 中进行清理（Tear down）。测试之间不允许共享可变状态。

## 参数化测试 (Parameterized Tests)

```swift
@Test("Validates formats", arguments: ["json", "xml", "csv"])
func validatesFormat(format: String) throws {
    let parser = try Parser(format: format)
    #expect(parser.isValid)
}
```

## 覆盖率 (Coverage)

```bash
swift test --enable-code-coverage
```

## 参考 (Reference)

有关基于协议的依赖注入（Dependency Injection）和 Swift Testing 的模拟对象（Mock）模式，请参阅技能（Skill）：`swift-protocol-di-testing`。
