#!/usr/bin/env bash
# bridge 脚本: 把 Claude Code hook 事件转成 ntfy 推送
#
# 由 ~/.claude/settings.json 的 hooks 配置触发
# 通过环境变量 CLAUDE_HOOK_EVENT 区分事件类型
# stdin 接收 hook 传入的 JSON

set -uo pipefail

# ===== 配置(install.sh 替换占位符)=====
NTFY_URL="__NTFY_URL__"
TOPIC="__TOPIC__"

# ===== 日志(便于诊断 hook 是否被触发)=====
LOG="$HOME/.claude/logs/notify-mobile.log"
mkdir -p "$(dirname "$LOG")"
TS="$(date '+%F %T')"

# ===== 读取 hook payload =====
payload=$(cat 2>/dev/null || echo '{}')
hook_event="${CLAUDE_HOOK_EVENT:-unknown}"

# 用 python3 安全解析 JSON
pyget() { printf '%s' "$payload" | /usr/bin/python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
# eval 表达式 $1 在 d 上
print($1)
" 2>/dev/null; }

cwd=$(pyget 'd.get("cwd","")')
project=$(basename "$cwd" 2>/dev/null || echo "")

# ===== 根据事件类型组装推送内容 =====
case "$hook_event" in
    Notification)
        # Claude 主动通知(权限请求 / idle / 其他系统通知)
        title="🤖 Claude 在等你"
        msg=$(pyget 'd.get("message","需要你回答")')
        priority="high"
        tags="bell,question"
        ;;
    PreToolUse)
        # 只处理 AskUserQuestion(install.sh 用 matcher 限定)
        tool_name=$(pyget 'd.get("tool_name","")')
        if [ "$tool_name" != "AskUserQuestion" ]; then
            echo "[$TS] event=PreToolUse skip tool=$tool_name" >> "$LOG"
            exit 0
        fi
        title="🤖 Claude 在问你"
        # 取第一个问题文本
        msg=$(pyget '(d.get("tool_input",{}).get("questions") or [{}])[0].get("question","等你选择")')
        priority="high"
        tags="bell,question"
        ;;
    Stop)
        title="✅ Claude 完成任务"
        msg="项目 ${project:-?} 已完成"
        priority="default"
        tags="white_check_mark"
        ;;
    *)
        echo "[$TS] event=$hook_event 未知,跳过" >> "$LOG"
        exit 0
        ;;
esac

# ===== 写日志 =====
# 截断长字段防日志爆炸
short_msg=$(printf '%s' "$msg" | head -c 200)
echo "[$TS] event=$hook_event project='$project' title='$title' msg='$short_msg' priority=$priority" >> "$LOG"

# ===== 推送(失败不阻塞 Claude) =====
http_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \
    -H "Title: $title" \
    -H "Priority: $priority" \
    -H "Tags: $tags" \
    -d "$msg" \
    "${NTFY_URL%/}/$TOPIC" 2>/dev/null || echo "ERR")
echo "[$TS] event=$hook_event ntfy_http=$http_code" >> "$LOG"

exit 0
