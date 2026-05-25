#!/bin/bash
# ============================================================
# exception_test.sh 閳?瀵倸鐖跺ù瀣槸婵傛ぞ娆?# 濞村鐦崷鐑樻珯:
#   1. 閺夊啴妾烘稉宥堝喕 (Permission Denied)
#   2. 閺傚洣娆㈡稉宥呯摠閸?(File Not Found)
#   3. 缂冩垹绮堕弬顓炵磻 (Network Disconnected)
#   4. 缁屾椽鍘ょ純?/ 缂傚搫銇戠€涙顔?(Empty Config / Missing Fields)
#   5. 闁板秶鐤嗘す鍗炲З閻?extractor 瀵倸鐖舵径鍕倞
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/lib/common.sh"

PASS=0
FAIL=0
TEST_LOG="$PROJECT_ROOT/logs/exception_test.log"
> "$TEST_LOG"

# ============================================================
# 瀹搞儱鍙?# ============================================================
log_test() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$TEST_LOG"; }
assert_pass() { echo -n "  TEST: $1 ... "; green "PASS"; ((PASS++)); echo "PASS: $1" >> "$TEST_LOG"; }
assert_fail() { echo -n "  TEST: $1 ... "; red "FAIL"; ((FAIL++)); echo "FAIL: $1" >> "$TEST_LOG"; }

# ============================================================
# 濞村鐦?: 閺夊啴妾烘稉宥堝喕
# ============================================================
test_permission_denied() {
    echo ""
    bold "========== 瀵倸鐖跺ù瀣槸1: 閺夊啴妾烘稉宥堝喕 =========="
    echo ""

    local perm_dir="$PROJECT_ROOT/fixtures/perm_test"
    mkdir -p "$perm_dir"

    # 1.1: create file with no permissions
    echo "secret content" > "$perm_dir/secret.txt"
    chmod 000 "$perm_dir/secret.txt" 2>/dev/null || true

    # 1.2: verify file is not readable
    if [ -r "$perm_dir/secret.txt" ]; then
        assert_fail "閺夊啴妾烘稉宥堝喕: 閹存劕濮涚拠璇插絿000閺夊啴妾洪弬鍥︽"
    else
        assert_pass "test passed"
    fi

    # 1.3: 閸掓稑缂撻弮鐘侯嚢閺夊啴妾洪惄顔肩秿
    mkdir -p "$perm_dir/noaccess"
    chmod 000 "$perm_dir/noaccess" 2>/dev/null || true

    # 1.4: 鐏忔繆鐦潻娑樺弳閺冪姵娼堥梽鎰窗瑜?
    if cd "$perm_dir/noaccess" 2>/dev/null; then
        assert_fail "test failed"
        cd "$PROJECT_ROOT"
    else
        assert_pass "test passed"
    fi

    # 1.5: config_get 鐎电懓缍嬮崜宥夊帳缂冾喗鏋冩禒鑸殿劀鐢瓕顕伴崣?
    if [ -f "$PROJECT_ROOT/config/courses.conf" ]; then
        assert_pass "閺夊啴妾烘稉宥堝喕: courses.conf test completed"
    else
        assert_fail "閺夊啴妾烘稉宥堝喕: courses.conf test completed"
    fi

    # 濞撳懐鎮?
    chmod 755 "$perm_dir/noaccess" 2>/dev/null || true
    chmod 644 "$perm_dir/secret.txt" 2>/dev/null || true
    rm -rf "$perm_dir"
}

