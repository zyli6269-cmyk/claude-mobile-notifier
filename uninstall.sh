#!/usr/bin/env bash
# 卸载脚本: 从 settings.json 移除我们的 hook,删除 bridge 脚本
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
BRIDGE_DST="$CLAUDE_DIR/scripts/notify-mobile.sh"

say()  { printf '\033[1;34m===>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }

# 1. 从 settings.json 移除我们的 hook
if [ -f "$SETTINGS_FILE" ] && command -v jq >/dev/null; then
    say "1/2 从 settings.json 移除 hook"
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak"
    TMP=$(mktemp)
    jq \
        --arg bridge "$BRIDGE_DST" \
        '
        def strip_ours($event):
            (.hooks[$event] // [])
            | map(.hooks |= map(select(.command // "" | contains($bridge) | not)))
            | map(select((.hooks | length) > 0));
        .hooks //= {}
        | .hooks.Notification = strip_ours("Notification")
        | .hooks.Stop = strip_ours("Stop")
        | if (.hooks.Notification | length) == 0 then del(.hooks.Notification) else . end
        | if (.hooks.Stop | length) == 0 then del(.hooks.Stop) else . end
        | if (.hooks | length) == 0 then del(.hooks) else . end
        ' "$SETTINGS_FILE" > "$TMP" && mv "$TMP" "$SETTINGS_FILE"
    ok "已清理(备份: $SETTINGS_FILE.bak)"
fi

# 2. 删除 bridge 脚本
if [ -f "$BRIDGE_DST" ]; then
    say "2/2 删除 bridge 脚本"
    rm -f "$BRIDGE_DST"
    ok "已删除 $BRIDGE_DST"
fi

echo ""
ok "卸载完成。topic 文件 $PROJECT_DIR/.topic 已保留以便后续重装时复用。"
echo "  要彻底重置,执行: rm $PROJECT_DIR/.topic"
