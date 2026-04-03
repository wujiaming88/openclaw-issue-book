# lossless-claw "messages.0 is empty" — 最终诊断报告

**日期**: 2026-04-03
**状态**: ✅ 已解决

## 问题

Anthropic API 返回 "The content field in the Message object at messages.0 is empty"，多个 agent 无法正常响应。

## 最终根因

lossless-claw 数据库中存在 `content=""` 且无 `message_parts` 的 assistant 消息记录。assembler 的 `contentFromParts()` 对这些消息返回空数组 `[]`，违反 Anthropic API 的非空 content 要求。

空消息产生于用户从 lossless-claw 0.4.0 升级到 0.5.x 期间，0.5.x 的 Bedrock auth 检测机制导致 compaction 部分失败，留下了垃圾数据。回退 0.4.0 后垃圾数据仍在库中，且正常对话也会持续产生新的空消息（tool-use-only assistant turn 存储时 content 为空）。

## 修复

在 `assembler.ts` 的 `assemble()` 输出处加一行 filter，过滤掉空 content 的 assistant 消息：

```typescript
const cleaned = rawMessages.filter((m) => !(m?.role === "assistant" && (Array.isArray(m.content) ? m.content.length === 0 : !m.content)));
return {
    messages: sanitizeToolUseResultPairing(cleaned) as AgentMessage[],
```

- 文件: `~/.openclaw/extensions/lossless-claw/src/assembler.ts`
- 位置: `assemble()` 方法 return 前
- 影响: 零记忆丢失（空消息无信息量）

## 诊断过程中的误判

| # | 假设 | 结论 | 教训 |
|---|------|------|------|
| 1 | compaction auth 失败导致堆积 | ❌ compaction 一直正常 | 先查数据再猜因果 |
| 2 | runtime.modelAuth 破坏 Bedrock | ❌ 摘要持续产生 | 用数据验证不用推理 |
| 3 | detectProviderAuthError 误报 | ❌ 正则没匹配到 | 先测再断言 |
| 4 | 0.4.0 静默降级 fallback | ❌ 全是 LLM 摘要 | 查 DB 比查 changelog 准 |
| 5 | opus-4-6 格式要求更严 | ❌ opus-4-5 也报错 | 控制变量验证 |
| 6 | 只是历史垃圾数据 | ❌ 空消息持续产生 | 清数据后要验证 |
| 7 | assembler 输出层未过滤 | ✅ 一行 filter 解决 | 加 debug 日志定位 |

## 关键教训

1. **应该一开始就在 assembler 输出处加 debug 日志看实际数据**，而不是从 changelog/源码猜因果链
2. **用数据库查询验证假设**比读源码推理更可靠
3. **空消息是持续产生的活跃问题**，不是一次性历史数据——清理无法根治，必须代码修复

## 标签

`plugin` `lossless-claw` `assembler` `anthropic` `empty-content` `bedrock` `已解决`
