#!/bin/sh
# ============================================================================
# lucky-star-mcp — 本地 MCP agent 安装/管理脚本
#
# 把 LuckyStar/LS_KTool 的 MCP 服务器注册到本机 agent（Claude Code / Cursor /
# Claude Desktop），并管理服务器进程与 adb 转发。
#
# 用法:
#   ./install.sh               # 一次性安装: 建 venv + 装依赖 + 注册 agent + 启动
#   ./install.sh install       # 只做: venv + 依赖 + 注册 agent（不启动）
#   ./install.sh start         # 启动 MCP 服务器 + adb forward
#   ./install.sh stop          # 停止 MCP 服务器
#   ./install.sh status        # 查看状态
#   ./install.sh uninstall     # 从各 agent 配置中移除 luckystar 注册
#
# 环境变量:
#   ANDROID_HOST   MCP 服务器连接设备的地址（默认 127.0.0.1，配合 adb forward）
# ============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PY_DIR="$SCRIPT_DIR/python"
VENV_DIR="$SCRIPT_DIR/.venv"
LOG_DIR="$SCRIPT_DIR/logs"
SERVER_PID_FILE="$LOG_DIR/server.pid"
SERVER_LOG="$LOG_DIR/server.log"
MCP_URL="http://127.0.0.1:14447/mcp"
SERVER_NAME="luckystar"

# ---------------------------------------------------------------- 工具函数

find_python() {
    # LuckyStarMcp.py + pydantic 需要 Python >= 3.12（typing.TypedDict 兼容性）
    for c in python3 python python3.14 python3.13 python3.12; do
        if command -v "$c" >/dev/null 2>&1; then
            v="$("$c" -c 'import sys; print(sys.version_info[0] * 100 + sys.version_info[1])' 2>/dev/null || echo 0)"
            if [ "$v" -ge 312 ]; then echo "$c"; return; fi
        fi
    done
    echo python
}
PY="$(find_python)"

venv_python() {
    if [ -x "$VENV_DIR/bin/python" ]; then echo "$VENV_DIR/bin/python"
    elif [ -x "$VENV_DIR/Scripts/python.exe" ]; then echo "$VENV_DIR/Scripts/python.exe"
    else echo ""; fi
}
VPY="$(venv_python)"

to_win_path() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1" 2>/dev/null || echo "$1"
    else echo "$1"; fi
}

# ---------------------------------------------------------------- 安装

setup() {
    echo "[*] Python 环境: $VENV_DIR"
    if [ -z "$VPY" ]; then
        "$PY" -m venv "$VENV_DIR"
        VPY="$(venv_python)"
    fi
    "$VPY" -m pip install -q --upgrade pip 2>/dev/null || true
    "$VPY" -m pip install -q -r "$SCRIPT_DIR/requirements.txt"
    echo "[+] 依赖已安装"
}

# 在单个 agent 配置文件里合并注册 luckystar（使用 venv python 安全改 JSON）
register_in_file() {
    local cfg="$1" name="$2" url="$3"
    local win_cfg="$(to_win_path "$cfg")"
    if [ -f "$cfg" ]; then
        cp "$cfg" "$cfg.bak.$(date +%s)" 2>/dev/null || true
    fi
    "$VPY" - "$win_cfg" "$name" "$url" <<'PYEOF'
import json, sys
path, name, url = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except Exception as e:
    print(f"[!] 无法解析 {path}: {e}", file=sys.stderr)
    sys.exit(1)
if not isinstance(data, dict):
    data = {}
servers = data.setdefault('mcpServers', {})
servers[name] = {"type": "http", "url": url, "enabled": True}
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write('\n')
print(f"[+] 已注册 '{name}' -> {url}  于 {path}")
PYEOF
}

# 从配置文件移除 luckystar
unregister_in_file() {
    local cfg="$1" name="$2"
    local win_cfg="$(to_win_path "$cfg")"
    if [ ! -f "$cfg" ]; then return 0; fi
    cp "$cfg" "$cfg.bak.$(date +%s)" 2>/dev/null || true
    "$VPY" - "$win_cfg" "$name" <<'PYEOF'
import json, sys
path, name = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
if isinstance(data, dict) and 'mcpServers' in data:
    data['mcpServers'].pop(name, None)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print(f"[-] 已移除 '{name}' 于 {path}")
PYEOF
}

