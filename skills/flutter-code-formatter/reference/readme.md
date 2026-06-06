# Flutter 代码规范化工具 - 使用指南

## 快速开始

输入 `-h` 查看本帮助文档

## 功能概览

自动扫描 Flutter 代码，检测不符合司机端代码规范的写法：
- **色值标准化** - 硬编码色值转为 GOColors 标准色库
- **MediaQuery 优化** - 避免不必要的 Widget 重建
- **Image.asset 迁移** - 统一使用 DiDiImage 组件

## 使用示例

### 示例1：检查单个文件、目录、或者粘贴代码（默认所有规则）

```
/flutter-code-formatter

//引用单个文件
@lib/pages/income_page.dart
引用目录
@lib/src/income_module/
或者输入代码：
【代码片段】

```

### 示例2：基于 Git 仓库路径检查（所有规则）

```
/flutter-code-formatter

请对该工程git diff master ，扫描其变更: [绝对路径]
```


### 示例3: 使用单一规则

```
检查以下文件的【色值标准化问题/MediaQuery 优化/Image.asset 迁移...其中一项】：
@lib/pages/income_page.dart
```