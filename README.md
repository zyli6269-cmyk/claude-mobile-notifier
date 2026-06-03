# Claude Code 手机提醒

让 Claude Code(VSCode 插件)在 **等你回答** 或 **完成任务** 时,Android 手机 **震动 + 响铃**。

## 工作原理

```
VSCode 里的 Claude Code
   ↓ Notification / Stop hook 触发
桥接脚本 ~/.claude/scripts/notify-mobile.sh
   ↓ HTTPS POST
ntfy.sh 公网推送服务
   ↓ WebSocket 长连接
手机 ntfy app(震动 + 锁屏弹窗)
```

零运维,不需要本机 docker 也不需要自己跑服务。topic 名是 12 位随机串,别人猜不到。

## 前置条件

- macOS(脚本里用了 `ipconfig getifaddr` 等命令,Linux 可改)
- 已安装 `jq` 和 `curl`(`brew install jq` 即可,curl macOS 自带)
- Android 手机 + [ntfy app](https://play.google.com/store/apps/details?id=io.heckel.ntfy)

## 安装

```bash
cd ~/projects/claude-mobile-notifier
./install.sh
```

脚本会:
1. 检查依赖(jq / curl),缺则 `brew install jq`
2. 生成 12 位随机 topic 并保存到本地 `.topic`(已 gitignore,权限 600)
3. 把桥接脚本部署到 `~/.claude/scripts/notify-mobile.sh`(填好 topic)
4. **幂等合并** `~/.claude/settings.json` 的 hooks 字段(不破坏已有配置;备份在 `settings.json.bak`)
5. 输出手机端订阅 URL

安装完后 **重启 VSCode** 让 Claude Code 重新加载 settings.json。

## 手机端配置

1. 装 ntfy app
2. 点 "+" 添加订阅
3. 服务器选 **ntfy.sh**,topic 填安装脚本输出的 12 位随机串
4. 进通知设置把这个订阅的优先级调到 **Max**,锁屏才会响铃

## 测试

订阅后在电脑上执行(用安装脚本输出的真实 URL):

```bash
curl -H 'Title: 🤖 测试' -H 'Priority: high' \
     -d '收到就成了' \
     https://ntfy.sh/claude-xxxxxxxxxxxx
```

手机应在 1~3 秒内响铃 + 震动。

## 实际使用

在 VSCode 里让 Claude Code 跑任务,什么都不用做:

| 场景 | 通知 | 优先级 |
|------|------|--------|
| Claude 需要权限 / 弹 AskUserQuestion | `🤖 Claude 在等你 + 问题内容` | 高(响铃) |
| Claude 跑完任务 | `✅ Claude 完成任务 + 项目名` | 默认(通常不响) |

## 卸载

```bash
./uninstall.sh
```

- 移除 settings.json 里我们加的 hook(其他 hook 不动)
- 删除桥接脚本
- `.topic` 保留,以便后续重装时复用

## 文件结构

| 路径 | 说明 |
|------|------|
| `install.sh` | 一键安装(幂等) |
| `uninstall.sh` | 卸载 |
| `scripts/notify-mobile.sh` | 桥接脚本模板,install.sh 会填入 topic 后复制走 |
| `.topic` | 安装时生成的 topic 名(已 gitignore,权限 600) |
| `docs/superpowers/specs/` | 设计文档 |

## 隐私说明

当前用 `ntfy.sh` 公网中转。推送内容会经过 ntfy.sh 服务器:
- 推送传输用 HTTPS 加密
- topic 名 12 位随机串,别人不订阅你的 topic 收不到
- 但 ntfy.sh 运维方理论上能看到推送内容(标题/正文)
- 推送内容包含:**项目目录名 + Claude 的 Notification message**

如对此敏感,建议 **自托管**(下方)。

## 自托管(可选)

ntfy 在 macOS 的预编译/brew 版本是 client-only,没有 server 模式。要自托管 ntfy server 有几种方式:

- **Linux 服务器 / NAS / 树莓派**:`docker run -p 80:80 binwiederhier/ntfy serve`,或 `apt install ntfy`
- **本机 docker**(macOS 上装 Docker Desktop 后):同上
- **本机 go 编译**:`git clone` 后 `make build`(不要打 `noserver` tag),需 GitHub 直连

切换到自托管:改 `scripts/notify-mobile.sh` 里的 `NTFY_URL` 为你的服务器地址,重跑 `./install.sh`。

## 已知限制

- 只支持 Claude Code(VSCode 插件 / CLI),不支持 Codex 桌面端
- 多 VSCode 窗口共用同一 topic,通过正文里的项目名区分
- `Notification` hook 的 `message` 字段内容质量取决于 Claude Code 版本

## 后续可扩展

- 反向控制(手机点选项 → 电脑响应)
- Codex 桌面端接入(需先调研其 hook 能力)
- 多设备区分(不同电脑用不同 topic)
- 自动部署自托管 ntfy server(单独写一个 self-host 脚本)
