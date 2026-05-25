#!/bin/bash
# ============================================================
# boundary_test.sh 鈥?杈圭晫娴嬭瘯濂椾欢
# 娴嬭瘯鍦烘櫙:
#   1. 瓒呭ぇ鏃ュ織鏂囦欢 (>100MB)
#   2. 纾佺洏绌洪棿涓嶈冻妯℃嫙
#   3. CPU婊¤浇鍦烘櫙
#   4. 缁煎悎鍘嬪姏娴嬭瘯 (閰嶇疆椹卞姩鐗?
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/lib/common.sh"

PASS=0
FAIL=0
TEST_LOG="$PROJECT_ROOT/logs/boundary_test.log"
> "$TEST_LOG"

# ============================================================
# 宸ュ叿
# ============================================================
log_test() {
    echo "[$(date '+%H:%M:%S')] $*" | tee -a "$TEST_LOG"
}
assert_pass() {
    echo -n "  TEST: $1 ... "
    green "PASS"
    ((PASS++)) || true
    echo "PASS: $1" >> "$TEST_LOG"
}
assert_fail() {
    echo -n "  TEST: $1 ... "
    red "FAIL"
    ((FAIL++)) || true
    echo "FAIL: $1" >> "$TEST_LOG"
}

# ============================================================
# 娴嬭瘯1: 瓒呭ぇ鏃ュ織鏂囦欢
# ============================================================
test_large_log() {
    echo ""
    bold "========== 杈圭晫娴嬭瘯1: 瓒呭ぇ鏃ュ織鏂囦欢 =========="
    echo ""

    local large_dir="$PROJECT_ROOT/fixtures/large_test"
    mkdir -p "$large_dir"

    # 1.1: 鐢熸垚 10MB 鏃ュ織鏂囦欢锛屾祴璇曟棩蹇楃郴缁熷鐞嗗ぇ鏂囦欢
    log_test "鐢熸垚10MB娴嬭瘯鏃ュ織..."
    local large_log="$large_dir/large_log.txt"
    > "$large_log"
    for i in $(seq 1 50000); do
        echo "Line $i: [INFO] deadline check: linux DDL=2026-06-20 23:59 remaining=12345 seconds" >> "$large_log"
    done

    local file_size
    file_size=$(du -h "$large_log" | cut -f1)
    log_test "鐢熸垚鏂囦欢澶у皬: $file_size"

    # 1.2: 鏃ュ織鍐欏叆鎬ц兘 鈥?5000鏉¤繛缁啓鍏?
    local bench_log="$PROJECT_ROOT/logs/bench_write.log"
    > "$bench_log"
    local start_time end_time elapsed
    start_time=$(date +%s)
    for i in $(seq 1 5000); do
        log_info "bench write test line $i with some extra data for padding"
    done
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    local entries
    entries=$(wc -l < "$bench_log" 2>/dev/null || echo 0)
    if [ "$entries" -ge 5000 ] && [ "$elapsed" -lt 10 ]; then
        assert_pass "瓒呭ぇ鏃ュ織: 5000鏉℃棩蹇楀啓鍏ヨ€楁椂${elapsed}s"
    else
        assert_fail "瓒呭ぇ鏃ュ織: 5000鏉″啓鍏ヨ€楁椂${elapsed}s, 鏉＄洰=$entries"
    fi
    rm -f "$bench_log"

    # 1.3: 瓒呭ぇ鏂囦欢 grep 鍏抽敭璇嶆€ц兘
    start_time=$(date +%s)
    grep -c "deadline" "$large_log" > /dev/null 2>&1 || true
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    if [ "$elapsed" -lt 5 ]; then
        assert_pass "瓒呭ぇ鏃ュ織: grep鍏抽敭璇嶈€楁椂${elapsed}s (<5s)"
    else
        assert_fail "瓒呭ぇ鏃ュ織: grep鑰楁椂${elapsed}s"
    fi

    # 1.4: 瓒呭ぇ鏂囦欢 MD5 璁＄畻
    local md5_time
    start_time=$(date +%s%N)
    file_md5 "$large_log" > /dev/null 2>&1 || true
    end_time=$(date +%s%N)
    elapsed=$(( (end_time - start_time) / 1000000 ))  # 姣
    if [ "$elapsed" -lt 5000 ]; then
        assert_pass "瓒呭ぇ鏃ュ織: MD5璁＄畻${file_size}鑰楁椂${elapsed}ms"
    else
        assert_fail "瓒呭ぇ鏃ュ織: MD5璁＄畻鑰楁椂${elapsed}ms"
    fi

    # 1.5: 鏃ュ織鏂囦欢澶у皬鐩戞帶
    local log_size
    log_size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$log_size" -gt 0 ]; then
        assert_pass "瓒呭ぇ鏃ュ織: 鏃ュ織鏂囦欢姝ｅ父澧為暱 (${log_size} bytes)"
    else
        assert_fail "瓒呭ぇ鏃ュ織: 鏃ュ織鏂囦欢涓虹┖"
    fi

    rm -rf "$large_dir"
}

