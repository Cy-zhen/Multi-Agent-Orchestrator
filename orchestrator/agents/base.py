"""
BaseAgent — Agent 基类，封装 CLI 调用和模板渲染

支持:
- claude (-p 模式)
- gemini (-p 模式)  
- codex (exec --full-auto 模式)
- 失败自动回退到 claude
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional
import json
import re
import subprocess
import sys
import time

# LangSmith tracing (graceful degradation)
try:
    from tracing import tracing as _tracing
except ImportError:
    _tracing = None

# 延迟导入 SkillLoader（避免循环）
_skill_loader = None

def _get_skill_loader(skills_dir: Optional[str] = None):
    global _skill_loader
    if _skill_loader is None:
        from skills.loader import SkillLoader
        _skill_loader = SkillLoader(skills_dir)
    return _skill_loader


@dataclass
class AgentResult:
    """Agent 执行结果"""
    success: bool
    agent: str
    action: str
    summary: str
    approved: Optional[bool] = None
    output_files: list = field(default_factory=list)
    raw_output: str = ""
    exit_code: int = 0
    error: str = ""

    def to_dict(self) -> dict:
        d = {
            "success": self.success,
            "agent": self.agent,
            "action": self.action,
            "summary": self.summary,
        }
        if self.approved is not None:
            d["approved"] = self.approved
        if self.output_files:
            d["output_files"] = self.output_files
        if self.error:
            d["error"] = self.error
        return d


def _extract_json_from_output(text: str) -> Optional[dict]:
    """从 CLI 输出中提取 JSON 块（可能嵌在文本中）"""
    # 尝试直接解析
    try:
        return json.loads(text.strip())
    except (json.JSONDecodeError, ValueError):
        pass

    # 尝试在 ```json ... ``` 代码块中查找
    pattern = re.compile(r"```(?:json)?\s*\n(.*?)\n```", re.DOTALL)
    for match in pattern.finditer(text):
        try:
            return json.loads(match.group(1))
        except (json.JSONDecodeError, ValueError):
            continue

    # 尝试找最后一个 { ... } 块
    brace_depth = 0
    start = -1
    for i in range(len(text) - 1, -1, -1):
        if text[i] == "}":
            if brace_depth == 0:
                end = i + 1
            brace_depth += 1
        elif text[i] == "{":
            brace_depth -= 1
            if brace_depth == 0:
                start = i
                try:
                    return json.loads(text[start:end])
                except (json.JSONDecodeError, ValueError):
                    brace_depth = 0
                    start = -1

    return None


class BaseAgent:
    """
    Agent 基类 — 读模板 → 注入 Skills → 调 CLI → 解析结果
    """

    # 模板目录
    TEMPLATES_DIR = Path.home() / ".claude" / "orchestrator" / "dispatch-templates"

    def __init__(
        self,
        name: str,
        cli: str,
        template: str,
        project_dir: str,
        skill_loader=None,
    ):
        """
        Args:
            name: Agent 名，如 "PM" / "FE" / "BE" / "QA" / "Designer" / "General"
            cli: CLI 工具名，"claude" / "gemini" / "codex"
            template: 模板文件名，如 "pm-generate-prd.txt"
            project_dir: 项目目录绝对路径
            skill_loader: SkillLoader 实例（默认自动创建）
        """
        self.name = name
        self.cli = cli
        self.template = template
        self.project_dir = Path(project_dir)
        self.loader = skill_loader or _get_skill_loader()

    def _log(self, msg: str):
        """输出到 stderr（与 bash 风格一致）"""
        print(f"[{self.name}] {msg}", file=sys.stderr)

    def render_template(self, variables: dict[str, str]) -> str:
        """
        渲染模板：读文件 → 替换 {{VAR}} → 注入 Skills

        Steps:
        1. 读 dispatch-templates/{self.template}
        2. 渲染 Skills 占位符（{{SKILLS_DESIGN}} 等）
        3. 替换普通变量占位符（{{PRD_CONTENT}} 等）
        """
        template_path = self.TEMPLATES_DIR / self.template
        if not template_path.exists():
            raise FileNotFoundError(f"模板不存在: {template_path}")

        text = template_path.read_text(encoding="utf-8")

        # Step 1: 用 SkillLoader 渲染 Skills 占位符
        text = self.loader.render_template_skills(self.name, text)

        # Step 2: 替换普通变量
        for key, value in variables.items():
            placeholder = "{{" + key + "}}"
            text = text.replace(placeholder, str(value))

        # Step 3: 清理未替换的占位符（标记为空值）
        text = re.sub(r"\{\{(\w+)\}\}", r"(未提供: \1)", text)

        return text

    def _build_command(self, prompt: str) -> list[str]:
        """根据 CLI 类型构建命令"""
        if self.cli == "claude":
            return ["claude", "-p", prompt, "--output-format", "json"]
        elif self.cli == "gemini":
            return ["gemini", "-p", prompt]
        elif self.cli == "codex":
            return ["codex", "exec", "--full-auto", "-q", prompt]
        else:
            raise ValueError(f"未知 CLI 类型: {self.cli}")

    def execute(self, prompt: str, timeout: int = 600) -> AgentResult:
        """
        执行 Agent：调用 CLI → 解析输出 → 返回 AgentResult
        （自动附带 LangSmith tracing span）
        """
        return self._execute_traced(prompt, timeout)

    def _execute_traced(self, prompt: str, timeout: int = 600) -> AgentResult:
        """内部执行（可追踪）"""
        self._log(f"执行中 (cli={self.cli}, timeout={timeout}s)...")
        cmd = self._build_command(prompt)

        try:
            proc = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout,
                cwd=str(self.project_dir),
                env=None,  # 继承环境
            )
            raw_output = proc.stdout + proc.stderr
            exit_code = proc.returncode

        except subprocess.TimeoutExpired:
            self._log(f"⏰ 超时 ({timeout}s)")
            return AgentResult(
                success=False, agent=self.name, action="",
                summary=f"执行超时 ({timeout}s)", exit_code=-1,
                error="TIMEOUT",
            )
        except FileNotFoundError:
            self._log(f"❌ CLI 不存在: {self.cli}")
            return AgentResult(
                success=False, agent=self.name, action="",
                summary=f"CLI 不存在: {self.cli}", exit_code=-1,
                error=f"CLI_NOT_FOUND: {self.cli}",
            )
        except Exception as e:
            self._log(f"❌ 执行异常: {e}")
            return AgentResult(
                success=False, agent=self.name, action="",
                summary=f"执行异常: {e}", exit_code=-1,
                error=str(e),
            )

        # 解析 JSON 结果
        parsed = _extract_json_from_output(raw_output)

        if parsed:
            return AgentResult(
                success=parsed.get("success", False),
                agent=parsed.get("agent", self.name),
                action=parsed.get("action", ""),
                summary=parsed.get("summary", ""),
                approved=parsed.get("approved"),
                output_files=parsed.get("output_files", []),
                raw_output=raw_output,
                exit_code=exit_code,
            )
        else:
            # 无法解析 JSON — 视为失败
            self._log("⚠️ 无法从输出中解析 JSON")
            return AgentResult(
                success=exit_code == 0,
                agent=self.name,
                action="",
                summary="执行完成但无法解析结构化输出",
                raw_output=raw_output,
                exit_code=exit_code,
                error="JSON_PARSE_FAILED" if exit_code != 0 else "",
            )

    def execute_with_retry(self, prompt: str, max_retries: int = 1, timeout: int = 600) -> AgentResult:
        """执行 + 失败自动重试"""
        for attempt in range(max_retries + 1):
            result = self.execute(prompt, timeout=timeout)
            if result.success:
                return result
            if attempt < max_retries:
                self._log(f"🔄 重试 ({attempt + 1}/{max_retries})...")
                time.sleep(2)
        return result

    def execute_with_fallback(self, prompt: str, timeout: int = 600) -> AgentResult:
        """主 CLI 失败时回退到 claude"""
        result = self.execute(prompt, timeout=timeout)
        if not result.success and self.cli != "claude":
            self._log(f"⚡ {self.cli} 失败，回退到 claude...")
            fallback = BaseAgent(
                name=self.name,
                cli="claude",
                template=self.template,
                project_dir=str(self.project_dir),
                skill_loader=self.loader,
            )
            result = fallback.execute(prompt, timeout=timeout)
        return result


# ---------- 便捷工厂函数 ----------

def create_agent(
    name: str,
    cli: str,
    template: str,
    project_dir: str,
) -> BaseAgent:
    """创建 Agent 实例"""
    return BaseAgent(
        name=name,
        cli=cli,
        template=template,
        project_dir=project_dir,
    )


# ---------- CLI 测试入口 ----------
if __name__ == "__main__":
    print("BaseAgent imported OK")
    print(f"Templates dir: {BaseAgent.TEMPLATES_DIR}")
    print(f"Templates exist: {BaseAgent.TEMPLATES_DIR.exists()}")
    if BaseAgent.TEMPLATES_DIR.exists():
        templates = list(BaseAgent.TEMPLATES_DIR.glob("*.txt"))
        print(f"Available templates: {[t.name for t in templates]}")
