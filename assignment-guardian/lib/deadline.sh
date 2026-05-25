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

deadline_check() {
    echo ""
    bold "========== 作业截止时间总览 =========="
    echo ""

    local expired="" today="" soon="" week="" later=""
    local total=0

    while IFS= read -r course; do
        local ddl
        ddl=$(config_get "$course" "ddl")
        [ -z "$ddl" ] && continue

        local remaining
        remaining=$(ddl_remaining_seconds "$ddl" 2>/dev/null || echo "unknown")
        [ "$remaining" = "unknown" ] && continue

        local submit
        submit=$(config_get "$course" "submit")
        submit="${submit:-未知}"

        total=$((total + 1))

        local line
        line="  [$(printf '%-8s' "$course")] DDL: $(printf '%-16s' "$ddl") | 提交: $(printf '%-5s' "$submit") | "

        if [ "$remaining" -lt 0 ]; then
            line+="$(red "已过期 $(human_readable_time $((-remaining)))")"
            expired+="$line"$'\n'
        elif [ "$remaining" -lt 86400 ]; then
            line+="$(red "今天截止!")"
            today+="$line"$'\n'
        elif [ "$remaining" -lt 259200 ]; then
            line+="$(yellow "剩余 $(human_readable_time "$remaining")")"
            soon+="$line"$'\n'
        elif [ "$remaining" -lt 604800 ]; then
            line+="$(blue "剩余 $(human_readable_time "$remaining")")"
            week+="$line"$'\n'
        else
            line+="$(green "剩余 $(human_readable_time "$remaining")")"
            later+="$line"$'\n'
        fi

        log_info "deadline check: $course  DDL=$ddl  submit=$submit  remaining=${remaining}s"
    done < <(config_list_courses)

    if [ "$total" -eq 0 ]; then
        yellow "  暂无配置有效DDL的课程，请检查 config/courses.conf"
        echo ""
        return
    fi

    # 按紧急度输出（紧急优先）
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
    green "共 ${total} 门课程"
    echo ""
}

# ============================================================
# deadline_notify — 供 crontab 调用，有紧急项时发邮件
# ============================================================
deadline_notify() {
    local urgent="" total=0 urgent_count=0

    while IFS= read -r course; do
        local ddl
        ddl=$(config_get "$course" "ddl")
        [ -z "$ddl" ] && continue

        local remaining
        remaining=$(ddl_remaining_seconds "$ddl" 2>/dev/null || echo "unknown")
        [ "$remaining" = "unknown" ] && continue

        local submit
        submit=$(config_get "$course" "submit")
        submit="${submit:-未知}"

        total=$((total + 1))

        # 只收集紧急项：已过期 / 今天 / 3天内
        if [ "$remaining" -lt 0 ]; then
            urgent+="  [$course] DDL: $ddl | 提交: $submit | 已过期 $(human_readable_time $((-remaining)))"$'\n'
            ((urgent_count++)) || true
        elif [ "$remaining" -lt 86400 ]; then
            urgent+="  [$course] DDL: $ddl | 提交: $submit | 今天截止!"$'\n'
            ((urgent_count++)) || true
        elif [ "$remaining" -lt 259200 ]; then
            urgent+="  [$course] DDL: $ddl | 提交: $submit | 剩余 $(human_readable_time "$remaining")"$'\n'
            ((urgent_count++)) || true
        fi

    done < <(config_list_courses)

    # 无紧急项，只写日志
    if [ "$urgent_count" -eq 0 ]; then
        log_info "notify: 无紧急作业 (共${total}门)"
        return 0
    fi

    # 有紧急项，组装邮件并发送
    local email
    email=$(config_get "notify" "email")
    email="${email:-root@localhost}"

    local body
    body="[作业守护者] 截止时间提醒 — $(date '+%Y-%m-%d %H:%M')
==============================================
⚠ 以下作业需要关注：
${urgent}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
共 ${total} 门课程，其中 ${urgent_count} 门需要关注
请登录系统查看: ./guardian.sh check
"

    _send_email "$email" "[作业守护者] 截止时间提醒" "$body"
    log_info "notify: 已发送邮件到 $email (紧急${urgent_count}项)"
    echo "notify: 检测到 ${urgent_count} 项紧急作业, 已发送通知到 $email"
}

# ============================================================
# _send_email — 发送邮件（依次尝试 msmtp / mail / 存文件）
# ============================================================
_send_email() {
    local to="$1"
    local subject="$2"
    local body="$3"

    # 方式1: msmtp
    if command -v msmtp &>/dev/null; then
        {
            echo "Subject: $subject"
            echo "To: $to"
            echo ""
            echo "$body"
        } | msmtp "$to" 2>/dev/null && return 0
    fi

    # 方式2: mail (mailutils / mailx)
    if command -v mail &>/dev/null; then
        echo "$body" | mail -s "$subject" "$to" 2>/dev/null && return 0
    fi

    # 方式3: 存文件兜底
    local notify_file="$LOG_DIR/notify_$(date '+%Y%m%d_%H%M%S').txt"
    {
        echo "Subject: $subject"
        echo "To: $to"
        echo ""
        echo "$body"
    } > "$notify_file"
    log_info "notify: 无邮件工具，提醒已存至 $notify_file"
}
