# OpenClaw Issue Book 📖

OpenClaw 问题诊断记录手册 — 由 ClawDoctor 自动维护。

## 分类

| 分类 | 目录 | 说明 |
|------|------|------|
| 🔌 Gateway | `issues/gateway/` | 网关启动、绑定、远程连接 |
| 📡 Channel | `issues/channel/` | 频道配置和连接 |
| 🤖 Provider | `issues/provider/` | AI 提供商、模型、API Key |
| 🧠 Agent | `issues/agent/` | Agent 配置、会话、工作区 |
| 📱 Node | `issues/node/` | 移动端配对和连接 |
| 🔧 Plugin | `issues/plugin/` | 插件加载和配置 |
| 🛠️ Tool | `issues/tool/` | 工具、MCP、技能系统 |
| 💻 CLI | `issues/cli/` | 命令行使用 |
| 📦 Install | `issues/install/` | 安装和升级 |
| 🔒 Security | `issues/security/` | 权限和安全 |
| ⚡ Performance | `issues/performance/` | 性能问题 |
| ❓ Other | `issues/other/` | 其他 |

详见 [CATEGORIES.md](CATEGORIES.md)

## 结构

```
issues/
├── gateway/
│   └── YYYY-MM-DD-简短描述.md
├── channel/
├── provider/
├── agent/
├── node/
├── plugin/
├── tool/
├── cli/
├── install/
├── security/
├── performance/
└── other/
```

## 问题模板

每条记录包含：
- **问题描述**：用户遇到了什么
- **环境信息**：相关版本、配置
- **根因分析**：为什么会出错
- **解决方案**：具体修复步骤
- **参考资料**：文档链接、GitHub Issue 等
- **标签**：分类标签便于检索

## 目录

（自动更新）

| 日期 | 问题 | 标签 |
|------|------|------|
| 2026-03-19 | [Session Tokens (cached) 含义解释](issues/other/2026-03-19-session-tokens-context-解释.md) | `knowledge` `context` `tokens` `session` |
| 2026-03-23 | [飞书 /new 命令无反应](issues/channel/2026-03-23-feishu-slash-command-no-response.md) | `channel` `feishu` `slash-command` `authorization` `allowFrom` |
| 2026-03-25 | [trusted-proxy 模式导致 CLI 命令握手超时](issues/gateway/2026-03-25-trusted-proxy-cli-handshake-timeout.md) | `gateway` `auth` `trusted-proxy` `cli` `handshake-timeout` `websocket` |
| 2026-03-26 | [doctor needsToken 逻辑误判 trusted-proxy 模式](issues/cli/2026-03-26-doctor-needsToken-trusted-proxy-误判.md) | `cli` `doctor` `auth` `trusted-proxy` `needsToken` `已修复` |
| 2026-04-02 | [TUI 连接 Gateway 报错 token mismatch](issues/cli/2026-04-02-tui-gateway-token-mismatch.md) | `cli` `tui` `gateway` `token` `auth` `已解决` |