register_agents() {
    echo "[*] 注册到本机 agent ..."
    # Claude Code
    if [ -f "$HOME/.claude.json" ] || [ -f "$HOME/.config/Claude/claude_desktop_config.json" ]; then
        register_in_file "$HOME/.claude.json" "$SERVER_NAME" "$MCP_URL"
    fi
    # Claude Desktop (mac)
    register_in_file "$HOME/Library/Application Support/Claude/claude_desktop_config.json" "$SERVER_NAME" "$MCP_URL" 2>/dev/null || true
    # Claude Desktop (windows)
    register_in_file "$HOME/AppData/Roaming/Claude/claude_desktop_config.json" "$SERVER_NAME" "$MCP_URL" 2>/dev/null || true
    # Cursor
    mkdir -p "$HOME/.cursor"
    register_in_file "$HOME/.cursor/mcp.json" "$SERVER_NAME" "$MCP_URL"
    echo "[+] 注册完成"
}

uninstall_agents() {
    echo "[*] 从本机 agent 移除注册 ..."
    unregister_in_file "$HOME/.claude.json" "$SERVER_NAME"
    unregister_in_file "$HOME/.cursor/mcp.json" "$SERVER_NAME"
    unregister_in_file "$HOME/Library/Application Support/Claude/claude_desktop_config.json" "$SERVER_NAME" 2>/dev/null || true
    unregister_in_file "$HOME/AppData/Roaming/Claude/claude_desktop_config.json" "$SERVER_NAME" 2>/dev/null || true
    echo "[+] 已移除"
}

# ---------------------------------------------------------------- 运行管理

device_forward() {
    if command -v adb >/dev/null 2>&1; then
        if adb devices | grep -q device; then
            adb forward tcp:9494 tcp:9494 >/dev/null 2>&1 || true
            echo "[*] adb forward: 本机 9494 -> 设备 9494"
            if ! adb shell "ss -tln 2>/dev/null | grep -q 9494" 2>/dev/null; then
                echo "[!] 设备上 9494 未监听。请先启动设备端 LS_KTool:"
                echo "    adb shell \"su -c 'echo 4 | /data/akernel/LS_KTool'\""
            fi
        else
            echo "[!] 未检测到已连接 adb 设备"
        fi
    fi
}

start() {
    [ -n "$VPY" ] || { echo "[!] venv 未就绪，请先运行 ./install.sh install"; exit 1; }
    device_forward
    mkdir -p "$LOG_DIR"
    if [ -f "$SERVER_PID_FILE" ] && kill -0 "$(cat "$SERVER_PID_FILE")" 2>/dev/null; then
        echo "[!] 服务器已在运行 (pid $(cat "$SERVER_PID_FILE"))"
        return 0
    fi
    local android_host="${ANDROID_HOST:-127.0.0.1}"
    nohup "$VPY" "$PY_DIR/LuckyStarMcp.py" --android-host "$android_host" >> "$SERVER_LOG" 2>&1 &
    echo $! > "$SERVER_PID_FILE"
    echo "[+] MCP 服务器启动: $MCP_URL (pid $(cat "$SERVER_PID_FILE"), android-host=$android_host)"
    sleep 2
    if curl -s -m 3 "$MCP_URL" -o /dev/null 2>/dev/null; then
        echo "[+] MCP 服务器可达 ✓"
    else
        echo "[!] 服务器暂未响应，查看日志: $SERVER_LOG"
    fi
}

stop() {
    if [ -f "$SERVER_PID_FILE" ] && kill -0 "$(cat "$SERVER_PID_FILE")" 2>/dev/null; then
        kill "$(cat "$SERVER_PID_FILE")" 2>/dev/null && echo "[+] 服务器已停止"
        rm -f "$SERVER_PID_FILE"
    else
        echo "[!] 没有运行中的服务器（或无 pid 文件）"
    fi
}

status() {
    if [ -f "$SERVER_PID_FILE" ] && kill -0 "$(cat "$SERVER_PID_FILE")" 2>/dev/null; then
        echo "[+] MCP 服务器运行中 (pid $(cat "$SERVER_PID_FILE")) -> $MCP_URL"
    else
        echo "[-] MCP 服务器未运行"
    fi
    curl -s -m 3 "$MCP_URL" -o /dev/null 2>/dev/null && echo "[+] $MCP_URL 可达" || echo "[-] $MCP_URL 不可达"
    adb forward --list 2>/dev/null | grep -q 9494 && echo "[+] adb forward 9494 已建立" || echo "[-] adb forward 9494 未建立"
}

# ---------------------------------------------------------------- 入口

case "${1:-}" in
    install)   setup; register_agents ;;
    start)     start ;;
    stop)      stop ;;
    status)    status ;;
    uninstall) uninstall_agents ;;
    *)
        setup
        register_agents
        start
        ;;
esac
