#!/bin/bash
# ============================================================
# extractor.sh — 模块4: 作业需求提取器 (配置驱动版)
# 功能:
#   - 直接解析 config/courses.conf 中的结构化作业配置
#   - 展示截止时间、提交方式、必交文件、命名规范、评分标准、
#     格式要求、禁止事项等完整信息
#   - 按课程维度输出汇总报告
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ============================================================
# 分类标签中文映射
# ============================================================
declare -A CATEGORY_LABELS
CATEGORY_LABELS["ddl"]="[截止时间]"
CATEGORY_LABELS["submit"]="[提交方式]"
CATEGORY_LABELS["target"]="[提交目标]"
CATEGORY_LABELS["required_files"]="[必交文件]"
CATEGORY_LABELS["naming"]="[打包命名]"
CATEGORY_LABELS["notes"]="[补充说明]"
CATEGORY_LABELS["grading"]="[评分标准]"
CATEGORY_LABELS["format"]="[格式要求]"
CATEGORY_LABELS["forbidden"]="[禁止事项]"

# 字段显示排序
readonly DISPLAY_ORDER=(
    "ddl"
    "submit"
    "target"
    "required_files"
    "naming"
    "grading"
    "format"
    "forbidden"
    "notes"
)

# ============================================================
# 解析 courses.conf 并展示单个课程的完整需求
# ============================================================
extract_course_info() {
    local course="$1"

    echo "  -------- 课程: $course --------"
    echo ""

    local has_any=false

    for field in "${DISPLAY_ORDER[@]}"; do
        local value
        value=$(config_get "$course" "$field" 2>/dev/null || true)
        if [ -n "$value" ]; then
            local label="${CATEGORY_LABELS[$field]:-[$field]}"
            printf "    %-16s %s\n" "$label" "$value"
            has_any=true
        fi
    done

    if [ "$has_any" = false ]; then
        yellow "    (无配置信息)"
    fi

    echo ""
}

# ============================================================
# 主函数: 从 courses.conf 提取所有课程作业需求
# ============================================================
extractor_scan() {
    echo ""
    bold "========== 作业需求提取器 (配置驱动版) =========="
    echo "  配置来源: $CONFIG_FILE"
    echo ""

    local course_count=0

    while IFS= read -r course; do
        [ -z "$course" ] && continue
        extract_course_info "$course"
        ((course_count++)) || true
    done < <(config_list_courses)

    echo "  -------- 提取汇总 --------"
    echo "  课程数量: $course_count"
    echo "  配置字段: ${#DISPLAY_ORDER[@]} 项"
    echo ""
    green "  ✓ 提取完成"
    log_info "extractor: scanned $course_count courses from $CONFIG_FILE"
}
