# TUI 连接 Gateway 报 unauthorized（systemd service 内嵌旧 token）

## 问题描述

用户在服务器上运行 `openclaw tui`，TUI 反复报错 `gateway disconnected: unauthorized`，无法连接 Gateway。

## 环境信息

- **OpenClaw 版本**: 2026.3.2 → 2026.3.13
- **OS**: Linux (Ubuntu)
- **Gateway 配置**:
  - `gateway.bind`: `lan`
  - `gateway.auth.mode`: `trusted-proxy`
  - `gateway.auth.trustedProxy.userHeader`: `x-forwarded-user`
- **服务管理**: systemd

## 症状

```
openclaw tui - ws://127.0.0.1:18789 - agent main - session main
connecting | idle
gateway disconnected: unauthorized | idle
gateway connect failed: Error: unauthorized
```

TUI 反复尝试连接，持续收到 `unauthorized` 错误。

## 根因分析

两个因素叠加导致问题：

1. **systemd service 文件内嵌了旧的 `OPENCLAW_GATEWAY_TOKEN`**：service 文件中 hardcode 了一个旧 token，与当前配置文件中的 `gateway.auth.token` 不一致，导致 Gateway 启动时使用了错误的认证凭据。

2. **auth 模式为 `trusted-proxy`**：该模式下 Gateway 只信任通过反向代理传入的请求（带有 `x-forwarded-user` 头），直连的 TUI WebSocket 请求不带此头，被视为未授权。

`openclaw gateway status` 输出中有明确提示：
```
Service config issue: Gateway service embeds OPENCLAW_GATEWAY_TOKEN and should be reinstalled.
Gateway service OPENCLAW_GATEWAY_TOKEN does not match gateway.auth.token in openclaw.json (service token is stale)
```

## 解决方案

### 步骤 1：运行 doctor 修复

```bash
openclaw doctor --repair
```

Doctor 自动执行了：
- 重新生成 systemd service 文件（移除内嵌的旧 token）
- 收紧 `~/.openclaw` 目录权限至 700
- 重启 Gateway 服务

### 步骤 2：确认 Gateway 正常

```bash
openclaw gateway status
# 确认 Runtime: running, RPC probe: ok
```

### 步骤 3：重新连接 TUI

```bash
openclaw tui
```

修复后 TUI 成功连接，不再报 `unauthorized`。

## 参考资料

- 文档：https://docs.openclaw.ai/gateway/troubleshooting
- 文档：https://docs.openclaw.ai/gateway/authentication
- 本地文档：`/usr/lib/node_modules/openclaw/docs/gateway/troubleshooting.md`

## 标签

`gateway` `tui` `unauthorized` `systemd` `service-token` `trusted-proxy` `doctor`
