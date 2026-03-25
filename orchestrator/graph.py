"""
LangGraph StateGraph 编排器

替代 orchestrator.py 中的 STATE_TABLE + auto-run 循环，
用 LangGraph 的 StateGraph 显式定义节点和边。

核心优势：
- 可视化：graph.get_graph().draw_mermaid() 生成 Mermaid 图
- 持久化：SQLite checkpointer 自动保存每步状态
- 可恢复：崩溃后从 checkpoint 恢复，不丢进度
- 可观测：与 LangSmith @traceable 无缝集成（Phase 5）

用法:
  python3 graph.py run <project_dir>        # 运行直到 GATE 节点
  python3 graph.py resume <project_dir>     # 从 checkpoint 恢复
  python3 graph.py visualize                # 输出 Mermaid 图
  python3 graph.py status <project_dir>     # 查看 checkpoint 状态
"""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path
from typing import Optional
import json
import sys

# 包路径修复
ORCHESTRATOR_HOME = Path.home() / ".claude" / "orchestrator"
sys.path.insert(0, str(ORCHESTRATOR_HOME))

from langgraph.graph import StateGraph, END
from langgraph.checkpoint.sqlite import SqliteSaver

from state import OrchestratorState
from agents.base import BaseAgent, AgentResult
from skills.loader import SkillLoader
from acceptance.checker import AcceptanceChecker
from tracing import traced_graph_node, traced_agent, traced_acceptance, traced_workflow, tracing, tracing_status

# ────────── 常量 ──────────

DB_PATH = str(ORCHESTRATOR_HOME / "checkpoints.db")
MAX_REFLECTIONS = 3
AGENT_TIMEOUT = 600  # 10 min


def _log(msg: str):
    print(f"[Graph] {msg}", file=sys.stderr)


def _ts() -> str:
    return datetime.now().isoformat()


# ────────── 辅助 ──────────

def _read_file(path: Path) -> str:
    if path.exists():
        return path.read_text(encoding="utf-8")
    return ""


def _build_variables(state: OrchestratorState) -> dict[str, str]:
    """从 state 构建模板变量"""
    project_dir = Path(state.get("project_dir", "."))
    doc = project_dir / "doc"
    return {
        "PROJECT_DIR": str(project_dir),
        "PRD_CONTENT": state.get("prd_content", "") or _read_file(doc / "prd.md"),
        "PRD_CONCEPT": _read_file(doc / "prd.md"),
        "FIGMA_URL": state.get("figma_url", "") or _read_file(doc / "figma-url.txt").strip(),
        "FE_PLAN": state.get("fe_plan", "") or _read_file(doc / "fe-plan.md"),
        "BE_PLAN": state.get("be_plan", "") or _read_file(doc / "be-plan.md"),
        "REFLECTION": state.get("reflection", "") or _read_file(doc / "reflection.md"),
        "TEST_PLAN": state.get("test_plan", "") or _read_file(doc / "test-plan.md"),
        "TEST_REPORT": json.dumps(state.get("test_result", {}), ensure_ascii=False),
        "TECH_STACK": "React + TypeScript",
    }


def _run_agent(
    state: OrchestratorState,
    agent_name: str,
    cli: str,
    template: str,
) -> AgentResult:
    """执行单个 Agent（带 LangSmith tracing）"""
    loader = SkillLoader()
    project_dir = state.get("project_dir", ".")
    variables = _build_variables(state)

    agent = BaseAgent(
        name=agent_name,
        cli=cli,
        template=template,
        project_dir=project_dir,
        skill_loader=loader,
    )
    prompt = agent.render_template(variables)

    with tracing.span(f"agent:{agent_name}", run_type="chain",
                       inputs={"cli": cli, "template": template}):
        return agent.execute_with_fallback(prompt, timeout=AGENT_TIMEOUT)


def _check_acceptance(state: OrchestratorState, agent_name: str) -> dict:
    """运行验收（带 LangSmith tracing）"""
    project_dir = state.get("project_dir", ".")
    checker = AcceptanceChecker(project_dir)

    with tracing.span(f"acceptance:{agent_name}", run_type="tool",
                       inputs={"agent": agent_name}):
        result = checker.check_for_agent(agent_name)
        _log(str(result))
        return result.to_dict()


# ────────── 节点函数 ──────────
# 每个节点接收 state，返回 state 的 partial update

def node_pm(state: OrchestratorState) -> dict:
    """PM: 生成 PRD"""
    _log("🔵 PM: 生成 PRD")
    result = _run_agent(state, "PM", "claude", "pm-generate-prd.txt")
    acceptance = _check_acceptance(state, "PM")

    update = {
        "current_node": "PM",
        "agent_result": result.to_dict(),
        "acceptance_result": acceptance,
        "logs": [f"[{_ts()}] PM 执行完成: {result.summary}"],
    }

    # 读取生成的 PRD
    prd_path = Path(state.get("project_dir", ".")) / "doc" / "prd.md"
    if prd_path.exists():
        update["prd_content"] = prd_path.read_text(encoding="utf-8")

    if not result.success:
        update["errors"] = [f"[{_ts()}] PM 执行失败: {result.error}"]

    return update


