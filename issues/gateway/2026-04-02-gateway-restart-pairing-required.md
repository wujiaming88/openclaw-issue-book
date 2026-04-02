# Gateway 重启后 CLI 报 pairing required

## 问题描述

用户执行 `openclaw gateway restart` 后，运行 `openclaw cron list` 等 CLI 命令报错：
```
gateway connect failed: GatewayClientRequestError: pairing required
Error: gateway closed (1008): pairing required
Gateway target: ws://127.0.0.1:18789
Source: local loopback
Config: /root/.openclaw/openclaw.json
Bind: lan
```

## 环境信息

- **OpenClaw 版本**: 2026.3.28.1
- **OS**: Linux (arkclaw)
- **Gateway target**: ws://127.0.0.1:18789
- **Bind**: lan

## 症状

- Gateway 重启后，CLI 命令无法连接 Gateway
- 报错 `pairing required`
- 连接来源为 local loopback

## 根因分析

Gateway 重启后，CLI 的设备身份（device identity）未通过验证，Gateway 要求重新配对。可能原因：
1. Gateway 重启导致设备认证状态刷新
2. `bind: lan` 模式下安全策略较严格，本地回环连接也需要设备配对
3. 设备 token 在重启后过期或失效

## 解决方案

建议的诊断和修复步骤：

1. `openclaw doctor` — 检查整体状态（此命令在 pairing 失败时仍可用）
2. `openclaw gateway status` — 确认 Gateway 运行状态
3. `openclaw devices list` — 查看设备配对状态
4. `openclaw devices approve <requestId>` — 审批待处理的配对请求
5. 如果以上无效：`openclaw gateway install --force && openclaw gateway restart`

用户自行解决，未提供具体修复步骤细节。

## 参考资料

- 文档：https://docs.openclaw.ai/gateway/troubleshooting （Pairing and device identity state changed）
- 文档：https://docs.openclaw.ai/cli/devices
- 文档：https://docs.openclaw.ai/gateway/pairing

## 标签

`gateway` `cli` `pairing` `device-auth` `restart` `已解决`
