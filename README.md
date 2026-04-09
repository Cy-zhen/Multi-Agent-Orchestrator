# Multi-Agent Orchestrator — Claude CLI + Antigravity

> PM/Designer/General 由 Claude(Antigravity) 执行，FE 由 Gemini 执行，BE/QA 由 Codex 执行。
> 状态机自动推进，用户只需 5 次介入。

## Runtime Truth

- **真实运行入口**: `~/.claude/orchestrator.sh` 与 `~/.claude/orchestrator/`
- 仓库中的 `claude/` 是当前 shell runtime 的开发副本
- 仓库中的 `orchestrator/` 是 Python v2 / LangGraph 实验目录，不是当前 live runtime
- **仓库修改不会自动同步到 live**
- 如果只改仓库副本，不同步到 `~/.claude/...`，Antigravity 实际行为不会变化

## Role / Executor Model

- `role` 决定职责边界：PM / Designer / FE / BE / QA / General
- `executor` 决定执行载体：`gemini` / `codex` / `claude` / `antigravity`
- fallback 是 **同一 role 换 executor**，不是角色漂移
- 例子：`FE@gemini` 失败后回退到 `FE@antigravity`

## 快速开始

### 1. 安装

```bash
# 解压到 home 目录
tar xzf orchestrator-bundle.tar.gz -C ~/

# 验证
ls ~/.claude/orchestrator.sh    # Claude CLI 侧
```

### 2. 目录结构

```
~/.claude/                        ← Claude CLI 全局配置
├── CLAUDE.md                     ← 全局编排规则
├── orchestrator.sh               ← 核心编排脚本（支持 --ag 模式）
├── logger.sh                     ← 日志系统
├── checkpoint.sh                 ← 断点恢复
├── setup-orchestrator.sh         ← 项目初始化
├── agents/                       ← 6 个 Agent 角色定义
│   ├── pm.md                     ← PM（Claude 执行）
│   ├── designer.md               ← Designer（Claude 执行）
│   ├── fe.md                     ← FE（Gemini 执行）
│   ├── be.md                     ← BE（Codex 执行）
│   ├── qa.md                     ← QA（Codex 执行）
│   ├── general.md                ← General（Claude 执行）
│   └── pm-references/            ← PM 参考文档
├── skills/                       ← Claude Code 全局技能
│   ├── frontend-design/          ← 🆕 Impeccable 设计技能 (SKILL.md + 7 reference)
│   ├── audit/ polish/ ...         ← 🆕 20 个 Impeccable 命令 skill
│   └── gstack/                   ← 质量关卡技能
├── orchestrator/                 ← 实验性 Python v2 / LangGraph 目录（非当前 live）
│   ├── SKILL.md                  ← 完整编排技能定义
│   ├── state-machine.md          ← 状态机说明
│   ├── logging.md                ← 日志格式说明
│   ├── state.py                  ← [v2] LangGraph 状态定义（TypedDict）
│   ├── graph.py                  ← [v2] LangGraph StateGraph（11 节点）
│   ├── orchestrator.py           ← [v2] Python 状态机编排器
│   ├── tracing.py                ← [v2] LangSmith 可观测性
│   ├── agents/                   ← [v2] Agent 基类
│   │   └── base.py              ← BaseAgent + CLI 执行器
│   ├── acceptance/               ← [v2] 验收系统
│   │   ├── checker.py           ← AcceptanceChecker（PM/FE/BE/QA/Designer）
│   │   ├── contract.py          ← 🆕 机器可读验收契约校验器
│   │   └── contract-template.json ← 🆕 断上下文可恢复的验收模板
│   ├── skills/                   ← 技能系统
│   │   ├── loader.py            ← [v2] SkillLoader（模板注入 + 渐进式披露）
│   │   ├── determine-next-action.md
│   │   ├── dispatch-agent.md
│   │   ├── run-chain.md
│   │   ├── pm/_config.yaml + 2 skills
│   │   ├── fe/_config.yaml + 2 skills
│   │   ├── be/_config.yaml + 2 skills
│   │   └── qa/_config.yaml + 2 skills
│   ├── chains/                   ← 执行链模板
│   │   ├── approve-prd.json
│   │   ├── plan-approved.json
│   │   └── qa-fix.json
│   └── dispatch-templates/       ← [v2] 5-Phase ReAct Prompt 模板
│       ├── pm-generate-prd.txt
│       ├── be-review-prd.txt
│       ├── fe-review-prd.txt
│       ├── designer-figma-prompt.txt
│       ├── qa-prepare-tests.txt
│       ├── qa-run-tests.txt
│       ├── be-implementation.txt
│       ├── fe-implementation.txt     ← 🆕 引用 impeccable 设计指南
│       ├── design-review-plan.txt    ← 🆕 引用 impeccable 7 维度
│       ├── design-review-visual.txt  ← 🆕 引用 impeccable 视觉基准
│       ├── pm-design-spec.txt        ← 🆕 设计规格提取模板
│       ├── pm-product-doc.txt        ← 🆕 产品文档生成模板（含流程图）
│       └── general-add-reflection.txt
└── workflows/                    ← 工作流触发器
    ├── start.md
    ├── onboard.md
    ├── approve.md
    ├── resume.md
    ├── set-state.md
    └── status.md

~/.gemini/                        ← 🆕 Gemini CLI 全局配置
└── skills/                       ← Impeccable 设计技能（FE Agent 使用）
    ├── frontend-design/          ← SKILL.md + 7 reference
    └── audit/ polish/ ...         ← 20 个命令 skill

~/.codex/                         ← 🆕 Codex CLI 全局配置
└── skills/                       ← Impeccable 设计技能（BE Agent 参考）
    ├── frontend-design/
    └── audit/ polish/ ...

项目仓库副本/                      ← Git 跟踪用
├── claude/orchestrator/          ← 当前 shell runtime 的仓库开发副本
├── orchestrator/                 ← Python v2 / LangGraph 实验目录
├── antigravity/
│   └── GEMINI.md                 ← Gemini CLI 角色定义（FE Agent）
├── claude/
│   └── CLAUDE.md                 ← Claude CLI 角色定义（Orchestrator）
└── doc/                          ← 进展文档
```

