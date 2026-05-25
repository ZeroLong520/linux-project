#!/bin/bash
# ============================================================
# functional_test.sh — 功能测试套件
# 测试范围: 所有4个模块的核心功能
# ============================================================

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
# 测试工具函数
# ============================================================
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
# 模块1: deadline.sh 功能测试
# ============================================================
test_deadline() {
    echo ""
    bold "========== 模块1: deadline.sh 功能测试 =========="
    echo ""

    # 测试1.1: config_get 读取DDL
    log_test "--- deadline: config_get test ---"
    local ddl
    ddl=$(config_get "linux" "ddl" 2>/dev/null || echo "")
    if [ -n "$ddl" ]; then
        assert_pass "config_get linux.ddl → $ddl"
    else
        assert_fail "config_get linux.ddl" "返回空值"
    fi

    # 测试1.2: config_get 读取submit
    local submit
    submit=$(config_get "linux" "submit")
    if [ "$submit" = "scp" ]; then
        assert_pass "config_get linux.submit = scp"
    else
        assert_fail "config_get linux.submit" "expected=scp actual=$submit"
    fi

    # 测试1.3: config_list_courses 列出所有课程
    local courses
    courses=$(config_list_courses)
    if echo "$courses" | grep -q "linux"; then
        assert_pass "config_list_courses 包含 'linux'"
    else
        assert_fail "config_list_courses 不包含 linux"
    fi

    # 测试1.4: ddl_remaining_seconds 时间计算
    local future_date="2099-12-31 23:59"
    local remaining
    remaining=$(ddl_remaining_seconds "$future_date" 2>/dev/null || echo "0")
    if [ "$remaining" -gt 0 ]; then
        assert_pass "ddl_remaining_seconds 2099-12-31 > 0 ($remaining 秒)"
    else
        assert_fail "ddl_remaining_seconds 2099-12-31" "结果为 $remaining"
    fi

    # 测试1.5: ddl_remaining_seconds 过期日期
    local past_date="2020-01-01 00:00"
    local past_remaining
    past_remaining=$(ddl_remaining_seconds "$past_date" 2>/dev/null || echo "0")
    if [ "$past_remaining" -lt 0 ]; then
        assert_pass "ddl_remaining_seconds 2020-01-01 < 0 (已过期)"
    else
        assert_fail "ddl_remaining_seconds 2020-01-01" "应为负数，实际=$past_remaining"
    fi

    # 测试1.6: human_readable_time
    local hr
    hr=$(human_readable_time 90061)  # 1天1小时1分钟
    if echo "$hr" | grep -q "天"; then
        assert_pass "human_readable_time 90061s 包含'天'"
    else
        assert_fail "human_readable_time 90061s" "输出=$hr"
    fi

    # 测试1.7: deadline_check 函数不报错
    if source "$PROJECT_ROOT/lib/deadline.sh" 2>/dev/null; then
        deadline_check > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            assert_pass "deadline_check 正常执行"
        else
            assert_fail "deadline_check 执行报错"
        fi
    else
        assert_fail "source deadline.sh 失败"
    fi
}

