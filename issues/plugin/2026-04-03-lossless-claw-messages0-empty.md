# lossless-claw "messages.0 is empty" Anthropic API 报错

## 问题描述

用户使用 lossless-claw 插件时，Anthropic API 返回 "The content field in the Message object at messages.0 is empty" 错误，导致 agent 无法正常响应。

## 环境信息

- **OpenClaw 版本**: v2026.3.28 (后升级到 v2026.4.1)
- **OS**: Ubuntu Linux 6.8.0
- **Node.js**: v22.22.0
- **lossless-claw 版本**: 0.4.0
- **Provider**: amazon-bedrock (Anthropic Claude)

## 症状

1. `"The content field in the Message object at messages.0 is empty"` — Anthropic API 拒绝请求
2. `"Cannot read properties of undefined (reading 'replace')"` — 下游代码崩溃
3. 部分 agent 无法响应，部分正常

## 根因分析

### 直接原因

lossless-claw 的 `assembler.ts` 在重建上下文时，将数据库中 `content=""` 且无 `message_parts` 的 assistant 消息直接输出为空 content 数组 `[]`，违反 Anthropic API 的非空 content 要求。

### `contentFromParts()` 逻辑（assembler.ts 第 428 行）

```typescript
if (parts.length === 0) {
    if (role === "assistant") {
        return fallbackContent ? [{ type: "text", text: fallbackContent }] : [];
        //     ↑ fallbackContent = "" (empty string) → falsy → 返回 []
    }
}
```

### 空消息产生原因

1. 用户曾从 lossless-claw 0.4.0 升级到 0.5.2/0.5.3
2. 0.5.x 版本引入了新的 provider auth 检测机制，与 Bedrock Bearer Token 认证不兼容
3. 在 0.5.x 期间，compaction 产生了 fallback 摘要和空 assistant 消息（167 条）
4. 回退到 0.4.0 后，compaction 恢复正常，但历史垃圾数据留在 DB 里
5. 空消息持续通过正常对话产生（模型返回只有 tool_use 没有文本的 assistant turn）

### 错误链

```
DB 中 assistant 消息 content="" + 0 parts
  → contentFromParts([], "assistant", "") → []
  → assembler 输出 {role: "assistant", content: []}
  → Anthropic API 拒绝: "messages.0 is empty"
  → 下游 retry 代码对 undefined content 调用 .replace() → crash
```

## 解决方案

### 代码修复（一行）

在 `assembler.ts` 第 728 行，`sanitizeToolUseResultPairing(rawMessages)` 前加过滤：

```typescript
// 原来
return {
    messages: sanitizeToolUseResultPairing(rawMessages) as AgentMessage[],

// 改成
const cleaned = rawMessages.filter((m) => !(m?.role === "assistant" && (Array.isArray(m.content) ? m.content.length === 0 : !m.content)));
return {
    messages: sanitizeToolUseResultPairing(cleaned) as AgentMessage[],
```

原理：空消息（content="" + 0 parts）没有任何信息量，过滤掉不丢失记忆。

### 可选：清理历史垃圾数据

```sql
CREATE TEMP TABLE bad_ids AS
  SELECT m.message_id FROM messages m
  LEFT JOIN message_parts mp ON mp.message_id = m.message_id
  WHERE m.role = 'assistant' AND length(m.content) = 0
  GROUP BY m.message_id HAVING COUNT(mp.part_id) = 0;

DELETE FROM summary_messages WHERE message_id IN (SELECT message_id FROM bad_ids);
DELETE FROM context_items WHERE item_type = 'message' AND message_id IN (SELECT message_id FROM bad_ids);
DELETE FROM messages WHERE message_id IN (SELECT message_id FROM bad_ids);
```

⚠️ 仅清理数据不够——空消息会持续产生，必须有代码修复。

## 诊断过程中的误判记录

1. ❌ 最初认为是 compaction auth 失败导致消息堆积 → 实际 compaction 一直正常
2. ❌ 认为 runtime.modelAuth 破坏了 Bedrock 认证 → 数据库证据否定（摘要持续产生到 17:36）
3. ❌ 认为 0.4.0 走 deterministic fallback → 数据库全是 LLM 摘要
4. ✅ 最终确认：空消息由 0.5.x 时期产生 + 持续由正常对话产生，assembler 输出层未过滤

## 风险评估

🟢 低风险 — 修改仅在输出层过滤无信息量的空消息，不影响数据存储和 compaction。

## 参考资料

- lossless-claw CHANGELOG: https://github.com/Martian-Engineering/lossless-claw/blob/main/CHANGELOG.md
- lossless-claw PR #205: Preserve assistant text and matched tool calls when pruning
- lossless-claw PR #228: Compaction fallback to next model
- assembler.ts `contentFromParts()` 第 428 行
- assembler.ts `assemble()` 第 728 行

## 标签

`plugin` `lossless-claw` `assembler` `anthropic` `empty-content` `bedrock`
