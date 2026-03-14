---
description: Manually switch workflow state to a target phase
---

# /set-state — 手动状态切换工作流

> 用于已有项目直接跳转到工作流中的指定状态，无需从 IDEA 开始。

## 使用场景

### 场景 1: 已有产品修复 bug

```
用户: /set-state IMPLEMENTATION
选择: Bug fix 流程
→ 直接进入 QA 测试 → 修复 → 再测
```

### 场景 2: 已有高质量设计，跳过 PRD review

```
用户: /set-state DESIGN_READY
→ 直接进入 FE+BE 编码
→ 跳过 PRD_REVIEW 和 Figma 设计阶段
```

### 场景 3: 已有代码，只需 QA 测试

```
用户: /set-state QA_TESTING
→ 直接派发 QA Agent 准备测试
→ 跳过所有开发阶段
```

### 场景 4: 已完成，归档文档

```
用户: /set-state DONE
→ 归档当前项目
→ 更新文档和交付物清单
```

---

## 命令语法

```bash
claude /set-state {TARGET_STATE} [options]
```

### 参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `{TARGET_STATE}` | 目标状态 (见下表) | `IMPLEMENTATION` |
| `--prd {path}` | 指定 PRD 文档路径 | `--prd ./doc/prd.md` |
| `--figma {url}` | 指定 Figma 设计链接 | `--figma https://figma.com/...` |
| `--force` | 跳过验证，强制切换 | `--force` |
| `--reason {text}` | 状态切换原因（日志） | `--reason "bug fix in auth"` |

---

## 支持的目标状态及验证

### 状态 1: PRD_DRAFT
```bash
claude /set-state PRD_DRAFT --prd ./doc/prd.md
```
**前置检查**:
- ✓ PRD 文件存在且有效
- ✓ 不能从 DONE 切回（除非 --force）

**操作**:
- 设置 `current_state = PRD_DRAFT`
- 加载指定的 PRD 文件到 state.json
- 记录切换日志
- 等待用户输入 `approved` 继续

---

### 状态 2: PRD_APPROVED
```bash
claude /set-state PRD_APPROVED --prd ./doc/prd.md
```
**前置检查**:
- ✓ PRD 文件存在且有效
- ✓ PRD 内容检查（是否包含必要章节）

**自动操作**:
- 跳过 BE/FE 审查
- 记录日志: "User manually approved PRD (skipped review)"
- 状态推进: PRD_APPROVED

---

### 状态 3: FIGMA_PROMPT
```bash
claude /set-state FIGMA_PROMPT --prd ./doc/prd.md
```
**前置检查**:
- ✓ PRD 文件存在
- 可选: 检查是否需要重新生成提示词

**操作**:
- 可选派发 Designer: `/generate-figma-prompt` (交互确认)
- 停在 FIGMA_PROMPT 状态等待用户提供 Figma 链接

---

### 状态 4: DESIGN_READY
```bash
claude /set-state DESIGN_READY \
  --prd ./doc/prd.md \
  --figma https://figma.com/design/...
```
**前置检查**:
- ✓ PRD 文件有效
- ✓ Figma URL 可访问 (ping figma.com)

**自动操作**:
- 状态: DESIGN_READY
- 通知用户: "设计已就绪，准备生成测试计划"
- 可选自动派发 QA Agent: `/prepare-tests`

---

### 状态 5: IMPLEMENTATION
```bash
claude /set-state IMPLEMENTATION \
  --prd ./doc/prd.md \
  --figma https://figma.com/design/...
```
**前置检查**:
- ✓ PRD 文件有效
- ✓ Figma URL 有效

**自动操作**:
- 跳过 QA 测试准备
- 记录: "Skipped QA_TESTING phase, entering IMPLEMENTATION"
- 派发 FE+BE Agent 开始编码
- 通知用户: "FE+BE 已开始编码"

**特殊情况 — Bug Fix 流程**:
```bash
claude /set-state IMPLEMENTATION \
  --reason "bug fix: auth timeout issue" \
  --skip-tests
```
- 标记为 bug fix 模式
- 可选跳过测试准备
- QA Agent 会针对性地写 regression 测试

---

### 状态 6: QA_TESTING
```bash
claude /set-state QA_TESTING \
  --prd ./doc/prd.md \
  --reason "manual QA entry"
```
**前置检查**:
- ✓ PRD 文件有效
- 提示: 确认代码已完成实现

**自动操作**:
- 派发 QA Agent: `/prepare-ui-tests`
- QA 生成测试计划和用例
- 停在 QA_TESTING 等待 QA 反馈

---

### 状态 7: QA_PASSED
```bash
claude /set-state QA_PASSED --reason "all tests passed"
```
**前置检查**:
- ✓ 当前状态是 QA_TESTING

**操作**:
- 标记 QA 通过
- 推进: QA_TESTING → QA_PASSED → DONE
- 生成交付物总结

---

### 状态 8: DONE
```bash
claude /set-state DONE --reason "project archived"
```
**前置检查**:
- 无强制检查

**操作**:
- 更新项目状态为完成
- 生成项目交付物清单
- 记录最终日志
- 可选: 生成项目总结报告

---

## 验证规则

### 状态转换验证矩阵

