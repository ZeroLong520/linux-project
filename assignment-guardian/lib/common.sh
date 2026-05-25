#!/bin/bash
# ============================================================
# common.sh 鈥?鍏叡鍩虹璁炬柦
# 鎵€鏈夋ā鍧楅€氳繃 source 鍔犺浇姝ゆ枃浠惰幏寰楀叡浜兘鍔?
# ============================================================

set -euo pipefail

# -------------------- 璺緞甯搁噺 --------------------
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$_LIB_DIR")"
CONFIG_FILE="$PROJECT_ROOT/config/courses.conf"
LOG_FILE="$PROJECT_ROOT/logs/guardian.log"
LOG_DIR="$PROJECT_ROOT/logs"

# 纭繚鏃ュ織鐩綍瀛樺湪
mkdir -p "$LOG_DIR"

# -------------------- 缁堢褰╄壊杈撳嚭 --------------------
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

# -------------------- 鏃ュ織鍑芥暟 --------------------
_log() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level  $*" >> "$LOG_FILE"
}

log_info()  { _log "INFO" "$@"; }
log_warn()  { _log "WARN" "$@"; }
log_error() { _log "ERROR" "$@"; }

# -------------------- 閰嶇疆瑙ｆ瀽 --------------------
# 鐢ㄦ硶: config_get <璇剧▼鍚? <瀛楁鍚?
# 绀轰緥: config_get linux ddl   鈫?  2026-06-20 23:59
config_get() {
    local course="$1"
    local field="$2"

    # 鐢?awk 瀹氫綅 [course] 娈佃惤锛屾彁鍙栧瓧娈靛€?
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

# 鍒楀嚭鎵€鏈夎绋嬫爣璇?
config_list_courses() {
    awk '/^\[.*\]/ { gsub(/[\[\]]/, ""); print }' "$CONFIG_FILE"
}

# -------------------- 閫氱敤宸ュ叿鍑芥暟 --------------------

# 妫€鏌ュ懡浠ゆ槸鍚﹀瓨鍦?
command_exists() {
    command -v "$1" &>/dev/null
}

# 璁＄畻鏂囦欢MD5
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

# 灏嗙鏁拌浆涓轰汉绫诲彲璇?
human_readable_time() {
    local seconds="$1"
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))

    local result=""
    [ $days -gt 0 ]    && result="${days}澶?
    [ $hours -gt 0 ]   && result="${result}${hours}灏忔椂"
    [ $minutes -gt 0 ] && result="${result}${minutes}鍒嗛挓"
    [ -z "$result" ]   && result="涓嶅埌1鍒嗛挓"
    echo "$result"
}

# 璁＄畻璺濈DDL杩樻湁澶氬皯绉?
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

# 妫€鏌ユ槸鍚﹀湪鏌愪釜鑼冨洿鍐?
in_range() {
    local val="$1"; local min="$2"; local max="$3"
    [ "$val" -ge "$min" ] && [ "$val" -le "$max" ]
}

# -------------------- 鑷 --------------------
# 纭繚閰嶇疆鏂囦欢瀛樺湪锛屽惁鍒欐姤閿?
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: 閰嶇疆鏂囦欢 $CONFIG_FILE 涓嶅瓨鍦? >&2
    exit 1
fi
