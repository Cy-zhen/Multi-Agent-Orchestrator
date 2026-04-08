#!/usr/bin/env bash
# orchestrator.sh — Multi-Agent 编排器 CLI（自主运行版）
# 核心功能：自动链式执行 AUTO 节点，在 USER_GATE 停下等用户信号
#
# 用法: orchestrator.sh <command> [args]
#   init <project_dir>          — 初始化新项目
#   onboard <project_dir>       — 已有项目接入
#   auto-run [project_dir]      — 自动链式执行（核心命令）
#   signal <text> [project_dir] — 处理用户信号并继续
#   status [project_dir]        — 读取状态 + 渲染状态卡片
#   next [project_dir]          — 查表推荐下一步操作
#   transition <to> [project_dir] — 手动状态转换
#   dispatch <agent> <skill>    — 构造 CLI + 模板替换 + 执行
#   parallel <a1:s1> <a2:s2>    — 并行派发 + 轮询等待

set -euo pipefail

# ---------- 路径常量 ----------
ORCHESTRATOR_HOME="${HOME}/.claude/orchestrator"
AGENTS_HOME="${HOME}/.claude/agents"
TEMPLATES_DIR="${ORCHESTRATOR_HOME}/dispatch-templates"
LOGGER="${HOME}/.claude/logger.sh"
CHECKPOINT="${HOME}/.claude/checkpoint.sh"

# Codex/Gemini 超时时间（秒），防止无限挂起
CLI_TIMEOUT=${CLI_TIMEOUT:-600}

# 驱动模式: cli (默认, 调 claude -p) 或 antigravity (Claude 任务由调用方自己做)
DRIVER_MODE="cli"

# 项目级路径 — 可通过参数传入 PROJECT_DIR，或在项目目录下运行
PROJECT_DIR=""
STATE_FILE=""
LOG_DIR=""
FALLBACK_QUEUE_FILE=""
PROGRESS_FILE=""

# 设置项目路径
set_project_dir() {
  local dir="${1:-$(pwd)}"
  # 展开 ~
  dir="${dir/#\~/$HOME}"
  if [[ ! -d "$dir" ]]; then
    die "项目目录不存在: $dir"
  fi
  PROJECT_DIR="$(cd "$dir" && pwd)"
  STATE_FILE="${PROJECT_DIR}/doc/state.json"
  LOG_DIR="${PROJECT_DIR}/doc/logs"
  FALLBACK_QUEUE_FILE="${PROJECT_DIR}/doc/.manual-takeover-queue.json"
  PROGRESS_FILE="${PROJECT_DIR}/doc/progress.md"
}

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------- 工具函数 ----------

die() { echo -e "${RED}ERROR: $*${NC}" >&2; exit 1; }

# macOS 兼容的 timeout 实现 (用 perl 替代 coreutils timeout)
run_with_timeout() {
  local secs="$1"; shift
  local tmpout; tmpout=$(mktemp)
  local pid exit_code=0

  # 后台运行命令，输出 tee 到临时文件 + stderr
  ( "$@" ) > "$tmpout" 2>&1 &
  pid=$!

  # 后台倒计时
  (
    local elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
      sleep 5
      elapsed=$((elapsed + 5))
      if [[ $elapsed -ge $secs ]]; then
        echo -e "${RED}⏰ 超时 (${secs}s)，终止进程 PID=${pid}${NC}" >&2
        kill -TERM "$pid" 2>/dev/null || true
        sleep 2
        kill -9 "$pid" 2>/dev/null || true
        exit 1
      fi
      # 每 30 秒打印一次心跳
      if (( elapsed % 30 == 0 )); then
        echo -e "  ⏳ 已运行 ${elapsed}s / ${secs}s ..." >&2
      fi
    done
  ) &
  local timer_pid=$!

  wait "$pid" 2>/dev/null
  exit_code=$?

  # 清理计时器
  kill "$timer_pid" 2>/dev/null || true
  wait "$timer_pid" 2>/dev/null || true

  # 输出结果到 stdout
  cat "$tmpout"
  rm -f "$tmpout"
  return $exit_code
}

check_project_dir() {
  [[ -n "$STATE_FILE" ]] || die "未设置项目路径。请传入 PROJECT_DIR 参数。"
  [[ -f "$STATE_FILE" ]] || die "项目未初始化（缺少 ${STATE_FILE}）。请先运行: orchestrator.sh init <project_dir>"
}

ensure_progress_file() {
  [[ -n "$PROJECT_DIR" ]] || return 0
  [[ -n "$PROGRESS_FILE" ]] || PROGRESS_FILE="${PROJECT_DIR}/doc/progress.md"
  if [[ ! -f "$PROGRESS_FILE" ]]; then
    cat > "$PROGRESS_FILE" << 'EOF'
# 工作进度账本

> 作用:
> - 记录各 Agent 的最新开发现场，覆盖“Memory 尚未保存”与“会话/Agent 中断”之间的空档
> - 供 Codex / Gemini / Claude / Antigravity 在新会话接手前快速恢复上下文

## Current Snapshot

- 当前模式:
- 当前目标:
- 当前主状态:
- 当前负责人:
- 最新接手建议:
- 当前 blockers:
- 当前 open questions:
- 最后更新时间:

> 规则:
> - 这个区块是覆盖式摘要，保持短小
> - 新会话默认先读这里，不默认读取全部历史

## Agent Updates

### Entry Template

```md
#### 2026-04-07T00:00:00Z | FE | plan|build|fix
- Completed:
- Decisions:
- Files:
- Blockers:
- Handoff:
- Next:
```
EOF
  fi
}

get_state() {
  jq -r '.state // "UNKNOWN"' "$STATE_FILE"
}

get_field() {
  jq -r ".$1 // \"\"" "$STATE_FILE"
}

get_work_mode() {
  local mode
  mode=$(get_field "work_mode")
  if [[ -n "$mode" && "$mode" != "null" ]]; then
    echo "$mode"
    return 0
  fi

  if [[ -f "$PROGRESS_FILE" ]]; then
    python3 - "$PROGRESS_FILE" <<'PYEOF'
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    print("")
    raise SystemExit

for line in path.read_text(encoding="utf-8").splitlines():
    if line.startswith("- 当前模式:"):
        print(line.split(":", 1)[1].strip())
        break
else:
    print("")
PYEOF
    return 0
  fi

  echo ""
}

read_doc_file() {
  local rel="$1"
  cat "${PROJECT_DIR}/${rel}" 2>/dev/null || true
}

get_skills_root() {
  local executor="$1"
  case "$executor" in
    gemini)      echo "${HOME}/.gemini/skills";;
    codex)       echo "${HOME}/.codex/skills";;
    claude)      echo "${HOME}/.claude/skills";;
    antigravity) echo "${HOME}/.gemini/antigravity/skills";;
    *)           echo "${HOME}/.claude/skills";;
  esac
}

get_executor_chain() {
  local role="$1"
  local primary="$2"
  case "$role" in
    FE)
      if [[ "$DRIVER_MODE" == "antigravity" ]]; then
        echo "${primary} antigravity"
      else
        echo "${primary} claude"
      fi
      ;;
    BE|QA)
      if [[ "$DRIVER_MODE" == "antigravity" ]]; then
        echo "${primary} antigravity"
      else
        echo "${primary} claude"
      fi
      ;;
    *)
      if [[ "$DRIVER_MODE" == "antigravity" ]]; then
        echo "antigravity"
      else
        echo "${primary}"
      fi
      ;;
  esac
}

template_optional_placeholders_for() {
  local template="$1"
  case "$template" in
    fe-implementation.txt|be-implementation.txt)
      echo "FEATURE_NAME DESIGN_CODE REFLECTION"
      ;;
    be-review-prd.txt|fe-review-prd.txt)
      echo ""
      ;;
    *)
      echo "FEATURE_NAME DESIGN_CODE REFLECTION FE_PLAN BE_PLAN TEST_PLAN FAILURE_CONTEXT SITE_URL TIME_RANGE"
      ;;
  esac
}