### 3. 使用方式

#### 从 Antigravity 客户端（推荐）
直接描述需求即可，Antigravity 会：
1. 先执行项目记忆预检：`bash ~/.project-memory/bin/pmem.sh status <project_dir>`
2. 已注册项目时先询问是否加载；确认后执行 `bash ~/.project-memory/bin/pmem.sh load <project_dir>`
3. 再调用 `orchestrator.sh --ag <command>` 管理工作流
4. 收到 `CLAUDE_TASK_PENDING` 时自己执行 Claude 任务（PM/Designer/General）
5. Codex/Gemini 任务由脚本内部调用
6. 任务结束后若产生新的关键上下文，主动询问是否更新项目记忆

#### 从 Claude CLI
```bash
claude  # 启动后直接描述需求，或：
# /orchestrator-start ~/my-project
# "approved"
# "figma ready https://..."
# "plan approved"
```

#### LangGraph 版（实验）
```bash
python3 ~/.claude/orchestrator/graph.py run <project_dir>       # 运行直到 USER_GATE
python3 ~/.claude/orchestrator/graph.py resume <project_dir>    # 从 checkpoint 恢复
python3 ~/.claude/orchestrator/graph.py visualize               # 输出 Mermaid 图
python3 ~/.claude/orchestrator/graph.py status <project_dir>    # checkpoint + tracing 状态
```

### 4. 工作流（5 次用户介入）

```
① 描述概念 → PM 自动生成 PRD → 停在 PRD_DRAFT
② "approved" → CEO 审查 → BE 审查 → FE 审查 → Designer 生成 Stitch 提示词 → 停在 FIGMA_PROMPT
③ "figma ready {url}" → PM 提取设计规格 + 更新 PRD → 停在 DESIGN_SPEC_REVIEW
④ "approved" → QA 生成测试 → 出实现计划 → 停等 plan approved
⑤ "plan approved" → FE+BE 并行编码 → 代码审查 → 安全审计 → QA 测试 → PM 生成产品文档 → DONE
```

