#!/bin/bash
# ============================================================
# guardian.sh — 课程作业管理系统主入口
# ============================================================

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/checker.sh"
source "$SCRIPT_DIR/lib/uploader.sh"

show_help() {
    echo "课程作业管理系统"
    echo "Usage: $0 <command> [options] <course>"
    echo ""
    echo "Commands:"
    echo "  verify <course>        执行作业规范自检"
    echo "  package <course>       仅打包作业"
    echo "  upload <course>        打包并上传作业"
    echo "  config <course>        查看课程配置"
    echo "  help                   显示帮助信息"
    echo ""
    echo "Options:"
    echo "  --dry                  试运行模式（不实际上传）"
    echo "  --skip-verify          跳过前置规范检查"
    echo ""
    echo "Example:"
    echo "  $0 verify linux"
    echo "  $0 upload --dry linux"
    echo "  $0 upload --skip-verify linux"
}

main() {
    local command="$1"
    local course=""
    local dry_run="false"
    local skip_verify="false"
    
    shift
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry)
                dry_run="true"
                shift
                ;;
            --skip-verify)
                skip_verify="true"
                shift
                ;;
            *)
                course="$1"
                shift
                ;;
        esac
    done
    
    case "$command" in
        verify)
            if [ -z "$course" ]; then
                red "错误: 请指定课程名称"
                show_help
                exit 1
            fi
            checker_verify "$course" "."
            ;;
            
        package)
            if [ -z "$course" ]; then
                red "错误: 请指定课程名称"
                show_help
                exit 1
            fi
            uploader_package_only "$course"
            ;;
            
        upload)
            if [ -z "$course" ]; then
                red "错误: 请指定课程名称"
                show_help
                exit 1
            fi
            uploader_upload "$course" "$dry_run" "$skip_verify"
            ;;
            
        config)
            if [ -z "$course" ]; then
                red "错误: 请指定课程名称"
                show_help
                exit 1
            fi
            config_show "$course"
            ;;
            
        help)
            show_help
            ;;
            
        *)
            red "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
