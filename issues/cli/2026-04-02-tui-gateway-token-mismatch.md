# TUI 连接 Gateway 报错 token mismatch

## 问题描述

用户打开 OpenClaw TUI 时报错：
```
gateway connect failed: GatewayClientRequestError: unauthorized: gateway token mismatch (open the dashboard URL and paste the token in Control UI settings)
```

## 环境信息

- **OpenClaw 版本**: 未提供
- **OS**: 未提供
- **相关配置**: TUI 连接 Gateway

## 症状

启动 TUI 后无法连接 Gateway，提示 token 不匹配。

## 根因分析

TUI 保存的 Gateway token 与 Gateway 实际使用的 token 不一致。常见原因：
1. Gateway 重启后 token 刷新（未配置固定 token）
2. TUI 缓存了旧 token
3. 手动修改过配置但未同步到 TUI

## 解决方案

1. 运行 `openclaw gateway token` 获取当前有效 token
2. 按报错提示，打开 Dashboard URL，在 Control UI settings 中粘贴正确的 token
3. 或使用 `openclaw tui --token $(openclaw gateway token)` 直接传入 token

## 参考资料

- 报错信息自带修复指引

## 标签

`cli` `tui` `gateway` `token` `auth` `已解决`
