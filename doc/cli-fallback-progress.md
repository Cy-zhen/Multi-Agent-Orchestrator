# CLI 回退机制进展

## 完成日期
2026-03-15

## 变更文件
- `/Users/cy-zhen/.claude/orchestrator.sh`

## 变更内容

### 新增
- `run_with_fallback()` — Gemini/Codex 失败时自动回退到 Claude/Antigravity
- `_emit_claude_task_pending()` — 统一的 CLAUDE_TASK_PENDING 输出辅助函数

### 修改
- `cmd_dispatch()` — 使用 `run_with_fallback()` 替代硬编码 CLI 调用
- `cmd_auto_run()` 串行执行 — 使用 `run_with_fallback()` 替代内联逻辑
- `cmd_auto_run()` 并行 IMPLEMENTATION — 增加 FE/BE 回退逻辑
- `cmd_onboard()` — Codex 扫描增加 Claude 回退；PRD 生成使用 `_emit_claude_task_pending()`

## 验证
- ✅ `bash -n orchestrator.sh` 语法通过
- ✅ `orchestrator.sh --help` 正常输出
