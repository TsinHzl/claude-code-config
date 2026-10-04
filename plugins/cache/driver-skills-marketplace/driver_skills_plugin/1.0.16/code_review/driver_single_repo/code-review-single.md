---
name: driver-code-review-single
description: 单仓库 Code Review 专家。通过 Git 溯源提取当前分支 Diff，深度审查逻辑 Bug、边界遗漏、可读性、性能优化及安全隐患，生成包含严重问题、改进建议和优雅重构方案的完整 Code Review 报告。
trigger: 当用户要求对当前仓库/分支进行 Code Review、代码审查、审查本次提交时触发。关键词：code review、代码审查、审查代码、review、代码质量检查。


---

# Skill: code-review-single（单仓库 Code Review 专家）

## 触发条件

- 用户输入包含：code review、代码审查、审查代码、review、代码质量
- 用户要求对当前分支的改动进行审查（单仓库场景）

## 输入参数

- `$ARGUMENTS`：支持三种模式（可组合）：
  - 组件路径（可选，格式 `@组件名/`）
  - commit hash 节点（可选，7-40位十六进制，如 `mf525235`、`abc1234`），diff 该节点到 HEAD
  - commit 数量（可选，从自然语言提取数字，如"最近两次commit"→2、"最近3个"→3）
  - 优先级：commit hash > commit 数量 > 源分支

## Role: 资深研发工程师，执行 Code Review

## Workflow (工作流)

请严格按以下两步顺序执行，第一步必须通过代码/终端执行工具一次性运行完毕：

### Step 1: 环境解析与提取 Diff (一次性执行完毕)

请使用终端/代码执行工具，一次性运行以下完整的 Bash 脚本（运行前，请替换脚本顶部三个变量：

- `PARAM`：用户输入的 `$ARGUMENTS`，无则留空
- `COMMIT_COUNT_RAW`：从用户自然语言中提取的数字，如"最近两次"→2，无则留空
- `COMMIT_HASH_RAW`：从用户输入中提取的 commit hash（7-40位十六进制字符串），如"mf525235"→mf525235，无则留空；**优先级高于 commit 数量和源分支模式**）：

```bash
#!/bin/bash
PARAM="<此处替换为用户输入参数，无则留空>"

# 1. 路径解析：剔除 @ 和 /，并尝试进入目录
if [ -n "$PARAM" ]; then
    CLEAN_PATH=$(echo "$PARAM" | sed -e 's/^@//' -e 's/\/$//')
    [ -d "$CLEAN_PATH" ] && cd "$CLEAN_PATH" || echo "未找到目录 $CLEAN_PATH，保持当前目录"
else
    CLEAN_PATH=$(basename "$(pwd)")
fi

# 安全拦截，判断当前目录是否是有效的 Git 仓库
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "BLOCK: 当前目录不是有效的 Git 仓库，结束操作。"
    exit 0
fi

REPO_NAME=$(basename "$(pwd)")

# 2. 获取当前分支与源头分支
C_BR=$(git branch --show-current)

# 尝试通过 reflog 获取源头分支
O_BR=$(git reflog show "$C_BR" 2>/dev/null | awk '/Created from/ {print $NF; exit}')
O_BR_COMPARE="${O_BR#remotes/}"   
O_BR_COMPARE="${O_BR_COMPARE#origin/}" 

# 【核心修复点】：处理 reflog 丢失 或 指向远端自身的场景（如重新 clone）
if [ -z "$O_BR" ] || [ "$C_BR" == "$O_BR_COMPARE" ]; then
    # 尝试读取远端仓库配置的默认主分支 (通常为 main 或 master)
    DEFAULT_BR=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    
    # 若无法通过 symbolic-ref 获取，则进行常规主分支盲测
    if [ -z "$DEFAULT_BR" ]; then
        for br in main master develop; do
            # 探测远端是否存在该分支
            if git rev-parse --verify "origin/$br" >/dev/null 2>&1; then
                DEFAULT_BR="$br"
                break
            fi
        done
    fi
    
    # 重新将源分支赋值为检测到的默认主分支兜底
    if [ -n "$DEFAULT_BR" ]; then
        O_BR="origin/$DEFAULT_BR"
        O_BR_COMPARE="$DEFAULT_BR"
    fi
fi

# 3. 阻断逻辑
if [ -z "$O_BR" ] || [ -z "$O_BR_COMPARE" ]; then
    echo "BLOCK: 未找到源分支且无法匹配默认主分支，结束操作。"
    exit 0
fi

if [ "$C_BR" == "$O_BR_COMPARE" ]; then
    echo "BLOCK: 当前分支($C_BR)即为源分支($O_BR_COMPARE)，无需审查，结束操作。"
    exit 0
fi

# 4. 获取 Diff 与上下文组装
DIFF_TMP="/tmp/git_diff_raw_$(date +%s).txt"
FINAL_TMP="/tmp/git_diff_final_$(date +%s).txt"

# 获取代码差异（这里依然使用带有 origin/ 的 $O_BR 进行精准 diff）
git diff "$O_BR" HEAD > "$DIFF_TMP"

# 检测代码是否有实质性改动
if [ ! -s "$DIFF_TMP" ]; then
    echo "BLOCK: 当前分支($C_BR)与源分支($O_BR)不同，但暂无代码实质改动，结束操作。"
    rm -f "$DIFF_TMP"
    exit 0
fi

# 若有实质改动，组装上下文信息并合并 Diff 给大模型
echo "REPOSITORY_NAME: $REPO_NAME" > "$FINAL_TMP"
echo "TARGET_COMPONENT: $CLEAN_PATH" >> "$FINAL_TMP"
echo "BRANCHES: $O_BR -> $C_BR" >> "$FINAL_TMP"
echo "=========================================" >> "$FINAL_TMP"
cat "$DIFF_TMP" >> "$FINAL_TMP"

# 读取最终文件并清理
cat "$FINAL_TMP"
rm -f "$DIFF_TMP" "$FINAL_TMP"
```

