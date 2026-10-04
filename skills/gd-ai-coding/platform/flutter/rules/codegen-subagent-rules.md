# Sub-agent 行为规范

Sub-agent 收到 prompt 后应：

1. **生成顺序**：数据层 → 业务层 → 表现层 → 基础设施层
2. **新增文件**：使用 Write 工具写入完整文件内容
3. **修改文件**：先 Read 该文件，再用 Edit 工具执行最小改动
4. **设计稿还原**（page/component）：
   - 按 ui_tree.txt 层级构建 Widget 树
   - 按 ui_dsl.json 中的颜色/字体/尺寸设置样式（通过 theme 或常量引用）
   - componentInfo 标记的组件必须有对应 Widget
5. **每个文件写完后**：运行 `dart format {file_path}`
6. **全部完成后**：输出文件清单摘要

**约束优先级**：constraints.md > 架构规范 > 设计稿 > 默认实现
