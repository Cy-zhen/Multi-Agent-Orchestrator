# Orchestrator 日志系统

> 完整的多 Agent 工作流追踪、审计和调试日志系统。
> 所有日志均存储在 `~/.claude/orchestrator/logs/` 目录。

---

## 日志目录结构

```
~/.claude/orchestrator/logs/
├── current.log              # 当前项目的实时日志（每个项目一份）
├── state-history.jsonl      # 状态转换历史（JSON Lines 格式）
├── agent-execution.jsonl    # Agent 执行详情
├── archive/
│   ├── 2026-03/
│   │   ├── project-a-20260313-142215.log
│   │   ├── project-b-20260314-093045.log
│   └── 2026-02/
│       └── ...
├── errors/
│   ├── 2026-03-13-141500-PRD_REVIEW-BE-failed.log
│   └── ...
└── README.md               # 日志文件说明
```

---

## 日志类型

### 1. Current Log (`current.log`)

**作用**: 当前项目实时执行日志

**位置**: `~/.claude/orchestrator/logs/{project_name}.log`

**级别**: TRACE, DEBUG, INFO, WARN, ERROR, FATAL

**格式**:
```
[TIMESTAMP] [LEVEL] [COMPONENT] [MESSAGE]
```

**示例**:
```
[2026-03-13 10:15:22] [INFO] [Orchestrator] Project initialized: my-app
[2026-03-13 10:15:23] [INFO] [StateManager] STATE: IDEA → PRD_DRAFT
[2026-03-13 10:15:24] [DEBUG] [Agent:PM] Task assigned: /generate-prd
[2026-03-13 10:15:45] [INFO] [Agent:PM] ✅ PRD generated: 2348 words
[2026-03-13 10:15:46] [DEBUG] [StateManager] Updating state.json
[2026-03-13 10:15:46] [INFO] [Orchestrator] Waiting for user: approved
```

---

### 2. State History (`state-history.jsonl`)

**作用**: 结构化状态转换历史（便于查询和分析）

**格式**: JSON Lines (每行一个 JSON 对象)

**示例**:
```json
{"timestamp":"2026-03-13T10:15:22Z","event":"init","project":"my-app","current_state":"IDEA","metadata":{"version":"1.0"}}
{"timestamp":"2026-03-13T10:15:23Z","event":"state_change","from":"IDEA","to":"PRD_DRAFT","agent":"PM","action":"/generate-prd","duration_ms":23000,"success":true}
{"timestamp":"2026-03-13T10:16:15Z","event":"user_input","signal":"approved","current_state":"PRD_DRAFT"}
{"timestamp":"2026-03-13T10:16:16Z","event":"state_change","from":"PRD_DRAFT","to":"PRD_REVIEW","agent":"Orchestrator","action":"auto_chain:be_review","duration_ms":1200}
```

**查询示例**:
```bash
# 查看项目全部状态历史
cat ~/.claude/orchestrator/logs/state-history.jsonl | grep '"project":"my-app"'

# 查看所有失败的转换
cat ~/.claude/orchestrator/logs/state-history.jsonl | grep '"success":false'

# 统计各阶段耗时
cat ~/.claude/orchestrator/logs/state-history.jsonl | jq 'select(.event=="state_change") | {from, to, duration_ms}'
```

---

### 3. Agent Execution (`agent-execution.jsonl`)

**作用**: 详细的 Agent 任务执行记录

**格式**: JSON Lines

**示例**:
```json
{"timestamp":"2026-03-13T10:15:24Z","agent":"PM","action":"/generate-prd","task_id":"pm-001","status":"started","cli":"claude"}
{"timestamp":"2026-03-13T10:15:45Z","agent":"PM","action":"/generate-prd","task_id":"pm-001","status":"completed","output_files":["doc/prd.md"],"duration_ms":21000,"success":true,"summary":"Generated PRD: my-app v1.0, 5 core features"}
{"timestamp":"2026-03-13T10:15:46Z","agent":"BE","action":"/review-prd","task_id":"be-001","status":"started","cli":"codex"}
{"timestamp":"2026-03-13T10:16:12Z","agent":"BE","action":"/review-prd","task_id":"be-001","status":"completed","approved":false,"issues":["API 响应格式不清晰","缺少错误处理规范"],"duration_ms":26000}
```

---

## 日志级别说明

| 级别 | 用途 | 示例 |
|------|------|------|
| **TRACE** | 最细粒度的调试信息 | 函数进入/退出，变量赋值 |
| **DEBUG** | 开发调试信息 | 文件读写，状态转换判断 |
| **INFO** | 正常流程信息 | Agent 启动/完成，状态变更 |
| **WARN** | 警告信息 | 字段缺失，非标准输出格式，超时提醒 |
| **ERROR** | 错误信息 | Agent 失败，文件不存在，网络错误 |
| **FATAL** | 致命错误 | 状态机崩溃，数据丢失 |

---

## 每个阶段的日志记录

### Phase: IDEA → PRD_DRAFT

