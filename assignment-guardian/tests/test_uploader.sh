#!/bin/bash
# ============================================================
# test_uploader.sh — uploader模块测试脚本
# 测试内容:
#   - dry-run模式
#   - 目标地址解析
#   - 打包功能
#   - 大文件处理
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."
FIXTURES_DIR="$PROJECT_ROOT/fixtures/linux-test"

# 加载模块
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/uploader.sh"

# 创建测试环境
setup_test_env() {
    echo "准备测试环境..."
    
    # 确保fixtures目录存在
    mkdir -p "$FIXTURES_DIR"
    
    # 创建测试文件
    echo "test content" > "$FIXTURES_DIR/test.txt"
    echo "another file" > "$FIXTURES_DIR/data.txt"
    
    echo "测试环境准备完成"
}

# 执行测试
run_tests() {
    echo ""
    bold "========== Uploader模块测试 =========="
    echo ""
    
    # 测试1: dry-run模式
    echo "测试1: Dry-run模式"
    cd "$FIXTURES_DIR"
    uploader_upload "linux" "true" "true"  # dry_run=true, skip_verify=true
    
    # 测试2: 仅打包功能
    echo ""
    echo "测试2: 仅打包功能"
    uploader_package_only "linux"
    
    # 测试3: 检查打包文件是否创建
    echo ""
    echo "测试3: 验证打包文件"
    local tarball="linux_unknown.tar.gz"
    if [ -f "$FIXTURES_DIR/$tarball" ]; then
        green "  ✓ 打包文件创建成功: $tarball"
        ls -lh "$FIXTURES_DIR/$tarball"
    else
        red "  ✗ 打包文件创建失败"
    fi
    
    # 测试4: 目标地址解析
    echo ""
    echo "测试4: 目标地址解析"
    local target="student@192.168.1.100:/home/teacher/submit/linux/"
    local parsed=$(parse_target "$target")
    echo "  解析结果: $parsed"
    local user=$(echo "$parsed" | cut -d'|' -f1)
    local host=$(echo "$parsed" | cut -d'|' -f2)
    local path=$(echo "$parsed" | cut -d'|' -f3)
    
    if [ "$user" = "student" ] && [ "$host" = "192.168.1.100" ] && [ "$path" = "/home/teacher/submit/linux/" ]; then
        green "  ✓ 目标地址解析正确"
    else
        red "  ✗ 目标地址解析失败"
    fi
    
    # 测试5: 命令检查
    echo ""
    echo "测试5: 依赖命令检查"
    if command_exists "tar"; then
        green "  ✓ tar 命令存在"
    else
        yellow "  ⚠ tar 命令不存在"
    fi
    
    if command_exists "rsync"; then
        green "  ✓ rsync 命令存在（支持断点续传）"
    else
        yellow "  ⚠ rsync 命令不存在（降级为SCP）"
    fi
    
    echo ""
    bold "========== 测试完成 =========="
}

# 主函数
main() {
    setup_test_env
    run_tests
}

main "$@"
