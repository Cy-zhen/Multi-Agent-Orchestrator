# 组件质量清单

## 摘要
每个组件实现完成后，用此清单自查。

## 检查项

### 状态覆盖
- [ ] Loading 状态（骨架屏或 Spinner）
- [ ] Empty 状态（无数据时友好提示）
- [ ] Error 状态（ErrorBoundary 或 fallback UI）
- [ ] Success 状态（正常数据展示）

### 响应式
- [ ] 手机（375px）布局正常
- [ ] 平板（768px）布局正常
- [ ] 桌面（1200px+）布局正常

### 可访问性
- [ ] 交互元素有 `aria-label` 或可见文字
- [ ] 键盘可导航（Tab / Enter / Escape）
- [ ] 颜色对比度满足 WCAG AA（4.5:1）

### 代码质量
- [ ] Props 有 TypeScript 类型定义
- [ ] 无 `console.log` 残留
- [ ] 无 `any` 类型
- [ ] 组件有 `displayName`（for DevTools）
