---
name: determine-next-action
description: 状态判定引擎 — 读取当前状态，查询转换表，输出下一步操作、执行者和节点类型
---

# /determine-next-action

> Orchestrator 核心决策技能。每次状态转换或用户输入后首先调用此技能。

## 执行前置条件

- `doc/state.json` 存在且可读
- 文件中包含 `state` 字段

## 算法

1. 读取 `doc/state.json` → `current_state`
2. 查询下方 **状态转换表** → 获取 `node_type`, `agent`, `cli`, `skill`, `next_state`
3. 根据 `node_type` 决定行为

---

## 状态转换表

| 状态 | node_type | agent | cli | skill | next_on_success | next_on_fail | 描述 |
|------|-----------|-------|-----|-------|-----------------|--------------|------|
| `IDEA` | `INTERACTIVE` | — | — | — | — | — | 需要用户描述产品概念 |
| `PRD_DRAFT` | `USER_GATE` | — | — | — | — | — | 用户审阅 PRD，说"approved"继续 |
| `PRD_REVIEW` | `AUTO` | be | codex | `/review-prd` | `BE_APPROVED` | `PRD_DRAFT` | BE 审查 PRD |
| `BE_APPROVED` | `AUTO` | fe | gemini | `/review-prd` | `PRD_APPROVED` | `PRD_DRAFT` | FE 审查 PRD |
| `PRD_APPROVED` | `AUTO` | designer | claude | `/generate-figma-prompt` | `FIGMA_PROMPT` | — | 生成 Figma 提示词 |
| `FIGMA_PROMPT` | `USER_GATE` | — | — | — | — | — | 等待用户完成 Figma 设计 |
| `DESIGN_READY` | `AUTO` | qa | codex | `/prepare-tests` | `TESTS_WRITTEN` | — | 生成测试计划 |
| `TESTS_WRITTEN` | `PLAN_GATE` | — | — | — | — | — | 用户审阅测试+实现计划 |
| `IMPLEMENTATION` | `AUTO` | fe+be | gemini+codex | `/figma-to-code build` | `QA_TESTING` | — | FE+BE 并行编码 |
| `QA_TESTING` | `AUTO` | qa | codex | `/run-tests` | `QA_PASSED` | `QA_FAILED` | 执行自动化测试 |
| `QA_PASSED` | `AUTO` | — | — | — | `DONE` | — | 自动转换到完成 |
| `QA_FAILED` | `AUTO` | general | claude | `/add-reflection` | `IMPLEMENTATION` | — | 分析失败生成反思 (≤3次) |
| `DONE` | — | — | — | — | — | — | 终止状态 |

---

## 节点类型行为

### AUTO — 自动执行

```
输出: "自动执行：{skill_name}..."
行为: 派发对应 Agent/CLI 执行该技能
完成后: 回到步骤 1 重新判断下一步
重复: 直到遇到非 AUTO 节点或链执行完毕
```

返回:
```json
{
  "current_state": "PRD_REVIEW",
  "node_type": "AUTO",
  "action": "execute",
  "agent": "be",
  "cli": "codex",
  "skill": "/review-prd",
  "next_state_on_success": "BE_APPROVED",
  "next_state_on_failure": "PRD_DRAFT",
  "prompt_template": "be-review-prd.txt",
  "preconditions": ["doc/prd.md exists", "state == PRD_REVIEW"]
}
```

### USER_GATE — 等待用户操作

```
输出: "等待用户操作：{描述}"
行为: 停止，等待用户信号
```

示例:
- `PRD_DRAFT` → "等待用户操作：审阅 PRD 后说 'approved' 继续"
- `FIGMA_PROMPT` → "等待用户操作：Figma 设计完成后说 'figma ready {url}'"

返回:
```json
{
  "current_state": "PRD_DRAFT",
  "node_type": "USER_GATE",
  "action": "wait",
  "gate": "user",
  "hint": "审阅 doc/prd.md 后说 'approved' 继续",
  "expected_signals": ["approved", "通过", "批准"]
}
```

### PLAN_GATE — 等待方案审批

```
输出: "等待方案审批：{描述}"
行为: 停止，等待用户确认计划
```

示例:
- `TESTS_WRITTEN` → "等待方案审批：审阅测试计划和实现计划后说 'plan approved'"

返回:
```json
{
  "current_state": "TESTS_WRITTEN",
  "node_type": "PLAN_GATE",
  "action": "wait",
  "gate": "plan",
  "hint": "审阅 doc/test-plan.md 和 doc/fe-plan.md / doc/be-plan.md 后说 'plan approved'",
  "expected_signals": ["plan approved", "计划通过"]
}
```

### INTERACTIVE — 需要交互

```
输出: "需要交互：{描述}"
行为: 停止，等待用户对话输入
```

示例:
- `IDEA` → "需要交互：请描述你的产品概念"

返回:
```json
{
  "current_state": "IDEA",
  "node_type": "INTERACTIVE",
  "action": "wait",
  "gate": "interactive",
  "hint": "请描述你的产品概念，PM 将自动生成 PRD"
}
```

---

## 特殊逻辑

### 并行执行 (IMPLEMENTATION)

当 `current_state == IMPLEMENTATION`:
- 同时派发 FE(gemini) 和 BE(codex)
- 使用 `sync_barrier` 等待两者均完成
- 两者都成功 → `QA_TESTING`
- 任一失败 → 停止链，报告错误

### 反思循环限制 (QA_FAILED)

当 `current_state == QA_FAILED`:
- 检查 `state.json` 中的 `reflection_count`
- 如果 `reflection_count >= 3` → 停止自动重试
  - 输出: "反思修复已达上限(3次)，需要人工介入"
  - 节点类型变为 `USER_GATE`
- 如果 `reflection_count < 3` → 正常 AUTO 执行

### Gate 拒绝 (PRD_REVIEW / BE_APPROVED)

当 BE 或 FE review 返回 `approved: false`:
- 链立即停止
- 状态回退到 `PRD_DRAFT`
- 输出拒绝原因 (issues 数组)
- 变为 `USER_GATE`: "等待用户操作：根据审查意见修改 PRD"
