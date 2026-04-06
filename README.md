# Multi-Agent Orchestrator — Claude CLI + Antigravity

> PM/Designer/General 由 Claude(Antigravity) 执行，FE 由 Gemini 执行，BE/QA 由 Codex 执行。
> 状态机自动推进，用户只需 5 次介入。

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
├── orchestrator/                 ← 编排器核心（v2 Python）
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
│   │   └── checker.py           ← AcceptanceChecker（PM/FE/BE/QA/Designer）
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

项目仓库镜像/                      ← Git 跟踪用
├── orchestrator/                 ← ~/.claude/orchestrator/ 的同步副本
├── antigravity/
│   └── GEMINI.md                 ← Gemini CLI 角色定义（FE Agent）
├── claude/
│   └── CLAUDE.md                 ← Claude CLI 角色定义（Orchestrator）
└── doc/                          ← 进展文档
```

### 3. 使用方式

#### 从 Antigravity 客户端（推荐）
直接描述需求即可，Antigravity 会：
1. 调用 `orchestrator.sh --ag <command>` 管理工作流
2. 收到 `CLAUDE_TASK_PENDING` 时自己执行 Claude 任务（PM/Designer/General）
3. Codex/Gemini 任务由脚本内部调用

#### 从 Claude CLI
```bash
claude  # 启动后直接描述需求，或：
# /orchestrator-start ~/my-project
# "approved"
# "figma ready https://..."
# "plan approved"
```

#### LangGraph 版（v2 新增）
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

### LangGraph 节点拓扑
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

### 6. 前置要求

- **Claude CLI** (`claude`) — 已安装并登录
- **Codex CLI** (`codex`) — 已安装并配置 API key
- **Gemini CLI** (`gemini`) — 已安装并完成 OAuth
- **Python 3.10+** — LangGraph 版需要
- **jq** — JSON 处理
- **Git** — Codex 需要 git repo
- **Impeccable 🆕** — 已安装到 `~/.claude/skills/`、`~/.gemini/skills/`、`~/.codex/skills/`

#### Python 依赖（v2）
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
├── figma-prompts.md          ← Designer 生成的 Figma 提示词
├── fe-plan.md                ← FE 审查 PRD 后的实现计划
├── test-plan.md              ← QA 生成的测试计划
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
| `code-scan.md` | Codex (BE) | onboard 扫描代码 |
| `figma-prompts.md` | Designer (Claude) | PRD 批准后生成 |
| `fe-plan.md` | FE (Gemini) | FE 审查 PRD 后 |
| `test-plan.md` | QA (Codex) | Figma 完成后生成 |
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

```bash
# 恢复执行
/orchestrator-resume ~/my-project
# 或
"resume"

# LangGraph 版
python3 ~/.claude/orchestrator/graph.py resume ~/my-project
```

---

### 10. v2 升级内容

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
