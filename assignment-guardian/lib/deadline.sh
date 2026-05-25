#!/bin/bash
# ============================================================
# deadline.sh 鈥?妯″潡1: 鎴鏃堕棿绠″
# 鍔熻兘:
#   - 鎵弿 courses.conf 涓墍鏈夎绋嬬殑DDL
#   - 鎸夌揣鎬ョ▼搴﹀垎绫伙紙宸茶繃鏈?/ 浠婂ぉ / 3澶╁唴 / 7澶╁唴 / 杩滄湡锛?
#   - 缁堢褰╄壊杈撳嚭
#   - 鐢熸垚鎻愰啋鏃ュ織
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# 鎵弿骞跺睍绀烘墍鏈変綔涓氭埅姝㈢姸鎬?
deadline_check() {
    echo ""
    bold "========== 浣滀笟鎴鏃堕棿鎬昏 =========="
    echo ""

    local now_epoch
    now_epoch=$(date +%s)

    local expired="" today="" soon="" week="" later=""

    while IFS= read -r course; do
        local ddl
        ddl=$(config_get "$course" "ddl")
        [ -z "$ddl" ] && continue

        local remaining
        remaining=$(ddl_remaining_seconds "$ddl" 2>/dev/null || echo "unknown")
        [ "$remaining" = "unknown" ] && continue

        local submit
        submit=$(config_get "$course" "submit")

        local line
        line=$(printf "  [%-8s] DDL: %s | 鎻愪氦: %-5s | " "$course" "$ddl" "$submit")

        if [ "$remaining" -lt 0 ]; then
            local abs=$(( -remaining ))
            line+="$(red "宸茶繃鏈?$(human_readable_time $abs)")"
            expired+="$line"$'\n'
        elif [ "$remaining" -lt 86400 ]; then
            line+="$(red "浠婂ぉ鎴!")"
            today+="$line"$'\n'
        elif [ "$remaining" -lt 259200 ]; then
            line+="$(yellow "鍓╀綑 $(human_readable_time $remaining)")"
            soon+="$line"$'\n'
        elif [ "$remaining" -lt 604800 ]; then
            line+="$(blue "鍓╀綑 $(human_readable_time $remaining)")"
            week+="$line"$'\n'
        else
            line+="$(green "鍓╀綑 $(human_readable_time $remaining)")"
            later+="$line"$'\n'
        fi

        log_info "deadline check: $course  DDL=$ddl  remaining=$remaining seconds"
    done < <(config_list_courses)

    # 鎸夌揣鎬ュ害杈撳嚭锛堢揣鎬ヤ紭鍏堬紝鍏朵綑绱ч殢锛?
    local has_urgent=false
    if [ -n "$expired$today$soon" ]; then
        has_urgent=true
        [ -n "$expired" ] && echo "$expired"
        [ -n "$today" ]   && echo "$today"
        [ -n "$soon" ]    && echo "$soon"
    fi
    [ -n "$week" ]  && echo "$week"
    [ -n "$later" ] && echo "$later"

    if [ "$has_urgent" = true ]; then
        red "  鈿?鏈夎繃鏈熸垨鍗冲皢鍒版湡浣滀笟锛岃鍙婃椂澶勭悊!"
    fi

    echo ""
    green "鍏?$(config_list_courses | wc -l) 闂ㄨ绋?
    echo ""
}