### Python v2 节点拓扑（实验）
```
PM → PM_UserReview → BE_Review →|approved| FE_Review →|approved| Designer
                                 |rejected| PM          |rejected| PM
Designer → Design_UserReview → QA_Prepare → Plan_UserReview → Implementation
Implementation → QA_Test →|pass| END
                          |fail| Reflection → Implementation (max 3x)
```

### 5. Agent 派发规则

| Agent | 执行者 | CLI | 产出 |
|-------|--------|-----|------|
| PM | Claude/Antigravity | `claude -p` | doc/prd.md |
| Designer | Claude/Antigravity | `claude -p` | doc/figma-prompts.md |
| General | Claude/Antigravity | `claude -p` | doc/reflection.md |
| FE | Gemini CLI | `gemini -p` | 前端代码 (.tsx/.css) |
| BE | Codex CLI | `codex exec` | 后端代码 (.go) |
| QA | Codex CLI | `codex exec` | 测试代码 + 测试执行 |

### Fallback 规则

- FE: `gemini` 失败时，CLI 模式回退到 `claude`，Antigravity 模式回退到 `antigravity`
- BE/QA: `codex` 失败时，CLI 模式回退到 `claude`，Antigravity 模式回退到 `antigravity`
- PM/Designer/General 在 `--ag` 模式下天然由 Antigravity 人工执行
- 回退后 **role 不变**，只变 `executor`
- `CLAUDE_TASK_PENDING` 表示同一 `role` 等待人工接管，不表示角色切换

### 6. 前置要求

- **Claude CLI** (`claude`) — 已安装并登录
- **Codex CLI** (`codex`) — 已安装并配置 API key
- **Gemini CLI** (`gemini`) — 已安装并完成 OAuth
- **Python 3.10+** — LangGraph 版需要
- **jq** — JSON 处理
- **Git** — Codex 需要 git repo
- **Impeccable 🆕** — 已安装到 `~/.claude/skills/`、`~/.gemini/skills/`、`~/.codex/skills/`

#### Python 依赖（实验 v2）
```bash
pip install langgraph langsmith langchain-core
```

#### LangSmith 可观测性（可选）
```bash
export LANGSMITH_API_KEY="ls-xxxx"
export LANGSMITH_PROJECT="multi-agent-orchestrator"
export LANGSMITH_TRACING=true
```

---

### 7. Onboard 已有项目

> 适用于已开发的产品接入工作流，从现有代码反向生成文档。

```bash
# Claude CLI
/orchestrator-onboard ~/my-existing-project

# Antigravity
"onboard ~/my-existing-project"
```

**Onboard 流程（2 步自动 + 1 步人工）:**

```
① Codex 扫描代码 → doc/code-scan.md (自动)
② PM 反向生成 PRD → doc/prd.md (自动 / Antigravity 执行)
③ 用户审阅 PRD → "approved" → 从 PRD_APPROVED 继续标准流程
```

| 场景 | 切入点 |
|------|--------|
| 已有产品 + 新功能 | PRD_APPROVED |
| 已有产品 + 修 bug | `/set-state IMPLEMENTATION` |
| 已有前端 + 新建后端 | PRD_APPROVED (标记 FE 完成) |
| 已有后端 + 新建前端 | DESIGN_READY (标记 BE 完成) |

---

### 8. 项目级产出文件

每个项目在 `{PROJECT_DIR}/doc/` 下自动产生以下文件（项目间完全隔离）：

