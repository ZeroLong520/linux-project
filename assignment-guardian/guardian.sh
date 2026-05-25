#!/bin/bash
# ============================================================
# guardian.sh 鈥?浣滀笟瀹堟姢鑰?涓诲叆鍙?
# 鐢ㄦ硶:
#   ./guardian.sh check              鎵弿浣滀笟鎴鏃堕棿
#   ./guardian.sh check --all         鏄剧ず鎵€鏈変綔涓氾紙鍚繙鏈燂級
#   ./guardian.sh verify <璇剧▼>       瀵规寚瀹氳绋嬫墽琛岃鑼冭嚜妫€
#   ./guardian.sh verify --all        瀵规墍鏈夎绋嬫墽琛岃鑼冭嚜妫€
#   ./guardian.sh upload <璇剧▼>       鎵撳寘骞朵笂浼犱綔涓?
#   ./guardian.sh upload --dry <璇剧▼> 璇曡繍琛屾ā寮?
#   ./guardian.sh extract [鐩綍]      鎻愬彇浣滀笟闇€姹傚叧閿瓧
#   ./guardian.sh status              鎬昏闈㈡澘
#   ./guardian.sh help                鏄剧ず甯姪
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 鍔犺浇妯″潡搴?
# 鍔犺浇妯″潡搴擄紙鍏?common锛屼箣鍚庣敤 PROJECT_ROOT 瀹氫綅锛?
source "$SCRIPT_DIR/lib/common.sh"
source "$PROJECT_ROOT/lib/deadline.sh"
source "$PROJECT_ROOT/lib/checker.sh"
source "$PROJECT_ROOT/lib/uploader.sh"
source "$PROJECT_ROOT/lib/extractor.sh"

# -------------------- 甯姪淇℃伅 --------------------
show_help() {
    echo "鐢ㄦ硶: ./guardian.sh <鍛戒护> [鍙傛暟]"
    echo ""
    echo "鍛戒护:"
    echo "  check              鎵弿浣滀笟鎴鏃堕棿锛堝叏閮ㄦ樉绀猴級"
    echo "  verify <璇剧▼>       瀵规寚瀹氳绋嬫墽琛岃鑼冭嚜妫€"
    echo "  verify --all        瀵规墍鏈夎绋嬫墽琛岃鑼冭嚜妫€"
    echo "  upload <璇剧▼>       鎵撳寘骞朵笂浼犳寚瀹氳绋嬩綔涓?
    echo "  upload --dry <璇剧▼> 璇曡繍琛屾ā寮忥紙鍙睍绀猴紝涓嶄笂浼狅級"
    echo "  extract [鐩綍]      浠庣洰褰曚腑鎻愬彇浣滀笟闇€姹傚叧閿瓧"
    echo "  status              鏄剧ず鎵€鏈変綔涓氱姸鎬佹€昏"
    echo "  help                鏄剧ず姝ゅ府鍔?
    echo ""
    echo "绀轰緥:"
    echo "  ./guardian.sh check"
    echo "  ./guardian.sh verify linux"
    echo "  ./guardian.sh upload --dry linux"
    echo "  ./guardian.sh extract ~/璇句欢/"
}

# -------------------- 鐘舵€佹€昏 --------------------
show_status() {
    echo ""
    bold "========== 浣滀笟瀹堟姢鑰?鈥?鐘舵€佹€昏 =========="
    echo ""
    echo "  閰嶇疆鏂囦欢: $CONFIG_FILE"
    echo "  鏃ュ織鏂囦欢: $LOG_FILE"
    echo "  璇剧▼鏁伴噺: $(config_list_courses | wc -l)"
    echo ""
    echo "  璇剧▼鍒楄〃:"
    while IFS= read -r course; do
        local ddl submit
        ddl=$(config_get "$course" "ddl")
        submit=$(config_get "$course" "submit")
        printf "    %-10s  DDL: %-16s  鎻愪氦: %s\n" "$course" "$ddl" "$submit"
    done < <(config_list_courses)
    echo ""
}

# -------------------- 涓诲叆鍙?--------------------
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        check)
            deadline_check
            ;;
        verify)
            if [ "${2:-}" = "--all" ]; then
                checker_verify_all "."
            elif [ -n "${2:-}" ]; then
                checker_verify "${2}" "."
            else
                red "閿欒: 璇锋寚瀹氳绋嬪悕锛屾垨浣跨敤 --all 妫€鏌ユ墍鏈?
                echo "绀轰緥: ./guardian.sh verify linux"
                exit 1
            fi
            ;;
        upload)
            if [ "${2:-}" = "--dry" ]; then
                uploader_upload "${3:-}" "true"
            elif [ -n "${2:-}" ]; then
                uploader_upload "${2}" "false"
            else
                red "閿欒: 璇锋寚瀹氳绋嬪悕"
                echo "绀轰緥: ./guardian.sh upload linux"
                exit 1
            fi
            ;;
        extract)
            extractor_scan "${2:-.}"
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            red "鏈煡鍛戒护: $cmd"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
