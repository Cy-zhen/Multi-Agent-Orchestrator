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

# 驱动模式: cli (默认, 调 claude -p) 或 antigravity (Claude 任务由调用方自己做)
DRIVER_MODE="cli"

# 项目级路径 — 可通过参数传入 PROJECT_DIR，或在项目目录下运行
PROJECT_DIR=""
STATE_FILE=""
LOG_DIR=""

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

check_project_dir() {
  [[ -n "$STATE_FILE" ]] || die "未设置项目路径。请传入 PROJECT_DIR 参数。"
  [[ -f "$STATE_FILE" ]] || die "项目未初始化（缺少 $STATE_FILE）。请先运行: orchestrator.sh init <project_dir>"
}

get_state() {
  jq -r '.state // "UNKNOWN"' "$STATE_FILE"
}

get_field() {
  jq -r ".$1 // \"\"" "$STATE_FILE"
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
    PRD_DRAFT)      echo "PRD_REVIEW";;
    PRD_REVIEW)
      [[ "$approved" == "true" ]] && echo "BE_APPROVED" || echo "PRD_DRAFT";;
    BE_APPROVED)
      [[ "$approved" == "true" ]] && echo "PRD_APPROVED" || echo "PRD_DRAFT";;
    PRD_APPROVED)   echo "FIGMA_PROMPT";;
    FIGMA_PROMPT)   echo "DESIGN_READY";;
    DESIGN_READY)   echo "TESTS_WRITTEN";;
    TESTS_WRITTEN)  echo "IMPLEMENTATION";;
    IMPLEMENTATION) echo "QA_TESTING";;
    QA_TESTING)     echo "QA_PASSED";;
    QA_PASSED)      echo "DONE";;
    QA_FAILED)      echo "IMPLEMENTATION";;
    *)              echo "UNKNOWN";;
  esac
}

# ---------- 转换表查询 ----------
# 返回: node_type|agent|cli|skill|prompt_template
lookup_state() {
  local state="$1"
  case "$state" in
    IDEA)           echo "INTERACTIVE|PM|claude|/generate-prd|pm-generate-prd.txt";;
    PRD_DRAFT)      echo "USER_GATE|-|-|-|-";;
    PRD_REVIEW)     echo "AUTO|BE|codex|/review-prd|be-review-prd.txt";;
    BE_APPROVED)    echo "AUTO|FE|gemini|/review-prd|fe-review-prd.txt";;
    PRD_APPROVED)   echo "AUTO|Designer|claude|/generate-figma-prompt|designer-figma-prompt.txt";;
    FIGMA_PROMPT)   echo "USER_GATE|-|-|-|-";;
    DESIGN_READY)   echo "AUTO|QA|codex|/prepare-tests|qa-prepare-tests.txt";;
    TESTS_WRITTEN)  echo "PLAN_GATE|-|-|-|-";;
    IMPLEMENTATION) echo "AUTO|FE+BE|gemini+codex|/figma-to-code|fe-implementation.txt";;
    QA_TESTING)     echo "AUTO|QA|codex|/run-tests|qa-run-tests.txt";;
    QA_PASSED)      echo "AUTO|-|-|-|-";;
    QA_FAILED)      echo "AUTO|General|claude|/add-reflection|general-add-reflection.txt";;
    DONE)           echo "TERMINAL|-|-|-|-";;
    *)              echo "UNKNOWN|-|-|-|-";;
  esac
}

