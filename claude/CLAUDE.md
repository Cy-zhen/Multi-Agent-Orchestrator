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
5. 再运行 `bash ~/.claude/orchestrator.sh --ag auto-run {PROJECT_DIR}`

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

## 约束

1. 先做项目记忆检查，再读运行态文件。
2. `--ag` 模式下不要调用 `claude -p` 来执行 Claude 任务。
3. `CLAUDE_TASK_PENDING` 必须先执行任务，再按 meta 里的 `next_state` 转状态。
4. FE/BE 失败时允许 fallback，但 `role` 不变。
5. 完成重要改造后，主动判断是否应更新项目记忆。
