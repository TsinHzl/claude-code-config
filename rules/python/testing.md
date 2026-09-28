---
paths:
  - "**/*.py"
  - "**/*.pyi"
---
# Python 测试

> 本文件是对 [common/testing.md](../common/testing.md) 的扩展，包含 Python 特有的测试内容。

## 框架（Framework）

使用 **pytest** 作为测试框架。

## 覆盖率（Coverage）

```bash
pytest --cov=src --cov-report=term-missing
```

## 测试组织（Test Organization）

使用 `pytest.mark` 进行测试分类（Test Categorization）：

```python
import pytest

@pytest.mark.unit
def test_calculate_total():
    ...

@pytest.mark.integration
def test_database_connection():
    ...
```

## 参考（Reference）

参阅技能（Skill）：`python-testing` 以了解详细的 pytest 模式与固件（Fixtures）。
