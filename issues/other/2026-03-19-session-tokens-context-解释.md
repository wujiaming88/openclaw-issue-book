# Session Tokens (cached) 含义解释

## 问题描述

用户在执行 `/new` 命令后查看 context breakdown，想了解 `Session tokens (cached): 33,082 total / ctx=200000` 的含义。

## 环境信息

- **OpenClaw 版本**: 当前版本
- **OS**: Linux 6.8.0-101-generic (x64)
- **Node.js**: v22.22.0
- **模型**: claude-opus-4-6-v1 (ctx=200,000)

## 症状

非故障类 — 用户对 context breakdown 信息不理解。

## 根因分析

这是知识问答，不涉及故障。`Session tokens` 是 OpenClaw 在发送请求给 LLM 之前计算出的当前会话总 token 数。

### 字段解释

| 字段 | 含义 |
|------|------|
| **Session tokens** | 当前会话已占用的 token 总数 |
| **cached** | 这些 token 已被 prompt caching 缓存，可复用以降低延迟和成本 |
| **33,082 total** | 当前会话总消耗 33,082 个 token |
| **ctx=200000** | 模型上下文窗口上限为 200,000 token |

### Token 组成

一个新会话（`/new` 后）的 ~33K token 大致来源：
- System prompt（系统提示词）：~10,085 tok
- Project Context（工作区文件）：~3,666 tok
- Skills list（技能列表）：~2,107 tok
- Tool schemas（工具定义 JSON）：~12,862 tok
- Tool list text：~2,443 tok
- 对话历史：剩余部分

### 实际意义

- 使用率：33,082 / 200,000 ≈ 16.5%
- 当接近 200K 上限时，OpenClaw 会自动截断较早的对话历史
- 光是系统提示 + 工具定义 + 工作区文件就占了约 33K token

## 解决方案

知识解答，无需修复操作。

## 参考资料

- OpenClaw context breakdown 输出（`/new` 后显示）
- LLM prompt caching 机制

## 标签

`knowledge` `context` `tokens` `session`
