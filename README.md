# 🔗 Claude Code Feishu Channel

> 让 Claude Code 连接飞书 —— 在飞书聊天中直接与 Claude 对话，像真人助手一样帮你写代码、查问题、做任务。

<p align="center">
  <img src="https://img.shields.io/badge/Claude_Code-Channel_Plugin-7C3AED?style=for-the-badge&logo=anthropic" alt="Claude Code Channel Plugin" />
  <img src="https://img.shields.io/badge/飞书-Feishu_/_Lark-00D6B9?style=for-the-badge" alt="Feishu / Lark" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="MIT License" />
</p>

---

## 这是什么？

Claude Code 的 [Channels](https://code.claude.com/docs/en/channels) 是一种将外部消息推送到正在运行的 Claude Code 会话的机制。官方提供了 Telegram 和 Discord 的 Channel 插件，但**没有飞书**。

本项目是社区首个 **飞书（Feishu / Lark）Channel 插件**，让你可以：

- 📱 **在飞书中给机器人发消息**，消息会实时推送到你本地的 Claude Code 会话
- 💬 **Claude 在终端完成工作后，自动将结果回复到飞书**
- 📎 **支持图片和文件**，双向传输
- 🔒 **安全的配对机制**，只有你授权的人才能使用

**一句话：出门在外也能用飞书指挥 Claude 帮你干活。**

## 工作原理

```
飞书 App ──── WebSocket 长连接 ────┐
                                  ▼
                        ┌──────────────────┐
你在飞书发消息 ─────────▶│  Feishu Channel  │──── stdio ────▶ Claude Code 会话
Claude 的回复 ◀─────────│   (本地 MCP 服务)  │◀─── stdio ────  (你的终端)
                        └──────────────────┘
```

- 插件作为 MCP 服务器运行在你的本地机器上
- 通过飞书 WebSocket 长连接接收消息，**无需公网 IP 或域名**
- Claude Code 通过 stdio 与插件通信
- Claude 在终端正常工作（读文件、跑命令等），完成后将结果发送到飞书

## 快速开始

### 前置条件

- [Claude Code](https://code.claude.com) v2.1.80+（需要 claude.ai 账号登录）
- [Bun](https://bun.sh) 运行时（`curl -fsSL https://bun.sh/install | bash`）
- 飞书开放平台应用（下面会教你创建）

### 第一步：创建飞书机器人

1. 前往 [飞书开放平台](https://open.feishu.cn/app) → 创建企业自建应用
2. 在「凭证与基础信息」页面，记下 **App ID** 和 **App Secret**
3. 在「添加应用能力」中，启用 **机器人** 能力
4. 在「事件与回调」中：
   - 配置方式选择 **使用长连接接收事件**（WebSocket，无需服务器）
   - 添加事件：`im.message.receive_v1`（接收消息 v2.0）
   - **注意**：需要先启动 Channel（第四步），飞书平台检测到连接后才能保存此配置
5. 在「权限管理」中，添加以下权限并开通：

| 权限 | 说明 |
|------|------|
| `im:message` | 获取与发送单聊、群组消息 |
| `im:message:send_as_bot` | 以应用的身份发送消息 |
| `im:resource` | 获取与上传图片或文件资源 |
| `im:chat` | 获取群组信息 |
| `im:message.reactions:write` | 添加消息表情回复 |

6. 创建应用版本并发布（企业内部应用可直接发布）

### 第二步：安装插件

在 Claude Code 中运行以下命令：

```bash
# 添加插件仓库（首次使用）
/plugin marketplace add whobot-ai/claude-code-feishu-channel

# 安装飞书 Channel 插件
/plugin install feishu@claude-code-feishu-channel
```

安装完成后，运行 `/reload-plugins` 激活插件命令。

### 第三步：配置凭证

在 Claude Code 中运行：

```
/feishu:configure <你的App_ID> <你的App_Secret>
```

或手动配置：

```bash
mkdir -p ~/.claude/channels/feishu
cat > ~/.claude/channels/feishu/.env << 'EOF'
FEISHU_APP_ID=cli_xxxx
FEISHU_APP_SECRET=xxxx
EOF
chmod 600 ~/.claude/channels/feishu/.env
```

### 第四步：启动

退出 Claude Code，然后用 Channel 标志重新启动：

```bash
claude --dangerously-load-development-channels plugin:feishu@claude-code-feishu-channel
```

> **注意**：研究预览阶段，自定义 Channel 需要 `--dangerously-load-development-channels` 标志，启动时会有安全提示，确认即可。

> **提示**：如果第一步中飞书平台「使用长连接接收事件」无法保存，先完成此步启动 Channel，平台检测到 WebSocket 连接后即可保存。

### 第五步：配对你的账号

1. 在飞书中找到你的机器人，发一条私信
2. 机器人会回复一个 6 位配对码
3. 回到 Claude Code 终端，运行：

```
/feishu:access pair <配对码>
```

4. 锁定访问，防止他人触发配对：

```
/feishu:access policy allowlist
```

**搞定！** 现在你可以在飞书中和 Claude 对话了。

## 功能一览

### MCP 工具

插件为 Claude 提供了 5 个工具：

| 工具 | 功能 |
|------|------|
| `reply` | 发送文本消息到飞书，支持引用回复和文件附件 |
| `react` | 给消息添加表情回复（THUMBSUP, SMILE 等） |
| `edit_message` | 编辑已发送的消息（适合进度更新） |
| `download_attachment` | 下载消息中的图片/文件到本地 |
| `fetch_messages` | 拉取聊天历史记录 |

### 消息处理流程

```
飞书消息到达 → 添加 👍 已读确认 → Claude 在终端正常工作 → 结果发送到飞书
```

Claude 会像处理终端输入一样完整处理飞书消息：读文件、跑命令、搜索代码，全过程在终端可见。完成后将结果通过 reply 发送到飞书。

### 访问控制

与官方 Discord/Telegram 插件一致的安全模型：

| 策略 | 行为 |
|------|------|
| `pairing`（默认） | 未知用户发消息 → 回复配对码 → 终端批准 |
| `allowlist` | 仅白名单用户通过，其他人静默丢弃 |
| `disabled` | 关闭所有消息接收 |

### 群组聊天支持

```bash
# 添加群组（需要 @提及 机器人才会响应）
/feishu:access group add <chat_id>

# 添加群组（所有消息都响应）
/feishu:access group add <chat_id> --no-mention

# 限制群组中哪些人可以触发
/feishu:access group add <chat_id> --allow ou_xxx,ou_yyy

# 移除群组
/feishu:access group rm <chat_id>
```

### Skill 命令参考

| 命令 | 说明 |
|------|------|
| `/feishu:configure` | 查看配置状态 |
| `/feishu:configure <id> <secret>` | 保存飞书应用凭证 |
| `/feishu:configure domain <url>` | 设置 API 域名（Lark 国际版） |
| `/feishu:access` | 查看访问控制状态 |
| `/feishu:access pair <code>` | 批准配对 |
| `/feishu:access allow <open_id>` | 手动添加白名单 |
| `/feishu:access remove <open_id>` | 移除白名单 |
| `/feishu:access policy <mode>` | 设置策略：pairing / allowlist / disabled |
| `/feishu:access group add <chat_id>` | 启用群组 |
| `/feishu:access group rm <chat_id>` | 禁用群组 |
| `/feishu:access set ackReaction THUMBSUP` | 设置已读回复表情（空字符串关闭） |

## Lark 国际版

如果你使用的是 Lark（飞书国际版），需要设置 API 域名：

```
/feishu:configure domain https://open.larksuite.com
```

或在 `~/.claude/channels/feishu/.env` 中添加：

```
FEISHU_DOMAIN=https://open.larksuite.com
```

## 配置文件

| 文件 | 说明 |
|------|------|
| `~/.claude/channels/feishu/.env` | 应用凭证（App ID / Secret） |
| `~/.claude/channels/feishu/access.json` | 访问控制状态（白名单、配对、群组） |
| `~/.claude/channels/feishu/inbox/` | 下载的附件暂存目录 |

## 与官方插件对比

| 特性 | Discord (官方) | Telegram (官方) | **Feishu (本项目)** |
|------|:-:|:-:|:-:|
| 双向消息 | ✅ | ✅ | ✅ |
| 配对认证 | ✅ | ✅ | ✅ |
| 群组支持 | ✅ | ❌ | ✅ |
| @提及触发 | ✅ | ❌ | ✅ |
| 文件附件 | ✅ | ✅ | ✅ |
| 表情回复 | ✅ | ❌ | ✅ |
| 消息编辑 | ✅ | ❌ | ✅ |
| 无需公网 IP | ✅ | ✅ | ✅ |

## 常见问题

**Q: 飞书开放平台「使用长连接接收事件」无法保存？**
需要先启动 Channel（第四步），飞书平台检测到 WebSocket 连接后才能保存配置。先配置凭证并启动 Claude Code，然后回到飞书平台保存。

**Q: 机器人没有回复我的消息？**
确保 Claude Code 正在运行并带有 `--dangerously-load-development-channels` 标志。机器人只在 Claude Code 会话活跃时才能响应。

**Q: 权限不足？**
检查飞书开放平台中是否已开通所有必要权限，并且应用版本已发布。

**Q: 如何在无人值守时使用？**
配合 `--dangerously-skip-permissions` 使用，但请确保在你信任的环境中运行。

**Q: Team/Enterprise 组织无法使用？**
需要组织管理员在 Claude 管理后台启用 Channels 功能。

## 开发

如果你想本地开发或修改此插件：

```bash
# 克隆项目
git clone https://github.com/whobot-ai/claude-code-feishu-channel.git
cd claude-code-feishu-channel/plugin

# 安装依赖
bun install

# 配置凭证后，在项目根目录以开发模式启动：
cd ..
claude --dangerously-load-development-channels server:feishu
```

## 致谢

- [Claude Code Channels](https://code.claude.com/docs/en/channels) — Anthropic 的 Channel 机制
- [claude-plugins-official](https://github.com/anthropics/claude-plugins-official) — 官方 Discord/Telegram 插件参考实现
- [飞书开放平台](https://open.feishu.cn) — 飞书 Bot API

## 许可证

[MIT](./plugin/LICENSE)