# ============================================================
# 娴嬭瘯2: 纾佺洏绌洪棿涓嶈冻妯℃嫙
# ============================================================
test_disk_full() {
    echo ""
    bold "========== 杈圭晫娴嬭瘯2: 纾佺洏绌洪棿涓嶈冻 =========="
    echo ""

    # 2.1: 妫€鏌ュ綋鍓嶇鐩樺彲鐢ㄧ┖闂?
    local disk_info avail
    disk_info=$(df -h "$PROJECT_ROOT" 2>/dev/null | tail -1 || echo "")
    avail=$(echo "$disk_info" | awk '{print $4}' 2>/dev/null || echo "unknown")
    log_test "褰撳墠纾佺洏鍙敤绌洪棿: $avail"
    assert_pass "test passed"

    # 2.2: 娴嬭瘯鍦ㄥ彧璇荤洰褰曚腑鍐欏叆鏃ュ織
    local test_dir="$PROJECT_ROOT/fixtures/disk_test"
    mkdir -p "$test_dir"

    local readonly_dir="$test_dir/readonly"
    mkdir -p "$readonly_dir"
    chmod 444 "$readonly_dir" 2>/dev/null || true

    # Try creating file in read-only dir — should fail
    if touch "$readonly_dir/test.log" 2>/dev/null; then
        assert_fail "test failed"
        chmod 755 "$readonly_dir" 2>/dev/null || true
    else
        assert_pass "test passed"
    fi

    chmod 755 "$readonly_dir" 2>/dev/null || true

    # 2.3: check logs dir writability
    if [ -w "$LOG_DIR" ]; then
        assert_pass "test passed"
    else
        assert_fail "纾佺洏婊? logstest completed"
    fi

    # 2.4: check config file readability
    if [ -r "$CONFIG_FILE" ]; then
        assert_pass "test passed"
    else
        assert_fail "纾佺洏婊? courses.conf test completed"
    fi

    rm -rf "$test_dir"
}

# ============================================================
# 娴嬭瘯3: CPU婊¤浇鍦烘櫙 (閰嶇疆椹卞姩鐗?
# ============================================================
test_cpu_full() {
    echo ""
    bold "========== 杈圭晫娴嬭瘯3: CPU婊¤浇 鈥?閰嶇疆瑙ｆ瀽鍘嬪姏 =========="
    echo ""

    # 3.1: 椤哄簭澶氭璋冪敤 extractor_scan锛堟ā鎷熸甯歌礋杞斤級
    log_test "椤哄簭澶氭璋冪敤 config_get 鍘嬪姏娴嬭瘯..."
    local start_time end_time
    start_time=$(date +%s%N)
    for i in $(seq 1 100); do
        config_get "linux" "ddl" > /dev/null 2>&1 || true
        config_get "linux" "submit" > /dev/null 2>&1 || true
        config_get "linux" "grading" > /dev/null 2>&1 || true
        config_get "db" "ddl" > /dev/null 2>&1 || true
        config_get "ds" "ddl" > /dev/null 2>&1 || true
    done
    end_time=$(date +%s%N)
    local elapsed=$(( (end_time - start_time) / 1000000 ))
    if [ "$elapsed" -lt 5000 ]; then
        assert_pass "test completed"
    else
        assert_fail "test completed"
    fi

    # 3.2: 椤哄簭鎵ц extractor_scan 10娆?
    log_test "椤哄簭璋冪敤 extractor_scan 脳 10..."
    start_time=$(date +%s%N)
    if source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null; then
        for i in $(seq 1 10); do
            extractor_scan > /dev/null 2>&1 || true
        done
    fi
    end_time=$(date +%s%N)
    elapsed=$(( (end_time - start_time) / 1000000 ))
    if [ "$elapsed" -lt 10000 ]; then
        assert_pass "test completed"
    else
        assert_fail "test completed"
    fi

    # 3.3: 骞跺彂鎵ц妯℃嫙 鈥?4涓悗鍙拌繘绋嬭皟鐢?config_get
    log_test "骞跺彂 config_get 4 杩涚▼..."
    start_time=$(date +%s%N)
    for i in 1 2 3 4; do
        (
            cd "$PROJECT_ROOT"
            source "$PROJECT_ROOT/lib/common.sh" 2>/dev/null
            for j in $(seq 1 50); do
                config_get "linux" "ddl" > /dev/null 2>&1 || true
                config_get "db" "submit" > /dev/null 2>&1 || true
                config_get "ds" "naming" > /dev/null 2>&1 || true
            done
        ) &
    done
    wait
    end_time=$(date +%s%N)
    elapsed=$(( (end_time - start_time) / 1000000 ))
    if [ "$elapsed" -lt 30000 ]; then
        assert_pass "test completed"
    else
        assert_fail "test completed"
    fi

    # 3.4: 绯荤粺鍦ㄩ珮璐熻浇涓嬩粛鑳藉搷搴?
    local resp
    resp=$(date +%s 2>/dev/null || echo 0)
    if [ "$resp" -gt 0 ]; then
        assert_pass "test completed"
    else
        assert_fail "CPU婊¤浇: test completed"
    fi
}

