---
description: Initialize a new multi-agent development project
---

# /start — 初始化新项目

启动多 Agent 开发工作流，创建项目骨架和状态文件。

## Steps

1. **创建项目目录结构**

```bash
mkdir -p doc/{logs,tests}
```

2. **初始化 state.json**

```bash
if [ ! -f "doc/state.json" ]; then
  PROJECT_NAME=$(basename "$(pwd)")
  cat > doc/state.json << EOF
{
  "state": "IDEA",
  "project": "$PROJECT_NAME",
  "prd_path": "doc/prd.md",
  "figma_url": null,
  "tests_path": "doc/tests/",
  "reflection_count": 0,
  "entry_point": "IDEA",
  "sessions": { "fe": null, "be": null, "qa": null },
  "chain_log": []
}
EOF
fi
```

3. **初始化 git（如果还不是 git 仓库）**

Codex CLI 需要在 git 仓库中运行：

```bash
git init 2>/dev/null || true
```

4. **确认工具可用**

```bash
which claude && echo "✅ Claude CLI" || echo "❌ Claude CLI not found"
which codex && echo "✅ Codex CLI" || echo "❌ Codex CLI not found"  
which gemini && echo "✅ Gemini CLI" || echo "❌ Gemini CLI not found"
```

5. **写入首条日志**

```bash
bash ~/.claude/logger.sh state_change "系统初始化完成，状态: IDEA" "orchestrator"
```

6. **输出就绪信号**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 状态: IDEA
🏗  项目: {PROJECT_NAME}
✅ 已完成: 项目初始化
⏭  下一步: 描述项目概念
📊 追踪报告: doc/logs/summary.md
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💡 请描述你的项目概念，Orchestrator 将自动派发 PM Agent 生成 PRD
```

> 或者使用快捷脚本: `bash ~/.claude/setup-orchestrator.sh`
