#!/usr/bin/env python3
"""
Multi-Agent Orchestrator v2 (Python)

与 orchestrator.sh 共存的 Python 编排层。
可被 orchestrator.sh 调用，也可独立运行。

用法:
  python3 orchestrator.py status <project_dir>
  python3 orchestrator.py auto-run <project_dir>
  python3 orchestrator.py dispatch <agent> <skill> <project_dir>
  python3 orchestrator.py skills <agent_name>
  python3 orchestrator.py acceptance <project_dir> [agent]
"""

from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional
import json
import sys

# 包路径修复（允许从任意位置调用）
ORCHESTRATOR_HOME = Path.home() / ".claude" / "orchestrator"
sys.path.insert(0, str(ORCHESTRATOR_HOME))

from agents.base import BaseAgent, AgentResult, create_agent
from skills.loader import SkillLoader
from acceptance.checker import AcceptanceChecker, AcceptanceResult


# ────────── 状态表 ──────────
#
# 每个状态定义: (node_type, agent, cli, skill, template, transitions)
#   node_type: AUTO / USER_GATE / PLAN_GATE / INTERACTIVE / TERMINAL
#   transitions: dict，条件→目标状态
#     "default"  = 无条件跳转
#     "approved" = Agent 返回 approved=true
#     "rejected" = Agent 返回 approved=false
#     "pass"     = 测试通过
#     "fail"     = 测试失败

@dataclass
class StateEntry:
    node_type: str
    agent: Optional[str]
    cli: Optional[str]
    skill: Optional[str]
    template: Optional[str]
    transitions: dict[str, str]

STATE_TABLE: dict[str, StateEntry] = {
    "IDEA": StateEntry(
        "INTERACTIVE", "PM", "claude", "/generate-prd", "pm-generate-prd.txt",
        {"default": "PRD_DRAFT"},
    ),
    "PRD_DRAFT": StateEntry(
        "USER_GATE", None, None, None, None,
        {"default": "PRD_REVIEW"},
    ),
    "PRD_REVIEW": StateEntry(
        "AUTO", "BE", "codex", "/review-prd", "be-review-prd.txt",
        {"approved": "BE_APPROVED", "rejected": "PRD_DRAFT"},
    ),
    "BE_APPROVED": StateEntry(
        "AUTO", "FE", "gemini", "/review-prd", "fe-review-prd.txt",
        {"approved": "PRD_APPROVED", "rejected": "PRD_DRAFT"},
    ),
    "PRD_APPROVED": StateEntry(
        "AUTO", "Designer", "claude", "/generate-figma-prompt", "designer-figma-prompt.txt",
        {"default": "FIGMA_PROMPT"},
    ),
    "FIGMA_PROMPT": StateEntry(
        "USER_GATE", None, None, None, None,
        {"default": "DESIGN_READY"},
    ),
    "DESIGN_READY": StateEntry(
        "AUTO", "QA", "codex", "/prepare-tests", "qa-prepare-tests.txt",
        {"default": "TESTS_WRITTEN"},
    ),
    "TESTS_WRITTEN": StateEntry(
        "PLAN_GATE", None, None, None, None,
        {"default": "IMPLEMENTATION"},
    ),
    "IMPLEMENTATION": StateEntry(
        "AUTO", "FE+BE", "mixed", "/figma-to-code", "fe-implementation.txt",
        {"default": "QA_TESTING"},
    ),
    "QA_TESTING": StateEntry(
        "AUTO", "QA", "codex", "/run-tests", "qa-run-tests.txt",
        {"pass": "QA_PASSED", "fail": "QA_FAILED"},
    ),
    "QA_PASSED": StateEntry(
        "AUTO", None, None, None, None,
        {"default": "DONE"},
    ),
    "QA_FAILED": StateEntry(
        "AUTO", "General", "claude", "/add-reflection", "general-add-reflection.txt",
        {"default": "IMPLEMENTATION"},
    ),
    "DONE": StateEntry(
        "TERMINAL", None, None, None, None,
        {},
    ),
}


# ────────── 状态管理 ──────────

