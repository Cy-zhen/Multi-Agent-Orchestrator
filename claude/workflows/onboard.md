---
description: Onboard an existing project into multi-agent workflow
---

# /onboard — 已有项目接入工作流

> 用于已开发的后端/前端产品快进入此多 Agent 工作流。
> 反向从代码生成文档，然后从中间状态切入。
> 与 PM Agent 的 `/import-existing` 协同工作。

## 应用场景

| 场景 | 入口 | 切入点 |
|------|------|--------|
| 已有完整产品 + 新功能需求 | `/onboard {project_dir}` | PRD_APPROVED |
| 已有产品 + 需要修 bug | `/onboard {project_dir}` + `/set-state IMPLEMENTATION` | IMPLEMENTATION |
| 已有产品 + 需要重构 | `/onboard {project_dir}` | PRD_DRAFT (重新编写目标) |
| 已有前端 + 新建后端 | `/onboard {project_dir}` | PRD_APPROVED (标记 FE 完成) |
| 已有后端 + 新建前端 | `/onboard {project_dir}` | DESIGN_READY (标记 BE 完成) |

---

## 执行流程

### 步骤 1: 初始化并分析现有代码

```bash
# 1a. 初始化项目工作流目录
bash ~/.claude/setup-orchestrator.sh ~/my-project

# 1b. 记录日志
bash ~/.claude/logger.sh agent_start "开始扫描现有代码" "pm"

# 1c. Codex 扫描代码结构（与 PM /import-existing Step 1 相同）
codex exec --full-auto '扫描当前项目代码，生成结构化分析报告，保存到 doc/code-scan.md'
bash ~/.claude/logger.sh agent_done "代码扫描完成" "be"
```

**任务要求**:
- 扫描项目目录结构（源码位置、配置文件、package.json 等）
- 识别技术栈（FE框架、BE框架、数据库、API 风格等）
- 列出所有已实现的功能模块
- 识别测试覆盖率（有无测试框架、覆盖哪些模块）
- 识别现有文档（有无 README / API docs / 架构文档）

**输出 JSON**:
```json
{
  "success": true,
  "agent": "General",
  "action": "/onboard",
  "analysis": {
    "project_dir": "/Users/cy-zhen/my-project",
    "tech_stack": {
      "frontend": "React 18 + Vite + Tailwind",
      "backend": "Node.js + Express + PostgreSQL",
      "api_style": "RESTful",
      "testing": "Jest + React Testing Library"
    },
    "modules": [
      { "name": "User Auth", "implemented": true, "status": "production" },
      { "name": "Dashboard", "implemented": true, "status": "beta" },
      { "name": "Settings", "implemented": false, "status": "planned" }
    ],
    "test_coverage": "68%",
    "documentation": {
      "has_readme": true,
      "has_api_docs": false,
      "has_arch_doc": false
    }
  },
  "next_step": "生成逆向 PRD"
}
```

---

### 步骤 2: 反向生成 PRD (PM Agent)

```bash
bash ~/.claude/logger.sh agent_start "PM 开始反向生成 PRD" "pm"
# → PM Agent: 从 doc/code-scan.md 反向生成现状 PRD
# → 写入 doc/prd.md
bash ~/.claude/logger.sh prd_generated "反向 PRD 从代码生成完成"
```

**任务要求**:
- 读取 General Agent 的分析结果
- 基于已实现的功能，反向写 PRD 的「已完成部分」
- 基于代码质量/测试覆盖，写出技术约束章节
- 标注「待确认」的部分（产品目标、商业指标等）
- 留出「本期新增功能」章节（供用户补充）

**PRD 结构** (反向 PRD 模板):
```markdown
# {项目名称} - 现状分析 PRD

## 技术栈信息
- FE: {框架/版本}
- BE: {框架/版本}
- 数据库: {类型/版本}

## 已实现功能
### User Auth (P0 | ✅ 完成 | 覆盖率: 85%)
- 说明: 从源码推导

### Dashboard (P0 | 🟡 测试覆盖不足 | 覆盖率: 45%)
- 说明: 从源码推导

## 待确认项
- [ ] 产品目标: ...
- [ ] 目标用户: ...
- [ ] 商业目标: ...

## 本期新增功能
{用户补充}

## 测试现状
- 总覆盖率: 68%
- 缺口: {未覆盖的模块}
```