def node_user_gate(state: OrchestratorState) -> dict:
    """用户审批节点 — 标记等待状态，graph 中断"""
    _log("⏸️ 等待用户审批")
    return {
        "current_node": "USER_GATE",
        "logs": [f"[{_ts()}] 等待用户审批"],
    }


def node_be_review(state: OrchestratorState) -> dict:
    """BE Review: 审查 PRD"""
    _log("🔵 BE: 审查 PRD")
    result = _run_agent(state, "BE", "codex", "be-review-prd.txt")
    return {
        "current_node": "BE_REVIEW",
        "agent_result": result.to_dict(),
        "user_approved": result.approved,
        "logs": [f"[{_ts()}] BE Review: approved={result.approved}"],
    }


def node_fe_review(state: OrchestratorState) -> dict:
    """FE Review: 审查 PRD"""
    _log("🔵 FE: 审查 PRD")
    result = _run_agent(state, "FE", "gemini", "fe-review-prd.txt")
    return {
        "current_node": "FE_REVIEW",
        "agent_result": result.to_dict(),
        "user_approved": result.approved,
        "logs": [f"[{_ts()}] FE Review: approved={result.approved}"],
    }


def node_designer(state: OrchestratorState) -> dict:
    """Designer: 生成 Figma Prompt"""
    _log("🔵 Designer: 生成 Figma Prompt")
    result = _run_agent(state, "Designer", "claude", "designer-figma-prompt.txt")
    acceptance = _check_acceptance(state, "Designer")

    update = {
        "current_node": "DESIGNER",
        "agent_result": result.to_dict(),
        "acceptance_result": acceptance,
        "logs": [f"[{_ts()}] Designer 执行完成"],
    }

    prompt_path = Path(state.get("project_dir", ".")) / "doc" / "figma-prompt.md"
    if prompt_path.exists():
        update["figma_prompt"] = prompt_path.read_text(encoding="utf-8")

    return update


def node_qa_prepare(state: OrchestratorState) -> dict:
    """QA: 准备测试"""
    _log("🔵 QA: 准备测试计划")
    result = _run_agent(state, "QA", "codex", "qa-prepare-tests.txt")
    acceptance = _check_acceptance(state, "QA")

    update = {
        "current_node": "QA_PREPARE",
        "agent_result": result.to_dict(),
        "acceptance_result": acceptance,
        "logs": [f"[{_ts()}] QA 测试准备完成"],
    }

    plan_path = Path(state.get("project_dir", ".")) / "doc" / "test-plan.md"
    if plan_path.exists():
        update["test_plan"] = plan_path.read_text(encoding="utf-8")

    return update


def node_implementation(state: OrchestratorState) -> dict:
    """FE + BE 并行实现"""
    _log("🔀 FE + BE 并行实现")
    loader = SkillLoader()
    project_dir = state.get("project_dir", ".")
    variables = _build_variables(state)

    def run_fe():
        agent = BaseAgent("FE", "gemini", "fe-implementation.txt", project_dir, loader)
        prompt = agent.render_template(variables)
        return agent.execute_with_fallback(prompt, timeout=900)

    def run_be():
        agent = BaseAgent("BE", "codex", "be-implementation.txt", project_dir, loader)
        prompt = agent.render_template(variables)
        return agent.execute_with_fallback(prompt, timeout=900)

    with ThreadPoolExecutor(max_workers=2) as pool:
        fe_future = pool.submit(run_fe)
        be_future = pool.submit(run_be)
        fe_result = fe_future.result(timeout=960)
        be_result = be_future.result(timeout=960)

    # FE + BE 分别验收
    fe_acc = _check_acceptance(state, "FE")
    be_acc = _check_acceptance(state, "BE")

    success = fe_result.success and be_result.success
    return {
        "current_node": "IMPLEMENTATION",
        "agent_result": {
            "FE": fe_result.to_dict(),
            "BE": be_result.to_dict(),
        },
        "acceptance_result": {"FE": fe_acc, "BE": be_acc},
        "logs": [
            f"[{_ts()}] FE: {fe_result.summary}",
            f"[{_ts()}] BE: {be_result.summary}",
        ],
        "errors": (
            [f"[{_ts()}] 实现失败"]
            if not success else []
        ),
    }


