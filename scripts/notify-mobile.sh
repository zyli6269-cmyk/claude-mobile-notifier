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
print($1)
" 2>/dev/null; }

# ===== Bash 安全命令白名单(只读/查询类,不推送)=====
SAFE_BASH_CMDS="ls cat head tail pwd echo printf find grep egrep fgrep awk sed which command type file stat wc sort uniq cut tr basename dirname env date uname hostname whoami id jq yq true false test ps top df du free lsof netstat ss ifconfig ipconfig ping host nslookup dig history alias declare set unset export readonly :"
# git 的只读子命令也视为安全。会修改仓库或配置的子命令不要放进来。
SAFE_GIT_SUBCMDS="status log diff show rev-parse ls-files ls-tree blame describe"

is_safe_bash() {
    local cmd="$1"
    # 含复合控制符(管道、重定向、逻辑连接、分号、子 shell)一律视为不安全
    if printf '%s' "$cmd" | grep -qE '(&&|\|\||;|\||>|<|`|\$\()'; then
        return 1
    fi
    local first second
    first=$(printf '%s' "$cmd" | awk '{print $1}')
    second=$(printf '%s' "$cmd" | awk '{print $2}')
    # 通用安全命令
    for safe in $SAFE_BASH_CMDS; do
        [ "$first" = "$safe" ] && return 0
    done
    # git 的只读子命令
    if [ "$first" = "git" ]; then
        for safe in $SAFE_GIT_SUBCMDS; do
            [ "$second" = "$safe" ] && return 0
        done
    fi
    return 1
}

cwd=$(pyget 'd.get("cwd","")')
project=$(basename "$cwd" 2>/dev/null || echo "")

# ===== 根据事件类型组装推送内容 =====
case "$hook_event" in
    Notification)
        # Claude 主动通知(理论上权限请求会走这里,实测可能不触发)
        title="🤖 Claude 在等你"
        msg=$(pyget 'd.get("message","需要你回答")')
        priority="high"
        tags="bell,question"
        ;;
    PreToolUse)
        tool_name=$(pyget 'd.get("tool_name","")')
        case "$tool_name" in
            AskUserQuestion)
                title="🤖 Claude 在问你"
                msg=$(pyget '(d.get("tool_input",{}).get("questions") or [{}])[0].get("question","等你选择")')
                priority="high"
                tags="bell,question"
                ;;
            Bash)
                cmd=$(pyget 'd.get("tool_input",{}).get("command","")')
                if is_safe_bash "$cmd"; then
                    # 安全命令(ls/cat/grep 等)静默
                    short=$(printf '%s' "$cmd" | head -c 80)
                    echo "[$TS] event=PreToolUse Bash skip(safe): $short" >> "$LOG"
                    exit 0
                fi
                title="🤖 Claude 要执行命令"
                # 正文截断到 120 字,锁屏看不下
                msg=$(printf '%s' "$cmd" | head -c 120)
                priority="high"
                tags="bell,warning"
                ;;
            *)
                # 其他 tool 不推(matcher 应该已经拦了,这是兜底)
                exit 0
                ;;
        esac
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
