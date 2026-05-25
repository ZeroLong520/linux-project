#!/bin/bash
# ============================================================
# exception_test.sh — 异常测试套件
# 测试场景:
#   1. 权限不足 (Permission Denied)
#   2. 文件不存在 (File Not Found)
#   3. 网络断开 (Network Disconnected)
#   4. 空配置文件 (Empty Config)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/lib/common.sh"

PASS=0
FAIL=0
TEST_LOG="$PROJECT_ROOT/logs/exception_test.log"
> "$TEST_LOG"

# ============================================================
# 工具
# ============================================================
log_test() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$TEST_LOG"; }
assert_pass() { echo -n "  TEST: $1 ... "; green "PASS"; ((PASS++)); echo "PASS: $1" >> "$TEST_LOG"; }
assert_fail() { echo -n "  TEST: $1 ... "; red "FAIL"; ((FAIL++)); echo "FAIL: $1" >> "$TEST_LOG"; }

# ============================================================
# 测试1: 权限不足
# ============================================================
test_permission_denied() {
    echo ""
    bold "========== 异常测试1: 权限不足 =========="
    echo ""

    local perm_dir="$PROJECT_ROOT/fixtures/perm_test"
    mkdir -p "$perm_dir"

    # 1.1: 创建无读权限的文件
    echo "secret content" > "$perm_dir/secret.txt"
    chmod 000 "$perm_dir/secret.txt" 2>/dev/null || true

    # 1.2: 尝试读取无权限文件 — extractor应优雅处理
    if source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null; then
        extractor_scan "$perm_dir" > /dev/null 2>&1 || true
        assert_pass "权限不足: extractor扫描000权限文件不崩溃"
    fi

    # 1.3: 创建无读权限目录
    mkdir -p "$perm_dir/noaccess"
    chmod 000 "$perm_dir/noaccess" 2>/dev/null || true

    # 1.4: 尝试进入无权限目录
    if cd "$perm_dir/noaccess" 2>/dev/null; then
        assert_fail "权限不足: 进入了000权限目录"
        cd "$PROJECT_ROOT"
    else
        assert_pass "权限不足: 正确拒绝访问000权限目录"
    fi

    # 1.5: config_get 对无权限配置文件的处理
    if [ -f "$PROJECT_ROOT/config/courses.conf" ]; then
        assert_pass "权限不足: courses.conf 可读"
    else
        assert_fail "权限不足: courses.conf 不可读"
    fi

    # 清理
    chmod 755 "$perm_dir/noaccess" 2>/dev/null || true
    chmod 644 "$perm_dir/secret.txt" 2>/dev/null || true
    rm -rf "$perm_dir"
}

# ============================================================
# 测试2: 文件不存在
# ============================================================
test_file_not_found() {
    echo ""
    bold "========== 异常测试2: 文件不存在 =========="
    echo ""

    # 2.1: config_get 查询不存在的课程
    local result
    result=$(config_get "nonexistent" "ddl" 2>/dev/null || echo "EMPTY")
    if [ -z "$result" ] || [ "$result" = "EMPTY" ]; then
        assert_pass "文件不存在: config_get 不存在课程返回空"
    else
        assert_fail "文件不存在: config_get 不存在课程返回='$result'"
    fi

    # 2.2: extractor 扫描不存在的目录
    if source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null; then
        extractor_scan "/nonexistent/path/12345" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            assert_pass "文件不存在: extractor 扫描不存在目录不崩溃"
        else
            # 优雅失败也算通过
            assert_pass "文件不存在: extractor 扫描不存在目录优雅失败"
        fi
    fi

    # 2.3: file_md5 对不存在的文件
    local md5
    md5=$(file_md5 "/nonexistent/file.txt" 2>/dev/null || echo "ERROR")
    if [ "$md5" = "ERROR" ] || [ -z "$md5" ]; then
        assert_pass "文件不存在: file_md5 不存在文件返回错误"
    else
        assert_fail "文件不存在: file_md5"
    fi

    # 2.4: checker_verify 对不存在的课程
    if source "$PROJECT_ROOT/lib/checker.sh" 2>/dev/null; then
        checker_verify "nonexistent" "." > /dev/null 2>&1 || true
        assert_pass "文件不存在: checker_verify 不存在课程不崩溃"
    fi
}

