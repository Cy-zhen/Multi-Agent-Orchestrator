---
name: multi-agent-orchestrator
description: 多Agent开发工作流编排器。管理PM/Designer/FE/BE/QA/General六个Agent的调度，驱动IDEA→DONE完整产品开发链路。当用户说"初始化项目"、"onboard"、"接入项目"、"approved"、"通过"、"批准"、"figma ready"、"plan approved"、"查看状态"、"/status"、"恢复执行"、"resume"、"继续"时触发。
---

# Multi-Agent Orchestrator

> **你是编排器的 UI 层，同时兼任 Claude Agent。**
>
> - Codex/Gemini 任务 → 脚本通过 CLI 调用（你不参与）
> - Claude 任务 → 脚本会输出 `CLAUDE_TASK_PENDING`，**由你来执行**
> - 其他 → 你只管调命令 + 转述结果
> - live source of truth 是 `~/.claude/orchestrator.sh` 与 `~/.claude/orchestrator/`
> - 仓库中的 `claude/` 是 shell runtime 开发副本；`orchestrator/` 是 Python v2 实验目录

## 新话题启动顺序

当用户在新话题里直接说“继续 / 查看状态 / 恢复执行 / approved / figma ready / plan approved”时：

1. 先确定目标项目路径 `{PROJECT_DIR}`
2. 先执行 Project Memory Bootstrap
3. 再跑 `bash ~/.claude/orchestrator.sh --ag status "{PROJECT_DIR}"` 读取当前状态
4. 根据当前状态决定是否转发用户信号或继续 auto-run

不要在不知道 `{PROJECT_DIR}` 和当前状态的情况下直接盲发信号。

## Project Memory Bootstrap

每次进入一个项目目录并准备开始编排前，先执行项目记忆检查。这个步骤优先于读取 `doc/state.json`、日志、checkpoint。

### 必做顺序

1. 先拿到目标项目绝对路径，记为 `{PROJECT_DIR}`
2. 运行: `bash ~/.project-memory/bin/pmem.sh status "{PROJECT_DIR}"`
3. 如果输出显示项目已注册：
   - 明确提示用户：`发现项目记忆，是否加载？`
   - 用户确认后再运行: `bash ~/.project-memory/bin/pmem.sh load "{PROJECT_DIR}"`
4. 如果输出显示项目未注册：
   - 先正常了解项目
   - 当你已经能给出稳定 slug 时，再提示用户是否初始化记忆
   - 初始化命令: `bash ~/.project-memory/bin/pmem.sh init "{PROJECT_DIR}" "{slug}"`

### 绝对禁止

- ❌ 跳过 `pmem.sh status` 直接开始读 `doc/state.json`
- ❌ 未经用户确认直接加载项目记忆
- ❌ 还没理解项目就擅自初始化项目记忆
- ❌ 把项目记忆和 `doc/state.json` 混为一谈
- ❌ 完成重要任务后忘记提醒用户是否要保存项目记忆

## Memory Save On Close

当一次任务结束后，如果本次工作产生了新的关键上下文，你要主动问用户是否保存项目记忆。

### 触发条件

- 架构变更
- 运行路径或 source-of-truth 变化
- 新增明显的踩坑记录
- 工作流规则变化
- 新的同步规则或手工步骤

### 询问方式

- 直接一句：`这次有新的关键上下文，是否更新项目记忆？`
- 用户确认后再执行记忆保存或更新
- 如果只是普通状态推进、没有新增长期价值信息，不要机械地每次都问

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
| "resume" / "恢复执行" / "继续" | `bash ~/.claude/orchestrator.sh --ag auto-run {PROJECT_DIR}` |
| 项目描述文本 (IDEA状态) | `bash ~/.claude/orchestrator.sh --ag signal "{用户原文}" {PROJECT_DIR}` |

### 初始化新项目时

如果用户只是说“初始化项目 {path}”：

1. 先跑 `init`
2. 再提示用户提供概念描述

如果用户同一轮同时给了路径和产品概念：

1. 跑 `init`
2. 再跑 `signal "{概念描述}" {PROJECT_DIR}`

## CLAUDE_TASK_PENDING 处理流程

当命令输出包含 `CLAUDE_TASK_PENDING` 时，你需要：

