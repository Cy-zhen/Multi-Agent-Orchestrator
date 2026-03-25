---
name: run-chain
description: 自动链执行引擎 — 循环执行 AUTO 节点直到遇到非 AUTO 节点或执行失败
---

# /run-chain

> 多步自动推进引擎。当 `/determine-next-action` 返回 `AUTO` 时，持续执行直到遇到 Gate 节点或失败。

## 执行前置条件

- `doc/state.json` 存在且可读
- `~/.claude/logger.sh` 可执行
- `~/.claude/checkpoint.sh` 可执行

## 执行流程

```
┌──────────────────────────────────┐
│ 1. begin_chain (checkpoint.sh)   │
└─────────────┬────────────────────┘
              │
              ▼
┌──────────────────────────────────┐
│ 2. /determine-next-action        │◄─────────────┐
└─────────────┬────────────────────┘              │
              │                                    │
              ▼                                    │
        ┌─────────────┐                           │
        │ node_type?  │                           │
        └──┬──┬──┬──┬─┘                           │
   AUTO   │  │  │  │  DONE                        │
   ┌──────┘  │  │  └──────┐                       │
   │   USER  │  │  PLAN   │                       │
   │   GATE  │  │  GATE   │                       │
   │    │    │  │   │     │                        │
   ▼    ▼    ▼  ▼   ▼     ▼                        │
┌──────────────────────────────────┐              │
│ AUTO:                            │              │
│  a. check_preconditions()        │              │
│  b. step_start (checkpoint.sh)   │              │
│  c. dispatch_agent()             │              │
│  d. 解析结果                      │              │
│     ├─ 成功 → update_state()     │──────────────┘
│     │         step_done()        │  (回到步骤 2)
│     │         generate_slice()   │
│     └─ 失败 → step_fail()       │
│                停止链             │
├──────────────────────────────────┤
│ USER_GATE / PLAN_GATE:           │
│  输出等待提示 → 停止             │
├──────────────────────────────────┤
│ INTERACTIVE:                     │
│  输出交互提示 → 停止             │
├──────────────────────────────────┤
│ DONE:                            │
│  finish_chain → 完成报告         │
└──────────────────────────────────┘
```

## 链输出格式

多步自动推进时，按以下格式逐行输出进度：

```
═══════════════════════════════════════════
  Auto-Chain 开始 | 起始状态: PRD_REVIEW
═══════════════════════════════════════════

1. /review-prd (BE → codex) → BE_APPROVED ✅
2. /review-prd (FE → gemini) → PRD_APPROVED ✅
3. /generate-figma-prompt (Designer → claude) → FIGMA_PROMPT ✅

───────────────────────────────────────────
  链暂停 | 当前状态: FIGMA_PROMPT
  等待用户操作：Figma 设计完成后说 "figma ready {url}"
───────────────────────────────────────────
```

## 失败输出格式

```
═══════════════════════════════════════════
  Auto-Chain 开始 | 起始状态: PRD_REVIEW
═══════════════════════════════════════════

1. /review-prd (BE → codex) → BE_APPROVED ✅
2. /review-prd (FE → gemini) → ❌ 被拒绝

───────────────────────────────────────────
  链停止 | 当前状态: PRD_DRAFT (已回退)
  原因: FE 审查不通过
  Issues:
    - [critical] App Router 路由结构未定义
    - [warning] 响应式断点缺少 Tablet
  等待用户操作：根据审查意见修改 PRD
───────────────────────────────────────────
```

## 并行执行格式

```
3. /figma-to-code build (FE+BE 并行)
   ├─ FE (gemini): 前端编码... ⏳
   ├─ BE (codex): 后端编码... ⏳
   ├─ FE 完成 ✅
   └─ BE 完成 ✅
   → QA_TESTING ✅
```

## 失败处理规则

1. **Agent 执行失败** (success: false)
   - 链立即停止
   - 输出失败原因和当前状态
   - checkpoint 标记 `step_fail`
   - 等待用户干预

2. **Gate 拒绝** (approved: false)
   - 链立即停止
   - 状态回退到 `PRD_DRAFT`
   - 输出拒绝原因 (issues)
   - 等待用户修改

3. **前置条件不满足**
   - 链立即停止
   - 输出缺失的前置条件
   - 不改变状态

4. **CLI 超时**
   - 链停止
   - 记录超时时间和 Agent
   - 建议用户 `/resume` 重试

5. **反思循环超限** (reflection_count >= 3)
   - 链停止
   - 输出: "反思修复已达上限(3次)，需要人工介入"

## Checkpoint 集成

| 时机 | 调用 |
|------|------|
| 链开始 | `bash ~/.claude/checkpoint.sh begin_chain "{chain_name}" "{project_dir}"` |
| 步骤开始 | `bash ~/.claude/checkpoint.sh step_start {N} "{step_name}" "{project_dir}"` |
| 步骤完成 | `bash ~/.claude/checkpoint.sh step_done {N} "{project_dir}"` |
| 步骤失败 | `bash ~/.claude/checkpoint.sh step_fail {N} "{error}" "{project_dir}"` |
| 链结束 | `bash ~/.claude/checkpoint.sh finish_chain "{project_dir}"` |

## 日志集成

| 时机 | 调用 |
|------|------|
| 步骤开始 | `bash ~/.claude/logger.sh STEP_START "{agent}:{skill}" "{agent}" "{session}"` |
| 步骤完成 | `bash ~/.claude/logger.sh STEP_DONE "{summary}" "{agent}" "{session}"` |
| 步骤失败 | `bash ~/.claude/logger.sh ERROR "{error}" "{agent}" "{session}"` |
| 状态变更 | `bash ~/.claude/logger.sh STATE_CHANGE "{old} → {new}" "orchestrator" "{session}"` |

## 切片文档生成

每次状态变更时自动生成 `doc/slice-{STATE}.md`:

```markdown
# 切片: {STATE} — {PROJECT_NAME}
**时间**: {timestamp}
**前序状态**: {previous_state}
**Agent**: {agent}
**操作**: {skill}

## 输出摘要
{agent output summary}

## 产出文件
- {file1} (新增/修改)
- {file2}

## 下一步
{next state 描述}
```
