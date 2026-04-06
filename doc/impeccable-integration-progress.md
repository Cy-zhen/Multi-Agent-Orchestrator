# Impeccable 前端设计 Skill 集成进展

> 更新时间：2026-04-06 16:10

## 状态：✅ 全部完成（含技能目录修复）

### 问题排查（2026-04-06）

**根因**：orchestrator.sh 通过 `gemini -p` / `codex exec --full-auto` 派发任务时，Agent 收到的是一个完整的 prompt 指令，跳过了正常 CLI 启动时的 skills 触发流程。Skills 虽然已安装且 CLI 能发现它们（`gemini skills list` 全部 Enabled），但 Agent 不会主动读取。

**解决方案：技能目录注入（Skill Catalog）**
- 不注入 skill 全文（避免上下文爆炸）
- 在 dispatch template 中加入 ~20 行技能清单 + `cat` 读取指令
- Agent 按需自行读取相关 skill → 只加载真正用到的

### Dispatch Template 更新（v2 技能目录版）

| 模板 | Agent/CLI | 变更 |
|------|----------|------|
| `fe-implementation.txt` | FE/Gemini | 10 个技能目录表 + 必读 `cat` 指令 |
| `fe-review-prd.txt` | FE/Gemini | 替换 `{{SKILLS_INJECTION}}` → 轻量推荐 |
| `design-review-plan.txt` | Gstack/Claude | 7 维度对应 7 个参考文件表 |
| `design-review-visual.txt` | Gstack/Claude | 8 维度对应技能/参考文件表 |

### 安装状态（未变）

| CLI | Skills | 路径 | 状态 |
|-----|--------|------|------|
| Claude Code | 21 | `~/.claude/skills/` | ✅ 全局 |
| Gemini CLI | 22 | `~/.gemini/skills/` | ✅ 全局 (含 pretext-reference) |
| Codex CLI | 21+ | `~/.codex/skills/` | ✅ 全局 |

### 关键发现

- Gemini CLI 的 skills 机制是**被动触发**的：`-p` 模式下，prompt 太具体时 Agent 不会触发 skills
- 解决方式：在 dispatch template 中显式告诉 Agent "先 `cat` 读取这个文件"
- 这是一个**架构级限制**：所有通过 dispatch prompt 派发的任务都需要在 template 中显式引导 Agent 读取 skills