# ---------- COMMAND: status ----------
cmd_status() {
  check_project_dir
  local state
  state=$(get_state)
  local info
  info=$(lookup_state "$state")
  local node_type agent cli skill template
  IFS='|' read -r node_type agent cli skill template <<< "$info"

  local reflection_count
  reflection_count=$(get_field "reflection_count")
  [[ -z "$reflection_count" ]] && reflection_count=0

  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║   Multi-Agent Orchestrator Status    ║${NC}"
  echo -e "${BOLD}╠══════════════════════════════════════╣${NC}"
  echo -e "║ 状态:       ${CYAN}${state}${NC}"
  echo -e "║ 节点类型:   ${YELLOW}${node_type}${NC}"
  echo -e "║ 等待 Agent: ${BLUE}${agent}${NC}"
  echo -e "║ CLI:        ${cli}"
  echo -e "║ 技能:       ${skill}"
  echo -e "║ 模板:       ${template}"
  echo -e "║ 反思次数:   ${reflection_count}/3"
  echo -e "║ 项目目录:   $(pwd)"
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

# ---------- CLI 回退执行函数 ----------
# run_with_fallback <cli> <prompt> <agent> [state] [skill] [template]
# 先尝试指定 CLI，失败后回退到 Claude/Antigravity
# 返回: 0=成功, 1=失败
# 输出存入全局变量 FALLBACK_OUTPUT
FALLBACK_OUTPUT=""
run_with_fallback() {
  local cli="$1"
  local prompt="$2"
  local agent="${3:-unknown}"
  local state="${4:-}"
  local skill="${5:-}"
  local template="${6:-}"

  local output=""
  local exit_code=0

  # --- 第一轮：尝试原始 CLI ---
  case "$cli" in
    claude)
      if [[ "$DRIVER_MODE" == "antigravity" ]]; then
        # Antigravity 模式: 直接走 CLAUDE_TASK_PENDING
        _emit_claude_task_pending "$prompt" "$agent" "$state" "$skill" "$template"
        return 99  # 特殊返回码：表示已写 TASK_PENDING，需要调用方退出
      fi
      echo -e "${YELLOW}执行 Claude CLI...${NC}"
      output=$(claude -p "$prompt" --output-format json 2>&1) || exit_code=$?
      ;;
    codex)
      if which codex >/dev/null 2>&1; then
        echo -e "${YELLOW}执行 Codex CLI...${NC}"
        output=$(codex exec --full-auto "$prompt" 2>&1) || exit_code=$?
      else
        echo -e "${YELLOW}Codex CLI 不可用${NC}"
        exit_code=1
      fi
      ;;
    gemini)
      if which gemini >/dev/null 2>&1; then
        echo -e "${YELLOW}执行 Gemini CLI...${NC}"
        output=$(gemini -p "$prompt" --yolo 2>&1) || exit_code=$?
      else
        echo -e "${YELLOW}Gemini CLI 不可用${NC}"
        exit_code=1
      fi
      ;;
    *)
      echo -e "${RED}未知 CLI: ${cli}${NC}"
      exit_code=1
      ;;
  esac

  # --- 成功则直接返回 ---
  if [[ $exit_code -eq 0 ]]; then
    echo -e "${GREEN}✓ ${cli} 执行成功${NC}"
    FALLBACK_OUTPUT="$output"
    return 0
  fi

  # --- 第二轮：回退到 Claude/Antigravity ---
  # 只对 gemini/codex 失败进行回退 (claude 失败不回退)
  if [[ "$cli" == "claude" ]]; then
    echo -e "${RED}✗ Claude CLI 执行失败 (exit: ${exit_code})${NC}"
    FALLBACK_OUTPUT="$output"
    return $exit_code
  fi

  echo -e "${YELLOW}⚠ ${cli} 执行失败 (exit: ${exit_code})，启动回退...${NC}"
  if [[ -x "$LOGGER" ]]; then
    bash "$LOGGER" warn "${cli} 失败(exit=${exit_code})，回退到 Claude" "orchestrator" 2>/dev/null || true
  fi

  if [[ "$DRIVER_MODE" == "antigravity" ]]; then
    # Antigravity 模式: 写任务文件让调用方执行
    _emit_claude_task_pending "$prompt" "$agent" "$state" "$skill" "$template"
    return 99  # 特殊返回码
  fi

  # CLI 模式: 回退到 claude -p
  echo -e "${YELLOW}回退: 使用 Claude CLI 执行 ${agent} 任务...${NC}"
  output=""
  exit_code=0
  output=$(claude -p "$prompt" --output-format json 2>&1) || exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    echo -e "${GREEN}✓ Claude CLI 回退执行成功${NC}"
  else
    echo -e "${RED}✗ Claude CLI 回退也失败 (exit: ${exit_code})${NC}"
  fi

  FALLBACK_OUTPUT="$output"
  return $exit_code
}

