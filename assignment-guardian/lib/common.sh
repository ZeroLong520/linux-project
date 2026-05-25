#!/bin/bash
# ============================================================
# common.sh — 公共基础设施
# 所有模块通过 source 加载此文件获得共享能力
# ============================================================

set -euo pipefail

# -------------------- 路径常量 --------------------
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$_LIB_DIR")"
CONFIG_FILE="$PROJECT_ROOT/config/courses.conf"
LOG_FILE="$PROJECT_ROOT/logs/guardian.log"
LOG_DIR="$PROJECT_ROOT/logs"

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# -------------------- 终端彩色输出 --------------------
_color() {
    local code="$1"; shift
    if [ -t 1 ]; then
        echo -e "\033[${code}m$*\033[0m"
    else
        echo "$*"
    fi
}

red()    { _color 31 "$@"; }
green()  { _color 32 "$@"; }
yellow() { _color 33 "$@"; }
blue()   { _color 34 "$@"; }
bold()   { _color 1 "$@"; }

# -------------------- 日志函数 --------------------
_log() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level  $*" >> "$LOG_FILE"
}

log_info()  { _log "INFO" "$@"; }
log_warn()  { _log "WARN" "$@"; }
log_error() { _log "ERROR" "$@"; }

# -------------------- 配置解析 --------------------
# 用法: config_get <课程名> <字段名>
# 示例: config_get linux ddl   →   2026-06-20 23:59
config_get() {
    local course="$1"
    local field="$2"

    # 用 awk 定位 [course] 段落，提取字段值
    awk -v course="$course" -v field="$field" '
        BEGIN { in_section = 0 }
        $0 ~ "^\\[" course "\\]" { in_section = 1; next }
        $0 ~ "^\\[" { in_section = 0 }
        in_section && $1 == field {
            sub(/^[^=]*= /, "")
            print
            exit
        }
    ' "$CONFIG_FILE"
}

# 列出所有课程标识
config_list_courses() {
    awk '/^\[.*\]/ { gsub(/[\[\]]/, ""); print }' "$CONFIG_FILE"
}

# -------------------- 通用工具函数 --------------------

# 检查命令是否存在
command_exists() {
    command -v "$1" &>/dev/null
}

# 计算文件MD5
file_md5() {
    if command_exists md5sum; then
        md5sum "$1" | awk '{print $1}'
    elif command_exists md5; then
        md5 -q "$1"
    else
        echo "ERROR: no md5 tool found"
        return 1
    fi
}

# 将秒数转为人类可读
human_readable_time() {
    local seconds="$1"
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))

    local result=""
    [ $days -gt 0 ]    && result="${days}天"
    [ $hours -gt 0 ]   && result="${result}${hours}小时"
    [ $minutes -gt 0 ] && result="${result}${minutes}分钟"
    [ -z "$result" ]   && result="不到1分钟"
    echo "$result"
}

# 计算距离DDL还有多少秒
ddl_remaining_seconds() {
    local ddl_str="$1"
    local ddl_epoch
    ddl_epoch=$(date -d "$ddl_str" +%s 2>/dev/null || echo 0)

    if [ "$ddl_epoch" = "0" ]; then
        echo 0
        return 1
    fi

    local now_epoch
    now_epoch=$(date +%s)
    echo $((ddl_epoch - now_epoch))
}

# 检查是否在某个范围内
in_range() {
    local val="$1"; local min="$2"; local max="$3"
    [ "$val" -ge "$min" ] && [ "$val" -le "$max" ]
}

# 查看指定课程的全部配置
config_show() {
    local course="$1"
    echo ""
    bold "========== 课程配置: $course =========="
    echo ""
    local fields=(ddl submit target required_files naming notes grading format forbidden)
    for field in "${fields[@]}"; do
        local value
        value=$(config_get "$course" "$field" 2>/dev/null || true)
        if [ -n "$value" ]; then
            printf "  %-16s %s\n" "$field:" "$value"
        fi
    done
    echo ""
}

# -------------------- 自检 --------------------
# 确保配置文件存在，否则报错
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: 配置文件 $CONFIG_FILE 不存在" >&2
    exit 1
fi
