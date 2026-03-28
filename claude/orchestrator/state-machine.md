# State Machine Reference

## 节点类型定义

| 类型 | 含义 | 行为 | 输出格式 |
|------|------|------|---------|
| `AUTO` | 系统自动执行 | 派发 Agent → 执行 → 推进下一步 | `自动执行：{skill}...` |
| `USER_GATE` | 等待用户操作 | 输出提示 → 停止链 | `等待用户操作：{描述}` |
| `PLAN_GATE` | 等待方案审批 | 输出提示 → 停止链 | `等待方案审批：{描述}` |
| `INTERACTIVE` | 需要用户交互 | 输出提示 → 停止链 | `需要交互：{描述}` |

---

## 状态定义

| 状态 | node_type | Agent | CLI | Skill | 等待方 | 描述 |
|------|-----------|-------|-----|-------|--------|------|
| `IDEA` | `INTERACTIVE` | — | — | — | 用户 | 需要用户描述产品概念 |
| `PRD_DRAFT` | `USER_GATE` | — | — | — | 用户 | 用户审阅 PRD，"approved" 继续 |
| `PRD_REVIEW` | `AUTO` | BE | codex | `/review-prd` | BE Agent | BE 从后端视角审查 PRD |
| `BE_APPROVED` | `AUTO` | FE | gemini | `/review-prd` | FE Agent | FE 从前端视角审查 PRD |
| `PRD_APPROVED` | `AUTO` | Designer | claude | `/generate-stitch-prompt` | Designer | 生成 Stitch 设计提示词 |
| `FIGMA_PROMPT` | `USER_GATE` | — | — | — | 用户 | 等待 Stitch 设计完成 |
| `DESIGN_READY` | `AUTO` | QA | codex | `/prepare-tests` | QA Agent | 生成测试计划 |
| `TESTS_WRITTEN` | `PLAN_GATE` | — | — | — | 用户 | 用户审阅计划 |
| `IMPLEMENTATION` | `AUTO` | FE+BE | gemini+codex | `/figma-to-code` | FE+BE 并行 | 前后端并行编码 |
| `QA_TESTING` | `AUTO` | QA | codex | `/run-tests` | QA Agent | 执行自动化测试 |
| `QA_PASSED` | `AUTO` | — | — | — | — | 自动 → DONE |
| `QA_FAILED` | `AUTO` | General | claude | `/add-reflection` | General | 分析失败 (≤3次) |
| `DONE` | — | — | — | — | — | 终止状态 |

---

## 转换表

```
源状态          node_type     触发条件                          目标状态         执行者        prompt_template
──────────────────────────────────────────────────────────────────────────────────────────────────────────────
IDEA          INTERACTIVE  用户提供概念描述                   PRD_DRAFT       PM(Claude)    pm-generate-prd.txt
PRD_DRAFT     USER_GATE    用户说 "approved/通过"            PRD_REVIEW      用户信号       —
PRD_REVIEW    AUTO         BE 审查通过                       BE_APPROVED     BE(Codex)     be-review-prd.txt
PRD_REVIEW    AUTO         BE 审查不通过                     PRD_DRAFT       BE(Codex)     be-review-prd.txt
BE_APPROVED   AUTO         FE 审查通过                       PRD_APPROVED    FE(Gemini)    fe-review-prd.txt
BE_APPROVED   AUTO         FE 审查不通过                     PRD_DRAFT       FE(Gemini)    fe-review-prd.txt
PRD_APPROVED  AUTO         生成 Stitch 设计提示词               FIGMA_PROMPT    Designer      designer-figma-prompt.txt
FIGMA_PROMPT  USER_GATE    用户说 "design ready {url}"         DESIGN_READY    用户信号       —
DESIGN_READY  AUTO         QA 生成测试计划                   TESTS_WRITTEN   QA(Codex)     qa-prepare-tests.txt
TESTS_WRITTEN PLAN_GATE    用户说 "plan approved"            IMPLEMENTATION  用户信号       —
IMPLEMENTATION AUTO        FE+BE 编码完成                    QA_TESTING      FE+BE         fe/be-implementation.txt
QA_TESTING    AUTO         测试通过                          QA_PASSED       QA(Codex)     qa-run-tests.txt
QA_TESTING    AUTO         测试失败                          QA_FAILED       QA(Codex)     qa-run-tests.txt
QA_PASSED     AUTO         —                                DONE            —              —
QA_FAILED     AUTO         反思后重新实现 (count<3)          IMPLEMENTATION  General       general-add-reflection.txt
QA_FAILED     USER_GATE    反思次数 ≥ 3                     —               用户干预       —
ANY_STATE     —            用户 /update-prd                  PRD_DRAFT       PM(Claude)    pm-generate-prd.txt
```

