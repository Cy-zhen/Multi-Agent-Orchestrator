"""
OrchestratorState — LangGraph 状态定义

状态是整个编排流程的共享上下文，在节点间传递。
SQLite checkpointer 会自动持久化每次状态变更。
"""

from typing import Annotated, Optional
from typing_extensions import TypedDict
import operator


def _append_list(a: list, b: list) -> list:
    """reducer: 追加日志列表"""
    return a + b


class OrchestratorState(TypedDict, total=False):
    """
    编排器共享状态

    Attributes:
        project_dir:       项目目录绝对路径
        current_node:      当前节点名称
        prd_content:       PRD 文档内容（PM 产出）
        figma_prompt:      Figma prompt（Designer 产出）
        figma_url:         Figma 设计稿 URL（用户提供）
        fe_plan:           前端实现计划
        be_plan:           后端实现计划
        test_plan:         测试计划（QA 产出）
        test_result:       测试结果（QA 产出）
        reflection:        反思内容
        reflection_count:  反思次数
        user_approved:     用户审批结果
        agent_result:      最近一次 Agent 结果 JSON
        acceptance_result: 最近一次验收结果
        errors:            错误列表（仅追加）
        logs:              操作日志（仅追加）
    """
    project_dir: str
    current_node: str
    prd_content: str
    figma_prompt: str
    figma_url: str
    fe_plan: str
    be_plan: str
    test_plan: str
    test_result: dict
    reflection: str
    reflection_count: int
    user_approved: Optional[bool]
    agent_result: dict
    acceptance_result: dict
    errors: Annotated[list[str], _append_list]
    logs: Annotated[list[str], _append_list]
