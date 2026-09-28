---
paths:
  - "**/*.py"
  - "**/*.pyi"
---
# Python 模式 (Patterns)

> 本文件在 [common/patterns.md](../common/patterns.md) 的基础上扩展了 Python 特有的内容。

## 协议 (Protocol) 与 鸭子类型 (Duck Typing)

```python
from typing import Protocol

class Repository(Protocol):
    def find_by_id(self, id: str) -> dict | None: ...
    def save(self, entity: dict) -> dict: ...
```

## 将 数据类 (Dataclasses) 用作 数据传输对象 (DTOs)

```python
from dataclasses import dataclass

@dataclass
class CreateUserRequest:
    name: str
    email: str
    age: int | None = None
```

## 上下文管理器 (Context Managers) 与 生成器 (Generators)

- 使用上下文管理器 (`with` 语句) 进行资源管理
- 使用生成器进行惰性求值 (Lazy Evaluation) 和节省内存的迭代

## 参考 (Reference)

请参阅技能 (Skill)：`python-patterns` 以获取包括装饰器 (Decorators)、并发 (Concurrency) 和包结构组织 (Package Organization) 在内的全面设计模式。