*(注：为防止转义冲突，上述代码块闭合符号多加了一个空格，实际使用时请去掉反引号间的空格)*

### Step 2: 深度审查与输出报告

拿到 Step 1 输出的 Diff 内容后，**严格执行以下判断**： 

1. 如果 Step 1 输出的内容含有 `BLOCK:` 字样，则直接结束当前 Code Review 操作，并向用户简述阻断原因（如：未找到源分支、无有效新提交等）。
2. 若无阻断字样，则开始执行深度 Code Review。

**审查要求**：略过自动生成文件(如 package-lock.json 等)。**审查前，先从 diff 中提取所有改动文件列表，按文件名字母序逐文件审查，每个文件内对每一处 `+` 行变更独立处理，不得合并、不得跳过任何改动点。对每处 `+` 行变更，严格按以下 6 项顺序逐项扫描，每项必须给出明确结论（发现/未发现），不得跳过**：
1. 安全漏洞（注入、越权、敏感信息泄露、OWASP Top 10）
2. **崩溃与异常（零容忍）**：空指针解引用、数组/集合越界访问、强制类型转换失败、除零运算、未捕获异常、资源未释放（文件句柄/数据库连接/内存泄漏）、线程安全问题（竞态条件/死锁）、栈溢出、无限递归、任何可能导致程序崩溃或抛出未处理异常的代码
3. 逻辑错误与边界遗漏（含条件判断、循环、并发）
4. 性能问题（时间复杂度、重复计算、内存泄漏）
5. 代码规范与可读性（命名、冗余逻辑、魔法数字）
6. 重构机会（可抽象逻辑、重复代码）

**分类规则（严格执行，不得主观判断）**：
- 🚫 严重问题：满足以下任一条件 → (a) 可导致程序崩溃/异常退出（含空指针、越界、未捕获异常、死锁、栈溢出等一切运行时崩溃风险）(b) 存在安全漏洞 (c) 数据丢失或损坏 (d) 构建/编译失败。第 1、2 项扫描结果**一律**归入此类，不得降级为改进建议。
- ⚠️ 改进建议：不满足严重问题条件，但属于第 3、4、5 项扫描发现的问题。
- 💡 优雅重构：第 6 项扫描结果，或对已有实现的结构性优化。

**排列规则**：同一类别内，按文件名字母序排列；同文件内按行号升序排列。每个独立代码位置对应一条意见，不合并、不拆分。
**仅报告 diff 中明确存在的问题，不推测、不补充 diff 之外的内容。**
**输出要求（强制执行，不可跳过）**：