render_template_file() {
  local template_path="$1"
  local role="$2"
  local executor="$3"

  [[ -f "$template_path" ]] || die "模板不存在: ${template_path}"

  local prompt
  prompt=$(cat "$template_path")

  local feature_name figma_url fe_plan be_plan reflection design_code test_plan failure_context site_url time_range skills_root
  feature_name=$(jq -r '.feature_name // .project // empty' "$STATE_FILE" 2>/dev/null || true)
  [[ -z "$feature_name" ]] && feature_name=$(basename "$PROJECT_DIR")
  figma_url=$(get_field figma_url)
  fe_plan=$(read_doc_file "doc/fe-plan.md")
  be_plan=$(read_doc_file "doc/be-plan.md")
  reflection=$(read_doc_file "doc/reflection.md")
  design_code=$(read_doc_file "doc/stitch-code.html")
  test_plan=$(read_doc_file "doc/tests/test-plan.md")
  [[ -z "$test_plan" ]] && test_plan=$(read_doc_file "doc/test-plan.md")
  failure_context=$(read_doc_file "doc/qa-report.md")
  site_url=$(get_field site_url)
  time_range=$(get_field time_range)
  skills_root=$(get_skills_root "$executor")

  prompt="${prompt//\{\{PROJECT_DIR\}\}/$PROJECT_DIR}"
  prompt="${prompt//\{\{PRD_CONTENT\}\}/$(read_doc_file "doc/prd.md")}"
  prompt="${prompt//\{\{FIGMA_URL\}\}/$figma_url}"
  prompt="${prompt//\{\{TEST_PLAN\}\}/$test_plan}"
  prompt="${prompt//\{\{FE_PLAN\}\}/$fe_plan}"
  prompt="${prompt//\{\{BE_PLAN\}\}/$be_plan}"
  prompt="${prompt//\{\{FAILURE_CONTEXT\}\}/$failure_context}"
  prompt="${prompt//\{\{SITE_URL\}\}/$site_url}"
  prompt="${prompt//\{\{TIME_RANGE\}\}/$time_range}"
  prompt="${prompt//\{\{FEATURE_NAME\}\}/$feature_name}"
  prompt="${prompt//\{\{DESIGN_CODE\}\}/$design_code}"
  prompt="${prompt//\{\{REFLECTION\}\}/$reflection}"
  prompt="${prompt//\{\{SKILLS_ROOT\}\}/$skills_root}"
  prompt="${prompt//\{\{SKILLS_INJECTION\}\}/优先参考 ${skills_root} 中与当前角色(${role})相关的 skills；如果该执行器目录下没有对应 skill，再按项目约束继续执行。}"

  local optional
  for optional in $(template_optional_placeholders_for "$(basename "$template_path")"); do
    prompt="${prompt//\{\{${optional}\}\}/}"
  done

  local unresolved
  unresolved=$(printf "%s" "$prompt" | grep -o '{{[A-Z_][A-Z_0-9]*}}' | sort -u || true)
  if [[ -n "$unresolved" ]]; then
    echo -e "${RED}模板变量缺失:$(printf '\n%s' "$unresolved")${NC}" >&2
    return 1
  fi

  printf "%s" "$prompt"
}

queue_manual_takeover() {
  local role="$1"
  local action="$2"
  local template="$3"
  local executor="$4"
  local fallback_from="$5"
  local next_state="$6"
  local prompt="$7"

  local prompt_file="${PROJECT_DIR}/doc/.queued-${role,,}-task.md"
  printf "%s" "$prompt" > "$prompt_file"

  cat > "$FALLBACK_QUEUE_FILE" << EOF
{
  "role": "${role}",
  "action": "${action}",
  "template": "${template}",
  "executor": "${executor}",
  "fallback_from": "${fallback_from}",
  "next_state_on_success": "${next_state}",
  "prompt_file": "${prompt_file}"
}
EOF
}

emit_queued_manual_takeover_if_any() {
  [[ -f "$FALLBACK_QUEUE_FILE" ]] || return 1

  local role action template executor fallback_from next_state prompt_file prompt
  role=$(jq -r '.role' "$FALLBACK_QUEUE_FILE")
  action=$(jq -r '.action' "$FALLBACK_QUEUE_FILE")
  template=$(jq -r '.template' "$FALLBACK_QUEUE_FILE")
  executor=$(jq -r '.executor' "$FALLBACK_QUEUE_FILE")
  fallback_from=$(jq -r '.fallback_from // ""' "$FALLBACK_QUEUE_FILE")
  next_state=$(jq -r '.next_state_on_success // ""' "$FALLBACK_QUEUE_FILE")
  prompt_file=$(jq -r '.prompt_file' "$FALLBACK_QUEUE_FILE")
  prompt=$(cat "$prompt_file")

  rm -f "$FALLBACK_QUEUE_FILE" "$prompt_file"
  _emit_claude_task_pending "$prompt" "$role" "$(get_state)" "$action" "$template" "$executor" "$fallback_from" "$next_state"
  return 0
}

set_state() {
  local new_state="$1"
  local action="${2:-manual}"
  local details="${3:-}"
  local old_state
  old_state=$(get_state)

  # 写入 state.json (使用 chain_log)
  local tmp
  tmp=$(mktemp)
  jq --arg s "$new_state" \
     --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     --arg from "$old_state" \
     --arg act "$action" \
     --arg det "$details" \
    '.state = $s | .chain_log += [{"from": $from, "to": $s, "ts": $t, "action": $act, "details": $det}]' \
    "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"

  # 日志
  if [[ -x "$LOGGER" ]]; then
    bash "$LOGGER" state_change "$old_state → $new_state" "orchestrator" 2>/dev/null || true
  fi

  echo -e "${GREEN}状态转换: ${old_state} → ${new_state}${NC}"
}

# 成功执行后的下一状态映射
next_state() {
  local state="$1"
  local approved="${2:-true}"  # CLI 输出中的 approved 字段
  case "$state" in
    IDEA)           echo "PRD_DRAFT";;
    PRD_DRAFT)      echo "CEO_REVIEW";;
    CEO_REVIEW)
      [[ "$approved" == "true" ]] && echo "PRD_REVIEW" || echo "PRD_DRAFT";;
    PRD_REVIEW)
      [[ "$approved" == "true" ]] && echo "BE_APPROVED" || echo "PRD_DRAFT";;
    BE_APPROVED)
      [[ "$approved" == "true" ]] && echo "DESIGN_PLAN_REVIEW" || echo "PRD_DRAFT";;
    DESIGN_PLAN_REVIEW)
      [[ "$approved" == "true" ]] && echo "PRD_APPROVED" || echo "PRD_DRAFT";;
    PRD_APPROVED)   echo "FIGMA_PROMPT";;
    FIGMA_PROMPT)   echo "DESIGN_SPEC";;
    DESIGN_SPEC)    echo "DESIGN_SPEC_REVIEW";;
    DESIGN_SPEC_REVIEW) echo "DESIGN_READY";;
    DESIGN_READY)   echo "TESTS_WRITTEN";;
    TESTS_WRITTEN)  echo "IMPLEMENTATION";;
    IMPLEMENTATION) echo "CODE_REVIEW";;
    CODE_REVIEW)
      [[ "$approved" == "true" ]] && echo "SECURITY_AUDIT" || echo "IMPLEMENTATION";;
    SECURITY_AUDIT)
      [[ "$approved" == "true" ]] && echo "QA_TESTING" || echo "IMPLEMENTATION";;
    QA_TESTING)     echo "VISUAL_REVIEW";;
    VISUAL_REVIEW)  echo "QA_PASSED";;
    QA_PASSED)      echo "PRODUCT_DOC";;
    PRODUCT_DOC)    echo "DONE";;
    QA_FAILED)      echo "IMPLEMENTATION";;
    *)              echo "UNKNOWN";;
  esac
}

