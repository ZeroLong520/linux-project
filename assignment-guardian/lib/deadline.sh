#!/bin/bash
# ============================================================
# deadline.sh — 模块1: 截止时间管家 + 邮件通知 + 定时任务
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ==================== QQ邮箱配置 ====================
MAIL_FROM="2722946953@qq.com"
MAIL_AUTH="uygnnsosvqeqdefi"
MAIL_TO="2722946953@qq.com"
SMTP_SERVER="smtp.qq.com"
SMTP_PORT="465"
SMTP_PROTO="smtps"

# ==================== 1. 传统截止时间扫描 ====================

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

# ==================== 2. 截止时间颜色扫描（按DDL升序）====================

deadline_scan() {
    echo ""
    bold "========== 截止时间总览（按截止时间排序，最先截止在前）=========="
    echo ""

    local now_epoch tmpfile
    now_epoch=$(date +%s)
    tmpfile=$(mktemp /tmp/deadline_XXXXXX)

    while IFS= read -r course; do
        [ -z "$course" ] && continue
        local ddl
        ddl=$(config_get "$course" "ddl" 2>/dev/null || true)
        [ -z "$ddl" ] && continue
        local remaining
        remaining=$(ddl_remaining_seconds "$ddl" 2>/dev/null || echo "unknown")
        [ "$remaining" = "unknown" ] && continue
        echo "${remaining}|${course}|${ddl}|$(config_get "$course" "submit" 2>/dev/null || echo 'N/A')" >> "$tmpfile"
        log_info "deadline scan: $course DDL=$ddl remaining=$remaining"
    done < <(config_list_courses)

    sort -t'|' -k1 -n "$tmpfile" | while IFS='|' read -r remaining course ddl submit; do
        local readable
        if [ "$remaining" -lt 0 ]; then
            readable="已过期 $(human_readable_time $(( -remaining )))"
        else
            readable="$(human_readable_time $remaining)"
        fi

        local line
        line=$(printf "  %-20s  DDL: %-16s  提交: %-5s  剩余: %s" "$course" "$ddl" "$submit" "$readable")

        if [ "$remaining" -lt 0 ]; then
            printf '\033[41;37m%s\033[0m\n' "$line"
        elif [ "$remaining" -lt 86400 ]; then
            red "$line 【今天截止！】"
        elif [ "$remaining" -lt 259200 ]; then
            yellow "$line"
        elif [ "$remaining" -lt 604800 ]; then
            blue "$line"
        else
            green "$line"
        fi
    done

    rm -f "$tmpfile"

    echo ""
    echo "-----------------------------------"
    printf '  '
    printf '\033[41;37m 已过期 \033[0m  '
    red "今天截止  "
    yellow "3天内  "
    blue "7天内  "
    green "远期  "
    echo ""
    echo ""
    echo "  共 $(config_list_courses | wc -l) 门课程"
    echo ""
}

# ==================== 3. 邮件发送（QQ邮箱 SMTP via curl）====================

deadline_send_mail() {
    local subject="$1"
    local body="$2"
    local recipient="${3:-$MAIL_TO}"

    local tmpfile
    tmpfile=$(mktemp /tmp/mail_XXXXXX.eml)

    cat > "$tmpfile" << MAILEOF
From: Assignment Guardian <${MAIL_FROM}>
To: <${recipient}>
Subject: ${subject}
Content-Type: text/plain; charset=utf-8

${body}
MAILEOF

    curl --silent --show-error \
        --url "${SMTP_PROTO}://${SMTP_SERVER}:${SMTP_PORT}" \
        --login-options AUTH=LOGIN \
        --user "${MAIL_FROM}:${MAIL_AUTH}" \
        --mail-from "${MAIL_FROM}" \
        --mail-rcpt "${recipient}" \
        --upload-file "$tmpfile" \
        --verbose 2>>"$LOG_FILE"

    local ret=$?
    rm -f "$tmpfile"

    if [ $ret -eq 0 ]; then
        log_info "邮件发送成功: $subject → $recipient"
        return 0
    else
        log_error "邮件发送失败: $subject → $recipient (exit=$ret)"
        return 1
    fi
}

# ==================== 4. 当天任务邮件提醒 ====================