```
{PROJECT_DIR}/doc/
├── state.json                ← 工作流状态（当前阶段 + 元数据）
├── idea.txt                  ← 用户概念描述
├── code-scan.md              ← Codex 代码扫描报告（onboard 时）
├── prd.md                    ← PM 生成的 PRD（随流程增量更新）
├── design-spec.md            ← 🆕 PM 提取的设计规格书（UI/交互/组件/状态）
├── product-doc.md            ← 🆕 PM 生成的产品文档（含5类流程图）
├── acceptance-contract.json  ← 🆕 机器可读验收契约（上下文恢复的事实源）
├── figma-prompts.md          ← Designer 生成的 Figma 提示词
├── fe-plan.md                ← FE 审查 PRD 后的实现计划
├── fe-self-check.md          ← 🆕 FE 最小自测结果
├── test-plan.md              ← QA 生成的测试计划
├── be-self-check.md          ← 🆕 BE 最小自测结果
├── test-report.md            ← 🆕 QA 正式验收报告
├── acceptance-screenshots/   ← 🆕 关键页面/状态截图证据
│   ├── *.png
│   └── manifest.json
├── reflection.md             ← General 反思分析（QA 失败时）
├── .claude-task.md           ← [临时] Antigravity 模式的 prompt
├── .claude-task-meta.json    ← [临时] 任务元数据 (agent/skill/next_state)
├── checkpoint.json           ← [活跃链] 执行链断点（完成后删除）
├── execution-plan.md         ← [活跃链] step-by-step 进度（完成后删除）
└── logs/
    ├── workflow.jsonl         ← 结构化日志（JSONL，机器可读）
    ├── {date}.log            ← 人类可读日志（按天归档）
    ├── summary.md            ← 追踪报告（状态卡片 + Agent 统计）
    └── chains/               ← 已完成执行链归档
        └── {chain}_{ts}.json
```

| 文件 | 产生者 | 时机 |
|------|--------|------|
| `state.json` | orchestrator.sh | init/onboard 创建，每次状态转换更新 |
| `prd.md` | PM (Claude) | 生成 → DESIGN_SPEC 增量更新 → PRODUCT_DOC 冻结 |
| `design-spec.md` | PM (Claude) | 🆕 Stitch 完成后提取设计规格 |
| `product-doc.md` | PM (Claude) | 🆕 开发完成后生成产品文档（含流程图） |
| `acceptance-contract.json` | FE/QA | 🆕 设计冻结后生成，开发/验收阶段持续更新 |
| `code-scan.md` | Codex (BE) | onboard 扫描代码 |
| `figma-prompts.md` | Designer (Claude) | PRD 批准后生成 |
| `fe-plan.md` | FE (Gemini) | FE 审查 PRD 后 |
| `fe-self-check.md` | FE (Gemini / direct run) | 🆕 FE 实现完成前更新最小自测 |
| `test-plan.md` | QA (Codex) | Figma 完成后生成 |
| `be-self-check.md` | BE (Codex / direct run) | 🆕 BE 实现完成前更新最小自测 |
| `test-report.md` | QA (Codex) | 🆕 QA 执行后输出正式验收结果 |
| `acceptance-screenshots/manifest.json` | QA / 视觉审查 | 🆕 每次验收更新截图证据 |
| `logs/workflow.jsonl` | logger.sh | 每个 Agent 操作时追加 |
| `logs/summary.md` | logger.sh | 状态变化时重新渲染 |
| `checkpoint.json` | checkpoint.sh | 执行链运行时，完成后清理 |

`/status` 命令自动读取以上文件，输出：
- 当前状态 + 节点类型
- 最近 8 条执行历史（谁在什么时候干了什么）
- 活跃执行链进度（如有）
- 下一步建议

### 9. 断点恢复

新会话进入已有项目时，agent 会：
1. 读 `doc/state.json` → 了解当前状态
2. 读 `doc/logs/summary.md` → 了解执行历史
3. 如有 `doc/checkpoint.json` → 从断点继续
4. 否则 → 从当前状态的下一步开始

### 10. 轻量验收契约

为了解决“上下文断掉后测试遗漏、后续 Agent 跑偏”的问题，v2 增加了轻量验收契约：

- `doc/acceptance-contract.json` 是验收事实源，不是长篇说明文
- 它必须明确：
  - 这次改了哪些页面 / 路由
  - 哪些是 P0 用户路径
  - 哪些 UI 状态必须被验证
  - 哪些地方不能回归
  - 需要保留哪些截图证据
  - FE / BE / QA 各层必须交什么证据
- `doc/acceptance-screenshots/` 保存关键截图，作为交接和复验证据
- `doc/fe-self-check.md` 与 `doc/be-self-check.md` 是开发层自证，不等同于 QA
- `doc/test-report.md` 是 QA 正式验收结果，必须写明 `Contract Revision: N`