# ---------- 转换表查询 ----------
# 返回: node_type|agent|cli|skill|prompt_template
lookup_state() {
  local state="$1"
  case "$state" in
    IDEA)              echo "INTERACTIVE|PM|claude|/generate-prd|pm-generate-prd.txt";;
    PRD_DRAFT)         echo "USER_GATE|-|-|-|-";;
    CEO_REVIEW)        echo "AUTO|Gstack|claude|/plan-ceo-review|ceo-review-prd.txt";;
    PRD_REVIEW)        echo "AUTO|BE|codex|/review-prd|be-review-prd.txt";;
    BE_APPROVED)       echo "AUTO|FE|gemini|/review-prd|fe-review-prd.txt";;
    DESIGN_PLAN_REVIEW) echo "AUTO|Gstack|claude|/plan-design-review|design-review-plan.txt";;
    PRD_APPROVED)      echo "AUTO|Designer|claude|/generate-figma-prompt|designer-figma-prompt.txt";;
    FIGMA_PROMPT)      echo "USER_GATE|-|-|-|-";;
    DESIGN_SPEC)       echo "AUTO|PM|claude|/extract-design-spec|pm-design-spec.txt";;
    DESIGN_SPEC_REVIEW) echo "USER_GATE|-|-|-|-";;
    DESIGN_READY)      echo "AUTO|QA|codex|/prepare-tests|qa-prepare-tests.txt";;
    TESTS_WRITTEN)     echo "PLAN_GATE|-|-|-|-";;
    IMPLEMENTATION)    echo "AUTO|FE+BE|gemini+codex|/figma-to-code|fe-implementation.txt";;
    CODE_REVIEW)       echo "AUTO|Gstack|claude|/review|staff-review-code.txt";;
    SECURITY_AUDIT)    echo "AUTO|Gstack|claude|/cso|cso-audit.txt";;
    QA_TESTING)        echo "AUTO|QA|codex|/run-tests|qa-run-tests.txt";;
    VISUAL_REVIEW)     echo "AUTO|Gstack|claude|/design-review|design-review-visual.txt";;
    QA_PASSED)         echo "AUTO|Gstack|claude|/ship|ship-release.txt";;
    PRODUCT_DOC)       echo "AUTO|PM|claude|/generate-product-doc|pm-product-doc.txt";;
    QA_FAILED)         echo "AUTO|Gstack|claude|/investigate|investigate-failure.txt";;
    DONE)              echo "TERMINAL|-|-|-|-";;
    *)                 echo "UNKNOWN|-|-|-|-";;
  esac
}

lookup_node_type() {
  local state="$1"
  local info
  info=$(lookup_state "$state")
  IFS='|' read -r node_type _ <<< "$info"
  echo "$node_type"
}

# ---------- COMMAND: status ----------
cmd_status() {
  check_project_dir
  ensure_progress_file
  local state
  state=$(get_state)
  local info
  info=$(lookup_state "$state")
  local node_type agent cli skill template
  IFS='|' read -r node_type agent cli skill template <<< "$info"

  local reflection_count
  reflection_count=$(get_field "reflection_count")
  [[ -z "$reflection_count" ]] && reflection_count=0
  local work_mode
  work_mode=$(get_work_mode)
  [[ -z "$work_mode" ]] && work_mode="未设置"

  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║   Multi-Agent Orchestrator Status    ║${NC}"
  echo -e "${BOLD}╠══════════════════════════════════════╣${NC}"
  echo -e "║ 状态:       ${CYAN}${state}${NC}"
  echo -e "║ 节点类型:   ${YELLOW}${node_type}${NC}"
  echo -e "║ 等待 Agent: ${BLUE}${agent}${NC}"
  echo -e "║ 主执行器:   ${cli}"
  echo -e "║ 动作:       ${skill}"
  echo -e "║ 模板:       ${template}"
  echo -e "║ 工作模式:   ${work_mode}"
  echo -e "║ 调查次数:   ${reflection_count}/3"
  echo -e "║ 项目目录:   ${PROJECT_DIR}"
  echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
  echo ""

  # 状态提示
  case "$node_type" in
    AUTO)        echo -e "${GREEN}→ 可自动执行。运行: orchestrator.sh dispatch ${agent} ${skill}${NC}";;
    USER_GATE)   echo -e "${YELLOW}→ 等待用户操作${NC}";;
    PLAN_GATE)   echo -e "${YELLOW}→ 等待方案审批${NC}";;
    INTERACTIVE) echo -e "${YELLOW}→ 需要用户交互提供信息${NC}";;
    TERMINAL)    echo -e "${GREEN}→ 工作流已完成 ✓${NC}";;
  esac

  # ── 执行历史（最近 8 条）──────────────────────────
  local log_file="${PROJECT_DIR}/doc/logs/workflow.jsonl"
  if [[ -f "$log_file" ]]; then
    echo ""
    echo -e "${BOLD}── 执行历史 ──${NC}"
    tail -8 "$log_file" | while IFS= read -r line; do
      local ts ev ag msg icon
      ts=$(echo "$line" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('ts','')[:16].replace('T',' '))" 2>/dev/null || echo '?')
      ev=$(echo "$line" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('event',''))" 2>/dev/null || echo '?')
      ag=$(echo "$line" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('agent',''))" 2>/dev/null || echo '?')
      msg=$(echo "$line" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('message',''))" 2>/dev/null || echo '?')
      case "$ev" in
        agent_start)  icon="🚀";;
        agent_done)   icon="✅";;
        state_change) icon="🔄";;
        *error*|*fail*) icon="❌";;
        *)            icon="ℹ️";;
      esac
      echo "  ${icon} ${ts} [${ag}] ${msg}"
    done
  fi

  if [[ -f "$PROGRESS_FILE" ]]; then
    echo ""
    echo -e "${BOLD}── 工作进度账本 ──${NC}"
    python3 - "$PROGRESS_FILE" <<'PYEOF'
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
snapshot = []
in_snapshot = False
for line in lines:
    if line.startswith("## Current Snapshot"):
        in_snapshot = True
        continue
    if in_snapshot and line.startswith("## "):
        break
    if in_snapshot:
        snapshot.append(line)

snapshot = [line for line in snapshot if line.strip()]
if not snapshot:
    print("  暂无 Current Snapshot，建议先更新 doc/progress.md")
else:
    print("  [Current Snapshot]")
    for line in snapshot:
        print(f"  {line}")
PYEOF
    echo "  完整账本: doc/progress.md"
  fi

  # ── Checkpoint（如有活跃链）──────────────────────
  if [[ -f "${PROJECT_DIR}/doc/checkpoint.json" ]]; then
    echo ""
    echo -e "${BOLD}── 活跃执行链 ──${NC}"
    cd "$PROJECT_DIR" && bash "$CHECKPOINT" read_status 2>/dev/null || true
  fi
}

# ---------- COMMAND: next ----------
cmd_next() {
  check_project_dir
  local state
  state=$(get_state)
  local info
  info=$(lookup_state "$state")
  local node_type agent cli skill template
  IFS='|' read -r node_type agent cli skill template <<< "$info"

  # 输出 JSON 供 Claude 解析
  cat <<EOF
{
  "current_state": "${state}",
  "node_type": "${node_type}",
  "agent": "${agent}",
  "cli": "${cli}",
  "skill": "${skill}",
  "prompt_template": "${template}",
  "is_auto": $([ "$node_type" = "AUTO" ] && echo "true" || echo "false"),
  "is_gate": $(echo "$node_type" | grep -q "GATE" && echo "true" || echo "false"),
  "recommended_action": "$(
    case "$node_type" in
      AUTO)        echo "dispatch ${agent} ${skill}";;
      USER_GATE)   echo "waiting for user signal";;
      PLAN_GATE)   echo "waiting for plan approval";;
      INTERACTIVE) echo "waiting for user input";;
      TERMINAL)    echo "workflow complete";;
      *)           echo "unknown";;
    esac
  )"
}
EOF
}

