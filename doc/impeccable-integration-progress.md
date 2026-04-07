# Impeccable 前端设计 Skill 集成进展

> 更新时间：2026-04-06 16:42

## 状态：✅ 全部完成（含 Antigravity 补装 + 技能目录修复）

---

### 安装状态（最终版）

| 工具 | Skills 目录 | impeccable 数 | 总数 | 状态 |
|------|------------|-------------|------|------|
| **Antigravity** | `~/.gemini/antigravity/skills/` | **20/20** | 991 | ✅ 补装完成 |
| **Gemini CLI** | `~/.gemini/skills/` | 20/20 | 22 | ✅ |
| **Claude CLI** | `~/.claude/skills/` | 21/21 | — | ✅ |
| **Codex CLI** | `~/.codex/skills/` | 21/21 | — | ✅ |

> ⚠️ Antigravity 和 Gemini CLI 是**两个不同的 skills 目录**！装到 `~/.gemini/skills/` 不等于 Antigravity 能用。

---

### 问题排查记录

#### 问题 1：Skills 安装位置错误（2026-03-29 发现）
- Gemini CLI skills 最初装到了项目级 `.gemini/skills/`
- **修复**：移到全局 `~/.gemini/skills/`

#### 问题 2：dispatch template 只列路径，Agent 不读（2026-04-06 发现）
- **根因**：orchestrator 通过 `gemini -p` / `codex exec --full-auto` 派发时，Agent 收到完整 prompt 后直接执行，跳过了 skills 的被动触发流程
- **修复**：技能目录注入 — 在 template 中加 `cat` 读取指令和按需技能表

#### 问题 3：Antigravity 缺少 19 个 impeccable skills（2026-04-06 发现）
- **根因**：Antigravity 的 skills 目录是 `~/.gemini/antigravity/skills/`，不是 `~/.gemini/skills/`
- 之前只装了 `frontend-design`，缺少 audit/polish/colorize/animate 等 19 个
- **修复**：从 `~/.gemini/skills/` 复制到 `~/.gemini/antigravity/skills/`

---

### Dispatch Template 技能目录注入

| 模板 | Agent/CLI | 注入方式 |
|------|----------|---------|
| `fe-implementation.txt` | FE/Gemini | 10 技能目录表 + `cat` 必读指令 |
| `fe-review-prd.txt` | FE/Gemini | 轻量推荐 + `cat` 指令 |
| `design-review-plan.txt` | Gstack/Claude | 7 维度对应参考文件表 |
| `design-review-visual.txt` | Gstack/Claude | 8 维度对应技能/参考文件表 |

---

### 架构启示

1. **`-p` 派发 = skills 不自动触发**：所有通过 dispatch prompt 派发的任务需要显式 `cat` 指令引导 Agent 读取 skills
2. **三个 skills 目录互相独立**：Antigravity / Gemini CLI / Claude CLI 各有自己的 skills 目录，装了一个不等于另一个能用
3. **直接用 CLI（交互模式）skills 正常工作**：只有 `-p` 单次派发模式有此限制
