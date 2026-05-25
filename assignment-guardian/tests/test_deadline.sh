#!/bin/bash
# ============================================================
# test_deadline.sh — deadline 模块测试
# 用法: ./test_deadline.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_CONFIG_DIR="$PROJECT_DIR/tests/testdata"
PASS=0
FAIL=0

# 引入模块
source "$PROJECT_DIR/lib/common.sh"
source "$PROJECT_DIR/lib/deadline.sh"

say()   { echo "  $*"; }
check() {
    local desc="$1"; local expected="$2"; local actual="$3"
    if [ "$actual" = "$expected" ]; then
        green "  [PASS] $desc"
        PASS=$((PASS + 1))
    else
        red "  [FAIL] $desc"
        say "    期望: $expected"
        say "    实际: $actual"
        FAIL=$((FAIL + 1))
    fi
}

# -------------------- 准备测试配置 --------------------
setup_test_config() {
    mkdir -p "$TEST_CONFIG_DIR"

    cat > "$TEST_CONFIG_DIR/test_courses.conf" << 'EOF'
# 测试用的课程配置
[math]
ddl = 2024-01-01 00:00
submit = scp

[english]
ddl = 2030-12-31 23:59
submit = git

[noddl]
submit = local
EOF
}
setup_test_config

# 临时替换 CONFIG_FILE
REAL_CONFIG="$CONFIG_FILE"
CONFIG_FILE="$TEST_CONFIG_DIR/test_courses.conf"

# -------------------- 测试开始 --------------------
echo ""
bold "========== deadline 模块测试 =========="
echo ""

# 测试1: config_list_courses 列出所有课程
say "测试1: 列出所有课程"
courses=$(config_list_courses)
check "应包含 math, english, noddl" \
    "$(echo -e 'math\nenglish\nnoddl')" \
    "$courses"

# 测试2: config_get 读取ddl
say "测试2: 读取DDL字段"
check "math 的 ddl" \
    "2024-01-01 00:00" \
    "$(config_get math ddl)"

# 测试3: 读取不存在的字段
say "测试3: 读取不存在的字段"
check "english 的 missing_field 应返回空" \
    "" \
    "$(config_get english missing_field)"

# 测试4: human_readable_time
say "测试4: 时间格式化"
check "86400秒 = 1天" \
    "1天" \
    "$(human_readable_time 86400)"
check "90061秒 = 1天1小时1分钟" \
    "1天1小时1分钟" \
    "$(human_readable_time 90061)"
check "59秒 = 不到1分钟" \
    "不到1分钟" \
    "$(human_readable_time 59)"

# 测试5: ddl_remaining_seconds — 已过期
say "测试5: 过期DDL返回负数"
remaining=$(ddl_remaining_seconds "2024-01-01 00:00")
check "math 已过期，remaining < 0" "true" \
    "$([ "$remaining" -lt 0 ] && echo true || echo false)"

# 测试6: ddl_remaining_seconds — 未来DDL
say "测试6: 未来DDL返回正数"
remaining=$(ddl_remaining_seconds "2030-12-31 23:59")
check "english 在未来，remaining > 0" "true" \
    "$([ "$remaining" -gt 0 ] && echo true || echo false)"

# 测试7: 无效日期格式
say "测试7: 无效日期格式"
remaining=$(ddl_remaining_seconds "invalid-date" 2>/dev/null || echo "FAIL")
check "无效日期返回 FAIL 兜底" "FAIL" "$remaining"

# 测试8: deadline_check 函数能正常调用
say "测试8: deadline_check 能正常执行"
output=$(deadline_check 2>&1)
if echo "$output" | grep -q "共"; then
    green "  [PASS] deadline_check 正常输出"
    PASS=$((PASS + 1))
else
    red "  [FAIL] deadline_check 无预期输出"
    ((FAIL++))
fi

# 测试9: 缺少ddl的课程不计入总数
say "测试9: noddl 课程不计入统计（因缺少ddl字段）"
count=$(echo "$output" | grep "共" | grep -o '[0-9]*')
check "应显示 2 门课程（noddl被跳过）" "2" "$count"

# -------------------- 测试10: 边界 — 空配置 --------------------
say "测试10: 空配置文件处理"
cat > "$TEST_CONFIG_DIR/empty.conf" << 'EOF'
# 完全没有课程的配置
EOF
CONFIG_FILE="$TEST_CONFIG_DIR/empty.conf"
output=$(deadline_check 2>&1)
if echo "$output" | grep -q "暂无"; then
    green "  [PASS] 空配置给出提示"
    PASS=$((PASS + 1))
else
    red "  [FAIL] 空配置未给出提示"
    ((FAIL++))
fi

# -------------------- 清理 --------------------
CONFIG_FILE="$REAL_CONFIG"
rm -rf "$TEST_CONFIG_DIR"

# -------------------- 汇总 --------------------
echo ""
echo "-----------------------------------"
green "  通过: $PASS"
[ "$FAIL" -gt 0 ] && red "  失败: $FAIL"
echo "  总计: $((PASS + FAIL))"
echo ""

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
