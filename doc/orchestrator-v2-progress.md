# 编排器 v2 升级进展

**最后更新**: 2025-03-25 全部完成 + 同步

## 完成状态

| Phase | 内容 | 状态 |
|-------|------|------|
| Phase 0 | Skills 框架（4 agent × 2 skills + _config.yaml） | ✅ |
| Phase 1 | 9 个 ReAct 模板升级 | ✅ |
| Phase 1.5 | 渐进式披露（inject_at + per-phase {{SKILLS_xxx}}） | ✅ |
| Phase 2 | Python 编排器（loader + base + orchestrator） | ✅ |
| Phase 3 | 验收系统（AcceptanceChecker + orchestrator 集成） | ✅ |
| Phase 4 | LangGraph StateGraph + SQLite checkpointer | ✅ |
| Phase 5 | LangSmith @traceable 集成 | ✅ |
| Bugfix | GEMINI.md 角色混淆修复 + 代码同步 | ✅ |

## 代码位置

| 位置 | 说明 |
|------|------|
| `~/.claude/orchestrator/` | 运行时目录（orchestrator.sh 使用） |
| `项目/orchestrator/` | 项目内镜像（git 跟踪用） |

> 两者内容一致，使用 `rsync` 同步。运行时用 `~/.claude/` 路径。

## GEMINI.md 修复

**问题**: `antigravity/GEMINI.md` 原先包含 Orchestrator 角色定义，Gemini CLI 读取后以为自己是编排器。

**修复**: 重写为 FE Agent 角色定义，明确告诉 Gemini 它是前端工程师，不是编排器。

## 框架使用方式

### 从 Antigravity (本对话) 使用

```bash
# 1. 初始化项目
bash ~/.claude/orchestrator.sh --ag init <project_dir>

# 2. 接入已有项目
bash ~/.claude/orchestrator.sh --ag onboard <project_dir>

# 3. 自动运行（遇到 CLAUDE_TASK_PENDING 时由 Antigravity 执行 PM/Designer 任务）
bash ~/.claude/orchestrator.sh --ag auto-run <project_dir>

# 4. 查看状态
bash ~/.claude/orchestrator.sh --ag status <project_dir>
```

### LangGraph 版（新）

```bash
python3 ~/.claude/orchestrator/graph.py run <project_dir>     # 运行
python3 ~/.claude/orchestrator/graph.py resume <project_dir>  # 恢复
python3 ~/.claude/orchestrator/graph.py status <project_dir>  # 状态
python3 ~/.claude/orchestrator/graph.py visualize             # 流程图
```
