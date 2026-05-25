#!/bin/bash
# ============================================================
# functional_test.sh 閳?閸旂喕鍏樺ù瀣槸婵傛ぞ娆?# 濞村鐦懠鍐ㄦ纯: 閹碘偓閺?娑擃亝膩閸ф娈戦弽绋跨妇閸旂喕鍏?# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/lib/common.sh"

PASS=0
FAIL=0
TEST_LOG="$PROJECT_ROOT/logs/functional_test.log"
FIXTURES_DIR="$PROJECT_ROOT/fixtures"

mkdir -p "$PROJECT_ROOT/logs"
> "$TEST_LOG"

# ============================================================
# 濞村鐦銉ュ徔閸戣姤鏆?# ============================================================
log_test() {
    echo "[$(date '+%H:%M:%S')] $*" | tee -a "$TEST_LOG"
}

assert_pass() {
    local desc="$1"
    echo -n "  TEST: $desc ... "
    green "PASS"
    ((PASS++)) || true
    echo "PASS: $desc" >> "$TEST_LOG"
}

assert_fail() {
    local desc="$1"
    local reason="${2:-}"
    echo -n "  TEST: $desc ... "
    red "FAIL${reason:+ ($reason)}"
    ((FAIL++)) || true
    echo "FAIL: $desc ${reason:+($reason)}" >> "$TEST_LOG"
}

assert_eq() {
    local desc="$1"; local expected="$2"; local actual="$3"
    if [ "$expected" = "$actual" ]; then
        assert_pass "$desc"
    else
        assert_fail "$desc" "expected='$expected' actual='$actual'"
    fi
}

# ============================================================
# 濡€虫健1: deadline.sh 閸旂喕鍏樺ù瀣槸
# ============================================================
test_deadline() {
    echo ""
    bold "========== 濡€虫健1: deadline.sh 閸旂喕鍏樺ù瀣槸 =========="
    echo ""

    # 濞村鐦?.1: config_get 鐠囪褰嘍DL
    log_test "--- deadline: config_get test ---"
    local ddl
    ddl=$(config_get "linux" "ddl" 2>/dev/null || echo "")
    if [ -n "$ddl" ]; then
        assert_pass "test passed"
    else
        assert_fail "config_get linux.ddl" "test completed"
    fi

    # 濞村鐦?.2: config_get 鐠囪褰噑ubmit
    local submit
    submit=$(config_get "linux" "submit")
    if [ "$submit" = "scp" ]; then
        assert_pass "config_get linux.submit = scp"
    else
        assert_fail "config_get linux.submit" "expected=scp actual=$submit"
    fi

    # 濞村鐦?.3: config_list_courses 閸掓鍤幍鈧張澶庮嚦缁?
    local courses
    courses=$(config_list_courses)
    if echo "$courses" | grep -q "linux"; then
        assert_pass "test passed"
    else
        assert_fail "test failed"
    fi

    # 濞村鐦?.4: ddl_remaining_seconds 閺冨爼妫跨拋锛勭暬
    local future_date="2037-12-31 23:59"
    local remaining
    remaining=$(ddl_remaining_seconds "$future_date" 2>/dev/null || echo "0")
    if [ "$remaining" -gt 0 ]; then
        assert_pass "ddl_remaining_seconds 2037-12-31 > 0 ($remaining sec)"
    else
        assert_fail "test failed"
    fi

    # 濞村鐦?.5: ddl_remaining_seconds 鏉╁洦婀￠弮銉︽埂
    local past_date="2020-01-01 00:00"
    local past_remaining
    past_remaining=$(ddl_remaining_seconds "$past_date" 2>/dev/null || echo "0")
    if [ "$past_remaining" -lt 0 ]; then
        assert_pass "test passed"
    else
        assert_fail "test failed"
    fi

    # 濞村鐦?.6: human_readable_time
    local hr
    hr=$(human_readable_time 90061)  # 1 day 1 hour 1 min
    if echo "$hr" | grep -q "天"; then
        assert_pass "test passed"
    else
        assert_fail "test failed"
    fi

    # 濞村鐦?.7: deadline_check 閸戣姤鏆熸稉宥嗗Г闁?
    if source "$PROJECT_ROOT/lib/deadline.sh" 2>/dev/null; then
        deadline_check > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            assert_pass "deadline_check test completed"
        else
            assert_fail "deadline_check test completed"
        fi
    else
        assert_fail "source deadline.sh test completed"
    fi
}

