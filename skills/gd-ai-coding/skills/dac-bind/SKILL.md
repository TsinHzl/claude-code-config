---
name: dac-bind
description: 交互式需求绑定 — 将当前 git 分支绑定到 DDP 需求 ID，后续提交自动写入 dac-trace notes
user-invocable: false
---

# dac-bind — 交互式需求绑定

## 触发方式
子 skill（不可直调）：对 Claude 说「执行 dac-bind 绑定当前分支」即可触发。

## 职责
在任意 git 仓库中，将当前工作分支绑定到一个 DDP 需求 ID。
绑定后，每次 `git commit` 自动将提交写入 `refs/notes/dac-trace`，
数据汇入 DAC dashboard 的"使用 dac 成员"统计。

---

## 执行步骤

### 步骤 1：确认当前在 git 仓库内

```bash
git rev-parse --git-dir 2>/dev/null || echo "NOT_GIT"
```

若不在 git 仓库，告知用户需要在 git 仓库根目录执行，终止。

### 步骤 2：读取当前分支名，尝试从分支名预填 DDP ID

```bash
git symbolic-ref --short HEAD 2>/dev/null
```

优先用 `grep -oE 'T-IBT-[0-9]+'` 提取候选 ID；未命中再尝试 `grep -oE 'R-IBG-[0-9]+'`。

### 步骤 3：读取已有绑定（如有）

```bash
cat .dac/req-bind 2>/dev/null
```

提取 `.req` 字段作为当前绑定值展示给用户。

### 步骤 4：AskUserQuestion 询问需求 ID

- 若从分支名提取到候选 ID，将其作为第一个选项（推荐）
- 若已有绑定，将当前绑定值作为"保持当前绑定"选项
- 必须提供"Other"让用户手动输入
- 提供"解绑（--clear）"选项

根据用户选择：
- 选择某个需求 ID → 执行步骤 5
- 解绑 → 执行步骤 6

### 步骤 5：确认安装 hook（如未安装）

检查当前 git 仓库是否已安装 DAC hook：

```bash
git config core.hooksPath 2>/dev/null
```

若 `core.hooksPath` 未指向 `.git/dac-hooks`，提示用户：
> "当前仓库未安装 DAC hook，绑定后需安装才能自动追踪。是否现在安装？"

若用户确认，执行：
```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/setup-hook-wrapper.sh
```

### 步骤 6：执行绑定

```bash
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/bind-req.sh --req <选择的 ID>
# 或解绑：
bash ${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/bind-req.sh --clear
```

### 步骤 7：输出结果

绑定成功后输出：
```
✅ 已绑定：req = T-IBT-XXXXXX
   分支：<当前分支名>
   已同步到后端，dashboard 统计立即可见（后端未配置或不可达时静默跳过，不影响绑定本身）。
   后续在此分支的每次 git commit 将自动写入 dac-trace notes。

   切换到其他分支后，绑定自动失效（分支校验）。
   重新绑定请再次执行 dac-bind。
```

解绑成功后输出：
```
✅ 已解绑，后续提交不再写入 dac-trace notes。
```

---

## 注意事项

- `bind-req.sh` 会自动将 `.dac/req-bind` 加入 `.git/info/exclude`，不影响仓库其他人
- 若仓库未安装 hook，绑定文件存在但提交不会自动追踪，必须先安装 hook
- 完整 DAC 工作流（`.dac/state.json`）优先级高于轻量绑定，无需重复操作
- 需求 ID 支持 `T-IBT-XXXXXX`（任务，推荐，可取到版本号）、`R-IBG-XXXXXX`（需求）格式或自定义名称（如项目代号）
