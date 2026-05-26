#!/bin/bash
# ============================================================
# checker.sh — 模块2: 作业规范自检器 + 截止时间提醒 + 邮件通知
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ==================== QQ邮箱配置 ====================
MAIL_FROM="2722946953@qq.com"
MAIL_AUTH="uygnnsosvqeqdefi"
MAIL_TO="2722946953@qq.com"
SMTP_SERVER="smtp.qq.com"
SMTP_PORT="465"
SMTP_PROTO="smtps"

# ==================== 1. 作业规范自检（保持原有功能）====================

checker_verify() {
    local course="$1"
    local target_dir="${2:-.}"

    echo ""
    bold "========== 作业规范自检: $course =========="
    echo ""

    local pass=0
    local fail=0

    # --- 检查项1: 必交文件（支持带路径的通配符）---
    local required
    required=$(config_get "$course" "required_files")
    if [ -n "$required" ]; then
        IFS=',' read -ra FILES <<< "$required"
        for pattern in "${FILES[@]}"; do
            pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            local search_dir="$target_dir"
            local name_pattern="$pattern"
            if [[ "$pattern" == */* ]]; then
                search_dir="$target_dir/$(dirname "$pattern")"
                name_pattern="$(basename "$pattern")"
            fi
            local found
            if [ -d "$search_dir" ]; then
                found=$(find "$search_dir" -maxdepth 1 -name "$name_pattern" 2>/dev/null | head -1)
            else
                found=""
            fi
            if [ -n "$found" ]; then
                local rel_path=$(realpath --relative-to="$target_dir" "$found" 2>/dev/null || echo "$found")
                green "  [PASS] 必交文件: $pattern → $rel_path"
                ((pass++)) || true
            else
                red "  [FAIL] 必交文件: $pattern → 未找到"
                ((fail++)) || true
            fi
        done
    fi

    # --- 检查项2: Shell脚本执行权限 ---
    while IFS= read -r -d '' script; do
        local rel_path=$(realpath --relative-to="$target_dir" "$script" 2>/dev/null || echo "$script")
        if [ -x "$script" ]; then
            green "  [PASS] 可执行权限: $rel_path"
            ((pass++)) || true
        else
            red "  [FAIL] 缺少执行权限: $rel_path (建议: chmod +x)"
            ((fail++)) || true
        fi
    done < <(find "$target_dir" -name "*.sh" -print0 2>/dev/null)

    # --- 检查项3: Shell脚本语法 ---
    while IFS= read -r -d '' script; do
        local rel_path=$(realpath --relative-to="$target_dir" "$script" 2>/dev/null || echo "$script")
        local syntax_result
        syntax_result=$(bash -n "$script" 2>&1)
        if [ $? -eq 0 ]; then
            green "  [PASS] 语法检查: $rel_path"
            ((pass++)) || true
        else
            red "  [FAIL] 语法错误: $rel_path → $syntax_result"
            ((fail++)) || true
        fi
    done < <(find "$target_dir" -name "*.sh" -print0 2>/dev/null)

    # --- 检查项4: 文件以换行符结尾 ---
    while IFS= read -r -d '' f; do
        if [ -s "$f" ]; then
            local rel_path=$(realpath --relative-to="$target_dir" "$f" 2>/dev/null || echo "$f")
            local last_char
            last_char=$(tail -c 1 "$f" | od -An -tx1 | tr -d ' ')
            if [ "$last_char" = "0a" ]; then
                green "  [PASS] 换行结尾: $rel_path"
                ((pass++)) || true
            else
                yellow "  [WARN] 缺少末尾换行: $rel_path"
            fi
        fi
    done < <(find "$target_dir" \( -name "*.sh" -o -name "*.md" -o -name "*.txt" \) -print0 2>/dev/null)

    # --- 检查项5: 绝对路径检查 ---
    local has_abs_path=0
    while IFS= read -r -d '' f; do
        local rel_path=$(realpath --relative-to="$target_dir" "$f" 2>/dev/null || echo "$f")
        if grep -qE '^/\|/\./|\.\./' "$f" 2>/dev/null; then
            red "  [FAIL] 包含绝对路径: $rel_path"
            ((fail++)) || true
            has_abs_path=1
        fi
    done < <(find "$target_dir" \( -name "*.sh" -o -name "*.md" -o -name "Makefile" \) -print0 2>/dev/null)
    [ $has_abs_path -eq 0 ] && green "  [PASS] 无绝对路径引用" && ((pass++)) || true

    # --- 检查项6: 编码检查（兼容模式）---
    local encoding_support=1
    if ! file --help 2>&1 | grep -q "\-I"; then
        encoding_support=0
    fi
    if [ $encoding_support -eq 1 ]; then
        while IFS= read -r -d '' f; do
            if [ -s "$f" ]; then
                local rel_path=$(realpath --relative-to="$target_dir" "$f" 2>/dev/null || echo "$f")
                local encoding
                encoding=$(file -I "$f" | awk -F'=' '{print $NF}' | tr -d ' ')
                if echo "$encoding" | grep -qi "utf-8\|ascii"; then
                    green "  [PASS] 编码正确: $rel_path ($encoding)"
                    ((pass++)) || true
                else
                    yellow "  [WARN] 非UTF-8编码: $rel_path ($encoding)"
                fi
            fi
        done < <(find "$target_dir" \( -name "*.sh" -o -name "*.md" -o -name "*.txt" \) -print0 2>/dev/null)
    else
        green "  [SKIP] 编码检查: 当前系统不支持"
    fi

    # --- 汇总 ---
    echo ""
    echo "-----------------------------------"
    local total=$((pass + fail))
    green "  通过: $pass"
    [ "$fail" -gt 0 ] && red "  未通过: $fail"
    echo "  总计: $total"
    echo ""
    log_info "checker verify: $course  pass=$pass fail=$fail"
    return $fail
}

checker_verify_all() {
    local target_dir="${1:-.}"
    local total_fail=0
    while IFS= read -r course; do
        checker_verify "$course" "$target_dir"
        total_fail=$((total_fail + $?))
    done < <(config_list_courses)
    return $total_fail
}

# ==================== 2. 截止时间扫描（颜色区分紧迫程度）====================

checker_deadline_scan() {
    echo ""
    bold "========== 截止时间总览（按截止时间排序，最先截止在前）=========="
    echo ""

    local now_epoch tmpfile
    now_epoch=$(date +%s)
    tmpfile=$(mktemp /tmp/deadline_XXXXXX)

    # 收集所有课程及剩余秒数
    while IFS= read -r course; do
        [ -z "$course" ] && continue

        local ddl
        ddl=$(config_get "$course" "ddl" 2>/dev/null || true)
        [ -z "$ddl" ] && continue

        local remaining
        remaining=$(ddl_remaining_seconds "$ddl" 2>/dev/null || echo "unknown")
        [ "$remaining" = "unknown" ] && continue

        # 写入临时文件: 剩余秒数|课程名|ddl|submit
        echo "${remaining}|${course}|${ddl}|$(config_get "$course" "submit" 2>/dev/null || echo 'N/A')" >> "$tmpfile"

        log_info "deadline scan: $course DDL=$ddl remaining=$remaining"
    done < <(config_list_courses)

    # 按剩余秒数升序排序（负数=已过期，排最前）
    local has_expired=false
    sort -t'|' -k1 -n "$tmpfile" | while IFS='|' read -r remaining course ddl submit; do
        local readable
        if [ "$remaining" -lt 0 ]; then
            readable="已过期 $(human_readable_time $(( -remaining )))"
            has_expired=true
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

    # 图例
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

checker_send_mail() {
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

checker_notify_today() {
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

        # 今天截止：剩余时间 >=0 且 < 24小时
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

    # 检查已过期的课程（也应该提醒）
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

    # 发送邮件
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
    if checker_send_mail "$subject" "$full_body"; then
        green "  ✓ 邮件提醒已发送"
        log_info "今日截止提醒邮件已发送:${today_courses}${expired_courses}"
    else
        red "  ✗ 邮件发送失败，请检查网络和SMTP配置"
        log_error "今日截止提醒邮件发送失败"
    fi

    echo ""
}

# ==================== 5. 定时扫描守护进程 ====================

checker_daemon() {
    local interval="${1:-3600}"

    echo ""
    bold "========== Checker 守护进程启动 =========="
    echo "  扫描间隔: ${interval}秒 ($(awk "BEGIN {printf \"%.1f\", $interval/3600}")小时)"
    echo "  邮件通知: ${MAIL_TO}"
    echo "  按 Ctrl+C 停止"
    echo ""

    while true; do
        local now
        now=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$now] 定时扫描..."

        checker_deadline_scan

        # 早上8点发送今日提醒
        local hour
        hour=$(date +%H)
        if [ "$hour" = "08" ]; then
            checker_notify_today
        fi

        log_info "daemon scan completed, next in ${interval}s"
        sleep "$interval"
    done
}

# ==================== 6. 设置crontab定时任务 ====================

checker_schedule_setup() {
    echo ""
    bold "========== 设置定时扫描任务 =========="
    echo ""

    local guardian_path="$PROJECT_ROOT/guardian.sh"
    local added=0

    crontab -l > /tmp/crontab_backup.txt 2>/dev/null || true

    # 每天早上8:00 发送今日截止邮件提醒
    local cron_line="0 8 * * * cd $PROJECT_ROOT && source lib/checker.sh && checker_notify_today >> $PROJECT_ROOT/logs/notify.log 2>&1"
    if ! crontab -l 2>/dev/null | grep -qF "checker_notify_today"; then
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
        green "  ✓ 已添加: 每天早上8:00 发送今日截止邮件提醒"
        added=1
    else
        yellow "  - 邮件提醒任务已存在，跳过"
    fi

    # 每天早上8:00 扫描截止时间
    cron_line="0 8 * * * cd $PROJECT_ROOT && source lib/checker.sh && checker_deadline_scan >> $PROJECT_ROOT/logs/deadline_scan.log 2>&1"
    if ! crontab -l 2>/dev/null | grep -qF "checker_deadline_scan"; then
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
        green "  ✓ 已添加: 每天早上8:00 扫描截止时间并记录日志"
        added=1
    else
        yellow "  - 截止时间扫描任务已存在，跳过"
    fi

    # 每6小时补充扫描（10:00, 16:00, 22:00）
    cron_line="0 10,16,22 * * * cd $PROJECT_ROOT && source lib/checker.sh && checker_deadline_scan >> $PROJECT_ROOT/logs/deadline_scan.log 2>&1"
    if ! crontab -l 2>/dev/null | grep -qF "10,16,22"; then
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
        green "  ✓ 已添加: 每天10:00/16:00/22:00 定时扫描"
        added=1
    else
        yellow "  - 定时扫描任务已存在，跳过"
    fi

    # 每小时检查是否有今天截止的任务
    cron_line="0 * * * * cd $PROJECT_ROOT && source lib/checker.sh && checker_notify_today >> $PROJECT_ROOT/logs/notify.log 2>&1"
    if ! crontab -l 2>/dev/null | grep -qF "每时检查"; then
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

# ==================== 7. 查看定时任务状态 ====================

checker_schedule_status() {
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
        yellow "  没有定时任务，请运行:"
        echo "    source lib/checker.sh && checker_schedule_setup"
    fi
    echo ""
}

# ==================== 8. 综合面板 ====================

checker_status_all() {
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

    checker_deadline_scan
    checker_notify_today
    checker_verify_all "."
    checker_schedule_status
}

# 直接执行时显示帮助
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "Usage: source checker.sh 然后调用以下函数:"
    echo ""
    echo "  === 规范检查 ==="
    echo "  checker_verify <课程>          — 作业规范自检"
    echo "  checker_verify_all             — 全部课程规范自检"
    echo ""
    echo "  === 截止时间 ==="
    echo "  checker_deadline_scan          — 截止时间颜色扫描"
    echo "  checker_notify_today           — 今日截止邮件提醒"
    echo "  checker_send_mail <主题> <正文> — 发送自定义邮件"
    echo ""
    echo "  === 定时任务 ==="
    echo "  checker_schedule_setup         — 一键设置crontab定时任务"
    echo "  checker_schedule_status        — 查看定时任务状态"
    echo "  checker_daemon [间隔秒]        — 后台守护进程模式"
    echo ""
    echo "  === 综合 ==="
    echo "  checker_status_all             — 综合检查面板"
fi
