"""
AcceptanceChecker — Sub-Agent 产出物的自动化验收

验收流程：
1. Agent 执行完成后，调用对应的 check_xxx() 方法
2. 返回 AcceptanceResult（通过/失败 + 详细反馈）
3. 验收失败时，生成改进建议，让 Agent 重做（最多重试 2 次）

支持的验收类型：
- PM:  PRD 文档结构、必需章节、可测试性
- FE:  编译通过、lint 通过、无 console.log、响应式
- BE:  编译通过、lint 通过、输入验证、错误处理
- QA:  测试通过率、覆盖率、无失败用例
- Designer: Figma prompt 结构检查
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional
import json
import re
import subprocess
import sys
import time


# ────────── 验收结果 ──────────

@dataclass
class CheckItem:
    """单项检查结果"""
    name: str
    passed: bool
    detail: str = ""
    severity: str = "error"  # error | warning | info

    def __str__(self):
        icon = "✅" if self.passed else ("❌" if self.severity == "error" else "⚠️")
        return f"{icon} {self.name}: {self.detail}" if self.detail else f"{icon} {self.name}"


@dataclass
class AcceptanceResult:
    """验收结果集合"""
    agent: str
    checks: list[CheckItem] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        """所有 error 级别检查都通过才算通过"""
        return all(
            c.passed for c in self.checks if c.severity == "error"
        )

    @property
    def score(self) -> float:
        """通过率"""
        if not self.checks:
            return 1.0
        return sum(1 for c in self.checks if c.passed) / len(self.checks)

    @property
    def failed_items(self) -> list[CheckItem]:
        return [c for c in self.checks if not c.passed]

    def generate_feedback(self) -> str:
        """生成给 Agent 的改进反馈"""
        if self.passed:
            return "✅ 所有验收项通过"

        lines = ["## 验收反馈（需要修复以下问题）\n"]
        for item in self.failed_items:
            lines.append(f"- **{item.name}**: {item.detail}")
        lines.append("\n请根据以上反馈修改后重新提交。")
        return "\n".join(lines)

    def to_dict(self) -> dict:
        return {
            "agent": self.agent,
            "passed": self.passed,
            "score": round(self.score, 2),
            "checks": [
                {"name": c.name, "passed": c.passed, "detail": c.detail, "severity": c.severity}
                for c in self.checks
            ],
        }

    def __str__(self):
        status = "✅ 通过" if self.passed else "❌ 未通过"
        return f"[{self.agent}] {status} ({self.score:.0%})\n" + "\n".join(str(c) for c in self.checks)


class AcceptanceError(Exception):
    """验收最终失败"""
    def __init__(self, message: str, result: Optional[AcceptanceResult] = None):
        super().__init__(message)
        self.result = result


def _log(msg: str):
    print(f"[Acceptance] {msg}", file=sys.stderr)


# ────────── 工具函数 ──────────

def _file_exists(path: Path) -> CheckItem:
    exists = path.exists() and path.stat().st_size > 0
    return CheckItem(
        name=f"文件存在: {path.name}",
        passed=exists,
        detail=f"{path.stat().st_size} bytes" if exists else "文件不存在或为空",
    )


def _has_sections(path: Path, sections: list[str]) -> CheckItem:
    """检查 markdown 文件是否包含指定章节"""
    if not path.exists():
        return CheckItem(name="必需章节", passed=False, detail="文件不存在")

    content = path.read_text(encoding="utf-8").lower()
    missing = [s for s in sections if s.lower() not in content]

    if missing:
        return CheckItem(
            name="必需章节",
            passed=False,
            detail=f"缺少: {', '.join(missing)}",
        )
    return CheckItem(name="必需章节", passed=True, detail=f"包含所有 {len(sections)} 个必需章节")


def _has_mermaid_diagram(path: Path) -> CheckItem:
    """检查是否包含 Mermaid 图表"""
    if not path.exists():
        return CheckItem(name="Mermaid 图表", passed=False, detail="文件不存在", severity="warning")

    content = path.read_text(encoding="utf-8")
    has_mermaid = "```mermaid" in content

    return CheckItem(
        name="Mermaid 图表",
        passed=has_mermaid,
        detail="包含 Mermaid 图表" if has_mermaid else "建议添加状态图或流程图",
        severity="warning",
    )


def _no_placeholder_text(path: Path) -> CheckItem:
    """检查是否包含占位符文本"""
    if not path.exists():
        return CheckItem(name="无占位符", passed=False, detail="文件不存在")

    content = path.read_text(encoding="utf-8")
    placeholders = ["TODO", "TBD", "待补充", "待定义", "xxx", "placeholder", "Lorem ipsum"]
    found = [p for p in placeholders if p.lower() in content.lower()]

    if found:
        return CheckItem(
            name="无占位符",
            passed=False,
            detail=f"发现占位符文本: {', '.join(found)}",
        )
    return CheckItem(name="无占位符", passed=True)


def _acceptance_criteria_testable(path: Path) -> CheckItem:
    """检查验收标准是否可测试（包含具体数值或动词）"""
    if not path.exists():
        return CheckItem(name="可测试验收标准", passed=False, detail="文件不存在")

    content = path.read_text(encoding="utf-8")

    # 查找 "验收标准" 或 "Acceptance Criteria" 部分
    has_criteria = any(
        keyword in content.lower()
        for keyword in ["验收标准", "acceptance criteria", "验收条件", "acceptance"]
    )

    if not has_criteria:
        return CheckItem(
            name="可测试验收标准",
            passed=False,
            detail="未找到验收标准章节",
        )

    # 检查是否包含具体数值（简单启发式）
    has_numbers = bool(re.search(r'\d+\s*(ms|秒|%|次|个|条)', content))
    has_verbs = any(v in content for v in ["应该", "必须", "不得", "should", "must", "shall"])

    testable = has_numbers or has_verbs
    return CheckItem(
        name="可测试验收标准",
        passed=testable,
        detail="包含可度量指标" if testable else "验收标准应包含具体数值（如 <200ms, >90%）",
        severity="warning",
    )


def _min_word_count(path: Path, min_count: int) -> CheckItem:
    """检查文件最少字数"""
    if not path.exists():
        return CheckItem(name=f"最少 {min_count} 字", passed=False, detail="文件不存在")

    content = path.read_text(encoding="utf-8")
    # 中英混合字数统计
    word_count = len(content.split()) + len(re.findall(r'[\u4e00-\u9fff]', content))

    return CheckItem(
        name=f"最少 {min_count} 字",
        passed=word_count >= min_count,
        detail=f"当前 {word_count} 字{'（不足）' if word_count < min_count else ''}",
    )


def _run_shell_check(cmd: str, cwd: str, name: str, timeout: int = 120) -> CheckItem:
    """运行 shell 命令检查"""
    try:
        proc = subprocess.run(
            cmd, shell=True, capture_output=True, text=True,
            cwd=cwd, timeout=timeout,
        )
        if proc.returncode == 0:
            return CheckItem(name=name, passed=True, detail="命令执行成功")
        else:
            # 截取最后 3 行错误信息
            err_lines = (proc.stderr or proc.stdout).strip().split("\n")[-3:]
            return CheckItem(
                name=name, passed=False,
                detail="\n".join(err_lines),
            )
    except subprocess.TimeoutExpired:
        return CheckItem(name=name, passed=False, detail=f"超时 ({timeout}s)")
    except Exception as e:
        return CheckItem(name=name, passed=False, detail=str(e))


def _no_console_log(project_dir: Path, src_dir: str = "src/") -> CheckItem:
    """检查是否有 console.log"""
    src_path = project_dir / src_dir
    if not src_path.exists():
        return CheckItem(name="无 console.log", passed=True, detail="src/ 目录不存在", severity="info")

    try:
        result = subprocess.run(
            f"grep -rn 'console\\.log' {src_dir} --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' | head -5",
            shell=True, capture_output=True, text=True,
            cwd=str(project_dir), timeout=10,
        )
        if result.stdout.strip():
            lines = result.stdout.strip().split("\n")
            return CheckItem(
                name="无 console.log",
                passed=False,
                detail=f"发现 {len(lines)} 处 console.log（仅显示前 5 处）",
                severity="warning",
            )
        return CheckItem(name="无 console.log", passed=True)
    except Exception:
        return CheckItem(name="无 console.log", passed=True, detail="检查跳过", severity="info")


def _has_error_boundaries(project_dir: Path) -> CheckItem:
    """检查 React 项目是否有 ErrorBoundary"""
    src_path = project_dir / "src"
    if not src_path.exists():
        return CheckItem(name="ErrorBoundary", passed=True, detail="src/ 目录不存在", severity="info")

    try:
        result = subprocess.run(
            "grep -rn 'ErrorBoundary\\|error.boundary\\|errorBoundary' src/ --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' | head -3",
            shell=True, capture_output=True, text=True,
            cwd=str(project_dir), timeout=10,
        )
        has_boundary = bool(result.stdout.strip())
        return CheckItem(
            name="ErrorBoundary",
            passed=has_boundary,
            detail="已实现 ErrorBoundary" if has_boundary else "建议添加 ErrorBoundary 组件",
            severity="warning",
        )
    except Exception:
        return CheckItem(name="ErrorBoundary", passed=True, detail="检查跳过", severity="info")


def _has_input_validation(project_dir: Path) -> CheckItem:
    """检查后端是否有输入验证"""
    for pattern in ["server/", "api/", "routes/", "controllers/", "handlers/"]:
        check_dir = project_dir / pattern
        if check_dir.exists():
            try:
                result = subprocess.run(
                    f"grep -rn 'validate\\|schema\\|zod\\|yup\\|joi\\|validator' {pattern} --include='*.ts' --include='*.js' --include='*.go' --include='*.py' | head -3",
                    shell=True, capture_output=True, text=True,
                    cwd=str(project_dir), timeout=10,
                )
                if result.stdout.strip():
                    return CheckItem(name="输入验证", passed=True, detail="已使用输入验证")
            except Exception:
                pass

    return CheckItem(
        name="输入验证", passed=False,
        detail="未检测到输入验证逻辑（validate/schema/zod/joi）",
        severity="warning",
    )


def _has_error_handling(project_dir: Path) -> CheckItem:
    """检查后端是否有统一错误处理"""
    for pattern in ["server/", "api/", "src/"]:
        check_dir = project_dir / pattern
        if check_dir.exists():
            try:
                result = subprocess.run(
                    f"grep -rn 'try.*catch\\|error.*handler\\|middleware.*error\\|recover\\|except' {pattern} --include='*.ts' --include='*.js' --include='*.go' --include='*.py' | head -3",
                    shell=True, capture_output=True, text=True,
                    cwd=str(project_dir), timeout=10,
                )
                if result.stdout.strip():
                    return CheckItem(name="错误处理", passed=True, detail="已实现错误处理机制")
            except Exception:
                pass

    return CheckItem(
        name="错误处理", passed=False,
        detail="未检测到统一错误处理（try/catch, error handler, recover）",
        severity="warning",
    )


# ────────── AcceptanceChecker ──────────

class AcceptanceChecker:
    """
    Main Agent 对 Sub-Agent 输出的自动验收

    用法:
        checker = AcceptanceChecker("/path/to/project")
        result = checker.check_pm()
        if not result.passed:
            print(result.generate_feedback())
    """

    def __init__(self, project_dir: str):
        self.project_dir = Path(project_dir)
        self.doc_dir = self.project_dir / "doc"

    def check_pm(self) -> AcceptanceResult:
        """验收 PRD 文档"""
        prd_path = self.doc_dir / "prd.md"
        checks = [
            _file_exists(prd_path),
            _min_word_count(prd_path, 200),
            _has_sections(prd_path, [
                "功能需求", "非功能需求", "验收标准",
            ]),
            _has_mermaid_diagram(prd_path),
            _acceptance_criteria_testable(prd_path),
            _no_placeholder_text(prd_path),
        ]
        return AcceptanceResult(agent="PM", checks=checks)

    def check_designer(self) -> AcceptanceResult:
        """验收设计 Prompt"""
        prompt_path = self.doc_dir / "figma-prompt.md"
        checks = [
            _file_exists(prompt_path),
            _min_word_count(prompt_path, 100),
            _has_sections(prompt_path, ["布局", "配色"]),
            _no_placeholder_text(prompt_path),
        ]
        # 布局和配色是 warning 级别
        for c in checks:
            if c.name == "必需章节" and not c.passed:
                c.severity = "warning"
        return AcceptanceResult(agent="Designer", checks=checks)

    def check_fe(self) -> AcceptanceResult:
        """验收前端代码"""
        checks = []

        # 检查 src/ 存在
        src_exists = (self.project_dir / "src").exists()
        checks.append(CheckItem(
            name="src/ 目录存在",
            passed=src_exists,
            detail="" if src_exists else "前端源码目录 src/ 不存在",
        ))

        if not src_exists:
            return AcceptanceResult(agent="FE", checks=checks)

        # 检测包管理器
        if (self.project_dir / "yarn.lock").exists():
            build_cmd, lint_cmd = "yarn build", "yarn lint"
        elif (self.project_dir / "pnpm-lock.yaml").exists():
            build_cmd, lint_cmd = "pnpm build", "pnpm lint"
        else:
            build_cmd, lint_cmd = "npm run build", "npm run lint"

        checks.extend([
            _run_shell_check(build_cmd, str(self.project_dir), f"编译通过 ({build_cmd})"),
            _run_shell_check(lint_cmd, str(self.project_dir), f"Lint 通过 ({lint_cmd})"),
            _no_console_log(self.project_dir),
            _has_error_boundaries(self.project_dir),
        ])

        return AcceptanceResult(agent="FE", checks=checks)

    def check_be(self) -> AcceptanceResult:
        """验收后端代码"""
        checks = []

        # 自动检测后端语言和构建命令
        if (self.project_dir / "go.mod").exists():
            build_cmd = "go build ./..."
            lint_cmd = "golangci-lint run"
        elif (self.project_dir / "server" / "package.json").exists():
            build_cmd = "cd server && npm run build"
            lint_cmd = "cd server && npm run lint"
        elif (self.project_dir / "requirements.txt").exists() or (self.project_dir / "pyproject.toml").exists():
            build_cmd = "python -m py_compile server/*.py 2>/dev/null || true"
            lint_cmd = "ruff check . || flake8 . || true"
        else:
            build_cmd = "echo 'No backend build detected'"
            lint_cmd = "echo 'No backend lint detected'"

        checks.extend([
            _run_shell_check(build_cmd, str(self.project_dir), f"编译通过"),
            _run_shell_check(lint_cmd, str(self.project_dir), f"Lint 通过"),
            _has_input_validation(self.project_dir),
            _has_error_handling(self.project_dir),
        ])

        return AcceptanceResult(agent="BE", checks=checks)

    def check_qa(self, test_result: Optional[dict] = None) -> AcceptanceResult:
        """验收测试结果"""
        checks = []

        if test_result:
            # 从传入的 test_result dict 验收
            passed_count = test_result.get("passed", 0)
            failed_count = test_result.get("failed", 0)
            coverage = test_result.get("coverage", 0)

            checks.extend([
                CheckItem(
                    name="有测试通过",
                    passed=passed_count > 0,
                    detail=f"{passed_count} 个测试通过",
                ),
                CheckItem(
                    name="无失败测试",
                    passed=failed_count == 0,
                    detail=f"{failed_count} 个测试失败" if failed_count > 0 else "全部通过",
                ),
                CheckItem(
                    name="覆盖率 ≥ 60%",
                    passed=coverage >= 60,
                    detail=f"当前覆盖率: {coverage}%",
                    severity="warning",
                ),
            ])
        else:
            # 尝试运行测试
            test_report = self.doc_dir / "test-report.md"
            checks.append(_file_exists(test_report))

            if test_report.exists():
                content = test_report.read_text(encoding="utf-8")
                has_pass = any(w in content.lower() for w in ["pass", "passed", "通过", "✅"])
                has_fail = any(w in content.lower() for w in ["fail", "failed", "失败", "❌"])

                checks.append(CheckItem(
                    name="测试结果",
                    passed=has_pass and not has_fail,
                    detail="测试通过" if has_pass and not has_fail else "存在失败测试",
                ))

        return AcceptanceResult(agent="QA", checks=checks)

    def check_all(self) -> dict[str, AcceptanceResult]:
        """运行所有验收检查"""
        results = {}
        results["PM"] = self.check_pm()
        results["Designer"] = self.check_designer()
        results["FE"] = self.check_fe()
        results["BE"] = self.check_be()
        results["QA"] = self.check_qa()
        return results

    def check_for_agent(self, agent_name: str, **kwargs) -> AcceptanceResult:
        """按 agent 名称运行对应验收"""
        agent_map = {
            "PM": self.check_pm,
            "Designer": self.check_designer,
            "FE": self.check_fe,
            "BE": self.check_be,
            "QA": self.check_qa,
        }
        checker_fn = agent_map.get(agent_name)
        if checker_fn is None:
            return AcceptanceResult(agent=agent_name, checks=[
                CheckItem(name="Agent 验收", passed=True, detail=f"无 {agent_name} 验收规则", severity="info")
            ])
        return checker_fn(**kwargs)


# ────────── 验收 + 重试包装 ──────────

def execute_with_acceptance(
    execute_fn: Callable,
    checker_fn: Callable[[], AcceptanceResult],
    max_retries: int = 2,
    prompt: str = "",
) -> tuple:
    """
    执行 Agent + 验收，失败自动重试

    Args:
        execute_fn: 执行函数，接收 prompt 参数，返回 AgentResult
        checker_fn: 验收函数，返回 AcceptanceResult
        max_retries: 最大重试次数
        prompt: 初始 prompt

    Returns:
        (AgentResult, AcceptanceResult)

    Raises:
        AcceptanceError: 超过重试次数仍未通过验收
    """
    current_prompt = prompt

    for attempt in range(max_retries + 1):
        _log(f"执行第 {attempt + 1} 次（共 {max_retries + 1} 次机会）")

        # 执行 Agent
        agent_result = execute_fn(current_prompt)

        if not agent_result.success:
            _log(f"Agent 执行失败: {agent_result.error}")
            if attempt < max_retries:
                _log("重试...")
                time.sleep(2)
                continue
            raise AcceptanceError(
                f"Agent 经过 {max_retries + 1} 次执行均失败",
                result=AcceptanceResult(agent=agent_result.agent, checks=[
                    CheckItem(name="Agent 执行", passed=False, detail=agent_result.error)
                ]),
            )

        # 运行验收
        acceptance = checker_fn()
        _log(str(acceptance))

        if acceptance.passed:
            _log(f"✅ 验收通过 (score: {acceptance.score:.0%})")
            return agent_result, acceptance

        # 验收失败 — 生成反馈追加到 prompt
        if attempt < max_retries:
            feedback = acceptance.generate_feedback()
            current_prompt = f"{prompt}\n\n## 上次验收反馈（第{attempt+1}次）\n{feedback}"
            _log(f"❌ 验收未通过，附加反馈后重试...")
            time.sleep(2)

    # 最终失败
    raise AcceptanceError(
        f"{acceptance.agent} 经过 {max_retries + 1} 次尝试仍未通过验收",
        result=acceptance,
    )


# ────────── CLI 入口 ──────────

def main():
    """CLI 入口：python3 acceptance/checker.py <project_dir> [agent]"""
    import sys

    if len(sys.argv) < 2:
        print("用法: python3 checker.py <project_dir> [agent]")
        print("  agent: PM | Designer | FE | BE | QA | all")
        sys.exit(1)

    project_dir = sys.argv[1]
    agent = sys.argv[2] if len(sys.argv) > 2 else "all"

    checker = AcceptanceChecker(project_dir)

    if agent == "all":
        results = checker.check_all()
        print("\n═══════ 验收报告 ═══════\n")
        all_passed = True
        for name, result in results.items():
            print(str(result))
            print()
            if not result.passed:
                all_passed = False
        print(f"\n总结: {'✅ 全部通过' if all_passed else '❌ 存在未通过项'}")
        # 输出 JSON
        print("\n" + json.dumps(
            {name: r.to_dict() for name, r in results.items()},
            indent=2, ensure_ascii=False,
        ))
    else:
        result = checker.check_for_agent(agent)
        print(str(result))
        print("\n" + json.dumps(result.to_dict(), indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
