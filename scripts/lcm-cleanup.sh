#!/usr/bin/env bash
# lcm-cleanup.sh — 清理 lossless-claw 数据库中有问题的空 assistant 消息
#
# 用法:
#   ./lcm-cleanup.sh                          # dry-run 模式（默认，只查不删）
#   ./lcm-cleanup.sh --dry-run                # 同上
#   ./lcm-cleanup.sh --execute                # 真正执行删除
#   ./lcm-cleanup.sh --db /path/to/file.db    # 指定数据库文件
#   ./lcm-cleanup.sh --agent arkclaw          # 按 agent 名过滤
#   ./lcm-cleanup.sh --conversation 5         # 按 conversation ID 过滤
#   ./lcm-cleanup.sh --backup                 # 仅备份数据库
#   ./lcm-cleanup.sh --backup --backup-dir /mnt/backup  # 备份到指定目录
#   ./lcm-cleanup.sh --restore {backup_file}  # 从备份恢复
#
# 示例:
#   ./lcm-cleanup.sh --db ~/.openclaw/lcm/conversations.db --agent arkclaw --dry-run
#   ./lcm-cleanup.sh --db ~/.openclaw/lcm/conversations.db --execute
#   ./lcm-cleanup.sh --backup                 # 备份所有 LCM 数据库
#   ./lcm-cleanup.sh --restore ~/.openclaw/lcm/conversations.db.bak.20260402_180000

set -euo pipefail

# ── 默认值 ──────────────────────────────────────────────────────────────────
MODE="dry-run"  # dry-run | execute | backup | restore
DB_PATH=""
AGENT_FILTER=""
CONVERSATION_FILTER=""
LCM_DIR="${HOME}/.openclaw/lcm"
BACKUP_DIR=""
RESTORE_FILE=""

# ── 颜色 ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ── 参数解析 ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      MODE="dry-run"; shift ;;
    --execute)
      MODE="execute"; shift ;;
    --backup)
      MODE="backup"; shift ;;
    --restore)
      MODE="restore"; RESTORE_FILE="$2"; shift 2 ;;
    --backup-dir)
      BACKUP_DIR="$2"; shift 2 ;;
    --db)
      DB_PATH="$2"; shift 2 ;;
    --agent)
      AGENT_FILTER="$2"; shift 2 ;;
    --conversation)
      CONVERSATION_FILTER="$2"; shift 2 ;;
    -h|--help)
      head -15 "$0" | tail -13
      exit 0 ;;
    *)
      echo -e "${RED}未知参数: $1${NC}"; exit 1 ;;
  esac
done