**输出 JSON**:
```json
{
  "success": true,
  "agent": "PM",
  "action": "/onboard-generate-prd",
  "summary": "已反向生成现状 PRD，包含已实现功能分析和缺口识别",
  "output_files": ["doc/prd-current-state.md"],
  "issues": ["产品目标待确认", "商业指标待补充"]
}
```

---

### 步骤 3: 用户补充和批准

```
用户: approved  (或自行编辑后 approved)
→ 状态: PRD_APPROVED (跳过 review 阶段)
→ Orchestrator: 派发 Designer Agent 生成 Figma 提示词
```

**注意**: onboard 模式下 **跳过 BE/FE 审查**，因为代码已是生产级。

---

### 步骤 4: 生成 Figma 提示词 (Designer Agent)

同标准流程，基于现状 PRD 生成新功能的 Figma 提示词。

---

### 步骤 5: 设定切入点

用户可选择：

```bash
# 选项 A: 继续标准流程（新功能从设计开始）
user: figma ready {url}
→ 继续标准流程的 QA/FE/BE 环节

# 选项 B: 跳到实现 (已有高清设计)
user: /set-state IMPLEMENTATION
→ 直接进入 FE+BE 编码，跳过 QA 测试准备

# 选项 C: 只补充新功能文档 (不需要改代码)
user: /set-state DONE
→ 状态更新，可用于文档存档
```

---

## 关键设计点

### 1. 逆向分析的准确性
- **代码静态分析**: 从文件结构、导入语句推导模块依赖
- **文档优先**: 如果项目有现成 README/docs，优先从中提取信息
- **人工确认**: 「待确认」部分必须由用户明确

### 2. 跳过 review 的理由
- 代码已经过测试，说明 BE/FE 审查已隐含进行过
- 再次 review 会增加流程时间
- 新需求的 review 在 PRD_DRAFT 阶段由用户把控

### 3. 并行编码加速
- onboard 后可直接进入 IMPLEMENTATION
- 无需等 Figma 设计（可复用现有 UI 框架）

---

## 日志记录

所有 onboard 步骤通过 `~/.claude/logger.sh` 统一记录:

```bash
# 日志输出到项目级 doc/logs/ 目录
bash ~/.claude/logger.sh agent_start "开始 onboard: /my-project" "orchestrator"
bash ~/.claude/logger.sh agent_start "Codex 扫描代码结构" "be"
bash ~/.claude/logger.sh agent_done "扫描完成: 12 模块, 68% 覆盖率" "be"
bash ~/.claude/logger.sh agent_start "PM 反向生成 PRD" "pm"
bash ~/.claude/logger.sh prd_generated "PRD 生成完成 (5 issues flagged)"
bash ~/.claude/logger.sh import_done "切入状态: PRD_DRAFT" "pm"
bash ~/.claude/logger.sh state_change "IDEA → PRD_DRAFT" "orchestrator"
bash ~/.claude/logger.sh checkpoint "等待用户审阅 PRD" "orchestrator"
```

查看日志: `cat doc/logs/workflow.jsonl | python3 -m json.tool | tail -20`

---

## 与标准流程的关系

```
标准流程: IDEA → PRD_DRAFT → PRD_REVIEW → PRD_APPROVED → FIGMA_PROMPT → ...

Onboard 快进:
  ├─ IDEA (用户描述新功能)
  ├─ /onboard {project_dir}
  │  ├─ General: 分析代码
  │  ├─ PM: 反向生成 PRD
  │  └─ STATE: IDEA → PRD_DRAFT → (user approved) → PRD_APPROVED
  └─ 从 PRD_APPROVED 继续标准流程 (Designer → FE+BE → QA)
```

---

## 错误处理

| 错误 | 处理 |
|------|------|
| 项目目录不存在 | 提示路径错误，停止 onboard |
| 无法识别技术栈 | 要求用户手工输入 (tech_stack.txt) |
| PRD 分析失败 | 回退到用户手工编写，提供模板 |
| 并行任务超时 | 设置 30min 超时，提示用户 |