# 写 CLAUDE_TASK_PENDING 文件 (内部辅助函数)
_emit_claude_task_pending() {
  local prompt="$1"
  local agent="${2:-}"
  local state="${3:-}"
  local skill="${4:-}"
  local template="${5:-}"
  local nxt
  nxt=$(next_state "$state" true 2>/dev/null || echo "")

  local task_file="${PROJECT_DIR}/doc/.claude-task.md"
  echo "$prompt" > "$task_file"

  cat > "${PROJECT_DIR}/doc/.claude-task-meta.json" << META
{
  "state": "${state}",
  "agent": "${agent}",
  "skill": "${skill}",
  "template": "${template}",
  "next_state": "${nxt}"
}
META

  echo ""
  echo -e "${YELLOW}══════════════════════════════════════${NC}"
  echo -e "${YELLOW}  CLAUDE_TASK_PENDING${NC}"
  echo -e "${YELLOW}══════════════════════════════════════${NC}"
  echo -e "Agent: ${agent} | Skill: ${skill}"
  echo -e "Prompt 已写入: ${task_file}"
  echo -e "下一状态: ${nxt}"
  echo -e ""
  echo -e "请你(Antigravity)作为 Claude 执行以下任务:"
  echo -e "1. 读取 ${task_file} 中的 prompt"
  echo -e "2. 按照 prompt 的要求执行任务"
  echo -e "3. 完成后运行: orchestrator.sh auto-run --ag ${PROJECT_DIR}"
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

  # 变量替换
  local prompt
  prompt=$(cat "$template_path")
  prompt="${prompt//\{\{PROJECT_DIR\}\}/$(pwd)}"
  prompt="${prompt//\{\{PRD_CONTENT\}\}/$(cat doc/prd.md 2>/dev/null || echo '[PRD not found]')}"
  prompt="${prompt//\{\{FIGMA_URL\}\}/$(get_field figma_url)}"
  prompt="${prompt//\{\{TEST_PLAN\}\}/$(cat doc/test-plan.md 2>/dev/null || echo '[Test plan not found]')}"
  prompt="${prompt//\{\{FE_PLAN\}\}/$(cat doc/fe-plan.md 2>/dev/null || echo '[FE plan not found]')}"

  echo -e "${BLUE}派发 Agent: ${agent} | Skill: ${skill} | CLI: ${cli}${NC}"
  echo -e "${CYAN}模板: ${template}${NC}"
  echo ""

  # 执行（带回退）
  cd "$PROJECT_DIR"
  run_with_fallback "$cli" "$prompt" "$agent" "$state" "$skill" "$template"
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
    "$LOGGER" agent_dispatch "agent=${agent} skill=${skill} cli=${cli} exit=${exit_code}"
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
    echo -e "${YELLOW}执行 Codex 扫描...${NC}"
    cd "$PROJECT_DIR"
    codex exec --full-auto "$scan_prompt" 2>&1 || scan_exit=$?
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
    _emit_claude_task_pending "$prd_prompt" "PM" "IDEA" "/generate-prd" "pm-generate-prd.txt"
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
    local info
    info=$(lookup_state "$state")
    local node_type agent cli skill template
    IFS='|' read -r node_type agent cli skill template <<< "$info"

    echo -e "${CYAN}[Step ${iteration}] 状态: ${state} | 类型: ${node_type} | Agent: ${agent}${NC}"

    case "$node_type" in
      AUTO)
        # === 特殊处理 ===
        if [[ "$state" == "QA_PASSED" ]]; then
          set_state "DONE" "auto_complete" "所有步骤完成"
          echo -e "${GREEN}🎉 工作流完成！${NC}"
          cmd_status
          return 0
        fi

        if [[ "$state" == "QA_FAILED" ]]; then
          local ref_count
          ref_count=$(jq -r '.reflection_count // 0' "$STATE_FILE")
          if [[ $ref_count -ge 3 ]]; then
            echo -e "${RED}反思次数已达 3 次上限，停止自动执行${NC}"
            echo -e "${YELLOW}请手动介入修复问题${NC}"
            cmd_status
            return 1
          fi
          # 增加反思计数
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
            fe_prompt=$(cat "$fe_template")
            fe_prompt="${fe_prompt//\{\{PROJECT_DIR\}\}/$PROJECT_DIR}"
            fe_prompt="${fe_prompt//\{\{PRD_CONTENT\}\}/$(cat "${PROJECT_DIR}/doc/prd.md" 2>/dev/null || echo '[No PRD]')}"
            fe_prompt="${fe_prompt//\{\{FIGMA_URL\}\}/$(get_field figma_url)}"
            fe_prompt="${fe_prompt//\{\{FE_PLAN\}\}/$(cat "${PROJECT_DIR}/doc/fe-plan.md" 2>/dev/null || echo '[No FE plan]')}"
          else
            fe_prompt="按照 ${PROJECT_DIR}/doc/prd.md 实现前端功能。"
          fi

          if [[ -f "$be_template" ]]; then
            be_prompt=$(cat "$be_template")
            be_prompt="${be_prompt//\{\{PROJECT_DIR\}\}/$PROJECT_DIR}"
            be_prompt="${be_prompt//\{\{PRD_CONTENT\}\}/$(cat "${PROJECT_DIR}/doc/prd.md" 2>/dev/null || echo '[No PRD]')}"
            be_prompt="${be_prompt//\{\{TEST_PLAN\}\}/$(cat "${PROJECT_DIR}/doc/tests/test-plan.md" 2>/dev/null || cat "${PROJECT_DIR}/doc/test-plan.md" 2>/dev/null || echo '[No test plan]')}"
          else
            be_prompt="按照 ${PROJECT_DIR}/doc/prd.md 实现后端功能。"
          fi

          # 并行启动
          local tmpdir; tmpdir=$(mktemp -d)
          (
            if which gemini >/dev/null 2>&1; then
              cd "$PROJECT_DIR" && gemini -p "$fe_prompt" --yolo > "${tmpdir}/fe.log" 2>&1
              echo $? > "${tmpdir}/fe.exit"
            else
              echo "Gemini CLI 不可用" > "${tmpdir}/fe.log"
              echo "1" > "${tmpdir}/fe.exit"
            fi
          ) &
          local fe_pid=$!

          (
            if which codex >/dev/null 2>&1; then
              cd "$PROJECT_DIR" && codex exec --full-auto "$be_prompt" > "${tmpdir}/be.log" 2>&1
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
                echo -e "${YELLOW}Gemini FE 失败，回退到 Antigravity 执行 FE 任务${NC}"
                _emit_claude_task_pending "$fe_prompt" "FE" "$state" "/figma-to-code" "fe-implementation.txt"
                # 如果 BE 也失败，写入提示让用户知道还需要回退 BE
                if [[ "$need_be_fallback" == true ]]; then
                  echo -e "${YELLOW}注意: BE 也需要回退。FE 完成后请再次运行 auto-run 触发 BE 回退。${NC}"
                  # 把 BE 需要回退的信息写入 state
                  local tmp; tmp=$(mktemp)
                  jq '.pending_be_fallback = true' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
                fi
                return 0
              elif [[ "$need_be_fallback" == true ]]; then
                echo -e "${YELLOW}Codex BE 失败，回退到 Antigravity 执行 BE 任务${NC}"
                _emit_claude_task_pending "$be_prompt" "BE" "$state" "/figma-to-code" "be-implementation.txt"
                return 0
              fi
            else
              # CLI 模式：串行回退（Claude 不能并行）
              if [[ "$need_fe_fallback" == true ]]; then
                echo -e "${YELLOW}Gemini FE 失败，回退到 Claude CLI 串行执行 FE...${NC}"
                local fe_fallback_output
                fe_fallback_output=$(claude -p "$fe_prompt" --output-format json 2>&1) && fe_ok=true || fe_ok=false
                [[ "$fe_ok" == true ]] && echo -e "${GREEN}✓ FE Claude 回退成功${NC}" || echo -e "${RED}✗ FE Claude 回退也失败${NC}"
              fi
              if [[ "$need_be_fallback" == true ]]; then
                echo -e "${YELLOW}Codex BE 失败，回退到 Claude CLI 串行执行 BE...${NC}"
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
          set_state "QA_TESTING" "implementation_done" "FE(ok=$fe_ok) BE(ok=$be_ok)"
          continue
        fi

        # === 串行执行（带回退） ===
        echo -e "${BLUE}═══ 派发: ${agent} → ${cli} ═══${NC}"

        # 日志：agent 开始
        if [[ -x "$LOGGER" ]]; then
          bash "$LOGGER" agent_start "${agent}: ${skill} 开始 (${cli})" "${agent}" 2>/dev/null || true
        fi

        local template_path="${TEMPLATES_DIR}/${template}"
        local prompt
        if [[ -f "$template_path" ]]; then
          prompt=$(cat "$template_path")
          prompt="${prompt//\{\{PROJECT_DIR\}\}/$PROJECT_DIR}"
          prompt="${prompt//\{\{PRD_CONTENT\}\}/$(cat "${PROJECT_DIR}/doc/prd.md" 2>/dev/null || echo '[No PRD]')}"
          prompt="${prompt//\{\{FIGMA_URL\}\}/$(get_field figma_url)}"
          prompt="${prompt//\{\{TEST_PLAN\}\}/$(cat "${PROJECT_DIR}/doc/tests/test-plan.md" 2>/dev/null || cat "${PROJECT_DIR}/doc/test-plan.md" 2>/dev/null || echo '[No test plan]')}"
          prompt="${prompt//\{\{FE_PLAN\}\}/$(cat "${PROJECT_DIR}/doc/fe-plan.md" 2>/dev/null || echo '[No FE plan]')}"
        else
          prompt="执行 ${skill} 任务，项目目录: ${PROJECT_DIR}"
        fi

        cd "$PROJECT_DIR"

        # 使用 run_with_fallback 执行（自动处理回退）
        run_with_fallback "$cli" "$prompt" "$agent" "$state" "$skill" "$template"
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
          PRD_DRAFT)     echo -e "  信号: ${BOLD}approved${NC} — 批准 PRD";;
          FIGMA_PROMPT)  echo -e "  信号: ${BOLD}figma ready <url>${NC} — Figma 设计完成";;
          TESTS_WRITTEN) echo -e "  信号: ${BOLD}plan approved${NC} — 批准测试计划";;
          IDEA)          echo -e "  信号: ${BOLD}<项目描述>${NC} — 提供概念描述";;
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
        local task_file="${PROJECT_DIR}/doc/.claude-task.md"
        echo "$prompt" > "$task_file"
        echo -e "${YELLOW}CLAUDE_TASK_PENDING: 请你执行 PRD 生成任务。${NC}"
        echo -e "Prompt 在: ${task_file}"
        echo -e "完成后将 PRD 写入 ${PROJECT_DIR}/doc/prd.md"
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
        set_state "DESIGN_READY" "figma_ready" "Figma URL: $url"
        # 继续自动链
        cmd_auto_run "$PROJECT_DIR"
      else
        echo -e "${YELLOW}FIGMA_PROMPT 阶段请说 'figma ready <url>'${NC}"
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
