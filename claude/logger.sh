#!/bin/bash
# ~/.claude/logger.sh
# 工作流全链路日志系统
# 用法: bash ~/.claude/logger.sh <event> "<message>" [agent] [session_id]
#
# 示例:
#   bash ~/.claude/logger.sh state_change "IDEA → PRD_DRAFT"
#   bash ~/.claude/logger.sh agent_start "BE 开始审查 PRD" "be" "sess_abc123"
#   bash ~/.claude/logger.sh agent_done "PRD 审查通过" "be" "sess_abc123"
#   bash ~/.claude/logger.sh error "Codex 超时" "be" "sess_abc123"

set -e

EVENT="${1:-unknown}"
MESSAGE="${2:-}"
AGENT="${3:-orchestrator}"
SESSION_ID="${4:-}"

# 日志目录：项目级 doc/logs/（遵循用户规则：进展文档在 doc 目录下）
LOG_DIR="doc/logs"
mkdir -p "$LOG_DIR"

# 时间戳
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DATE=$(date -u +"%Y-%m-%d")

# 日志文件路径
LOG_FILE="$LOG_DIR/workflow.jsonl"
DAILY_FILE="$LOG_DIR/${DATE}.log"
SUMMARY_FILE="$LOG_DIR/summary.md"

# 读取当前状态（优先项目级，回退全局模板）
STATE="UNKNOWN"
PROJECT="unknown"
if [ -f "doc/state.json" ]; then
  STATE=$(python3 -c "import json; d=json.load(open('doc/state.json')); print(d.get('state','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
  PROJECT=$(python3 -c "import json; d=json.load(open('doc/state.json')); print(d.get('project','unknown'))" 2>/dev/null || echo "unknown")
elif [ -f "$HOME/.claude/orchestrator/state.json" ]; then
  STATE=$(python3 -c "import json; d=json.load(open('$HOME/.claude/orchestrator/state.json')); print(d.get('current_state','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
  PROJECT=$(python3 -c "import json; d=json.load(open('$HOME/.claude/orchestrator/state.json')); print(d.get('project_name','unknown'))" 2>/dev/null || echo "unknown")
fi

# 事件级别映射
case "$EVENT" in
  error|agent_error|chain_break)       LEVEL="ERROR" ;;
  warn|retry|qa_failed)                LEVEL="WARN"  ;;
  state_change|checkpoint|done)        LEVEL="INFO"  ;;
  agent_start|agent_done|agent_output) LEVEL="DEBUG" ;;
  *)                                   LEVEL="INFO"  ;;
esac

# 图标映射
case "$EVENT" in
  error|agent_error|chain_break) ICON="⛔" ;;
  warn|retry)                    ICON="⚠️" ;;
  qa_failed)                     ICON="❌" ;;
  state_change)                  ICON="🔄" ;;
  checkpoint)                    ICON="⏸" ;;
  agent_start)                   ICON="🚀" ;;
  agent_done)                    ICON="✅" ;;
  prd_generated|prd_approved)    ICON="📋" ;;
  prd_updated)                   ICON="📝" ;;
  import_done)                   ICON="📦" ;;
  figma_ready)                   ICON="🎨" ;;
  tests_written)                 ICON="🧪" ;;
  implementation_start)          ICON="⚡" ;;
  qa_passed|done)                ICON="🎉" ;;
  *)                             ICON="ℹ️"  ;;
esac

