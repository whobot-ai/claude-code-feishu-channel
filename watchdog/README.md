# 🛡️ Feishu Watchdog — 飞书服务看门狗

自动监控飞书服务进程，崩溃后自动重启，实现 7×24 无人值守运行。

## 适用场景

| 运行模式 | 是否需要看门狗 | 说明 |
|----------|:--------------:|------|
| **Channel 插件**（`claude --dangerously-load-development-channels`） | ❌ 不需要 | Claude Code 管理插件生命周期 |
| **Standalone 模式**（独立运行） | ✅ 建议启用 | 无父进程兜底，需外部守护 |

## 快速开始

### 1. 确保服务器脚本会写 PID 文件

你的服务器需要在启动时将自身 PID 写入 `~/.claude/channels/feishu/standalone.pid`：

```typescript
import { writeFileSync } from 'fs'
import { join } from 'path'
import { homedir } from 'os'

const STATE_DIR = join(homedir(), '.claude', 'channels', 'feishu')
writeFileSync(join(STATE_DIR, 'standalone.pid'), String(process.pid))
```

### 2. 启动看门狗

```bash
FEISHU_SERVER_SCRIPT="$HOME/feishu-standalone-server.ts" \
  bash watchdog/watchdog.sh
```

### 3. 验证自愈

```bash
# 模拟崩溃
kill $(cat ~/.claude/channels/feishu/standalone.pid)
# 等待 ~30 秒 → 看门狗自动重启服务
tail -f ~/.claude/channels/feishu/watchdog.log
```

## 配置

| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `FEISHU_SERVER_SCRIPT` | *(必需)* | 要监控的服务器脚本路径 |
| `FEISHU_STATE_DIR` | `~/.claude/channels/feishu` | 状态文件目录 |
| `CHECK_INTERVAL` | `30` | 检查间隔（秒） |
| `MAX_RESTART_BACKOFF` | `300` | 最大退避时间（秒） |
| `FEISHU_RUNTIME` | `bun run` | 运行时命令 |

## Windows 开机自启

```bat
@echo off
start "FeishuWatchdog" /MIN bash -c ^
  "FEISHU_SERVER_SCRIPT=%USERPROFILE%\.claude\feishu-standalone-server.ts bash %USERPROFILE%\path\to\watchdog\watchdog.sh"
```

## 工作原理

```
看门狗启动 → 检查服务器 PID 文件
   ├─ 存活 → 等待 30s → 再次检查
   └─ 死亡 → 退避等待 → 重启服务器 → 确认启动 → 等待 30s
```

- **单例守卫**：`mkdir` 原子锁，防止多个看门狗实例同时运行
- **指数退避**：连续失败后等待时间递增（30s → 60s → 90s → ... → 300s）
- **跨平台**：Windows 用 `tasklist`，Linux/macOS 用 `kill -0`
- **优雅退出**：`Ctrl+C` 或 `kill` 自动清理锁文件

## 故障排查

| 问题 | 原因 | 解决 |
|------|------|------|
| 看门狗反复重启 | 服务器未写 PID 文件 | 检查 `~/.claude/channels/feishu/standalone.pid` 是否存在 |
| 启动后立即退出 | 已有实例在运行 | 删除 `watchdog.lock` 目录 |
| `Permission denied` | 权限不足 | `chmod +x watchdog.sh` |
