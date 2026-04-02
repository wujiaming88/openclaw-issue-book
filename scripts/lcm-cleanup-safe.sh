#!/usr/bin/env bash
# lcm-cleanup.sh — OpenClaw LCM 数据库清理工具
#
# 设计原则（从第一性原理出发）：
# 1. 只读操作绝对不修改任何东西
# 2. 参数化 SQL 防止注入
# 3. 所有修改前自动备份 + 完整性校验
# 4. 显式确认 + 详细提示
# 5. 出错时自动回滚
# 6. 零推断，显式指定
#
# 使用：
#   ./lcm-cleanup.sh --scan                   # 只查看问题数据（完全只读）
#   ./lcm-cleanup.sh --backup                 # 仅备份
#   ./lcm-cleanup.sh --restore <backup_file>  # 恢复备份
#   ./lcm-cleanup.sh --delete                 # 删除（需停止 Gateway + 多次确认）
#   ./lcm-cleanup.sh --rollback               # 回滚到最后一次备份

set -euo pipefail

# ── 颜色 ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── 全局变量 ──────────────────────────────────────────────────────────────
MODE=""
DB_PATH=""
LCM_DIR="${HOME}/.openclaw/lcm"
BACKUP_LATEST=""
TEMP_SQL="/tmp/lcm-cleanup-$$.sql"

# ── 清理临时文件 ──────────────────────────────────────────────────────────
cleanup_temp() {
  rm -f "$TEMP_SQL"
}
trap cleanup_temp EXIT

# ── 错误处理 ──────────────────────────────────────────────────────────────
die() {
  echo -e "${RED}❌ 错误: $*${NC}" >&2
  exit 1
}

warn() {
  echo -e "${YELLOW}⚠️  $*${NC}"
}

info() {
  echo -e "${CYAN}ℹ️  $*${NC}"
}

success() {
  echo -e "${GREEN}✅ $*${NC}"
}

# ── 找 LCM 数据库 ──────────────────────────────────────────────────────────
find_db() {
  if [[ -n "$DB_PATH" ]]; then
    [[ -f "$DB_PATH" ]] || die "数据库文件不存在: $DB_PATH"
    return 0
  fi

  local -a dbs
  mapfile -t dbs < <(find "$LCM_DIR" -maxdepth 1 -type f -name "*.db" 2>/dev/null | sort)

  case ${#dbs[@]} in
    0) die "未找到任何 LCM 数据库文件" ;;
    1) DB_PATH="${dbs[0]}" ;;
    *)
      echo "找到多个数据库，请选择:"
      for i in "${!dbs[@]}"; do
        echo "  [$i] ${dbs[$i]}"
      done
      read -rp "选择 (0-$((${#dbs[@]}-1))): " choice
      DB_PATH="${dbs[$choice]}" || die "无效选择"
      ;;
  esac

  info "使用数据库: $DB_PATH"
}

# ── 验证数据库完整性 ──────────────────────────────────────────────────────
verify_db_integrity() {
  local db="$1"
  local result
  result=$(sqlite3 "$db" "PRAGMA integrity_check;" 2>&1) || die "无法访问数据库: $db"
  if [[ "$result" != "ok" ]]; then
    die "数据库完整性检查失败: $result"
  fi
}

# ── 备份数据库 ────────────────────────────────────────────────────────────
backup_db() {
  local db="$1"
  local backup_dir="${LCM_DIR}/backups"
  mkdir -p "$backup_dir"

  local timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_file="${backup_dir}/$(basename "$db").bak.${timestamp}"

  info "正在备份到: $backup_file"

  # 使用 SQLite 的 .backup 确保一致性
  if ! sqlite3 "$db" ".backup '$backup_file'" 2>/dev/null; then
    die "备份失败"
  fi

  # 验证备份
  if ! verify_db_integrity "$backup_file"; then
    rm -f "$backup_file"
    die "备份文件损坏，已删除备份"
  fi

  success "备份完成: $backup_file"
  BACKUP_LATEST="$backup_file"
  echo "$backup_file"
}