# ---------- COMMAND: transition ----------
cmd_transition() {
  local to_state="${1:-}"
  [[ -z "$to_state" ]] && die "用法: orchestrator.sh transition <目标状态>"
  check_project_dir
  set_state "$to_state"
}

# ---------- Role / Executor 执行函数 ----------
# run_with_executor <executor> <prompt> <role> [state] [action] [template] [fallback_from] [next_state]
# 返回: 0=成功, 1=失败, 99=写入 CLAUDE_TASK_PENDING
FALLBACK_OUTPUT=""
run_with_executor() {
  local executor="$1"
  local prompt="$2"
  local role="${3:-unknown}"
  local state="${4:-}"
  local action="${5:-}"
  local template="${6:-}"
  local fallback_from="${7:-}"
  local next_state="${8:-}"

  local output=""
  local exit_code=0

  case "$executor" in
    antigravity)
      _emit_claude_task_pending "$prompt" "$role" "$state" "$action" "$template" "$executor" "$fallback_from" "$next_state"
      return 99
      ;;
    claude)
      if [[ "$DRIVER_MODE" == "antigravity" ]]; then
        _emit_claude_task_pending "$prompt" "$role" "$state" "$action" "$template" "antigravity" "${fallback_from:-claude}" "$next_state"
        return 99
      fi
      echo -e "${YELLOW}执行 Claude CLI...${NC}"
      output=$(claude -p "$prompt" --output-format json 2>&1) || exit_code=$?
      ;;
    codex)
      if which codex >/dev/null 2>&1; then
        echo -e "${YELLOW}执行 Codex CLI (timeout=${CLI_TIMEOUT}s)...${NC}"
        output=$(run_with_timeout "$CLI_TIMEOUT" codex exec --full-auto -C "$PROJECT_DIR" "$prompt" < /dev/null) || exit_code=$?
        if [[ $exit_code -eq 137 || $exit_code -eq 143 ]]; then
          echo -e "${RED}✗ Codex 超时被终止${NC}"
        fi
      else
        echo -e "${YELLOW}Codex CLI 不可用${NC}"
        exit_code=1
      fi
      ;;
    gemini)
      if which gemini >/dev/null 2>&1; then
        echo -e "${YELLOW}执行 Gemini CLI (timeout=${CLI_TIMEOUT}s)...${NC}"
        output=$(run_with_timeout "$CLI_TIMEOUT" gemini -p "$prompt" --yolo < /dev/null) || exit_code=$?
        if [[ $exit_code -eq 137 || $exit_code -eq 143 ]]; then
          echo -e "${RED}✗ Gemini 超时被终止${NC}"
        fi
      else
        echo -e "${YELLOW}Gemini CLI 不可用${NC}"
        exit_code=1
      fi
      ;;
    *)
      echo -e "${RED}未知执行器: ${executor}${NC}"
      exit_code=1
      ;;
  esac

  if [[ $exit_code -eq 0 ]]; then
    echo -e "${GREEN}✓ ${executor} 执行成功${NC}"
    FALLBACK_OUTPUT="$output"
    return 0
  fi

  echo -e "${YELLOW}⚠ ${executor} 执行失败 (exit: ${exit_code})${NC}"
  if [[ -x "$LOGGER" ]]; then
    bash "$LOGGER" warn "role=${role} executor=${executor} 失败(exit=${exit_code})" "orchestrator" 2>/dev/null || true
  fi

  FALLBACK_OUTPUT="$output"
  return $exit_code
}

# run_role_with_fallback <role> <primary_executor> <prompt> [state] [action] [template] [next_state]
run_role_with_fallback() {
  local role="$1"
  local primary_executor="$2"
  local prompt="$3"
  local state="${4:-}"
  local action="${5:-}"
  local template="${6:-}"
  local next_state="${7:-}"
  local output=""
  local exit_code=1
  local fallback_from=""
  local executor

  for executor in $(get_executor_chain "$role" "$primary_executor"); do
    run_with_executor "$executor" "$prompt" "$role" "$state" "$action" "$template" "$fallback_from" "$next_state"
    exit_code=$?
    if [[ $exit_code -eq 0 || $exit_code -eq 99 ]]; then
      return $exit_code
    fi
    output="$FALLBACK_OUTPUT"
    fallback_from="$executor"
    echo -e "${YELLOW}→ 继续回退: role=${role} ${executor} -> 下一个执行器${NC}"
  done

  FALLBACK_OUTPUT="$output"
  return $exit_code
}

# 写 CLAUDE_TASK_PENDING 文件 (内部辅助函数)
_emit_claude_task_pending() {
  local prompt="$1"
  local role="${2:-}"
  local state="${3:-}"
  local action="${4:-}"
  local template="${5:-}"
  local executor="${6:-antigravity}"
  local fallback_from="${7:-}"
  local nxt="${8:-}"
  [[ -z "$nxt" ]] && nxt=$(next_state "$state" true 2>/dev/null || echo "")
  local next_node_type="UNKNOWN"
  [[ -n "$nxt" ]] && next_node_type=$(lookup_node_type "$nxt")

  local task_file="${PROJECT_DIR}/doc/.claude-task.md"
  echo "$prompt" > "$task_file"

  cat > "${PROJECT_DIR}/doc/.claude-task-meta.json" << META
{
  "state": "${state}",
  "agent": "${role}",
  "role": "${role}",
  "skill": "${action}",
  "action": "${action}",
  "template": "${template}",
  "executor": "${executor}",
  "fallback_from": "${fallback_from}",
  "next_node_type": "${next_node_type}",
  "next_state": "${nxt}",
  "next_state_on_success": "${nxt}"
}
META

  echo ""
  echo -e "${YELLOW}══════════════════════════════════════${NC}"
  echo -e "${YELLOW}  CLAUDE_TASK_PENDING${NC}"
  echo -e "${YELLOW}══════════════════════════════════════${NC}"
  echo -e "Role: ${role} | Action: ${action} | Executor: ${executor}"
  [[ -n "$fallback_from" ]] && echo -e "Fallback From: ${fallback_from}"
  echo -e "Prompt 已写入: ${task_file}"
  echo -e "下一状态: ${nxt} (${next_node_type})"
  echo -e ""
  echo -e "请你以 ${role} 角色执行以下任务:"
  echo -e "1. 读取 ${task_file} 中的 prompt"
  echo -e "2. 读取 ${PROJECT_DIR}/doc/.claude-task-meta.json"
  echo -e "3. 按照 prompt 的要求执行任务"
  echo -e "4. 完成后先运行: orchestrator.sh --ag transition ${nxt} ${PROJECT_DIR}"
  if [[ "$next_node_type" == "AUTO" ]]; then
    echo -e "5. 再运行: orchestrator.sh --ag auto-run ${PROJECT_DIR}"
  else
    echo -e "5. 不要继续 auto-run；改为运行: orchestrator.sh --ag status ${PROJECT_DIR}"
    echo -e "6. 等待用户在 ${nxt} 阶段显式给出 gate 信号"
  fi
  echo -e "${YELLOW}══════════════════════════════════════${NC}"
}