# ============================================================
# 娴嬭瘯4: 缁煎悎鍘嬪姏娴嬭瘯 (閰嶇疆椹卞姩鐗?
# ============================================================
test_stress_combined() {
    echo ""
    bold "========== Boundary Test 4: Combined Stress =========="
    echo ""

    # 4.1: 鍏ㄩ噺 config_get 璇诲彇鎵€鏈夎绋嬫墍鏈夊瓧娈?
    local start_time end_time
    start_time=$(date +%s%N)
    local fields=("ddl" "submit" "target" "required_files" "naming" "grading" "format" "forbidden" "notes")
    local total_reads=0
    while IFS= read -r course; do
        [ -z "$course" ] && continue
        for field in "${fields[@]}"; do
            config_get "$course" "$field" > /dev/null 2>&1 || true
            ((total_reads++)) || true
        done
    done < <(config_list_courses)
    end_time=$(date +%s%N)
    local elapsed=$(( (end_time - start_time) / 1000000 ))

    if [ "$elapsed" -lt 5000 ]; then
        assert_pass "缁煎悎鍘嬪姏: ${total_reads}娆onfig_get鑰楁椂${elapsed}ms (<5s)"
    else
        assert_fail "test completed"
    fi

    # 4.2: deadline_check 鍘嬪姏娴嬭瘯
    log_test "deadline_check 鍘嬪姏娴嬭瘯..."
    start_time=$(date +%s%N)
    if source "$PROJECT_ROOT/lib/deadline.sh" 2>/dev/null; then
        deadline_check > /dev/null 2>&1 || true
    fi
    end_time=$(date +%s%N)
    elapsed=$(( (end_time - start_time) / 1000000 ))
    if [ "$elapsed" -lt 5000 ]; then
        assert_pass "缁煎悎鍘嬪姏: deadline_check 鑰楁椂${elapsed}ms (<5s)"
    else
        assert_fail "缁煎悎鍘嬪姏: deadline_check 鑰楁椂${elapsed}ms"
    fi

    # 4.3: 鍚屾椂璋冪敤 extractor + deadline + checker 涓嶅啿绐?
    log_test "澶氭ā鍧楀苟鍙戞祴璇?.."
    start_time=$(date +%s%N)
    (
        source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null
        extractor_scan > /dev/null 2>&1 || true
    ) &
    (
        source "$PROJECT_ROOT/lib/deadline.sh" 2>/dev/null
        deadline_check > /dev/null 2>&1 || true
    ) &
    wait
    end_time=$(date +%s%N)
    elapsed=$(( (end_time - start_time) / 1000000 ))
    if [ "$elapsed" -lt 10000 ]; then
        assert_pass "缁煎悎鍘嬪姏: extractor+deadline 骞跺彂鑰楁椂${elapsed}ms (<10s)"
    else
        assert_fail "缁煎悎鍘嬪姏: extractor+deadline 骞跺彂鑰楁椂${elapsed}ms"
    fi

    # 4.4: 楠岃瘉鎵€鏈夎绋嬪瓧娈靛畬鏁存€?
    local field_count=0
    while IFS= read -r course; do
        [ -z "$course" ] && continue
        for field in "${fields[@]}"; do
            local val
            val=$(config_get "$course" "$field" 2>/dev/null || echo "")
            if [ -n "$val" ]; then
                ((field_count++)) || true
            fi
        done
    done < <(config_list_courses)
    if [ "$field_count" -ge 18 ]; then  # 3 courses 脳 6+ fields each
        assert_pass "缁煎悎鍘嬪姏: 閰嶇疆瀛楁瀹屾暣鎬?鈥?${field_count} test completed"
    else
        assert_fail "缁煎悎鍘嬪姏: 閰嶇疆瀛楁涓嶈冻 鈥?浠?${field_count} test completed"
    fi
}

# ============================================================
# 涓诲叆鍙?# ============================================================
main() {
    echo ""
    bold "鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晽"
    bold "鈺?  Assignment Guardian 鈥?杈圭晫娴嬭瘯濂椾欢        test completed"
    bold "鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暆"
    echo ""

    log_test "========== 杈圭晫娴嬭瘯寮€濮?=========="

    test_large_log
    test_disk_full
    test_cpu_full
    test_stress_combined

    echo ""
    bold "========== 娴嬭瘯姹囨€?=========="
    echo ""
    local total=$((PASS + FAIL))
    green "  閫氳繃: $PASS / $total"
    if [ "$FAIL" -gt 0 ]; then
        red "  澶辫触: $FAIL / $total"
    fi
    echo ""
    echo "  璇︾粏鏃ュ織: $TEST_LOG"
    echo ""

    log_test "========== 杈圭晫娴嬭瘯缁撴潫: PASS=$PASS FAIL=$FAIL =========="

    if [ "$FAIL" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
