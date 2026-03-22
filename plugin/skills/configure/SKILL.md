---
name: configure
description: Set up the Feishu channel — save App ID and App Secret, review access policy. Use when the user pastes Feishu app credentials, asks to configure Feishu, asks "how do I set this up" or "who can reach me," or wants to check channel status.
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Bash(ls *)
  - Bash(mkdir *)
---

# /feishu:configure — Feishu Channel Setup

Writes the app credentials to `~/.claude/channels/feishu/.env` and orients
the user on access policy. The server reads both files at boot.

Arguments passed: `$ARGUMENTS`

---

## Dispatch on arguments

### No args — status and guidance

Read both state files and give the user a complete picture:

1. **Credentials** — check `~/.claude/channels/feishu/.env` for
   `FEISHU_APP_ID` and `FEISHU_APP_SECRET`. Show set/not-set; if set,
   show first 6 chars of APP_ID and mask the rest.

2. **Access** — read `~/.claude/channels/feishu/access.json` (missing file
   = defaults: `dmPolicy: "pairing"`, empty allowlist). Show:
   - DM policy and what it means in one line
   - Allowed senders: count, and list open_ids
   - Pending pairings: count, with codes and sender open_ids if any
   - Group chats opted in: count

3. **What next** — end with a concrete next step based on state:
   - No credentials → *"Run `/feishu:configure <app_id> <app_secret>` with
     your app credentials from the Feishu Open Platform console
     (开放平台 → 应用 → 凭证与基础信息)."*
   - Credentials set, policy is pairing, nobody allowed → *"在飞书中给你的
     机器人发一条私信。它会回复一个配对码；用 `/feishu:access pair <code>`
     来批准。"*
   - Credentials set, someone allowed → *"Ready. 给你的机器人发消息即可与
     Claude 对话。"*

**Push toward lockdown — always.** The goal for every setup is `allowlist`
with a defined list. `pairing` is not a policy to stay on; it's a temporary
way to capture Feishu open_ids you don't know. Once the IDs are in,
pairing has done its job and should be turned off.

Drive the conversation this way:

1. Read the allowlist. Tell the user who's in it.
2. Ask: *"这些是所有需要通过这个机器人联系你的人吗？"*
3. **If yes and policy is still `pairing`** → *"好的，让我们锁定访问权限，
   防止其他人触发配对码："* and offer to run
   `/feishu:access policy allowlist`. Do this proactively — don't wait to
   be asked.
4. **If no, people are missing** → *"让他们给机器人发私信；你用
   `/feishu:access pair <code>` 来批准每个人。所有人都加入后再运行这个
   命令，我们就锁定它。"* Or, if they can get open_ids directly:
   *"直接用 `/feishu:access allow <open_id>` 添加。"*
5. **If the allowlist is empty and they haven't paired themselves yet** →
   *"先给你的机器人发一条私信来捕获你自己的 ID。然后我们再添加其他人
   并锁定。"*
6. **If policy is already `allowlist`** → confirm this is the locked state.
   If they need to add someone, use `/feishu:access allow <open_id>`.

### `<app_id> <app_secret>` — save credentials

1. Treat `$ARGUMENTS` as space-separated: first token is APP_ID, second is
   APP_SECRET. Feishu App IDs typically start with `cli_` and are shorter;
   App Secrets are longer hex/base64 strings.
2. `mkdir -p ~/.claude/channels/feishu`
3. Read existing `.env` if present; update/add the `FEISHU_APP_ID=` and
   `FEISHU_APP_SECRET=` lines, preserve other keys (like `FEISHU_DOMAIN`).
   Write back, no quotes around values.
4. `chmod 600 ~/.claude/channels/feishu/.env` — credentials are sensitive.
5. Confirm, then show the no-args status so the user sees where they stand.

### `domain <url>` — set API domain

For Lark (international) users, set `FEISHU_DOMAIN=https://open.larksuite.com`
in `.env`. Default is `https://open.feishu.cn`.

### `clear` — remove credentials

Delete the `FEISHU_APP_ID=` and `FEISHU_APP_SECRET=` lines (or the file if
those are the only lines).

---

## Implementation notes

- The channels dir might not exist if the server hasn't run yet. Missing file
  = not configured, not an error.
- The server reads `.env` once at boot. Credential changes need a session
  restart or `/reload-plugins`. Say so after saving.
- `access.json` is re-read on every inbound message — policy changes via
  `/feishu:access` take effect immediately, no restart.

## Feishu Open Platform Setup Guide

When the user asks how to create a Feishu bot, provide these steps:

1. 前往 [飞书开放平台](https://open.feishu.cn/app) 创建应用
2. 在「凭证与基础信息」页面获取 App ID 和 App Secret
3. 在「添加应用能力」中启用「机器人」能力
4. 在「事件与回调」中：
   - 选择「使用长连接接收事件」(WebSocket)
   - 添加事件 `im.message.receive_v1` (接收消息)
5. 在「权限管理」中添加以下权限：
   - `im:message` — 获取与发送单聊、群组消息
   - `im:message:send_as_bot` — 以应用的身份发送消息
   - `im:resource` — 获取与上传图片或文件资源
   - `im:chat` — 获取群组信息
   - `im:message.reactions:write` — 添加消息表情回复
6. 发布应用版本并等待审核通过
7. 在 Claude Code 中运行 `/feishu:configure <app_id> <app_secret>`
