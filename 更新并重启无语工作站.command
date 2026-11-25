#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
app="$HOME/Applications/无语工作站.app"

printf '正在编译并更新无语工作站…\n'
"$root/build"

# Gracefully stop any running GUI instance without touching headless bridge-cli MCP processes
for pid in $(pgrep -f "无语工作站.app/Contents/MacOS/Bridge" || true); do
    cmd=$(ps -p "$pid" -o args= 2>/dev/null || true)
    case "$cmd" in
        *" mcp"*) ;;
        *) kill "$pid" 2>/dev/null || true ;;
    esac
done
sleep 0.35

printf '正在启动最新版无语工作站：%s\n' "$app"
exec /usr/bin/open "$app"
