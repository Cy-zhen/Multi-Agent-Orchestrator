# chenglou/pretext 仓库深度分析

## 📌 概览

| 属性 | 值 |
|------|-----|
| **仓库** | [chenglou/pretext](https://github.com/chenglou/pretext) |
| **作者** | Cheng Lou（React 社区名人，react-motion / reason-react 作者） |
| **⭐ Stars** | 26.3k |
| **Forks** | 1.2k |
| **语言** | TypeScript 89.8%, HTML 10.2% |
| **许可证** | MIT |
| **版本** | 0.0.3 (早期阶段) |
| **包名** | `@chenglou/pretext` |
| **Commits** | 273 |
| **贡献者** | 6 人 |

---

## 🎯 它解决什么问题？

**一句话总结**：纯 JS/TS 的多行文本测量与布局库，绕过 DOM reflow，实现高性能文本排版。

### 核心痛点

Web 开发中，测量文本高度（`getBoundingClientRect`, `offsetHeight`）会触发 **layout reflow**，这是浏览器最昂贵的操作之一。当 UI 组件各自独立进行 DOM 读写交错时，浏览器可能反复重排整个文档。

### Pretext 的解法

采用 **两阶段模型**：

```
prepare(text, font)  →  一次性：分词、规则应用、Canvas 测量、缓存宽度
layout(prepared, width, lineHeight)  →  纯算术：在缓存宽度上做加减，零 DOM 操作
```

> [!IMPORTANT]
> `layout()` **始终保持纯算术运算**，这是整个项目的核心架构不变量。所有优化都围绕这个约束展开。

---

## 🏗️ 架构分析

### 源码结构

```
src/
├── layout.ts          # 核心布局引擎：prepare(), layout(), layoutWithLines() 等公开 API
├── layout.test.ts     # 单元测试
├── analysis.ts        # 文本分析：Unicode 分段、空白处理、胶水规则
├── bidi.ts            # 双向文本 (BiDi) 处理，源自 pdf.js 的设计
├── line-break.ts      # 行断裂逻辑：CJK 禁则处理、soft hyphen 等
├── measurement.ts     # Canvas measureText 封装、缓存层、浏览器 quirks 修正
├── test-data.ts       # 测试数据
└── text-modules.d.ts  # 类型声明
```

### 关键设计决策

| 决策 | 选择 | 为什么 |
|------|------|--------|
| 测量方式 | Canvas `measureText()` | 直接走浏览器字体引擎，避免 DOM 布局 |
| 热路径 | 纯算术 | `layout()` 绝不接触 DOM |
| 分段方式 | `Intl.Segmenter` | 浏览器原生 Unicode 分段，不自己实现 |
| 缓存粒度 | 按 segment（词/运行单元）| 非整行，非单字符 |
| BiDi 处理 | 基于 pdf.js 的设计 | 成熟方案 |
| 浏览器差异 | prepare 阶段的预处理 + 微容差 | 不在 layout 阶段修正 |

### 工程特色

- **极其严肃的准确性测试体系**：
  - 跨浏览器 accuracy check (Chrome/Firefox/Safari)
  - 语料库 (corpus) 扫描验证
  - 基准测试 snapshot
  - Gatsby 真实页面验证
  - pre-wrap 专用 oracle 测试
- 配备 `AGENTS.md` + `CLAUDE.md` — 专为 AI 辅助开发优化
- 使用 `oxlint` + TypeScript 6.0 进行代码质量控制

---

## 📊 性能数据

基于仓库内 benchmark snapshot（500 段文本批处理）：

| 阶段 | 耗时 | 说明 |
|------|------|------|
| `prepare()` | ~19ms | 一次性预计算（分段+测量+缓存） |
| `layout()` | ~0.09ms | 纯算术热路径 |

> `layout()` 比 `prepare()` 快约 **211 倍**，这正是设计目标：resize 时只需调 `layout()`。

---

## 🌍 多语言支持深度

这不是简单的"支持多语言"，而是经过**系统化的语料库级别验证**：

| 语言 | 状态 | 备注 |
|------|------|------|
| 英文/拉丁 | ✅ 干净 | 基础用例 |
| 中文 | 🟡 活跃优化 | Songti SC vs PingFang SC 字体差异；Chrome 有窄宽度正向误差 |
| 日文 | 🟡 金丝雀 | 假名迭代标记处理；标点压缩边界 |
| 韩文 | ✅ 干净 | 跨字体矩阵验证通过 |
| 阿拉伯文 | 🟡 接近完成 | RTL + 标点粘黏规则；粗语料库已清理 |
| 泰文 | ✅ 干净 | ASCII 引号胶水处理 |
| 高棉文 | ✅ 干净 | 保留零宽分隔符 |
| 缅甸文 | 🔴 未完全解决 | Chrome/Safari 分歧；东南亚前沿 |
| 乌尔都文 | ⏸️ 搁置 | Nastaliq/Naskh 成形差异 |
| 印地文 | ✅ 干净 | 跨字体验证通过 |
| 希伯来文 | ✅ 干净 | 跨字体验证通过 |
| Emoji | ✅ 修正 | Chrome/Firefox macOS 的 Canvas/DOM 宽度差异已修正 |
| 混合文本 | 🟡 接近完成 | URL、emoji ZWJ、soft-hyphen 等边界情况 |

---

## 🔌 API 设计

### Use Case 1: 快速高度测量（不触 DOM）

```ts
import { prepare, layout } from '@chenglou/pretext'

const prepared = prepare('AGI 春天到了. بدأت الرحلة 🚀', '16px Inter')
const { height, lineCount } = layout(prepared, maxWidth, 20)
```

### Use Case 2: 手动行级布局（Canvas/SVG/WebGL 渲染）

```ts
import { prepareWithSegments, layoutWithLines, walkLineRanges, layoutNextLine } from '@chenglou/pretext'

// 固定宽度排版
const { lines } = layoutWithLines(prepared, 320, 26)

// 获取行宽（用于 shrink-wrap）
walkLineRanges(prepared, 320, line => { ... })

// 逐行可变宽度布局（如文字环绕图片）
layoutNextLine(prepared, cursor, width)
```

---

## 💡 作者的深层思考

来自 `thoughts.md` 的关键洞察：

> [!NOTE]
> **"如果用户层有更好的文本控制能力，80% 的 CSS 规范可以避免。"**

作者认为：
1. **当前 web UI 被困在几种固定范式**：着陆页、博客、SaaS Dashboard、移动 2-3 个矩形
2. **CSS 的便利性正在被侵蚀**：CSS 表达力越强 → CSS 性能越差；AI 减少了硬编码 CSS 配置的需求
3. **浏览器竞争困境**：规范太庞大，新引擎无法竞争。解法是 **把更多能力移到用户态**
4. **"可验证软件的成本将趋向于 0"** — 暗示 AI 辅助开发是核心迭代方法

---

## 🏷️ 实际应用场景

1. **虚拟化/遮挡列表** — 不再需要猜测行高，精确知道每项高度
2. **Masonry 布局** — JS 驱动的灵活布局，无需 CSS hack
3. **AI 辅助验证** — 开发时验证按钮标签是否溢出，无需浏览器
4. **防止布局偏移** — 新文本加载时精确重锚点滚动位置
5. **Canvas/SVG/WebGL 渲染** — 脱离 DOM 的完整文本排版
6. **聊天气泡 shrink-wrap** — 多行文本的最紧容器宽度计算

---

## 🔍 研究方法论亮点

项目的 `RESEARCH.md` 展示了一种**极其严谨的工程研究方法**：

1. **「什么被保留/什么被丢弃」记录法** — 每个方向都记录了保留和拒绝的原因
2. **语料库驱动** — 用真实多语言文本做回归测试（日文小说《罗生门》、中文《祝福》、阿拉伯散文等）
3. **跨浏览器的三方验证** — Chrome/Safari/Firefox 分别做准确性扫描
4. **"金丝雀"模式** — 特定语言的特定文本作为回归检测的哨兵
5. **拒绝过度工程** — 明确记录"什么看起来诱人但实际有害"的方案

---

## 📈 项目成熟度评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 创新性 | ⭐⭐⭐⭐⭐ | 填补了 web 平台一个关键缺失 |
| 工程质量 | ⭐⭐⭐⭐⭐ | 测试体系、文档、研究日志极其优秀 |
| API 设计 | ⭐⭐⭐⭐⭐ | 简洁、渐进复杂度、职责清晰 |
| 成熟度 | ⭐⭐⭐ | v0.0.3，还在活跃迭代中 |
| 社区热度 | ⭐⭐⭐⭐⭐ | 26k+ stars，显然击中了痛点 |
| 生产可用性 | ⭐⭐⭐⭐ | 核心功能已经过大量验证，但版本号仍是 0.x |

---

## 🧬 与作者背景的关联

Cheng Lou 是 React 生态的重要人物：
- **react-motion** — React 动画库
- **ReasonML / ReScript** — Facebook 的 ML 家族语言，React 的类型安全变体
- 曾在 **Meta/Facebook** 工作

Pretext 延续了他一贯的风格：**找到一个被忽视的底层问题，用优雅的抽象解决它**。这次的目标是 web 文本布局——一个看似"已解决"但实际充满隐痛的领域。

---

## 🛠️ 前端开发参考手册

> 以下内容提炼自 Pretext 的设计思想和实现，可直接用于指导前端开发。

### 1. 性能模式：预计算/热路径分离

Pretext 最核心的架构思想——**把昂贵操作和频繁操作分离**——是一个通用的前端性能模式：

```
❌ 每次 resize 都重新测量所有文本高度（触发 reflow）
✅ 初始化时预计算（prepare），resize 时纯算术（layout）
```

**应用到你的项目中：**

| 场景 | 预计算（一次性） | 热路径（频繁） |
|------|-----------------|----------------|
| 虚拟列表 | 预测量每项高度 | 滚动时查表定位 |
| 动画 | 预计算关键帧/贝塞尔 | 每帧插值 |
| 响应式布局 | 预解析断点规则 | resize 时快速匹配 |
| 搜索 | 预建索引 | 输入时查询索引 |

### 2. 避免 Layout Thrashing（布局抖动）

Pretext 存在的根本原因就是避免 DOM 读写交错。前端开发中的黄金法则：

```ts
// ❌ 读写交错 — 每次读都触发 reflow
elements.forEach(el => {
  const h = el.offsetHeight     // 读 → 强制 reflow
  el.style.height = h + 10 + 'px'  // 写
})

// ✅ 批量读，批量写
const heights = elements.map(el => el.offsetHeight)  // 批量读
elements.forEach((el, i) => {
  el.style.height = heights[i] + 10 + 'px'           // 批量写
})
```

**高级技巧（来自 Pretext 的思路）：**
- 用 `Canvas.measureText()` 替代 DOM 测量来获取文本宽高
- 用 `requestAnimationFrame` 将写操作推迟到下一帧
- 对文本密集型 UI（聊天、编辑器），考虑用 Pretext 消除 DOM 测量

### 3. 文本处理最佳实践

从 Pretext 的多语言研究中提炼的实用知识：

```ts
// ✅ 用 Intl.Segmenter 做 Unicode 安全的分词（而不是 split(' ')）
const segmenter = new Intl.Segmenter('zh', { granularity: 'word' })
const words = [...segmenter.segment('AGI春天到了')].map(s => s.segment)
// → ['AGI', '春天', '到', '了']

// ✅ 用 Intl.Segmenter 做字素切分（处理 emoji 等）
const graphemes = new Intl.Segmenter('en', { granularity: 'grapheme' })
const chars = [...graphemes.segment('👨‍👩‍👧‍👦hello')].map(s => s.segment)
// → ['👨‍👩‍👧‍👦', 'h', 'e', 'l', 'l', 'o']  (ZWJ emoji 是一个字素)
```

**字体相关踩坑点（来自 Pretext RESEARCH.md）：**
- ⚠️ **`system-ui` 在 macOS 上不可靠** — Canvas 和 DOM 会解析到不同的 SF Pro 变体，导致测量不一致。生产环境用命名字体
- ⚠️ **Emoji 在 Chrome/Firefox 的 Canvas 中可能比 DOM 中更宽** — 如果你依赖 `measureText` 测量含 emoji 文本，注意浏览器差异
- ✅ 标点符号应与前一个词合并测量（不独立拆分），否则小数累积会导致行尾误差

### 4. 缓存策略模式

Pretext 的缓存设计值得借鉴：

```ts
// Pretext 的缓存层次：
// 1. 按 segment (词/运行单元) 缓存宽度 — 粒度合适
// 2. 懒计算派生值 (emoji 计数、字素宽度) — 不用不算
// 3. 提供 clearCache() — 允许释放

// 在你的项目中：
class MeasurementCache {
  private cache = new Map<string, number>()
  
  getWidth(text: string, font: string): number {
    const key = `${font}|${text}`
    let w = this.cache.get(key)
    if (w === undefined) {
      w = this.ctx.measureText(text).width  // 仅首次测量
      this.cache.set(key, w)
    }
    return w
  }
  
  clear() { this.cache.clear() }  // 字体切换时释放
}
```

### 5. 可直接使用 Pretext 的场景

在以下前端场景中，可以考虑直接引入 `@chenglou/pretext`：

| 场景 | 用法 | 收益 |
|------|------|------|
| **虚拟滚动列表** | `prepare` + `layout` 预算每项高度 | 告别 `estimatedItemSize` 猜测 |
| **聊天气泡** | `walkLineRanges` 算最紧宽度 | 完美 shrink-wrap |
| **文本截断** | `layoutWithLines` 获取行信息 | 精确 N 行截断 + ellipsis |
| **Canvas 编辑器** | `layoutNextLine` 逐行排版 | 脱 DOM 的完整文本渲染 |
| **CLS 优化** | 服务端/Worker 预算高度 | 消除布局偏移 |
| **自适应字号** | `walkLineRanges` 二分搜索合适字号 | 文字充满容器 |

### 6. 工程实践参考

Pretext 仓库本身的工程实践也值得学习：

- **AGENTS.md + CLAUDE.md** — 为 AI 辅助开发量身定制的项目说明文件
- **RESEARCH.md** — "保留/丢弃"双列记录法，适合任何需要探索的技术方向
- **accuracy snapshot** — 跨浏览器回归快照，不只是"通过/失败"的测试
- **corpus 驱动测试** — 用真实数据（非构造的 fixture）做验证
- **oxlint + TypeScript 6.0** — 现代 lint + 类型检查工具链组合

---

*分析时间: 2026-04-01 · 前端参考章节追加于同日*
