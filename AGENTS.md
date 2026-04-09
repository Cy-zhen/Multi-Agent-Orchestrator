

<!-- PROJECT_MEMORY_START -->
## Project Memory Summary

- Full memory: `/Users/cy-zhen/.project-memory/projects/multi-agent-orchestrator/memory.md`
- Source: `# multi-agent-orchestrator - 项目记忆`

### TL;DR

- 这是一个多 Agent 开发编排器，但当前主要操作者是 Antigravity
- Git 仓库副本在 `/Users/cy-zhen/Desktop/multi-agent-orchestrator`
- 真正 live 的运行入口不在仓库里，而在 `~/.claude/` 和 `~/.gemini/antigravity/`
- 如果只改仓库副本，Antigravity / Claude CLI 不会自动生效，通常还要手动 `cp` 同步

### Source of Truth

- GitHub 上传副本: `/Users/cy-zhen/Desktop/multi-agent-orchestrator`
- Claude live 入口: `~/.claude/CLAUDE.md`
- Claude live 编排器脚本: `~/.claude/orchestrator.sh`
- Claude live 编排器目录: `~/.claude/orchestrator/`
- Antigravity live skill: `~/.gemini/antigravity/skills/multi-agent-orchestrator/SKILL.md`
- 项目记忆系统: `~/.project-memory/`

### Operating Rules

- 当前主要由 Antigravity 操作所有 Agent；它是主操作面
- Antigravity 负责编排和文档类任务，不应该直接写业务前后端代码
- FE 主要由 Gemini CLI 执行
- BE 和 QA 主要由 Codex CLI 执行
- `doc/state.json` 是运行态，不是长期记忆
- 项目记忆是长期上下文，优先级在新会话恢复时高于 `doc/state.json`

### Common Commands

- 查看项目记忆状态:
  - `bash ~/.project-memory/bin/pmem.sh status "/Users/cy-zhen/Desktop/multi-agent-orchestrator"`
- 加载项目记忆:
  - `bash ~/.project-memory/bin/pmem.sh load "/Users/cy-zhen/Desktop/multi-agent-orchestrator"`
- 查看工作流状态:
  - `bash ~/.claude/orchestrator.sh --ag status /Users/cy-zhen/Desktop/multi-agent-orchestrator`
- 恢复自动执行:
  - `bash ~/.claude/orchestrator.sh --ag auto-run /Users/cy-zhen/Desktop/multi-agent-orchestrator`

### Pitfalls

- 现象: 改了仓库里的 `claude/CLAUDE.md` 或 `antigravity/.../SKILL.md`，实际行为没变
  - 原因: live 文件不在仓库里
  - 正解: 同步到 `~/.claude/CLAUDE.md` 或 `~/.gemini/antigravity/skills/.../SKILL.md`
- 现象: 某个 Agent 明明装过 skill，但运行时像没装一样
  - 原因: Antigravity / Gemini CLI / Claude CLI / Codex CLI 的 skills 目录彼此独立
  - 正解: 分别检查 4 个目录，不要假设装一个就全都有

### Open Issues

- `orchestrator.sh` 的端到端测试还没系统跑完
- “轻量任务模式”还没有实现
  - 目标是支持不走完整状态机，直接处理小 UI / 小文档 / 小规则修改
- 项目记忆系统之前只有 `status/load/init` 这类基础能力
  - 现在已补成更适合 Agent 直接消费的版本，但还没做更强的结构化输出

## Direct-Run Guidance

> 只适用于直接在各 CLI 内单跑，不适用于 orchestrator 已经派发好的链式任务。

### Codex Direct Run

- 默认职责仍然是 BE / QA，不要因为装了 design skills 就默认去接 FE 角色
- 如果当前项目存在 `doc/acceptance-contract.json`：
  - 在开始实现、测试、review 之前先读它
  - 把它当作断上下文后的验收事实源，不要只靠会话记忆
  - 如果你做的是 QA / 验收，优先核对：
    - 关键页面 / 路由
    - P0 用户路径
    - 必测 UI 状态
    - 不可回归项
    - 截图证据清单
- 如果你单兵模式直接做所有内容：
  - 仍然要分别产出 `doc/fe-self-check.md` 和 `doc/be-self-check.md`（按实际触及层）
  - 如果有 UI 改动，至少做一轮最小前端 smoke
  - 最后跑 `python3 orchestrator/acceptance/consistency.py .`
- 如果用户直接要求 Codex 处理 UI / 前端设计 / 视觉审查：
  - 先读 `~/.codex/skills/frontend-design/SKILL.md`
  - 再按场景补读：
    - `typeset`
    - `colorize`
    - `arrange`
    - `animate`
    - `adapt`
    - `harden`
    - `distill`
    - `polish`
    - `audit`
    - `normalize`
    - `extract`
    - `critique`
- 如果只是 BE 在实现 API、数据模型、测试：
  - `frontend-design` 仅在接口会明显影响 UI 状态设计时参考
  - 不要让 design skills 反客为主，覆盖后端主职责
  - 如果改动会影响前端状态或验收路径，更新 `doc/acceptance-contract.json`
  - 后端完成后必须更新 `doc/be-self-check.md`

### Claude Direct Run

- 如果当前项目存在 `doc/acceptance-contract.json`：
  - 先读取它，再决定设计审查范围、视觉检查清单、或 handoff 内容
  - 不要脱离契约自由扩展审查范围，除非明确记录偏差原因
  - 如果你在单兵模式下直接做实现，也要要求对应层提交自测报告
- 如果直接做设计 prompt / 设计审查：
  - 先读 `~/.claude/skills/frontend-design/SKILL.md`
  - 再按任务补读 `typeset`, `colorize`, `arrange`, `adapt`, `animate`, `critique`, `distill`, `polish`
- 如果只是编排流程、状态推进、文档协调：
  - 不需要为了“形式正确”去读整套设计 skills

### Gemini Direct Run

- 如果当前项目存在 `doc/acceptance-contract.json`：
  - 在开始 FE 实现前先读它
  - 把它当作本轮 UI 范围、关键路径、状态覆盖和截图证据的约束
  - FE 完成后如有 UI 变更，负责更新它
  - FE 完成后还要写 `doc/fe-self-check.md`
- 如果直接做 FE 实现或 UI 重构：
  - 先读 `~/.gemini/skills/frontend-design/SKILL.md`
  - 再按任务补读 `typeset`, `colorize`, `arrange`, `animate`, `adapt`, `harden`, `distill`, `polish`, `audit`
- 如果只是在消费已有设计稿并做小修：
  - 至少保持 `frontend-design` + 本次问题直接相关的 1-2 个 skill

<!-- PROJECT_MEMORY_END -->
