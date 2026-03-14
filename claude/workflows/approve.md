---
description: Approve PRD or implementation plan and trigger auto-chain
---

# /approve — 审批并触发 Auto-Chain

处理用户的审批信号，根据当前状态触发相应的自动执行链。

## Steps

1. **读取当前状态**

```bash
STATE=$(python3 -c "import json; print(json.load(open('doc/state.json'))['state'])")
```

2. **根据状态执行对应链路**

### 如果 state == `PRD_DRAFT`（用户审批 PRD）

**初始化 Checkpoint**:
```bash
bash ~/.claude/checkpoint.sh begin_chain "approve_prd" ~/.claude/orchestrator/chains/approve-prd.json
```

**执行 Auto-Chain（每步带 checkpoint）**:

```bash
# Step 1: 更新状态 → PRD_REVIEW
bash ~/.claude/checkpoint.sh step_start 1
bash ~/.claude/logger.sh prd_approved "用户批准 PRD"
bash ~/.claude/logger.sh state_change "PRD_DRAFT → PRD_REVIEW" "orchestrator"
# [更新 state.json → PRD_REVIEW]
bash ~/.claude/checkpoint.sh step_done 1

# Step 2: BE 审查 PRD
bash ~/.claude/checkpoint.sh step_start 2
bash ~/.claude/logger.sh agent_start "BE 开始 PRD 技术审查（阶段1）" "be"
codex exec --full-auto "$(cat ~/.claude/agents/be.md | head -50)
请审查以下 PRD:
$(cat doc/prd.md)
输出 JSON: {success, agent:'BE', action:'/review-prd', approved:bool, issues:[]}"
# [解析结果]
bash ~/.claude/logger.sh agent_done "BE 审查完成：VERDICT={result}" "be"
# 如果 rejected → step_fail + 回退 PRD_DRAFT + 停链
bash ~/.claude/checkpoint.sh step_done 2 '{"approved": true}'

# Step 3: 更新状态 → BE_APPROVED
bash ~/.claude/checkpoint.sh step_start 3
# [更新 state.json → BE_APPROVED]
bash ~/.claude/logger.sh state_change "PRD_REVIEW → BE_APPROVED" "orchestrator"
bash ~/.claude/checkpoint.sh step_done 3

# Step 4: FE 审查 PRD
bash ~/.claude/checkpoint.sh step_start 4
bash ~/.claude/logger.sh agent_start "FE 开始 PRD 技术审查（阶段2）" "fe"
# [Gemini FE 审查]
bash ~/.claude/logger.sh agent_done "FE 审查完成：VERDICT={result}" "fe"
# 如果 rejected → step_fail + 回退 PRD_DRAFT + 停链
bash ~/.claude/checkpoint.sh step_done 4 '{"approved": true}'

# Step 5: 更新状态 → PRD_APPROVED
bash ~/.claude/checkpoint.sh step_start 5
# [更新 state.json → PRD_APPROVED]
bash ~/.claude/logger.sh state_change "BE_APPROVED → PRD_APPROVED" "orchestrator"
bash ~/.claude/checkpoint.sh step_done 5

# Step 6: Designer 生成 Figma 提示词
bash ~/.claude/checkpoint.sh step_start 6
bash ~/.claude/logger.sh agent_start "Designer 开始生成 Figma 提示词" "designer"
# [Designer 执行]
bash ~/.claude/logger.sh agent_done "Figma 提示词生成完成" "designer"
bash ~/.claude/checkpoint.sh step_done 6

# Step 7: 更新状态 → FIGMA_PROMPT
bash ~/.claude/checkpoint.sh step_start 7
# [更新 state.json → FIGMA_PROMPT]
bash ~/.claude/logger.sh state_change "PRD_APPROVED → FIGMA_PROMPT" "orchestrator"
bash ~/.claude/logger.sh checkpoint "等待用户完成 Figma 设计" "orchestrator"
bash ~/.claude/checkpoint.sh step_done 7

# 完成链路
bash ~/.claude/checkpoint.sh finish_chain
```

### 如果 state == `TESTS_WRITTEN`（用户审批实现计划）

**初始化 Checkpoint**:
```bash
bash ~/.claude/checkpoint.sh begin_chain "plan_approved" ~/.claude/orchestrator/chains/plan-approved.json
```

**执行 Auto-Chain（每步带 checkpoint）**:

```bash
# Step 1: 更新状态 → IMPLEMENTATION
bash ~/.claude/checkpoint.sh step_start 1
bash ~/.claude/logger.sh implementation_start "FE+BE 并行启动实现阶段"
bash ~/.claude/logger.sh state_change "TESTS_WRITTEN → IMPLEMENTATION" "orchestrator"
# [更新 state.json → IMPLEMENTATION]
bash ~/.claude/checkpoint.sh step_done 1

# Step 2-3: 并行启动 FE + BE
bash ~/.claude/checkpoint.sh step_start 2
bash ~/.claude/checkpoint.sh step_start 3
bash ~/.claude/logger.sh agent_start "Gemini FE 开始前端实现" "fe"
bash ~/.claude/logger.sh agent_start "Codex BE 开始后端实现" "be"
# [并行执行 Gemini + Codex]
bash ~/.claude/logger.sh agent_done "FE 实现完成" "fe"
bash ~/.claude/checkpoint.sh step_done 2
bash ~/.claude/logger.sh agent_done "BE 实现完成" "be"
bash ~/.claude/checkpoint.sh step_done 3

# Step 4: 同步屏障
bash ~/.claude/checkpoint.sh step_start 4
# [确认 FE+BE 均完成]
bash ~/.claude/checkpoint.sh step_done 4

# Step 5: 更新状态 → QA_TESTING
bash ~/.claude/checkpoint.sh step_start 5
bash ~/.claude/logger.sh state_change "IMPLEMENTATION → QA_TESTING" "orchestrator"
bash ~/.claude/checkpoint.sh step_done 5

# Step 6: QA 测试
bash ~/.claude/checkpoint.sh step_start 6
bash ~/.claude/logger.sh agent_start "QA 开始执行测试" "qa"
# [Codex QA 执行]
bash ~/.claude/logger.sh agent_done "QA 测试完成" "qa"
bash ~/.claude/checkpoint.sh step_done 6

# Step 7: 结果判定
bash ~/.claude/checkpoint.sh step_start 7
# [QA_PASSED → DONE / QA_FAILED → 修复循环]
bash ~/.claude/checkpoint.sh step_done 7

# 完成链路
bash ~/.claude/checkpoint.sh finish_chain
```

3. **失败处理**

任何步骤失败时：
```bash
bash ~/.claude/checkpoint.sh step_fail {step_id} "{error_message}"
bash ~/.claude/logger.sh chain_break "链中断 @ Step {step_id}：{error}" "orchestrator"
```

```
⛔ Auto-Chain 在 Step {step_id} 中断
Agent: {agent}
错误: {error_message}
当前状态: {state}

🔄 已保存 Checkpoint，可通过 /resume 恢复
查看断点状态: bash ~/.claude/checkpoint.sh read_status
查看日志: cat doc/logs/summary.md

可选操作:
  1. 输入 /resume 从断点继续
  2. 输入 "retry" 重试当前节点
  3. 输入 "skip" 跳过并继续（谨慎）
  4. 输入 "/update-prd" 回到草稿重新规划
```
