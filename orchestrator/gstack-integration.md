# Gstack 集成规范

> 本文档定义 Gstack skills 在 Orchestrator 工作流中的详细调用规范。

## 概述

[Gstack](https://github.com/garrytan/gstack) 是 Y Combinator CEO Garry Tan 的 Claude Code 工具集，包含 28 个 slash commands，模拟完整虚拟工程团队。

本项目从中选取 **9 个 skills** 作为**质量关卡**嵌入 IDEA → DONE 工作流。

## 安装位置

```
项目目录/.claude/skills/gstack/    ← gstack 源码
orchestrator/dispatch-templates/    ← 调度 prompt 模板
```

---

## Skills 调用规范

### 1. `/plan-ceo-review` — CEO 产品审查

| 项 | 值 |
|---|---|
| **状态** | `CEO_REVIEW` |
| **触发** | 用户 approved PRD 后自动触发 |
| **执行者** | Claude |
| **模板** | `ceo-review-prd.txt` |
| **输入** | `doc/prd.md` |
| **输出** | `doc/ceo-review.md` |
| **通过条件** | `approved: true` |
| **失败处理** | 回退到 `PRD_DRAFT`，附带 CEO 反馈 |

### 2. `/plan-design-review` — 设计审查

| 项 | 值 |
|---|---|
| **状态** | `DESIGN_PLAN_REVIEW` |
| **触发** | BE + FE 审查均通过后自动触发 |
| **执行者** | Claude |
| **模板** | `design-review-plan.txt` |
| **输入** | `doc/prd.md`, `doc/ceo-review.md` |
| **输出** | `doc/design-plan-review.md` |
| **通过条件** | `approved: true` (所有维度 ≥ 6 分) |
| **失败处理** | 回退到 `PRD_DRAFT`，附带设计反馈 |

### 3. `/review` — Staff Engineer 代码审查

| 项 | 值 |
|---|---|
| **状态** | `CODE_REVIEW` |
| **触发** | FE+BE 编码完成后自动触发 |
| **执行者** | Claude |
| **模板** | `staff-review-code.txt` |
| **输入** | `git diff main`, `doc/prd.md` |
| **输出** | `doc/code-review.md` |
| **通过条件** | 无 CRITICAL 级别发现 |
| **失败处理** | 回退到 `IMPLEMENTATION`，附带修复清单 |

### 4. `/cso` — 安全审计

| 项 | 值 |
|---|---|
| **状态** | `SECURITY_AUDIT` |
| **触发** | 代码审查通过后自动触发 |
| **执行者** | Claude |
| **模板** | `cso-audit.txt` |
| **输入** | 全部源代码 + 依赖文件 |
| **输出** | `doc/security-audit.md` |
| **通过条件** | 无 CRITICAL 级别漏洞 |
| **失败处理** | 回退到 `IMPLEMENTATION`，附带修复清单 |

### 5. `/investigate` — Root-cause 调试

| 项 | 值 |
|---|---|
| **状态** | `QA_FAILED` |
| **触发** | QA 测试失败时自动触发 |
| **执行者** | Claude |
| **模板** | `investigate-failure.txt` |
| **输入** | 失败的测试输出 |
| **输出** | `doc/investigation-report.md` |
| **循环限制** | 最多 3 次 |
| **超限处理** | 停止自动重试，等待用户干预 |

### 6. `/design-review` — 视觉审查

| 项 | 值 |
|---|---|
| **状态** | `VISUAL_REVIEW` |
| **触发** | QA 测试通过后自动触发 |
| **执行者** | Claude |
| **模板** | `design-review-visual.txt` |
| **输入** | 站点 URL |
| **输出** | `doc/visual-review.md` |
| **通过条件** | 修复完成或无发现 |
| **约束** | 风险 > 20% 时停止 |

### 7. `/ship` — 发布

| 项 | 值 |
|---|---|
| **状态** | `QA_PASSED` |
| **触发** | 视觉审查通过后自动触发 |
| **执行者** | Claude |
| **模板** | `ship-release.txt` |
| **输出** | `doc/ship-report.md` |
| **结果** | 创建 PR，状态转 `DONE` |

### 8. `/retro` — 回顾报告（可选）

| 项 | 值 |
|---|---|
| **触发** | 用户手动触发 `/retro` |
| **执行者** | Claude |
| **模板** | `retro-report.txt` |
| **输出** | `doc/retro-report.md` |

### 9. `/document-release` — 文档更新（可选）

| 项 | 值 |
|---|---|
| **触发** | 用户手动触发 `/document-release` |
| **执行者** | Claude |
| **模板** | `document-release.txt` |
| **输出** | `doc/docs-update-report.md` |

---

## 与现有 Agent 的协调规则

1. **Gstack 不替代 FE/BE/QA**：Gstack 是审查层，不写业务代码
2. **Gstack 全部走 Claude CLI**：不走 Codex 或 Gemini
3. **审查不通过 = 链停止**：回退到适当的前序状态
4. **输出格式统一**：所有 Gstack 输出遵循标准 JSON schema
5. **日志记录**：每次 Gstack 调用都写 orchestrator 日志
