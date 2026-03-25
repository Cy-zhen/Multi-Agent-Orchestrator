"""
Skills Loader — 渐进式披露的核心组件

负责读取 skills/{agent}/_config.yaml，按 inject_at 字段
分阶段加载 skill 内容，返回 phase→text 字典。
"""

from pathlib import Path
from typing import Optional
import re

# 尝试加载 PyYAML；如果不存在，使用简单的 YAML 解析
try:
    import yaml
except ImportError:
    yaml = None


def _strip_inline_comment(val: str) -> str:
    """Strip inline YAML comments: 'design  # comment' -> 'design'"""
    if val.startswith('"') or val.startswith("'"):
        return val
    if "  #" in val:
        val = val.split("  #")[0]
    elif "\t#" in val:
        val = val.split("\t#")[0]
    return val.strip()


def _simple_yaml_parse(text: str) -> dict:
    """极简 YAML 解析器 — 仅处理 _config.yaml 的扁平和嵌套列表结构"""
    result = {"skills": []}
    current_skill = None
    for line in text.split("\n"):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        # 顶层 key: value
        if not line.startswith(" ") and ":" in stripped:
            key, _, val = stripped.partition(":")
            val = _strip_inline_comment(val.strip()).strip('"').strip("'")
            if val and key.strip() != "skills":
                result[key.strip()] = val
        # 列表项开始
        elif stripped.startswith("- name:"):
            if current_skill:
                result["skills"].append(current_skill)
            name = _strip_inline_comment(stripped.split(":", 1)[1].strip()).strip('"').strip("'")
            current_skill = {"name": name}
        # 列表项的属性
        elif current_skill and ":" in stripped and not stripped.startswith("-"):
            key, _, val = stripped.partition(":")
            val = _strip_inline_comment(val.strip()).strip('"').strip("'")
            if val:
                current_skill[key.strip()] = val
    if current_skill:
        result["skills"].append(current_skill)
    return result


def _load_yaml(path: Path) -> dict:
    """加载 YAML 文件，优先用 PyYAML，否则用简单解析器"""
    text = path.read_text(encoding="utf-8")
    if yaml:
        return yaml.safe_load(text) or {}
    return _simple_yaml_parse(text)


def _extract_summary(text: str) -> str:
    """inject_mode=summary: 提取第一段（到第一个 ## 之前）"""
    lines = text.split("\n")
    result = []
    started = False
    for line in lines:
        if line.startswith("# ") and not started:
            result.append(line)
            started = True
            continue
        if started:
            if line.startswith("## "):
                break
            result.append(line)
    return "\n".join(result).strip() if result else text[:500]


def _extract_rules(text: str) -> str:
    """inject_mode=rules: 提取所有 ## 段落标题 + 下面的 bullet list"""
    lines = text.split("\n")
    result = []
    in_section = False
    for line in lines:
        if line.startswith("## "):
            result.append(line)
            in_section = True
            continue
        if in_section:
            if line.startswith("# ") and not line.startswith("## "):
                in_section = False
                continue
            if line.strip().startswith("- ") or line.strip().startswith("* "):
                result.append(line)
            elif line.strip().startswith("```"):
                # 跳过代码块
                in_section = False
            elif not line.strip():
                result.append("")
            else:
                # 非 bullet 行，保留简短描述
                if len(line.strip()) < 100:
                    result.append(line)
    return "\n".join(result).strip()


def _estimate_tokens(text: str) -> int:
    """粗略估算 token 数（中英混合，按字符数/3）"""
    return len(text) // 3


