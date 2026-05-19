#!/bin/bash
# ============================================================
# guardian.sh — 作业守护者 主入口
# 用法:
#   ./guardian.sh check              扫描作业截止时间
#   ./guardian.sh check --all         显示所有作业（含远期）
#   ./guardian.sh verify <课程>       对指定课程执行规范自检
#   ./guardian.sh verify --all        对所有课程执行规范自检
#   ./guardian.sh upload <课程>       打包并上传作业
#   ./guardian.sh upload --dry <课程> 试运行模式
#   ./guardian.sh extract [目录]      提取作业需求关键字
#   ./guardian.sh status              总览面板
#   ./guardian.sh help                显示帮助
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载模块库
# 加载模块库（先 common，之后用 PROJECT_ROOT 定位）
source "$SCRIPT_DIR/lib/common.sh"
source "$PROJECT_ROOT/lib/deadline.sh"
source "$PROJECT_ROOT/lib/checker.sh"
source "$PROJECT_ROOT/lib/uploader.sh"
source "$PROJECT_ROOT/lib/extractor.sh"

# -------------------- 帮助信息 --------------------
show_help() {
    echo "用法: ./guardian.sh <命令> [参数]"
    echo ""
    echo "命令:"
    echo "  check              扫描作业截止时间（默认显示7天内）"
    echo "  check --all         显示所有作业（含远期）"
    echo "  verify <课程>       对指定课程执行规范自检"
    echo "  verify --all        对所有课程执行规范自检"
    echo "  upload <课程>       打包并上传指定课程作业"
    echo "  upload --dry <课程> 试运行模式（只展示，不上传）"
    echo "  extract [目录]      从目录中提取作业需求关键字"
    echo "  status              显示所有作业状态总览"
    echo "  help                显示此帮助"
    echo ""
    echo "示例:"
    echo "  ./guardian.sh check"
    echo "  ./guardian.sh verify linux"
    echo "  ./guardian.sh upload --dry linux"
    echo "  ./guardian.sh extract ~/课件/"
}

# -------------------- 状态总览 --------------------
show_status() {
    echo ""
    bold "========== 作业守护者 — 状态总览 =========="
    echo ""
    echo "  配置文件: $CONFIG_FILE"
    echo "  日志文件: $LOG_FILE"
    echo "  课程数量: $(config_list_courses | wc -l)"
    echo ""
    echo "  课程列表:"
    while IFS= read -r course; do
        local ddl submit
        ddl=$(config_get "$course" "ddl")
        submit=$(config_get "$course" "submit")
        printf "    %-10s  DDL: %-16s  提交: %s\n" "$course" "$ddl" "$submit"
    done < <(config_list_courses)
    echo ""
}

# -------------------- 主入口 --------------------
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        check)
            if [ "${2:-}" = "--all" ]; then
                deadline_check "true"
            else
                deadline_check "false"
            fi
            ;;
        verify)
            if [ "${2:-}" = "--all" ]; then
                checker_verify_all "."
            elif [ -n "${2:-}" ]; then
                checker_verify "${2}" "."
            else
                red "错误: 请指定课程名，或使用 --all 检查所有"
                echo "示例: ./guardian.sh verify linux"
                exit 1
            fi
            ;;
        upload)
            if [ "${2:-}" = "--dry" ]; then
                uploader_upload "${3:-}" "true"
            elif [ -n "${2:-}" ]; then
                uploader_upload "${2}" "false"
            else
                red "错误: 请指定课程名"
                echo "示例: ./guardian.sh upload linux"
                exit 1
            fi
            ;;
        extract)
            extractor_scan "${2:-.}"
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            red "未知命令: $cmd"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
