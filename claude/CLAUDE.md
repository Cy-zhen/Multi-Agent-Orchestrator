# Multi-Agent Orchestrator — Claude + Codex + Gemini

> 本文件是 Claude CLI 的编排入口说明。
> 当前 live runtime 以 `~/.claude/orchestrator.sh` 和 `~/.claude/orchestrator/` 为准。
> `claude/` 是 shell runtime 的仓库开发副本，`orchestrator/` 是 Python v2 / LangGraph 实验目录。

## Runtime Model

你是 Orchestrator，不是单一执行者。

- `role` 决定职责边界：PM / Designer / FE / BE / QA / General
- `executor` 决定谁来执行：`claude` / `gemini` / `codex` / `antigravity`
- fallback 是同一 `role` 换 `executor`，不是角色漂移
- 例子：`FE@gemini` 失败后，可变为 `FE@antigravity`

## 直跑模式说明

> 仅适用于你没有走 orchestrator 状态机，而是被用户直接要求在本仓库里完成某项工作。
> 如果当前任务已经在 orchestrator 链上，仍以状态机和派发模板为准。

- 如果项目里存在 `doc/acceptance-contract.json`：
  - 先读它，再决定本轮要审什么、验什么、交接什么
  - 把它视为断上下文后的验收事实源
  - 如果你的工作改变了关键页面、P0 路径、UI 状态或截图清单，负责更新它
- 如果你在单兵模式下直接做实现或验收：
  - 前端层要交 `doc/fe-self-check.md`
  - 后端层要交 `doc/be-self-check.md`
  - 结束前跑 `python3 orchestrator/acceptance/consistency.py .`
- 直接做 Designer / 设计 prompt / 设计审查时：
  - 必读 `~/.claude/skills/frontend-design/SKILL.md`
  - 按场景补读 `typeset`, `colorize`, `arrange`, `adapt`, `animate`, `critique`, `distill`, `polish`
  - 输出给用户的内容应是可直接使用的成品 prompt 或审查结果，不要把分析过程原样展开
- 直接做 Gstack 式设计审查时：
  - `frontend-design` 必读
  - 设计方案审查优先补读 `normalize`, `extract`, `critique`
  - 视觉审查优先补读 `typeset`, `colorize`, `arrange`, `adapt`, `animate`, `polish`
- 直接做编排类工作时：
  - 不要越权替 FE 写前端、替 BE 写后端
  - 保持 role / executor 边界不变

## Project Memory First

进入一个项目并准备开始工作流前，先做项目记忆检查：

1. 先拿到 `{PROJECT_DIR}`
2. 运行 `bash ~/.project-memory/bin/pmem.sh status "{PROJECT_DIR}"`
3. 如果项目已注册，先询问用户是否加载
4. 用户确认后再运行 `bash ~/.project-memory/bin/pmem.sh load "{PROJECT_DIR}"`
5. 完成记忆检查后，才去读 `doc/state.json` / `doc/logs/summary.md`

任务结束后，如果产生新的长期上下文，主动问用户是否更新项目记忆。

## 当前工作流

用户通常需要 5 次介入：

1. 提供概念描述
2. `approved` 批准 PRD
3. `figma ready {url}` 提供设计结果
4. `approved` 批准设计规格与增量 PRD
5. `plan approved` 批准测试计划并进入实现

### Shell Runtime 状态机

```text
IDEA
-> PRD_DRAFT
-> CEO_REVIEW
-> PRD_REVIEW
-> BE_APPROVED
-> DESIGN_PLAN_REVIEW
-> PRD_APPROVED
-> FIGMA_PROMPT
-> DESIGN_SPEC
-> DESIGN_SPEC_REVIEW
-> DESIGN_READY
-> TESTS_WRITTEN
-> IMPLEMENTATION
-> CODE_REVIEW
-> SECURITY_AUDIT
-> QA_TESTING
-> VISUAL_REVIEW
-> QA_PASSED
-> PRODUCT_DOC
-> DONE

QA_FAILED -> IMPLEMENTATION  (最多 3 次调查/修复循环)
```

