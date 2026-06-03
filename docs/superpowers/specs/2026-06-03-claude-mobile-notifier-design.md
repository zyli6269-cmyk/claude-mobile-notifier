# Claude Code 手机提醒系统 - 设计文档

**日期**: 2026-06-03
**作者**: apple
**状态**: 设计草案

## 1. 背景与目标

### 痛点
Claude Code(VSCode 插件)在长任务执行过程中,会出现两种需要用户关注的时刻:

1. **AI 等待用户回答**:Claude 主动弹出 AskUserQuestion、请求工具权限、需要补充信息时
2. **AI 完成任务**:跑了几分钟甚至几十分钟的任务终于结束

如果用户没有一直盯着 VSCode 窗口,这两个时刻往往被错过,造成等待空转,影响开发效率。

### 目标
让 Android 手机在上述两个时刻**震动 + 响铃 + 锁屏弹窗显示问题内容**,用户可以离开电脑去做别的事,需要回答时回到电脑前点击选项。

### 显式不在本期范围内
- **手机端反向控制电脑**(在手机上直接点击选项让 Claude 继续)。原因:Claude Code 是 VSCode 扩展,选项渲染在 sidebar 按钮上,外部进程无法干净注入。后续如有强需求再走 macOS 辅助功能方案。
- **Codex 桌面端的集成**。原因:Codex 桌面 app 不在本期目标内,且其 hook 能力尚未调研。
- **跨网络访问**(不在家时使用)。原因:用户当前场景是家/办公室同一 WiFi,自托管 ntfy 简单够用。

## 2. 用户场景

### 场景 A:AI 等待用户回答
1. 用户在 VSCode 中让 Claude 执行一个修改任务
2. Claude 中途需要用户做选择(AskUserQuestion 弹出选项 / 请求 Bash 权限)
3. 用户此刻在客厅看视频,手机震动 + 响铃
4. 手机锁屏弹窗显示:`🤖 Claude 在等你:要把组件改成 React 还是 Vue?`
5. 用户回到书桌,在 VSCode 里点选项

### 场景 B:AI 完成任务
1. 用户启动一个长任务(如重构十几个文件)
2. 用户去泡咖啡
3. Claude 完成,手机收到通知:`✅ Claude 完成任务`(默认优先级,不响铃)
4. 用户喝完咖啡看到通知,回到电脑继续

## 3. 系统架构

```
┌──────────────────────────────────────────────────┐
│  VSCode (Claude Code 扩展)                       │
│  - 触发 Notification hook(等待用户)             │
│  - 触发 Stop hook(任务完成)                     │
└────────────────┬─────────────────────────────────┘
                 │ hook 执行 shell 命令
                 │ 通过 stdin 传 JSON
                 ▼
┌──────────────────────────────────────────────────┐
│  bridge 脚本 (~/.claude/scripts/notify-mobile.sh)│
│  - 解析 hook JSON                                │
│  - 格式化推送内容(标题/正文/优先级/emoji)     │
│  - curl POST 到 ntfy 服务器                      │
└────────────────┬─────────────────────────────────┘
                 │ HTTP POST
                 ▼
┌──────────────────────────────────────────────────┐
│  自托管 ntfy 服务器(Docker)                    │
│  - 监听 :80 或自定义端口                         │
│  - 路由消息到订阅 topic 的 Android 客户端        │
└────────────────┬─────────────────────────────────┘
                 │ WebSocket(长连接)
                 ▼
┌──────────────────────────────────────────────────┐
│  Android: ntfy 官方 app                          │
│  - 订阅 topic                                    │
│  - 收到推送 → 震动 / 响铃 / 锁屏弹窗             │
└──────────────────────────────────────────────────┘
```

## 4. 组件设计

### 4.1 ntfy 服务器(自托管)

**部署方式**: Docker Compose

**位置**: 用户开发机(同一台跑 VSCode 的 Mac)

**配置**:
- 监听端口:`8080`(避免占用 80)
- 数据持久化:`./ntfy-cache:/var/cache/ntfy`
- 配置文件:`./server.yml`,允许匿名发布(局域网内信任)
- topic 名:`claude-{8 位随机串}`(用户首次配置时生成,确保不被外人猜中)

**docker-compose.yml**(放在项目根):
```yaml
services:
  ntfy:
    image: binwiederhier/ntfy
    container_name: ntfy
    command: serve
    environment:
      - TZ=Asia/Shanghai
    volumes:
      - ./ntfy-cache:/var/cache/ntfy
      - ./server.yml:/etc/ntfy/server.yml
    ports:
      - "8080:80"
    restart: unless-stopped
```

**启动**:`docker compose up -d`

### 4.2 桌面 bridge 脚本

**位置**: `~/.claude/scripts/notify-mobile.sh`

**输入**: stdin JSON(Claude Code hooks 标准格式)

**职责**:
1. 读取 stdin JSON
2. 根据 hook 类型(Notification / Stop)选择推送模板
3. 提取关键字段(message / cwd / session_id 等)
4. curl POST 到 ntfy 服务器

