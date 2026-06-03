#!/usr/bin/env bash
# 一键安装脚本: 桥接 Claude Code hooks 到 ntfy 推送
# 用 ntfy.sh 公网服务(零运维)+ 12 位随机 topic 防猜测
# 幂等: 重复执行不会重复添加 hook,会复用已生成的 topic

set -euo pipefail

# ============ 路径常量 ============
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_SCRIPTS_DIR="$CLAUDE_DIR/scripts"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
BRIDGE_SRC="$PROJECT_DIR/scripts/notify-mobile.sh"
BRIDGE_DST="$CLAUDE_SCRIPTS_DIR/notify-mobile.sh"
TOPIC_FILE="$PROJECT_DIR/.topic"
NTFY_URL="https://ntfy.sh"

# ============ 辅助函数 ============
say()  { printf '\033[1;34m===>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# ============ 1/4 检查依赖 ============
say "1/4 检查依赖"
command -v jq >/dev/null || { command -v brew >/dev/null || die "需要 jq 或 brew"; say "  安装 jq..."; brew install jq; }
command -v curl >/dev/null || die "缺少 curl"
ok "依赖就绪"

# ============ 2/4 准备 topic ============
say "2/4 准备 topic"
if [ -f "$TOPIC_FILE" ]; then
    TOPIC=$(cat "$TOPIC_FILE")
    ok "复用已有 topic: $TOPIC"
else
    TOPIC="claude-$(openssl rand -hex 6)"
    printf '%s' "$TOPIC" > "$TOPIC_FILE"
    chmod 600 "$TOPIC_FILE"
    ok "新生成 topic: $TOPIC"
fi

# ============ 3/4 部署 bridge 脚本 ============
say "3/4 部署 bridge 脚本"
mkdir -p "$CLAUDE_SCRIPTS_DIR"
sed -e "s|__NTFY_URL__|$NTFY_URL|g" \
    -e "s|__TOPIC__|$TOPIC|g" \
    "$BRIDGE_SRC" > "$BRIDGE_DST"
chmod +x "$BRIDGE_DST"
ok "已部署到 $BRIDGE_DST"

# ============ 4/4 合并 hooks 到 settings.json ============
say "4/4 合并 hooks 到 settings.json"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi

# 备份(只保留最新一份,避免堆积)
cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak"

NOTIF_CMD="CLAUDE_HOOK_EVENT=Notification \"$BRIDGE_DST\""
STOP_CMD="CLAUDE_HOOK_EVENT=Stop \"$BRIDGE_DST\""
PRETOOL_CMD="CLAUDE_HOOK_EVENT=PreToolUse \"$BRIDGE_DST\""

# 幂等合并:先剔除现有 hooks 中所有指向我们 bridge 脚本的 entry,再添加
TMP=$(mktemp)
jq \
    --arg bridge "$BRIDGE_DST" \
    --arg notif_cmd "$NOTIF_CMD" \
    --arg stop_cmd "$STOP_CMD" \
    --arg pretool_cmd "$PRETOOL_CMD" \
    '
    def strip_ours($event):
        (.hooks[$event] // [])
        | map(.hooks |= map(select(.command // "" | contains($bridge) | not)))
        | map(select((.hooks | length) > 0));
    .hooks //= {}
    | .hooks.Notification = (strip_ours("Notification") + [{matcher:"", hooks:[{type:"command", command:$notif_cmd}]}])
    | .hooks.Stop = (strip_ours("Stop") + [{matcher:"", hooks:[{type:"command", command:$stop_cmd}]}])
    | .hooks.PreToolUse = (strip_ours("PreToolUse") + [{matcher:"AskUserQuestion|Bash", hooks:[{type:"command", command:$pretool_cmd}]}])
    ' "$SETTINGS_FILE" > "$TMP" && mv "$TMP" "$SETTINGS_FILE"

ok "hooks 已合并(备份: $SETTINGS_FILE.bak)"

# ============ 汇报结果 ============
SUB_URL="$NTFY_URL/$TOPIC"

echo ""
echo "================================================================"
ok "安装完成"
echo "================================================================"
echo ""
echo "📱 手机端订阅 URL(在 ntfy app 里添加):"
echo ""
echo "     $SUB_URL"
echo ""
echo "Android 下载 ntfy app:"
echo "  • Google Play: https://play.google.com/store/apps/details?id=io.heckel.ntfy"
echo "  • F-Droid:     https://f-droid.org/packages/io.heckel.ntfy/"
echo ""
echo "🧪 测试推送(订阅后执行,手机应立刻响):"
echo ""
echo "     curl -H 'Title: 🤖 测试' -H 'Priority: high' -d '收到就成了' $SUB_URL"
echo ""
echo "📌 如未立刻生效,请重启 VSCode 或 Claude Code CLI。"
echo ""
echo "⚠️  当前用 ntfy.sh 公网中转(零运维)。推送内容(项目名/问题文本)"
echo "    会经过 ntfy.sh 服务器。如需自托管,见 README 的'自托管'章节。"
echo ""
