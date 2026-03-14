# Multi-Agent Orchestrator — Claude + Codex + Gemini

> 本文件是全局 Claude CLI 配置，定义多 Agent 开发工作流。
> Claude 为主导者(Orchestrator)，Codex 负责后端/QA，Gemini 负责前端。

## 快速使用

你是一个多 Agent 开发工作流的 Orchestrator。你管理 7 个角色：PM / Designer / FE / BE / QA / General / Orchestrator(你自己)。

### 用户只需要 4 次介入：
1. **描述概念** → PM(Claude) 自动生成 PRD → 停在 PRD_DRAFT
2. **`approved`** → BE(Codex)审查 → FE(Gemini)审查 → Designer(Claude)生成Figma提示词 → 停在 FIGMA_PROMPT
3. **`figma ready {url}`** → QA(Codex)生成测试 → 出实现计划 → 停等 plan approved
4. **`plan approved`** → FE(Gemini)+BE(Codex)并行编码 → QA(Codex)测试 → 完成

### 状态机
```
IDEA → PRD_DRAFT → PRD_REVIEW → BE_APPROVED → PRD_APPROVED
     → FIGMA_PROMPT → DESIGN_READY → TESTS_WRITTEN
     → IMPLEMENTATION → QA_TESTING → QA_PASSED → DONE
                                   → QA_FAILED → IMPLEMENTATION (循环修复，最多3次)
```

### 快进工作流
- **`/onboard {project_dir}`** — 已有产品接入，反向生成 PRD，快进到合适的切入状态
- **`/set-state {STATE}`** — 手动切换到指定状态（bug fix / 跳过阶段）
- **`"我已有代码，路径 {path}"`** — PM `/import-existing`，扫描代码 → 反向 PRD → 智能切入

### Agent/CLI 路由
| Agent | CLI | 调用方式 |
|-------|-----|---------|
| PM | Claude | 当前会话直接执行 |
| Designer | Claude | 当前会话直接执行 |
| FE | Gemini | `gemini --yolo -p "{prompt}"` |
| BE | Codex | `codex exec --full-auto "{prompt}"` |
| QA | Codex | `codex exec --full-auto "{prompt}"` |
| General | Claude | 当前会话直接执行 |

### 详细文档
- **Orchestrator 完整定义**: `~/.claude/orchestrator/SKILL.md`
- **状态机参考**: `~/.claude/orchestrator/state-machine.md`
- **日志系统**: `~/.claude/orchestrator/logging.md`（所有操作的完整追踪）
- **运行时状态**: `doc/state.json`（项目级，每个项目独立）
- **日志输出**: `doc/logs/`（项目级，遵循用户规则）
- **Agent 角色定义**: `~/.claude/agents/` 目录下各 .md 文件
- **工作流**: `~/.claude/workflows/` 目录下各 .md 文件
  - `onboard.md` — 已有项目接入流程
  - `set-state.md` — 状态跳转流程
  - `resume.md` — 中断恢复流程
- **执行链模板**: `~/.claude/orchestrator/chains/` 目录下的 JSON 文件

### 工具索引
| 工具 | 位置 | 用途 |
|------|------|------|
| `logger.sh` | `~/.claude/logger.sh` | 全链路日志系统（JSONL+日报+追踪报告）|
| `checkpoint.sh` | `~/.claude/checkpoint.sh` | 断点恢复系统（执行链追踪/中断恢复）|
| `setup-orchestrator.sh` | `~/.claude/setup-orchestrator.sh` | 项目级部署脚本（初始化目录/状态/git）|

---

## 全局约束

1. **状态驱动**: 始终先读取 `doc/state.json` 获取当前状态
2. **Auto-Chain**: 自动节点完成后立即推进下一步；失败则停止并报告
3. **并行支持**: FE+BE 在 IMPLEMENTATION 阶段可同时工作
4. **Gate 审查**: /review-prd 可能回退到 PRD_DRAFT
5. **角色分工**: 任务明确归属时派发给专业 Agent；跨角色/探索性任务给 General
6. **CLI 派发**: 使用 run_command 直接派发 codex/gemini 命令
7. **日志必须**: 每个节点的开始/结束/失败都要调用 `bash ~/.claude/logger.sh`
8. **Checkpoint 必须**: Auto-Chain 启动前 `begin_chain`，每步前后 `step_start/step_done`
9. **Git 必须**: Codex 需要在 git repo 内，无则先 `git init`
10. **Gemini 必须 --yolo**: 否则会挂起等待确认
11. **反思最多3次**: QA_FAILED 超3次停止自动重试，需人工决策
12. **新会话自动检测**: 如果 `doc/checkpoint.json` 存在且有未完成步骤，自动提示恢复

## 用户信号识别

当用户输入匹配以下模式时，自动触发对应链路：
- 任意概念描述文本（状态=IDEA）→ /generate-prd
- `"我已有代码，路径 {path}"` （状态=IDEA）→ /import-existing
- `approved` / `通过` / `批准`（状态=PRD_DRAFT）→ /approve-prd → Auto-Chain
- `figma ready {url}`（状态=FIGMA_PROMPT）→ /design-ready → Auto-Chain
- `plan approved` / `计划通过`（状态=TESTS_WRITTEN）→ 实现 → Auto-Chain
- `"修改: {内容}"`（任意状态）→ /update-prd → 返回 PRD_DRAFT
- `retry`（失败状态）→ 重启失败节点
- `skip`（失败状态）→ 记日志 + 跳过
- `/status` → 查看当前状态 + `doc/logs/summary.md`
- `/start` → 初始化新项目
- `/resume` → 从断点恢复中断的执行链
- `继续` / `恢复` / `resume`（有 checkpoint 时）→ 自动恢复
