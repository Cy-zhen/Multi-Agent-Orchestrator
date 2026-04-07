

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

<!-- PROJECT_MEMORY_END -->

