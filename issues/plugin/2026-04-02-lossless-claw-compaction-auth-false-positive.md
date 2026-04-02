# lossless-claw compaction 认证误报导致摘要丢弃

- **日期**: 2026-04-02
- **分类**: plugin / lossless-claw
- **严重程度**: 🔴 高（导致对话不可用）
- **影响版本**: lossless-claw 0.2.7+ / OpenClaw v2026.3.8+
- **状态**: 已定位根因，待提 PR

## 症状

1. `The content field in the Message object at messages.0 is empty`（Anthropic API 拒绝）
2. `Cannot read properties of undefined (reading 'replace')`
3. `[lcm] compaction failed: provider auth error`（但 LLM 调用实际成功）

## 根因分析

### 因果链

```
对话内容包含 auth/token 等关键词（如讨论认证问题）
  → LCM compaction 成功生成摘要
  → detectProviderAuthError() 扫描响应内容
  → AUTH_ERROR_TEXT_PATTERN 匹配到摘要中的 "token"/"unauthorized"/"401" 等词
  → 误判为认证失败 → 丢弃已生成的摘要
  → compaction 持续失败 → 旧消息无法压缩
  → 空 content 的 assistant 消息（tool-call-only turn）积累
  → assembler 输出空 content → Anthropic API 拒绝
```

### 关键代码位置

**`src/plugin/index.ts`** 中的 `detectProviderAuthError()` 函数：

```typescript
const AUTH_ERROR_TEXT_PATTERN =
  /\b401\b|unauthorized|unauthorised|invalid[_ -]?token|
   authentication failed|authorization failed|.../i;
```

`collectErrorText()` 递归遍历对象的所有字符串值，包括 LLM 响应内容。
当响应内容恰好包含认证相关关键词时，会被误判为 provider auth error。

### 触发条件

- 使用 `AWS_BEARER_TOKEN_BEDROCK` 认证（走 `runtime.modelAuth` 路径）
- 对话内容涉及认证/安全话题（摘要中包含 auth 关键词）
- OpenClaw v2026.3.8+ 引入 `runtime.modelAuth` 后才出现

### 日志证据

```
[lcm] compaction failed: provider auth error.
Current: amazon-bedrock/global.anthropic.claude-haiku-4-5-20251001-v1:0
Detail: assistant text # OpenClaw Diagnostic Session Summary...
```

注意 "Detail" 包含完整摘要文本 → **LLM 调用成功了**，但被误判为失败。

## 建议修复

### 修复 1：`detectProviderAuthError` 不应扫描成功响应内容

```typescript
// 只检查 error 对象的 message/code/status，不递归扫描所有字符串
function detectProviderAuthError(error: unknown): CompletionBridgeErrorInfo | undefined {
  // 只检查顶层 error 属性，不深度遍历响应内容
  if (!isRecord(error)) return undefined;
  
  const statusCode = extractErrorStatusCode(error);
  // 只检查 error.message / error.code，不遍历所有子字段
  const message = typeof error.message === 'string' ? error.message : '';
  
  if (statusCode !== 401 && !AUTH_ERROR_TEXT_PATTERN.test(message)) {
    return undefined;
  }
  // ...
}
```

### 修复 2：`contentFromParts` 不返回空数组（防御层）

```typescript
// 当前
return fallbackContent ? [{ type: "text", text: fallbackContent }] : [];
// 修复
return [{ type: "text", text: fallbackContent || "" }];
```

### 修复 3：`assemble()` 输出前过滤空 content 消息

```typescript
const safeMessages = rawMessages.filter(msg => {
  if (msg?.role === "assistant" && Array.isArray(msg.content) && msg.content.length === 0) {
    return false;
  }
  return true;
});
```

## 影响范围

- 任何使用 Bedrock Bearer Token 认证 + 讨论认证相关话题的用户
- 可能影响其他包含特定关键词的对话（如安全审计、密码管理等话题）

## 临时解决方案

1. 清理数据库中 content 长度为 0 且无 parts 的 assistant 消息
2. 换用非 Bedrock provider 做 compaction（避免 runtime.modelAuth 路径）

## 关联

- PR #238: fix/empty-assistant-content-crash（部分修复，未覆盖误报场景）
- OpenClaw PR #41090: runtime.modelAuth 引入
