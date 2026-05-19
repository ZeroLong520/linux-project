#!/bin/bash
# ============================================================
# checker.sh — 模块2: 作业规范自检器
# 功能:
#   - 检查文件命名是否符合规范
#   - 检查必交文件是否齐全
#   - 检查Shell脚本是否有执行权限
#   - 检查Shell脚本语法 (bash -n)
#   - 检查文件是否以换行符结尾
#   - 输出检查报告（通过/未通过）
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# 对指定课程执行规范自检
checker_verify() {
    local course="$1"
    local target_dir="${2:-.}"

    echo ""
    bold "========== 作业规范自检: $course =========="
    echo ""

    local pass=0
    local fail=0

    # --- 检查项1: 必交文件 ---
    local required
    required=$(config_get "$course" "required_files")
    if [ -n "$required" ]; then
        IFS=',' read -ra FILES <<< "$required"
        for pattern in "${FILES[@]}"; do
            pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            local found
            found=$(find "$target_dir" -maxdepth 1 -name "$pattern" 2>/dev/null | head -1)
            if [ -n "$found" ]; then
                green "  [PASS] 必交文件: $pattern → $found"
                ((pass++)) || true
            else
                red "  [FAIL] 必交文件: $pattern → 未找到"
                ((fail++)) || true
            fi
        done
    fi

    # --- 检查项2: Shell脚本执行权限 ---
    while IFS= read -r -d '' script; do
        if [ -x "$script" ]; then
            green "  [PASS] 可执行权限: $script"
            ((pass++)) || true
        else
            red "  [FAIL] 缺少执行权限: $script (建议: chmod +x)"
            ((fail++)) || true
        fi
    done < <(find "$target_dir" -maxdepth 1 -name "*.sh" -print0 2>/dev/null)

    # --- 检查项3: Shell脚本语法 (bash -n) ---
    while IFS= read -r -d '' script; do
        local syntax_result
        syntax_result=$(bash -n "$script" 2>&1)
        if [ $? -eq 0 ]; then
            green "  [PASS] 语法检查: $script"
            ((pass++)) || true
        else
            red "  [FAIL] 语法错误: $script → $syntax_result"
            ((fail++)) || true
        fi
    done < <(find "$target_dir" -maxdepth 1 -name "*.sh" -print0 2>/dev/null)

    # --- 检查项4: 文件以换行符结尾 ---
    while IFS= read -r -d '' f; do
        if [ -s "$f" ]; then
            local last_char
            last_char=$(tail -c 1 "$f" | od -An -tx1 | tr -d ' ')
            if [ "$last_char" = "0a" ]; then
                green "  [PASS] 换行结尾: $f"
                ((pass++)) || true
            else
                yellow "  [WARN] 缺少末尾换行: $f (可能导致工具链异常)"
            fi
        fi
    done < <(find "$target_dir" -maxdepth 1 \( -name "*.sh" -o -name "*.md" -o -name "*.txt" \) -print0 2>/dev/null)

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

# 对所有课程执行自检
checker_verify_all() {
    local target_dir="${1:-.}"
    local total_fail=0

    while IFS= read -r course; do
        checker_verify "$course" "$target_dir"
        total_fail=$((total_fail + $?))
    done < <(config_list_courses)

    return $total_fail
}