# ---------- COMMAND: dispatch ----------
cmd_dispatch() {
  local agent="${1:-}"
  local skill="${2:-}"
  [[ -z "$agent" || -z "$skill" ]] && die "用法: orchestrator.sh dispatch <agent> <skill>"
  check_project_dir

  # 查找模板
  local state
  state=$(get_state)
  local info
  info=$(lookup_state "$state")
  local _nt _ag cli _sk template
  IFS='|' read -r _nt _ag cli _sk template <<< "$info"

  local template_path="${TEMPLATES_DIR}/${template}"
  if [[ ! -f "$template_path" ]]; then
    die "模板不存在: ${template_path}"
  fi

  local prompt
  prompt=$(render_template_file "$template_path" "$agent" "$cli") || return 1

  echo -e "${BLUE}派发 Role: ${agent} | Action: ${skill} | Primary Executor: ${cli}${NC}"
  echo -e "${CYAN}模板: ${template}${NC}"
  echo ""

  # 执行（带回退）
  cd "$PROJECT_DIR"
  run_role_with_fallback "$agent" "$cli" "$prompt" "$state" "$skill" "$template"
  local exit_code=$?

  if [[ $exit_code -eq 99 ]]; then
    # CLAUDE_TASK_PENDING
    return 0
  fi

  # 输出
  if [[ $exit_code -eq 0 ]]; then
    echo -e "${GREEN}✓ 执行成功${NC}"
  else
    echo -e "${RED}✗ 执行失败 (exit code: ${exit_code})${NC}"
  fi
  echo "$FALLBACK_OUTPUT"

  # 日志
  if [[ -x "$LOGGER" ]]; then
    "$LOGGER" agent_dispatch "role=${agent} action=${skill} primary_executor=${cli} exit=${exit_code}"
  fi

  return $exit_code
}