```
当前状态  →  目标状态    | 需要验证 | 自动操作 | 说明
---------|-------------|---------|---------|--------
IDEA     →  PRD_DRAFT  | PRD 文件 | - | 正常流程
IDEA     →  IMPL       | 全部    | ⚠️ 多步跳跃，confirm | 需用户确认
PRD_DRAFT → IMPL       | PRD+Design | ✅ 自动跳过 review | 快进模式
ANY      →  QA_TESTING | PRD+Figma | ✅ 直接进入 QA | 快进
DONE     →  PRD_DRAFT  | - | ❌ 不允许回溯，除非 --force | 默认不许
```

### --force 标志

```bash
# 强制回溯（需谨慎）
claude /set-state PRD_DRAFT --prd ./doc/prd.md --force
# 日志: [WARN] State rollback from DONE to PRD_DRAFT (force=true)

# 强制跳跃多个状态
claude /set-state IMPLEMENTATION --force
# 日志: [WARN] Multi-stage jump: IDEA → IMPLEMENTATION (force=true)
```

---

## 交互流程

### 示例 1: 从零进入 IMPLEMENTATION

```
用户: /set-state IMPLEMENTATION --prd doc/prd.md --figma https://figma.com/...

Orchestrator:
  ✓ PRD 检查: doc/prd.md 包含必要章节
  ✓ Figma 检查: URL 有效

  ⚠️ 确认：将跳过以下阶段:
    - PRD_REVIEW (BE/FE 审查)
    - FIGMA_PROMPT (设计提示词)
    - TESTS_WRITTEN (测试准备)

  是否继续? (y/n)

用户: y

  派发 FE Agent (Gemini):
    "基于 PRD 和 Figma 设计实现前端..."

  派发 BE Agent (Codex):
    "基于 PRD 实现后端 API..."

  ✅ 并行编码已启动
  等待进度... (查看日志: ~/.claude/orchestrator/logs/current.log)
```

### 示例 2: Bug fix 模式

```
用户: /set-state IMPLEMENTATION \
  --reason "fix: login timeout bug" \
  --skip-tests

Orchestrator:
  ℹ️ 检测到 bug fix 模式

  派发 QA Agent:
    "准备 regression 测试用例:
     - 测试 login timeout 场景
     - 确认修复不破坏现有功能"

  派发 BE Agent (Codex):
    "修复 bug: login timeout..."

  ✅ Bug fix 流程已启动
```

---

## 日志记录

每次 `/set-state` 操作都记录到两处：

### 1. 主日志 (`~/.claude/orchestrator/logs/current.log`)

```
[2026-03-13 14:22:15] CMD: /set-state IMPLEMENTATION
[2026-03-13 14:22:15] FROM_STATE: IDEA
[2026-03-13 14:22:15] TARGET_STATE: IMPLEMENTATION
[2026-03-13 14:22:15] VALIDATION: prd=✓, figma=✓
[2026-03-13 14:22:15] SKIPPED_PHASES: PRD_REVIEW, FIGMA_PROMPT, TESTS_WRITTEN
[2026-03-13 14:22:16] STATE: IDEA → IMPLEMENTATION
[2026-03-13 14:22:17] AGENT:BE TASK:implementation (Codex)
[2026-03-13 14:22:17] AGENT:FE TASK:implementation (Gemini)
```

### 2. 状态历史 (`state.json.history`)

```json
{
  "timestamp": "2026-03-13T14:22:15Z",
  "event": "set-state",
  "from_state": "IDEA",
  "to_state": "IMPLEMENTATION",
  "reason": "",
  "skipped_phases": ["PRD_REVIEW", "FIGMA_PROMPT", "TESTS_WRITTEN"],
  "agent": "Orchestrator",
  "metadata": {
    "command": "/set-state IMPLEMENTATION --prd doc/prd.md --figma https://figma.com/...",
    "validation_passed": true
  }
}
```

---

## 错误处理

| 错误 | 处理 |
|------|------|
| 目标状态不存在 | 列出所有合法状态，要求重新输入 |
| PRD 文件无效 | 显示具体缺陷，建议修复或使用 --force |
| Figma URL 无效 | 尝试 ping，失败则要求用户验证 |
| 非法状态转换 | 提示转换规则，建议中间步骤 |
| 多步跳跃未确认 | 列出被跳过的阶段，要求用户确认 |

---

## 与标准流程的关系

```
标准流程:
  IDEA → PRD_DRAFT → PRD_REVIEW → PRD_APPROVED
       → FIGMA_PROMPT → DESIGN_READY → TESTS_WRITTEN
       → IMPLEMENTATION → QA_TESTING → QA_PASSED → DONE

/set-state 快进:
  /set-state PRD_DRAFT     → [用户编辑 PRD]
  /set-state IMPLEMENTATION → 直接跳到 IMPL (跳过中间 5 步)
  /set-state QA_TESTING    → 跳到 QA (跳过 FE+BE 开发)
  /set-state DONE          → 直接完成
```

---

## 最佳实践

### ✅ 推荐用法

```bash
# 场景 1: 已有高质量设计 + PRD
/set-state DESIGN_READY --prd ./prd.md --figma {url}

# 场景 2: Bug fix (跳过测试准备)
/set-state IMPLEMENTATION --reason "bug: auth timeout" --skip-tests

# 场景 3: 只需 QA 测试
/set-state QA_TESTING --prd ./prd.md
```

### ❌ 不推荐用法

```bash
# ❌ 跳过所有 review，直接进 IMPLEMENTATION（风险高）
/set-state IMPLEMENTATION  # 需要 --force + 多次确认

# ❌ 回溯状态而不修复原因
/set-state PRD_DRAFT --force  # 日志会标记 WARNING
```

