#!/bin/bash
# ============================================================
# extractor.sh — 模块4: 作业需求提取器
# 功能:
#   - 扫描指定目录中的文本文件和PDF
#   - 关键词匹配提取作业关键信息
#   - 输出汇总报告
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# 关键词模式（可扩展）
KEYWORDS=(
    "截止|ddl|deadline|due date"
    "提交方式|submit|上传|upload"
    "命名|naming|文件名"
    "格式|format|要求"
    "评分|分值|满分|grading"
)

# 从目录中提取作业需求
extractor_scan() {
    local scan_dir="${1:-.}"

    echo ""
    bold "========== 作业需求提取 =========="
    echo "  扫描目录: $(realpath "$scan_dir")"
    echo ""

    # 扫描文本文件
    while IFS= read -r -d '' txtfile; do
        echo "  ── $(basename "$txtfile") ──"

        for pattern_group in "${KEYWORDS[@]}"; do
            local matches
            matches=$(grep -niE "$pattern_group" "$txtfile" 2>/dev/null | head -5)
            if [ -n "$matches" ]; then
                echo "$matches" | while IFS= read -r line; do
                    echo "    $line"
                done
            fi
        done

        echo ""
    done < <(find "$scan_dir" -maxdepth 1 \( -name "*.txt" -o -name "*.md" -o -name "*.rst" \) -print0 2>/dev/null)

    # 尝试处理PDF
    if command_exists pdftotext; then
        while IFS= read -r -d '' pdffile; do
            echo "  ── $(basename "$pdffile") (PDF) ──"

            local pdf_text
            pdf_text=$(pdftotext "$pdffile" - 2>/dev/null)

            for pattern_group in "${KEYWORDS[@]}"; do
                local matches
                matches=$(echo "$pdf_text" | grep -niE "$pattern_group" | head -3)
                if [ -n "$matches" ]; then
                    echo "$matches" | while IFS= read -r line; do
                        echo "    $line"
                    done
                fi
            done

            echo ""
        done < <(find "$scan_dir" -maxdepth 1 -name "*.pdf" -print0 2>/dev/null)
    else
        yellow "  提示: 安装 poppler-utils (pdftotext) 可支持PDF提取"
    fi

    echo ""
    green "  提取完成"
    log_info "extractor: scanned $scan_dir"
}
