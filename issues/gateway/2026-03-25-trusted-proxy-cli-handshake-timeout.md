# trusted-proxy 模式导致 CLI 命令握手超时

## 问题描述

在 `gateway.auth.mode: "trusted-proxy"` 配置下，执行 `openclaw cron list` 等 CLI/RPC 命令时报错 `gateway closed (1000): no close reason`，连接被 Gateway 主动关闭。

## 环境信息

- **OpenClaw 版本**: 2026.3.13
- **OS**: Linux (arkclaw)
- **Node.js**: v22.22.0
- **相关配置**:
  ```json
  "gateway": {
    "bind": "lan",
    "auth": {
      "mode": "trusted-proxy",
      "token": "***",
      "trustedProxy": {
        "userHeader": "x-forwarded-user"
      }
    },
    "trustedProxies": ["127.0.0.1", "172.31.0.0/16", "192.168.0.0/16"]
  }
  ```

## 症状

```
gateway connect failed: Error: gateway closed (1000): 
Error: gateway closed (1000 normal closure): no close reason
Gateway target: ws://127.0.0.1:18789
Source: local loopback
```

Gateway 日志关键信息：
```json
{
  "cause": "handshake-timeout",
  "handshake": "failed",
  "durationMs": 9668,
  "handshakeMs": 3003
}
```

- `openclaw tui` 同样受影响（之前报 `unauthorized`，经 `openclaw doctor --repair` 修复过服务器端，但 arkclaw 未修复）
- WebSocket 连接建立后 3 秒握手超时，Gateway 返回 1000 正常关闭码

## 根因分析

`trusted-proxy` 认证模式要求所有连接经过反向代理，由代理注入 `x-forwarded-user` 请求头完成身份识别。

但 CLI 命令（`openclaw cron list`、`openclaw tui` 等）通过 WebSocket **直连** Gateway，不经过反向代理：
1. CLI 直连 → 没有 `x-forwarded-user` 头
2. Gateway 等待认证信息 → 3 秒后握手超时
3. Gateway 主动关闭连接 → 返回 close code 1000

**核心矛盾**：`trusted-proxy` 模式天然与 CLI 直连不兼容。所有不经过反向代理的本地连接（CLI、TUI、cron 命令）都会失败。

## 解决方案

### 推荐方案：切换为 token 模式

```bash
openclaw config set gateway.auth.mode token
openclaw gateway restart
```

- CLI/TUI/cron 直连：自动使用配置文件中的 token 认证 ✅
- 反向代理访问：代理转发时附带 token 即可 ✅
- 局域网安全：有 token 保护 ✅

### 备选方案：owner 模式

```bash
openclaw config set gateway.auth.mode owner
openclaw gateway restart
```

- 仅适合 `bind: "loopback"` 场景
- `bind: "lan"` 下不推荐（局域网内无认证保护）

## 关联问题

- 同一根因曾导致 `openclaw tui` 报 `unauthorized` 错误（服务器端已通过 `openclaw doctor --repair` 修复）
- 之前的诊断记录：2026-03-19 TUI unauthorized 问题

## 参考资料

- 文档：https://docs.openclaw.ai/gateway/authentication
- 之前诊断的 trusted-proxy 安全评估

## 标签

`gateway` `auth` `trusted-proxy` `cli` `handshake-timeout` `websocket`
