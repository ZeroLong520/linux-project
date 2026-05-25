#!/bin/bash
# ============================================================
# checker.sh 鈥?妯″潡2: 浣滀笟瑙勮寖鑷鍣?
# 鍔熻兘:
#   - 妫€鏌ユ枃浠跺懡鍚嶆槸鍚︾鍚堣鑼?
#   - 妫€鏌ュ繀浜ゆ枃浠舵槸鍚﹂綈鍏?
#   - 妫€鏌hell鑴氭湰鏄惁鏈夋墽琛屾潈闄?
#   - 妫€鏌hell鑴氭湰璇硶 (bash -n)
#   - 妫€鏌ユ枃浠舵槸鍚︿互鎹㈣绗︾粨灏?
#   - 杈撳嚭妫€鏌ユ姤鍛婏紙閫氳繃/鏈€氳繃锛?
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# 瀵规寚瀹氳绋嬫墽琛岃鑼冭嚜妫€
checker_verify() {
    local course="$1"
    local target_dir="${2:-.}"

    echo ""
    bold "========== 浣滀笟瑙勮寖鑷: $course =========="
    echo ""

    local pass=0
    local fail=0

    # --- 妫€鏌ラ」1: 蹇呬氦鏂囦欢 ---
    local required
    required=$(config_get "$course" "required_files")
    if [ -n "$required" ]; then
        IFS=',' read -ra FILES <<< "$required"
        for pattern in "${FILES[@]}"; do
            pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            local found
            found=$(find "$target_dir" -maxdepth 1 -name "$pattern" 2>/dev/null | head -1)
            if [ -n "$found" ]; then
                green "  [PASS] 蹇呬氦鏂囦欢: $pattern 鈫?$found"
                ((pass++)) || true
            else
                red "  [FAIL] 蹇呬氦鏂囦欢: $pattern 鈫?鏈壘鍒?
                ((fail++)) || true
            fi
        done
    fi

    # --- 妫€鏌ラ」2: Shell鑴氭湰鎵ц鏉冮檺 ---
    while IFS= read -r -d '' script; do
        if [ -x "$script" ]; then
            green "  [PASS] 鍙墽琛屾潈闄? $script"
            ((pass++)) || true
        else
            red "  [FAIL] 缂哄皯鎵ц鏉冮檺: $script (寤鸿: chmod +x)"
            ((fail++)) || true
        fi
    done < <(find "$target_dir" -maxdepth 1 -name "*.sh" -print0 2>/dev/null)

    # --- 妫€鏌ラ」3: Shell鑴氭湰璇硶 (bash -n) ---
    while IFS= read -r -d '' script; do
        local syntax_result
        syntax_result=$(bash -n "$script" 2>&1)
        if [ $? -eq 0 ]; then
            green "  [PASS] 璇硶妫€鏌? $script"
            ((pass++)) || true
        else
            red "  [FAIL] 璇硶閿欒: $script 鈫?$syntax_result"
            ((fail++)) || true
        fi
    done < <(find "$target_dir" -maxdepth 1 -name "*.sh" -print0 2>/dev/null)

    # --- 妫€鏌ラ」4: 鏂囦欢浠ユ崲琛岀缁撳熬 ---
    while IFS= read -r -d '' f; do
        if [ -s "$f" ]; then
            local last_char
            last_char=$(tail -c 1 "$f" | od -An -tx1 | tr -d ' ')
            if [ "$last_char" = "0a" ]; then
                green "  [PASS] 鎹㈣缁撳熬: $f"
                ((pass++)) || true
            else
                yellow "  [WARN] 缂哄皯鏈熬鎹㈣: $f (鍙兘瀵艰嚧宸ュ叿閾惧紓甯?"
            fi
        fi
    done < <(find "$target_dir" -maxdepth 1 \( -name "*.sh" -o -name "*.md" -o -name "*.txt" \) -print0 2>/dev/null)

    # --- 姹囨€?---
    echo ""
    echo "-----------------------------------"
    local total=$((pass + fail))
    green "  閫氳繃: $pass"
    [ "$fail" -gt 0 ] && red "  鏈€氳繃: $fail"
    echo "  鎬昏: $total"
    echo ""

    log_info "checker verify: $course  pass=$pass fail=$fail"

    return $fail
}

# 瀵规墍鏈夎绋嬫墽琛岃嚜妫€
checker_verify_all() {
    local target_dir="${1:-.}"
    local total_fail=0

    while IFS= read -r course; do
        checker_verify "$course" "$target_dir"
        total_fail=$((total_fail + $?))
    done < <(config_list_courses)

    return $total_fail
}
