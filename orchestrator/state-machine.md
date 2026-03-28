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
| `CEO_REVIEW` | `AUTO` | Gstack | claude | `/plan-ceo-review` | Claude | 🆕 CEO 视角审查产品设计合理性 |
| `PRD_REVIEW` | `AUTO` | BE | codex | `/review-prd` | BE Agent | BE 从后端视角审查 PRD |
| `BE_APPROVED` | `AUTO` | FE | gemini | `/review-prd` | FE Agent | FE 从前端视角审查 PRD |
| `DESIGN_PLAN_REVIEW` | `AUTO` | Gstack | claude | `/plan-design-review` | Claude | 🆕 7维度设计审查 |
| `PRD_APPROVED` | `AUTO` | Designer | claude | `/generate-stitch-prompt` | Designer | 生成 Stitch 设计提示词 |
| `FIGMA_PROMPT` | `USER_GATE` | — | — | — | 用户 | 等待 Stitch 设计完成 |
| `DESIGN_READY` | `AUTO` | QA | codex | `/prepare-tests` | QA Agent | 生成测试计划 |
| `TESTS_WRITTEN` | `PLAN_GATE` | — | — | — | 用户 | 用户审阅计划 |
| `IMPLEMENTATION` | `AUTO` | FE+BE | gemini+codex | `/figma-to-code` | FE+BE 并行 | 前后端并行编码 |
| `CODE_REVIEW` | `AUTO` | Gstack | claude | `/review` | Claude | 🆕 Staff Engineer 生产级代码审查 |
| `SECURITY_AUDIT` | `AUTO` | Gstack | claude | `/cso` | Claude | 🆕 OWASP + STRIDE 安全审计 |
| `QA_TESTING` | `AUTO` | QA | codex | `/run-tests` | QA Agent | 执行自动化测试 |
| `VISUAL_REVIEW` | `AUTO` | Gstack | claude | `/design-review` | Claude | 🆕 80项视觉审查 + 自动修复 |
| `QA_PASSED` | `AUTO` | Gstack | claude | `/ship` | Claude | 🆕 Release Engineer 发布流程 |
| `QA_FAILED` | `AUTO` | Gstack | claude | `/investigate` | Claude | 🆕 系统化 root-cause 调试（替代 /add-reflection） |
| `DONE` | — | — | — | — | — | 终止状态 |

---

## 转换表

