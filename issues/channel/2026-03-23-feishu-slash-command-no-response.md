# 飞书 /new 命令无反应

## 问题描述

用户在飞书私聊中输入 `/new` 命令没有任何反应，但普通对话正常。

## 环境信息

- **Channel**: 飞书 (Feishu)
- **连接模式**: WebSocket 长连接
- **dmPolicy**: `"open"`
- **allowFrom**: 未配置

## 症状

- 在飞书中发送 `/new` 没有任何反馈
- 普通消息能正常送达和回复
- Gateway 日志显示：
  ```
  system command detected, plain-text dispatch, reply suppressed
  system command dispatched (delivered=false)
  ```
  关键信息：`delivered=false` — 命令被识别但投递失败。

## 根因分析

**消息路由和命令授权是两套独立机制：**

| 层级 | 检查内容 | 用户情况 |
|------|---------|---------|
| 消息路由 | `dmPolicy` 控制消息能否到达 agent | `"open"` → ✅ 正常 |
| 命令授权 | 检查发送者是否在授权组中 | ❌ 未通过 |

- `dmPolicy: "open"` 只放行普通消息，不等同于命令授权
- 命令系统在没有 `commands.allowFrom` 时，回退到检查 channel 的 `allowFrom` / pairing 列表
- 用户的飞书 `allowFrom` 未配置，pairing 也未使用（因为 dmPolicy 是 open）
- 结果：命令系统认为用户不在任何授权组中，静默丢弃命令

**文档明确说明：**
> `dmPolicy: "open"` — Allow all users (**requires `"*"` in allowFrom**)
> Unauthorized command-only messages are silently ignored.

## 解决方案

在 `openclaw.json` 中为飞书配置 `allowFrom`:

```json5
{
  channels: {
    feishu: {
      dmPolicy: "open",
      allowFrom: ["*"],  // 允许所有用户
    }
  }
}
```

快速修复命令：

```bash
openclaw config set channels.feishu.allowFrom '["*"]' && openclaw gateway restart
```

## 参考资料

- 文档：[Feishu Channel](/channels/feishu) — dmPolicy reference 表格
- 文档：[Slash Commands](/tools/slash-commands) — 命令授权机制说明

## 标签

`channel` `feishu` `slash-command` `authorization` `allowFrom`