```
[10:15:22] [INFO] [Orchestrator] 检测用户输入 (type=concept_description)
[10:15:22] [DEBUG] [StateManager] 当前状态: IDEA
[10:15:22] [INFO] [Orchestrator] 转换: IDEA → PRD_DRAFT
[10:15:23] [INFO] [Agent:PM] 分配任务: /generate-prd
[10:15:23] [DEBUG] [Agent:PM] CLI: claude -p "..." --output-format json
[10:15:24] [DEBUG] [Agent:PM] 需求拆解开始
[10:15:35] [DEBUG] [Agent:PM] 领域研究完成: 竞品分析 5 个
[10:15:45] [DEBUG] [Agent:PM] PRD 撰写完成
[10:15:45] [INFO] [Agent:PM] ✅ 任务完成: /generate-prd
[10:15:46] [INFO] [StateManager] 保存 PRD: doc/prd.md (2348 字)
[10:15:46] [INFO] [StateManager] 状态: PRD_DRAFT (等待用户审批)
[10:15:46] [INFO] [Orchestrator] 💬 用户提示: "请审阅 PRD 后回复 'approved' 继续"
```

### Phase: PRD_DRAFT → PRD_REVIEW (Auto-Chain: BE Review)

```
[10:16:16] [INFO] [Orchestrator] 检测用户信号: approved
[10:16:16] [INFO] [StateManager] Auto-Chain 启动: BE → FE → Designer
[10:16:16] [INFO] [StateManager] 状态: PRD_DRAFT → PRD_REVIEW
[10:16:17] [INFO] [Agent:BE] 分配任务: /review-prd (Phase 1)
[10:16:17] [DEBUG] [Agent:BE] CLI: codex exec --full-auto "..."
[10:16:22] [DEBUG] [Agent:BE] 检查 API 设计
[10:16:28] [DEBUG] [Agent:BE] 检查 数据库规范
[10:16:35] [DEBUG] [Agent:BE] 检查 性能约束
[10:16:42] [INFO] [Agent:BE] ✅ 评审完成
[10:16:43] [DEBUG] [Agent:BE] 评审结果: approved=false, issues=2
[10:16:43] [WARN] [Orchestrator] BE 发现问题，回退状态
[10:16:43] [INFO] [StateManager] 状态: PRD_REVIEW → PRD_DRAFT (issues flagged)
[10:16:44] [INFO] [Orchestrator] 💬 用户提示: "BE 发现 2 个问题，请查看 doc/review-be.md 后更新 PRD"
```

### Phase: IMPLEMENTATION (FE+BE 并行)

```
[10:20:15] [INFO] [Orchestrator] 派发并行任务: FE + BE
[10:20:15] [INFO] [Agent:FE] 分配任务: /figma-to-code (build)
[10:20:15] [INFO] [Agent:BE] 分配任务: /figma-to-code (build)
[10:20:16] [DEBUG] [Agent:FE] Task ID: fe-003, CLI: gemini --yolo -p "..."
[10:20:16] [DEBUG] [Agent:BE] Task ID: be-003, CLI: codex exec --full-auto "..."
[10:20:16] [INFO] [StateManager] 并行任务状态: {fe: running, be: running}
[10:20:46] [DEBUG] [ProgressMonitor] FE: 进度 30% (React 组件编写)
[10:20:46] [DEBUG] [ProgressMonitor] BE: 进度 40% (API 实现)
[10:21:16] [DEBUG] [ProgressMonitor] FE: 进度 70% (集成完成)
[10:21:46] [DEBUG] [ProgressMonitor] BE: 进度 80% (数据库迁移)
[10:22:15] [INFO] [Agent:FE] ✅ 前端实现完成: 8 files changed
[10:22:31] [INFO] [Agent:BE] ✅ 后端实现完成: 12 files changed
[10:22:31] [INFO] [StateManager] 并行任务完成: {fe: done, be: done}
[10:22:32] [INFO] [StateManager] 状态: IMPLEMENTATION → QA_TESTING
[10:22:32] [INFO] [Orchestrator] 派发 QA 准备 UI 测试
```

---

## 错误日志记录

### 位置: `~/.claude/orchestrator/logs/errors/{date}-{component}-{error_type}.log`

**示例**: `2026-03-13-102245-BE_REVIEW-TIMEOUT.log`

```
[2026-03-13 10:22:45] [ERROR] [Agent:BE] Task timeout after 30s
[2026-03-13 10:22:45] [DEBUG] Task ID: be-001
[2026-03-13 10:22:45] [DEBUG] Task: /review-prd
[2026-03-13 10:22:45] [DEBUG] CLI: codex exec --full-auto "..."
[2026-03-13 10:22:45] [DEBUG] Elapsed time: 30123ms
[2026-03-13 10:22:45] [ERROR] 原因: Codex 进程未响应
[2026-03-13 10:22:46] [INFO] [Orchestrator] 链停止: 等待用户干预
[2026-03-13 10:22:46] [INFO] [Orchestrator] 💬 建议: 检查 Codex 进程状态 / 重试 /review-prd / 查看详细错误: cat errors/2026-03-13-102245-BE_REVIEW-TIMEOUT.log
```

