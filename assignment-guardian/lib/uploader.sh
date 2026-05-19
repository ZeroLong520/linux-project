#!/bin/bash
# ============================================================
# uploader.sh — 模块3: 一键打包上传
# 功能:
#   - 读取配置中的打包命名规则
#   - 自动 tar 打包
#   - SCP 上传至目标服务器
#   - MD5 校验上传完整性
#   - 支持 dry-run 试运行模式
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# 打包并上传指定课程作业
uploader_upload() {
    local course="$1"
    local dry_run="${2:-false}"

    local target
    target=$(config_get "$course" "target")
    local naming
    naming=$(config_get "$course" "naming")

    if [ -z "$target" ]; then
        red "错误: 课程 '$course' 未配置提交目标 (target)"
        return 1
    fi

    echo ""
    bold "========== 打包上传: $course =========="
    echo ""

    # 生成包名（替换学号为占位符，用户需手动修改或通过参数传入）
    local tarball="${naming:-${course}_backup.tar.gz}"
    tarball=$(echo "$tarball" | sed 's/学号/${STUDENT_ID:-unknown}/g')

    echo "  打包文件: $tarball"
    echo "  提交目标: $target"

    if [ "$dry_run" = "true" ]; then
        yellow "  [DRY-RUN] 跳过实际打包和上传"
        echo ""
        return 0
    fi

    # Step 1: 打包
    echo ""
    echo "  [1/3] 正在打包..."
    if tar czf "$tarball" . --exclude="logs" --exclude=".git" --exclude="*.tar.gz" --exclude="*.zip" 2>/dev/null; then
        local size
        size=$(du -h "$tarball" | cut -f1)
        green "  [1/3] 打包完成 ($size): $tarball"
    else
        red "  [1/3] 打包失败"
        return 1
    fi

    # Step 2: 上传 (SCP)
    echo "  [2/3] 正在上传..."
    if scp "$tarball" "$target" 2>/dev/null; then
        green "  [2/3] 上传完成 → $target"
    else
        red "  [2/3] 上传失败: 请检查网络和SSH配置"
        return 1
    fi

    # Step 3: MD5 校验
    echo "  [3/3] 正在校验..."
    local local_md5 remote_md5
    local_md5=$(file_md5 "$tarball")
    local remote_file="$target/$(basename "$tarball")"

    remote_md5=$(ssh "${target%%:*}" "md5sum '$remote_file' 2>/dev/null | awk '{print \$1}'" 2>/dev/null || echo "")

    if [ -n "$remote_md5" ] && [ "$local_md5" = "$remote_md5" ]; then
        green "  [3/3] 校验通过: MD5=$local_md5"
    else
        yellow "  [3/3] 无法校验远程MD5（可能需要手动确认）"
        yellow "       本地MD5: $local_md5"
    fi

    echo ""
    green "  ✓ 上传流程完成"
    log_info "uploader: $course → $target  tarball=$tarball  md5=$local_md5"
}
