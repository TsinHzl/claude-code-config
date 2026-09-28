---
paths:
  - "**/*.py"
  - "**/*.pyi"
---
# Python 安全规范 (Python Security)

> 本文件是对 [common/security.md](../common/security.md) 的 Python 特定内容补充。

## 密钥管理 (Secret Management)

```python
import os
from dotenv import load_dotenv

load_dotenv()

api_key = os.environ["OPENAI_API_KEY"]  # 如果缺失则抛出 KeyError
```

## 安全扫描 (Security Scanning)

- 使用 **bandit** 进行静态安全分析：
  ```bash
  bandit -r src/
  ```

## 参考 (Reference)

参见技能（Skill）：`django-security` 获取 Django 特定的安全指南（如适用）。