class SkillLoader:
    """
    Skills 加载器 — 读取 _config.yaml，按 phase 分流 skill 内容

    使用方式:
        loader = SkillLoader()
        phase_skills = loader.load_for_agent("pm")
        # phase_skills = {"design": "...", "validate": "..."}
    """

    def __init__(self, skills_dir: Optional[str] = None):
        if skills_dir:
            self.skills_dir = Path(skills_dir)
        else:
            self.skills_dir = Path.home() / ".claude" / "orchestrator" / "skills"

    def _read_config(self, agent_name: str) -> dict:
        """读取指定 agent 的 _config.yaml"""
        config_path = self.skills_dir / agent_name.lower() / "_config.yaml"
        if not config_path.exists():
            return {"skills": [], "max_inject_tokens": 2000}
        return _load_yaml(config_path)

    def _load_skill_content(self, agent_name: str, skill: dict) -> str:
        """根据 inject_mode 加载 skill 文件内容"""
        file_path = self.skills_dir / agent_name.lower() / skill.get("file", "")
        if not file_path.exists():
            return f"⚠️ Skill 文件不存在: {file_path}"

        mode = skill.get("inject_mode", "summary")
        raw_text = file_path.read_text(encoding="utf-8")

        if mode == "full":
            return raw_text
        elif mode == "rules":
            return _extract_rules(raw_text)
        elif mode == "summary":
            return _extract_summary(raw_text)
        elif mode == "none":
            return f"📚 {skill['name']}: 详见 {file_path} (按需读取)"
        else:
            return _extract_summary(raw_text)

    def load_for_agent(self, agent_name: str) -> dict[str, str]:
        """
        加载指定 agent 的所有 trigger=always skills，按 inject_at 分组

        Returns:
            {"upfront": "...", "design": "...", "validate": "..."} 
            key = inject_at 值, value = 拼接好的注入文本
        """
        config = self._read_config(agent_name)
        max_tokens = int(config.get("max_inject_tokens", 2000))
        skills = config.get("skills", [])

        phase_contents: dict[str, list[str]] = {}
        total_tokens = 0

        for skill in skills:
            if skill.get("trigger", "always") != "always":
                continue

            phase = skill.get("inject_at", "upfront")
            content = self._load_skill_content(agent_name, skill)
            skill_tokens = _estimate_tokens(content)

            # 容量控制
            if total_tokens + skill_tokens > max_tokens:
                # 超出容量，降级为 none 模式
                content = f"📚 {skill['name']}: 详见 skills/{agent_name.lower()}/{skill.get('file', '')} (超出注入容量，按需读取)"
                skill_tokens = _estimate_tokens(content)

            header = f"\n---\n### 📋 {skill['name']}\n"
            if phase not in phase_contents:
                phase_contents[phase] = []
            phase_contents[phase].append(header + content)
            total_tokens += skill_tokens

        # 合并同一 phase 的所有 skill
        return {phase: "\n".join(items) for phase, items in phase_contents.items()}

    def get_on_demand_skills(self, agent_name: str) -> list[dict]:
        """返回 trigger=on_demand 的 skill 列表"""
        config = self._read_config(agent_name)
        return [
            {
                "name": s["name"],
                "description": s.get("description", ""),
                "file": str(self.skills_dir / agent_name.lower() / s.get("file", "")),
            }
            for s in config.get("skills", [])
            if s.get("trigger") == "on_demand"
        ]

    def render_template_skills(self, agent_name: str, template_text: str) -> str:
        """
        在模板文本中替换所有 {{SKILLS_xxx}} 占位符

        示例:
            {{SKILLS_DESIGN}}   → inject_at=design 的 skill 内容
            {{SKILLS_VALIDATE}} → inject_at=validate 的 skill 内容
            {{SKILLS_INJECTION}}→ 所有 skill 内容（兼容旧模板）
        """
        phase_skills = self.load_for_agent(agent_name)

        # 替换 phase-specific 占位符 {{SKILLS_xxx}}
        pattern = re.compile(r"\{\{SKILLS_(\w+)\}\}")
        def replacer(match):
            phase_name = match.group(1).lower()
            return phase_skills.get(phase_name, "")

        result = pattern.sub(replacer, template_text)

        # 兼容旧模板: {{SKILLS_INJECTION}} → 所有 skill 合并
        if "{{SKILLS_INJECTION}}" in result:
            all_skills = "\n".join(phase_skills.values())
            result = result.replace("{{SKILLS_INJECTION}}", all_skills)

        return result


# ---------- CLI 测试入口 ----------
if __name__ == "__main__":
    import sys
    agent = sys.argv[1] if len(sys.argv) > 1 else "pm"
    loader = SkillLoader()
    print(f"=== Loading skills for '{agent}' ===\n")

    phases = loader.load_for_agent(agent)
    for phase, content in phases.items():
        tokens = _estimate_tokens(content)
        print(f"[{phase}] ({tokens} tokens)")
        print(content[:200] + "..." if len(content) > 200 else content)
        print()

    on_demand = loader.get_on_demand_skills(agent)
    if on_demand:
        print(f"On-demand skills: {[s['name'] for s in on_demand]}")
