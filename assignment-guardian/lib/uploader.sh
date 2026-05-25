#!/bin/bash
# ============================================================
# uploader.sh 鈥?妯″潡3: 涓€閿墦鍖呬笂浼?
# 鍔熻兘:
#   - 璇诲彇閰嶇疆涓殑鎵撳寘鍛藉悕瑙勫垯
#   - 鑷姩 tar 鎵撳寘
#   - SCP 涓婁紶鑷崇洰鏍囨湇鍔″櫒
#   - MD5 鏍￠獙涓婁紶瀹屾暣鎬?
#   - 鏀寔 dry-run 璇曡繍琛屾ā寮?
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# 鎵撳寘骞朵笂浼犳寚瀹氳绋嬩綔涓?
uploader_upload() {
    local course="$1"
    local dry_run="${2:-false}"

    local target
    target=$(config_get "$course" "target")
    local naming
    naming=$(config_get "$course" "naming")

    if [ -z "$target" ]; then
        red "閿欒: 璇剧▼ '$course' 鏈厤缃彁浜ょ洰鏍?(target)"
        return 1
    fi

    echo ""
    bold "========== 鎵撳寘涓婁紶: $course =========="
    echo ""

    # 鐢熸垚鍖呭悕锛堟浛鎹㈠鍙蜂负鍗犱綅绗︼紝鐢ㄦ埛闇€鎵嬪姩淇敼鎴栭€氳繃鍙傛暟浼犲叆锛?
    local tarball="${naming:-${course}_backup.tar.gz}"
    tarball=$(echo "$tarball" | sed 's/瀛﹀彿/${STUDENT_ID:-unknown}/g')

    echo "  鎵撳寘鏂囦欢: $tarball"
    echo "  鎻愪氦鐩爣: $target"

    if [ "$dry_run" = "true" ]; then
        yellow "  [DRY-RUN] 璺宠繃瀹為檯鎵撳寘鍜屼笂浼?
        echo ""
        return 0
    fi

    # Step 1: 鎵撳寘
    echo ""
    echo "  [1/3] 姝ｅ湪鎵撳寘..."
    if tar czf "$tarball" . --exclude="logs" --exclude=".git" --exclude="*.tar.gz" --exclude="*.zip" 2>/dev/null; then
        local size
        size=$(du -h "$tarball" | cut -f1)
        green "  [1/3] 鎵撳寘瀹屾垚 ($size): $tarball"
    else
        red "  [1/3] 鎵撳寘澶辫触"
        return 1
    fi

    # Step 2: 涓婁紶 (SCP)
    echo "  [2/3] 姝ｅ湪涓婁紶..."
    if scp "$tarball" "$target" 2>/dev/null; then
        green "  [2/3] 涓婁紶瀹屾垚 鈫?$target"
    else
        red "  [2/3] 涓婁紶澶辫触: 璇锋鏌ョ綉缁滃拰SSH閰嶇疆"
        return 1
    fi

    # Step 3: MD5 鏍￠獙
    echo "  [3/3] 姝ｅ湪鏍￠獙..."
    local local_md5 remote_md5
    local_md5=$(file_md5 "$tarball")
    local remote_file="$target/$(basename "$tarball")"

    remote_md5=$(ssh "${target%%:*}" "md5sum '$remote_file' 2>/dev/null | awk '{print \$1}'" 2>/dev/null || echo "")

    if [ -n "$remote_md5" ] && [ "$local_md5" = "$remote_md5" ]; then
        green "  [3/3] 鏍￠獙閫氳繃: MD5=$local_md5"
    else
        yellow "  [3/3] 鏃犳硶鏍￠獙杩滅▼MD5锛堝彲鑳介渶瑕佹墜鍔ㄧ‘璁わ級"
        yellow "       鏈湴MD5: $local_md5"
    fi

    echo ""
    green "  鉁?涓婁紶娴佺▼瀹屾垚"
    log_info "uploader: $course 鈫?$target  tarball=$tarball  md5=$local_md5"
}
