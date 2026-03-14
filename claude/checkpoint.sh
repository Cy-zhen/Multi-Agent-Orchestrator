#!/bin/bash
# ~/.claude/checkpoint.sh
# 断点恢复系统 — 检查点管理脚本
#
# 用法:
#   bash ~/.claude/checkpoint.sh begin_chain <chain_name> <chain_file>
#   bash ~/.claude/checkpoint.sh step_start <step_id>
#   bash ~/.claude/checkpoint.sh step_done <step_id> [result_json]
#   bash ~/.claude/checkpoint.sh step_fail <step_id> <error_message>
#   bash ~/.claude/checkpoint.sh finish_chain
#   bash ~/.claude/checkpoint.sh read_status

set -euo pipefail

CHECKPOINT_FILE="doc/checkpoint.json"
PLAN_FILE="doc/execution-plan.md"

# ─── 工具函数 ───────────────────────────────────────────────

get_timestamp() {
  date +"%Y-%m-%dT%H:%M:%S%z"
}

ensure_doc_dir() {
  mkdir -p doc
}

# 从 checkpoint.json 渲染 execution-plan.md
generate_plan_md() {
  if [ ! -f "$CHECKPOINT_FILE" ]; then return 0; fi

  python3 << 'PYEOF'
import json

CHECKPOINT = "doc/checkpoint.json"
PLAN = "doc/execution-plan.md"

with open(CHECKPOINT) as f:
    cp = json.load(f)

icon_map = {'done':'✅ 完成','running':'🔄 执行中','pending':'⏳ 待执行','failed':'❌ 失败','skipped':'⏭ 已跳过'}
agent_cli = {'fe':'Gemini','be':'Codex','qa':'Codex','pm':'Claude','designer':'Claude','general':'Claude','orchestrator':'—'}

done_count = sum(1 for s in cp['steps'] if s['status'] in ('done','skipped'))
total = len(cp['steps'])
running = [s for s in cp['steps'] if s['status'] == 'running']
failed = [s for s in cp['steps'] if s['status'] == 'failed']

if done_count == total:
    overall = '✅ 已完成'
elif failed:
    overall = '❌ 已中断（失败）'
elif running:
    overall = '🔄 执行中'
else:
    overall = '⏳ 已中断'

start_short = cp.get('chain_started_at', '—')[:16].replace('T', ' ')
title = cp.get('chain_description', cp['active_chain'])
chain_name = cp['active_chain']

lines = []
lines.append(f'# 执行计划: {title}')
lines.append('')
lines.append(f'> **链名**: `{chain_name}`  |  **状态**: {overall}  |  **进度**: {done_count}/{total}  |  **启动**: {start_short}')
lines.append('')
lines.append('| # | 步骤 | Agent (CLI) | 状态 | 时间 | 备注 |')
lines.append('|---|------|------------|------|------|------|')

for step in cp['steps']:
    sid = step['id']
    desc = step.get('description', step['name'])
    agent = step.get('agent', '—')
    cli = agent_cli.get(agent, '—')
    agent_str = f'{agent} ({cli})' if cli != '—' else agent
    status = icon_map.get(step['status'], step['status'])

    ts = '—'
    if step.get('started_at'):
        ts = step['started_at'][11:16]
    if step.get('finished_at'):
        ts = step['finished_at'][11:16]

    note = '—'
    if step['status'] == 'running':
        note = '← **断点**'
    elif step['status'] == 'failed' and step.get('error'):
        note = step['error'][:50]
    elif step['status'] == 'done' and step.get('result'):
        r = step['result']
        note = str(r)[:50] if r else '—'

    lines.append(f'| {sid} | {desc} | {agent_str} | {status} | {ts} | {note} |')

if running:
    lines.append('')
    lines.append('> [!WARNING]')
    lines.append(f'> 执行在 **Step {running[0]["id"]}** 中断。输入 `/resume` 或重新进入会话自动恢复。')
elif failed:
    lines.append('')
    lines.append('> [!CAUTION]')
    lines.append(f'> **Step {failed[0]["id"]}** 执行失败: {failed[0].get("error","未知错误")}')

with open(PLAN, 'w') as f:
    f.write('\n'.join(lines) + '\n')
PYEOF
}

# ─── 命令实现 ───────────────────────────────────────────────