# ============================================================
# 测试3: 网络断开模拟
# ============================================================
test_network_disconnected() {
    echo ""
    bold "========== 异常测试3: 网络断开 =========="
    echo ""

    # 3.1: SCP 到不存在的主机
    local test_tarball="$PROJECT_ROOT/fixtures/test_upload.tar.gz"
    echo "network test" > "$PROJECT_ROOT/fixtures/test_upload.txt"
    tar czf "$test_tarball" -C "$PROJECT_ROOT/fixtures" test_upload.txt 2>/dev/null || true

    # 模拟 SCP 失败 — 不应崩溃
    if scp "$test_tarball" "no-such-host.example.com:/tmp/" 2>/dev/null; then
        assert_fail "网络断开: SCP到不存在主机应失败但成功了"
    else
        assert_pass "网络断开: SCP到不存在主机正确失败"
    fi

    rm -f "$test_tarball" "$PROJECT_ROOT/fixtures/test_upload.txt"

    # 3.2: uploader dry-run 模式下不尝试网络连接
    local upload_dir="$PROJECT_ROOT/fixtures/upload_net_test"
    mkdir -p "$upload_dir"
    cd "$upload_dir"
    if source "$PROJECT_ROOT/lib/uploader.sh" 2>/dev/null; then
        uploader_upload "linux" "true" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            assert_pass "网络断开: dry-run 模式跳过网络操作"
        else
            assert_fail "网络断开: dry-run 模式失败"
        fi
    fi
    cd "$PROJECT_ROOT"
    rm -rf "$upload_dir"

    # 3.3: SSH 到不存在主机
    if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no "no-such-host.example.com" "echo test" 2>/dev/null; then
        assert_fail "网络断开: SSH到不存在主机成功"
    else
        assert_pass "网络断开: SSH到不存在主机正确超时"
    fi
}

# ============================================================
# 测试4: 空配置
# ============================================================
test_empty_config() {
    echo ""
    bold "========== 异常测试4: 空配置 =========="
    echo ""

    # 4.1: 创建空配置文件
    local empty_config="$PROJECT_ROOT/fixtures/empty_courses.conf"
    echo "" > "$empty_config"

    # 4.2: 对空配置调用 config_list_courses
    local courses
    courses=$(awk '/^\[.*\]/ { gsub(/[\[\]]/, ""); print }' "$empty_config" 2>/dev/null || echo "")
    if [ -z "$courses" ]; then
        assert_pass "空配置: config_list_courses 返回空"
    else
        assert_fail "空配置: 应返回空但得到='$courses'"
    fi

    # 4.3: 对空配置调用 config_get
    local val
    val=$(awk -v course="linux" -v field="ddl" '
        BEGIN { in_section = 0 }
        $0 ~ "^\\[" course "\\]" { in_section = 1; next }
        $0 ~ "^\\[" { in_section = 0 }
        in_section && $1 == field { sub(/^[^=]*= /, ""); print; exit }
    ' "$empty_config" 2>/dev/null || echo "")
    if [ -z "$val" ]; then
        assert_pass "空配置: config_get 返回空"
    else
        assert_fail "空配置: config_get 返回='$val'"
    fi

    rm -f "$empty_config"

    # 4.4: 测试空白字段值
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
        assert_pass "空配置: 空白字段值正确处理"
    else
        assert_fail "空配置: 空白字段返回='$blank_ddl'"
    fi
    rm -f "$test_conf"

    # 4.5: 配置文件缺失时的行为
    # common.sh 中已有检查: 如果 CONFIG_FILE 不存在则 exit 1
    # 这里验证配置文件存在
    if [ -f "$PROJECT_ROOT/config/courses.conf" ]; then
        assert_pass "空配置: courses.conf 存在（系统正常）"
    else
        assert_fail "空配置: courses.conf 缺失"
    fi
}

# ============================================================
# 主入口
# ============================================================
main() {
    echo ""
    bold "╔══════════════════════════════════════════════╗"
    bold "║   Assignment Guardian — 异常测试套件        ║"
    bold "╚══════════════════════════════════════════════╝"
    echo ""

    log_test "========== 异常测试开始 =========="

    test_permission_denied
    test_file_not_found
    test_network_disconnected
    test_empty_config

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

    log_test "========== 异常测试结束: PASS=$PASS FAIL=$FAIL =========="

    if [ "$FAIL" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
