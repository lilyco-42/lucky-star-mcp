# lucky-star-mcp

AI-agent plugins for the **LuckyStar / LS_KTool** Android memory-debugging stack
(from [lsnbm/Linux-android-arm64](https://github.com/lsnbm/Linux-android-arm64)).

This repository packages the agent-facing components so any MCP-capable client
(Claude Code, Claude Desktop, Cursor, etc.) can drive the Android debugger
through the standard **Model Context Protocol (MCP)**.

> ⚠️ Research/learning use only. The upstream driver provides kernel memory
> read/write, module scanning, hardware breakpoints, and input simulation.
> Use it only on devices and processes you own or are authorized to test.

---

## What's inside

```
lucky-star-mcp/
├── python/
│   ├── LuckyStarMcp.py      # FastMCP server  → exposes the Android bridge as MCP tools
│   ├── http_bridge.py       # NativeHttpBridge → talks to the Android HTTP server (port 9494)
│   └── examples/
│       └── mcp-config.example.json   # sample MCP client registration
├── go-client/               # Go desktop client (Fyne UI) with a bundled MCP server (internal/mcp)
├── requirements.txt         # Python deps (mcp, pydantic)
└── LICENSE                  # MIT
```

### Python MCP server (`python/`)

`LuckyStarMcp.py` is a self-contained FastMCP server. It exposes the Android
debugger's full toolset as MCP tools:

- Connection: `android_connection`, `discover_android_bridges`, `android_bridge_ping`
- Target: `android_target_set_pid`, `android_target_attach_package`, `android_target_find_pid`, `android_target_current`
- Environment: `android_env_get_params`
- Memory: `android_memory_regions`, `android_memory_read`, `android_memory_write`, `android_memory_dump`
- Scanning: `android_memory_scan_start`, `android_memory_scan_refine`, `android_memory_scan_results`, `android_memory_scan_status`, `android_memory_scan_clear`
- Pointers: `android_pointer_status`, `android_pointer_scan`, `android_pointer_merge`, `android_saved_*`
- Modules/breakpoints: `android_module_address`, breakpoint helpers

### Go client (`go-client/`)

A desktop GUI client (Fyne) for the same bridge, with its own MCP server in
`internal/mcp` (uses `mark3labs/mcp-go`). Build with `build.ps1` / `go build`.

---

## Prerequisites

1. **Android device** running `LS_KTool` in HTTP-server mode (port `9494`),
   reachable over the LAN (or via a Cloudflare tunnel URL).
2. **Python 3.12+** for the Python MCP server.

> The MCP server starts even when the device is offline — each tool call will
> then return a bridge-connection error instead.

---

## One-shot install for local agents

`./install.sh` sets up a Python venv, registers the MCP server with your local
agents (Claude Code, Claude Desktop, Cursor), and starts it:

```bash
./install.sh            # venv + deps + register agents + start server
./install.sh status     # check server / adb forward state
./install.sh stop       # stop the server
```

It also runs `adb forward tcp:9494 tcp:9494` so the server reaches the device
through the adb connection (`--android-host 127.0.0.1`).

---

## Install & run (Python)

```bash
pip install -r requirements.txt

# Start the MCP server (default: http://127.0.0.1:14447/mcp)
python python/LuckyStarMcp.py

# Point it at a specific device on your LAN:
python python/LuckyStarMcp.py --android-host 192.168.1.50 --android-timeout 4

# Use a Cloudflare tunnel URL instead of a raw IP:
python python/LuckyStarMcp.py --android-host "https://your-tunnel.trycloudflare.com"
```

| Flag | Default | Description |
|------|---------|-------------|
| `--mcp-host` | `127.0.0.1` | Bind host for the local MCP web server |
| `--mcp-port` | `14447` | Bind port for the local MCP web server |
| `--mcp-path` | `/mcp` | HTTP endpoint path for streamable-http clients |
| `--android-host` | `auto` | Android IP/host, full HTTP(S) tunnel URL, or `auto` for LAN discovery |
| `--android-timeout` | `4` | Timeout (seconds) for Android bridge requests |

Environment variables: `ANDROID_HTTP_HOST` (default `auto`), `ANDROID_HTTP_PORT`
(`9494`), `ANDROID_HTTP_TIMEOUT` (`4`), `ANDROID_MCP_BIND_HOST` (`127.0.0.1`),
`ANDROID_MCP_BIND_PORT` (`14447`), `ANDROID_MCP_PATH` (`/mcp`).

---

## Register with an MCP client

With the server running, register it in your client's MCP config. Example
(Claude Code / Claude Desktop style):

```json
{
  "mcpServers": {
    "luckystar": {
      "type": "http",
      "url": "http://127.0.0.1:14447/mcp",
      "enabled": true
    }
  }
}
```

Or, to have the client launch the server itself (stdio mode):

```json
{
  "mcpServers": {
    "luckystar": {
      "command": "python",
      "args": ["/path/to/lucky-star-mcp/python/LuckyStarMcp.py"]
    }
  }
}
```

---

## License

MIT. The `LuckyStarMcp.py`, `http_bridge.py`, and `go-client/` sources are
derived from [lsnbm/Linux-android-arm64](https://github.com/lsnbm/Linux-android-arm64)
(© 2025 LsLucky). See `LICENSE`.