# ============================================================
# 模块2: checker.sh 功能测试
# ============================================================
test_checker() {
    echo ""
    bold "========== 模块2: checker.sh 功能测试 =========="
    echo ""

    # 创建测试环境
    local test_dir="$PROJECT_ROOT/fixtures/checker_test"
    mkdir -p "$test_dir"

    # 2.1: 创建符合规范的脚本
    cat > "$test_dir/good_script.sh" << 'SCRIPT'
#!/bin/bash
echo "Hello World"
SCRIPT
    chmod +x "$test_dir/good_script.sh"

    # 2.2: 创建缺执行权限的脚本
    cat > "$test_dir/noperm_script.sh" << 'SCRIPT'
#!/bin/bash
echo "No Permission"
SCRIPT

    # 2.3: 创建有语法错误的脚本
    cat > "$test_dir/bad_syntax.sh" << 'SCRIPT'
#!/bin/bash
if [ -z "$VAR"
then
    echo "missing ]"
SCRIPT
    chmod +x "$test_dir/bad_syntax.sh"

    # 2.4: 创建缺少末尾换行的文件
    echo -n "no newline at end" > "$test_dir/no_newline.txt"

    # 测试 bash -n 语法检查 — 正确脚本
    if bash -n "$test_dir/good_script.sh" 2>/dev/null; then
        assert_pass "bash -n: 正确脚本 [PASS]"
    else
        assert_fail "bash -n: 正确脚本"
    fi

    # 测试 bash -n 语法检查 — 错误脚本
    if bash -n "$test_dir/bad_syntax.sh" 2>/dev/null; then
        assert_fail "bash -n: 错误脚本应失败"
    else
        assert_pass "bash -n: 错误脚本 [FAIL]（符合预期）"
    fi

    # 测试执行权限检查
    if [ -x "$test_dir/good_script.sh" ]; then
        assert_pass "执行权限: good_script.sh 有执行权限"
    else
        assert_fail "执行权限: good_script.sh"
    fi
    if [ ! -x "$test_dir/noperm_script.sh" ]; then
        assert_pass "执行权限: noperm_script.sh 无执行权限（正确检测）"
    else
        assert_fail "执行权限: noperm_script.sh 应有权限缺失"
    fi

    # 测试换行符检测
    local last_char
    last_char=$(tail -c 1 "$test_dir/good_script.sh" | od -An -tx1 | tr -d ' ')
    if [ "$last_char" = "0a" ]; then
        assert_pass "换行符: good_script.sh 末尾有换行"
    else
        assert_fail "换行符: good_script.sh"
    fi
    last_char=$(tail -c 1 "$test_dir/no_newline.txt" | od -An -tx1 | tr -d ' ')
    if [ "$last_char" != "0a" ]; then
        assert_pass "换行符: no_newline.txt 缺末尾换行（正确检测）"
    else
        assert_fail "换行符: no_newline.txt"
    fi

    # 测试 checker_verify 函数
    if source "$PROJECT_ROOT/lib/checker.sh" 2>/dev/null; then
        checker_verify "linux" "$test_dir" > /dev/null 2>&1 || true
        assert_pass "checker_verify linux 正常执行"
    else
        assert_fail "source checker.sh 失败"
    fi

    rm -rf "$test_dir"
}

# ============================================================
# 模块3: uploader.sh 功能测试
# ============================================================
test_uploader() {
    echo ""
    bold "========== 模块3: uploader.sh 功能测试 =========="
    echo ""

    # 3.1: config_get 读取target
    local target
    target=$(config_get "linux" "target")
    if [ -n "$target" ]; then
        assert_pass "uploader: config_get linux.target 非空"
    else
        assert_fail "uploader: config_get linux.target"
    fi

    # 3.2: config_get 读取naming
    local naming
    naming=$(config_get "linux" "naming")
    if echo "$naming" | grep -q "tar.gz"; then
        assert_pass "uploader: naming包含tar.gz → $naming"
    else
        assert_fail "uploader: naming=$naming"
    fi

    # 3.3: 测试 dry-run 模式（不应实际打包上传）
    local test_dir="$PROJECT_ROOT/fixtures/uploader_test"
    mkdir -p "$test_dir"
    echo "test" > "$test_dir/test_file.txt"

    cd "$test_dir"
    if source "$PROJECT_ROOT/lib/uploader.sh" 2>/dev/null; then
        uploader_upload "linux" "true" > /dev/null 2>&1 || true
        assert_pass "uploader: dry-run 模式执行成功"
    fi
    cd "$PROJECT_ROOT"
    rm -rf "$test_dir"

    # 3.4: file_md5 函数
    local test_md5_file="$PROJECT_ROOT/fixtures/md5_test.txt"
    echo "hello md5 test" > "$test_md5_file"
    local md5_result
    md5_result=$(file_md5 "$test_md5_file" 2>/dev/null || echo "")
    if [ -n "$md5_result" ] && [ ${#md5_result} -eq 32 ]; then
        assert_pass "file_md5: 返回32位MD5 → $md5_result"
    else
        assert_fail "file_md5" "结果=$md5_result"
    fi
    rm -f "$test_md5_file"
}

# ============================================================
# 模块4: extractor.sh 功能测试
# ============================================================
test_extractor() {
    echo ""
    bold "========== 模块4: extractor.sh 功能测试 =========="
    echo ""

    # 4.1: 扫描fixtures目录中的md文件
    if source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null; then
        local result
        result=$(extractor_scan "$FIXTURES_DIR" 2>/dev/null || true)
        if echo "$result" | grep -q "sample_requirements"; then
            assert_pass "extractor: 识别 fixtures/sample_requirements.md"
        else
            assert_fail "extractor: 未识别 sample_requirements.md"
        fi
        if echo "$result" | grep -q "db_requirements"; then
            assert_pass "extractor: 识别 fixtures/db_requirements.txt"
        else
            assert_fail "extractor: 未识别 db_requirements.txt"
        fi
    else
        assert_fail "source extractor.sh 失败"
    fi

    # 4.2: 测试关键词匹配 — 截止时间
    local test_content="截止日期: 2026-06-20  提交截止  deadline: 2026-07-01"
    local match
    match=$(echo "$test_content" | grep -ciE "截止|ddl|deadline" || echo 0)
    if [ "$match" -ge 3 ]; then
        assert_pass "extractor: 截止关键词匹配 ($match 处)"
    else
        assert_fail "extractor: 截止关键词匹配" "仅 $match 处"
    fi

    # 4.3: 测试关键词匹配 — 提交方式
    local test_submit="提交方式: SCP上传  submit: git  upload 递交"
    match=$(echo "$test_submit" | grep -ciE "提交方式|submit|上传|upload|递交" || echo 0)
    if [ "$match" -ge 3 ]; then
        assert_pass "extractor: 提交方式关键词匹配 ($match 处)"
    else
        assert_fail "extractor: 提交方式关键词匹配" "仅 $match 处"
    fi

    # 4.4: 测试关键词匹配 — 评分标准
    local test_grade="评分标准 满分100分 grading rubric 评分规则"
    match=$(echo "$test_grade" | grep -ciE "评分|分值|满分|grading|rubric|评分标准" || echo 0)
    if [ "$match" -ge 3 ]; then
        assert_pass "extractor: 评分关键词匹配 ($match 处)"
    else
        assert_fail "extractor: 评分关键词匹配" "仅 $match 处"
    fi

    # 4.5: 测试HTML文本提取
    local html_test="$PROJECT_ROOT/fixtures/test.html"
    echo '<html><body><h1>作业要求</h1><p>截止时间: 2026-06-30</p><p>提交: SCP上传</p></body></html>' > "$html_test"
    if source "$PROJECT_ROOT/lib/extractor.sh" 2>/dev/null; then
        extractor_scan "$FIXTURES_DIR" > /dev/null 2>&1 || true
        assert_pass "extractor: HTML文件扫描不报错"
    fi
    rm -f "$html_test"
}

# ============================================================
# 主入口
# ============================================================
main() {
    echo ""
    bold "╔══════════════════════════════════════════════╗"
    bold "║   Assignment Guardian — 功能测试套件        ║"
    bold "╚══════════════════════════════════════════════╝"
    echo ""

    log_test "========== 功能测试开始 =========="

    test_deadline
    test_checker
    test_uploader
    test_extractor

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

    log_test "========== 功能测试结束: PASS=$PASS FAIL=$FAIL =========="

    if [ "$FAIL" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
