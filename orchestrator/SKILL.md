# Multi-Agent Orchestrator

> Claude CLI 主导的多 Agent 开发工作流编排器。管理 PM/Designer/FE/BE/QA/General 六个专业 Agent 的协调调度，驱动从 IDEA 到 DONE 的完整产品开发链路。
> 全局配置位于 `~/.claude/`，所有项目共享。运行时状态和日志位于项目级 `doc/` 目录。
>
> ### Orchestrator 子技能（决策引擎）
> - [/determine-next-action](file:///Users/cy-zhen/.claude/orchestrator/skills/determine-next-action.md) — 状态判定：查表决定下一步操作和节点类型
> - [/run-chain](file:///Users/cy-zhen/.claude/orchestrator/skills/run-chain.md) — 自动链执行：循环 AUTO 节点直到遇到 Gate
> - [/dispatch-agent](file:///Users/cy-zhen/.claude/orchestrator/skills/dispatch-agent.md) — CLI 派发：构造命令、执行、解析输出
>
> ### CLI 工具
> - [orchestrator.sh](file:///Users/cy-zhen/.claude/orchestrator.sh) — 编排器 CLI（status / next / transition / dispatch / parallel）
>
> ### Dispatch Prompt Templates
> 位于: `~/.claude/orchestrator/dispatch-templates/*.txt`
> 被 `/dispatch-agent` 加载并做变量替换后传给各 CLI

## 核心职责

1. **状态管理** — 读写 `doc/state.json`，维护当前工作流状态
2. **信号路由** — 解析用户信号，匹配对应的自动链路
3. **Agent 派发** — 根据状态和角色，向正确的 CLI 派发任务
4. **Auto-Chain** — 自动节点完成后推进下一步，失败时停链报告
5. **并行协调** — FE+BE 同时工作时，等待双方完成后统一推进
6. **日志记录** — 每个节点开始/结束/失败都记日志

**绝不用 Claude 写前端代码，绝不用 Gemini 写后端代码。**

---

## Agent 技能清单

| Agent | 技能文档 | CLI | 活跃状态 | 核心技能 |
|---|---|---|---|---|
| **Orchestrator** | `~/.claude/orchestrator/SKILL.md` | Claude | 始终活跃 | 状态管理、派发、链路控制 |
| **PM** (产品经理) | `~/.claude/agents/pm.md` | Claude | IDEA 状态 / 需要 PRD | `/generate-prd`, `/update-prd`, `/import-existing` |
| **Designer** (设计师) | `~/.claude/agents/designer.md` | Claude | PRD_APPROVED 状态 | `/generate-figma-prompt`, `/design-ready` |
| **BE** (后端工程师) | `~/.claude/agents/be.md` | Codex | DESIGN_READY / PRD_REVIEW(阶段1) | `/review-prd`(BE视角), `/figma-to-code`(后端) |
| **FE** (前端工程师) | `~/.claude/agents/fe.md` | Gemini | DESIGN_READY / PRD_REVIEW(阶段2) | `/review-prd`(FE视角), `/figma-to-code`(前端) |
| **QA** (测试工程师) | `~/.claude/agents/qa.md` | Codex | TESTS_WRITTEN / QA_TESTING | `/prepare-tests`, `/run-tests` |
| **General** (全能) | `~/.claude/agents/general.md` | Claude | 跨角色 / 探索性 | 所有技能 |
| **Gstack** (质量关卡) | `.claude/skills/gstack/` | Claude | 多个阶段交叉介入 | `/plan-ceo-review`, `/plan-design-review`, `/review`, `/cso`, `/investigate`, `/design-review`, `/ship`, `/retro`, `/document-release` |

### 共享设计技能：Impeccable

> 来源：[pbakaus/impeccable](https://github.com/pbakaus/impeccable) (Apache 2.0)
> 基于 Anthropic 的 frontend-design skill 扩展，提供更深入的前端设计指导。

**已安装位置（全局共享）：**

| CLI | 路径 | 说明 |
|-----|------|------|
| Claude Code | `~/.claude/skills/frontend-design/` | Designer/Gstack 使用 |
| Gemini CLI | `~/.gemini/skills/frontend-design/` | FE Agent 使用 |
| Codex CLI | `~/.codex/skills/frontend-design/` | BE Agent 参考 |

**包含内容：**
- `SKILL.md` — 核心设计原则 + AI Slop 检测清单
- `reference/typography.md` — 排版规范
- `reference/color-and-contrast.md` — 配色与对比度
- `reference/spatial-design.md` — 空间设计
- `reference/motion-design.md` — 动效设计
- `reference/interaction-design.md` — 交互设计
- `reference/responsive-design.md` — 响应式设计
- `reference/ux-writing.md` — UX 文案
- 20 个命令 skill：`/audit`, `/critique`, `/normalize`, `/polish`, `/distill`, `/clarify`, `/optimize`, `/harden`, `/animate`, `/colorize`, `/bolder`, `/quieter`, `/delight`, `/extract`, `/adapt`, `/onboard`, `/typeset`, `/arrange`, `/overdrive`, `/teach-impeccable`

**Dispatch Template 集成：**

| 模板 | 阶段 | 集成方式 |
|------|------|----------|
| `design-review-plan.txt` | DESIGN_PLAN_REVIEW | 7 维度审查对齐 impeccable（Pass 4 AI Slop 必查） |
| `design-review-visual.txt` | VISUAL_REVIEW | 80 项视觉审查引用 impeccable 基准 |
| `fe-implementation.txt` | IMPLEMENTATION | FE 编码时参考 impeccable 设计指南 |

---

## 状态机（18 个状态，含 5 个 Gstack 质量关卡 🆕）

```
IDEA ──────────────────────────────────────────────────────────────
  └─(PM: /generate-prd 或 /import-existing)──► PRD_DRAFT
                                                     │
                                             ⏸ 用户审阅 PRD
                                                     │
                                          (用户: /approve-prd)
                                                     │
                                         🆕 CEO_REVIEW
                                     (Gstack: /plan-ceo-review)
                                                  │
                                    ┌─────────────┴─────────────┐
                                  通过                         不通过
                                    │                     PRD_DRAFT ⏸
                              PRD_REVIEW
                                  │
                             ┌────┴────────────────────┐
                      (BE: /review-prd 阶段1)     (如BE拒绝)
                             │                    PRD_DRAFT ⏸
                    (FE: /review-prd 阶段2)
                             │
               ┌─────────────┴──────────────┐
            通过                           打回
       🆕 DESIGN_PLAN_REVIEW            PRD_DRAFT ⏸
       (Gstack: /plan-design-review)
               ┌─────────────┴──────────────┐
            通过                           问题
       PRD_APPROVED                     PRD_DRAFT ⏸
            │
  (Designer: /generate-stitch-prompt)
            │
       FIGMA_PROMPT
            │
    ⏸ 用户完成 Stitch 设计 → "design ready {url}"
            │
       DESIGN_READY
            │
     (QA: /prepare-tests)
            │
      TESTS_WRITTEN
            │
    ⏸ 用户审阅测试计划 → "plan approved"
            │
    ┌───────┴───────┐
(FE: /figma-to-code) (BE: /figma-to-code)  ← 并行
    └───────┬───────┘
            │（两者均完成）
      IMPLEMENTATION
            │
    🆕 CODE_REVIEW (Gstack: /review)
            │
    🆕 SECURITY_AUDIT (Gstack: /cso)
            │
  (QA: /run-tests)
            │
       QA_TESTING
       │          │
     通过        失败
       │          │
 🆕 VISUAL_REVIEW  🆕 QA_FAILED
 (Gstack: /design-review) (Gstack: /investigate, 最多3次)
       │                        │
   QA_PASSED               IMPLEMENTATION ──┘
 (Gstack: /ship)
       │
     DONE
       │
  (可选: /retro + /document-release)

ANY_STATE ──(/update-prd)──► PRD_DRAFT ⏸
ANY_STATE ──(/import-existing)──► [PM 判断切入状态]
```

详细转换规则见 [state-machine.md](file:///Users/cy-zhen/.claude/orchestrator/state-machine.md)

---

## 日志规范（每个节点必须执行）

**logger 位于**: `~/.claude/logger.sh`
**调用格式**: `bash ~/.claude/logger.sh <event> "<message>" [agent] [session_id]`

### 事件类型

| 事件 | 何时触发 |
|------|---------|
| `state_change` | 每次状态转换 |
| `checkpoint` | 每次等待用户介入 |
| `agent_start` | 派发任务给子 Agent 时 |
| `agent_done` | 子 Agent 完成时 |
| `agent_error` | 子 Agent 报错时 |
| `chain_break` | Auto-Chain 中断时 |
| `prd_generated` | PM 生成 PRD |
| `prd_approved` | 用户批准 PRD |
| `prd_updated` | PM 更新 PRD |
| `import_done` | 现有项目扫描完成 |
| `figma_ready` | 用户提供 Figma URL |
| `tests_written` | QA 生成测试计划 |
| `implementation_start` | FE+BE 并行开始 |
| `qa_passed` / `qa_failed` | QA 结果 |
| `done` | 流程完成 |
| `error` | 任何错误 |

### 日志调用模板

```bash
# 状态转换
bash ~/.claude/logger.sh state_change "IDEA → PRD_DRAFT" "orchestrator"

# 派发 Agent
bash ~/.claude/logger.sh agent_start "派发 BE 审查 PRD" "be" "$SESSION_ID"

# Agent 完成
bash ~/.claude/logger.sh agent_done "BE PRD 审查完成，VERDICT: APPROVED" "be" "$SESSION_ID"

# 错误
bash ~/.claude/logger.sh chain_break "Gemini FE 超时，session: $SESSION_ID" "orchestrator"

# 检查点
bash ~/.claude/logger.sh checkpoint "等待用户审阅 PRD" "orchestrator"
```

**日志输出位置**（项目级 `doc/logs/`，遵循用户规则）:
- `doc/logs/workflow.jsonl` — 结构化 JSONL，机器可读
- `doc/logs/YYYY-MM-DD.log` — 按天人类可读日志
- `doc/logs/summary.md` — 自动更新的流程追踪报告

---

## 用户信号表（4个介入点 + 扩展命令）

| 用户输入 | 当前状态 | 触发动作 |
|---------|---------|---------|
| 概念描述（自然语言）| IDEA | → PM `/generate-prd` → 停在 `PRD_DRAFT` |
| `"我已有代码，路径 {path}"` | IDEA | → PM `/import-existing` → 停在 PM 判断的切入状态 |
| `"通过"` / `"approved"` / `"ok"` | PRD_DRAFT | → Auto-Chain → 停在 `FIGMA_PROMPT` |
| `"figma ready {url}"` | FIGMA_PROMPT | → Auto-Chain → 停在 `TESTS_WRITTEN` |
| `"plan approved"` | TESTS_WRITTEN | → Auto-Chain → 完成 |
| `"修改: {内容}"` | 任意状态 | → PM `/update-prd` → 返回 `PRD_DRAFT` |
| `"retry"` | 失败状态 | → 重启失败节点 |
| `"skip"` | 失败状态 | → 记日志 + 跳过，继续链 |
| `/status` | 任意 | → 读取 `doc/state.json` + `doc/logs/summary.md` |

---

## Agent/CLI 路由

| Agent | CLI | Prompt 模板 | 调用格式 |
|-------|-----|------------|--------|
| PM | Claude | `pm-generate-prd.txt` | `claude -p "$(cat template)" --output-format json` |
| Designer | Claude | `designer-figma-prompt.txt` | `claude -p "$(cat template)" --output-format json` |
| FE | Gemini | `fe-review-prd.txt` / `fe-implementation.txt` | `gemini -p "$(cat template)" --yolo -o json` |
| BE | Codex | `be-review-prd.txt` / `be-implementation.txt` | `codex exec --full-auto "$(cat template)"` |
| QA | Codex | `qa-prepare-tests.txt` / `qa-run-tests.txt` | `codex exec --full-auto "$(cat template)"` |
| General | Claude | `general-add-reflection.txt` | `claude -p "$(cat template)" --output-format json` |
| Gstack:CEO | Claude | `ceo-review-prd.txt` | `claude -p "$(cat template)" --output-format json` |
| Gstack:Design | Claude | `design-review-plan.txt` | `claude -p "$(cat template)" --output-format json` |
| Gstack:Review | Claude | `staff-review-code.txt` | `claude -p "$(cat template)" --output-format json` |
| Gstack:CSO | Claude | `cso-audit.txt` | `claude -p "$(cat template)" --output-format json` |
| Gstack:Visual | Claude | `design-review-visual.txt` | `claude -p "$(cat template)" --output-format json` |
| Gstack:Debug | Claude | `investigate-failure.txt` | `claude -p "$(cat template)" --output-format json` |
| Gstack:Ship | Claude | `ship-release.txt` | `claude -p "$(cat template)" --output-format json` |
| Gstack:Retro | Claude | `retro-report.txt` | `claude -p "$(cat template)" --output-format json` |
| Gstack:Docs | Claude | `document-release.txt` | `claude -p "$(cat template)" --output-format json` |

> 详细 CLI 构造规则和变量替换见 [dispatch-agent.md](file:///Users/cy-zhen/.claude/orchestrator/skills/dispatch-agent.md)
> Prompt 模板位于: `~/.claude/orchestrator/dispatch-templates/`
> Gstack Skills 源码位于: `.claude/skills/gstack/`

---

## State 持久化

状态文件: `doc/state.json`（项目级，每个项目独立）

```json
{
  "project": "项目名",
  "state": "IDEA",
  "prd_path": "doc/prd.md",
  "figma_url": null,
  "tests_path": "doc/tests/",
  "reflection_count": 0,
  "entry_point": "IDEA",
  "sessions": { "fe": null, "be": null, "qa": null },
  "chain_log": []
}
```

**状态读写片段**:
```bash
# 读取状态
STATE=$(python3 -c "import json; print(json.load(open('doc/state.json'))['state'])")

# 写入新状态（带日志）
NEW_STATE="PRD_DRAFT"
OLD_STATE=$STATE
python3 -c "
import json
with open('doc/state.json','r') as f: s=json.load(f)
s['state']='$NEW_STATE'
s['chain_log'].append({'from':'$OLD_STATE','to':'$NEW_STATE','ts':'$(date -u +%Y-%m-%dT%H:%M:%SZ)'})
with open('doc/state.json','w') as f: json.dump(s,f,indent=2,ensure_ascii=False)
"
bash ~/.claude/logger.sh state_change "$OLD_STATE → $NEW_STATE" "orchestrator"
```

---

## Auto-Chain 执行规则

1. **Auto 节点**完成后立即触发下一步
2. **⏸ 检查点**必须停下来等用户，输出状态卡片
3. **任何节点失败** → 记日志 → 链停止 → 输出失败摘要 → 等待用户干预
4. **FE + BE 在 IMPLEMENTATION 阶段并行启动**
5. **并行任务必须全部完成**才能推进到下一状态

### 失败处理

```bash
# 检测到失败时
bash ~/.claude/logger.sh chain_break "链中断 @ {节点}：{错误摘要}" "orchestrator"

# 输出给用户
echo "
⛔ 链中断 @ {节点}
状态: {CURRENT_STATE}
原因: {错误摘要}
Session: {sessionId}

查看详细日志: cat doc/logs/workflow.jsonl | python3 -m json.tool | tail -20
查看追踪报告: cat doc/logs/summary.md

可选操作:
  1. 修复后输入 \"retry\" 重试当前节点
  2. 输入 \"skip\" 跳过并继续（谨慎）
  3. 输入 \"/update-prd\" 回到草稿重新规划
"
```

### QA 反思循环（最多3次）

```bash
REFLECTION_COUNT=$(python3 -c "import json; print(json.load(open('doc/state.json'))['reflection_count'])")
if [ "$REFLECTION_COUNT" -ge 3 ]; then
  bash ~/.claude/logger.sh error "QA 失败超过3次，停止自动重试" "orchestrator"
  echo "⛔ QA 失败已达3次上限，需要人工决策"
  # 等待用户，不再自动重试
fi
```

### 并行节点协议（FE+BE figma-to-code）

```
1. 同时派发:
   - Codex: BE 后端实现任务
   - Gemini: FE 前端实现任务
2. 轮询等待:
   - 每 30s 检查两个进程状态
   - 任一失败 → 链停止，报告失败方
   - 两者完成 → 合并输出，推进到 IMPLEMENTATION
3. 状态记录:
   state.json.sessions = {
     "be": { "status": "running|done|failed", "command_id": "..." },
     "fe": { "status": "running|done|failed", "command_id": "..." }
   }
```

### Gate 节点协议（review-prd）

```
BE 审查 (阶段1):
  - Codex 执行 PRD 审查
  - 输出包含 {approved: bool, issues: []}
  - approved=true → 进入 FE 审查(阶段2)
  - approved=false → 状态回退到 PRD_DRAFT，附带 issues 列表

FE 审查 (阶段2):
  - Gemini 执行 PRD 审查
  - 逻辑同上
  - approved=true → PRD_APPROVED
  - approved=false → 状态回退到 PRD_DRAFT
```

---

## 每个节点的完整执行规范

### IDEA → PRD_DRAFT（新项目）

```bash
bash ~/.claude/logger.sh agent_start "PM 开始生成 PRD" "pm"
# [PM 执行 /generate-prd，写入 doc/prd.md]
bash ~/.claude/logger.sh prd_generated "PRD V1.0 生成完成"
bash ~/.claude/logger.sh state_change "IDEA → PRD_DRAFT" "orchestrator"
bash ~/.claude/logger.sh checkpoint "等待用户审阅 PRD" "orchestrator"
# [输出状态卡片，停止等待]
```

### IDEA → [切入状态]（现有项目 /import-existing）

```bash
bash ~/.claude/logger.sh agent_start "PM 开始扫描现有代码" "pm"
# Step 1: Codex 扫描
SESSION_ID=$(codex exec --full-auto '扫描代码...')
bash ~/.claude/logger.sh agent_start "Codex 扫描代码结构" "be" "$SESSION_ID"
# [等待完成]
bash ~/.claude/logger.sh agent_done "代码扫描完成，写入 doc/code-scan.md" "be" "$SESSION_ID"
# Step 2: PM 生成反向 PRD
bash ~/.claude/logger.sh prd_generated "反向 PRD 从代码生成完成"
bash ~/.claude/logger.sh import_done "切入状态: {STATE}" "pm"
bash ~/.claude/logger.sh state_change "IDEA → {STATE}" "orchestrator"
bash ~/.claude/logger.sh checkpoint "等待用户确认切入方案" "orchestrator"
```

### PRD_DRAFT → PRD_REVIEW（用户批准后 Auto-Chain）

```bash
bash ~/.claude/logger.sh prd_approved "用户批准 PRD V{n}"
bash ~/.claude/logger.sh state_change "PRD_DRAFT → PRD_REVIEW" "orchestrator"

# BE 审查（阶段1）
bash ~/.claude/logger.sh agent_start "BE 开始 PRD 技术审查（阶段1）" "be"
# [BE /review-prd 执行]
bash ~/.claude/logger.sh agent_done "BE 审查完成：VERDICT=APPROVED" "be"

# FE 审查（阶段2，在 BE 通过后）
bash ~/.claude/logger.sh agent_start "FE 开始 PRD 技术审查（阶段2）" "fe"
# [FE /review-prd 执行]
bash ~/.claude/logger.sh agent_done "FE 审查完成：VERDICT=APPROVED" "fe"

# 根据结果
bash ~/.claude/logger.sh state_change "PRD_REVIEW → PRD_APPROVED" "orchestrator"
```

### PRD_APPROVED → FIGMA_PROMPT

```bash
bash ~/.claude/logger.sh agent_start "Designer 开始生成 Figma 提示词" "designer"
# [Designer /generate-figma-prompt 执行]
bash ~/.claude/logger.sh agent_done "Figma 提示词生成完成：doc/figma-prompt.md" "designer"
bash ~/.claude/logger.sh state_change "PRD_APPROVED → FIGMA_PROMPT" "orchestrator"
bash ~/.claude/logger.sh checkpoint "等待用户完成 Figma 设计" "orchestrator"
```

### FIGMA_PROMPT → TESTS_WRITTEN（用户提供 Figma URL 后）

```bash
bash ~/.claude/logger.sh figma_ready "用户提供 Figma URL: $FIGMA_URL"
# 写入 state.json figma_url
bash ~/.claude/logger.sh state_change "FIGMA_PROMPT → DESIGN_READY" "orchestrator"

bash ~/.claude/logger.sh agent_start "QA 开始生成测试计划" "qa"
# [QA /prepare-tests 执行]
bash ~/.claude/logger.sh tests_written "测试计划生成完成，{n} 个测试用例" "qa"
bash ~/.claude/logger.sh state_change "DESIGN_READY → TESTS_WRITTEN" "orchestrator"
bash ~/.claude/logger.sh checkpoint "等待用户审阅测试计划" "orchestrator"
```

### TESTS_WRITTEN → IMPLEMENTATION（用户 "plan approved" 后，并行）

```bash
bash ~/.claude/logger.sh implementation_start "FE+BE 并行启动实现阶段"
bash ~/.claude/logger.sh state_change "TESTS_WRITTEN → IMPLEMENTATION" "orchestrator"

# 并行启动
FE_SESSION=$(gemini --yolo -p '{FE任务}')
BE_SESSION=$(codex exec --full-auto '{BE任务}')

bash ~/.claude/logger.sh agent_start "Gemini FE 开始前端实现" "fe" "$FE_SESSION"
bash ~/.claude/logger.sh agent_start "Codex BE 开始后端实现" "be" "$BE_SESSION"

# 监控两个 session，全部完成后继续
bash ~/.claude/logger.sh agent_done "FE 实现完成" "fe" "$FE_SESSION"
bash ~/.claude/logger.sh agent_done "BE 实现完成" "be" "$BE_SESSION"
```

### IMPLEMENTATION → QA_TESTING → QA_PASSED/FAILED

```bash
bash ~/.claude/logger.sh agent_start "QA 开始执行测试" "qa"
bash ~/.claude/logger.sh state_change "IMPLEMENTATION → QA_TESTING" "orchestrator"
# [QA /prepare-ui-tests 执行]

# QA 通过
bash ~/.claude/logger.sh qa_passed "QA 全部通过：{n}/{n} 用例" "qa"
bash ~/.claude/logger.sh state_change "QA_TESTING → QA_PASSED" "orchestrator"
bash ~/.claude/logger.sh done "🎉 项目完成！查看报告: doc/tests/qa-report.md" "orchestrator"

# QA 失败（另一个分支）
bash ~/.claude/logger.sh qa_failed "QA 失败：{n} 个用例失败" "qa"
bash ~/.claude/logger.sh state_change "QA_TESTING → QA_FAILED" "orchestrator"
# reflection_count + 1
# 如果 < 3，重新走 IMPLEMENTATION
# 如果 >= 3，停止
```

---

## 状态卡片模板（检查点时输出）

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 状态: {STATE}
🏗  项目: {project}
✅ 已完成: {completed_nodes}
⏭  下一步: {next_action}
📊 追踪报告: doc/logs/summary.md
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{具体等待用户做什么，一句话}
```

---

## Orchestrator 启动清单（新任务时）

```bash
# 1. 创建目录结构
mkdir -p doc/{logs,tests}

# 2. 确认 git 已初始化（Codex 需要）
[ -d .git ] || git init

# 3. 初始化 state.json
cat > doc/state.json << 'EOF'
{
  "state": "IDEA",
  "project": "PROJECT_NAME",
  "prd_path": "doc/prd.md",
  "figma_url": null,
  "tests_path": "doc/tests/",
  "reflection_count": 0,
  "entry_point": "IDEA",
  "sessions": { "fe": null, "be": null, "qa": null },
  "chain_log": []
}
EOF

# 4. 确保 logger 可执行
chmod +x ~/.claude/logger.sh

# 5. 写入第一条日志
bash ~/.claude/logger.sh state_change "系统初始化完成，状态: IDEA" "orchestrator"
```

---

## CLI 调用速查

```bash
# Codex (BE/QA) - 必须在 git repo 内
codex exec --full-auto '{任务}'

# Gemini (FE) - 必须 --yolo
gemini --yolo -p '{任务}'

# 后台并行
FE_SID=$(gemini --yolo -p '{FE任务}' &)
BE_SID=$(codex exec --full-auto '{BE任务}' &)

# 状态查看
cat doc/logs/summary.md
```

---

## 错误恢复

| 场景 | 处理 |
|------|------|
| CLI 命令超时 | 终止进程，报告超时，建议重试 |
| Agent 输出格式错误 | 尝试解析，失败则报告原始输出 |
| 并行任务一方失败 | 终止另一方（如仍运行），报告失败方原因 |
| 状态文件损坏 | 从 chain_log 重建最后已知状态 |
| 用户发送无效信号 | 提示当前状态和可用操作 |

---

## 全局约束

1. **Git 必须**：Codex 需要在 git repo 内，无则 `git init`
2. **Gemini 必须 --yolo**：否则会挂起等待确认
3. **日志必须**：每个节点开始/结束/失败都要写日志
4. **并行支持**：FE+BE 同步启动，都完成才进下一状态
5. **失败立即停链**：写 chain_break 日志，输出失败摘要，等待用户
6. **调查最多3次**：QA_FAILED 经 /investigate 调查后重试，超3次停止
7. **状态持久化**：每次状态转换后写 state.json + 日志
8. **项目隔离**：所有运行时文件在项目级 `doc/` 目录，全局 `~/.claude/` 只存模板
9. **Gstack 全部走 Claude**：所有 gstack skills 均通过 Claude CLI 执行，不走 Codex/Gemini
10. **质量关卡不跳过**：CEO_REVIEW 和 CODE_REVIEW 为必经节点，不可 skip
11. **设计质量**：所有涉及 UI/前端的设计审查和实现必须参考 impeccable frontend-design skill，避免 AI Slop