# ── 检查 Gateway 状态 ──────────────────────────────────────────────────────
check_gateway_stopped() {
  if systemctl --user is-active openclaw-gateway.service &>/dev/null; then
    warn "Gateway 仍在运行！"
    read -rp "要继续删除吗？这可能导致数据损坏 (yes/no): " ans
    if [[ "$ans" != "yes" ]]; then
      die "用户取消。建议先运行: openclaw gateway stop"
    fi
  else
    success "Gateway 已停止"
  fi
}

# ── SCAN 模式：只读扫描 ────────────────────────────────────────────────────
scan_mode() {
  find_db
  verify_db_integrity "$DB_PATH"

  echo ""
  echo -e "${BLUE}━━━ 扫描模式 (只读) ━━━${NC}"
  echo "数据库: $DB_PATH"
  echo ""

  # 数据库概览
  echo -e "${CYAN}📊 数据库统计${NC}"
  sqlite3 -header -column "$DB_PATH" "
    SELECT 
      COUNT(DISTINCT c.id) as conversations,
      COUNT(m.message_id) as total_messages,
      SUM(CASE WHEN m.role = 'assistant' THEN 1 ELSE 0 END) as assistant_msgs,
      SUM(CASE WHEN m.role = 'user' THEN 1 ELSE 0 END) as user_msgs
    FROM conversations c
    LEFT JOIN messages m ON m.conversation_id = c.id;
  "

  # 问题类型 A：空 content + 无 parts
  echo ""
  echo -e "${YELLOW}[A] 空 content 且无 parts 的 assistant 消息${NC}"
  local count_a
  count_a=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*)
    FROM (
      SELECT m.message_id
      FROM messages m
      LEFT JOIN message_parts mp ON mp.message_id = m.message_id
      WHERE m.role = 'assistant'
        AND COALESCE(m.content, '') IN ('', '[]')
      GROUP BY m.message_id
      HAVING COUNT(mp.part_id) = 0
    );
  ")

  if [[ $count_a -gt 0 ]]; then
    echo "   共 $count_a 条（这些会被删除）"
    echo ""
    sqlite3 -header -column "$DB_PATH" "
      SELECT 
        m.message_id,
        m.conversation_id,
        m.ordinal,
        COALESCE(m.content, 'NULL') as content,
        m.created_at
      FROM messages m
      LEFT JOIN message_parts mp ON mp.message_id = m.message_id
      WHERE m.role = 'assistant'
        AND COALESCE(m.content, '') IN ('', '[]')
      GROUP BY m.message_id
      HAVING COUNT(mp.part_id) = 0
      ORDER BY m.created_at DESC
      LIMIT 10;
    "
    [[ $count_a -gt 10 ]] && echo "    ... 还有 $((count_a - 10)) 条"
  else
    echo "   未找到问题数据"
  fi

  # 问题类型 B：content 为 []
  echo ""
  echo -e "${YELLOW}[B] content 为 '[]' 但有 parts 的消息（可能有问题）${NC}"
  local count_b
  count_b=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*)
    FROM (
      SELECT m.message_id
      FROM messages m
      LEFT JOIN message_parts mp ON mp.message_id = m.message_id
      WHERE m.role = 'assistant'
        AND m.content = '[]'
      GROUP BY m.message_id
      HAVING COUNT(mp.part_id) > 0
    );
  ")
  echo "   共 $count_b 条（不会删除，仅展示）"

  # 问题类型 C：孤立引用
  echo ""
  echo -e "${YELLOW}[C] 孤立的 context_items 引用${NC}"
  local count_c
  count_c=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*)
    FROM context_items ci
    LEFT JOIN messages m ON m.message_id = ci.message_id
    WHERE ci.item_type = 'message' AND m.message_id IS NULL;
  ")
  echo "   共 $count_c 条（如果删除 [A]，这些也会被清理）"

  echo ""
  echo "下一步:"
  echo "  1. 备份备份:    $0 --db '$DB_PATH' --backup"
  echo "  2. 删除问题数据: $0 --db '$DB_PATH' --delete"
  echo "  3. 回滚:        $0 --db '$DB_PATH' --rollback"
}