# ── 1. JSONL 结构化日志（机器可读）──────────────────────────
JSON_ENTRY=$(python3 -c "
import json, sys
entry = {
    'ts': '$TS',
    'level': '$LEVEL',
    'event': '$EVENT',
    'state': '$STATE',
    'project': '$PROJECT',
    'agent': '$AGENT',
    'session_id': '$SESSION_ID',
    'message': $(echo "$MESSAGE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
}
print(json.dumps(entry, ensure_ascii=False))
" 2>/dev/null || echo "{\"ts\":\"$TS\",\"level\":\"$LEVEL\",\"event\":\"$EVENT\",\"state\":\"$STATE\",\"agent\":\"$AGENT\",\"message\":\"$MESSAGE\"}")

echo "$JSON_ENTRY" >> "$LOG_FILE"

# ── 2. 人类可读日志（按天归档）──────────────────────────────
HUMAN_LINE="[$TS] $ICON [$LEVEL] [$AGENT] [$STATE] $MESSAGE"
[ -n "$SESSION_ID" ] && HUMAN_LINE="$HUMAN_LINE (session: $SESSION_ID)"
echo "$HUMAN_LINE" >> "$DAILY_FILE"

# ── 3. 终端实时输出（只显示 INFO 及以上）──────────────────────
if [ "$LEVEL" != "DEBUG" ]; then
  echo "$ICON [$AGENT] $MESSAGE" >&2
fi

# ── 4. 更新 summary.md（状态变化时）─────────────────────────
if [ "$EVENT" = "state_change" ] || [ "$EVENT" = "done" ] || [ "$EVENT" = "error" ] || [ "$EVENT" = "checkpoint" ]; then
  python3 <<PYEOF
import json, os
from datetime import datetime

summary_file = "$SUMMARY_FILE"
log_file = "$LOG_FILE"

entries = []
if os.path.exists(log_file):
    with open(log_file) as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    entries.append(json.loads(line))
                except:
                    pass

state_changes = [e for e in entries if e.get('event') == 'state_change']
errors = [e for e in entries if e.get('level') == 'ERROR']
agent_starts = [e for e in entries if e.get('event') == 'agent_start']
agent_dones = [e for e in entries if e.get('event') == 'agent_done']

current_state = "$STATE"
project = "$PROJECT"

lines = [
    f"# 工作流追踪报告",
    f"",
    f"**项目**: {project}  ",
    f"**当前状态**: {current_state}  ",
    f"**最后更新**: $TS  ",
    f"",
    f"---",
    f"",
    f"## 状态流转历史",
    f"",
    f"| 时间 | 事件 | 说明 |",
    f"|------|------|------|",
]

for e in entries:
    if e.get('level') in ('INFO', 'WARN', 'ERROR') and e.get('event') not in ('agent_output',):
        ts_short = e.get('ts', '')[:19].replace('T', ' ')
        icon = ''
        ev = e.get('event', '')
        if 'error' in ev: icon = '⛔'
        elif 'warn' in ev or 'failed' in ev: icon = '⚠️'
        elif 'done' in ev or 'approved' in ev or 'passed' in ev: icon = '✅'
        elif 'start' in ev: icon = '🚀'
        elif 'state_change' in ev: icon = '🔄'
        elif 'checkpoint' in ev: icon = '⏸'
        else: icon = 'ℹ️'
        agent = e.get('agent', '')
        msg = e.get('message', '')
        lines.append(f"| {ts_short} | {icon} [{agent}] | {msg} |")

lines += [
    f"",
    f"---",
    f"",
    f"## Agent 执行统计",
    f"",
    f"| Agent | 启动次数 | 完成次数 | 错误次数 |",
    f"|-------|---------|---------|---------| ",
]

agents = set(e.get('agent') for e in entries if e.get('agent'))
for ag in sorted(agents):
    starts = sum(1 for e in agent_starts if e.get('agent') == ag)
    dones = sum(1 for e in agent_dones if e.get('agent') == ag)
    errs = sum(1 for e in errors if e.get('agent') == ag)
    lines.append(f"| {ag} | {starts} | {dones} | {errs} |")

lines += [
    f"",
    f"---",
    f"",
    f"## 错误记录",
    f"",
]

if errors:
    for e in errors:
        ts_short = e.get('ts', '')[:19].replace('T', ' ')
        lines.append(f"- **{ts_short}** [{e.get('agent','')}] {e.get('message','')}")
else:
    lines.append("_暂无错误_")

lines += [
    f"",
    f"---",
    f"",
    f"## 日志文件",
    f"",
    f"- 结构化日志（JSONL）: `doc/logs/workflow.jsonl`",
    f"- 今日日志: `doc/logs/$DATE.log`",
    f"- 本报告: `doc/logs/summary.md`",
]

with open(summary_file, 'w') as f:
    f.write('\n'.join(lines) + '\n')
PYEOF
fi

exit 0
