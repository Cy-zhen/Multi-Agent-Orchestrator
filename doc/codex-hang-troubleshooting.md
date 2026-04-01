# Codex 挂起排查与修复报告

**日期**: 2026-03-31  
**状态**: ✅ 已修复

---

## 根本原因

在 `--ag` (Antigravity) 模式下 `auto-run` 执行到需要 Codex/Gemini 的阶段时：

1. **stdout 被 `$()` 完全吞掉** — `output=$(codex exec ...)` 会捕获所有输出，Antigravity 看不到任何进度
2. **没有超时机制** — 如果 Codex API 慢或网络问题，脚本会无限等待
3. **stdin 未隔离** — 子 shell 中 Codex 可能尝试读取 stdin（虽然 `--full-auto` 理论上不需要），无 TTY 环境下可能异常

这三个因素叠加导致 Antigravity 判断进程"挂起"。

## 修复内容

### 1. 新增 `run_with_timeout()` 函数（macOS 兼容）

macOS 没有 `timeout` 命令，实现了纯 bash 的超时控制：
- 默认 300 秒（5 分钟）超时，可通过 `CLI_TIMEOUT` 环境变量调整
- 每 30 秒打印心跳 `⏳ 已运行 Xs / 300s ...`（Antigravity 能看到进度）
- 超时后先 SIGTERM，2 秒后 SIGKILL

### 2. 所有 Codex/Gemini 调用增加保护

| 修改位置 | 改动 |
|---------|------|
| `run_with_fallback()` codex 分支 | `+ run_with_timeout` `+ -C $PROJECT_DIR` `+ < /dev/null` |
| `run_with_fallback()` gemini 分支 | `+ run_with_timeout` `+ < /dev/null` |
| `cmd_onboard()` 扫描 | `+ run_with_timeout` `+ -C $PROJECT_DIR` `+ < /dev/null` |
| IMPLEMENTATION 并行 FE | `+ run_with_timeout` `+ < /dev/null` |
| IMPLEMENTATION 并行 BE | `+ run_with_timeout` `+ -C $PROJECT_DIR` `+ < /dev/null` |

### 3. 超时退出码检测

```bash
if [[ $exit_code -eq 137 || $exit_code -eq 143 ]]; then
  echo "✗ Codex 超时被终止"
fi
```

## 使用方式

```bash
# 默认 5 分钟超时
bash ~/.claude/orchestrator.sh --ag auto-run /path/to/project

# 自定义超时（10 分钟）
CLI_TIMEOUT=600 bash ~/.claude/orchestrator.sh --ag auto-run /path/to/project
```