**核心逻辑**(伪代码):
```bash
#!/usr/bin/env bash
set -euo pipefail

NTFY_URL="http://localhost:8080"
TOPIC="claude-XXXXXXXX"   # 安装时生成

payload=$(cat)
hook_type="${CLAUDE_HOOK_EVENT:-unknown}"   # 由 hook 类型决定
cwd=$(echo "$payload" | jq -r '.cwd // ""')
project=$(basename "$cwd")

case "$hook_type" in
  Notification)
    title="🤖 Claude 在等你"
    msg=$(echo "$payload" | jq -r '.message // "需要你回答"')
    priority="high"
    tags="bell,question"
    ;;
  Stop)
    title="✅ Claude 完成任务"
    msg="项目 $project 的任务已完成"
    priority="default"
    tags="white_check_mark"
    ;;
  *)
    exit 0   # 未知 hook 类型不推送
    ;;
esac

curl -sS \
  -H "Title: $title" \
  -H "Priority: $priority" \
  -H "Tags: $tags" \
  -d "$msg" \
  "$NTFY_URL/$TOPIC" > /dev/null
```

**错误处理**:
- ntfy 服务器不可达时,静默失败(不阻塞 Claude Code 的主流程)
- 用 `|| true` 兜底

### 4.3 Claude Code hooks 配置

**位置**: `~/.claude/settings.json`

**新增字段**:
```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "CLAUDE_HOOK_EVENT=Notification ~/.claude/scripts/notify-mobile.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "CLAUDE_HOOK_EVENT=Stop ~/.claude/scripts/notify-mobile.sh"
          }
        ]
      }
    ]
  }
}
```

**为什么只选 Notification 和 Stop**:
- `Notification`:Claude Code 在需要用户输入时触发(等待权限、AskUserQuestion 等),正好对应"等你回答"场景
- `Stop`:任务最终结束触发,对应"完成"场景
- `PreToolUse` / `PostToolUse`:每个工具调用都触发,频率太高会刷屏,本期不接入
- `SubagentStop`:subagent 结束,会增加噪音,本期不接入

### 4.4 Android 端配置

**安装**: ntfy 官方 app(Google Play 或 F-Droid)

**订阅设置**:
1. 添加订阅 → 输入 `http://<电脑局域网 IP>:8080/<topic>`
2. 通知优先级:跟随服务端 Priority header
3. 震动模式:跟随系统默认,优先级 High 时强震
4. 提示音:用户自选(系统通知音)

**测试**:
- 桌面端发一条测试推送:`curl -d "test" http://localhost:8080/<topic>`
- 手机应收到通知

## 5. 推送内容设计

| 场景 | 标题 | 正文 | 优先级 | tag/emoji |
|------|------|------|--------|-----------|
| Claude 等待回答 | 🤖 Claude 在等你 | hook 传入的 `message` 字段(通常是问题文本或权限请求说明) | high(会响铃/震动) | bell,question |
| Claude 完成任务 | ✅ Claude 完成任务 | 项目 `xxx` 的任务已完成 | default(无声) | white_check_mark |

**优先级映射到 Android 行为**:
- `high`(4):锁屏弹窗 + 震动 + 响铃,即使免打扰模式也响(用户需在 Android 通知设置里允许 ntfy)
- `default`(3):正常通知栏,可能震动一下

## 6. 安装与配置流程(给用户的操作指南)

1. **启动 ntfy 服务器**
   ```bash
   cd ~/projects/claude-mobile-notifier
   docker compose up -d
   ```

2. **生成 topic 名并安装 bridge 脚本**
   ```bash
   ./install.sh
   ```
   脚本职责:
   - 随机生成 topic 名
   - 复制 `notify-mobile.sh` 到 `~/.claude/scripts/`
   - 把 topic 名填入脚本
   - 把 hooks 配置追加(或合并)到 `~/.claude/settings.json`
   - 输出手机端订阅 URL

3. **手机端订阅**
   - 装 ntfy app,扫描安装脚本输出的二维码或手动输入订阅 URL

4. **测试**
   - 在 VSCode 里让 Claude 执行一个需要确认的命令(如修改文件)
   - 手机应在权限请求时收到推送

## 7. 文件结构

```
~/projects/claude-mobile-notifier/
├── docker-compose.yml
├── server.yml                 # ntfy 服务器配置
├── install.sh                 # 一键安装脚本
├── uninstall.sh               # 卸载脚本
├── scripts/
│   └── notify-mobile.sh       # bridge 脚本(install.sh 会复制到 ~/.claude/scripts/)
├── docs/
│   └── superpowers/
│       └── specs/
│           └── 2026-06-03-claude-mobile-notifier-design.md  # 本文档
├── README.md
└── .gitignore                 # 忽略 ntfy-cache/
```

## 8. 风险与限制

1. **Notification hook 的 `message` 字段格式**: 未实际验证 Claude Code 在 AskUserQuestion / 权限请求等不同子场景下是否都通过 Notification hook 触发,以及 message 字段的内容质量。实施时第一步要做 hook payload 抓取验证。
2. **局域网 IP 变化**: 电脑 IP 变了手机要重订阅。后期可以用 mDNS(`<hostname>.local`)缓解。
3. **VSCode 不运行时也不会推送**: 因为 hook 是 Claude Code 触发的,VSCode 不开就没有 hook。这是预期行为,符合"等待 AI 响应"的场景。
4. **多 VSCode 窗口**: 多个窗口同时跑 Claude,推送会都发到同一个 topic,用户分不清哪个项目在等。当前 cwd 字段会出现在正文里,可以靠它区分,但锁屏可能截断。本期接受这个限制。

## 9. 后续可拓展(不在本期)

- 反向控制(手机选择 → 电脑)
- Codex 桌面 app 接入
- 跨网络访问(VPN 或 ntfy 公网中继)
- 多设备区分(给每台电脑用独立 topic)
- 推送内容里附加项目 emoji / 颜色区分