cmd_begin_chain() {
  local chain_name="${1:?用法: begin_chain <chain_name> <chain_template_file>}"
  local chain_file="${2:?缺少链模板文件路径}"

  ensure_doc_dir

  if [ ! -f "$chain_file" ]; then
    echo "❌ 链模板不存在: $chain_file" >&2
    exit 1
  fi

  local ts
  ts=$(get_timestamp)

  # 从模板读取 steps，注入到 checkpoint.json
  python3 -c "
import json, sys

with open('$chain_file') as f:
    template = json.load(f)

checkpoint = {
    'version': 1,
    'macro_state': '',
    'active_chain': '$chain_name',
    'chain_description': template.get('description', ''),
    'chain_started_at': '$ts',
    'last_updated': '$ts',
    'steps': [],
    'interrupted_at': None
}

for i, step in enumerate(template['steps'], 1):
    checkpoint['steps'].append({
        'id': i,
        'name': step['name'],
        'description': step.get('description', ''),
        'agent': step.get('agent', 'orchestrator'),
        'status': 'pending',
        'started_at': None,
        'finished_at': None,
        'result': None,
        'error': None
    })

# 读取当前 macro_state
try:
    with open('doc/state.json') as f:
        state = json.load(f)
        checkpoint['macro_state'] = state.get('state', 'UNKNOWN')
except FileNotFoundError:
    checkpoint['macro_state'] = 'UNKNOWN'

with open('$CHECKPOINT_FILE', 'w') as f:
    json.dump(checkpoint, f, indent=2, ensure_ascii=False)

print(f'✅ 执行链 [{checkpoint[\"active_chain\"]}] 已初始化，共 {len(checkpoint[\"steps\"])} 步')
"

  generate_plan_md
  echo "📋 执行计划已生成: $PLAN_FILE"
}

cmd_step_start() {
  local step_id="${1:?用法: step_start <step_id>}"
  local ts
  ts=$(get_timestamp)

  python3 -c "
import json

with open('$CHECKPOINT_FILE') as f:
    cp = json.load(f)

found = False
for step in cp['steps']:
    if step['id'] == $step_id:
        step['status'] = 'running'
        step['started_at'] = '$ts'
        found = True
        print(f'▶ Step {step[\"id\"]}: {step[\"name\"]} — 开始执行 ({step[\"agent\"]})')
        break

if not found:
    print(f'❌ 未找到 step_id=$step_id')
    exit(1)

cp['last_updated'] = '$ts'

with open('$CHECKPOINT_FILE', 'w') as f:
    json.dump(cp, f, indent=2, ensure_ascii=False)
"

  generate_plan_md
}

cmd_step_done() {
  local step_id="${1:?用法: step_done <step_id> [result_json]}"
  local result="${2:-null}"
  local ts
  ts=$(get_timestamp)

  python3 -c "
import json

with open('$CHECKPOINT_FILE') as f:
    cp = json.load(f)

found = False
for step in cp['steps']:
    if step['id'] == $step_id:
        step['status'] = 'done'
        step['finished_at'] = '$ts'
        try:
            step['result'] = json.loads('$result')
        except:
            step['result'] = '$result' if '$result' != 'null' else None
        found = True
        print(f'✅ Step {step[\"id\"]}: {step[\"name\"]} — 完成')
        break

if not found:
    print(f'❌ 未找到 step_id=$step_id')
    exit(1)

cp['last_updated'] = '$ts'

# 检查是否所有步骤都完成
all_done = all(s['status'] in ('done', 'skipped') for s in cp['steps'])
if all_done:
    print(f'🎉 执行链 [{cp[\"active_chain\"]}] 全部完成！')

with open('$CHECKPOINT_FILE', 'w') as f:
    json.dump(cp, f, indent=2, ensure_ascii=False)
"

  generate_plan_md
}

cmd_step_fail() {
  local step_id="${1:?用法: step_fail <step_id> <error_message>}"
  local error="${2:?缺少错误信息}"
  local ts
  ts=$(get_timestamp)

  python3 -c "
import json

with open('$CHECKPOINT_FILE') as f:
    cp = json.load(f)

found = False
for step in cp['steps']:
    if step['id'] == $step_id:
        step['status'] = 'failed'
        step['finished_at'] = '$ts'
        step['error'] = '''$error'''
        found = True
        print(f'❌ Step {step[\"id\"]}: {step[\"name\"]} — 失败: $error')
        break

if not found:
    print(f'❌ 未找到 step_id=$step_id')
    exit(1)

cp['last_updated'] = '$ts'
cp['interrupted_at'] = '$ts'

with open('$CHECKPOINT_FILE', 'w') as f:
    json.dump(cp, f, indent=2, ensure_ascii=False)
"

  generate_plan_md
}

cmd_step_skip() {
  local step_id="${1:?用法: step_skip <step_id>}"
  local ts
  ts=$(get_timestamp)

  python3 -c "
import json

with open('$CHECKPOINT_FILE') as f:
    cp = json.load(f)

found = False
for step in cp['steps']:
    if step['id'] == $step_id:
        step['status'] = 'skipped'
        step['finished_at'] = '$ts'
        found = True
        print(f'⏭ Step {step[\"id\"]}: {step[\"name\"]} — 已跳过')
        break

if not found:
    print(f'❌ 未找到 step_id=$step_id')
    exit(1)

cp['last_updated'] = '$ts'

with open('$CHECKPOINT_FILE', 'w') as f:
    json.dump(cp, f, indent=2, ensure_ascii=False)
"

  generate_plan_md
}

