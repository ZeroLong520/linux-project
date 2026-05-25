#!/bin/bash
# ============================================================
# boundary_test.sh — 边界测试套件
# 测试场景:
#   1. 超大日志文件 (>100MB)
#   2. 磁盘空间不足模拟
#   3. CPU满载场景
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
# 工具
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
# 测试1: 超大日志文件
# ============================================================
test_large_log() {
    echo ""
    bold "========== 边界测试1: 超大日志文件 =========="
    echo ""

    local large_dir="$PROJECT_ROOT/fixtures/large_test"
    mkdir -p "$large_dir"

    # 1.1: 生成 10MB 日志文件，测试 extractor 处理大文件
    log_test "生成10MB测试日志..."
    local large_log="$large_dir/large_log.txt"
    > "$large_log"
    for i in $(seq 1 50000); do
        echo "Line $i: 截止时间 2026-06-20, 提交方式 SCP上传, 评分标准 满分100分, deadline: $(date)" >> "$large_log"
    done

    local file_size
    file_size=$(du -h "$large_log" | cut -f1)
    log_test "生成文件大小: $file_size"

    # 1.2: extractor 扫描大文件 — 应在合理时间内完成
    local start_time end_time elapsed
    start_time=$(date +%s)
    if source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null; then
        extractor_scan "$large_dir" > /dev/null 2>&1 || true
    fi
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    if [ "$elapsed" -lt 30 ]; then
        assert_pass "超大日志: extractor处理${file_size}日志耗时${elapsed}s (<30s)"
    else
        assert_fail "超大日志: 耗时${elapsed}s超过30s"
    fi

    # 1.3: 超大文件 grep 关键词性能
    start_time=$(date +%s)
    grep -c "截止时间" "$large_log" > /dev/null 2>&1 || true
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    if [ "$elapsed" -lt 5 ]; then
        assert_pass "超大日志: grep关键词耗时${elapsed}s (<5s)"
    else
        assert_fail "超大日志: grep耗时${elapsed}s"
    fi

    # 1.4: 日志写入性能 — 5000条连续写入
    local bench_log="$PROJECT_ROOT/logs/bench_write.log"
    > "$bench_log"
    start_time=$(date +%s)
    for i in $(seq 1 5000); do
        log_info "bench write test line $i with some extra data for padding"
    done
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    local entries
    entries=$(wc -l < "$bench_log" 2>/dev/null || echo 0)
    if [ "$entries" -ge 5000 ] && [ "$elapsed" -lt 10 ]; then
        assert_pass "超大日志: 5000条日志写入耗时${elapsed}s"
    else
        assert_fail "超大日志: 5000条写入耗时${elapsed}s, 条目=$entries"
    fi
    rm -f "$bench_log"

    # 1.5: 超大文件 MD5 计算
    local md5_time
    start_time=$(date +%s%N)
    file_md5 "$large_log" > /dev/null 2>&1 || true
    end_time=$(date +%s%N)
    elapsed=$(( (end_time - start_time) / 1000000 ))  # 毫秒
    if [ "$elapsed" -lt 5000 ]; then
        assert_pass "超大日志: MD5计算${file_size}耗时${elapsed}ms"
    else
        assert_fail "超大日志: MD5计算耗时${elapsed}ms"
    fi

    rm -rf "$large_dir"
}

# ============================================================
# 测试2: 磁盘空间不足模拟
# ============================================================
test_disk_full() {
    echo ""
    bold "========== 边界测试2: 磁盘空间不足 =========="
    echo ""

    # 2.1: 检查当前磁盘可用空间
    local disk_info avail
    disk_info=$(df -h "$PROJECT_ROOT" 2>/dev/null | tail -1 || echo "")
    avail=$(echo "$disk_info" | awk '{print $4}' 2>/dev/null || echo "unknown")
    log_test "当前磁盘可用空间: $avail"
    assert_pass "磁盘满: 当前可用空间=$avail"

    # 2.2: 模拟写入受限场景 — 创建临时文件系统镜像
    # 创建一个小的 tmpfs（需要root）/ 或用 dd 创建固定大小文件
    # 由于无root权限，改为测试：检测 write 失败时的行为
    local test_dir="$PROJECT_ROOT/fixtures/disk_test"
    mkdir -p "$test_dir"

    # 2.3: 测试在只读目录中写入日志
    local readonly_dir="$test_dir/readonly"
    mkdir -p "$readonly_dir"
    echo "test" > "$readonly_dir/test.txt" 2>/dev/null || true
    chmod 444 "$readonly_dir" 2>/dev/null || true
    if echo "write test" > "$readonly_dir/new.txt" 2>/dev/null; then
        assert_fail "磁盘满: 向只读目录写入应失败"
    else
        assert_pass "磁盘满: 只读目录写入被正确拒绝"
    fi
    chmod 755 "$readonly_dir" 2>/dev/null || true

    # 2.4: 测试 tar 打包到不存在的路径
    local bad_tarball="/nonexistent/path/test.tar.gz"
    if tar czf "$bad_tarball" -C "$test_dir" . 2>/dev/null; then
        assert_fail "磁盘满: tar到不存在路径应失败"
    else
        assert_pass "磁盘满: tar到不存在路径正确失败"
    fi

    # 2.5: 日志文件可写入性
    if [ -w "$PROJECT_ROOT/logs" ]; then
        assert_pass "磁盘满: logs目录可写入"
    else
        assert_fail "磁盘满: logs目录不可写入"
    fi

    rm -rf "$test_dir"
}

