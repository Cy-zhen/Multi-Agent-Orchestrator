# Acceptance Recovery Matrix

这份矩阵用来回答一个核心问题：
在不同阶段、不同协作模式、不同中断方式下，当前流程会不会丢验收边界。

## 判定原则

- 项目记忆负责恢复长期上下文
- `doc/state.json` 和 `doc/logs/summary.md` 负责恢复运行态
- `doc/acceptance-contract.json` 负责恢复验收边界
- `doc/fe-self-check.md` / `doc/be-self-check.md` 负责恢复开发层自证
- `doc/test-plan.md` / `doc/test-report.md` / `doc/acceptance-screenshots/manifest.json` 负责恢复验证证据

## Case Matrix

| Case | 阶段 | 风险 | 现在的保护措施 | 结论 |
|---|---|---|---|---|
| 单 Agent 不中断 | 实现 / QA / 审查 | 低 | 当前会话上下文 + 项目记忆 + contract | 可用 |
| 单 Agent 中断 | 实现中 | 中 | 重进后先读项目记忆、state、logs、contract、自测报告 | 可用 |
| 多 Agent 不中断 | FE + BE + QA 连续协作 | 中 | dispatch templates 全部先读 contract | 可用 |
| 多 Agent 中断 | FE/BE 其中一个掉线，其他 Agent 接手 | 高 | orchestrator + contract + logs + progress artifacts | 可用，但要求 contract 及时更新 |
| Codex 中断，Antigravity 接手 | 实现或 QA 中途切换 | 高 | `~/.codex/AGENTS.md` + Antigravity skill + Claude live templates | 可用 |
| Gemini 中断，Claude/Antigravity 接手 | FE 实现中途切换 | 高 | `~/.gemini/GEMINI.md` + `~/.claude/CLAUDE.md` + FE template | 可用 |
| QA 中断后直接 resume | QA_TESTING | 高 | QA 必须先读 contract，再跑 tests/report/screenshots | 可用 |
| 视觉审查中断后 resume | VISUAL_REVIEW | 中 | visual-review template 先读 contract screenshot list | 可用 |
| scope 变化但 contract 未更新 | 任意阶段 | 很高 | 目前只能靠流程约束与 review 发现 | 仍有风险 |
| 项目未创建 contract | 早期阶段 | 高 | QA prepare-tests 会补建最小 contract | 可用，但第一次执行前仍有空窗 |

## 剩余风险

### 1. Scope changed but contract not updated

这是当前最大的真实风险。

表现：
- FE / BE 改了关键路径
- 但没有更新 `doc/acceptance-contract.json`
- 后续 QA 和视觉审查仍按旧边界验收

缓解：
- 已要求 FE / Codex direct-run 更新 contract
- 已要求 QA 从 contract 反查关键路径
- 仍建议在 code review 时顺手检查 contract revision 是否需要变化

### 2. 证据文件存在，但内容过时

表现：
- `manifest.json` 在
- 但截图没重拍，或者 test report 没引用当前 revision

缓解：
- QA / visual review 模板都已要求更新 evidence
- 已补 `python3 orchestrator/acceptance/consistency.py .` 做简单 revision consistency check

### 3. 开发层没做最小自测

表现：
- FE 代码能 build，但页面实际不能滚动 / 点击
- BE 代码能 build，但接口 happy path 或错误 path 没验证

缓解：
- FE 现在必须交 `doc/fe-self-check.md`
- BE 现在必须交 `doc/be-self-check.md`
- QA 模板会读取这两份自测结果，并检查是否与正式验收冲突
### 4. 项目早期尚未生成 contract

表现：
- 用户还在 PRD/设计早期
- 恢复时只能靠 PRD 和记忆

缓解：
- 现在要求 QA prepare-tests 阶段最迟必须补建 contract
- 如果后续你希望更早锁边界，可以把 contract 生成提前到 DESIGN_READY

## 建议的阶段策略

### PRD / 设计前

- 主要依赖项目记忆和 PRD
- 不强制要求完整 contract

### DESIGN_READY

- 开始有必要建立 `doc/acceptance-contract.json`
- 这里是最适合第一次锁定验收边界的时点

### TESTS_WRITTEN

- contract 应该已经可用
- test plan 应与 contract 对齐

### IMPLEMENTATION

- FE / BE 任何影响关键路径或状态的改动，都要更新 contract

### QA_TESTING / VISUAL_REVIEW

- contract 是第一输入，不是附属文档
- test report 和 screenshot manifest 是输出证据

## 结论

当前这套设计已经覆盖了：

- 单 Agent 不中断
- 单 Agent 中断
- 多 Agent 不中断
- 多 Agent 中断
- Codex 中断后由 Antigravity 接入
- Gemini 中断后由 Claude/Antigravity 接入

当前最大的残余问题不是“恢复不了”，而是：
**有人改了 scope 却没更新 contract。**

这已经不再是上下文恢复问题，而是执行纪律问题。