# ---------- COMMAND: parallel ----------
cmd_parallel() {
  [[ $# -lt 2 ]] && die "用法: orchestrator.sh parallel <agent1:skill1> <agent2:skill2> [...]"
  check_project_dir

  echo -e "${BLUE}并行派发 $# 个任务...${NC}"

  local pids=()
  local tasks=()
  local tmpdir
  tmpdir=$(mktemp -d)

  for task in "$@"; do
    local agent skill
    IFS=':' read -r agent skill <<< "$task"
    tasks+=("$task")

    # 后台执行
    (
      cmd_dispatch "$agent" "$skill" > "${tmpdir}/${agent}_${skill}.log" 2>&1
      echo $? > "${tmpdir}/${agent}_${skill}.exit"
    ) &
    pids+=($!)
    echo -e "  启动: ${agent}:${skill} (PID: ${pids[-1]})"
  done

  echo -e "${YELLOW}等待所有任务完成...${NC}"

  local failed=0
  for i in "${!pids[@]}"; do
    wait "${pids[$i]}" 2>/dev/null || true
    local exit_file="${tmpdir}/$(echo "${tasks[$i]}" | tr ':' '_').exit"
    local log_file="${tmpdir}/$(echo "${tasks[$i]}" | tr ':' '_').log"
    local exit_code
    exit_code=$(cat "$exit_file" 2>/dev/null || echo "1")

    if [[ "$exit_code" -eq 0 ]]; then
      echo -e "  ${GREEN}✓ ${tasks[$i]}${NC}"
    else
      echo -e "  ${RED}✗ ${tasks[$i]} (exit: ${exit_code})${NC}"
      ((failed++))
    fi
  done

  # 清理
  rm -rf "$tmpdir"

  if [[ $failed -gt 0 ]]; then
    echo -e "${RED}${failed}/$# 任务失败${NC}"
    return 1
  else
    echo -e "${GREEN}全部 $# 任务成功${NC}"
    return 0
  fi
}

# ---------- COMMAND: init ----------
cmd_init() {
  local dir="${1:-}"
  [[ -z "$dir" ]] && die "用法: orchestrator.sh init <project_dir>"
  set_project_dir "$dir"

  echo -e "${BLUE}初始化项目: ${PROJECT_DIR}${NC}"

  # 创建目录
  mkdir -p "${PROJECT_DIR}/doc/logs" "${PROJECT_DIR}/doc/tests"

  # 初始化 git
  if [[ ! -d "${PROJECT_DIR}/.git" ]]; then
    git -C "${PROJECT_DIR}" init 2>/dev/null || true
  fi

  # 初始化 state.json
  if [[ ! -f "$STATE_FILE" ]]; then
    local project_name
    project_name=$(basename "$PROJECT_DIR")
    cat > "$STATE_FILE" << EOF
{
  "state": "IDEA",
  "project": "${project_name}",
  "work_mode": null,
  "prd_path": "doc/prd.md",
  "figma_url": null,
  "tests_path": "doc/tests/",
  "reflection_count": 0,
  "entry_point": "IDEA",
  "sessions": { "fe": null, "be": null, "qa": null },
  "chain_log": []
}
EOF
    echo -e "${GREEN}✓ state.json 已创建${NC}"
  else
    echo -e "${YELLOW}state.json 已存在，跳过${NC}"
  fi

  ensure_progress_file

  # 写首条日志
  if [[ -x "$LOGGER" ]]; then
    bash "$LOGGER" state_change "系统初始化完成，状态: IDEA" "orchestrator" 2>/dev/null || true
  fi

  # 检查工具
  echo ""
  echo -e "${BOLD}工具检查:${NC}"
  which claude >/dev/null 2>&1 && echo -e "  ${GREEN}✅ Claude CLI${NC}" || echo -e "  ${RED}❌ Claude CLI${NC}"
  which codex >/dev/null 2>&1 && echo -e "  ${GREEN}✅ Codex CLI${NC}" || echo -e "  ${RED}❌ Codex CLI${NC}"
  which gemini >/dev/null 2>&1 && echo -e "  ${GREEN}✅ Gemini CLI${NC}" || echo -e "  ${RED}❌ Gemini CLI${NC}"

  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "📋 状态: ${CYAN}IDEA${NC}"
  echo -e "🏗  项目: $(basename "$PROJECT_DIR")"
  echo -e "📂 路径: ${PROJECT_DIR}"
  echo -e "✅ 已完成: 项目初始化"
  echo -e "⏭  下一步: 描述项目概念 或 运行 orchestrator.sh onboard ${PROJECT_DIR}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ---------- COMMAND: onboard ----------
cmd_onboard() {
  local dir="${1:-}"
  [[ -z "$dir" ]] && die "用法: orchestrator.sh onboard <project_dir>"

  # 先初始化
  cmd_init "$dir"
  set_project_dir "$dir"
  cd "$PROJECT_DIR"

  # ── 日志：onboard 开始 ──
  if [[ -x "$LOGGER" ]]; then
    bash "$LOGGER" agent_start "开始 onboard: $(basename "$PROJECT_DIR")" "orchestrator" 2>/dev/null || true
  fi

  echo ""
  echo -e "${BLUE}═══ Step 1: Codex 扫描代码 ═══${NC}"

  # Codex 扫描
  local scan_prompt="扫描当前项目代码，生成结构化分析报告。包括：项目结构、技术栈、已实现功能模块、测试覆盖率、现有文档。将报告写入 doc/code-scan.md。输出 JSON: {\"success\": true, \"summary\": \"扫描结果摘要\"}"

  if [[ -x "$LOGGER" ]]; then
    bash "$LOGGER" agent_start "Codex 扫描代码结构" "be" 2>/dev/null || true
  fi

  local scan_exit=0
  if which codex >/dev/null 2>&1; then
    echo -e "${YELLOW}执行 Codex 扫描 (timeout=${CLI_TIMEOUT}s)...${NC}"
    cd "$PROJECT_DIR"
    run_with_timeout "$CLI_TIMEOUT" codex exec --full-auto -C "$PROJECT_DIR" "$scan_prompt" < /dev/null 2>&1 || scan_exit=$?
    if [[ $scan_exit -eq 0 ]]; then
      if [[ -x "$LOGGER" ]]; then
        bash "$LOGGER" agent_done "代码扫描完成" "be" 2>/dev/null || true
      fi
    else
      echo -e "${YELLOW}⚠ Codex 扫描失败 (exit: ${scan_exit})，回退到 Claude 扫描...${NC}"
      if [[ "$DRIVER_MODE" == "antigravity" ]]; then
        echo -e "${YELLOW}Antigravity 模式: 跳过自动扫描，由你手动完成${NC}"
      elif which claude >/dev/null 2>&1; then
        claude -p "$scan_prompt" --output-format json 2>&1 || echo -e "${RED}Claude 扫描也失败，继续...${NC}"
      fi
    fi
  else
    echo -e "${YELLOW}Codex 不可用，尝试 Claude 扫描...${NC}"
    if [[ "$DRIVER_MODE" == "antigravity" ]]; then
      echo -e "${YELLOW}Antigravity 模式: 跳过自动扫描，由你手动完成${NC}"
    elif which claude >/dev/null 2>&1; then
      claude -p "$scan_prompt" --output-format json 2>&1 || echo -e "${RED}Claude 扫描也失败，继续...${NC}"
    else
      echo -e "${YELLOW}无可用 CLI，跳过自动扫描${NC}"
    fi
    if [[ -x "$LOGGER" ]]; then
      bash "$LOGGER" warn "Codex 不可用，已回退" "orchestrator" 2>/dev/null || true
    fi
  fi

  echo ""
  echo -e "${BLUE}═══ Step 2: Claude PM 生成 PRD ═══${NC}"

  if [[ -x "$LOGGER" ]]; then
    bash "$LOGGER" agent_start "PM 反向生成 PRD" "pm" 2>/dev/null || true
  fi

  # Claude 生成 PRD
  local code_scan=""
  [[ -f "${PROJECT_DIR}/doc/code-scan.md" ]] && code_scan=$(cat "${PROJECT_DIR}/doc/code-scan.md")

  local prd_prompt="你是 PM Agent。基于以下代码扫描结果，反向生成产品需求文档(PRD)。\n\n代码扫描结果:\n${code_scan}\n\n要求：\n1. 列出已实现功能（从代码推导）\n2. 技术栈信息\n3. 待确认项（产品目标/商业指标留空）\n4. 本期新增功能（留空让用户补充）\n5. 写入文件: ${PROJECT_DIR}/doc/prd.md\n\n输出 JSON: {\"success\": true, \"agent\": \"PM\", \"summary\": \"PRD 摘要\"}"

  if [[ "$DRIVER_MODE" == "antigravity" ]]; then
    # Antigravity 模式：使用统一的 _emit_claude_task_pending 辅助函数
    _emit_claude_task_pending "$prd_prompt" "PM" "IDEA" "/generate-prd" "pm-generate-prd.txt" "antigravity" "" "PRD_DRAFT"
    return 0
  elif which claude >/dev/null 2>&1; then
    echo -e "${YELLOW}执行 Claude PM...${NC}"
    claude -p "$prd_prompt" --output-format json 2>&1 || echo -e "${RED}Claude PM 失败${NC}"
    if [[ -x "$LOGGER" ]]; then
      bash "$LOGGER" agent_done "PM PRD 生成完成" "pm" 2>/dev/null || true
    fi
  else
    echo -e "${YELLOW}Claude CLI 不可用，跳过 PRD 生成${NC}"
  fi

  # 更新状态到 PRD_DRAFT
  set_state "PRD_DRAFT" "onboard_import" "反向扫描+PRD 生成完成"

  if [[ -x "$LOGGER" ]]; then
    bash "$LOGGER" import_done "Onboard 完成，切入状态: PRD_DRAFT" "orchestrator" 2>/dev/null || true
    bash "$LOGGER" checkpoint "等待用户审阅 PRD" "orchestrator" 2>/dev/null || true
  fi

  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "📋 状态: ${CYAN}PRD_DRAFT${NC} (USER_GATE)"
  echo -e "🏗  项目: $(basename "$PROJECT_DIR")"
  echo -e "✅ 已完成: 代码扫描 → PRD 反向生成"
  echo -e "📄 PRD: ${PROJECT_DIR}/doc/prd.md"
  echo -e "⏭  下一步: 审阅 PRD 后运行 orchestrator.sh signal approved ${PROJECT_DIR}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}⏸ 等待用户审阅 PRD...${NC}"
}

# ---------- COMMAND: auto-run ----------
# 核心命令：自动链式执行 AUTO 节点，遇到 GATE/TERMINAL 停下
cmd_auto_run() {
  local dir="${1:-$(pwd)}"
  set_project_dir "$dir"
  check_project_dir

  local max_iterations=20  # 安全阀：最多自动执行 20 步
  local iteration=0

  while true; do
    ((iteration++))
    if [[ $iteration -gt $max_iterations ]]; then
      echo -e "${RED}安全阀: 超过 ${max_iterations} 步自动执行，停止${NC}"
      break
    fi

    local state
    state=$(get_state)

    if [[ "$state" == "IMPLEMENTATION" ]] && emit_queued_manual_takeover_if_any; then
      return 0
    fi

    local info
    info=$(lookup_state "$state")
    local node_type agent cli skill template
    IFS='|' read -r node_type agent cli skill template <<< "$info"

    echo -e "${CYAN}[Step ${iteration}] 状态: ${state} | 类型: ${node_type} | Agent: ${agent}${NC}"

    case "$node_type" in
      AUTO)
        # === 特殊处理 ===
        if [[ "$state" == "QA_FAILED" ]]; then
          local ref_count
          ref_count=$(jq -r '.reflection_count // 0' "$STATE_FILE")
          if [[ $ref_count -ge 3 ]]; then
            echo -e "${RED}调查次数已达 3 次上限，停止自动执行${NC}"
            echo -e "${YELLOW}请手动介入修复问题${NC}"
            cmd_status
            return 1
          fi
          # 增加调查计数
          local tmp; tmp=$(mktemp)
          jq '.reflection_count += 1' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
        fi

        # === 并行执行 (IMPLEMENTATION 阶段) ===
        if [[ "$state" == "IMPLEMENTATION" ]]; then
          echo -e "${BLUE}═══ 并行执行 FE + BE ═══${NC}"
          if [[ -x "$LOGGER" ]]; then
            bash "$LOGGER" implementation_start "FE(Gemini)+BE(Codex) 并行编码开始" "orchestrator" 2>/dev/null || true
          fi

          local fe_template="${TEMPLATES_DIR}/fe-implementation.txt"
          local be_template="${TEMPLATES_DIR}/be-implementation.txt"
          local fe_ok=true be_ok=true

          # 构造 prompts
          local fe_prompt be_prompt
          if [[ -f "$fe_template" ]]; then
            fe_prompt=$(render_template_file "$fe_template" "FE" "gemini") || return 1
          else
            fe_prompt="按照 ${PROJECT_DIR}/doc/prd.md 实现前端功能。"
          fi

          if [[ -f "$be_template" ]]; then
            be_prompt=$(render_template_file "$be_template" "BE" "codex") || return 1
          else
            be_prompt="按照 ${PROJECT_DIR}/doc/prd.md 实现后端功能。"
          fi

          # 并行启动
          local tmpdir; tmpdir=$(mktemp -d)
          (
            if which gemini >/dev/null 2>&1; then
              cd "$PROJECT_DIR" && run_with_timeout "$CLI_TIMEOUT" gemini -p "$fe_prompt" --yolo < /dev/null > "${tmpdir}/fe.log" 2>&1
              echo $? > "${tmpdir}/fe.exit"
            else
              echo "Gemini CLI 不可用" > "${tmpdir}/fe.log"
              echo "1" > "${tmpdir}/fe.exit"
            fi
          ) &
          local fe_pid=$!

          (
            if which codex >/dev/null 2>&1; then
              cd "$PROJECT_DIR" && run_with_timeout "$CLI_TIMEOUT" codex exec --full-auto -C "$PROJECT_DIR" "$be_prompt" < /dev/null > "${tmpdir}/be.log" 2>&1
              echo $? > "${tmpdir}/be.exit"
            else
              echo "Codex CLI 不可用" > "${tmpdir}/be.log"
              echo "1" > "${tmpdir}/be.exit"
            fi
          ) &
          local be_pid=$!

          echo -e "  FE (Gemini): PID ${fe_pid}"
          echo -e "  BE (Codex):  PID ${be_pid}"
          echo -e "${YELLOW}等待并行任务完成...${NC}"

          wait $fe_pid 2>/dev/null || true
          wait $be_pid 2>/dev/null || true

          local fe_exit=$(cat "${tmpdir}/fe.exit" 2>/dev/null || echo "1")
          local be_exit=$(cat "${tmpdir}/be.exit" 2>/dev/null || echo "1")

          [[ "$fe_exit" -ne 0 ]] && fe_ok=false
          [[ "$be_exit" -ne 0 ]] && be_ok=false

          echo -e "  FE: $([[ "$fe_ok" == true ]] && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}")"
          echo -e "  BE: $([[ "$be_ok" == true ]] && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}")"

          rm -rf "$tmpdir"

          # --- 回退逻辑：Gemini/Codex 失败时用 Claude 补救 ---
          local need_fe_fallback=false need_be_fallback=false
          [[ "$fe_ok" == false ]] && need_fe_fallback=true
          [[ "$be_ok" == false ]] && need_be_fallback=true

          if [[ "$need_fe_fallback" == true || "$need_be_fallback" == true ]]; then
            echo -e "${YELLOW}⚠ 检测到失败任务，启动 Claude/Antigravity 回退...${NC}"
            if [[ -x "$LOGGER" ]]; then
              bash "$LOGGER" warn "并行执行部分失败: FE(ok=$fe_ok) BE(ok=$be_ok)，启动回退" "orchestrator" 2>/dev/null || true
            fi

            if [[ "$DRIVER_MODE" == "antigravity" ]]; then
              # Antigravity 模式：写 TASK_PENDING，一次只能一个
              # 优先回退 FE（因为后续 BE 也会回退）
              if [[ "$need_fe_fallback" == true ]]; then
                echo -e "${YELLOW}Gemini FE 失败，回退到 Antigravity 执行 FE 角色任务${NC}"
                if [[ "$need_be_fallback" == true ]]; then
                  echo -e "${YELLOW}BE 也需要人工接管，已加入手动接管队列。${NC}"
                  queue_manual_takeover "BE" "/figma-to-code" "be-implementation.txt" "antigravity" "codex" "CODE_REVIEW" "$be_prompt"
                  _emit_claude_task_pending "$fe_prompt" "FE" "$state" "/figma-to-code" "fe-implementation.txt" "antigravity" "gemini" "IMPLEMENTATION"
                else
                  _emit_claude_task_pending "$fe_prompt" "FE" "$state" "/figma-to-code" "fe-implementation.txt" "antigravity" "gemini" "CODE_REVIEW"
                fi
                return 0
              elif [[ "$need_be_fallback" == true ]]; then
                echo -e "${YELLOW}Codex BE 失败，回退到 Antigravity 执行 BE 角色任务${NC}"
                _emit_claude_task_pending "$be_prompt" "BE" "$state" "/figma-to-code" "be-implementation.txt" "antigravity" "codex" "CODE_REVIEW"
                return 0
              fi
            else
              # CLI 模式：串行回退（Claude 不能并行）
              if [[ "$need_fe_fallback" == true ]]; then
                echo -e "${YELLOW}Gemini FE 失败，回退到 Claude CLI 串行执行 FE 角色...${NC}"
                local fe_fallback_output
                fe_fallback_output=$(claude -p "$fe_prompt" --output-format json 2>&1) && fe_ok=true || fe_ok=false
                [[ "$fe_ok" == true ]] && echo -e "${GREEN}✓ FE Claude 回退成功${NC}" || echo -e "${RED}✗ FE Claude 回退也失败${NC}"
              fi
              if [[ "$need_be_fallback" == true ]]; then
                echo -e "${YELLOW}Codex BE 失败，回退到 Claude CLI 串行执行 BE 角色...${NC}"
                local be_fallback_output
                be_fallback_output=$(claude -p "$be_prompt" --output-format json 2>&1) && be_ok=true || be_ok=false
                [[ "$be_ok" == true ]] && echo -e "${GREEN}✓ BE Claude 回退成功${NC}" || echo -e "${RED}✗ BE Claude 回退也失败${NC}"
              fi
            fi
          fi

          if [[ "$fe_ok" == false && "$be_ok" == false ]]; then
            echo -e "${RED}FE + BE 都失败（含回退），停止${NC}"
            if [[ -x "$LOGGER" ]]; then
              bash "$LOGGER" chain_break "FE+BE 并行+回退执行失败" "orchestrator" 2>/dev/null || true
            fi
            return 1
          fi

          if [[ -x "$LOGGER" ]]; then
            bash "$LOGGER" agent_done "FE+BE 完成(含回退): FE(ok=$fe_ok) BE(ok=$be_ok)" "orchestrator" 2>/dev/null || true
          fi
          set_state "CODE_REVIEW" "implementation_done" "FE(ok=$fe_ok) BE(ok=$be_ok)"
          continue
        fi

        # === 串行执行（带回退） ===
        echo -e "${BLUE}═══ 派发 Role: ${agent} → Primary Executor: ${cli} ═══${NC}"

        # 日志：agent 开始
        if [[ -x "$LOGGER" ]]; then
          bash "$LOGGER" agent_start "${agent}: ${skill} 开始 (${cli})" "${agent}" 2>/dev/null || true
        fi

        local template_path="${TEMPLATES_DIR}/${template}"
        local prompt
        if [[ -f "$template_path" ]]; then
          prompt=$(render_template_file "$template_path" "$agent" "$cli") || return 1
        else
          prompt="执行 ${skill} 任务，项目目录: ${PROJECT_DIR}"
        fi

        cd "$PROJECT_DIR"

        # 按 role 执行（自动处理执行器回退）
        run_role_with_fallback "$agent" "$cli" "$prompt" "$state" "$skill" "$template"
        local exit_code=$?

        if [[ $exit_code -eq 99 ]]; then
          # CLAUDE_TASK_PENDING — 正常退出，等 Antigravity 处理
          return 0
        fi

        if [[ $exit_code -ne 0 ]]; then
          echo -e "${RED}✗ Agent ${agent} 执行失败 (exit: ${exit_code})${NC}"
          echo "$FALLBACK_OUTPUT" | tail -20
          if [[ -x "$LOGGER" ]]; then
            bash "$LOGGER" chain_break "${agent} 执行失败: exit ${exit_code}" "orchestrator" 2>/dev/null || true
          fi
          echo -e "${YELLOW}链中断。可选操作:${NC}"
          echo -e "  retry:  orchestrator.sh auto-run ${PROJECT_DIR}"
          echo -e "  skip:   orchestrator.sh transition <next_state> ${PROJECT_DIR}"
          return 1
        fi

        echo -e "${GREEN}✓ Agent ${agent} 执行成功${NC}"

        # 解析 approved 字段
        local approved="true"
        if echo "$FALLBACK_OUTPUT" | jq -e '.approved' >/dev/null 2>&1; then
          approved=$(echo "$FALLBACK_OUTPUT" | jq -r '.approved')
        fi

        # 状态转换
        local nxt
        nxt=$(next_state "$state" "$approved")
        set_state "$nxt" "${agent}_executed" "approved=$approved"

        # 日志
        if [[ -x "$LOGGER" ]]; then
          bash "$LOGGER" agent_done "${agent}: ${skill} 完成" "${agent}" 2>/dev/null || true
        fi

        continue
        ;;

      USER_GATE|PLAN_GATE|INTERACTIVE)
        echo ""
        cmd_status
        echo -e "${YELLOW}⏸ 等待用户信号。运行: orchestrator.sh signal <信号> ${PROJECT_DIR}${NC}"
        case "$state" in
          PRD_DRAFT)          echo -e "  信号: ${BOLD}approved${NC} — 批准 PRD";;
          FIGMA_PROMPT)       echo -e "  信号: ${BOLD}figma ready <url>${NC} — Figma 设计完成";;
          DESIGN_SPEC_REVIEW) echo -e "  信号: ${BOLD}approved${NC} — 批准设计规格 + 更新后的 PRD";;
          TESTS_WRITTEN)      echo -e "  信号: ${BOLD}plan approved${NC} — 批准测试计划";;
          IDEA)               echo -e "  信号: ${BOLD}<项目描述>${NC} — 提供概念描述";;
        esac
        return 0
        ;;

      TERMINAL)
        echo -e "${GREEN}🎉 工作流已完成！${NC}"
        cmd_status
        return 0
        ;;

      *)
        echo -e "${RED}未知节点类型: ${node_type}${NC}"
        return 1
        ;;
    esac
  done
}