```
源状态              node_type     触发条件                            目标状态             执行者              prompt_template
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
IDEA              INTERACTIVE  用户提供概念描述                     PRD_DRAFT           PM(Claude)          pm-generate-prd.txt
PRD_DRAFT         USER_GATE    用户说 "approved/通过"              CEO_REVIEW          用户信号             —
CEO_REVIEW        AUTO         CEO 审查通过                        PRD_REVIEW          Gstack(Claude)      ceo-review-prd.txt
CEO_REVIEW        AUTO         CEO 审查不通过                      PRD_DRAFT           Gstack(Claude)      ceo-review-prd.txt
PRD_REVIEW        AUTO         BE 审查通过                         BE_APPROVED         BE(Codex)           be-review-prd.txt
PRD_REVIEW        AUTO         BE 审查不通过                       PRD_DRAFT           BE(Codex)           be-review-prd.txt
BE_APPROVED       AUTO         FE 审查通过                         DESIGN_PLAN_REVIEW  FE(Gemini)          fe-review-prd.txt
BE_APPROVED       AUTO         FE 审查不通过                       PRD_DRAFT           FE(Gemini)          fe-review-prd.txt
DESIGN_PLAN_REVIEW AUTO        设计审查通过                        PRD_APPROVED        Gstack(Claude)      design-review-plan.txt
DESIGN_PLAN_REVIEW AUTO        设计审查发现问题                    PRD_DRAFT           Gstack(Claude)      design-review-plan.txt
PRD_APPROVED      AUTO         生成 Stitch 设计提示词                FIGMA_PROMPT        Designer            designer-figma-prompt.txt
FIGMA_PROMPT      USER_GATE    用户说 "design ready {url}"           DESIGN_READY        用户信号             —
DESIGN_READY      AUTO         QA 生成测试计划                     TESTS_WRITTEN       QA(Codex)           qa-prepare-tests.txt
TESTS_WRITTEN     PLAN_GATE    用户说 "plan approved"              IMPLEMENTATION      用户信号             —
IMPLEMENTATION    AUTO         FE+BE 编码完成                      CODE_REVIEW         FE+BE               fe/be-implementation.txt
CODE_REVIEW       AUTO         代码审查通过                        SECURITY_AUDIT      Gstack(Claude)      staff-review-code.txt
CODE_REVIEW       AUTO         代码审查发现严重问题                IMPLEMENTATION      Gstack(Claude)      staff-review-code.txt
SECURITY_AUDIT    AUTO         安全审计通过                        QA_TESTING          Gstack(Claude)      cso-audit.txt
SECURITY_AUDIT    AUTO         安全审计发现严重漏洞                IMPLEMENTATION      Gstack(Claude)      cso-audit.txt
QA_TESTING        AUTO         测试通过                            VISUAL_REVIEW       QA(Codex)           qa-run-tests.txt
QA_TESTING        AUTO         测试失败                            QA_FAILED           QA(Codex)           qa-run-tests.txt
VISUAL_REVIEW     AUTO         视觉审查通过/修复完成               QA_PASSED           Gstack(Claude)      design-review-visual.txt
QA_PASSED         AUTO         Release 完成                        DONE                Gstack(Claude)      ship-release.txt
QA_FAILED         AUTO         调查后重新实现 (count<3)            IMPLEMENTATION      Gstack(Claude)      investigate-failure.txt
QA_FAILED         USER_GATE    调查次数 ≥ 3                       —                   用户干预             —
ANY_STATE         —            用户 /update-prd                    PRD_DRAFT           PM(Claude)          pm-generate-prd.txt
```

---

## Auto-Chain 路径

### 路径 1: 概念 → PRD (INTERACTIVE → USER_GATE)
```
用户输入概念
  → PM: /generate-prd (INTERACTIVE)
  → 输出 PRD 文件
  → 状态 = PRD_DRAFT (USER_GATE)
  → ⏸ 等待用户操作：审阅 PRD
```

### 路径 2: 用户批准 → 设计提示词 (AUTO×5 → USER_GATE)
```
用户: "approved" (状态=PRD_DRAFT)
  → 1. 🆕 Gstack: /plan-ceo-review (AUTO, Claude)
    ├→ 通过 → 2. BE: /review-prd (AUTO, Codex)
    │         ├→ 通过 → 3. FE: /review-prd (AUTO, Gemini)
    │         │         ├→ 通过 → 4. 🆕 Gstack: /plan-design-review (AUTO, Claude)
    │         │         │         ├→ 通过 → 5. Designer: /generate-stitch-prompt (AUTO)
    │         │         │         │         → 状态 = FIGMA_PROMPT (USER_GATE)
    │         │         │         │         → ⏸ 等待用户操作：Stitch 设计完成
    │         │         │         └→ 发现问题 → ❌ 链停止 → PRD_DRAFT
    │         │         └→ 不通过 → ❌ 链停止 → PRD_DRAFT
    │         └→ 不通过 → ❌ 链停止 → PRD_DRAFT
    └→ 不通过 → ❌ 链停止 → PRD_DRAFT (附 CEO 反馈)
```

### 路径 3: 设计完成 → 实现计划 (AUTO → PLAN_GATE)
```
用户: "design ready https://..." (状态=FIGMA_PROMPT)
  → 记录 design_url (存入 figma_url 字段)
  → 1. QA: /prepare-tests (AUTO)
  → 状态 = TESTS_WRITTEN (PLAN_GATE)
  → ⏸ 等待方案审批：审阅测试计划和实现计划
```

