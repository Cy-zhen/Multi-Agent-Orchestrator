# React 编码规范

## 核心规则

### 组件设计
- 优先使用 Server Components，只在需要交互时用 `'use client'`
- 组件单一职责，超过 200 行必须拆分
- Props 必须用 TypeScript interface 定义，不用 `any`
- 使用 `forwardRef` 暴露 DOM 引用给父组件

### 状态管理
- 局部状态用 `useState` / `useReducer`
- 全局客户端状态用 Zustand
- 服务端数据用 TanStack React Query（不要存到全局 store）
- 避免 prop drilling 超过 3 层，使用 Context 或 Zustand

### 性能
- 列表渲染必须有稳定的 `key`（不用 index）
- 大列表用虚拟滚动（@tanstack/react-virtual）
- 图片用 `next/image` 自动优化
- 动态导入大组件 `dynamic(() => import(...))`

### 样式
- 使用 Tailwind CSS 4 utility classes
- 复杂样式用 `cn()` 合并（clsx + tailwind-merge）
- 响应式断点：`sm:375` / `md:768` / `lg:1200`
- 暗色模式用 `dark:` 变体

### 禁止
- ❌ `console.log`（调试完必须删除）
- ❌ `// @ts-ignore` 或 `// @ts-expect-error`
- ❌ 内联样式 `style={{}}`
- ❌ `useEffect` 用于数据获取（用 React Query）