deadline_notify_today() {
    echo ""
    bold "========== 今日截止任务检查 =========="
    echo ""

    local now_epoch
    now_epoch=$(date +%s)

    local today_courses=""
    local mail_body=""
    local urgent_count=0

    while IFS= read -r course; do
        [ -z "$course" ] && continue
        local ddl submit target notes grading
        ddl=$(config_get "$course" "ddl" 2>/dev/null || true)
        submit=$(config_get "$course" "submit" 2>/dev/null || true)
        target=$(config_get "$course" "target" 2>/dev/null || true)
        notes=$(config_get "$course" "notes" 2>/dev/null || true)
        grading=$(config_get "$course" "grading" 2>/dev/null || true)
        [ -z "$ddl" ] && continue

        local remaining
        remaining=$(ddl_remaining_seconds "$ddl" 2>/dev/null || echo "0")

        if [ "$remaining" -ge 0 ] && [ "$remaining" -lt 86400 ]; then
            local ddl_date
            ddl_date=$(date -d "$ddl" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$ddl")
            red "  [今日截止] $course — DDL: $ddl_date"
            today_courses="$today_courses $course"
            urgent_count=$((urgent_count + 1))
            mail_body+="
----------------------------------------
课程:       $course
截止时间:   $ddl
提交方式:   ${submit:-N/A}
提交目标:   ${target:-N/A}
说明:       ${notes:-无}
评分标准:   ${grading:-无}
----------------------------------------
"
        fi
    done < <(config_list_courses)

    local expired_courses=""
    while IFS= read -r course; do
        [ -z "$course" ] && continue
        local ddl
        ddl=$(config_get "$course" "ddl" 2>/dev/null || true)
        [ -z "$ddl" ] && continue
        local remaining
        remaining=$(ddl_remaining_seconds "$ddl" 2>/dev/null || echo "0")
        if [ "$remaining" -lt 0 ]; then
            local ddl_date
            ddl_date=$(date -d "$ddl" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$ddl")
            red "  [已过期!] $course — DDL: $ddl_date"
            expired_courses="$expired_courses $course"
            urgent_count=$((urgent_count + 1))
        fi
    done < <(config_list_courses)

    if [ -n "$expired_courses" ]; then
        mail_body+="
========== 以下课程已逾期 ==========
$expired_courses
"
    fi

    if [ -z "$today_courses" ] && [ -z "$expired_courses" ]; then
        green "  今天没有截止的作业"
        echo ""
        return 0
    fi

    echo ""

    local today_str
    today_str=$(date '+%Y年%m月%d日')
    local subject="【作业提醒】${today_str} 有 ${urgent_count} 门课程需要关注"

    local full_body
    full_body=$(cat << BODYEOF
同学你好，

以下是 ${today_str} 需要关注的作业情况：

${mail_body}

请及时完成并提交，避免逾期影响成绩！

---
Assignment Guardian 作业守护者
自动发送时间: $(date '+%Y-%m-%d %H:%M:%S')
BODYEOF
)

    echo "  正在发送邮件提醒到 ${MAIL_TO} ..."
    if deadline_send_mail "$subject" "$full_body"; then
        green "  ✓ 邮件提醒已发送"
        log_info "今日截止提醒邮件已发送:${today_courses}${expired_courses}"
    else
        red "  ✗ 邮件发送失败，请检查网络和SMTP配置"
        log_error "今日截止提醒邮件发送失败"
    fi

    echo ""
}

# ==================== 5. 设置crontab定时任务 ====================

deadline_schedule_setup() {
    echo ""
    bold "========== 设置定时扫描任务 =========="
    echo ""

    local added=0
    crontab -l > /tmp/crontab_backup.txt 2>/dev/null || true

    # 每天早上8:00 发送今日截止邮件提醒
    local cron_line="0 8 * * * cd $PROJECT_ROOT && source lib/deadline.sh && deadline_notify_today >> $PROJECT_ROOT/logs/notify.log 2>&1"
    if ! crontab -l 2>/dev/null | grep -qF "deadline_notify_today"; then
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
        green "  ✓ 已添加: 每天早上8:00 发送今日截止邮件提醒"
        added=1
    else
        yellow "  - 邮件提醒任务已存在，跳过"
    fi

    # 每天早上8:00 扫描截止时间
    cron_line="0 8 * * * cd $PROJECT_ROOT && source lib/deadline.sh && deadline_scan >> $PROJECT_ROOT/logs/deadline_scan.log 2>&1"
    if ! crontab -l 2>/dev/null | grep -qF "deadline_scan"; then
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
        green "  ✓ 已添加: 每天早上8:00 扫描截止时间并记录日志"
        added=1
    else
        yellow "  - 截止时间扫描任务已存在，跳过"
    fi

    # 每6小时补充扫描
    cron_line="0 10,16,22 * * * cd $PROJECT_ROOT && source lib/deadline.sh && deadline_scan >> $PROJECT_ROOT/logs/deadline_scan.log 2>&1"
    if ! crontab -l 2>/dev/null | grep -qF "10,16,22"; then
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
        green "  ✓ 已添加: 每天10:00/16:00/22:00 定时扫描"
        added=1
    else
        yellow "  - 定时扫描任务已存在，跳过"
    fi

    # 每小时检查今天截止任务
    cron_line="0 * * * * cd $PROJECT_ROOT && source lib/deadline.sh && deadline_notify_today >> $PROJECT_ROOT/logs/notify.log 2>&1"
    if ! crontab -l 2>/dev/null | grep -qF "每时检查|deadline_notify_today.*notify"; then
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
        green "  ✓ 已添加: 每小时检查今天截止任务并发送提醒"
        added=1
    else
        yellow "  - 每小时检查任务已存在，跳过"
    fi

    echo ""
    echo "  当前crontab任务列表:"
    echo "  ----------------------------------------"
    crontab -l 2>/dev/null | while IFS= read -r line; do
        [ -n "$line" ] && echo "  $line"
    done
    echo "  ----------------------------------------"
    echo ""

    if [ "$added" -eq 1 ]; then
        green "  定时任务设置完成！"
        log_info "crontab scheduled tasks configured"
    else
        yellow "  所有定时任务已存在，无需重复添加"
    fi
    echo ""
}

# ==================== 6. 查看定时任务状态 ====================

deadline_schedule_status() {
    echo ""
    bold "========== 定时任务状态 =========="
    echo ""
    if crontab -l 2>/dev/null | grep -q '.'; then
        echo "  当前定时任务:"
        echo ""
        crontab -l 2>/dev/null | while IFS= read -r line; do
            [ -z "$line" ] && continue
            echo "    $line"
        done
        echo ""
        green "  ✓ 定时任务运行中"
    else
        yellow "  没有定时任务，请运行: ./guardian.sh schedule"
    fi
    echo ""
}

# ==================== 7. 综合面板 ====================

deadline_status_all() {
    echo ""
    bold "============================================"
    bold "    Assignment Guardian — 综合检查面板"
    bold "============================================"
    echo ""
    echo "  检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  配置文件: $CONFIG_FILE"
    echo "  日志文件: $LOG_FILE"
    echo "  邮件通知: $MAIL_TO"
    echo ""

    deadline_scan
    deadline_notify_today
    checker_verify_all "."
    deadline_schedule_status
}
