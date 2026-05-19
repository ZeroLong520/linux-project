#!/bin/bash
# ============================================================
# deadline.sh — 模块1: 截止时间管家
# 功能:
#   - 扫描 courses.conf 中所有课程的DDL
#   - 按紧急程度分类（已过期 / 今天 / 3天内 / 7天内 / 远期）
#   - 终端彩色输出
#   - 生成提醒日志
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# 扫描并展示所有作业截止状态
deadline_check() {
    echo ""
    bold "========== 作业截止时间总览 =========="
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
        line=$(printf "  [%-8s] DDL: %s | 提交: %-5s | " "$course" "$ddl" "$submit")

        if [ "$remaining" -lt 0 ]; then
            local abs=$(( -remaining ))
            line+="$(red "已过期 $(human_readable_time $abs)")"
            expired+="$line"$'\n'
        elif [ "$remaining" -lt 86400 ]; then
            line+="$(red "今天截止!")"
            today+="$line"$'\n'
        elif [ "$remaining" -lt 259200 ]; then
            line+="$(yellow "剩余 $(human_readable_time $remaining)")"
            soon+="$line"$'\n'
        elif [ "$remaining" -lt 604800 ]; then
            line+="$(blue "剩余 $(human_readable_time $remaining)")"
            week+="$line"$'\n'
        else
            line+="$(green "剩余 $(human_readable_time $remaining)")"
            later+="$line"$'\n'
        fi

        log_info "deadline check: $course  DDL=$ddl  remaining=$remaining seconds"
    done < <(config_list_courses)

    # 按紧急度输出（紧急优先，其余紧随）
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
        red "  ⚠ 有过期或即将到期作业，请及时处理!"
    fi

    echo ""
    green "共 $(config_list_courses | wc -l) 门课程"
    echo ""
}
