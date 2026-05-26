#!/bin/bash
# ============================================================
# checker.sh — 模块2: 作业规范自检器
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

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
