---
description: View current multi-agent workflow status
---

# /status — 查看工作流状态

读取 `doc/state.json`、`doc/checkpoint.json`、`doc/logs/summary.md` 和 `doc/progress.md`，输出当前状态、执行进度和下一步建议。

## Steps

1. **读取状态文件**

```bash
cat doc/state.json
```

2. **检查是否有活跃 Checkpoint**

```bash
if [ -f "doc/checkpoint.json" ]; then
  echo "🔄 存在活跃执行链:"
  bash ~/.claude/checkpoint.sh read_status
fi
```

3. **读取追踪报告**

```bash
cat doc/logs/summary.md 2>/dev/null || echo "暂无追踪报告"
```

4. **读取工作进度账本摘要**

```bash
sed -n '/^## Current Snapshot/,/^## /p' doc/progress.md 2>/dev/null || echo "暂无工作进度账本"
```

> 默认只读 `Current Snapshot`。只有当摘要里提到 blocker / handoff / 冲突需要追溯时，才继续读取最近 1-3 条 `Agent Updates`。

5. **格式化输出**

解析 JSON 并输出以下格式：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 状态: {state}
🏗  项目: {project}
🧭 模式: {work_mode || "未设置"}
📄 PRD: {prd_path || "未生成"}
🎨 Figma: {figma_url || "未提供"}
🧪 测试: {tests_path || "未生成"}
🔁 反思次数: {reflection_count}/3

📜 最近执行（chain_log 最后5条）:
─────────────────────────────
{timestamp} | {from} → {to}
...

🔄 执行链: {chain_name || "无活跃链"}
📊 链进度: {done}/{total} 步完成
🔴 断点: Step {id} — {name} (如有)

⏭  下一步: {建议操作}
📋 执行计划: doc/execution-plan.md (如有活跃链)
📝 最新交接: doc/progress.md
📊 完整追踪: doc/logs/summary.md
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

6. **下一步建议映射**

| 当前状态 | 建议 |
|---------|------|
| `IDEA` | 💡 请描述项目概念，或输入 "我已有代码，路径 {path}" |
| `PRD_DRAFT` | 📖 请审阅 PRD (`doc/prd.md`)，确认后回复 `approved` |
| `PRD_REVIEW` | ⏳ BE 正在审查 PRD... |
| `BE_APPROVED` | ⏳ FE 正在审查 PRD... |
| `PRD_APPROVED` | ⏳ 正在生成 Figma 设计提示词... |
| `FIGMA_PROMPT` | 🎨 请在 Figma 完成设计，然后回复 `figma ready {url}` |
| `DESIGN_READY` | ⏳ QA 正在生成测试计划... |
| `TESTS_WRITTEN` | 📋 请审阅测试计划，确认后回复 `plan approved` |
| `IMPLEMENTATION` | ⏳ FE+BE 正在编码实现... |
| `QA_TESTING` | ⏳ QA 正在执行测试... |
| `QA_PASSED` | ✅ 即将完成 |
| `QA_FAILED` | 🔧 正在分析失败原因（已反思 {reflection_count}/3 次）|
| `DONE` | 🎉 项目完成！|
| **有 checkpoint** | 🔄 存在未完成执行链，输入 `/resume` 恢复 |
