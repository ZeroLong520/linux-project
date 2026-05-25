#!/bin/bash
# ============================================================
# extractor.sh 鈥?妯″潡4: 浣滀笟闇€姹傛彁鍙栧櫒 (閰嶇疆椹卞姩鐗?
# 鍔熻兘:
#   - 鐩存帴瑙ｆ瀽 config/courses.conf 涓殑缁撴瀯鍖栦綔涓氶厤缃?#   - 灞曠ず鎴鏃堕棿銆佹彁浜ゆ柟寮忋€佸繀浜ゆ枃浠躲€佸懡鍚嶈鑼冦€佽瘎鍒嗘爣鍑嗐€?#     鏍煎紡瑕佹眰銆佺姝簨椤圭瓑瀹屾暣淇℃伅
#   - 鎸夎绋嬬淮搴﹁緭鍑烘眹鎬绘姤鍛?# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ============================================================
# 鍒嗙被鏍囩涓枃鏄犲皠
# ============================================================
declare -A CATEGORY_LABELS
CATEGORY_LABELS["ddl"]="[鎴鏃堕棿]"
CATEGORY_LABELS["submit"]="[鎻愪氦鏂瑰紡]"
CATEGORY_LABELS["target"]="[鎻愪氦鐩爣]"
CATEGORY_LABELS["required_files"]="[蹇呬氦鏂囦欢]"
CATEGORY_LABELS["naming"]="[鎵撳寘鍛藉悕]"
CATEGORY_LABELS["notes"]="[琛ュ厖璇存槑]"
CATEGORY_LABELS["grading"]="[璇勫垎鏍囧噯]"
CATEGORY_LABELS["format"]="[鏍煎紡瑕佹眰]"
CATEGORY_LABELS["forbidden"]="[绂佹浜嬮」]"

# 瀛楁灞曠ず鐨勬帓搴?readonly DISPLAY_ORDER=(
    "ddl"
    "submit"
    "target"
    "required_files"
    "naming"
    "grading"
    "format"
    "forbidden"
    "notes"
)

# ============================================================
# 瑙ｆ瀽 courses.conf 骞跺睍绀哄崟涓绋嬬殑瀹屾暣闇€姹?# ============================================================
extract_course_info() {
    local course="$1"

    echo "  鈥斺€斺€?璇剧▼: $course 鈥斺€斺€?
    echo ""

    local has_any=false

    for field in "${DISPLAY_ORDER[@]}"; do
        local value
        value=$(config_get "$course" "$field" 2>/dev/null || true)
        if [ -n "$value" ]; then
            local label="${CATEGORY_LABELS[$field]:-[$field]}"
            printf "    %-16s %s\n" "$label" "$value"
            has_any=true
        fi
    done

    if [ "$has_any" = false ]; then
        yellow "    (鏃犻厤缃俊鎭?"
    fi

    echo ""
}

# ============================================================
# 涓诲嚱鏁? 浠?courses.conf 鎻愬彇鎵€鏈夎绋嬩綔涓氶渶姹?# ============================================================
extractor_scan() {
    echo ""
    bold "========== 浣滀笟闇€姹傛彁鍙栧櫒 (閰嶇疆椹卞姩鐗? =========="
    echo "  閰嶇疆鏉ユ簮: $CONFIG_FILE"
    echo ""

    local course_count=0

    while IFS= read -r course; do
        [ -z "$course" ] && continue
        extract_course_info "$course"
        ((course_count++)) || true
    done < <(config_list_courses)

    echo "  鈥斺€斺€?鎻愬彇姹囨€?鈥斺€斺€?
    echo "  璇剧▼鏁伴噺: $course_count"
    echo "  閰嶇疆瀛楁: ${#DISPLAY_ORDER[@]} 椤?
    echo ""
    green "  鉁?鎻愬彇瀹屾垚"
    log_info "extractor: scanned $course_count courses from $CONFIG_FILE"
}