1. **读取** `{PROJECT_DIR}/doc/.claude-task.md` 中的 prompt
2. **读取** `{PROJECT_DIR}/doc/.claude-task-meta.json` 了解 `role` / `action` / `executor` / `fallback_from` / `next_state`
3. **执行** prompt 中描述的任务
   - 你是在做该 `role` 的**人工接管执行器**
   - 不是把 FE/BE 角色改成 Claude 本身
4. 完成任务后，**手动转换状态**: `bash ~/.claude/orchestrator.sh --ag transition {next_state} {PROJECT_DIR}`
5. **继续链**: `bash ~/.claude/orchestrator.sh --ag auto-run {PROJECT_DIR}`

## 绝对禁止

- ❌ 不加 `--ag` 调命令（会触发 claude -p 失败）
- ❌ 跳过 `CLAUDE_TASK_PENDING` 直接改状态
- ❌ 自己决定下一步状态（必须由脚本告诉你）
- ❌ 把 `CLAUDE_TASK_PENDING` 理解成“Claude 角色接管一切”

## Role / Executor 语义

- `role` 决定职责边界：FE 还是 FE，BE 还是 BE
- `executor` 决定由谁执行：Gemini / Codex / Antigravity / Claude
- fallback 的正确含义是：**同一 role 换执行器，不换职责**
- 例子：
  - `role=FE executor=gemini` 失败
  - fallback 后变成 `role=FE executor=antigravity`
  - 这时你做的是 **FE 的人工接管**，不是“Claude 顺手帮忙写前端”

## 工作流概览

```text
IDEA(交互) -> PRD_DRAFT(等审批) -> CEO_REVIEW -> PRD_REVIEW(BE/codex) -> BE_APPROVED(FE/gemini)
-> DESIGN_PLAN_REVIEW -> PRD_APPROVED(Designer/你执行) -> FIGMA_PROMPT(等用户)
-> DESIGN_SPEC(PM/你执行) -> DESIGN_SPEC_REVIEW(等审批) -> DESIGN_READY(QA/codex)
-> TESTS_WRITTEN(等审批) -> IMPLEMENTATION(FE+BE并行)
-> CODE_REVIEW -> SECURITY_AUDIT -> QA_TESTING(codex)
-> VISUAL_REVIEW -> QA_PASSED(ship) -> PRODUCT_DOC(PM/你执行) -> DONE

QA_FAILED -> IMPLEMENTATION  (最多 3 次调查/修复循环)
```

- Claude / Antigravity 常见人工执行点：`IDEA`、`PRD_APPROVED`、`DESIGN_SPEC`、`QA_FAILED`、`PRODUCT_DOC`
- FE / BE 在 `IMPLEMENTATION` 阶段如果主执行器失败，也可能通过 `CLAUDE_TASK_PENDING` 回退给你人工接管
- 其他为 USER_GATE 或脚本自动执行

## 日志与断点恢复

每次执行 `/status` 或 onboard 时，你应该：

0. **先完成 Project Memory Bootstrap**
   - 已注册项目：先问是否加载，再决定是否读取 memory
   - 未注册项目：先继续收集上下文，不要抢跑初始化
1. **先读状态**: `{PROJECT_DIR}/doc/state.json`
2. **读取日志**: `{PROJECT_DIR}/doc/logs/summary.md` — 包含完整执行时间线
3. **读取 JSONL**: `{PROJECT_DIR}/doc/logs/workflow.jsonl` — 结构化日志（最后几行即可）
4. **检查断点**: 如果存在 `{PROJECT_DIR}/doc/checkpoint.json`，调 `bash ~/.claude/checkpoint.sh read_status` 显示执行链状态
5. **执行计划**: `{PROJECT_DIR}/doc/execution-plan.md` — 当前链的 step-by-step 进度

### 新会话恢复

当你进入一个已有项目时：
- 先跑 `bash ~/.project-memory/bin/pmem.sh status "{PROJECT_DIR}"`
- 如果已注册，先询问是否加载项目记忆；用户确认后跑 `bash ~/.project-memory/bin/pmem.sh load "{PROJECT_DIR}"`
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

## Token 效率规则

> 来源: [drona23/claude-token-efficient](https://github.com/drona23/claude-token-efficient) (MIT)
> 多 Agent 流水线是高输出量场景，token 优化效果显著。

- 先读项目记忆状态，再读 state.json + 日志，不盲猜上下文
- 回复精炼，禁止寒暄/拍马屁/废话结尾
- 局部编辑优先，不重写整个文件
- 已读文件不重复读取
- 简单直接的方案优先，不过度工程
- 用户明确指令永远覆盖本文件规则