def node_qa_test(state: OrchestratorState) -> dict:
    """QA: 运行测试"""
    _log("🔵 QA: 运行测试")
    result = _run_agent(state, "QA", "codex", "qa-run-tests.txt")
    acceptance = _check_acceptance(state, "QA")

    test_result = {}
    if result.raw_json:
        test_result = result.raw_json

    return {
        "current_node": "QA_TEST",
        "agent_result": result.to_dict(),
        "acceptance_result": acceptance,
        "test_result": test_result,
        "logs": [f"[{_ts()}] QA 测试结果: success={result.success}"],
    }


def node_reflection(state: OrchestratorState) -> dict:
    """General: 反思 + 生成改进方案"""
    count = state.get("reflection_count", 0) + 1
    _log(f"🔵 General: 反思（第 {count} 次）")

    result = _run_agent(state, "General", "claude", "general-add-reflection.txt")

    update = {
        "current_node": "REFLECTION",
        "reflection_count": count,
        "agent_result": result.to_dict(),
        "logs": [f"[{_ts()}] 反思 #{count}: {result.summary}"],
    }

    ref_path = Path(state.get("project_dir", ".")) / "doc" / "reflection.md"
    if ref_path.exists():
        update["reflection"] = ref_path.read_text(encoding="utf-8")

    return update


# ────────── 路由函数 ──────────

def route_be_review(state: OrchestratorState) -> str:
    """BE Review 路由：approved → FE_Review, rejected → PM"""
    approved = state.get("user_approved")
    if approved:
        return "FE_Review"
    _log("❌ BE Review rejected → 回到 PM")
    return "PM"


def route_fe_review(state: OrchestratorState) -> str:
    """FE Review 路由：approved → Designer, rejected → PM"""
    approved = state.get("user_approved")
    if approved:
        return "Designer"
    _log("❌ FE Review rejected → 回到 PM")
    return "PM"


def route_qa_test(state: OrchestratorState) -> str:
    """QA 测试路由：pass → END, fail → Reflection (or END if max)"""
    result = state.get("agent_result", {})
    success = result.get("success", False)

    if success:
        return "DONE"

    count = state.get("reflection_count", 0)
    if count >= MAX_REFLECTIONS:
        _log(f"🛑 反思次数已达上限 ({count}/{MAX_REFLECTIONS})")
        return "DONE"

    return "Reflection"


# ────────── 构建 StateGraph ──────────

def build_graph() -> StateGraph:
    """构建编排 StateGraph"""
    graph = StateGraph(OrchestratorState)

    # 添加节点
    graph.add_node("PM", node_pm)
    graph.add_node("PM_UserReview", node_user_gate)
    graph.add_node("BE_Review", node_be_review)
    graph.add_node("FE_Review", node_fe_review)
    graph.add_node("Designer", node_designer)
    graph.add_node("Design_UserReview", node_user_gate)
    graph.add_node("QA_Prepare", node_qa_prepare)
    graph.add_node("Plan_UserReview", node_user_gate)
    graph.add_node("Implementation", node_implementation)
    graph.add_node("QA_Test", node_qa_test)
    graph.add_node("Reflection", node_reflection)

    # 设置入口
    graph.set_entry_point("PM")

    # 定义边
    graph.add_edge("PM", "PM_UserReview")
    graph.add_edge("PM_UserReview", "BE_Review")  # 用户审批后继续

    # BE Review → 条件路由
    graph.add_conditional_edges("BE_Review", route_be_review, {
        "FE_Review": "FE_Review",
        "PM": "PM",
    })

    # FE Review → 条件路由
    graph.add_conditional_edges("FE_Review", route_fe_review, {
        "Designer": "Designer",
        "PM": "PM",
    })

    graph.add_edge("Designer", "Design_UserReview")
    graph.add_edge("Design_UserReview", "QA_Prepare")
    graph.add_edge("QA_Prepare", "Plan_UserReview")
    graph.add_edge("Plan_UserReview", "Implementation")
    graph.add_edge("Implementation", "QA_Test")

    # QA Test → 条件路由
    graph.add_conditional_edges("QA_Test", route_qa_test, {
        "DONE": END,
        "Reflection": "Reflection",
    })

    graph.add_edge("Reflection", "Implementation")

    return graph


def compile_graph(db_path: Optional[str] = None):
    """编译 graph + checkpointer (返回 context manager)"""
    graph = build_graph()

    if db_path is None:
        db_path = DB_PATH

    # SqliteSaver.from_conn_string returns a context manager
    # Caller must use: with compile_graph() as app: ...
    import contextlib

    @contextlib.contextmanager
    def _compiled():
        with SqliteSaver.from_conn_string(db_path) as checkpointer:
            yield graph.compile(checkpointer=checkpointer)

    return _compiled()


# ────────── CLI 命令 ──────────