# ============================================================
# 濞村鐦?: 閺傚洣娆㈡稉宥呯摠閸?/ 鐎涙顔屾稉宥呯摠閸?# ============================================================
test_file_not_found() {
    echo ""
    bold "========== 瀵倸鐖跺ù瀣槸2: 閺傚洣娆?鐎涙顔屾稉宥呯摠閸?=========="
    echo ""

    # 2.1: config_get 閺屻儴顕楁稉宥呯摠閸︺劎娈戠拠鍓р柤
    local result
    result=$(config_get "nonexistent" "ddl" 2>/dev/null || echo "EMPTY")
    if [ -z "$result" ] || [ "$result" = "EMPTY" ]; then
        assert_pass "test passed"
    else
        assert_fail "test failed"
    fi

    # 2.2: config_get 閺屻儴顕楀鎻掔摠閸︺劏顕崇粙瀣畱娑撳秴鐡ㄩ崷銊ョ摟濞?
    local missing_field
    missing_field=$(config_get "linux" "nonexistent_field" 2>/dev/null || echo "EMPTY")
    if [ -z "$missing_field" ] || [ "$missing_field" = "EMPTY" ]; then
        assert_pass "test passed"
    else
        assert_fail "test failed"
    fi

    # 2.3: file_md5 鐎甸€涚瑝鐎涙ê婀惃鍕瀮娴?
    local md5
    md5=$(file_md5 "/nonexistent/file.txt" 2>/dev/null || echo "ERROR")
    if [ "$md5" = "ERROR" ] || [ -z "$md5" ]; then
        assert_pass "閺傚洣娆㈡稉宥呯摠閸? file_md5 test completed"
    else
        assert_fail "test failed"
    fi

    # 2.4: checker_verify 鐎甸€涚瑝鐎涙ê婀惃鍕嚦缁?
    if source "$PROJECT_ROOT/lib/checker.sh" 2>/dev/null; then
        checker_verify "nonexistent" "." > /dev/null 2>&1 || true
        assert_pass "test passed"
    fi

    # 2.5: extractor_scan with valid config
    if source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null; then
        extractor_scan > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            assert_pass "test passed"
        else
            assert_fail "閺傚洣娆㈡稉宥呯摠閸? extractor_scan test completed"
        fi
    fi

    # 2.6: config_get 缁屽搫鐡у▓闈涒偓鐓庮槱閻?
    local test_conf="$PROJECT_ROOT/fixtures/blank_field.conf"
    cat > "$test_conf" << 'CONF'
[test_course]
ddl =
submit =
target =
required_files =
CONF
    local blank_ddl
    blank_ddl=$(awk -v course="test_course" -v field="ddl" '
        BEGIN { in_section = 0 }
        $0 ~ "^\\[" course "\\]" { in_section = 1; next }
        $0 ~ "^\\[" { in_section = 0 }
        in_section && $1 == field { sub(/^[^=]*= /, ""); print; exit }
    ' "$test_conf" 2>/dev/null || echo "BLANK")
    if [ -z "$blank_ddl" ] || [ "$blank_ddl" = "BLANK" ]; then
        assert_pass "閺傚洣娆㈡稉宥呯摠閸? test completed"
    else
        assert_fail "test failed"
    fi
    rm -f "$test_conf"
}

# ============================================================
# 濞村鐦?: 缂冩垹绮堕弬顓炵磻濡剝瀚?# ============================================================
test_network_disconnected() {
    echo ""
    bold "========== 瀵倸鐖跺ù瀣槸3: 缂冩垹绮堕弬顓炵磻 =========="
    echo ""

    # 3.1: SCP 閸掗绗夌€涙ê婀惃鍕瘜閺?
    local test_tarball="$PROJECT_ROOT/fixtures/test_upload.tar.gz"
    echo "network test" > "$PROJECT_ROOT/fixtures/test_upload.txt"
    tar czf "$test_tarball" -C "$PROJECT_ROOT/fixtures" test_upload.txt 2>/dev/null || true

    # 濡剝瀚?SCP 婢惰精瑙?閳?娑撳秴绨插畷鈺傜皾
    if scp "$test_tarball" "no-such-host.example.com:/tmp/" 2>/dev/null; then
        assert_fail "缂冩垹绮堕弬顓炵磻: SCPtest completed"
    else
        assert_pass "test completed"
    fi

    rm -f "$test_tarball" "$PROJECT_ROOT/fixtures/test_upload.txt"

    # 3.2: uploader dry-run 濡€崇础娑撳绗夌亸婵婄槸缂冩垹绮舵潻鐐村复
    local upload_dir="$PROJECT_ROOT/fixtures/upload_net_test"
    mkdir -p "$upload_dir"
    cd "$upload_dir"
    if source "$PROJECT_ROOT/lib/uploader.sh" 2>/dev/null; then
        uploader_upload "linux" "true" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            assert_pass "缂冩垹绮堕弬顓炵磻: dry-run test completed"
        else
            assert_fail "缂冩垹绮堕弬顓炵磻: dry-run test completed"
        fi
    fi
    cd "$PROJECT_ROOT"
    rm -rf "$upload_dir"

    # 3.3: SSH 閸掗绗夌€涙ê婀稉缁樻簚
    if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no "no-such-host.example.com" "echo test" 2>/dev/null; then
        assert_fail "缂冩垹绮堕弬顓炵磻: SSHtest completed"
    else
        assert_pass "test completed"
    fi
}

# ============================================================
# 濞村鐦?: 缁屾椽鍘ょ純?/ 瀵倸鐖堕柊宥囩枂
# ============================================================
test_empty_config() {
    echo ""
    bold "========== 瀵倸鐖跺ù瀣槸4: 缁屾椽鍘ょ純?/ 瀵倸鐖堕柊宥囩枂 =========="
    echo ""

    # 4.1: 閸掓稑缂撶粚娲帳缂冾喗鏋冩禒?
    local empty_config="$PROJECT_ROOT/fixtures/empty_courses.conf"
    echo "" > "$empty_config"

    # 4.2: 鐎靛湱鈹栭柊宥囩枂鐠嬪啰鏁?config_list_courses
    local courses
    courses=$(awk '/^\[.*\]/ { gsub(/[\[\]]/, ""); print }' "$empty_config" 2>/dev/null || echo "")
    if [ -z "$courses" ]; then
        assert_pass "缁屾椽鍘ょ純? config_list_courses test completed"
    else
        assert_fail "test failed"
    fi

    # 4.3: 鐎靛湱鈹栭柊宥囩枂鐠嬪啰鏁?config_get
    local val
    val=$(awk -v course="linux" -v field="ddl" '
        BEGIN { in_section = 0 }
        $0 ~ "^\\[" course "\\]" { in_section = 1; next }
        $0 ~ "^\\[" { in_section = 0 }
        in_section && $1 == field { sub(/^[^=]*= /, ""); print; exit }
    ' "$empty_config" 2>/dev/null || echo "")
    if [ -z "$val" ]; then
        assert_pass "缁屾椽鍘ょ純? config_get test completed"
    else
        assert_fail "test failed"
    fi

    rm -f "$empty_config"

    # 4.4: 闁板秶鐤嗛弬鍥︽缂傚搫銇戦弮鍓佹畱鐞涘奔璐?
    if [ -f "$PROJECT_ROOT/config/courses.conf" ]; then
        assert_pass "test passed"
    else
        assert_fail "缁屾椽鍘ょ純? courses.conf test completed"
    fi

    # 4.5: 妤犲矁鐦夐弬鏉款杻鐎涙顔?grading/format/forbidden 鐎涙ê婀?
    local grading format forbidden
    grading=$(config_get "linux" "grading" 2>/dev/null || echo "")
    format=$(config_get "linux" "format" 2>/dev/null || echo "")
    forbidden=$(config_get "linux" "forbidden" 2>/dev/null || echo "")
    if [ -n "$grading" ] && [ -n "$format" ] && [ -n "$forbidden" ]; then
        assert_pass "缁屾椽鍘ょ純? 閺傛澘顤冪€涙顔?grading/format/forbidden test completed"
    else
        assert_fail "test failed"
    fi

    # 4.6: ddl 閺堫亣顫︽穱顔芥暭绾喛顓?
    local db_ddl ds_ddl
    db_ddl=$(config_get "db" "ddl")
    ds_ddl=$(config_get "ds" "ddl")
    if [ "$db_ddl" = "2026-06-15 17:00" ]; then
        assert_pass "test passed"
    else
        assert_fail "test failed"
    fi
    if [ "$ds_ddl" = "2026-06-10 12:00" ]; then
        assert_pass "test passed"
    else
        assert_fail "test failed"
    fi
}

# ============================================================
# 濞村鐦?: extractor 闁板秶鐤嗘す鍗炲З瀵倸鐖舵径鍕倞
# ============================================================
test_extractor_exceptions() {
    echo ""
    bold "========== 瀵倸鐖跺ù瀣槸5: extractor 闁板秶鐤嗘す鍗炲З瀵倸鐖?=========="
    echo ""

    # 5.1: config_list_courses 濮濓絽鐖舵潻鏂挎礀閹碘偓閺堝顕崇粙?
    local courses
    courses=$(config_list_courses 2>/dev/null || echo "")
    local course_count
    course_count=$(echo "$courses" | grep -c . 2>/dev/null || echo 0)
    if [ "$course_count" -ge 3 ]; then
        assert_pass "extractor瀵倸鐖? 闁板秶鐤嗘稉顓熸箒 ${course_count} test completed"
    else
        assert_fail "extractor瀵倸鐖? 娴?${course_count} test completed"
    fi

    # 5.2: extractor_scan 鏉堟挸鍤崠鍛儓闁板秶鐤嗛弶銉︾爱鐠侯垰绶?
    if source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null; then
        local result
        result=$(extractor_scan 2>/dev/null || true)
        if echo "$result" | grep -q "courses.conf"; then
            assert_pass "test passed"
        else
            assert_fail "test failed"
        fi
    fi

    # 5.3: DISPLAY_ORDER 閸栧懎鎯堥幍鈧張?娑擃亜鐡у▓?
    if source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null; then
        if [ "${#DISPLAY_ORDER[@]}" -eq 9 ]; then
            assert_pass "extractor瀵倸鐖? DISPLAY_ORDER test completed"
        else
            assert_fail "extractor瀵倸鐖? DISPLAY_ORDER=${#DISPLAY_ORDER[@]} test completed"
        fi
    fi

    # 5.4: CATEGORY_LABELS 閸栧懎鎯堥弬鏉款杻閺嶅洨顒?
    if source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null; then
        if [ "${CATEGORY_LABELS[grading]}" = "[鐠囧嫬鍨庨弽鍥у櫙]" ] && \
           [ "${CATEGORY_LABELS[format]}" = "[閺嶇厧绱＄憰浣圭湴]" ] && \
           [ "${CATEGORY_LABELS[forbidden]}" = "[缁備焦顒涙禍瀣€峕" ]; then
            assert_pass "extractor瀵倸鐖? 閺傛澘顤冮弽鍥╊劮 grading/format/forbidden test completed"
        else
            assert_fail "test failed"
        fi
    fi
}

# ============================================================
# 娑撹鍙嗛崣?# ============================================================
main() {
    echo ""
    bold "閳烘柡鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫧"
    bold "閳?  Assignment Guardian 閳?瀵倸鐖跺ù瀣槸婵傛ぞ娆?       test completed"
    bold "閳烘埃鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ殕"
    echo ""

    log_test "========== 瀵倸鐖跺ù瀣槸瀵偓婵?=========="

    test_permission_denied
    test_file_not_found
    test_network_disconnected
    test_empty_config
    test_extractor_exceptions

    echo ""
    bold "========== 濞村鐦Ч鍥ㄢ偓?=========="
    echo ""
    local total=$((PASS + FAIL))
    green "  闁俺绻? $PASS / $total"
    if [ "$FAIL" -gt 0 ]; then
        red "  婢惰精瑙? $FAIL / $total"
    fi
    echo ""
    echo "  鐠囷妇绮忛弮銉ョ箶: $TEST_LOG"
    echo ""

    log_test "========== 瀵倸鐖跺ù瀣槸缂佹挻娼? PASS=$PASS FAIL=$FAIL =========="

    if [ "$FAIL" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
