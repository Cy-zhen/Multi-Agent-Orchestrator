---
name: resume
description: Resume an interrupted Auto-Chain from checkpoint
---

# /resume — 从断点恢复中断的执行链

当会话因断网、上下文溢出或 API 限制中断后，用此工作流恢复。

## Steps

1. **检查 checkpoint 是否存在**

```bash
if [ ! -f "doc/checkpoint.json" ]; then
  echo "📭 无活跃执行链 — 无需恢复"
  echo "当前状态:"
  cat doc/state.json 2>/dev/null || echo "未初始化"
  exit 0
fi
```

2. **读取断点状态**

```bash
bash ~/.claude/checkpoint.sh read_status
```

> 💡 也可直接查看人可读的执行计划: `cat doc/execution-plan.md`

3. **找到断点位置**

解析 `doc/checkpoint.json`，识别：
- 第一个 `status == "running"` 的 step → **中断点**（需重新执行）
- 如果没有 running，第一个 `status == "pending"` → **下一步**
- 如果全部 done/skipped → 链已完成，执行 `finish_chain`

```bash
python3 -c "
import json
with open('doc/checkpoint.json') as f:
    cp = json.load(f)

running = [s for s in cp['steps'] if s['status'] == 'running']
pending = [s for s in cp['steps'] if s['status'] == 'pending']
done    = [s for s in cp['steps'] if s['status'] == 'done']

if running:
    print(f'RESUME_FROM={running[0][\"id\"]}')
    print(f'RESUME_TYPE=retry')
    print(f'RESUME_STEP={running[0][\"name\"]}')
elif pending:
    print(f'RESUME_FROM={pending[0][\"id\"]}')
    print(f'RESUME_TYPE=continue')
    print(f'RESUME_STEP={pending[0][\"name\"]}')
else:
    print('RESUME_FROM=0')
    print('RESUME_TYPE=completed')
"
```

4. **向用户展示恢复选项**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 发现未完成的执行链: {chain_name}
📋 宏状态: {macro_state}
✅ 已完成: {done_count}/{total} 步

[逐步列出已完成和未完成的步骤]

🔴 中断于: Step {id} — {name}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
请选择操作:
  1️⃣ 从断点继续（重新执行 Step {id}）
  2️⃣ 跳过当前步骤，继续后续
  3️⃣ 放弃此链，保持当前状态
```

5. **根据用户选择执行**

### 选择 1: 从断点继续

从中断的 step 开始，按顺序执行剩余 steps。每步都调用 checkpoint：

```bash
# 对于每个待执行的 step:
bash ~/.claude/checkpoint.sh step_start {step_id}
# [执行实际操作]
bash ~/.claude/checkpoint.sh step_done {step_id} "{result}"
# 失败时:
bash ~/.claude/checkpoint.sh step_fail {step_id} "{error}"
```

### 选择 2: 跳过当前步骤

```bash
bash ~/.claude/checkpoint.sh step_skip {step_id}
# 继续执行下一步
```

### 选择 3: 放弃

```bash
bash ~/.claude/checkpoint.sh finish_chain
bash ~/.claude/logger.sh chain_break "用户放弃执行链 {chain_name}" "orchestrator"
```

6. **链路完成后清理**

```bash
bash ~/.claude/checkpoint.sh finish_chain
bash ~/.claude/logger.sh state_change "执行链 {chain_name} 完成，当前状态: {state}" "orchestrator"
```

## 自动检测规则

> **CLAUDE.md 全局约束**: 每次新会话启动时，如果 `doc/checkpoint.json` 存在且有 `running` 或 `pending` 步骤，Orchestrator 应**自动提示**用户是否要恢复，而不是等用户手动输入 `/resume`。

检测逻辑：
```bash
if [ -f "doc/checkpoint.json" ]; then
  HAS_UNFINISHED=$(python3 -c "
import json
with open('doc/checkpoint.json') as f:
    cp = json.load(f)
unfinished = [s for s in cp['steps'] if s['status'] in ('running','pending')]
print('yes' if unfinished else 'no')
  ")
  if [ "$HAS_UNFINISHED" = "yes" ]; then
    echo "⚠ 检测到未完成的执行链，建议执行 /resume"
    echo "📋 执行计划: cat doc/execution-plan.md"
    bash ~/.claude/checkpoint.sh read_status
  fi
fi
```