def cmd_run(project_dir: str):
    """运行 graph 直到 USER_GATE 中断"""
    config = {"configurable": {"thread_id": project_dir}}

    initial_state: OrchestratorState = {
        "project_dir": project_dir,
        "current_node": "PM",
        "reflection_count": 0,
        "errors": [],
        "logs": [f"[{_ts()}] 工作流启动"],
    }

    _log(f"🚀 启动 LangGraph 工作流: {project_dir}")

    with compile_graph() as app:
        for event in app.stream(initial_state, config=config):
            node_name = list(event.keys())[0]
            node_data = event[node_name]
            current = node_data.get("current_node", "?")
            _log(f"  ✓ 完成节点: {node_name} → current={current}")

            if current == "USER_GATE":
                _log("⏸️ 到达用户审批点，工作流暂停")
                print("USER_GATE_REACHED")
                return

    _log("✅ 工作流完成")


def cmd_resume(project_dir: str):
    """从 checkpoint 恢复执行"""
    config = {"configurable": {"thread_id": project_dir}}

    _log(f"♻️ 从 checkpoint 恢复: {project_dir}")

    with compile_graph() as app:
        for event in app.stream(None, config=config):
            node_name = list(event.keys())[0]
            node_data = event[node_name]
            current = node_data.get("current_node", "?")
            _log(f"  ✓ 完成节点: {node_name} → current={current}")

            if current == "USER_GATE":
                _log("⏸️ 到达用户审批点，工作流暂停")
                print("USER_GATE_REACHED")
                return

    _log("✅ 工作流完成")


def cmd_visualize():
    """输出 Mermaid 可视化"""
    graph = build_graph()
    compiled = graph.compile()
    try:
        mermaid = compiled.get_graph().draw_mermaid()
        print(mermaid)
    except Exception as e:
        _log(f"Mermaid 输出失败: {e}")
        # 退回手动输出
        print("```mermaid")
        print("graph TD")
        print("  PM --> PM_UserReview")
        print("  PM_UserReview --> BE_Review")
        print("  BE_Review -->|approved| FE_Review")
        print("  BE_Review -->|rejected| PM")
        print("  FE_Review -->|approved| Designer")
        print("  FE_Review -->|rejected| PM")
        print("  Designer --> Design_UserReview")
        print("  Design_UserReview --> QA_Prepare")
        print("  QA_Prepare --> Plan_UserReview")
        print("  Plan_UserReview --> Implementation")
        print("  Implementation --> QA_Test")
        print("  QA_Test -->|pass| END")
        print("  QA_Test -->|fail| Reflection")
        print("  Reflection --> Implementation")
        print("```")


def cmd_status(project_dir: str):
    """查看 checkpoint + tracing 状态"""
    # Tracing 状态
    ts = tracing_status()
    print(f"\n╔══════ LangSmith Tracing ══════╗")
    print(f"║ Installed: {ts['langsmith_installed']}")
    print(f"║ Enabled:   {ts['tracing_enabled']}")
    print(f"║ API Key:   {'✅ set' if ts['api_key_set'] else '❌ not set'}")
    print(f"║ Project:   {ts['project']}")
    print(f"╚══════════════════════════════╝")

    # Checkpoint 状态
    try:
        with SqliteSaver.from_conn_string(DB_PATH) as checkpointer:
            config = {"configurable": {"thread_id": project_dir}}
            checkpoint = checkpointer.get(config)
            if checkpoint:
                state = checkpoint.get("channel_values", {})
                current = state.get("current_node", "UNKNOWN")
                ref_count = state.get("reflection_count", 0)
                logs = state.get("logs", [])
                errors = state.get("errors", [])
                print(f"\n╔══════ LangGraph Checkpoint ══════╗")
                print(f"║ 项目: {project_dir}")
                print(f"║ 当前节点: {current}")
                print(f"║ 反思次数: {ref_count}/{MAX_REFLECTIONS}")
                print(f"║ 日志条数: {len(logs)}")
                print(f"║ 错误数: {len(errors)}")
                print(f"╚══════════════════════════════════╝")
                if logs:
                    print(f"\n最近日志:")
                    for log in logs[-5:]:
                        print(f"  {log}")
            else:
                print(f"\n无 checkpoint: {project_dir}")
    except Exception as e:
        print(f"读取 checkpoint 失败: {e}")


# ────────── 入口 ──────────

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1]

    if command == "run":
        project_dir = sys.argv[2] if len(sys.argv) > 2 else "."
        cmd_run(project_dir)
    elif command == "resume":
        project_dir = sys.argv[2] if len(sys.argv) > 2 else "."
        cmd_resume(project_dir)
    elif command == "visualize":
        cmd_visualize()
    elif command == "status":
        project_dir = sys.argv[2] if len(sys.argv) > 2 else "."
        cmd_status(project_dir)
    else:
        print(f"未知命令: {command}")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
