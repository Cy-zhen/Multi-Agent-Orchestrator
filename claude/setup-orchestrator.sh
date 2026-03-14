#!/bin/bash
# ~/.claude/setup-orchestrator.sh
# 在目标项目中初始化多 Agent Orchestrator 工作流
#
# 用法:
#   bash ~/.claude/setup-orchestrator.sh                 # 当前目录
#   bash ~/.claude/setup-orchestrator.sh /path/to/project # 指定目录
#
# 功能:
#   1. 创建项目级目录结构 (doc/logs, doc/tests)
#   2. 初始化 doc/state.json（如不存在）
#   3. 确保 git 已初始化（Codex 需要）
#   4. 添加 .gitignore 条目
#   5. 写入首条日志

set -e

TARGET="${1:-$(pwd)}"
PROJECT_NAME=$(basename "$TARGET")

echo "🚀 初始化 Multi-Agent Orchestrator → $TARGET"

# 1. 创建项目级目录结构
mkdir -p "$TARGET/doc/logs"
mkdir -p "$TARGET/doc/tests"
echo "✅ 项目目录结构已创建"

# 2. 初始化 state.json（如不存在）
STATE_FILE="$TARGET/doc/state.json"
if [ ! -f "$STATE_FILE" ]; then
  cat > "$STATE_FILE" << EOF
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
  echo "✅ 初始化 doc/state.json (state: IDEA, project: $PROJECT_NAME)"
else
  echo "⚠️  doc/state.json 已存在，跳过初始化"
fi

# 3. 确保 git 已初始化（Codex 需要）
if [ ! -d "$TARGET/.git" ]; then
  cd "$TARGET" && git init
  echo "✅ Git 已初始化"
else
  echo "✅ Git 已存在"
fi

# 4. 添加 .gitignore 条目（忽略运行时状态和日志）
GITIGNORE="$TARGET/.gitignore"
if ! grep -q "doc/state.json" "$GITIGNORE" 2>/dev/null; then
  echo "" >> "$GITIGNORE"
  echo "# Orchestrator runtime (不提交运行时状态)" >> "$GITIGNORE"
  echo "doc/state.json" >> "$GITIGNORE"
  echo "doc/logs/" >> "$GITIGNORE"
  echo "✅ .gitignore 已更新"
fi

# 5. 确保 logger 可执行
chmod +x "$HOME/.claude/logger.sh" 2>/dev/null || true

# 6. 写入第一条日志
cd "$TARGET"
bash "$HOME/.claude/logger.sh" state_change "系统初始化完成，状态: IDEA，项目: $PROJECT_NAME" "orchestrator"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 初始化完成！"
echo ""
echo "项目结构:"
echo "  doc/"
echo "    state.json        ← 运行时状态"
echo "    prd.md            ← PRD 文档（待生成）"
echo "    logs/"
echo "      workflow.jsonl  ← 结构化日志"
echo "      summary.md      ← 流程追踪报告"
echo "    tests/            ← 测试用例（待生成）"
echo ""
echo "全局配置（所有项目共享）:"
echo "  ~/.claude/"
echo "    orchestrator/SKILL.md  ← 调度逻辑"
echo "    agents/*.md            ← Agent 角色定义"
echo "    workflows/*.md         ← 工作流"
echo "    logger.sh              ← 日志系统"
echo ""
echo "开始使用: 向 Claude 描述你的产品想法即可"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