cmd_finish_chain() {
  if [ ! -f "$CHECKPOINT_FILE" ]; then
    echo "⚠ 无活跃执行链" >&2
    return 0
  fi

  local ts
  ts=$(get_timestamp)

  python3 -c "
import json, os

with open('$CHECKPOINT_FILE') as f:
    cp = json.load(f)

done_count   = sum(1 for s in cp['steps'] if s['status'] == 'done')
failed_count = sum(1 for s in cp['steps'] if s['status'] == 'failed')
total        = len(cp['steps'])

print(f'📊 执行链 [{cp[\"active_chain\"]}] 完成统计:')
print(f'   ✅ 完成: {done_count}/{total}')
if failed_count:
    print(f'   ❌ 失败: {failed_count}/{total}')
print(f'   ⏱ 开始: {cp[\"chain_started_at\"]}')
print(f'   ⏱ 结束: \"$ts\"')

# 归档到 doc/logs/chains/
os.makedirs('doc/logs/chains', exist_ok=True)
archive_name = f'doc/logs/chains/{cp[\"active_chain\"]}_{\"$ts\".replace(\":\", \"\")}.json'
cp['finished_at'] = '$ts'
with open(archive_name, 'w') as f:
    json.dump(cp, f, indent=2, ensure_ascii=False)
print(f'   📁 归档: {archive_name}')
"

  # 最终渲染一次 Markdown（标记为完成）
  generate_plan_md

  # 归档 Markdown
  if [ -f "$PLAN_FILE" ]; then
    local ts_safe
    ts_safe=$(echo "$ts" | tr -d ':')
    local chain_name
    chain_name=$(python3 -c "import json; print(json.load(open('$CHECKPOINT_FILE'))['active_chain'])" 2>/dev/null || echo 'chain')
    local md_archive="doc/logs/chains/${chain_name}_${ts_safe}.md"
    /bin/cp "$PLAN_FILE" "$md_archive" 2>/dev/null || true
    echo "   📋 Markdown 归档: $md_archive"
  fi

  # 清除活跃 checkpoint 和执行计划
  rm -f "$CHECKPOINT_FILE"
  rm -f "$PLAN_FILE"
  echo "✅ 活跃 checkpoint 和执行计划已清除"
}

cmd_read_status() {
  if [ ! -f "$CHECKPOINT_FILE" ]; then
    echo "📭 无活跃执行链（没有 checkpoint.json）"
    return 0
  fi

  python3 -c "
import json

with open('$CHECKPOINT_FILE') as f:
    cp = json.load(f)

done    = [s for s in cp['steps'] if s['status'] == 'done']
running = [s for s in cp['steps'] if s['status'] == 'running']
pending = [s for s in cp['steps'] if s['status'] == 'pending']
failed  = [s for s in cp['steps'] if s['status'] == 'failed']
skipped = [s for s in cp['steps'] if s['status'] == 'skipped']

print('━' * 40)
print(f'🔄 执行链: {cp[\"active_chain\"]}')
print(f'📋 宏状态: {cp[\"macro_state\"]}')
print(f'📝 描述: {cp.get(\"chain_description\", \"\")}')
print(f'⏱ 开始: {cp[\"chain_started_at\"]}')
print(f'⏱ 更新: {cp[\"last_updated\"]}')
print()

total = len(cp['steps'])
print(f'📊 进度: {len(done)}/{total} 完成')
print()

for step in cp['steps']:
    icon = {'done':'✅','running':'🔄','pending':'⏳','failed':'❌','skipped':'⏭'}
    s = icon.get(step['status'], '❓')
    line = f'  {s} {step[\"id\"]}. {step[\"name\"]} ({step[\"agent\"]})'
    if step['status'] == 'failed' and step.get('error'):
        line += f' — {step[\"error\"]}'
    if step['status'] == 'done' and step.get('result'):
        line += f' → {step[\"result\"]}'
    print(line)

print()

if running:
    print(f'🔴 中断于: Step {running[0][\"id\"]} — {running[0][\"name\"]}')
elif pending:
    print(f'⏭ 下一步: Step {pending[0][\"id\"]} — {pending[0][\"name\"]}')
elif not pending and not running:
    print('🎉 所有步骤已完成')

print('━' * 40)
"
}

# ─── 主入口 ─────────────────────────────────────────────────

CMD="${1:?用法: checkpoint.sh <begin_chain|step_start|step_done|step_fail|step_skip|finish_chain|read_status> [args...]}"
shift

case "$CMD" in
  begin_chain)  cmd_begin_chain "$@" ;;
  step_start)   cmd_step_start "$@" ;;
  step_done)    cmd_step_done "$@" ;;
  step_fail)    cmd_step_fail "$@" ;;
  step_skip)    cmd_step_skip "$@" ;;
  finish_chain) cmd_finish_chain "$@" ;;
  read_status)  cmd_read_status "$@" ;;
  *)
    echo "❌ 未知命令: $CMD" >&2
    echo "可用命令: begin_chain, step_start, step_done, step_fail, step_skip, finish_chain, read_status" >&2
    exit 1
    ;;
esac
