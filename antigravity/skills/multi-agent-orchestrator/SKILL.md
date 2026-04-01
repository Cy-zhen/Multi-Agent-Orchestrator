---
name: multi-agent-orchestrator
description: 多Agent开发工作流编排器。管理PM/Designer/FE/BE/QA/General六个Agent的调度，驱动IDEA→DONE完整产品开发链路。当用户说"初始化项目"、"onboard"、"接入项目"、"approved"、"通过"、"批准"、"figma ready"、"plan approved"、"查看状态"、"/status"、"恢复执行"、"resume"时触发。
---

# Multi-Agent Orchestrator

> **你是编排器的 UI 层，同时兼任 Claude Agent。**
>
> - Codex/Gemini 任务 → 脚本通过 CLI 调用（你不参与）
> - Claude 任务 → 脚本会输出 `CLAUDE_TASK_PENDING`，**由你来执行**
> - 其他 → 你只管调命令 + 转述结果

## 命令映射表

**所有命令都加 `--ag` 标志**（告诉脚本你是 Antigravity/Claude，不要调 claude -p）：

| 用户说的话 | 你执行的命令 |
|-----------|-------------|
| "初始化项目 {path}" | `bash ~/.claude/orchestrator.sh --ag init {path}` |
| "onboard {path}" / "接入项目 {path}" | `bash ~/.claude/orchestrator.sh --ag onboard {path}` |
| "approved" / "通过" | `bash ~/.claude/orchestrator.sh --ag signal approved {PROJECT_DIR}` |
| "figma ready {url}" | `bash ~/.claude/orchestrator.sh --ag signal "figma ready {url}" {PROJECT_DIR}` |
| "approved" (DESIGN_SPEC_REVIEW状态) | `bash ~/.claude/orchestrator.sh --ag signal approved {PROJECT_DIR}` |
| "plan approved" | `bash ~/.claude/orchestrator.sh --ag signal "plan approved" {PROJECT_DIR}` |
| "/status" / "查看状态" | `bash ~/.claude/orchestrator.sh --ag status {PROJECT_DIR}` |
| "resume" / "恢复执行" | `bash ~/.claude/orchestrator.sh --ag auto-run {PROJECT_DIR}` |
| 项目描述文本 (IDEA状态) | `bash ~/.claude/orchestrator.sh --ag signal "描述" {PROJECT_DIR}` |

## CLAUDE_TASK_PENDING 处理流程

当命令输出包含 `CLAUDE_TASK_PENDING` 时，你需要：

1. **读取** `{PROJECT_DIR}/doc/.claude-task.md` 中的 prompt
2. **读取** `{PROJECT_DIR}/doc/.claude-task-meta.json` 了解 agent/skill/next_state
3. **执行** prompt 中描述的任务（你就是 Claude Agent）
4. 完成任务后，**手动转换状态**: `bash ~/.claude/orchestrator.sh --ag transition {next_state} {PROJECT_DIR}`
5. **继续链**: `bash ~/.claude/orchestrator.sh --ag auto-run {PROJECT_DIR}`

## 绝对禁止

- ❌ 不加 `--ag` 调命令（会触发 claude -p 失败）
- ❌ 跳过 `CLAUDE_TASK_PENDING` 直接改状态
- ❌ 自己决定下一步状态（必须由脚本告诉你）

## 工作流概览

```
IDEA(交互) → PRD_DRAFT(等审批) → CEO_REVIEW → PRD_REVIEW(BE/codex) → BE_APPROVED(FE/gemini)
→ DESIGN_PLAN_REVIEW → PRD_APPROVED(Designer/你执行) → FIGMA_PROMPT(等用户)
→ DESIGN_SPEC(PM/你执行) → DESIGN_SPEC_REVIEW(等审批) → DESIGN_READY(QA/codex)
→ TESTS_WRITTEN(等审批) → IMPLEMENTATION(FE+BE并行)
→ CODE_REVIEW → SECURITY_AUDIT → QA_TESTING(codex)
→ VISUAL_REVIEW → QA_PASSED(ship) → PRODUCT_DOC(PM/你执行) → DONE
```

- **粗体状态** 由脚本调 codex/gemini
- *斜体状态* (IDEA/PRD_APPROVED/QA_FAILED) 输出 CLAUDE_TASK_PENDING → 你执行
- 其他为 USER_GATE 等用户信号

## 日志与断点恢复

每次执行 `/status` 或 onboard 时，你应该：

1. **读取日志**: `{PROJECT_DIR}/doc/logs/summary.md` — 包含完整执行时间线
2. **读取 JSONL**: `{PROJECT_DIR}/doc/logs/workflow.jsonl` — 结构化日志（最后几行即可）
3. **检查断点**: 如果存在 `{PROJECT_DIR}/doc/checkpoint.json`，调 `bash ~/.claude/checkpoint.sh read_status` 显示执行链状态
4. **执行计划**: `{PROJECT_DIR}/doc/execution-plan.md` — 当前链的 step-by-step 进度

### 新会话恢复

当你进入一个已有项目时：
- 先读 `doc/state.json` 了解当前状态
- 再读 `doc/logs/summary.md` 了解历史
- 如果是你之前执行过的项目 → 从断点继续 (`auto-run`)
- 如果是全新项目 → 走正常 onboard 流程

### 展示给用户

每次用户查看状态时，以卡片形式展示：
```
📋 状态: {state}
🏗 项目: {project}
📜 最近执行:
  🚀 21:01 [pm] 开始生成 PRD
  ✅ 21:03 [pm] PRD 生成完成
  🔄 21:03 [orchestrator] IDEA → PRD_DRAFT
⏭ 下一步: {建议}
```