# ---------- COMMAND: signal ----------
# 处理用户信号，推进状态，然后继续 auto-run
cmd_signal() {
  local signal_text="${1:-}"
  local dir="${2:-$(pwd)}"
  [[ -z "$signal_text" ]] && die "用法: orchestrator.sh signal <信号文本> [project_dir]"

  set_project_dir "$dir"
  check_project_dir

  local state
  state=$(get_state)

  echo -e "${BLUE}收到信号: '${signal_text}' (当前状态: ${state})${NC}"

  case "$state" in
    IDEA)
      # 保存概念描述，派发 PM
      echo "$signal_text" > "${PROJECT_DIR}/doc/idea.txt"

      echo -e "${BLUE}═══ PM Agent 生成 PRD ═══${NC}"
      local prd_template="${TEMPLATES_DIR}/pm-generate-prd.txt"
      local prompt
      if [[ -f "$prd_template" ]]; then
        prompt=$(cat "$prd_template")
        prompt="${prompt//\{\{PROJECT_DIR\}\}/$PROJECT_DIR}"
        prompt="${prompt//\{\{IDEA_CONTENT\}\}/$signal_text}"
      else
        prompt="你是 PM Agent。为以下概念生成 PRD：${signal_text}。写入 ${PROJECT_DIR}/doc/prd.md。"
      fi

      if [[ "$DRIVER_MODE" == "antigravity" ]]; then
        _emit_claude_task_pending "$prompt" "PM" "IDEA" "/generate-prd" "pm-generate-prd.txt" "antigravity" "" "PRD_DRAFT"
        return 0
      elif which claude >/dev/null 2>&1; then
        cd "$PROJECT_DIR" && claude -p "$prompt" --output-format json 2>&1 || true
      fi

      set_state "PRD_DRAFT" "pm_generated_prd" "从概念描述生成 PRD"
      # PRD_DRAFT 是 USER_GATE，不继续 auto-run
      cmd_status
      echo -e "${YELLOW}⏸ 请审阅 ${PROJECT_DIR}/doc/prd.md，然后运行: orchestrator.sh signal approved ${PROJECT_DIR}${NC}"
      ;;

    PRD_DRAFT)
      if [[ "$signal_text" =~ ^(approved|通过|批准|ok)$ ]]; then
        set_state "PRD_REVIEW" "user_approved" "用户批准 PRD"
        # 继续自动链
        cmd_auto_run "$PROJECT_DIR"
      else
        echo -e "${YELLOW}未识别的信号。PRD_DRAFT 阶段请说 'approved' 批准。${NC}"
      fi
      ;;

    FIGMA_PROMPT)
      if [[ "$signal_text" =~ ^figma\ ready ]]; then
        local url
        url=$(echo "$signal_text" | sed 's/figma ready //')
        # 更新 figma_url
        local tmp; tmp=$(mktemp)
        jq --arg u "$url" '.figma_url = $u' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
        set_state "DESIGN_SPEC" "figma_ready" "Figma URL: $url"
        # 继续自动链 → DESIGN_SPEC (AUTO) → DESIGN_SPEC_REVIEW (GATE)
        cmd_auto_run "$PROJECT_DIR"
      else
        echo -e "${YELLOW}FIGMA_PROMPT 阶段请说 'figma ready <url>'${NC}"
      fi
      ;;

    DESIGN_SPEC_REVIEW)
      if [[ "$signal_text" =~ ^(approved|通过|批准|ok)$ ]]; then
        set_state "DESIGN_READY" "user_approved_design_spec" "用户批准设计规格 + 更新后的 PRD"
        # 继续自动链
        cmd_auto_run "$PROJECT_DIR"
      else
        echo -e "${YELLOW}DESIGN_SPEC_REVIEW 阶段请说 'approved' 批准设计规格。${NC}"
        echo -e "${CYAN}请审阅以下文件:${NC}"
        echo -e "  📄 ${PROJECT_DIR}/doc/design-spec.md — 设计规格书"
        echo -e "  📄 ${PROJECT_DIR}/doc/prd.md — 更新后的 PRD"
      fi
      ;;

    TESTS_WRITTEN)
      if [[ "$signal_text" =~ ^(plan\ approved|计划通过|approved|通过)$ ]]; then
        set_state "IMPLEMENTATION" "plan_approved" "用户批准测试计划"
        # 继续自动链
        cmd_auto_run "$PROJECT_DIR"
      else
        echo -e "${YELLOW}TESTS_WRITTEN 阶段请说 'plan approved' 批准。${NC}"
      fi
      ;;

    *)
      echo -e "${YELLOW}当前状态 ${state} 不接受用户信号。使用 orchestrator.sh status 查看状态。${NC}"
      ;;
  esac
}