校验方式：

```bash
python3 orchestrator/acceptance/contract.py doc/acceptance-contract.json
python3 orchestrator/acceptance/consistency.py .
```

这个方案刻意不做全站像素级视觉回归；优先保证任何 Agent 在失去会话上下文后，仍能根据同一份契约完成复验。

```bash
# 恢复执行
/orchestrator-resume ~/my-project
# 或
"resume"

# LangGraph 版
python3 ~/.claude/orchestrator/graph.py resume ~/my-project
```

---

### 10. Python v2 实验内容

> 下面这些能力主要对应 `项目/orchestrator/` 目录。
> 当前 Antigravity 的主工作流仍然跑 `~/.claude/orchestrator.sh` 这条 shell runtime。

| Phase | 内容 | 说明 |
|-------|------|------|
| Phase 0 | Skills 框架 | 4 agent × (_config.yaml + 2 skills)，按角色注入专业知识 |
| Phase 1 | ReAct 模板 | 9 个模板升级为 5-Phase ReAct 格式（分析→规划→执行→验证→总结） |
| Phase 1.5 | 渐进式披露 | `inject_at` 字段控制 skill 在哪个 phase 注入 |
| Phase 2 | Python 编排器 | SkillLoader + BaseAgent + 13 状态 state machine |
| Phase 3 | 验收系统 | AcceptanceChecker（PM/FE/BE/QA/Designer 各有验收规则） |
| Phase 4 | LangGraph | StateGraph 11 节点 + SQLite checkpointer + Mermaid 可视化 |
| Phase 5 | LangSmith | @traceable 装饰器 + span API，零开销优雅降级 |
| Phase 6 | Impeccable | 集成 pbakaus/impeccable 前端设计技能，3 个 dispatch template 引用设计基准 |

---

### 11. Impeccable 设计技能 🆕

> 来源：[pbakaus/impeccable](https://github.com/pbakaus/impeccable) (Apache 2.0)

所有 Agent 共享的前端设计技能，避免 AI Slop（千篇一律的 AI 生成 UI）。

**包含：**
- 1 个核心 skill (`frontend-design`) + 7 个设计参考文档（排版/配色/空间/动效/交互/响应式/UX文案）
- 20 个命令 skill：`/audit` `/polish` `/normalize` `/critique` `/distill` 等

**安装位置：**

| CLI | 路径 |
|-----|------|
| Claude Code | `~/.claude/skills/frontend-design/` |
| Gemini CLI | `~/.gemini/skills/frontend-design/` |
| Codex CLI | `~/.codex/skills/frontend-design/` |

**Dispatch Template 集成：**
- `design-review-plan.txt` — 7 维度设计审查对齐 impeccable
- `design-review-visual.txt` — 80 项视觉审查引用 impeccable 基准
- `fe-implementation.txt` — FE 编码时参考 impeccable 设计指南

---

### 12. Token 效率规则 🆕

> 来源：[drona23/claude-token-efficient](https://github.com/drona23/claude-token-efficient) (MIT, ⭐2.6k)

社区验证的 Claude 输出 token 优化规则，平均减少 ~63% 无效输出。适配多 Agent 编排场景后集成到所有配置文件。

**核心规则：**
1. 先思考再行动 — 读取已有文件再写代码
2. 输出精炼 — 禁止拍马屁开头和废话结尾
3. 局部编辑优先 — 不重写整个文件
4. 不重复读取 — 已读文件不重复读取
5. 测试后交付 — 代码完成前必须验证
6. 简单直接 — 不过度工程
7. 用户指令优先 — 用户明确指令覆盖一切
8. 纯 ASCII — 避免 em dash、智能引号等特殊字符

**同步位置：**

| 文件 | 说明 |
|------|------|
| `~/.claude/CLAUDE.md` | Claude 全局配置（Orchestrator + PM/Designer/General） |
| `antigravity/GEMINI.md` | Gemini FE Agent 配置 |
| `antigravity/skills/multi-agent-orchestrator/SKILL.md` | Orchestrator 技能定义（Antigravity 使用） |
