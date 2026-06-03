# Claude Code 手机提醒

> 让 Claude Code(VSCode 插件 / CLI)在 **等你回答**、**要执行危险命令** 或 **完成任务** 时,Android 手机自动 **震动 + 响铃**。

适合的人:**用 Claude Code 跑长任务时,不想一直盯着电脑**。把通知推到手机后台,任务完成或需要你介入时立刻响铃,中间可以去喝水、看视频、做别的事。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Platform](https://img.shields.io/badge/platform-macOS-blue)
![Mobile](https://img.shields.io/badge/mobile-Android-green)

---

## 目录

- [是什么](#是什么)
- [架构](#架构)
- [前置条件](#前置条件)
- [安装](#安装-3-步)
- [手机端配置](#手机端配置)
- [实际使用场景](#实际使用场景)
- [触发规则](#触发规则)
- [验证 / 调试](#验证--调试)
- [常见问题](#常见问题)
- [卸载](#卸载)
- [隐私与安全](#隐私与安全)
- [自托管(可选)](#自托管可选)
- [后续可扩展](#后续可扩展)
- [致谢](#致谢)
- [License](#license)

---

## 是什么

把 Claude Code 的 [hooks](https://docs.claude.com/en/docs/claude-code/hooks) 桥接到 [ntfy](https://ntfy.sh) 推送服务:

- Claude 弹问题等你回答 → 手机响铃
- Claude 要执行危险命令(如 `brew install`、`git push`、`rm`)→ 手机响铃,锁屏看到命令内容
- Claude 跑只读命令(`ls`、`git status`)→ 不打扰,静音通过
- Claude 完成任务 → 手机收到默认优先级通知(不响铃,只通知栏)

**核心特性:**

- 零运维:用 `ntfy.sh` 公网服务,不需要自建服务器
- 一键安装:`./install.sh` 全部搞定
- 幂等:重复安装不会破坏现有配置,带自动备份
- 安全过滤:内置 Bash 安全命令白名单,避免 `ls`/`cat`/`grep` 这类只读命令刷屏
- 隐私可控:topic 是 12 位随机串(`claude-XXXXXXXXXXXX`),别人猜不到。要更高隐私可自托管

---

## 架构

```
┌──────────────────────────────────────────────────┐
│ VSCode 里的 Claude Code(或 CLI 版本)           │
│   - Notification hook → 等待用户                 │
│   - PreToolUse hook   → 工具调用前(AskUserQuestion / Bash) │
│   - Stop hook         → 任务完成                 │
└────────────────┬─────────────────────────────────┘
                 │ hook 调用 shell 命令
                 │ stdin 传 JSON payload
                 ▼
┌──────────────────────────────────────────────────┐
│ 桥接脚本 ~/.claude/scripts/notify-mobile.sh      │
│   1. 解析 hook JSON                              │
│   2. 判断事件类型 + 命令安全性                   │
│   3. 安全命令(ls/cat/git status...)直接静默    │
│   4. 危险命令 / 提问 / 完成 → 格式化推送内容    │
│   5. HTTPS POST 到 ntfy.sh                       │
│   6. 写诊断日志                                  │
└────────────────┬─────────────────────────────────┘
                 │ HTTPS POST(标题/正文/优先级/tags)
                 ▼
┌──────────────────────────────────────────────────┐
│ ntfy.sh 公网推送服务                             │
│   topic = claude-<12 位随机串>                   │
└────────────────┬─────────────────────────────────┘
                 │ WebSocket 长连接
                 ▼
┌──────────────────────────────────────────────────┐
│ Android: ntfy 官方 app                           │
│   - 锁屏弹窗 + 震动 + 响铃(高优先级)          │
│   - 通知栏静默(默认优先级)                    │
└──────────────────────────────────────────────────┘
```

---

## 前置条件

| 需求 | 检查命令 | 说明 |
|------|---------|------|
| macOS | `uname` 应返回 `Darwin` | 脚本里用了 `ipconfig`、`brew` 等 macOS 特定工具。Linux 用户需要适配 |
| Homebrew | `brew --version` | 用于自动装 `jq`(如缺) |
| curl | `curl --version` | macOS 自带 |
| python3 | `/usr/bin/python3 --version` | macOS 自带 |
| Claude Code | VSCode 插件已装,或 CLI 已装 | hooks 由它触发 |
| Android 手机 | - | 装 ntfy app |

---

## 安装(3 步)

### 第 1 步:克隆并安装

```bash
git clone https://github.com/<你的 GitHub 用户名>/claude-mobile-notifier.git ~/projects/claude-mobile-notifier
cd ~/projects/claude-mobile-notifier
./install.sh
```

脚本会自动:

1. 检查依赖,缺 `jq` 就 `brew install jq`
2. 生成一个 12 位随机 topic 名(如 `claude-6ffa4ba1c508`),存到 `.topic`(已 gitignore,权限 600)
3. 把桥接脚本部署到 `~/.claude/scripts/notify-mobile.sh`(填好 topic)
4. **幂等合并** `~/.claude/settings.json` 的 hooks 字段(`Notification` / `PreToolUse` / `Stop`),不破坏你已有的其他配置;自动创建 `.bak` 备份
5. 输出手机端订阅 URL

安装完毕后,你会看到类似这样的输出:

```
================================================================
✓ 安装完成
================================================================

📱 手机端订阅 URL(在 ntfy app 里添加):

     https://ntfy.sh/claude-6ffa4ba1c508
...
```

### 第 2 步:手机端订阅(下方详细说明)

### 第 3 步:**重启 VSCode**

这是必需的!Claude Code 在启动时加载 `settings.json` 的 hooks 配置,不重启的话新加的 hooks 不会生效。

> 完全关掉 VSCode 窗口,重新打开。如果你用 Claude Code CLI,关掉 terminal 重开即可。

---

## 手机端配置

### 1. 装 ntfy app

- [Google Play](https://play.google.com/store/apps/details?id=io.heckel.ntfy)
- [F-Droid](https://f-droid.org/packages/io.heckel.ntfy/)(无需 Google 账号)

### 2. 添加订阅

打开 app:

1. 点右下角 **"+"** → 选 **"Subscribe to topic"** / **"订阅主题"**
   - ⚠️ 不要进 "Manage users" / "管理用户"——那是给私有服务器配认证用的,会问用户名密码,**这个项目不需要**
2. **Topic** 一栏填:安装脚本输出的那串(如 `claude-6ffa4ba1c508`)
3. 服务器保持默认 `ntfy.sh`,不要勾 "Use another server"
4. 点 **Subscribe** / **订阅** 完成

### 3. 调通知优先级到最高

进刚才订阅的那条 → 右上角 ⋮ → **Notification settings**:

- 把 **Priority** 设为 **Max / 最高**
- 允许 **Override Do Not Disturb**(允许越过免打扰)
- 选一个有辨识度的提示音

不这样调的话,锁屏不会响铃,只在通知栏静默显示。

### 4. 关掉系统省电

Android 系统可能把 ntfy app 列为后台限制,导致消息延迟到达:

设置 → 应用 → ntfy → 电池 → **不限制 / 允许后台活动**

---

## 实际使用场景

配置完成后,**不需要做任何额外操作**,正常用 Claude Code 即可。下面是几个典型场景:

### 场景 1:跑长任务时去做别的事

你让 Claude 重构一个项目,任务大概要跑 15 分钟。你:

1. 给 Claude 下达任务,然后去客厅看会儿视频
2. Claude 中途要执行 `git push origin main` → **手机响铃 + 锁屏看到命令** → 你瞄一眼觉得 OK,回电脑点 "Allow"
3. Claude 跑完整个任务 → **手机出 ✅ Claude 完成任务**(默认优先级,通常不响,通知栏可见)
4. 你回电脑继续干别的

### 场景 2:让 Claude 跑测试套件

测试需要 5 分钟跑完。你去泡咖啡。完成后手机提醒。

### 场景 3:Claude 让你做选择

Claude 用 `AskUserQuestion` 问你"要采用方案 A 还是方案 B" → **手机响铃,锁屏看到完整问题文本** → 你回电脑点选项。

---

## 触发规则

| 事件 | 例子 | 推送 | 响铃 |
|------|------|------|------|
| `AskUserQuestion`(我用结构化选项问你) | "要继续重构吗?" | ✅ | ✅(高优先级) |
| Bash 危险/有副作用命令 | `brew install`, `git push`, `rm`, `npm install`, 含 `&&;|><` 的复合命令 | ✅ | ✅(高优先级) |
| Bash 只读/查询命令 | `ls`, `cat`, `grep`, `find`, `jq`, `git status/log/diff/show` | ❌ 跳过 | - |
| `Stop`(每轮回答结束) | - | ✅ | ❌(默认优先级,通常不响) |
| `Notification`(Claude 主动通知,如 idle 60s) | - | ✅(若触发) | ✅(高优先级) |

**安全命令白名单**(完整列表见 `scripts/notify-mobile.sh` 里的 `SAFE_BASH_CMDS`):

```
ls cat head tail pwd echo printf find grep egrep fgrep awk sed which command type
file stat wc sort uniq cut tr basename dirname env date uname hostname whoami id
jq yq true false test ps top df du free lsof netstat ss ifconfig ipconfig
ping host nslookup dig history alias declare set unset export readonly :
```

**git 子命令白名单**:

```
status log diff show branch remote config rev-parse ls-files ls-tree blame describe tag stash
```

要修改白名单,改 `scripts/notify-mobile.sh` 里的对应变量,然后重跑 `./install.sh`(它会重新部署桥接脚本)。

---

## 验证 / 调试

### 手动发条测试推送

```bash
TOPIC=$(cat ~/projects/claude-mobile-notifier/.topic)
curl -H 'Title: 🤖 测试' -H 'Priority: high' \
     -d '收到就成了' \
     "https://ntfy.sh/$TOPIC"
```

手机应在 1-3 秒内响铃 + 震动。

### 看桥接日志

每次 hook 触发都会写日志,定位问题用:

```bash
tail -20 ~/.claude/logs/notify-mobile.log
```

每行格式:

```
[2026-06-03 22:48:07] event=PreToolUse project='apple' title='🤖 Claude 在问你' msg='手机有响吗?' priority=high
[2026-06-03 22:48:07] event=PreToolUse ntfy_http=200
```

- `event=` 触发的 hook 类型
- `ntfy_http=200` 说明 ntfy.sh 收到了;不是 200 就是网络或 topic 出问题了
- `skip(safe): xxx` 说明这个 Bash 命令被识别为安全,没推送

### 看 hooks 配置

```bash
jq '.hooks' ~/.claude/settings.json
```

应该看到 `Notification` / `PreToolUse` / `Stop` 三个 key。

---

## 常见问题

### Q1:发了测试推送手机没响

排查顺序:

1. **看 ntfy app 主页**,点进你订阅的 topic,**消息列表里有没有看到这条测试**?
   - 有 → 推送送到了,问题在系统通知没弹/没响
   - 没有 → 订阅可能没成功 / 订阅的是别的 topic / app 后台被杀
2. **系统设置 → 应用 → ntfy → 通知**,是否允许?
3. **该订阅的优先级是不是 Max?** 不是 Max 锁屏不响
4. **是否开了勿扰模式?** 高优先级也需要"允许越过勿扰"才能响

### Q2:Claude 弹问题/命令时手机没响

1. **VSCode 重启了吗?** 装完 hooks 必须重启
2. **看日志** `tail ~/.claude/logs/notify-mobile.log` — 有没有对应行?
   - 没有 → hook 没触发,VSCode 没加载新 settings.json
   - 有但 `ntfy_http != 200` → 网络问题
   - 有 `skip(safe): xxx` → 这条命令被白名单跳过,符合预期

### Q3:Bash 命令推送太多 / 太少

- 太多:在 `scripts/notify-mobile.sh` 的 `SAFE_BASH_CMDS` 里加你认为安全的命令,重跑 `./install.sh`
- 太少(漏推危险命令):在白名单里去掉对应命令

### Q4:换电脑或重装系统

1. 在新机器上克隆这个仓库
2. **复制旧的 `.topic` 过来**(在 `~/projects/claude-mobile-notifier/.topic`),这样手机端不用重新订阅
3. 跑 `./install.sh`

如果没有旧 `.topic`,会生成新 topic,手机端要重新订阅。

### Q5:不想被 Stop 通知刷屏

Stop hook 用的是 `default` 优先级,Android 通常**只在通知栏静默显示,不响铃**。如果你的 Android 仍然响,把订阅的"默认通知优先级"调到 Low / Min。

或者干脆从 hooks 配置里删掉 Stop,改 `~/.claude/settings.json`:

```json
"hooks": {
  // 删掉 Stop 这一节
}
```

---

## 卸载

```bash
cd ~/projects/claude-mobile-notifier
./uninstall.sh
```

会:

- 从 `settings.json` 移除我们的 hooks(其他 hooks 不动)
- 删除 `~/.claude/scripts/notify-mobile.sh`
- 保留 `.topic`,以便后续重装时复用

要彻底重置:

```bash
rm ~/projects/claude-mobile-notifier/.topic
```

---

## 隐私与安全

**默认用 ntfy.sh 公网中转**,推送内容会经过 ntfy.sh 服务器:

| 项目 | 风险 | 缓解 |
|------|------|------|
| topic 名泄露后任何人都能发垃圾通知到你手机 | 中 | `.topic` 在 .gitignore 内,权限 600,不会被 commit;不要在 issue / 截图里展示 |
| 推送内容(项目名 / Bash 命令 / 问题文本)经过 ntfy.sh 服务器 | 中 | 用 HTTPS 传输;ntfy.sh 运维方理论上能看到内容 |
| 推送内容可能含敏感的代码片段 | 中 | bridge 脚本对正文截断到 100-120 字,但仍可能含路径/项目名 |

**对此敏感请自托管(下方)**。

### 哪些是真的"敏感"

- ✅ topic 名(相当于密码)
- ⚠️ 推送正文(项目名 + Bash 命令 + 问题文本)
- ✅ `~/.claude/settings.json` 里的 API key(本项目从不接触它)

---

## 自托管(可选)

ntfy 在 macOS 的 brew 和官方预编译版本都是 client-only(`noserver` 编译 tag),要自托管 server 必须在 Linux 上跑:

### 方案 1:Linux 服务器 / NAS / 树莓派

```bash
docker run -d \
  --name ntfy \
  --restart unless-stopped \
  -p 80:80 \
  binwiederhier/ntfy serve
```

或 `apt install ntfy`。

### 方案 2:macOS 装 Docker Desktop

```yaml
# docker-compose.yml
services:
  ntfy:
    image: binwiederhier/ntfy
    command: serve
    environment:
      - TZ=Asia/Shanghai
    ports:
      - "8080:80"
    volumes:
      - ./ntfy-cache:/var/cache/ntfy
    restart: unless-stopped
```

启动: `docker compose up -d`

### 切换到自托管

改 `scripts/notify-mobile.sh` 里的 `NTFY_URL`(`__NTFY_URL__` 占位是被 install.sh 替换的,看 install.sh 里 `NTFY_URL=`):

```diff
- NTFY_URL="https://ntfy.sh"
+ NTFY_URL="http://192.168.x.x:8080"
```

或更稳的方式:改 `install.sh` 里 `NTFY_URL` 的赋值,重跑 `./install.sh`。

手机端 ntfy app 添加订阅时,服务器栏选 "Use another server",填入你的自托管地址。

---

## 后续可扩展

未在本期实现,有兴趣可以 PR:

- [ ] **反向控制**(手机点 yes/no → 电脑响应):基于 ntfy actions + reply-topic polling + PreToolUse 阻塞 hook
- [ ] **Codex 桌面端集成**:需要先调研 Codex 的 hook / 通知 API
- [ ] **跨网络支持**:VPN / Cloudflare Tunnel / 自托管 ntfy 走公网
- [ ] **多设备区分**:不同电脑用不同 topic,推送内容里加电脑名
- [ ] **Linux 移植**:替换 `ipconfig` 等 macOS 命令
- [ ] **iOS 端**:ntfy iOS 客户端比较弱,可考虑接 Bark
- [ ] **更智能的危险命令判断**:解析复合命令,识别 `cd foo && rm -rf` 这种实际危险的

---

## 致谢

- [ntfy](https://ntfy.sh) - 开源、零配置的 pub-sub 推送服务,本项目的核心
- [Claude Code hooks](https://docs.claude.com/en/docs/claude-code/hooks) - 提供事件触发机制

---

## License

[MIT](LICENSE) © 2026
