# OpenSpec 规范驱动开发（自动内置模式）

## 核心行为
遇到复杂需求时，Claude 自动创建并维护 `openspec/` 目录下的所有规范文件，
全程驱动四阶段工作流。用户无需安装任何工具，无需手动执行任何命令。

---

## 一、触发条件（满足任意一项自动启用）

- 涉及 3 个以上文件的修改
- 新功能或新模块开发
- 重构、架构调整
- 接口 / 数据协议变更
- 用户描述的需求包含多个独立步骤或子系统交互

不满足上述条件的小改动（单文件 bug fix、typo 修正等）直接执行，不走本流程。

---

## 二、目录结构（由 Claude 自动创建维护）

```
openspec/
├── project.md              # 项目上下文（首次初始化时创建）
├── specs/                  # 已归档的最终规范（source of truth）
├── changes/                # 进行中的变更
│   └── <change-name>/
│       ├── proposal.md     # 变更提案
│       ├── tasks.md        # 任务清单（含实时状态）
│       └── specs/          # 本次变更的规范增量
│           └── <domain>/
│               └── spec.md
└── archive/                # 已完成归档的变更
    └── <change-name>_<YYYYMMDD>/
```

---

## 三、阶段 1 — 自动起草提案

收到复杂需求后，在写任何业务代码之前，Claude 自动执行：

### 3.1 确定 change-name
用 kebab-case 命名，描述变更内容，例如：
`add-ride-filter`、`refactor-payment-flow`、`update-location-protocol`

### 3.2 创建 `openspec/changes/<change-name>/proposal.md`

```markdown
# 变更提案：<change-name>

## 背景
<为什么需要这个变更，解决什么问题>

## 目标范围
**在范围内：**
- <具体包含的内容>

**不在范围内：**
- <明确排除的内容>

## 技术方案
<关键技术决策、依赖、约束>

## 预期影响
<对现有功能的影响、性能、兼容性>

## 风险
<识别的风险及应对策略>
```

### 3.3 创建 `openspec/changes/<change-name>/tasks.md`

```markdown
# 任务清单：<change-name>

## 状态：DRAFT

## 任务
- [ ] <任务 1 描述>
- [ ] <任务 2 描述>
- [ ] <任务 3 描述>

## 验收标准
- [ ] <验收条件 1>
- [ ] <验收条件 2>
```

### 3.4 创建规范增量 `openspec/changes/<change-name>/specs/<domain>/spec.md`
（涉及接口、状态、业务规则时创建）

```markdown
### Requirement: <需求名称>
- The system SHALL <约束描述>

#### Scenario: <场景名称>
- GIVEN <前置条件>
- WHEN <触发事件>
- THEN <预期结果>
```

### 3.5 展示提案摘要，等待用户确认
输出 proposal.md 核心内容 + tasks.md 完整任务列表，明确告知：
**"以上是本次变更的提案，确认后开始实施"**，等待用户回复。

---

## 四、阶段 2 — 审查确认

用户确认提案后才能进入实施阶段。

若用户提出修改意见：
1. 更新 `proposal.md` 和 `tasks.md`
2. 重新展示修改后内容
3. 再次等待确认

---

## 五、阶段 3 — 逐任务实施

用户确认后，按以下规则执行：

1. 将 `tasks.md` 状态更新为 `IN_PROGRESS`
2. 按任务顺序逐一实施，每完成一项：
   - 将对应 `- [ ]` 改为 `- [x]`
   - 简述完成情况
3. 代码实现必须与 `specs/` 中的规范一致
4. 发现超出提案范围的需求 → **立即停止**，先补充提案或创建新变更，不合并进当前范围
5. 全部任务完成后，将状态更新为 `DONE`

---

## 六、阶段 4 — 自动归档

所有任务状态为 `[x]` 且验收标准满足后，Claude 自动执行：

1. 将 `tasks.md` 状态改为 `ARCHIVED`
2. 将 `openspec/changes/<change-name>/specs/` 内容合并写入 `openspec/specs/`
3. 将整个 `openspec/changes/<change-name>/` 目录移至
   `openspec/archive/<change-name>_<YYYYMMDD>/`

---

## 七、变更状态流转

```
DRAFT → IN_REVIEW → IN_PROGRESS → DONE → ARCHIVED
                 ↘ REJECTED（用户拒绝提案，需修改后重新确认）
```

状态写在 `tasks.md` 的 `## 状态：` 字段，Claude 在每个阶段切换时自动更新。

---

## 八、代码审查前自检

实施完成、准备提 PR 前，对照 `tasks.md` 自动检查：

```
- [ ] 所有任务已完成（tasks.md 全部 [x]）
- [ ] 代码实现与 specs/ 中规范一致
- [ ] 变更未超出 proposal.md 定义的范围
- [ ] 无意外副作用或未预期的依赖变更
- [ ] 验收标准全部满足
```

---

## 九、Git 集成规范

### 分支命名
```
feature/<change-name>
refactor/<change-name>
hotfix/<change-name>
```

### Commit 格式
```
feat(<change-name>): <简短描述>

- 具体实现内容 1
- 具体实现内容 2

Refs: openspec/changes/<change-name>
```

---

## 十、强制约束（不可绕过）

| 场景 | 必须执行 |
|------|---------|
| 触发条件满足 | 先创建提案文件，再写业务代码 |
| 实施前 | 展示提案摘要，等待用户明确确认 |
| 实施中 | 每完成一项任务立即更新 tasks.md |
| 需求超出范围 | 停止实施，扩展提案或新建变更 |
| 任务全部完成 | 自动执行归档，更新 openspec/specs/ |

---

## 十一、openspec/project.md 初始化

首次在项目中触发 OpenSpec 工作流时，若 `openspec/project.md` 不存在，
自动创建并填入以下内容（根据项目实际情况填写）：

```markdown
# 项目上下文

## 技术栈
<语言、框架、主要依赖>

## 架构约定
<分层结构、命名规范、关键设计决策>

## 目录结构
<项目关键目录说明>

## 开发约定
<代码风格、测试要求、分支策略>
```
