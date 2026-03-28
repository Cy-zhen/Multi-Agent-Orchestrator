# 编排器工作进展

**最后更新**: 2026-03-25 23:05

## ✅ Game Studio Skill

基于 [Claude-Code-Game-Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) 创建了 `game-studio` skill（291 行），安装位置：
- `~/.claude/skills/game-studio/SKILL.md`
- `~/.gemini/antigravity/skills/game-studio/SKILL.md`
- Repo: `claude/skills/game-studio/SKILL.md`

## ✅ 已完成

### 1. Figma → Stitch 文档迁移（8 个文件）

| 文件 | 状态 |
|------|------|
| `claude/agents/designer.md` | ✅ Stitch 术语 + Code to Clipboard 交付物说明 + FE 消费指南 |
| `claude/orchestrator/dispatch-templates/designer-figma-prompt.txt` | ✅ Stitch Design Tokens + 交付物提醒 |
| `claude/agents/fe.md` | ✅ Stitch 消费步骤 + `{{DESIGN_CODE}}` 变量 |
| `claude/orchestrator/dispatch-templates/fe-implementation.txt` | ✅ Design URL (Stitch) + `{{DESIGN_CODE}}` 段 |
| `claude/orchestrator/state-machine.md` | ✅ 描述更新 + 信号别名 |
| `claude/CLAUDE.md` | ✅ 文案同步 |
| `claude/orchestrator/SKILL.md` | ✅ 技能表 + 信号表 + 日志 |
| `claude/orchestrator/skills/dispatch-agent.md` | ✅ 变量表 + 模板引用 |

### 2. 设计决策

- 内部状态名 `FIGMA_PROMPT` / `figma_url` 保持不变（代码零改动）
- 用户信号 `design ready` / `stitch ready` / `figma ready` 三种均可
- 新增 `{{DESIGN_CODE}}` 变量用于 Stitch Code to Clipboard

### 3. 同步到 ~/.claude/（运行时目录）

所有 8 个修改文件已从 repo 复制到 `~/.claude/`，路径引用（`~/.claude/orchestrator/dispatch-templates/...`）验证正确。

## 📋 后续可选

- `workflows/set-state.md`、`onboard.md`、`approve.md`、`status.md` 中的 Figma 文案可批量更新
- `pm.md` 第 400 行"无 Figma"描述可更新
