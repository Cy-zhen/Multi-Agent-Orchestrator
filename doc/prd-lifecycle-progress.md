# PRD 文档生命周期改进 — 进展

## 状态: ✅ 已完成

## 变更摘要

### 问题
orchestrator 工作流中 PRD 在生成后就"冻结"，Stitch 原型设计的 UI/交互细节和开发后的实际实现都不会反哺到文档。

### 方案
新增 3 个状态节点 + 2 个 dispatch template，实现文档生命周期闭环。

## 具体改动

### 1. orchestrator.sh (状态机)

**next_state()** 新增路由:
- `FIGMA_PROMPT → DESIGN_SPEC → DESIGN_SPEC_REVIEW → DESIGN_READY`
- `QA_PASSED → PRODUCT_DOC → DONE`

**lookup_state()** 新增映射:
- `DESIGN_SPEC` → AUTO | PM | claude | pm-design-spec.txt
- `DESIGN_SPEC_REVIEW` → USER_GATE (用户审阅设计规格 + 更新后的 PRD)
- `PRODUCT_DOC` → AUTO | PM | claude | pm-product-doc.txt

**cmd_signal()** 新增:
- `FIGMA_PROMPT` 信号 → 转到 `DESIGN_SPEC`（而不是直接 DESIGN_READY）
- `DESIGN_SPEC_REVIEW` 信号处理 → approved 后继续自动链

### 2. 新增 Dispatch Templates

- `pm-design-spec.txt` — 从原型 + PRD 提取设计规格书
  - 产出: doc/design-spec.md
  - 同步更新 PRD (追加 UI 规格引用)
  - 输入: Stitch 链接/HTML + PRD

- `pm-product-doc.txt` — 开发完成后生成产品文档
  - 产出: doc/product-doc.md
  - 含 5 类 Mermaid 流程图 (用户旅程/页面导航/业务状态/数据流向/API序列)
  - 代码扫描驱动，不凭空编造
  - 同步更新 README.md + PRD 冻结标记

### 3. SKILL.md 更新
- 状态机图: 18 → 21 个状态
- 用户信号表: 4 → 5 个介入点
- Agent/CLI 路由表: PM 增加 2 个新模板

## 文档生命周期（改进后）

```
PRD v1.0 (IDEA 阶段生成)
    ↓
PRD v1.1 (DESIGN_SPEC 阶段, 追加 UI 规格引用)
    ↓ ⏸ 用户审阅
PRD v2.0 (PRODUCT_DOC 阶段, 冻结标记 → 指向 product-doc.md)
```

## 验证结果
- ✅ bash -n orchestrator.sh 语法检查通过
- ✅ 状态机路径 trace 正确
- ✅ 2 个新 template 文件已创建

## 副本同步

| 源文件 | 副本路径 | 状态 |
|--------|---------|------|
| `~/.claude/orchestrator.sh` | `claude/orchestrator.sh` | ✅ 已同步 |
| `orchestrator/SKILL.md` | `claude/orchestrator/SKILL.md` | ✅ 已同步 |
| `~/.claude/.../pm-design-spec.txt` | `claude/orchestrator/dispatch-templates/pm-design-spec.txt` | ✅ 已同步 |
| `~/.claude/.../pm-product-doc.txt` | `claude/orchestrator/dispatch-templates/pm-product-doc.txt` | ✅ 已同步 |
| `antigravity/skills/multi-agent-orchestrator/SKILL.md` | — (单独更新) | ✅ 已更新 |
| `claude/CLAUDE.md` | — (单独更新) | ✅ 已更新 |
| `antigravity/GEMINI.md` | — (单独更新) | ✅ 已更新 |
| `README.md` | — (根文件) | ✅ 已更新 |