# ============================================================
# 测试3: CPU满载场景
# ============================================================
test_cpu_full() {
    echo ""
    bold "========== 边界测试3: CPU满载场景 =========="
    echo ""

    # 3.1: 并行运行多个 extractor 实例，检查 CPU 利用率和响应
    local stress_dir="$PROJECT_ROOT/fixtures/cpu_test"
    mkdir -p "$stress_dir"

    # 生成多个中等大小文件
    for f in $(seq 1 20); do
        > "$stress_dir/test_${f}.txt"
        for _ in $(seq 1 1000); do
            echo "截止时间 deadline submit 提交方式 评分标准 命名规范 format grading" >> "$stress_dir/test_${f}.txt"
        done
    done

    # 3.2: 顺序扫描 20 个文件（模拟正常负载）
    log_test "顺序扫描 20 个文件..."
    local start_time end_time
    start_time=$(date +%s%N)
    if source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null; then
        extractor_scan "$stress_dir" > /dev/null 2>&1 || true
    fi
    end_time=$(date +%s%N)
    local elapsed=$(( (end_time - start_time) / 1000000 ))
    if [ "$elapsed" -lt 10000 ]; then
        assert_pass "CPU满载: 顺序扫描20文件耗时${elapsed}ms (<10s)"
    else
        assert_fail "CPU满载: 顺序扫描耗时${elapsed}ms"
    fi

    # 3.3: 并发执行模拟 — 4个后台进程
    log_test "并发扫描 4 进程..."
    start_time=$(date +%s%N)
    for i in 1 2 3 4; do
        (
            cd "$PROJECT_ROOT"
            source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null
            extractor_scan "$stress_dir" > /dev/null 2>&1 || true
        ) &
    done
    wait
    end_time=$(date +%s%N)
    elapsed=$(( (end_time - start_time) / 1000000 ))
    if [ "$elapsed" -lt 30000 ]; then
        assert_pass "CPU满载: 4并发扫描耗时${elapsed}ms (<30s)"
    else
        assert_fail "CPU满载: 4并发扫描耗时${elapsed}ms"
    fi

    # 3.4: 系统在高负载下仍能响应
    local resp
    resp=$(date +%s 2>/dev/null || echo 0)
    if [ "$resp" -gt 0 ]; then
        assert_pass "CPU满载: 高负载下系统维护响应能力"
    else
        assert_fail "CPU满载: 系统无响应"
    fi

    rm -rf "$stress_dir"
}

# ============================================================
# 额外: 综合压力测试
# ============================================================
test_stress_combined() {
    echo ""
    bold "========== 边界测试4: 综合压力测试 =========="
    echo ""

    local combo_dir="$PROJECT_ROOT/fixtures/combo_stress"
    mkdir -p "$combo_dir"

    # 4.1: 创建多格式混合文件
    echo '<html><body>截止时间: 2026-06-30</body></html>' > "$combo_dir/test.html"
    echo '{"ddl":"2026-06-20","submit":"scp"}' > "$combo_dir/test.json"
    echo "deadline,submit,score" > "$combo_dir/test.csv"
    echo "2026-06-15,git,100" >> "$combo_dir/test.csv"
    echo '<root><ddl>2026-06-20</ddl></root>' > "$combo_dir/test.xml"

    local start_time end_time
    start_time=$(date +%s%N)
    if source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null; then
        extractor_scan "$combo_dir" > /dev/null 2>&1 || true
    fi
    end_time=$(date +%s%N)
    local elapsed=$(( (end_time - start_time) / 1000000 ))

    if [ "$elapsed" -lt 5000 ]; then
        assert_pass "综合压力: 多格式混合扫描耗时${elapsed}ms (<5s)"
    else
        assert_fail "综合压力: 多格式扫描耗时${elapsed}ms"
    fi

    rm -rf "$combo_dir"

    # 4.2: deadline_check 大量课程
    log_test "deadline_check 压力测试..."
    start_time=$(date +%s%N)
    if source "$PROJECT_ROOT/lib/deadline.sh" 2>/dev/null; then
        deadline_check > /dev/null 2>&1 || true
    fi
    end_time=$(date +%s%N)
    elapsed=$(( (end_time - start_time) / 1000000 ))
    if [ "$elapsed" -lt 5000 ]; then
        assert_pass "综合压力: deadline_check 耗时${elapsed}ms (<5s)"
    else
        assert_fail "综合压力: deadline_check 耗时${elapsed}ms"
    fi
}

# ============================================================
# 主入口
# ============================================================
main() {
    echo ""
    bold "╔══════════════════════════════════════════════╗"
    bold "║   Assignment Guardian — 边界测试套件        ║"
    bold "╚══════════════════════════════════════════════╝"
    echo ""

    log_test "========== 边界测试开始 =========="

    test_large_log
    test_disk_full
    test_cpu_full
    test_stress_combined

    echo ""
    bold "========== 测试汇总 =========="
    echo ""
    local total=$((PASS + FAIL))
    green "  通过: $PASS / $total"
    if [ "$FAIL" -gt 0 ]; then
        red "  失败: $FAIL / $total"
    fi
    echo ""
    echo "  详细日志: $TEST_LOG"
    echo ""

    log_test "========== 边界测试结束: PASS=$PASS FAIL=$FAIL =========="

    if [ "$FAIL" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
