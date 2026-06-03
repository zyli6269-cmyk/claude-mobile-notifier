#!/usr/bin/env bash
# bridge 脚本: 把 Claude Code hook 事件转成 ntfy 推送
#
# 由 ~/.claude/settings.json 的 hooks 配置触发
# 通过环境变量 CLAUDE_HOOK_EVENT 区分事件类型(Notification / Stop)
# stdin 接收 hook 传入的 JSON

set -uo pipefail

# ===== 配置 =====
# 安装时由 install.sh 替换为实际值
NTFY_URL="__NTFY_URL__"
TOPIC="__TOPIC__"

# ===== 读取 hook payload =====
# 即使读取失败也不阻塞 Claude,所以静默处理
payload=$(cat 2>/dev/null || echo '{}')
hook_event="${CLAUDE_HOOK_EVENT:-unknown}"

# 提取 cwd 做项目区分(失败则空)
cwd=$(printf '%s' "$payload" | /usr/bin/python3 -c \
    'import json,sys;d=json.load(sys.stdin);print(d.get("cwd",""))' 2>/dev/null || echo "")
project=$(basename "$cwd" 2>/dev/null || echo "")

# ===== 根据事件类型组装推送内容 =====
case "$hook_event" in
    Notification)
        title="🤖 Claude 在等你"
        # 取 hook 提供的 message 字段;如果取不到给个兜底
        msg=$(printf '%s' "$payload" | /usr/bin/python3 -c \
            'import json,sys;d=json.load(sys.stdin);print(d.get("message","需要你回答"))' 2>/dev/null \
            || echo "Claude 需要你回答")
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
        # 未知事件类型,不推送
        exit 0
        ;;
esac

# ===== 推送 =====
# 失败也不阻塞 Claude,所以静默
curl -sS --max-time 3 \
    -H "Title: $title" \
    -H "Priority: $priority" \
    -H "Tags: $tags" \
    -d "$msg" \
    "${NTFY_URL%/}/$TOPIC" \
    > /dev/null 2>&1 || true

exit 0
