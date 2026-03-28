---
name: dispatch-agent
description: CLI 派发规范 — 根据 agent/cli 类型构造非交互命令并执行
---

# /dispatch-agent

> 根据 agent 角色和对应 CLI，构造非交互命令并执行。支持 claude / codex / gemini 三种 CLI。

## 执行前置条件

- 目标 CLI 已安装且认证正常
- 项目目录存在
- prompt 模板文件存在于 `~/.claude/orchestrator/dispatch-templates/`

---

## CLI 调用约定

| CLI | 命令格式 | 自动确认 | 输出控制 | 默认超时 | 工作目录 |
|-----|---------|---------|---------|---------|---------|
| claude | `claude -p "{prompt}"` | `--dangerously-skip-permissions` | `--output-format json` | 300s | 当前目录 |
| codex | `codex exec "{prompt}"` | `--full-auto` | 文本输出 | 600s | git repo |
| gemini | `gemini -p "{prompt}"` | `--yolo` | `-o json` | 300s | 当前目录 |

### CLI 特殊约束

| CLI | 约束 | 处理 |
|-----|------|------|
| codex | 必须在 git 仓库内 | 检查 `.git/`，无则 `git init` |
| codex | 不支持 JSON 输出格式 | prompt 中要求输出 JSON，手动解析 |
| gemini | OAuth 启动慢 | timeout ≥ 120s |
| gemini | 需要 `--yolo` | 否则挂起等待确认 |
| claude | 支持 `--add-dir` | 传入项目目录获取文件访问 |

---

## Prompt 构造规则

### 1. 加载模板

从 `~/.claude/orchestrator/dispatch-templates/{template_name}.txt` 读取。

### 2. 变量替换

| 变量 | 来源 | 说明 |
|------|------|------|
| `{{PROJECT_DIR}}` | 函数参数 | 项目根目录绝对路径 |
| `{{PRD_CONTENT}}` | `cat doc/prd.md` | PRD 全文内容 |
| `{{TEST_PLAN}}` | `cat doc/test-plan.md` | 测试计划内容 |
| `{{FE_PLAN}}` | `cat doc/fe-plan.md` | 前端实现计划 |
| `{{BE_PLAN}}` | `cat doc/be-plan.md` | 后端实现计划 |
| `{{FIGMA_URL}}` | `state.json → figma_url` | 设计稿 URL（Stitch 分享链接） |
| `{{FIGMA_PROMPTS}}` | `cat doc/stitch-prompts.md` | Stitch 设计提示词 |
| `{{REFLECTION}}` | `cat doc/reflection.md` | QA 反思文档 |
| `{{QA_RESULTS}}` | `cat doc/qa-results.json` | QA 测试结果 |
| `{{DESIGN_SYSTEM}}` | `cat docs/design/design-system.md` | 设计 Token（可选） |
| `{{STYLE_GUIDE}}` | `cat docs/design/stitch-style-guide.md` | 样式前缀（可选） |
| `{{DESIGN_CODE}}` | `cat doc/stitch-code.html` | Stitch Code to Clipboard HTML（可选） |

### 3. 尾部 JSON 指令

每个 prompt 末尾统一附加输出格式要求：

```
请以 JSON 格式输出结果:
{
  "success": true|false,
  "agent": "{AGENT_NAME}",
  "action": "{SKILL_NAME}",
  "summary": "简要描述",
  "output_files": [],
  "issues": [],
  "approved": true|false  // 仅 review 类
}
```

---

## 命令构造示例

### claude (PM / Designer / General)

```bash
claude -p "$(cat ~/.claude/orchestrator/dispatch-templates/designer-figma-prompt.txt \
  | sed "s|{{PRD_CONTENT}}|$(cat doc/prd.md)|g" \
  | sed "s|{{PROJECT_DIR}}|$(pwd)|g")" \
  --add-dir "$(pwd)" \
  --dangerously-skip-permissions \
  --output-format json
```

### codex (BE / QA)

```bash
cd "$PROJECT_DIR"
codex exec "$(cat ~/.claude/orchestrator/dispatch-templates/be-review-prd.txt \
  | sed "s|{{PRD_CONTENT}}|$(cat doc/prd.md)|g" \
  | sed "s|{{PROJECT_DIR}}|$(pwd)|g")" \
  --full-auto
```

### gemini (FE)

```bash
gemini -p "$(cat ~/.claude/orchestrator/dispatch-templates/fe-review-prd.txt \
  | sed "s|{{PRD_CONTENT}}|$(cat doc/prd.md)|g" \
  | sed "s|{{PROJECT_DIR}}|$(pwd)|g")" \
  --yolo \
  --include-directories "$(pwd)" \
  -o json
```

---

## 输出解析

### 解析流程

1. 捕获 CLI stdout + stderr
2. 在输出中搜索 JSON 块（`{` 开始到对应 `}` 结束）
3. 用 `jq` 验证 JSON 合法性
4. 检查必填字段: `success`, `agent`, `action`
5. 返回解析后的结构化结果

### 解析失败处理

- 无法找到 JSON → 将整个输出作为 `summary`，标记 `success: unknown`
- JSON 不合法 → 记录原始输出，报告解析错误
- 缺少必填字段 → 补充默认值，标记 `partial_parse: true`

---

## Prompt 模板文件清单

| 模板文件 | Agent | CLI | 技能 |
|---------|-------|-----|------|
| `pm-generate-prd.txt` | PM | claude | `/generate-prd` |
| `be-review-prd.txt` | BE | codex | `/review-prd` |
| `fe-review-prd.txt` | FE | gemini | `/review-prd` |
| `designer-figma-prompt.txt` | Designer | claude | `/generate-stitch-prompt` |
| `qa-prepare-tests.txt` | QA | codex | `/prepare-tests` |
| `fe-implementation.txt` | FE | gemini | `/figma-to-code build` |
| `be-implementation.txt` | BE | codex | `/figma-to-code build` |
| `qa-run-tests.txt` | QA | codex | `/run-tests` |
| `general-add-reflection.txt` | General | claude | `/add-reflection` |

---

## 并行派发

当 `skill == "/figma-to-code build"` 且 `agent == "fe+be"` 时：

1. 同时启动两个 CLI 进程（后台执行）
2. FE → `gemini -p ... --yolo`
3. BE → `codex exec ... --full-auto`
4. 使用 `wait` 等待两者完成
5. 收集两者的输出
6. 两者都成功 → 返回合并结果
7. 任一失败 → 返回失败结果 + 成功方的输出