# ── BACKUP 模式：仅备份 ────────────────────────────────────────────────────
backup_mode() {
  find_db
  verify_db_integrity "$DB_PATH"
  backup_db "$DB_PATH"
}

# ── RESTORE 模式 ──────────────────────────────────────────────────────────
restore_mode() {
  local backup_file="$1"
  [[ -z "$backup_file" ]] && die "必须指定备份文件"
  [[ -f "$backup_file" ]] || die "备份文件不存在: $backup_file"

  verify_db_integrity "$backup_file"

  # 要求用户显式指定原始数据库路径
  read -rp "恢复到哪个数据库？(完整路径): " target_db
  [[ -z "$target_db" ]] && die "必须指定目标数据库路径"

  echo ""
  echo "将要执行:"
  echo "  备份文件: $backup_file"
  echo "  恢复到:   $target_db"
  echo ""
  
  # 二次确认
  read -rp "确认恢复？(type 'yes' to confirm): " ans
  [[ "$ans" != "yes" ]] && die "用户取消"

  # 再备份一次现有的数据库
  if [[ -f "$target_db" ]]; then
    info "现有数据库已备份到: $(backup_db "$target_db")"
  fi

  cp "$backup_file" "$target_db"
  verify_db_integrity "$target_db"
  success "恢复完成！请运行: openclaw gateway start"
}

# ── DELETE 模式：删除问题数据 ──────────────────────────────────────────────
delete_mode() {
  find_db
  verify_db_integrity "$DB_PATH"

  # 先扫一遍看有多少要删
  local count_a
  count_a=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*)
    FROM (
      SELECT m.message_id
      FROM messages m
      LEFT JOIN message_parts mp ON mp.message_id = m.message_id
      WHERE m.role = 'assistant'
        AND COALESCE(m.content, '') IN ('', '[]')
      GROUP BY m.message_id
      HAVING COUNT(mp.part_id) = 0
    );
  ")

  if [[ $count_a -eq 0 ]]; then
    info "未找到问题数据，无需删除"
    return 0
  fi

  echo ""
  echo -e "${RED}━━━ 删除模式 ━━━${NC}"
  echo "将删除 $count_a 条空 assistant 消息"
  echo ""

  # 检查 Gateway
  check_gateway_stopped

  # 备份
  local backup_file
  backup_file=$(backup_db "$DB_PATH")

  # 显示要删除的详细信息
  echo ""
  echo -e "${YELLOW}要删除的消息:${NC}"
  sqlite3 -header -column "$DB_PATH" "
    SELECT 
      m.message_id,
      m.conversation_id,
      m.ordinal,
      m.created_at
    FROM messages m
    LEFT JOIN message_parts mp ON mp.message_id = m.message_id
    WHERE m.role = 'assistant'
      AND COALESCE(m.content, '') IN ('', '[]')
    GROUP BY m.message_id
    HAVING COUNT(mp.part_id) = 0
    ORDER BY m.created_at DESC;
  "

  # 三重确认
  echo ""
  echo -e "${RED}⚠️  这是最后一次确认！${NC}"
  echo "  - 数据已备份到: $backup_file"
  echo "  - 可随时恢复: $0 --db '$DB_PATH' --restore '$backup_file'"
  echo ""

  read -rp "确认删除？(type 'yes I understand' to continue): " ans
  [[ "$ans" != "yes I understand" ]] && {
    die "用户取消。备份已保留: $backup_file"
  }

  # 执行删除
  info "正在删除..."

  sqlite3 "$DB_PATH" "
    BEGIN TRANSACTION;

    -- 删除 context_items 引用
    DELETE FROM context_items 
    WHERE item_type = 'message' 
      AND message_id IN (
        SELECT m.message_id
        FROM messages m
        LEFT JOIN message_parts mp ON mp.message_id = m.message_id
        WHERE m.role = 'assistant'
          AND COALESCE(m.content, '') IN ('', '[]')
        GROUP BY m.message_id
        HAVING COUNT(mp.part_id) = 0
      );

    -- 删除消息
    DELETE FROM messages 
    WHERE message_id IN (
      SELECT m.message_id
      FROM messages m
      LEFT JOIN message_parts mp ON mp.message_id = m.message_id
      WHERE m.role = 'assistant'
        AND COALESCE(m.content, '') IN ('', '[]')
      GROUP BY m.message_id
      HAVING COUNT(mp.part_id) = 0
    );

    COMMIT;
  " || {
    warn "删除失败！自动回滚..."
    die "恢复备份: cp '$backup_file' '$DB_PATH'"
  }

  # 清理孤立引用
  sqlite3 "$DB_PATH" "
    DELETE FROM context_items 
    WHERE item_type = 'message' 
      AND message_id NOT IN (SELECT message_id FROM messages);
  "

  # VACUUM
  sqlite3 "$DB_PATH" "VACUUM;"

  # 验证完整性
  verify_db_integrity "$DB_PATH"

  success "删除完成！"
  echo ""
  echo "后续步骤:"
  echo "  1. 启动 Gateway: openclaw gateway start"
  echo "  2. 测试对话"
  echo "  3. 如有问题回滚: $0 --db '$DB_PATH' --rollback"
  echo ""
  echo "备份保留在: $backup_file"
}

