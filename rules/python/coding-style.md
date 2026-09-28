---
paths:
  - "**/*.py"
  - "**/*.pyi"
---
# Python 编码规范 (Python Coding Style)

> 本文件在 [common/coding-style.md](../common/coding-style.md) 的基础上扩展了 Python 特定的内容。

## 标准 (Standards)

- 遵循 **PEP 8** 规范
- 在所有函数签名中使用 **类型注解 (Type Annotations)**

## 不可变性 (Immutability)

优先使用不可变数据结构：

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class User:
    name: str
    email: str

from typing import NamedTuple

class Point(NamedTuple):
    x: float
    y: float
```

## 格式化 (Formatting)

- 使用 **black** 进行代码格式化
- 使用 **isort** 进行导入排序
- 使用 **ruff** 进行代码检查 (Linting)

## 参考 (Reference)

有关完整的 Python 惯用法和模式，请参阅技能 (Skill)：`python-patterns`。
