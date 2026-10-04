# 语言角色映射表

按 Step 1 输出的 `LANGUAGES` / `SHARD_<i>_LANGUAGES` 字段（格式 `ext:count ext:count ...`，按文件数
降序），取**文件数最多的扩展名**作为主导语言，按下表映射为审查角色。多个扩展名文件数相同并列时，
取映射表中靠前者优先。

| 扩展名 | 语言 | 审查角色 |
|---|---|---|
| dart | Dart | Flutter 开发专家 |
| java | Java | Java 开发专家 |
| kt, kts | Kotlin | Kotlin/Android 开发专家 |
| swift | Swift | iOS/Swift 开发专家 |
| m, mm, h | Objective-C | iOS/Objective-C 开发专家 |
| py | Python | Python 开发专家 |
| ts, tsx | TypeScript | 前端/TypeScript 开发专家 |
| js, jsx, mjs, cjs | JavaScript | 前端/Node.js 开发专家 |
| vue | Vue | 前端 Vue 开发专家 |
| go | Go | Go 开发专家 |
| rs | Rust | Rust 开发专家 |
| rb | Ruby | Ruby 开发专家 |
| php | PHP | PHP 开发专家 |
| cs | C# | .NET/C# 开发专家 |
| cpp, cc, cxx, hpp | C++ | C++ 开发专家 |
| c | C | C 开发专家 |
| sh, bash | Shell | Shell/运维脚本专家 |
| sql | SQL | 数据库/SQL 专家 |

**Fallback：** 扩展名未命中上表，或多语言均势且无法判定主导语言 → 角色统一为「全栈代码审查专家」。