---

## 日志查询工具

### 1. 查看实时日志（跟踪当前项目）

```bash
# 持续输出（类似 tail -f）
tail -f ~/.claude/orchestrator/logs/current.log

# 最后 100 行
tail -100 ~/.claude/orchestrator/logs/current.log

# 搜索关键词
grep "error\|failed" ~/.claude/orchestrator/logs/current.log
```

### 2. 查询状态历史

```bash
# 查看项目全部历史
cat ~/.claude/orchestrator/logs/state-history.jsonl | jq 'select(.project=="my-app")'

# 查看某个时间段的操作
cat ~/.claude/orchestrator/logs/state-history.jsonl | jq 'select(.timestamp > "2026-03-13T10:00:00Z" and .timestamp < "2026-03-13T11:00:00Z")'

# 统计各阶段平均耗时
cat ~/.claude/orchestrator/logs/state-history.jsonl | jq -s 'group_by(.to) | map({state: .[0].to, avg_duration_ms: (map(.duration_ms) | add / length)})'
```

### 3. 查询 Agent 执行历史

```bash
# 查看 BE Agent 全部任务
cat ~/.claude/orchestrator/logs/agent-execution.jsonl | jq 'select(.agent=="BE")'

# 查看失败的任务
cat ~/.claude/orchestrator/logs/agent-execution.jsonl | jq 'select(.success==false)'

# 统计各 Agent 的执行时长
cat ~/.claude/orchestrator/logs/agent-execution.jsonl | jq -s 'group_by(.agent) | map({agent: .[0].agent, total_time_ms: (map(.duration_ms) | add), count: length})'
```

### 4. 生成项目报告

```bash
# 生成项目完整报告（当前日志中）
~/.claude/scripts/log-report.sh my-app

# 输出示例:
# Project: my-app
# Start: 2026-03-13 10:15:22
# End: 2026-03-13 14:35:18
# Duration: 4h 19m 56s
# Status: ✅ DONE
#
# Timeline:
#   IDEA → PRD_DRAFT: 23s (PM)
#   PRD_DRAFT → PRD_REVIEW: 26s (BE) + 31s (FE)
#   ...
#
# Agents:
#   PM: 1 task, 23s
#   BE: 3 tasks, 85s
#   FE: 3 tasks, 127s
#   QA: 1 task, 45s
```

---

## 日志文件大小管理

### 日志轮转策略

| 条件 | 行动 |
|------|------|
| 文件 > 10MB | 创建备份，重命名为 `current-backup-{timestamp}.log` |
| 文件 > 100MB | 归档到 `archive/{month}/` |
| 超过 30 天 | 移到 `archive/` |

---

## 隐私与安全

### 敏感信息过滤

日志系统**自动过滤**以下内容：
- API 密钥、Token
- 用户密码、认证信息
- 个人身份信息 (PII)
- 内部 IP 地址、内网域名

**过滤示例**:
```
[BEFORE] API_KEY=sk-1234567890abcdef
[AFTER]  API_KEY=***REDACTED***

[BEFORE] user_email=john@example.com
[AFTER]  user_email=***REDACTED***
```

### 日志权限

```
-rw------- (600)  ~/.claude/orchestrator/logs/current.log
-rw------- (600)  ~/.claude/orchestrator/logs/*.jsonl
```

仅所有者可读写，其他用户无权限。

---

## 日志启用/禁用

### 环境变量配置

```bash
# 启用详细日志
export CLAUDE_LOG_LEVEL=DEBUG

# 禁用日志输出到文件（仅 stdout）
export CLAUDE_LOG_FILE=none

# 只记录状态转换，不记录详细执行
export CLAUDE_LOG_SCOPE=state_only

# 禁用所有日志
export CLAUDE_LOG_LEVEL=OFF
```

### 项目级配置 (`~/.claude/settings.json`)

```json
{
  "logging": {
    "enabled": true,
    "level": "INFO",
    "format": "compact",
    "retention_days": 30,
    "archive_path": "~/.claude/orchestrator/logs/archive"
  }
}
```

---

## 日志标准与最佳实践

### ✅ 好的日志

```
[10:15:22] [INFO] [Agent:PM] ✅ PRD 生成完成: 2348 字，包含 5 核心功能
[10:15:22] [DEBUG] [StateManager] 状态转换: IDEA → PRD_DRAFT (duration=23000ms)
```

### ❌ 不好的日志

```
[10:15:22] [INFO] Done
[10:15:22] [DEBUG] Process running...
```

### 日志记录清单

- ✅ 包含时间戳（秒级精度）
- ✅ 标明日志级别
- ✅ 标明组件/Agent 名称
- ✅ 包含具体信息（不用模糊词如 "success"）
- ✅ 错误日志附带原因和建议
- ✅ 耗时操作记录持续时间
- ✅ 并行操作同时记录多条信息