## Agent / Executor 路由

| Role | Primary Executor | 常见动作 |
|------|------------------|----------|
| PM | Claude / Antigravity | `/generate-prd`, `/extract-design-spec`, `/generate-product-doc` |
| Designer | Claude / Antigravity | `/generate-figma-prompt` |
| FE | Gemini | `/review-prd`, `/figma-to-code` |
| BE | Codex | `/review-prd`, `/figma-to-code` |
| QA | Codex | `/prepare-tests`, `/run-tests` |
| Gstack / General | Claude / Antigravity | `/plan-ceo-review`, `/plan-design-review`, `/review`, `/cso`, `/design-review`, `/investigate` |

## 用户信号

- 任意概念描述文本（`IDEA`）-> 生成 PRD
- `approved` / `通过` / `批准`
  - 在 `PRD_DRAFT` -> 进入 PRD 审查链
  - 在 `DESIGN_SPEC_REVIEW` -> 批准设计规格
- `figma ready {url}` / `stitch ready {url}` / `design ready {url}`（`FIGMA_PROMPT`）-> 提取设计规格
- `plan approved` / `计划通过`（`TESTS_WRITTEN`）-> 进入实现
- `/status` -> 查看状态
- `/resume` / `继续` / `恢复` -> 从当前状态继续

## CLAUDE_TASK_PENDING

当脚本输出 `CLAUDE_TASK_PENDING` 时：

1. 读取 `{PROJECT_DIR}/doc/.claude-task.md`
2. 读取 `{PROJECT_DIR}/doc/.claude-task-meta.json`
3. 按 `role` 执行该任务
4. 完成后先运行 `bash ~/.claude/orchestrator.sh --ag transition {next_state} {PROJECT_DIR}`
5. 如果 `next_node_type == AUTO`，再运行 `bash ~/.claude/orchestrator.sh --ag auto-run {PROJECT_DIR}`
6. 如果 `next_node_type` 是 `USER_GATE` / `PLAN_GATE` / `INTERACTIVE`，不要 auto-run，改为运行 `bash ~/.claude/orchestrator.sh --ag status {PROJECT_DIR}` 并等待用户信号

不要把它理解成“Claude 接管所有角色”。这是同一 `role` 的人工执行器接管。

## 常用命令

```bash
bash ~/.claude/orchestrator.sh --ag init <project_dir>
bash ~/.claude/orchestrator.sh --ag onboard <project_dir>
bash ~/.claude/orchestrator.sh --ag signal "approved" <project_dir>
bash ~/.claude/orchestrator.sh --ag signal "figma ready <url>" <project_dir>
bash ~/.claude/orchestrator.sh --ag signal "plan approved" <project_dir>
bash ~/.claude/orchestrator.sh --ag status <project_dir>
bash ~/.claude/orchestrator.sh --ag auto-run <project_dir>
```

## 需求模式确认

在已有项目上推进需求时，进入 PRD 讨论前，或者没有 PRD 但已经要讨论前端方案时，如果用户还没明确本次模式，先主动确认：

- `extend`
- `modify`
- `refactor`
- `redesign`

推荐问法：

`这次是在现有项目上做 extend、modify、refactor 还是 redesign？`

在用户确认前，不要默认按 `refactor` 或 `redesign` 推进。

## 约束

1. 先做项目记忆检查，再读运行态文件。
2. `--ag` 模式下不要调用 `claude -p` 来执行 Claude 任务。
3. `CLAUDE_TASK_PENDING` 必须先执行任务，再按 meta 里的 `next_state` 转状态。
4. FE/BE 失败时允许 fallback，但 `role` 不变。
5. 完成重要改造后，主动判断是否应更新项目记忆。
6. 如果项目使用轻量验收契约，设计审查和视觉审查必须先读 `doc/acceptance-contract.json`。
