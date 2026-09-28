---
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
---
# Go 模式 (Go Patterns)

> 本文件是对 [common/patterns.md](../common/patterns.md) 的扩展，包含了 Go 语言特有的模式内容。

## 函数式选项 (Functional Options)

```go
type Option func(*Server)

func WithPort(port int) Option {
    return func(s *Server) { s.port = port }
}

func NewServer(opts ...Option) *Server {
    s := &Server{port: 8080}
    for _, opt := range opts {
        opt(s)
    }
    return s
}
```

## 小接口 (Small Interfaces)

在调用的位置定义接口，而不是在实现的位置。

## 依赖注入 (Dependency Injection)

使用构造函数（Constructor functions）来注入依赖：

```go
func NewUserService(repo UserRepository, logger Logger) *UserService {
    return &UserService{repo: repo, logger: logger}
}
```

## 参考 (Reference)

请参阅技能（Skill）：`golang-patterns`，以获取更全面的 Go 模式，涵盖并发、错误处理和包组织等内容。
