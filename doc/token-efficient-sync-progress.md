# Token 效率规则同步进展

> 日期: 2026-04-03
> 来源: [drona23/claude-token-efficient](https://github.com/drona23/claude-token-efficient) (MIT, ⭐2.6k)

## 背景

该仓库提供一套极简的 CLAUDE.md 规则（仅 8 条），通过控制 Claude 的输出行为减少冗余 token。社区基准测试显示平均减少 ~63% 输出 token，在自动化流水线和高输出量场景效果最显著。

## 同步状态

| 文件 | 状态 | 说明 |
|------|------|------|
| `~/.claude/CLAUDE.md` | ✅ 已同步 | 新增「Token 效率规则」章节（8 条规则），位于全局约束之前 |
| `antigravity/GEMINI.md` | ✅ 已同步 | 新增「Token 效率规则」章节（7 条规则），针对 FE 代码输出优化 |
| `antigravity/skills/multi-agent-orchestrator/SKILL.md` | ✅ 已同步 | 新增「Token 效率规则」章节（6 条规则），针对编排器场景 |
| `README.md` | ✅ 已同步 | 新增第 12 章节，记录出处和同步位置 |
| `claude/CLAUDE.md`（仓库镜像） | ✅ 已同步 | 从 `~/.claude/CLAUDE.md` 复制 |

## 规则内容（适配后）

1. **先思考再行动** — 读取已有文件再写代码，不盲猜上下文
2. **输出精炼** — 禁止拍马屁开头和废话结尾
3. **局部编辑优先** — 不重写整个文件
4. **不重复读取** — 已读文件不重复读取（除非已变更）
5. **测试后交付** — 代码完成前必须验证
6. **简单直接** — 不过度工程
7. **用户指令优先** — 用户明确指令覆盖一切
8. **纯 ASCII** — 避免 em dash、智能引号等特殊字符

## 注意事项

- CLAUDE.md 本身会在每条消息消耗 input token，所以规则要**极简**
- 原仓库的规则只有 8 行，我们适配后各文件也控制在 6-8 条以内
- 低频/单次查询场景，这些规则的 input token 开销可能大于 output 节省
- 我们的多 Agent 流水线属于高输出量场景，净节省应为正
