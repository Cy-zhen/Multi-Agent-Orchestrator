"""
LangSmith 可观测性集成

提供 @traceable 装饰器包装，让 Agent 执行、验收检查、
状态转换等关键操作在 LangSmith 上可追踪。

配置:
  设置环境变量即可启用:
    LANGSMITH_API_KEY=ls-xxxx
    LANGSMITH_PROJECT=multi-agent-orchestrator
    LANGSMITH_TRACING=true

  未设置时，装饰器无副作用（零开销）。

用法:
  from tracing import traced_agent, traced_acceptance, traced_graph_node
"""

import os
import functools
from datetime import datetime
from typing import Any, Callable, Optional

# 检测 LangSmith 是否可用
_TRACING_ENABLED = os.environ.get("LANGSMITH_TRACING", "").lower() in ("true", "1", "yes")

try:
    from langsmith import traceable, trace
    _HAS_LANGSMITH = True
except ImportError:
    _HAS_LANGSMITH = False


def _noop_decorator(
    name: Optional[str] = None,
    run_type: str = "chain",
    **kwargs,
) -> Callable:
    """当 LangSmith 不可用时的空装饰器"""
    def wrapper(fn: Callable) -> Callable:
        return fn
    return wrapper


def get_traceable(**kwargs) -> Callable:
    """
    获取 @traceable 装饰器

    如果 LangSmith 已配置且可用，返回真实的 @traceable。
    否则返回 no-op 装饰器。
    """
    if _HAS_LANGSMITH and _TRACING_ENABLED:
        return traceable(**kwargs)
    return _noop_decorator(**kwargs)


# ────────── 预定义装饰器 ──────────

def traced_agent(agent_name: str):
    """
    追踪 Agent 执行

    用法:
        @traced_agent("PM")
        def run_pm(state):
            ...
    """
    return get_traceable(
        name=f"agent:{agent_name}",
        run_type="chain",
        tags=["agent", agent_name.lower()],
        metadata={"agent": agent_name},
    )


def traced_acceptance(agent_name: str):
    """
    追踪验收检查

    用法:
        @traced_acceptance("PM")
        def check_pm():
            ...
    """
    return get_traceable(
        name=f"acceptance:{agent_name}",
        run_type="tool",
        tags=["acceptance", agent_name.lower()],
        metadata={"agent": agent_name},
    )


def traced_graph_node(node_name: str):
    """
    追踪 Graph 节点执行

    用法:
        @traced_graph_node("PM")
        def node_pm(state):
            ...
    """
    return get_traceable(
        name=f"node:{node_name}",
        run_type="chain",
        tags=["graph_node", node_name.lower()],
        metadata={"node": node_name},
    )


def traced_cli(cli_name: str, agent_name: str):
    """
    追踪 CLI 调用（claude/codex/gemini）

    用法:
        @traced_cli("claude", "PM")
        def call_claude(prompt):
            ...
    """
    return get_traceable(
        name=f"cli:{cli_name}:{agent_name}",
        run_type="tool",
        tags=["cli", cli_name, agent_name.lower()],
        metadata={"cli": cli_name, "agent": agent_name},
    )


def traced_workflow(project_dir: str):
    """
    追踪整个工作流

    用法:
        @traced_workflow("/path/to/project")
        def run_workflow():
            ...
    """
    return get_traceable(
        name="workflow:orchestrator",
        run_type="chain",
        tags=["workflow"],
        metadata={"project_dir": project_dir},
    )


# ────────── 手动 Span 管理 ──────────

class TracingContext:
    """
    手动 span 管理（用于非装饰器场景）

    用法:
        ctx = TracingContext()
        with ctx.span("my_operation", run_type="tool"):
            do_stuff()
    """

    def span(
        self,
        name: str,
        run_type: str = "chain",
        inputs: Optional[dict] = None,
        **kwargs,
    ):
        if _HAS_LANGSMITH and _TRACING_ENABLED:
            return trace(name=name, run_type=run_type, inputs=inputs or {}, **kwargs)

        # 返回一个 no-op context manager
        import contextlib
        return contextlib.nullcontext()


# 全局 context
tracing = TracingContext()


# ────────── 状态报告 ──────────

def tracing_status() -> dict:
    """返回当前 tracing 配置状态"""
    return {
        "langsmith_installed": _HAS_LANGSMITH,
        "tracing_enabled": _TRACING_ENABLED,
        "api_key_set": bool(os.environ.get("LANGSMITH_API_KEY")),
        "project": os.environ.get("LANGSMITH_PROJECT", "(default)"),
        "endpoint": os.environ.get("LANGSMITH_ENDPOINT", "https://api.smith.langchain.com"),
    }
