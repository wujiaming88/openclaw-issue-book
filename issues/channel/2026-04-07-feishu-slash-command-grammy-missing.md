# 飞书斜杠命令无响应 — grammy 依赖缺失

## 问题描述

飞书渠道发送斜杠命令（如 `/status`、`/new`）时，OpenClaw 无任何响应，静默失败。

## 环境信息

- **OpenClaw 版本**: v2026.4.2
- **OS**: Linux（火山引擎 VPS）
- **Node.js**: v22.x
- **渠道**: 飞书（通过 openclaw-lark 第三方插件）
- **相关配置**: 内置 feishu 插件 `enabled: false`，使用 `openclaw-lark` 插件

## 症状

- 飞书发送 `/status` 等斜杠命令，机器人无响应
- 普通消息可以正常收发
- "有时候"不响应（取决于命令 dispatch 路径是否触发 sticker-cache 模块）

## 错误日志

```
07:41:42+00:00 info  feishu[default]: detected system command, using plain-text dispatch
07:41:43+00:00 error feishu[default]: failed to dispatch message: Error [ERR_MODULE_NOT_FOUND]: Cannot find package 'grammy' imported from /root/.local/share/pnpm/global/5/.pnpm/openclaw@2026.4.2_@napi-rs+canvas@0.1.97/node_modules/openclaw/dist/sticker-cache-Cf0p9p0n.js
```

## 根因分析

**OpenClaw v2026.3.31+ 已知 Bug**：`sticker-cache` 模块（Telegram 贴纸缓存）对 `grammy`（Telegram SDK）使用静态 import，而非懒加载。命令 dispatch 路径会触发该模块加载，即使用户完全不使用 Telegram 渠道。

当 `grammy` 未安装时（纯飞书部署不需要 Telegram），命令 dispatch 崩溃，导致所有斜杠命令静默失败。

**关键点**：
1. 命令被正确识别（`system command detected, plain-text dispatch`）
2. 在 dispatch 执行阶段因缺少 `grammy` 而崩溃
3. 普通消息不经过此路径，所以正常工作

## 解决方案

手动安装 grammy 依赖：

```bash
cd /root/.local/share/pnpm/global/5/.pnpm/openclaw@2026.4.2_@napi-rs+canvas@0.1.97/node_modules/openclaw
pnpm add grammy --registry=https://registry.npmmirror.com  # 国内用淘宝镜像
openclaw gateway restart
```

> 注意：国内环境 `npm install grammy` 可能超时，建议用 pnpm + 淘宝镜像。

## 排查过程

1. 初始怀疑：权限/白名单问题 → 加 `useAccessGroups: false` 无效
2. 查看日志发现 `grammy` 缺失错误 → 确认根因
3. 搜索 GitHub 发现已知 issue（#59850, #60481, #58701）
4. 安装 grammy 后问题解决

## 参考资料

- GitHub Issue: https://github.com/openclaw/openclaw/issues/59850
- GitHub Issue: https://github.com/openclaw/openclaw/issues/60481
- GitHub Issue: https://github.com/openclaw/openclaw/issues/58701 (v2026.3.31 引入)
- ClawX 同类问题: https://github.com/ValueCell-ai/ClawX/issues/765
- 文档: [斜杠命令](/tools/slash-commands) | [飞书渠道](/channels/feishu)

## 风险评估

🟢 低风险 — `grammy` 是纯 JS 库，安装不影响飞书或其他渠道功能。

## 预防建议

- 等待上游修复（将 sticker-cache 改为动态 import）
- 升级到修复版本后可移除手动安装的 grammy
- 每次 OpenClaw 升级后检查此问题是否复现

## 标签

`channel` `feishu` `grammy` `slash-command` `known-bug` `dependency`