# ── 自动发现数据库 ──────────────────────────────────────────────────────────
if [[ -z "$DB_PATH" ]]; then
  echo -e "${CYAN}🔍 自动搜索 LCM 数据库...${NC}"
  mapfile -t DB_FILES < <(find "$LCM_DIR" -type f -name "*.db" 2>/dev/null)
  
  if [[ ${#DB_FILES[@]} -eq 0 ]]; then
    echo -e "${RED}❌ 未找到 LCM 数据库文件，请用 --db 指定路径${NC}"
    exit 1
  elif [[ ${#DB_FILES[@]} -eq 1 ]]; then
    DB_PATH="${DB_FILES[0]}"
    echo -e "   找到: ${GREEN}${DB_PATH}${NC}"
  else
    echo -e "   找到多个数据库:"
    for i in "${!DB_FILES[@]}"; do
      echo -e "   ${YELLOW}[$i]${NC} ${DB_FILES[$i]}"
    done
    echo ""
    read -rp "请选择 (输入序号): " choice
    DB_PATH="${DB_FILES[$choice]}"
  fi
fi

# ── 恢复模式 ──────────────────────────────────────────────────────────────
if [[ "$MODE" == "restore" ]]; then
  if [[ -z "$RESTORE_FILE" || ! -f "$RESTORE_FILE" ]]; then
    echo -e "${RED}❌ 备份文件不存在: ${RESTORE_FILE}${NC}"
    exit 1
  fi
  
  # 从备份文件名推断原始路径
  # 格式: xxx.db.bak.20260402_180000 → xxx.db
  ORIG_PATH=$(echo "$RESTORE_FILE" | sed 's/\.bak\.[0-9_]*//')
  
  echo -e "${CYAN}🔄 恢复数据库${NC}"
  echo -e "   备份文件: ${YELLOW}${RESTORE_FILE}${NC}"
  echo -e "   恢复到:   ${YELLOW}${ORIG_PATH}${NC}"
  echo ""
  read -rp "确认恢复？(输入 yes): " confirm
  if [[ "$confirm" != "yes" ]]; then
    echo "已取消。"
    exit 0
  fi
  
  cp "$RESTORE_FILE" "$ORIG_PATH"
  echo -e "${GREEN}✅ 恢复完成！重启 Gateway 生效: openclaw gateway start${NC}"
  exit 0
fi

# ── 备份模式 ──────────────────────────────────────────────────────────────
if [[ "$MODE" == "backup" ]]; then
  TARGET_DIR="${BACKUP_DIR:-${LCM_DIR}/backups}"
  mkdir -p "$TARGET_DIR"
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  
  if [[ -n "$DB_PATH" ]]; then
    # 备份指定数据库
    DB_FILES=("$DB_PATH")
  else
    # 备份所有数据库
    mapfile -t DB_FILES < <(find "$LCM_DIR" -maxdepth 1 -type f -name "*.db" 2>/dev/null)
  fi
  
  if [[ ${#DB_FILES[@]} -eq 0 ]]; then
    echo -e "${RED}❌ 未找到 LCM 数据库文件${NC}"
    exit 1
  fi
  
  echo -e "${CYAN}📦 备份 LCM 数据库${NC}"
  echo -e "   目标目录: ${TARGET_DIR}"
  echo ""
  
  TOTAL_SIZE=0
  for db in "${DB_FILES[@]}"; do
    BASENAME=$(basename "$db")
    BACKUP_FILE="${TARGET_DIR}/${BASENAME}.bak.${TIMESTAMP}"
    
    # 使用 sqlite3 的 .backup 命令确保一致性（处理 WAL 模式）
    if command -v sqlite3 &>/dev/null; then
      sqlite3 "$db" ".backup '${BACKUP_FILE}'"
    else
      cp "$db" "$BACKUP_FILE"
      # 也复制 WAL 和 SHM 文件
      [[ -f "${db}-wal" ]] && cp "${db}-wal" "${BACKUP_FILE}-wal"
      [[ -f "${db}-shm" ]] && cp "${db}-shm" "${BACKUP_FILE}-shm"
    fi
    
    FILE_SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
    echo -e "   ✅ ${BASENAME} → ${GREEN}${BACKUP_FILE}${NC} (${FILE_SIZE})"
  done
  
  # 清理旧备份（保留最近 10 个）
  echo ""
  OLD_COUNT=$(find "$TARGET_DIR" -name "*.bak.*" -type f | sort | head -n -10 | wc -l)
  if [[ $OLD_COUNT -gt 0 ]]; then
    echo -e "${YELLOW}🧹 清理旧备份（保留最近 10 个）...${NC}"
    find "$TARGET_DIR" -name "*.bak.*" -type f | sort | head -n -10 | xargs rm -f
    echo -e "   删除 ${OLD_COUNT} 个旧备份"
  fi
  
  echo ""
  echo -e "${GREEN}✅ 备份完成！${NC}"
  echo ""
  echo "恢复命令:"
  echo -e "  ${CYAN}$0 --restore ${BACKUP_FILE}${NC}"
  exit 0
fi

# ── 检查数据库文件 ────────────────────────────────────────────────────────
if [[ ! -f "$DB_PATH" ]]; then
  echo -e "${RED}❌ 数据库文件不存在: ${DB_PATH}${NC}"
  exit 1
fi

echo ""
if [[ "$MODE" == "dry-run" ]]; then
  echo -e "${YELLOW}━━━ DRY-RUN 模式（只查不删）━━━${NC}"
else
  echo -e "${RED}━━━ EXECUTE 模式（将执行删除）━━━${NC}"
fi
echo -e "数据库: ${CYAN}${DB_PATH}${NC}"
echo ""

# ── 构建过滤条件 ──────────────────────────────────────────────────────────
CONV_WHERE=""
if [[ -n "$AGENT_FILTER" ]]; then
  CONV_WHERE="AND c.session_key LIKE '%${AGENT_FILTER}%'"
  echo -e "Agent 过滤: ${CYAN}${AGENT_FILTER}${NC}"
fi
if [[ -n "$CONVERSATION_FILTER" ]]; then
  CONV_WHERE="AND m.conversation_id = ${CONVERSATION_FILTER}"
  echo -e "Conversation 过滤: ${CYAN}${CONVERSATION_FILTER}${NC}"
fi

# ── Step 1: 概览 ──────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}📊 数据库概览${NC}"
sqlite3 -header -column "$DB_PATH" "
SELECT 
  c.id as conv_id,
  c.session_key,
  COUNT(m.message_id) as total_messages,
  SUM(CASE WHEN m.role = 'assistant' THEN 1 ELSE 0 END) as assistant_msgs,
  c.created_at
FROM conversations c
LEFT JOIN messages m ON m.conversation_id = c.id
GROUP BY c.id
ORDER BY c.created_at DESC
LIMIT 20;
"

# ── Step 2: 查找问题消息 ──────────────────────────────────────────────────

# 类型 A: content 为空的 assistant 消息（无 parts）
echo ""
echo -e "${CYAN}🔍 查找问题消息...${NC}"
echo ""
echo -e "${YELLOW}[A] 空 content + 无 parts 的 assistant 消息:${NC}"
COUNT_A=$(sqlite3 "$DB_PATH" "
SELECT COUNT(*) FROM messages m
LEFT JOIN message_parts mp ON mp.message_id = m.message_id
LEFT JOIN conversations c ON c.id = m.conversation_id
WHERE m.role = 'assistant'
  AND (m.content IS NULL OR m.content = '' OR m.content = '[]')
  ${CONV_WHERE}
GROUP BY m.message_id
HAVING COUNT(mp.part_id) = 0;
" | wc -l)

sqlite3 -header -column "$DB_PATH" "
SELECT m.message_id, m.conversation_id, m.role, m.ordinal,
       COALESCE(length(m.content), 0) as content_len,
       m.content as content_preview,
       COUNT(mp.part_id) as part_count,
       m.created_at
FROM messages m
LEFT JOIN message_parts mp ON mp.message_id = m.message_id
LEFT JOIN conversations c ON c.id = m.conversation_id
WHERE m.role = 'assistant'
  AND (m.content IS NULL OR m.content = '' OR m.content = '[]')
  ${CONV_WHERE}
GROUP BY m.message_id
HAVING COUNT(mp.part_id) = 0
ORDER BY m.created_at DESC;
"
echo -e "   共 ${RED}${COUNT_A}${NC} 条"

# 类型 B: content 只有空数组的 assistant 消息
echo ""
echo -e "${YELLOW}[B] content 为 '[]' 的 assistant 消息（有 parts 但可能有问题）:${NC}"
sqlite3 -header -column "$DB_PATH" "
SELECT m.message_id, m.conversation_id, m.ordinal,
       m.content as content_preview,
       COUNT(mp.part_id) as part_count,
       m.created_at
FROM messages m
LEFT JOIN message_parts mp ON mp.message_id = m.message_id
LEFT JOIN conversations c ON c.id = m.conversation_id
WHERE m.role = 'assistant'
  AND m.content = '[]'
  ${CONV_WHERE}
GROUP BY m.message_id
HAVING COUNT(mp.part_id) > 0
ORDER BY m.created_at DESC
LIMIT 20;
"

# 类型 C: 孤立的 tool_result（对应的 tool_call 已丢失）
echo ""
echo -e "${YELLOW}[C] context_items 中引用了不存在的消息:${NC}"
COUNT_C=$(sqlite3 "$DB_PATH" "
SELECT COUNT(*) FROM context_items ci
LEFT JOIN messages m ON m.message_id = ci.message_id
WHERE ci.item_type = 'message'
  AND m.message_id IS NULL;
")
echo -e "   共 ${RED}${COUNT_C}${NC} 条孤立引用"

# ── Step 3: 执行或提示 ──────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$MODE" == "dry-run" ]]; then
  echo ""
  echo -e "${GREEN}✅ dry-run 完成。以上是将被清理的问题数据。${NC}"
  echo ""
  echo "下一步:"
  echo -e "  1. 备份:   ${CYAN}$0 --db ${DB_PATH} --backup${NC}"
  echo -e "  2. 清理:   ${CYAN}$0 --db ${DB_PATH} --execute${NC}"
  exit 0
fi

# ── 真正执行 ──────────────────────────────────────────────────────────────
echo ""
echo -e "${RED}⚠️  即将执行删除操作！${NC}"
echo ""
read -rp "确认继续？(输入 yes): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "已取消。"
  exit 0
fi

# 备份
BACKUP="${DB_PATH}.bak.$(date +%Y%m%d_%H%M%S)"
echo -e "${CYAN}📦 备份到: ${BACKUP}${NC}"
cp "$DB_PATH" "$BACKUP"

echo -e "${CYAN}🧹 开始清理...${NC}"

# A: 删除空 assistant 消息（无 parts）
DELETED_A=$(sqlite3 "$DB_PATH" "
-- 收集要删除的 message_id
CREATE TEMP TABLE _empty_assistant AS
SELECT m.message_id FROM messages m
LEFT JOIN message_parts mp ON mp.message_id = m.message_id
LEFT JOIN conversations c ON c.id = m.conversation_id
WHERE m.role = 'assistant'
  AND (m.content IS NULL OR m.content = '' OR m.content = '[]')
  ${CONV_WHERE}
GROUP BY m.message_id
HAVING COUNT(mp.part_id) = 0;

-- 删除 context_items 引用
DELETE FROM context_items WHERE item_type = 'message' 
  AND message_id IN (SELECT message_id FROM _empty_assistant);

-- 删除 parts（以防万一）
DELETE FROM message_parts WHERE message_id IN (SELECT message_id FROM _empty_assistant);

-- 删除消息本身
DELETE FROM messages WHERE message_id IN (SELECT message_id FROM _empty_assistant);

SELECT changes();
")
echo -e "   [A] 删除空 assistant 消息: ${GREEN}${DELETED_A}${NC} 条"

# C: 清理孤立的 context_items 引用
DELETED_C=$(sqlite3 "$DB_PATH" "
DELETE FROM context_items WHERE item_type = 'message'
  AND message_id NOT IN (SELECT message_id FROM messages);
SELECT changes();
")
echo -e "   [C] 清理孤立 context_items: ${GREEN}${DELETED_C}${NC} 条"

# VACUUM
sqlite3 "$DB_PATH" "VACUUM;"
echo -e "   VACUUM 完成"

echo ""
echo -e "${GREEN}✅ 清理完成！${NC}"
echo ""
echo "后续步骤:"
echo -e "  1. ${CYAN}openclaw gateway start${NC}"
echo -e "  2. 测试对话是否正常"
echo -e "  3. 如有问题，恢复备份: ${CYAN}cp ${BACKUP} ${DB_PATH}${NC}"
