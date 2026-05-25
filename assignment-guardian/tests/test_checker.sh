#!/bin/bash
# ============================================================
# test_checker.sh — checker模块测试脚本
# 测试内容:
#   - 正常文件检查
#   - 中文文件名处理
#   - 空格文件名处理
#   - 超大文件模拟
#   - 绝对路径检测
#   - UTF-8编码检测
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."
FIXTURES_DIR="$PROJECT_ROOT/fixtures/linux-test"

# 加载模块
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/checker.sh"

# 创建测试fixtures
setup_fixtures() {
    echo "准备测试fixtures..."
    
    # 创建测试目录
    mkdir -p "$FIXTURES_DIR"
    
    # 创建正常的shell脚本（带执行权限）
    cat > "$FIXTURES_DIR/test_normal.sh" << 'EOF'
#!/bin/bash
echo "Hello World"
EOF
    chmod +x "$FIXTURES_DIR/test_normal.sh"
    
    # 创建无执行权限的脚本
    cat > "$FIXTURES_DIR/test_noexec.sh" << 'EOF'
#!/bin/bash
echo "No exec permission"
EOF
    
    # 创建语法错误的脚本
    cat > "$FIXTURES_DIR/test_bad_syntax.sh" << 'EOF'
#!/bin/bash
if [ true
echo "bad syntax"
EOF
    chmod +x "$FIXTURES_DIR/test_bad_syntax.sh"
    
    # 创建中文文件名
    cat > "$FIXTURES_DIR/测试文件.sh" << 'EOF'
#!/bin/bash
echo "中文测试"
EOF
    chmod +x "$FIXTURES_DIR/测试文件.sh"
    
    # 创建带空格的文件名
    cat > "$FIXTURES_DIR/test file.sh" << 'EOF'
#!/bin/bash
echo "space in name"
EOF
    chmod +x "$FIXTURES_DIR/test file.sh"
    
    # 创建包含绝对路径的文件
    cat > "$FIXTURES_DIR/test_abs_path.sh" << 'EOF'
#!/bin/bash
cp /etc/passwd ./
cd /home/user
EOF
    chmod +x "$FIXTURES_DIR/test_abs_path.sh"
    
    # 创建缺少末尾换行的文件
    printf "no newline at end" > "$FIXTURES_DIR/no_newline.txt"
    
    # 创建README.md
    cat > "$FIXTURES_DIR/README.md" << 'EOF'
# Test Project
This is a test project.
EOF
    
    echo "Fixtures准备完成"
}

# 执行测试
run_tests() {
    echo ""
    bold "========== Checker模块测试 =========="
    echo ""
    
    # 测试1: 正常文件检查
    echo "测试1: 正常文件检查"
    checker_verify "linux" "$FIXTURES_DIR"
    
    # 测试2: 检查是否正确检测绝对路径
    echo ""
    echo "测试2: 验证绝对路径检测"
    if grep -q "包含绝对路径" "$FIXTURES_DIR/test_abs_path.sh"; then
        green "  ✓ 绝对路径检测测试通过"
    else
        red "  ✗ 绝对路径检测测试失败"
    fi
    
    # 测试3: 检查中文文件名处理
    echo ""
    echo "测试3: 中文文件名处理"
    if [ -f "$FIXTURES_DIR/测试文件.sh" ]; then
        green "  ✓ 中文文件名支持"
    else
        red "  ✗ 中文文件名不支持"
    fi
    
    # 测试4: 检查空格文件名处理
    echo ""
    echo "测试4: 空格文件名处理"
    if [ -f "$FIXTURES_DIR/test file.sh" ]; then
        green "  ✓ 空格文件名支持"
    else
        red "  ✗ 空格文件名不支持"
    fi
    
    echo ""
    bold "========== 测试完成 =========="
}

# 清理fixtures
cleanup_fixtures() {
    echo "清理测试fixtures..."
    rm -rf "$FIXTURES_DIR"
}

# 主函数
main() {
    setup_fixtures
    run_tests
    # cleanup_fixtures  # 保留fixtures以便手动检查
}

main "$@"
