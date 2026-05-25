#!/bin/bash
# ============================================================
# extractor.sh — 模块4: 作业需求提取器 (增强版)
# 功能:
#   - 扫描指定目录中的多种文件格式 (txt/md/rst/pdf/docx/html/csv/json/xml/log)
#   - 加权关键词匹配提取作业关键信息
#   - 支持中文同义词扩展，提升匹配准确度
#   - 输出汇总报告
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ============================================================
# 加权关键词库 (权重 1-5，越高越重要)
# ============================================================
declare -A KEYWORD_WEIGHTS

# 截止时间相关 — 权重 5（最关键）
KEYWORD_WEIGHTS["deadline"]="5|截止|ddl|deadline|due date|截至|截止日期|截止时间|提交截止|due_date"

# 提交方式相关 — 权重 4
KEYWORD_WEIGHTS["submit"]="4|提交方式|submit|上传|upload|提交到|发送至|递交|投递|submit to"

# 命名规范相关 — 权重 4
KEYWORD_WEIGHTS["naming"]="4|命名|naming|文件名|文件命名|命名规则|命名格式|命名规范|naming convention"

# 格式要求 — 权重 3
KEYWORD_WEIGHTS["format"]="3|格式|format|要求|规范|标准|编码|encoding|字符集|charset"

# 评分标准 — 权重 3
KEYWORD_WEIGHTS["grading"]="3|评分|分值|满分|grading|评分标准|评分细则|打分|rubric|总分|评分规则"

# 必交文件 — 权重 4
KEYWORD_WEIGHTS["required"]="4|必交|必须提交|required|mandatory|必需|必要文件|必交文件|required files"

# 禁止事项 — 权重 2
KEYWORD_WEIGHTS["forbidden"]="2|禁止|不得|不允许|forbidden|禁止使用|严禁|杜绝"

# 引用/参考 — 权重 1
KEYWORD_WEIGHTS["reference"]="1|参考资料|引用|references|参考文献|推荐阅读|阅读材料"

# 实验环境 — 权重 2
KEYWORD_WEIGHTS["environment"]="2|环境|environment|平台|操作系统|OS|运行环境|编译环境"

# ============================================================
# 从文本中按加权关键词提取匹配行
# ============================================================
extract_weighted_lines() {
    local text="$1"
    local results=""

    for category in "${!KEYWORD_WEIGHTS[@]}"; do
        local entry="${KEYWORD_WEIGHTS[$category]}"
        local weight="${entry%%|*}"
        local patterns="${entry#*|}"

        local grep_pattern=""
        IFS='|' read -ra PATTERNS <<< "$patterns"
        for p in "${PATTERNS[@]}"; do
            if [ -z "$grep_pattern" ]; then
                grep_pattern="$p"
            else
                grep_pattern="$grep_pattern|$p"
            fi
        done

        local matches
        matches=$(echo "$text" | grep -niE "$grep_pattern" 2>/dev/null | head -5)
        if [ -n "$matches" ]; then
            while IFS= read -r line; do
                results+="$weight|$category|$line"$'\n'
            done <<< "$matches"
        fi
    done

    if [ -n "$results" ]; then
        echo "$results" | sort -t'|' -k1,1nr
    fi
}

# ============================================================
# 将 .docx 转换为纯文本
# ============================================================
docx_to_text() {
    local docx_file="$1"

    if command_exists python3; then
        python3 -c "
import sys
try:
    from docx import Document
    doc = Document('$docx_file')
    for p in doc.paragraphs:
        print(p.text)
except ImportError:
    import zipfile, xml.etree.ElementTree as ET
    try:
        z = zipfile.ZipFile('$docx_file')
        xml_content = z.read('word/document.xml')
        root = ET.fromstring(xml_content)
        for p in root.iter('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}p'):
            texts = [t.text for t in p.iter('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}t') if t.text]
            if texts:
                print(''.join(texts))
        z.close()
    except Exception as e:
        sys.exit(1)
" 2>/dev/null && return 0
    fi

    return 1
}

# ============================================================
# 将 .html 转换为纯文本
# ============================================================
html_to_text() {
    local html_file="$1"
    sed -e 's/<[^>]*>//g' \
        -e 's/&nbsp;/ /g' \
        -e 's/&amp;/\&/g' \
        -e 's/&lt;/</g' \
        -e 's/&gt;/>/g' \
        -e 's/&quot;/"/g' \
        -e '/^[[:space:]]*$/d' \
        "$html_file" 2>/dev/null
}

# ============================================================
# CSV/JSON/XML 转换
# ============================================================
csv_to_text() {
    cat "$1" 2>/dev/null | sed 's/,/ | /g'
}

json_to_text() {
    if command_exists python3; then
        python3 -c "
import json, sys
with open('$1', 'r', encoding='utf-8', errors='ignore') as f:
    data = json.load(f)
def flatten(obj, prefix=''):
    if isinstance(obj, dict):
        for k, v in obj.items():
            flatten(v, f'{prefix}{k}: ')
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            flatten(v, f'{prefix}[{i}] ')
    else:
        print(f'{prefix}{obj}')
flatten(data)
" 2>/dev/null || cat "$1" 2>/dev/null
    else
        cat "$1" 2>/dev/null
    fi
}

xml_to_text() {
    sed -e 's/<[^>]*>//g' \
        -e '/^[[:space:]]*$/d' \
        "$1" 2>/dev/null
}