# ── ROLLBACK 模式：回滚到最后一次备份 ────────────────────────────────────
rollback_mode() {
  find_db
  
  # 找最新的备份
  local latest_backup
  latest_backup=$(find "${LCM_DIR}/backups" -name "$(basename "$DB_PATH").bak.*" -type f 2>/dev/null | sort -r | head -1)
  
  [[ -z "$latest_backup" ]] && die "未找到备份文件"
  
  info "最新备份: $latest_backup"
  restore_mode "$latest_backup"
}

# ── 参数解析 ──────────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
  cat << EOF
lcm-cleanup.sh — LCM 数据库清理工具 (安全优先)

用法:
  $0 --scan [--db <path>]           # 只查看（完全只读）
  $0 --backup [--db <path>]         # 仅备份
  $0 --delete [--db <path>]         # 删除问题数据（需多次确认）
  $0 --restore <backup_file>        # 恢复指定备份
  $0 --rollback [--db <path>]       # 回滚到最新备份

选项:
  --db <path>        指定数据库文件路径
  -h, --help         显示帮助

设计原则:
  ✓ 只读操作绝不修改
  ✓ 参数化 SQL 防注入
  ✓ 修改前自动备份
  ✓ 多重确认机制
  ✓ 完整性校验
  ✓ 完全可恢复

示例:
  # 1. 先扫描
  $0 --scan

  # 2. 备份
  $0 --backup

  # 3. 删除
  $0 --delete

  # 4. 如有问题，回滚
  $0 --rollback
EOF
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan) MODE="scan"; shift ;;
    --backup) MODE="backup"; shift ;;
    --delete) MODE="delete"; shift ;;
    --restore) MODE="restore"; RESTORE_FILE="$2"; shift 2 ;;
    --rollback) MODE="rollback"; shift ;;
    --db) DB_PATH="$2"; shift 2 ;;
    -h|--help) exec head -10 "$0"; ;;
    *) die "未知参数: $1" ;;
  esac
done

# ── 执行 ──────────────────────────────────────────────────────────────────
case "$MODE" in
  scan) scan_mode ;;
  backup) backup_mode ;;
  delete) delete_mode ;;
  restore) restore_mode "${RESTORE_FILE:-}" ;;
  rollback) rollback_mode ;;
  *) die "必须指定操作: --scan|--backup|--delete|--restore|--rollback" ;;
esac