### 路径 4: 计划批准 → 完成 (AUTO×7 → DONE | LOOP)
```
用户: "plan approved" (状态=TESTS_WRITTEN)
  → 1. FE + BE: /figma-to-code build (AUTO, 并行)
    → 等待两者完成
  → 2. 🆕 Gstack: /review (AUTO, Claude) — Staff Engineer 代码审查
    ├→ 通过 → 继续
    └→ 严重问题 → IMPLEMENTATION (重新修改)
  → 3. 🆕 Gstack: /cso (AUTO, Claude) — 安全审计
    ├→ 通过 → 继续
    └→ 严重漏洞 → IMPLEMENTATION (修复)
  → 4. QA: /run-tests (AUTO)
    ├→ 全部通过 → 5. 🆕 Gstack: /design-review (AUTO) — 视觉审查
    │             → 6. 🆕 Gstack: /ship (AUTO) — 发布
    │             → 状态 = DONE ✅
    └→ 有失败 → 7. 🆕 Gstack: /investigate (AUTO) — 调查根因
                → 状态 = IMPLEMENTATION → 回到步骤 1 (循环修复)
                → 最多 3 次
```

### 路径 5: 完成后回顾 (DONE 后可选)
```
状态 = DONE
  → 用户: "/retro" (手动触发)
  → Gstack: /retro — 生成回顾报告
  → 用户: "/document-release" (手动触发)
  → Gstack: /document-release — 更新项目文档
```

---

## 用户信号 → 状态映射

| 用户输入 | 当前状态 | 目标状态 | 触发 Chain |
|---------|---------|---------|-----------|
| 概念描述文本 | `IDEA` | `PRD_DRAFT` | 内联 PM |
| `approved` / `通过` / `批准` | `PRD_DRAFT` | `CEO_REVIEW` | approve-prd chain |
| `design ready {url}` / `stitch ready {url}` / `figma ready {url}` | `FIGMA_PROMPT` | `DESIGN_READY` | design-ready chain |
| `plan approved` / `计划通过` | `TESTS_WRITTEN` | `IMPLEMENTATION` | plan-approved chain |
| `修改: {内容}` | 任意 | `PRD_DRAFT` | PM /update-prd |
| `retry` / `重试` | 失败状态 | 重启失败节点 | — |
| `skip` / `跳过` | 失败状态 | 跳过当前步骤 | 日志记录 |
| `/status` | 任意 | 不变 | 显示状态 |
| `/resume` | 有 checkpoint | 断点恢复 | resume chain |
| `/retro` | `DONE` | 不变 | Gstack 生成回顾报告 |
| `/document-release` | `DONE` | 不变 | Gstack 更新文档 |

---

## 输入/输出约定

### 每个 Agent 的输出必须包含

```json
{
  "success": true|false,
  "agent": "PM|Designer|FE|BE|QA|General|Gstack",
  "action": "/generate-prd|/review-prd|/plan-ceo-review|...",
  "summary": "简要描述完成了什么",
  "output_files": ["path/to/file1", "path/to/file2"],
  "issues": [],
  "approved": true|false
}
```

### 失败时必须包含

```json
{
  "success": false,
  "agent": "Gstack",
  "action": "/plan-ceo-review",
  "error": "具体错误描述",
  "suggestion": "建议的修复方向"
}
```

---

## Gstack Skills 速查（按工作流阶段）

| 阶段 | Skill | 角色 | 说明 |
|------|-------|------|------|
| Think | `/office-hours` | YC Partner | IDEA 阶段产品重定义（可选增强） |
| Plan | `/plan-ceo-review` | CEO | PRD 审查：产品设计合理性 |
| Plan | `/plan-eng-review` | Eng Manager | 架构审查（可选，增强 BE+FE 审查） |
| Plan | `/plan-design-review` | Senior Designer | 7维度设计审查 |
| Design | `/design-consultation` | Design Partner | 设计系统构建（可选） |
| Review | `/review` | Staff Engineer | 代码审查：生产级 bug |
| Security | `/cso` | CSO | OWASP + STRIDE 安全审计 |
| Test | `/qa` | QA Lead | 浏览器自动化测试（增强） |
| Visual | `/design-review` | Designer Who Codes | 80项视觉审查 |
| Debug | `/investigate` | Debugger | 系统化 root-cause 调试 |
| Ship | `/ship` | Release Engineer | 发布流程 |
| Docs | `/document-release` | Technical Writer | 更新文档 |
| Reflect | `/retro` | Eng Manager | 回顾报告 |