# ============================================================
# 安全读取文件（处理编码问题）
# ============================================================
safe_read_file() {
    local file="$1"

    if iconv -f UTF-8 -t UTF-8 "$file" >/dev/null 2>&1; then
        cat "$file" 2>/dev/null
    elif command_exists iconv; then
        iconv -f GBK -t UTF-8 "$file" 2>/dev/null || cat "$file" 2>/dev/null
    else
        cat "$file" 2>/dev/null
    fi
}

# ============================================================
# 扫描单个文件
# ============================================================
scan_file() {
    local file="$1"
    local ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    local label="$2"
    local content=""

    case "$ext" in
        docx)
            if ! command_exists python3; then
                yellow "  跳过 $file (需要 python3 解析 docx)"
                return
            fi
            content=$(docx_to_text "$file")
            ;;
        html|htm)
            content=$(html_to_text "$file")
            ;;
        csv)
            content=$(csv_to_text "$file")
            ;;
        json)
            content=$(json_to_text "$file")
            ;;
        xml)
            content=$(xml_to_text "$file")
            ;;
        txt|md|rst|log|conf|cfg|ini|yaml|yml|sh|py|c|h|cpp|java)
            content=$(safe_read_file "$file")
            ;;
        *)
            content=$(safe_read_file "$file" 2>/dev/null || true)
            ;;
    esac

    if [ -z "$content" ]; then
        return
    fi

    echo "  ——— $(basename "$file") $label ———"

    local weighted_results
    weighted_results=$(extract_weighted_lines "$content")

    if [ -n "$weighted_results" ]; then
        local prev_category=""
        echo "$weighted_results" | while IFS='|' read -r weight category line; do
            if [ "$category" != "$prev_category" ]; then
                local cat_label
                case "$category" in
                    deadline)    cat_label="[截止时间]" ;;
                    submit)      cat_label="[提交方式]" ;;
                    naming)      cat_label="[命名规范]" ;;
                    format)      cat_label="[格式要求]" ;;
                    grading)     cat_label="[评分标准]" ;;
                    required)    cat_label="[必交文件]" ;;
                    forbidden)   cat_label="[禁止事项]" ;;
                    reference)   cat_label="[参考资料]" ;;
                    environment) cat_label="[实验环境]" ;;
                    *)           cat_label="[$category]" ;;
                esac
                echo "    $cat_label (权重:$weight)"
                prev_category="$category"
            fi
            echo "      $line"
        done
    else
        yellow "    未匹配到作业需求关键词"
    fi
    echo ""
}

# ============================================================
# 主函数: 从目录中提取作业需求
# ============================================================
extractor_scan() {
    local scan_dir="${1:-.}"

    echo ""
    bold "========== 作业需求提取器 (增强版) =========="
    echo "  扫描目录: $(realpath "$scan_dir")"
    echo ""

    local file_count=0

    # 文本文件
    while IFS= read -r -d '' txtfile; do
        scan_file "$txtfile" ""
        ((file_count++)) || true
    done < <(find "$scan_dir" -maxdepth 1 \( -name "*.txt" -o -name "*.md" -o -name "*.rst" -o -name "*.log" -o -name "*.conf" -o -name "*.cfg" -o -name "*.ini" -o -name "*.yaml" -o -name "*.yml" \) -print0 2>/dev/null)

    # HTML
    while IFS= read -r -d '' htmlfile; do
        scan_file "$htmlfile" "(HTML)"
        ((file_count++)) || true
    done < <(find "$scan_dir" -maxdepth 1 \( -name "*.html" -o -name "*.htm" \) -print0 2>/dev/null)

    # CSV/JSON/XML
    while IFS= read -r -d '' datafile; do
        scan_file "$datafile" "(DATA)"
        ((file_count++)) || true
    done < <(find "$scan_dir" -maxdepth 1 \( -name "*.csv" -o -name "*.json" -o -name "*.xml" \) -print0 2>/dev/null)

    # DOCX
    while IFS= read -r -d '' docxfile; do
        if command_exists python3; then
            scan_file "$docxfile" "(DOCX)"
            ((file_count++)) || true
        else
            yellow "  跳过 $(basename "$docxfile") (需要 python3)"
        fi
    done < <(find "$scan_dir" -maxdepth 1 -name "*.docx" -print0 2>/dev/null)

    # PDF
    if command_exists pdftotext; then
        while IFS= read -r -d '' pdffile; do
            local pdf_text
            pdf_text=$(pdftotext "$pdffile" - 2>/dev/null)
            if [ -n "$pdf_text" ]; then
                echo "  ——— $(basename "$pdffile") (PDF) ———"
                local wr
                wr=$(extract_weighted_lines "$pdf_text")
                if [ -n "$wr" ]; then
                    local prev=""
                    echo "$wr" | while IFS='|' read -r w c l; do
                        if [ "$c" != "$prev" ]; then
                            echo "    [$c] (权重:$w)"
                            prev="$c"
                        fi
                        echo "      $l"
                    done
                fi
                echo ""
            fi
            ((file_count++)) || true
        done < <(find "$scan_dir" -maxdepth 1 -name "*.pdf" -print0 2>/dev/null)
    else
        yellow "  提示: 安装 poppler-utils (pdftotext) 可支持 PDF 提取"
    fi

    echo "  ——— 提取汇总 ———"
    echo "  扫描文件数: $file_count"
    if [ -f "$LOG_FILE" ]; then
        local kw_hits
        kw_hits=$(grep -c "extractor:" "$LOG_FILE" 2>/dev/null || echo 0)
        echo "  历史提取次数: $kw_hits"
    fi
    echo ""
    green "  ✅ 提取完成"
    log_info "extractor: scanned $scan_dir"
}
