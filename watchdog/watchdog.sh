#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# feishu-watchdog.sh — 飞书服务看门狗
#
# 功能：
#   1. 监控指定的飞书服务进程是否存活
#   2. 进程死亡 → 自动重启
#   3. 默认检查间隔：30 秒
#   4. 跨平台单例守卫（mkdir 原子锁）
#
# 用法：
#   bash watchdog.sh                                    # 使用默认配置
#   FEISHU_SERVER_SCRIPT=./my-server.ts bash watchdog.sh  # 自定义服务器脚本
#   CHECK_INTERVAL=60 bash watchdog.sh                    # 自定义检查间隔
#
# 环境变量：
#   FEISHU_SERVER_SCRIPT  要监控的服务器脚本路径（必需）
#   FEISHU_STATE_DIR      状态文件目录（默认 ~/.claude/channels/feishu）
#   CHECK_INTERVAL        检查间隔秒数（默认 30）
#   MAX_RESTART_BACKOFF   最大重启退避秒数（默认 300）
#   FEISHU_RUNTIME        运行时命令（默认 bun run）
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# ── 配置 ──────────────────────────────────────────────────────────────────────
HOME_DIR="${HOME:-$USERPROFILE}"
STATE_DIR="${FEISHU_STATE_DIR:-$HOME_DIR/.claude/channels/feishu}"
SERVER_SCRIPT="${FEISHU_SERVER_SCRIPT:-}"
RUNTIME="${FEISHU_RUNTIME:-bun run}"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
MAX_RESTART_BACKOFF="${MAX_RESTART_BACKOFF:-300}"

PID_FILE="$STATE_DIR/standalone.pid"
LOCK_DIR="$STATE_DIR/watchdog.lock"
LOG_FILE="$STATE_DIR/watchdog.log"

# ── 参数验证 ──────────────────────────────────────────────────────────────────
if [ -z "$SERVER_SCRIPT" ]; then
  echo "[ERROR] FEISHU_SERVER_SCRIPT is required. Example:"
  echo "  FEISHU_SERVER_SCRIPT=~/feishu-standalone-server.ts bash watchdog.sh"
  echo "  Or set it in your environment."
  exit 1
fi

mkdir -p "$STATE_DIR"

# ── 日志 ──────────────────────────────────────────────────────────────────────
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WATCHDOG] $*" | tee -a "$LOG_FILE"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 单例守卫：使用 mkdir 原子操作确保只有一个 watchdog 实例在运行
# ═══════════════════════════════════════════════════════════════════════════════
acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ > "$LOCK_DIR/pid"
    return 0
  fi

  # 锁已存在，检查持有者是否存活（Windows: 用 tasklist 代替 kill -0）
  local locker_pid
  locker_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
  if [ -n "$locker_pid" ] && tasklist 2>/dev/null | grep -qE "^\S+\s+$locker_pid\s"; then
    log "Watchdog already running (PID=$locker_pid), exiting."
    exit 0
  fi

  # 持有者已死，清除残留锁
  log "Lock holder PID=$locker_pid is dead, removing stale lock"
  rm -rf "$LOCK_DIR"
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ > "$LOCK_DIR/pid"
    return 0
  fi
  log "ERROR: Cannot acquire lock directory"
  exit 1
}

release_lock() {
  rm -rf "$LOCK_DIR"
  log "Watchdog stopped."
}

# ── 进程存活检查（跨平台：Windows 用 tasklist，Unix 用 kill -0）──────────────
is_alive() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$pid" ]; then
      # Windows: tasklist
      if command -v tasklist >/dev/null 2>&1; then
        tasklist 2>/dev/null | grep -qE "^\S+\s+$pid\s" && return 0
      # Unix: kill -0
      else
        kill -0 "$pid" 2>/dev/null && return 0
      fi
    fi
  fi
  return 1
}

# ── 启动服务器 ────────────────────────────────────────────────────────────────
start_server() {
  log "Starting server: $SERVER_SCRIPT"
  local server_dir
  server_dir=$(dirname "$SERVER_SCRIPT")

  # 清除旧 PID 文件（服务器会自己写新的）
  rm -f "$PID_FILE"

  # 后台启动
  cd "$server_dir"
  $RUNTIME "$SERVER_SCRIPT" >> "$STATE_DIR/standalone.log" 2>&1 &
  log "Launched process (shell PID=$!)"

  # 等待服务器写入 PID 文件（最多等待 15 秒）
  local waited=0
  while [ $waited -lt 15 ]; do
    sleep 1
    waited=$((waited + 1))
    if [ -f "$PID_FILE" ]; then
      local real_pid
      real_pid=$(cat "$PID_FILE" 2>/dev/null)
      if [ -n "$real_pid" ]; then
        if command -v tasklist >/dev/null 2>&1; then
          tasklist 2>/dev/null | grep -qE "^\S+\s+$real_pid\s" || continue
        else
          kill -0 "$real_pid" 2>/dev/null || continue
        fi
        log "Server startup confirmed (PID=$real_pid, waited ${waited}s)"
        return 0
      fi
    fi
  done

  log "ERROR: Server failed to start within ${waited}s"
  return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# 主循环
# ═══════════════════════════════════════════════════════════════════════════════

main() {
  acquire_lock
  trap release_lock EXIT

  log "=============================================="
  log "Watchdog started (PID=$$)"
  log "Monitoring: $SERVER_SCRIPT"
  log "State dir:  $STATE_DIR"
  log "Check interval: ${CHECK_INTERVAL}s"
  log "Max backoff: ${MAX_RESTART_BACKOFF}s"
  log "=============================================="

  local consecutive_failures=0

  while true; do
    if is_alive; then
      consecutive_failures=0
    else
      consecutive_failures=$((consecutive_failures + 1))
      local backoff=$((CHECK_INTERVAL * consecutive_failures))
      if [ $backoff -gt "$MAX_RESTART_BACKOFF" ]; then
        backoff=$MAX_RESTART_BACKOFF
      fi

      log "Server is DOWN (failure #$consecutive_failures). Restarting in ${backoff}s..."
      sleep "$backoff"

      if ! is_alive; then
        start_server || log "CRITICAL: Server startup failed after $consecutive_failures attempts"
      fi
    fi

    sleep "$CHECK_INTERVAL"
  done
}

main "$@"