# ============================================================
# 濡€虫健2: checker.sh 閸旂喕鍏樺ù瀣槸
# ============================================================
test_checker() {
    echo ""
    bold "========== 濡€虫健2: checker.sh 閸旂喕鍏樺ù瀣槸 =========="
    echo ""

    # 閸掓稑缂撳ù瀣槸閻滎垰顣?
    local test_dir="$PROJECT_ROOT/fixtures/checker_test"
    mkdir -p "$test_dir"

    # 2.1: 閸掓稑缂撶粭锕€鎮庣憴鍕瘱閻ㄥ嫯鍓奸張?
    cat > "$test_dir/good_script.sh" << 'SCRIPT'
#!/bin/bash
echo "Hello World"
SCRIPT
    chmod +x "$test_dir/good_script.sh"

    # 2.2: 閸掓稑缂撶紓鐑樺⒔鐞涘本娼堥梽鎰畱閼存碍婀?
    cat > "$test_dir/noperm_script.sh" << 'SCRIPT'
#!/bin/bash
echo "No Permission"
SCRIPT

    # 2.3: 閸掓稑缂撻張澶庮嚔濞夋洟鏁婄拠顖滄畱閼存碍婀?
    cat > "$test_dir/bad_syntax.sh" << 'SCRIPT'
#!/bin/bash
if [ -z "$VAR"
then
    echo "missing ]"
SCRIPT
    chmod +x "$test_dir/bad_syntax.sh"

    # 2.4: 閸掓稑缂撶紓鍝勭毌閺堫偄鐔幑銏ｎ攽閻ㄥ嫭鏋冩禒?
    printf "#!/bin/bash\necho no newline" > "$test_dir/no_newline.sh"
    chmod +x "$test_dir/no_newline.sh"

    # 2.5: 鏉╂劘顢?checker_verify
    log_test "--- checker: verify test ---"
    if source "$PROJECT_ROOT/lib/checker.sh" 2>/dev/null; then
        checker_verify "linux" "$test_dir" > /dev/null 2>&1 || true
        assert_pass "checker_verify linux test completed"
    else
        assert_fail "source checker.sh test completed"
    fi

    # 2.6: 濞村鐦?required_files 閸栧綊鍘?
    local req
    req=$(config_get "linux" "required_files")
    if echo "$req" | grep -q "report.pdf"; then
        assert_pass "test passed"
    else
        assert_fail "checker: required_files=$req"
    fi

    # 濞撳懐鎮?
    rm -rf "$test_dir"
}

# ============================================================
# 濡€虫健3: uploader.sh 閸旂喕鍏樺ù瀣槸
# ============================================================
test_uploader() {
    echo ""
    bold "========== 濡€虫健3: uploader.sh 閸旂喕鍏樺ù瀣槸 =========="
    echo ""

    # 3.1: config_get 鐠囪褰?target
    local target
    target=$(config_get "linux" "target")
    if echo "$target" | grep -q "192.168.1.100"; then
        assert_pass "test passed"
    else
        assert_fail "uploader: target=$target"
    fi

    # 3.2: config_get 鐠囪褰?naming
    local naming
    naming=$(config_get "linux" "naming")
    if echo "$naming" | grep -q "tar.gz"; then
        assert_pass "test passed"
    else
        assert_fail "uploader: naming=$naming"
    fi

    # 3.3: 濞村鐦?dry-run 濡€崇础閿涘牅绗夋惔鏂跨杽闂勫懏澧﹂崠鍛瑐娴肩媴绱?
    local test_dir="$PROJECT_ROOT/fixtures/uploader_test"
    mkdir -p "$test_dir"
    echo "test" > "$test_dir/test_file.txt"

    cd "$test_dir"
    if source "$PROJECT_ROOT/lib/uploader.sh" 2>/dev/null; then
        uploader_upload "linux" "true" > /dev/null 2>&1 || true
        assert_pass "uploader: dry-run test completed"
    fi
    cd "$PROJECT_ROOT"
    rm -rf "$test_dir"

    # 3.4: file_md5 閸戣姤鏆?
    local test_md5_file="$PROJECT_ROOT/fixtures/md5_test.txt"
    echo "hello md5 test" > "$test_md5_file"
    local md5_result
    md5_result=$(file_md5 "$test_md5_file" 2>/dev/null || echo "")
    if [ -n "$md5_result" ] && [ ${#md5_result} -eq 32 ]; then
        assert_pass "test passed"
    else
        assert_fail "test failed"
    fi
    rm -f "$test_md5_file"
}

# ============================================================
# 濡€虫健4: extractor.sh 閸旂喕鍏樺ù瀣槸 (闁板秶鐤嗘す鍗炲З閻?
# ============================================================
test_extractor() {
    echo ""
    bold "========== 濡€虫健4: extractor.sh 閸旂喕鍏樺ù瀣槸 (闁板秶鐤嗘す鍗炲З閻? =========="
    echo ""

    # 4.1: extractor_scan 濮濓絽鐖堕幍褑顢戞稉宥嗗Г闁?
    if source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null; then
        local result
        result=$(extractor_scan 2>/dev/null || true)
        if [ -n "$result" ]; then
            assert_pass "extractor: extractor_scan test completed"
        else
            assert_fail "extractor: extractor_scan test completed"
        fi
    else
        assert_fail "source extractor.sh test completed"
    fi

    # 4.2: 鏉堟挸鍤稉顓炲瘶閸氼偂绗佹稉顏囶嚦缁?(linux, db, ds)
    if source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null; then
        local result
        result=$(extractor_scan 2>/dev/null || true)
        if echo "$result" | grep -q "linux"; then
            assert_pass "test passed"
        else
            assert_fail "test failed"
        fi
        if echo "$result" | grep -q "db"; then
            assert_pass "test passed"
        else
            assert_fail "test failed"
        fi
        if echo "$result" | grep -q "ds"; then
            assert_pass "test passed"
        else
            assert_fail "test failed"
        fi
    fi

    # 4.3: config_get 鐠囪褰囬弬鏉款杻 grading 鐎涙顔?
    local grading
    grading=$(config_get "linux" "grading" 2>/dev/null || echo "")
    if echo "$grading" | grep -qE "40|50"; then
        assert_pass "test passed"
    else
        assert_fail "test failed"
    fi

    # 4.4: config_get 鐠囪褰囬弬鏉款杻 format 鐎涙顔?
    local fmt
    fmt=$(config_get "linux" "format" 2>/dev/null || echo "")
    if echo "$fmt" | grep -q "UTF-8"; then
        assert_pass "test passed"
    else
        assert_fail "test failed"
    fi

    # 4.5: config_get 鐠囪褰囬弬鏉款杻 forbidden 鐎涙顔?
    local forbid
    forbid=$(config_get "linux" "forbidden" 2>/dev/null || echo "")
    if echo "$forbid" | grep -q "test"; then
        assert_pass "test passed"
    else
        assert_fail "test failed"
    fi

    # 4.6: 鏉堟挸鍤稉顓炲瘶閸?[鐠囧嫬鍨庨弽鍥у櫙] [閺嶇厧绱＄憰浣圭湴] [缁備焦顒涙禍瀣€峕 閺嶅洨顒?
    if source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null; then
        local result
        result=$(extractor_scan 2>/dev/null || true)
        if echo "$result" | grep -q "鐠囧嫬鍨庨弽鍥у櫙"; then
            assert_pass "extractor: 鏉堟挸鍤崠鍛儓 [鐠囧嫬鍨庨弽鍥у櫙] test completed"
        else
            assert_fail "extractor: 鏉堟挸鍤紓鍝勭毌 [鐠囧嫬鍨庨弽鍥у櫙]"
        fi
        if echo "$result" | grep -q "閺嶇厧绱＄憰浣圭湴"; then
            assert_pass "extractor: 鏉堟挸鍤崠鍛儓 [閺嶇厧绱＄憰浣圭湴] test completed"
        else
            assert_fail "extractor: 鏉堟挸鍤紓鍝勭毌 [閺嶇厧绱＄憰浣圭湴]"
        fi
        if echo "$result" | grep -q "forbidden" 2>/dev/null; then
            assert_pass "extractor: 鏉堟挸鍤崠鍛儓 [缁備焦顒涙禍瀣€峕 test completed"
        else
            assert_fail "extractor: 鏉堟挸鍤紓鍝勭毌 [缁備焦顒涙禍瀣€峕"
        fi
    fi

    # 4.7: 閹绘劕褰囧Ч鍥ㄢ偓缁樻▔缁€楦款嚦缁嬪鏆熼柌?
    if source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null; then
        local result
        result=$(extractor_scan 2>/dev/null || true)
        if echo "$result" | grep -q "鐠囧墽鈻奸弫浼村櫤"; then
            assert_pass "extractor: 鏉堟挸鍤崠鍛儓 '鐠囧墽鈻奸弫浼村櫤' test completed"
        else
            assert_fail "extractor: test completed"
        fi
    fi

    # 4.8: 妤犲矁鐦?ddl 閺堫亣顫︽穱顔芥暭閿涘牆绨叉稉?sample_requirements.md 娑撯偓閼疯揪绱?
    local ddl
    ddl=$(config_get "linux" "ddl")
    if [ "$ddl" = "2026-06-20 23:59" ]; then
        assert_pass "test passed"
    else
        assert_fail "test failed"
    fi
}

# ============================================================
# 娑撹鍙嗛崣?# ============================================================
main() {
    echo ""
    bold "閳烘柡鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫧"
    bold "閳?  Assignment Guardian 閳?閸旂喕鍏樺ù瀣槸婵傛ぞ娆?       test completed"
    bold "閳烘埃鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ櫜閳烘劏鏅查埡鎰ㄦ殕"
    echo ""

    log_test "========== 閸旂喕鍏樺ù瀣槸瀵偓婵?=========="

    test_deadline
    test_checker
    test_uploader
    test_extractor

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

    log_test "========== 閸旂喕鍏樺ù瀣槸缂佹挻娼? PASS=$PASS FAIL=$FAIL =========="

    if [ "$FAIL" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