- **必须**调用 Write 文件写入工具（禁止将内容输出到聊天代替写文件）
- 写入路径：`<Step 1 脚本执行时的工作目录>/<TARGET_COMPONENT>-code-review.md`（即 `pwd` 所在目录，非系统根目录）
- 若当前组件无改动则直接跳过不生成
- 写入完成后，向用户输出一行确认：`已生成：<完整文件路径>`

请在生成的 Markdown 文件中，**严格套用以下结构**进行排版，不属于该模块的内容严禁强行填入：

# 📦 仓库名称：[读取日志中的 REPOSITORY_NAME]

**分支对比**：`[读取日志中的源分支]` -> `[读取日志中的当前分支]`

## 📝 变更概述

[简明扼要地总结该组件/仓库的主要代码变动点]

## 🚨 深度审查意见

*(三大类别必须全部输出。若某类无发现，写：`本次变更未发现此类问题。`，不得省略该类别标题。)*

### 🚫 严重问题 (Critical)

*仅列出满足分类规则严重问题条件的问题（崩溃/未处理异常/安全漏洞/数据损坏/构建失败）。**任何可能导致运行时崩溃或抛出未处理异常的代码必须在此列出，不得降级。** 不符合条件的一律归入改进建议。*

* **问题描述**：[精准描述缺陷原因]

* **潜在影响**：[描述后果，如：内存溢出、数据泄露]

* **位置**：第 L[起始行号] - L[结束行号] 行

* **当前分支和原分支改动对比**：

  ```javascript
  // 原分支代码
  [请完整提取原分支代码块]
  
  // 当前分支改动代码
  [请完整提取当前分支改动的代码]
  ```

* **修复对比**：

  ```javascript
  // ❌ 原始代码
  [完整提取包含问题的原始代码块]
  
  // ✅ 修复代码
  [提供符合 Clean Code、高性能的重构代码]
  ```

* **修复重点**：[简述修复后的核心优势，如：降低环路复杂度]

### ⚠️ 改进建议 (Standard)

*列出所有不满足严重问题条件、但属于逻辑错误/边界遗漏/性能问题/代码规范的问题。按文件名字母序、行号升序排列。*

* **建议点**：[描述建议，如：建议使用 Optional Chaining 替代多层 if 判断]

* **理由**：[说明为什么这样改更好]

* **位置**：第 L[起始行号] - L[结束行号] 行

* **当前分支和原分支改动对比**：

  ```javascript
  // 原分支代码
  [请完整提取原分支代码块]
  
  // 当前分支改动代码
  [请完整提取当前分支改动的代码]
  ```

* **修复对比**：

  ```javascript
  // ❌ 原始代码
  [完整提取包含问题的原始代码块]
  
  // ✅ 修复代码
  [提供符合 Clean Code、高性能的重构代码]
  ```

* **修复重点**：[简述修复后的核心优势，如：降低环路复杂度]

### 💡 优雅重构 (Refactoring)

*必须基于上下文给出具体的重构方案。严格遵守下述对比格式执行：*

* **位置**：第 L[起始行号] - L[结束行号] 行

* **当前分支和原分支改动对比**：

  ```javascript
  // 原分支代码
  [请完整提取原分支代码块]
  
  // 当前分支改动代码
  [请完整提取当前分支改动的代码]
  ```

* **修复对比**：

  ```javascript
  // ❌ 原始代码
  [请完整提取包含问题的原始代码块]
  
  // ✅ 修复代码
  [请提供符合 Clean Code 原则、更高性能或更健壮的重构代码]
  ```

* **修复重点**：[简述修复后的核心优势，如：降低了环路复杂度 / 提高了 O(n) 效率]

## 🏁 总结评述

* **整体评价**：[按公式计算：10 - (严重问题数×3) - (改进建议数×0.5) - (重构建议数×0.2)，最低 1 分，保留一位小数。格式：X.X 分（严重×N，改进×N，重构×N）]
* **核心风险**：[一句话总结最需要关注的改动点]

---

## Constraints (强制约束)

- 强制使用中文输出。
- 极简明了，拒绝废话和过度寒暄。