# ---------- MAIN ----------
main() {
  # 解析全局 flags (--ag 可出现在任何位置)
  local args=()
  for arg in "$@"; do
    case "$arg" in
      --ag|--antigravity)
        DRIVER_MODE="antigravity"
        ;;
      *)
        args+=("$arg")
        ;;
    esac
  done
  set -- "${args[@]}"

  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    init)       cmd_init "$@";;
    onboard)    cmd_onboard "$@";;
    auto-run)   cmd_auto_run "$@";;
    signal)     cmd_signal "$@";;
    status)
      local dir="${1:-$(pwd)}"
      set_project_dir "$dir"
      cmd_status "${@:2}"
      ;;
    next)
      local dir="${1:-$(pwd)}"
      set_project_dir "$dir"
      cmd_next "${@:2}"
      ;;
    transition)
      local to="${1:-}"
      local dir="${2:-$(pwd)}"
      set_project_dir "$dir"
      cmd_transition "$to"
      ;;
    dispatch)
      local dir="${3:-$(pwd)}"
      set_project_dir "$dir"
      cmd_dispatch "$1" "$2"
      ;;
    parallel)
      set_project_dir "$(pwd)"
      cmd_parallel "$@"
      ;;
    -h|--help|help|"")
      cat << 'HELP'
Multi-Agent Orchestrator CLI (自主运行版)

用法: orchestrator.sh [--ag] <command> [args]

全局选项:
  --ag, --antigravity   Antigravity 模式: Claude 任务由调用方执行

核心命令:
  init <project_dir>              初始化新项目
  onboard <project_dir>           已有项目接入 (扫描+PRD)
  auto-run [project_dir]          自动链式执行 AUTO 节点
  signal <text> [project_dir]     处理用户信号 (approved/figma ready/plan approved)

查询命令:
  status [project_dir]            读取当前状态 + 状态卡片
  next [project_dir]              查表推荐下一步 (JSON)

底层命令:
  transition <state> [project_dir]  手动状态转换
  dispatch <agent> <skill>          构造 CLI + 模板替换 + 执行
  parallel <a1:s1> <a2:s2>          并行派发

工作流信号:
  approved / 通过                   批准 PRD (PRD_DRAFT 阶段)
  figma ready <url>                Figma 设计完成 (FIGMA_PROMPT 阶段)
  plan approved / 计划通过           批准测试计划 (TESTS_WRITTEN 阶段)
HELP
      ;;
    *)
      die "未知命令: ${cmd}。运行 orchestrator.sh --help 查看帮助"
      ;;
  esac
}

main "$@"
