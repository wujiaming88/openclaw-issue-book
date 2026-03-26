# openclaw doctor needsToken 逻辑误判 trusted-proxy 模式

## 问题描述

旧版 `openclaw doctor` 的 `needsToken` 判断逻辑使用排除法，只认识 `password` 和 `token` 两种模式，导致 `trusted-proxy` 模式被误判为"未配置认证"。在 `--repair` 时可能覆盖用户合法的 `trusted-proxy` 配置。

## 环境信息

- **OpenClaw 版本**: 旧版（具体版本未确认，早于 2026.3.x）
- **OS**: Linux
- **Node.js**: v22.22.0
- **相关配置**:
  ```json
  {
    "gateway": {
      "auth": {
        "mode": "trusted-proxy",
        "token": "***",
        "trustedProxy": {
          "userHeader": "x-forwarded-user"
        }
      }
    }
  }
  ```

## 症状

运行 `openclaw doctor` 时，对 `trusted-proxy` 模式误报：

> "Gateway auth is off or missing a token. Token auth is now the recommended default (including loopback)."

运行 `openclaw doctor --repair` 时，可能自动生成 token 并覆盖 `trusted-proxy` 配置。

## 根因分析

旧版代码（第 157 行）：

```javascript
const needsToken = auth.mode !== "password" && (auth.mode !== "token" || !auth.token);
```

逻辑缺陷：
- 只排除 `password` 和 `token` 两种模式
- `trusted-proxy`、`owner`、`none` 等模式全部被当作"未配置认证"
- `needsToken` 返回 `true` → doctor 认为需要自动生成 token

## 解决方案

### 已修复 ✅

在当前版本（2026.3.13+）中已修复，新逻辑改为**显式列举已知模式**：

```javascript
function shouldRequireGatewayTokenForInstall(cfg, _env) {
    const mode = cfg.gateway?.auth?.mode;
    if (mode === "token") return true;
    if (mode === "password" || mode === "none" || mode === "trusted-proxy") return false;
    // ... 其他检查
    return true;
}
```

`trusted-proxy` 被正确识别 → `return false` → 不会误判为需要 token。

### 用户操作

升级到最新版即可：

```bash
npm update -g openclaw
# 或
pnpm update -g openclaw
```

当前最新版：**2026.3.24**

## 相关问题

- [Issue #17761](https://github.com/openclaw/openclaw/issues/17761): Gateway auth dispatcher blocks all internal services when mode=trusted-proxy
- [Issue #20073](https://github.com/openclaw/openclaw/issues/20073): Bind loopback and auth.mode trusted-proxy not working together
- [Issue #26007](https://github.com/openclaw/openclaw/issues/26007): Feature request: trustedProxy.loopbackUser for CLI/sub-agent access

## 参考资料

- 源码：`/usr/lib/node_modules/openclaw/dist/gateway-install-token-CeShOI6y.js`
- 函数：`shouldRequireGatewayTokenForInstall()`
- 关联诊断：[trusted-proxy 导致 CLI 握手超时](../gateway/2026-03-25-trusted-proxy-cli-handshake-timeout.md)

## 标签

`cli` `doctor` `auth` `trusted-proxy` `needsToken` `已修复`
