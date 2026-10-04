# 章节映射模式（`--map-sections`）

触发：主编排 Read 执行 `skills/ui-spec/SKILL.md`，参数 `--map-sections "openspec/changes/{req_name}/ui"`

用于主编排在 PRD spec 生成完成后，补充 index.json 中的章节映射关系。

## 前置条件

- `{目录}/index.json` 存在
- `openspec/changes/{req_name}/prd/prd-spec.md` 存在（phase = `prd-speced`，章节结构已最终确定）

## 执行步骤

### M-1：加载数据

- 读取 index.json（获取设计稿列表及 node_name）
- 从 `prd-spec.md` 提取功能章节列表（§3.x 功能点标题），确保映射基于需求澄清后的最终结构

### M-2：向用户确认映射关系

```
请为设计稿指定关联的需求章节：

设计稿 ds_001（节点名: 面板半展开最低展示）
→ 关联章节（输入编号如 1,3 或"全部"）：

  可选章节：
  1. §3.2.1 司机邀请
  2. §3.2.3 司机接单
  3. §3.2.4 完单页

设计稿 ds_002（节点名: 首页-主流程）
→ 关联章节：
```

只有 1 个设计稿时，自动关联所有章节（可确认跳过交互）。

### M-3：更新 index.json

将用户指定的映射关系写入 index.json 的 `sections` 字段，移除 `"mapping": "pending"` 标记。

```
✅ 章节映射完成，已更新 index.json
```