class StateManager:
    """读/写 doc/state.json"""

    def __init__(self, project_dir: str):
        self.project_dir = Path(project_dir)
        self.state_file = self.project_dir / "doc" / "state.json"
        self.log_file = self.project_dir / "doc" / "logs" / "workflow.jsonl"

    def get_state(self) -> str:
        if not self.state_file.exists():
            return "UNKNOWN"
        data = json.loads(self.state_file.read_text(encoding="utf-8"))
        return data.get("state", "UNKNOWN")

    def get_data(self) -> dict:
        if not self.state_file.exists():
            return {}
        return json.loads(self.state_file.read_text(encoding="utf-8"))

    def set_state(self, new_state: str, action: str = "", details: str = ""):
        old_state = self.get_state()
        data = self.get_data()
        data["state"] = new_state
        data["last_action"] = action
        data["updated_at"] = datetime.now().isoformat()

        # 写 state.json
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        self.state_file.write_text(
            json.dumps(data, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )

        # 追加日志
        self._log_event("state_change", "", f"{old_state} → {new_state}: {details}")
        _log(f"🔄 状态: {old_state} → {new_state}")

    def _log_event(self, event: str, agent: str, message: str):
        self.log_file.parent.mkdir(parents=True, exist_ok=True)
        entry = {
            "ts": datetime.now().isoformat(),
            "event": event,
            "agent": agent,
            "message": message,
        }
        with open(self.log_file, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")

    def log_agent_start(self, agent: str, action: str):
        self._log_event("agent_start", agent, f"开始执行: {action}")

    def log_agent_done(self, agent: str, summary: str):
        self._log_event("agent_done", agent, summary)

    def log_error(self, agent: str, error: str):
        self._log_event("agent_error", agent, error)

    def get_reflection_count(self) -> int:
        data = self.get_data()
        return int(data.get("reflection_count", 0))

    def increment_reflection(self):
        data = self.get_data()
        data["reflection_count"] = int(data.get("reflection_count", 0)) + 1
        self.state_file.write_text(
            json.dumps(data, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )


# ────────── 辅助函数 ──────────

def _log(msg: str):
    print(msg, file=sys.stderr)


def _read_file(path: Path) -> str:
    if path.exists():
        return path.read_text(encoding="utf-8")
    return ""


def _build_variables(project_dir: Path) -> dict[str, str]:
    """构建模板变量"""
    doc = project_dir / "doc"
    return {
        "PROJECT_DIR": str(project_dir),
        "PRD_CONTENT": _read_file(doc / "prd.md"),
        "PRD_CONCEPT": _read_file(doc / "prd.md"),  # IDEA 阶段的概念
        "FIGMA_URL": _read_file(doc / "figma-url.txt").strip(),
        "FE_PLAN": _read_file(doc / "fe-plan.md"),
        "BE_PLAN": _read_file(doc / "be-plan.md"),
        "REFLECTION": _read_file(doc / "reflection.md"),
        "TEST_PLAN": _read_file(doc / "test-plan.md"),
        "TEST_REPORT": _read_file(doc / "test-report.md"),
        "TECH_STACK": "React + TypeScript",  # TODO: 从 package.json 提取
    }


# ────────── 核心执行 ──────────

def determine_transition(entry: StateEntry, result: Optional[AgentResult]) -> str:
    """根据 Agent 结果确定下一个状态"""
    transitions = entry.transitions

    if not transitions:
        return "DONE"

    if "default" in transitions and len(transitions) == 1:
        return transitions["default"]

    if result is None:
        return transitions.get("default", "UNKNOWN")

    # Review 类 Agent
    if result.approved is True:
        return transitions.get("approved", transitions.get("default", "UNKNOWN"))
    elif result.approved is False:
        return transitions.get("rejected", transitions.get("default", "UNKNOWN"))

    # QA 类 Agent
    if result.success:
        return transitions.get("pass", transitions.get("default", "UNKNOWN"))
    else:
        return transitions.get("fail", transitions.get("default", "UNKNOWN"))


def run_single_agent(
    entry: StateEntry,
    project_dir: str,
    loader: SkillLoader,
) -> AgentResult:
    """执行单个 Agent"""
    variables = _build_variables(Path(project_dir))
    agent = BaseAgent(
        name=entry.agent,
        cli=entry.cli,
        template=entry.template,
        project_dir=project_dir,
        skill_loader=loader,
    )
    prompt = agent.render_template(variables)
    return agent.execute_with_fallback(prompt)


def run_parallel_fe_be(
    project_dir: str,
    loader: SkillLoader,
) -> tuple[AgentResult, AgentResult]:
    """并行执行 FE 和 BE"""
    variables = _build_variables(Path(project_dir))

    def run_fe():
        agent = BaseAgent("FE", "gemini", "fe-implementation.txt", project_dir, loader)
        prompt = agent.render_template(variables)
        return agent.execute_with_fallback(prompt, timeout=900)

    def run_be():
        agent = BaseAgent("BE", "codex", "be-implementation.txt", project_dir, loader)
        prompt = agent.render_template(variables)
        return agent.execute_with_fallback(prompt, timeout=900)

    _log("🔀 并行执行 FE + BE...")
    with ThreadPoolExecutor(max_workers=2) as pool:
        fe_future = pool.submit(run_fe)
        be_future = pool.submit(run_be)
        fe_result = fe_future.result(timeout=960)
        be_result = be_future.result(timeout=960)

    return fe_result, be_result


# ────────── 命令实现 ──────────

def cmd_status(project_dir: str):
    """显示当前状态"""
    sm = StateManager(project_dir)
    state = sm.get_state()
    entry = STATE_TABLE.get(state)

    if entry is None:
        print(f"❌ 未知状态: {state}")
        return

    reflection = sm.get_reflection_count()

    print()
    print("╔══════════════════════════════════════╗")
    print("║   Multi-Agent Orchestrator v2        ║")
    print("╠══════════════════════════════════════╣")
    print(f"║ 状态:       {state}")
    print(f"║ 节点类型:   {entry.node_type}")
    print(f"║ 等待 Agent: {entry.agent or '-'}")
    print(f"║ CLI:        {entry.cli or '-'}")
    print(f"║ 模板:       {entry.template or '-'}")
    print(f"║ 反思次数:   {reflection}/3")
    print(f"║ 项目:       {project_dir}")
    print("╚══════════════════════════════════════╝")
    print()

    if entry.node_type == "AUTO":
        print(f"→ 可自动执行。运行: python3 orchestrator.py auto-run {project_dir}")
    elif entry.node_type in ("USER_GATE", "PLAN_GATE"):
        print("→ 等待用户操作")
    elif entry.node_type == "TERMINAL":
        print("→ 工作流已完成 ✓")


def cmd_auto_run(project_dir: str):
    """自动链式执行：AUTO 节点自动运行，GATE 节点停下"""
    sm = StateManager(project_dir)
    loader = SkillLoader()

    MAX_ITERATIONS = 20  # 防止无限循环
    for i in range(MAX_ITERATIONS):
        state = sm.get_state()
        entry = STATE_TABLE.get(state)

        if entry is None:
            _log(f"❌ 未知状态: {state}")
            return

        _log(f"\n{'='*40}")
        _log(f"Step {i+1}: 状态={state}, 类型={entry.node_type}")

        # TERMINAL
        if entry.node_type == "TERMINAL":
            _log("✅ 工作流已完成")
            return

        # USER_GATE / PLAN_GATE — 停下
        if entry.node_type in ("USER_GATE", "PLAN_GATE", "INTERACTIVE"):
            _log(f"⏸️  {entry.node_type} — 等待用户操作")

            # INTERACTIVE 节点：输出 CLAUDE_TASK_PENDING
            if entry.node_type == "INTERACTIVE":
                _write_claude_task(project_dir, entry, sm)
                print("CLAUDE_TASK_PENDING")
            return

        # AUTO — 执行 Agent
        if entry.node_type == "AUTO":
            if entry.agent is None:
                # 无 Agent 节点（如 QA_PASSED），直接跳转
                next_state = determine_transition(entry, None)
                sm.set_state(next_state, action="auto-skip")
                continue

            sm.log_agent_start(entry.agent, entry.skill or "")

            # IMPLEMENTATION 特殊处理：FE+BE 并行
            if state == "IMPLEMENTATION":
                fe_result, be_result = run_parallel_fe_be(project_dir, loader)
                success = fe_result.success and be_result.success
                summary = f"FE: {fe_result.summary} | BE: {be_result.summary}"
                result = AgentResult(
                    success=success,
                    agent="FE+BE",
                    action="/figma-to-code",
                    summary=summary,
                )
                sm.log_agent_done("FE+BE", summary)
            else:
                result = run_single_agent(entry, project_dir, loader)
                sm.log_agent_done(entry.agent, result.summary)

            # ──── 验收检查 ────
            if result.success and entry.agent:
                checker = AcceptanceChecker(project_dir)
                acceptance = checker.check_for_agent(entry.agent.split("+")[0])
                if not acceptance.passed:
                    _log(f"⚠️ 验收未通过: {acceptance.agent} (score: {acceptance.score:.0%})")
                    for item in acceptance.failed_items:
                        _log(f"   {item}")
                    sm._log_event("acceptance_fail", entry.agent, acceptance.generate_feedback())
                else:
                    _log(f"✅ 验收通过: {acceptance.agent} (score: {acceptance.score:.0%})")

            if not result.success:
                sm.log_error(entry.agent, result.error or result.summary)

            # 确定下一个状态
            next_state = determine_transition(entry, result)

            # QA_FAILED 反思次数保护
            if next_state == "QA_FAILED":
                count = sm.get_reflection_count()
                if count >= 3:
                    _log("🛑 反思次数已达上限 (3/3)，停止执行")
                    sm.set_state("DONE", action="reflection_limit_reached")
                    return
                sm.increment_reflection()

            sm.set_state(next_state, action=f"agent:{entry.agent}", details=result.summary)

    _log("⚠️ 达到最大迭代次数，停止执行")


def cmd_dispatch(agent: str, skill: str, project_dir: str):
    """手动派发单个 Agent"""
    sm = StateManager(project_dir)
    loader = SkillLoader()
    state = sm.get_state()
    entry = STATE_TABLE.get(state)

    if entry is None:
        _log(f"❌ 未知状态: {state}")
        return

    # 查找匹配的模板
    variables = _build_variables(Path(project_dir))
    ag = BaseAgent(
        name=agent,
        cli=entry.cli or "claude",
        template=entry.template or f"{agent.lower()}-{skill.replace('/', '')}.txt",
        project_dir=project_dir,
        skill_loader=loader,
    )
    prompt = ag.render_template(variables)
    result = ag.execute_with_fallback(prompt)
    print(json.dumps(result.to_dict(), indent=2, ensure_ascii=False))


def cmd_skills(agent_name: str):
    """显示指定 agent 的 skills"""
    loader = SkillLoader()
    phases = loader.load_for_agent(agent_name)
    print(f"\n=== Skills for '{agent_name}' ===\n")
    for phase, content in phases.items():
        tokens = len(content) // 3
        print(f"[inject_at={phase}] (~{tokens} tokens)")
        # 只显示前 3 行
        lines = content.split("\n")[:3]
        for line in lines:
            print(f"  {line}")
        if len(content.split("\n")) > 3:
            print(f"  ... ({len(content)} chars total)")
        print()


def _write_claude_task(project_dir: str, entry: StateEntry, sm: StateManager):
    """写 .claude-task.md 让 Antigravity 执行"""
    doc = Path(project_dir) / "doc"
    doc.mkdir(parents=True, exist_ok=True)

    variables = _build_variables(Path(project_dir))
    loader = SkillLoader()

    if entry.template:
        agent = BaseAgent(
            name=entry.agent or "PM",
            cli="claude",
            template=entry.template,
            project_dir=project_dir,
            skill_loader=loader,
        )
        prompt = agent.render_template(variables)
    else:
        prompt = f"当前状态: {sm.get_state()}，请处理。"

    (doc / ".claude-task.md").write_text(prompt, encoding="utf-8")

    # 元数据
    state = sm.get_state()
    next_state = determine_transition(entry, None)
    meta = {
        "agent": entry.agent,
        "skill": entry.skill,
        "next_state": next_state,
        "created_at": datetime.now().isoformat(),
    }
    (doc / ".claude-task-meta.json").write_text(
        json.dumps(meta, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )


# ────────── CLI 入口 ──────────

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1]

    if command == "status":
        project_dir = sys.argv[2] if len(sys.argv) > 2 else "."
        cmd_status(project_dir)

    elif command == "auto-run":
        project_dir = sys.argv[2] if len(sys.argv) > 2 else "."
        cmd_auto_run(project_dir)

    elif command == "dispatch":
        if len(sys.argv) < 4:
            print("用法: orchestrator.py dispatch <agent> <skill> [project_dir]")
            sys.exit(1)
        agent = sys.argv[2]
        skill = sys.argv[3]
        project_dir = sys.argv[4] if len(sys.argv) > 4 else "."
        cmd_dispatch(agent, skill, project_dir)

    elif command == "skills":
        agent_name = sys.argv[2] if len(sys.argv) > 2 else "pm"
        cmd_skills(agent_name)

    elif command == "acceptance":
        project_dir = sys.argv[2] if len(sys.argv) > 2 else "."
        agent_name = sys.argv[3] if len(sys.argv) > 3 else "all"
        checker = AcceptanceChecker(project_dir)
        if agent_name == "all":
            results = checker.check_all()
            all_passed = True
            for name, result in results.items():
                print(str(result))
                print()
                if not result.passed:
                    all_passed = False
            print(f"\n{'✅ 全部通过' if all_passed else '❌ 存在未通过项'}")
        else:
            result = checker.check_for_agent(agent_name)
            print(str(result))

    elif command == "--help" or command == "-h":
        print(__doc__)

    else:
        print(f"未知命令: {command}")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