---

## Auto-Chain 路径

### 路径 1: 概念 → PRD (INTERACTIVE → AUTO → USER_GATE)
```
用户输入概念
  → PM: /generate-prd (INTERACTIVE)
  → 输出 PRD 文件
  → 状态 = PRD_DRAFT (USER_GATE)
  → ⏸ 等待用户操作：审阅 PRD
```

### 路径 2: 用户批准 → 设计提示词 (AUTO×3 → USER_GATE)
```
用户: "approved" (状态=PRD_DRAFT)
  → 1. BE: /review-prd (AUTO)
    ├→ 通过 → 2. FE: /review-prd (AUTO)
    │         ├→ 通过 → 3. Designer: /generate-stitch-prompt (AUTO)
    │         │         → 状态 = FIGMA_PROMPT (USER_GATE)
    │         │         → ⏸ 等待用户操作：Stitch 设计完成
    │         └→ 不通过 → ❌ 链停止
    │                    → 状态 = PRD_DRAFT (USER_GATE)
    └→ 不通过 → ❌ 链停止
               → 状态 = PRD_DRAFT (USER_GATE)
```

### 路径 3: 设计完成 → 实现计划 (AUTO → PLAN_GATE)
```
用户: "design ready https://..." (状态=FIGMA_PROMPT)
  → 记录 design_url (存入 figma_url 字段)
  → 1. QA: /prepare-tests (AUTO)
  → 状态 = TESTS_WRITTEN (PLAN_GATE)
  → ⏸ 等待方案审批：审阅测试计划和实现计划
```

### 路径 4: 计划批准 → 完成 (AUTO×3 → DONE | LOOP)
```
用户: "plan approved" (状态=TESTS_WRITTEN)
  → 1. FE + BE: /figma-to-code build (AUTO, 并行)
    → 等待两者完成
  → 2. QA: /run-tests (AUTO)
    ├→ 全部通过 → 状态 = DONE ✅
    └→ 有失败 → 3. General: /add-reflection (AUTO)
                → 状态 = IMPLEMENTATION → 回到步骤 1 (循环修复)
                → 最多 3 次
```

---

## 用户信号 → 状态映射

| 用户输入 | 当前状态 | 目标状态 | 触发 Chain |
|---------|---------|---------|-----------|
| 概念描述文本 | `IDEA` | `PRD_DRAFT` | 内联 PM |
| `approved` / `通过` / `批准` | `PRD_DRAFT` | `PRD_REVIEW` | approve-prd chain |
| `design ready {url}` / `stitch ready {url}` / `figma ready {url}` | `FIGMA_PROMPT` | `DESIGN_READY` | design-ready chain |
| `plan approved` / `计划通过` | `TESTS_WRITTEN` | `IMPLEMENTATION` | plan-approved chain |
| `修改: {内容}` | 任意 | `PRD_DRAFT` | PM /update-prd |
| `retry` / `重试` | 失败状态 | 重启失败节点 | — |
| `skip` / `跳过` | 失败状态 | 跳过当前步骤 | 日志记录 |
| `/status` | 任意 | 不变 | 显示状态 |
| `/resume` | 有 checkpoint | 断点恢复 | resume chain |

---

## 输入/输出约定

### 每个 Agent 的输出必须包含

```json
{
  "success": true|false,
  "agent": "PM|Designer|FE|BE|QA|General",
  "action": "/generate-prd|/review-prd|...",
  "summary": "简要描述完成了什么",
  "output_files": ["path/to/file1", "path/to/file2"],
  "issues": [],
  "approved": true|false  // 仅 review 类操作
}
```

### 失败时必须包含

```json
{
  "success": false,
  "agent": "BE",
  "action": "/review-prd",
  "error": "具体错误描述",
  "suggestion": "建议的修复方向"
}
```
