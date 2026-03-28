---
name: game-studio
description: 游戏开发工作室技能 — 48个AI Agent协作的独立游戏开发框架。支持 Godot/Unity/Unreal 引擎，覆盖从创意脑暴到发布上架全流程。Use when user says "做游戏", "vibe一个游戏", "game dev", "开始游戏项目", "游戏设计", "game design", "游戏原型", "prototype", "游戏风格", "game style", "MDA", "GDD", "数值平衡", "balance design", "关卡设计", "level design", "游戏UI", "game UI", "游戏机制", "game mechanics", "核心循环", "core loop", "玩法设计", 或任何涉及游戏项目的设计、开发、原型工作。
---

# Game Studio — AI 游戏开发工作室

> 参考: [Claude-Code-Game-Studios](https://github.com/Donchitos/Claude-Code-Game-Studios)（MIT License）
> 48 个 AI Agent + 37 个工作流技能 + 完整的工作室层级架构

## 概述

将 Claude Code 变成一个完整的游戏开发工作室。不是一个通用助手，而是一个由 **导演 → 部门主管 → 专家** 三层架构组成的虚拟团队。

**核心理念**：
- 你做决策，AI 团队提供结构、专业知识和质量把关
- 每个 Agent 有明确的职责边界和上升路径
- 协作协议：**提问 → 选项 → 决策 → 草案 → 审批**

---

## 工作室层级（3 层 48 个 Agent）

### Tier 1 — 导演层（战略决策）

| Agent | 职责 |
|-------|------|
| **Creative Director** | 愿景守护、核心支柱定义、创意冲突仲裁、MDA美学排序 |
| **Technical Director** | 技术栈选型、架构决策、性能标准、技术债务管理 |
| **Producer** | 项目管理、Sprint计划、里程碑追踪、跨部门变更协调 |

### Tier 2 — 部门主管层（领域管理）

| Agent | 职责 |
|-------|------|
| **Game Designer** | 核心循环、系统设计、数值平衡、GDD 文档 |
| **Lead Programmer** | 代码架构、技术审查、编码标准执行 |
| **Art Director** | 视觉风格、资源管线、美术标准 |
| **Audio Director** | 音效设计、音乐风格、音频系统架构 |
| **Narrative Director** | 故事架构、对话系统、世界观构建 |
| **QA Lead** | 测试策略、Bug分类、质量门禁 |
| **Release Manager** | 发布流程、版本管理、平台合规 |
| **Localization Lead** | 多语言支持、文化适配 |

### Tier 3 — 专家层（执行实现）

**编程**: gameplay-programmer, engine-programmer, ai-programmer, network-programmer, tools-programmer, ui-programmer

**设计**: systems-designer, level-designer, economy-designer

**美术/音频**: technical-artist, sound-designer

**叙事**: writer, world-builder

**用户体验**: ux-designer, prototyper

**基础设施**: performance-analyst, devops-engineer, analytics-engineer, security-engineer

**质量**: qa-tester, accessibility-specialist

**运营**: live-ops-designer, community-manager

### 引擎专家（按项目选择）

| 引擎 | Agent |
|------|-------|
| Godot 4 | `godot-specialist` |
| Unity | `unity-specialist` |
| Unreal Engine 5 | `unreal-specialist` |

---

## 协调规则

1. **垂直委派**: 导演 → 主管 → 专家，复杂决策不跳级
2. **水平协商**: 同层 Agent 可咨询但不做跨域绑定决策
3. **冲突解决**: 设计冲突上升到 Creative Director，技术冲突上升到 Technical Director
4. **变更传播**: 跨部门变更由 Producer 协调
5. **域边界**: Agent 不修改职责外的文件，除非明确委派

---

## 工作流命令（37 个 Slash Commands）

### 项目管理

| 命令 | 说明 |
|------|------|
| `/start` | 引导式启动 — 问你在哪个阶段（无想法/模糊概念/明确设计/已有代码）|
| `/project-stage-detect` | 分析现有项目，判断当前阶段 |
| `/reverse-document` | 从代码反向生成设计文档 |
| `/gate-check` | 检查是否满足进入下一阶段的条件 |
| `/map-systems` | 生成系统依赖关系图 |
| `/design-system` | 建立设计系统和规范 |

### 创意 & 原型

| 命令 | 说明 |
|------|------|
| `/brainstorm` | 从零开始探索游戏创意 |
| `/prototype` | 快速原型验证（隔离在 `prototypes/` 目录）|
| `/playtest-report` | 测试报告模板和分析框架 |
| `/onboard` | 新成员/新会话上下文恢复 |
| `/localize` | 国际化和本地化工作流 |

### 审查 & 分析

| 命令 | 说明 |
|------|------|
| `/design-review` | 设计审查（对照核心支柱/MDA）|
| `/code-review` | 代码审查（架构/性能/可测试性）|
| `/balance-check` | 数值平衡检查 |
| `/asset-audit` | 资源审计（大小/格式/命名）|
| `/scope-check` | 范围检查（功能 vs 产能）|
| `/perf-profile` | 性能分析和优化建议 |
| `/tech-debt` | 技术债务评估和偿还计划 |

### 生产管理

| 命令 | 说明 |
|------|------|
| `/sprint-plan` | Sprint 计划（含估算和优先级）|
| `/milestone-review` | 里程碑审核 |
| `/estimate` | 工作量估算 |
| `/retrospective` | 回顾 & 改进 |
| `/bug-report` | Bug 报告模板 |

### 发布

| 命令 | 说明 |
|------|------|
| `/release-checklist` | 发布检查清单 |
| `/launch-checklist` | 上架检查清单 |
| `/changelog` | 变更日志生成 |
| `/patch-notes` | 补丁说明 |
| `/hotfix` | 紧急修复流程 |

### 团队编排（多 Agent 协作单一功能）

| 命令 | 涉及 Agent |
|------|-----------|
| `/team-combat` | game-designer + gameplay-programmer + ai-programmer + sound-designer |
| `/team-narrative` | narrative-director + writer + world-builder + sound-designer |
| `/team-ui` | ux-designer + ui-programmer + technical-artist |
| `/team-release` | release-manager + qa-lead + devops-engineer |
| `/team-polish` | performance-analyst + qa-tester + technical-artist |
| `/team-audio` | audio-director + sound-designer + engine-programmer |
| `/team-level` | level-designer + technical-artist + gameplay-programmer |

---

## 设计理论框架

### MDA Framework（核心）

游戏设计的 Mechanics-Dynamics-Aesthetics 分析：

| 美学类型 | 描述 | 对应体验 |
|---------|------|---------|
| Sensation | 感官愉悦 | 视觉/音效冲击 |
| Fantasy | 角色扮演 | 成为他人 |
| Narrative | 戏剧性 | 故事推进 |
| Challenge | 掌控感 | 技能成长 |
| Fellowship | 社交 | 合作/竞争 |
| Discovery | 探索 | 发现新事物 |
| Expression | 创造力 | 自我表达 |
| Submission | 放松 | 轻松消遣 |

### 愿景表达框架

每个游戏项目必须回答：

1. **核心幻想**: 玩家在这个游戏里能做什么别处做不到的？（情感承诺，不是功能列表）
2. **独特钩子**: "它像 [对标游戏]，但也 [独特点]"，如果"但也"不能引发好奇心，钩子需要改
3. **目标美学排序**: 按优先级排列上面 8 个 MDA 美学类型
4. **情感弧线**: 一个游戏会话中玩家的情感变化地图
5. **反支柱**: 这个游戏**不是**什么？每个"不"保护一个"是"

### 其他设计工具

- **自我决定理论 (SDT)**: 自主感 / 胜任感 / 归属感 → 玩家动机
- **心流设计**: 挑战-技能平衡 → 玩家沉浸
- **Bartle 玩家类型**: 成就者/探索者/社交者/杀手 → 受众定位

---

## 编码标准

- 公共 API 必须有文档注释
- 每个系统必须有架构决策记录（ADR）在 `docs/architecture/`
- **游戏数值必须外部化**（配置文件驱动，禁止硬编码 magic number）
- 公共方法必须可单元测试（依赖注入优于单例）
- 提交必须引用相关设计文档或任务 ID
- **验证驱动开发**: 先写测试再实现；UI 变更用截图验证

## 设计文档标准

每个机制的设计文档（`design/gdd/`）必须包含 8 个章节：

1. **Overview** — 一段概要
2. **Player Fantasy** — 目标感受和体验
3. **Detailed Rules** — 无歧义的机制规则
4. **Formulas** — 所有数学公式和变量定义
5. **Edge Cases** — 异常情况处理
6. **Dependencies** — 依赖的其他系统
7. **Tuning Knobs** — 可调参数清单
8. **Acceptance Criteria** — 可测试的验收条件

---

## 项目结构模板

```
my-game/
├── CLAUDE.md              # 主配置
├── .claude/
│   ├── settings.json      # Hooks、权限、安全规则
│   ├── agents/            # Agent 定义（MD + YAML frontmatter）
│   ├── skills/            # Slash commands（每个命令一个子目录）
│   ├── hooks/             # Hook 脚本（bash，跨平台）
│   └── rules/             # 路径范围编码标准
├── src/                   # 游戏源代码
├── assets/                # 美术、音频、VFX、Shader、数据文件
├── design/                # GDD、叙事文档、关卡设计
├── docs/                  # 技术文档和 ADR
├── tests/                 # 测试套件
├── tools/                 # 构建和管线工具
├── prototypes/            # 一次性原型（隔离于 src/）
└── production/            # Sprint 计划、里程碑、发布跟踪
```

---

## 快速开始

### 前置条件

- Git
- Claude Code (`npm install -g @anthropic-ai/claude-code`)
- 推荐: jq（Hook 验证）、Python 3（JSON 验证）

### 两种启动方式

**方式 1: 克隆模板仓库**

```bash
git clone https://github.com/Donchitos/Claude-Code-Game-Studios.git my-game
cd my-game
claude
# 然后输入 /start
```

**方式 2: 在 Antigravity 中直接 vibe（推荐）**

不需要克隆仓库。直接用本 Skill 的框架，告诉 Claude 你想做什么游戏：

1. 描述你的游戏创意（"我想做一个 XXX 风格的小游戏"）
2. Claude 会以 Creative Director 身份引导你完成：
   - 核心幻想 → 独特钩子 → MDA 美学排序
   - 引擎选择（Godot / Unity / Unreal / 纯 Web）
   - 项目脚手架搭建
3. 然后以 Game Designer 身份产出 GDD
4. 最后以 Lead Programmer 身份编码实现

### 引擎选择指南

| 场景 | 推荐引擎 |
|------|---------|
| 2D 像素风 / 小游戏 | **Godot 4**（轻量、GDScript 上手快）|
| 纯 Web 小游戏 | **HTML5 + Canvas/Phaser**（零安装，浏览器直接玩）|
| 3D 手游 / 中型项目 | **Unity**（C#、跨平台强）|
| 3A / 写实 3D | **Unreal Engine 5**（C++/Blueprint、Nanite/Lumen）|

---

## 使用场景

本技能适合以下场景：
- 🎮 Vibe 一个小游戏（Web / 移动端 / 桌面端）
- 🏗️ 搭建游戏项目脚手架
- 📋 编写 GDD（游戏设计文档）
- ⚖️ 数值平衡和经济系统设计
- 🧪 游戏系统原型验证
- 🚀 游戏发布和上架准备

---

## 参考链接

- 源码仓库: https://github.com/Donchitos/Claude-Code-Game-Studios
- 许可证: MIT
