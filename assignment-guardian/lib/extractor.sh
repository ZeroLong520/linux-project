#!/bin/bash
# ============================================================
# extractor.sh - Module 4: Assignment Requirements Extractor
# Features:
#   - Read assignment requirements from fixtures/ folder
#   - Each fixture file may contain multiple courses (split by headers)
#   - Replace/update corresponding course content in courses.conf
#   - Auto-detect and add new courses not yet in courses.conf
#   - Display DDL, submit method, required files, naming convention,
#     grading criteria, format requirements, forbidden items
#   - Output summary per course, each course displayed only once
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

FIXTURES_DIR="$PROJECT_ROOT/fixtures"

# ============================================================
declare -A CATEGORY_LABELS
CATEGORY_LABELS["ddl"]="[DDL]"
CATEGORY_LABELS["submit"]="[Submit]"
CATEGORY_LABELS["target"]="[Target]"
CATEGORY_LABELS["required_files"]="[Required Files]"
CATEGORY_LABELS["naming"]="[Naming]"
CATEGORY_LABELS["notes"]="[Notes]"
CATEGORY_LABELS["grading"]="[Grading]"
CATEGORY_LABELS["format"]="[Format]"
CATEGORY_LABELS["forbidden"]="[Forbidden]"

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

readonly ALL_FIELDS=(
    "ddl"
    "submit"
    "target"
    "required_files"
    "naming"
    "notes"
    "grading"
    "format"
    "forbidden"
)

# ============================================================
declare -A FIXTURE_DDL
declare -A FIXTURE_SUBMIT
declare -A FIXTURE_TARGET
declare -A FIXTURE_REQUIRED_FILES
declare -A FIXTURE_NAMING
declare -A FIXTURE_NOTES
declare -A FIXTURE_GRADING
declare -A FIXTURE_FORMAT
declare -A FIXTURE_FORBIDDEN

FIXTURE_COURSES=()
declare -A FIXTURE_SEEN

# ============================================================
# Map course display name to English tag
# ============================================================
name_to_tag() {
    local name="$1"

    # Known course mappings
    if echo "$name" | grep -qi '数据库原理\|数据库'; then
        echo "db"; return
    fi
    if echo "$name" | grep -qi 'Linux\|Shell'; then
        echo "linux"; return
    fi
    if echo "$name" | grep -qi '数据结构'; then
        echo "ds"; return
    fi
    if echo "$name" | grep -qi '跨平台'; then
        echo "crossplatform"; return
    fi

    # Unknown course: keep the name as-is (Chinese characters work with awk parser)
    # Remove leading/trailing whitespace
    local tag
    tag=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -z "$tag" ]; then
        tag="unknown"
    fi
    echo "$tag"
}

# ============================================================
extract_after_label() {
    local content="$1"
    local keyword="$2"
    local line
    line=$(echo "$content" | grep -iE "$keyword" | head -1)
    if [ -z "$line" ]; then
        echo ""; return
    fi
    local val
    val=$(echo "$line" | sed 's/.*[：:][[:space:]]*//' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    echo "$val"
}

# ============================================================
extract_ddl() {
    local content="$1"
    echo "$content" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}' | head -1
}

extract_submit() {
    local content="$1"
    local submit_line
    submit_line=$(echo "$content" | grep -iE 'submit|SCP|Git|提交方式' | head -1)

    if [ -z "$submit_line" ]; then
        echo ""; return
    fi

    if echo "$submit_line" | grep -qiE '\bscp\b|SCP'; then
        echo "scp"
    elif echo "$submit_line" | grep -qiE '\bgit\b|Git'; then
        echo "git"
    elif echo "$submit_line" | grep -qiE '\blocal\b'; then
        echo "local"
    else
        local raw
        raw=$(echo "$submit_line" | sed 's/.*[：:][[:space:]]*//' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        echo "$raw"
    fi
}

extract_target() {
    local content="$1"
    local submit_val="$2"

    local target_line
    target_line=$(echo "$content" | grep -iE 'target|目标|server|服务器' | grep -v 'grading\|评分' | head -1)
    if [ -n "$target_line" ]; then
        local t
        t=$(echo "$target_line" | grep -oE '[a-zA-Z0-9_.-]+@[a-zA-Z0-9_.-]+:[^[:space:]]+' | head -1)
        if [ -n "$t" ]; then echo "$t"; return; fi
        t=$(echo "$target_line" | grep -oE '/[^[:space:]]+' | head -1)
        if [ -n "$t" ]; then echo "$t"; return; fi
    fi

    local submit_line
    submit_line=$(echo "$content" | grep -iE 'submit|Git push|SCP|提交方式' | head -1)

    if [ "$submit_val" = "git" ] && [ -n "$submit_line" ]; then
        local git_url
        git_url=$(echo "$submit_line" | grep -oE 'git@[^[:space:]]+' | head -1)
        if [ -z "$git_url" ]; then
            git_url=$(echo "$submit_line" | grep -oE 'github\.com[:/][^[:space:]]+' | head -1)
            [ -n "$git_url" ] && echo "git@$git_url" && return
        else
            echo "$git_url"; return
        fi
    fi

    if [ "$submit_val" = "scp" ]; then
        local scp_target
        scp_target=$(echo "$content" | grep -oE '[a-zA-Z0-9_.-]+@[a-zA-Z0-9_.-]+:[^[:space:]]+' | head -1)
        [ -n "$scp_target" ] && echo "$scp_target" && return
    fi

    echo ""
}

extract_required_files() {
    local content="$1"

    local line
    line=$(echo "$content" | grep -iE 'required|必交文件' | head -1)
    if [ -n "$line" ]; then
        local val
        val=$(echo "$line" | sed 's/.*[：:][[:space:]]*//' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$val" ] && [ "$val" != "$line" ]; then
            echo "$val"; return
        fi
    fi

    local section
    section=$(echo "$content" | sed -n '/## Required Files\|## 必交文件/,/## /p' | grep '^- ')
    if [ -n "$section" ]; then
        local files=""
        while IFS= read -r bullet; do
            local f
            f=$(echo "$bullet" | sed 's/^-[[:space:]]*//' | sed 's/[（(][^）)]*[）)]//g' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -n "$f" ]; then
                if [ -n "$files" ]; then
                    files="$files, $f"
                else
                    files="$f"
                fi
            fi
        done <<< "$section"
        echo "$files"; return
    fi

    echo ""
}

extract_naming() {
    local content="$1"

    local naming_line
    naming_line=$(echo "$content" | grep -iE 'naming|命名' | grep '学号' | head -1)

    if [ -z "$naming_line" ]; then
        naming_line=$(echo "$content" | grep -iE 'naming|命名' | head -1)
    fi

    if [ -n "$naming_line" ]; then
        local name_val
        name_val=$(echo "$naming_line" | grep -oE '[a-zA-Z0-9_-]+学号[^[:space:],;]*\.(tar\.gz|zip|tgz|tar)' | head -1)
        if [ -n "$name_val" ]; then echo "$name_val"; return; fi

        name_val=$(echo "$naming_line" | sed 's/.*[：:][[:space:]]*//' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$name_val" ] && [ "$name_val" != "$naming_line" ]; then
            echo "$name_val"; return
        fi
    fi

    echo ""
}

extract_notes() {
    local content="$1"
    local parts=()

    local naming_sec
    naming_sec=$(echo "$content" | sed -n '/## Naming\|## 命名规范/,/## /p' | grep -v '^##' | grep -v '^[[:space:]]*$' | grep -v 'naming\|命名')
    if [ -n "$naming_sec" ]; then
        local n
        n=$(echo "$naming_sec" | grep '^- ' | sed 's/^-[[:space:]]*//' | tr '\n' ';' | sed 's/;$//')
        [ -n "$n" ] && parts+=("$n")
    fi

    local env_sec
    env_sec=$(echo "$content" | sed -n '/## Environment\|## 实验环境/,/## /p' | grep -v '^##' | grep -v '^[[:space:]]*$')
    if [ -n "$env_sec" ]; then
        local e
        e=$(echo "$env_sec" | grep '^- ' | sed 's/^-[[:space:]]*//' | tr '\n' ';' | sed 's/;$//')
        [ -n "$e" ] && parts+=("$e")
    fi

    if [ ${#parts[@]} -eq 0 ]; then
        local extra
        extra=$(echo "$content" | grep -iE '逾期\|overdue\|补充说明' | head -1)
        if [ -n "$extra" ]; then
            extra=$(echo "$extra" | sed 's/^[-*#[:space:]]*//' | tr -d '\r')
            echo "$extra"; return
        fi
    fi

    local IFS=';'
    echo "${parts[*]}"
}

extract_grading() {
    local content="$1"

    local section
    section=$(echo "$content" | sed -n '/## Grading\|## 评分标准/,/## /p' | grep '^- ')
    if [ -n "$section" ]; then
        local grades
        grades=$(echo "$section" | sed 's/^-[[:space:]]*//' | tr '\n' ',' | sed 's/,$//;s/,[[:space:]]*$//')
        echo "$grades"; return
    fi

    local line
    line=$(echo "$content" | grep -iE 'grading|评分标准' | head -1)
    if [ -n "$line" ]; then
        local val
        val=$(echo "$line" | sed 's/.*[：:][[:space:]]*//' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -n "$val" ] && [ "$val" != "$line" ] && echo "$val" && return
    fi

    echo ""
}

extract_format() {
    local content="$1"

    local section
    section=$(echo "$content" | sed -n '/## Format\|## 格式要求/,/## /p' | grep '^- ')
    if [ -n "$section" ]; then
        local fmt
        fmt=$(echo "$section" | sed 's/^-[[:space:]]*//' | tr '\n' ',' | sed 's/,$//;s/,[[:space:]]*$//')
        echo "$fmt"; return
    fi

    extract_after_label "$content" 'format|格式要求'
}

extract_forbidden() {
    local content="$1"

    local section
    section=$(echo "$content" | sed -n '/## Forbidden\|## 禁止事项/,/## /p' | grep '^- ')
    if [ -n "$section" ]; then
        local fb
        fb=$(echo "$section" | sed 's/^-[[:space:]]*//' | tr '\n' ',' | sed 's/,$//;s/,[[:space:]]*$//')
        echo "$fb"; return
    fi

    local line
    line=$(echo "$content" | grep -iE 'forbidden|禁止|严禁' | head -1)
    if [ -n "$line" ]; then
        local val
        val=$(echo "$line" | sed 's/.*[：:][[:space:]]*//' | tr -d '\r')
        if [ -n "$val" ] && [ "$val" != "$line" ]; then
            echo "$val"; return
        fi
        echo "$line" | sed 's/^[-*#[:space:]]*//' | tr -d '\r'
        return
    fi

    echo ""
}

# ============================================================
# Process a single course section (content already split from file)
# ============================================================
_process_course_section() {
    local section="$1"
    local course_name="$2"
    local source_file="$3"

    local course_tag
    course_tag=$(name_to_tag "$course_name")

    # Dedup: first occurrence wins globally
    if [ "${FIXTURE_SEEN[$course_tag]:-}" = "1" ]; then
        log_info "extractor: skip duplicate course '$course_tag' ($course_name) from $source_file"
        return
    fi
    FIXTURE_SEEN[$course_tag]=1
    FIXTURE_COURSES+=("$course_tag")

    local ddl_val submit_val target_val req_val naming_val notes_val grading_val fmt_val fb_val

    ddl_val=$(extract_ddl "$section")
    submit_val=$(extract_submit "$section")
    target_val=$(extract_target "$section" "$submit_val")
    req_val=$(extract_required_files "$section")
    naming_val=$(extract_naming "$section")
    notes_val=$(extract_notes "$section")
    grading_val=$(extract_grading "$section")
    fmt_val=$(extract_format "$section")
    fb_val=$(extract_forbidden "$section")

    FIXTURE_DDL[$course_tag]="$ddl_val"
    FIXTURE_SUBMIT[$course_tag]="$submit_val"
    FIXTURE_TARGET[$course_tag]="$target_val"
    FIXTURE_REQUIRED_FILES[$course_tag]="$req_val"
    FIXTURE_NAMING[$course_tag]="$naming_val"
    FIXTURE_NOTES[$course_tag]="$notes_val"
    FIXTURE_GRADING[$course_tag]="$grading_val"
    FIXTURE_FORMAT[$course_tag]="$fmt_val"
    FIXTURE_FORBIDDEN[$course_tag]="$fb_val"

    log_info "extractor: parsed course '$course_tag' ($course_name) from $source_file"
}

# ============================================================
# Parse a single fixture file (may contain multiple courses)
# Splits by "^# ... — 作业要求" / "^# ... — 课程作业要求" headers
# ============================================================
parse_fixture_file() {
    local file="$1"
    local content
    content=$(cat "$file" 2>/dev/null || true)
    [ -z "$content" ] && { log_warn "extractor: empty fixture: $file"; return; }

    # Find all header lines matching: # COURSE_NAME — 作业要求 / 课程作业要求
    local header_data
    header_data=$(echo "$content" | grep -nE '^# .+ — (作业要求|课程作业要求)' || true)

    if [ -z "$header_data" ]; then
        # No course headers found — treat entire file as one course
        local fallback_name
        fallback_name=$(basename "$file" | sed 's/\.[^.]*$//')
        _process_course_section "$content" "$fallback_name" "$file"
        return
    fi

    # Build arrays of line numbers and course names
    local header_lines=()
    local header_names=()
    while IFS=: read -r line_num rest; do
        header_lines+=("$line_num")
        local name
        name=$(echo "$rest" | sed 's/^# //;s/ — .*//' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        header_names+=("$name")
    done <<< "$header_data"

    local total_lines
    total_lines=$(echo "$content" | wc -l)

    # Process each section
    local count=${#header_lines[@]}
    local i
    for ((i = 0; i < count; i++)); do
        local start=${header_lines[$i]}
        local name="${header_names[$i]}"

        local end
        if ((i + 1 < count)); then
            end=$((${header_lines[$i+1]} - 1))
        else
            end=$total_lines
        fi

        # Extract section: from start line to end line
        local section
        section=$(echo "$content" | sed -n "${start},${end}p")

        _process_course_section "$section" "$name" "$file"
    done
}

# ============================================================
parse_all_fixtures() {
    [ ! -d "$FIXTURES_DIR" ] && { log_warn "extractor: fixtures dir not found"; return; }

    local fixture_files=()
    while IFS= read -r -d '' f; do
        fixture_files+=("$f")
    done < <(find "$FIXTURES_DIR" -maxdepth 1 -type f \( -name "*.txt" -o -name "*.md" \) -print0 2>/dev/null || true)

    for f in "${fixture_files[@]}"; do
        parse_fixture_file "$f"
    done
}

# ============================================================
get_fixture_field() {
    local course="$1"
    local field="$2"
    local val=""

    case "$field" in
        ddl)            val="${FIXTURE_DDL[$course]:-}" ;;
        submit)         val="${FIXTURE_SUBMIT[$course]:-}" ;;
        target)         val="${FIXTURE_TARGET[$course]:-}" ;;
        required_files) val="${FIXTURE_REQUIRED_FILES[$course]:-}" ;;
        naming)         val="${FIXTURE_NAMING[$course]:-}" ;;
        notes)          val="${FIXTURE_NOTES[$course]:-}" ;;
        grading)        val="${FIXTURE_GRADING[$course]:-}" ;;
        format)         val="${FIXTURE_FORMAT[$course]:-}" ;;
        forbidden)      val="${FIXTURE_FORBIDDEN[$course]:-}" ;;
    esac

    if [ -z "$val" ]; then
        echo "NONE"
    else
        echo "$val"
    fi
}

# ============================================================
update_courses_conf() {
    local bak="$CONFIG_FILE.bak"
    cp "$CONFIG_FILE" "$bak" 2>/dev/null || true

    # Read all data from ORIGINAL config BEFORE redirect truncates it
    local existing_courses=()
    while IFS= read -r c; do
        [ -z "$c" ] && continue
        existing_courses+=("$c")
    done < <(config_list_courses)

    local header
    header=$(sed -n '1,/^\[/p' "$CONFIG_FILE" | head -n -1)

    # Pre-read original field values for courses NOT in fixtures
    declare -A ORIG_DDL ORIG_SUBMIT ORIG_TARGET ORIG_REQUIRED_FILES
    declare -A ORIG_NAMING ORIG_NOTES ORIG_GRADING ORIG_FORMAT ORIG_FORBIDDEN

    for course in "${existing_courses[@]}"; do
        [ "${FIXTURE_SEEN[$course]:-}" = "1" ] && continue
        ORIG_DDL[$course]=$(config_get "$course" "ddl" 2>/dev/null || true)
        ORIG_SUBMIT[$course]=$(config_get "$course" "submit" 2>/dev/null || true)
        ORIG_TARGET[$course]=$(config_get "$course" "target" 2>/dev/null || true)
        ORIG_REQUIRED_FILES[$course]=$(config_get "$course" "required_files" 2>/dev/null || true)
        ORIG_NAMING[$course]=$(config_get "$course" "naming" 2>/dev/null || true)
        ORIG_NOTES[$course]=$(config_get "$course" "notes" 2>/dev/null || true)
        ORIG_GRADING[$course]=$(config_get "$course" "grading" 2>/dev/null || true)
        ORIG_FORMAT[$course]=$(config_get "$course" "format" 2>/dev/null || true)
        ORIG_FORBIDDEN[$course]=$(config_get "$course" "forbidden" 2>/dev/null || true)
    done

    # Now write the new config
    {
        echo "$header"
        echo ""

        for course in "${FIXTURE_COURSES[@]}"; do
            echo "# ====== ${course} (from fixtures) ======"
            echo "[$course]"
            for field in "${ALL_FIELDS[@]}"; do
                echo "$field = $(get_fixture_field "$course" "$field")"
            done
            echo ""
        done

        for course in "${existing_courses[@]}"; do
            [ "${FIXTURE_SEEN[$course]:-}" = "1" ] && continue

            echo "# ====== $course ======"
            echo "[$course]"
            echo "ddl = ${ORIG_DDL[$course]:-NONE}"
            echo "submit = ${ORIG_SUBMIT[$course]:-NONE}"
            echo "target = ${ORIG_TARGET[$course]:-NONE}"
            echo "required_files = ${ORIG_REQUIRED_FILES[$course]:-NONE}"
            echo "naming = ${ORIG_NAMING[$course]:-NONE}"
            echo "notes = ${ORIG_NOTES[$course]:-NONE}"
            echo "grading = ${ORIG_GRADING[$course]:-NONE}"
            echo "format = ${ORIG_FORMAT[$course]:-NONE}"
            echo "forbidden = ${ORIG_FORBIDDEN[$course]:-NONE}"
            echo ""
        done
    } > "$CONFIG_FILE"

    log_info "extractor: updated $CONFIG_FILE"
}

# ============================================================
extract_course_info() {
    local course="$1"

    echo "  -------- Course: $course --------"
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
        yellow "    (No config info)"
    fi

    echo ""
}

# ============================================================
extractor_scan() {
    echo ""
    bold "========== Assignment Requirements Extractor =========="
    echo "  Fixtures source: $FIXTURES_DIR"
    echo "  Config file:     $CONFIG_FILE"
    echo ""

    blue "  [1/3] Scanning fixtures folder..."
    parse_all_fixtures

    local fixture_count=${#FIXTURE_COURSES[@]}
    if [ "$fixture_count" -gt 0 ]; then
        green "  Parsed $fixture_count course(s) from fixtures:"
        for c in "${FIXTURE_COURSES[@]}"; do
            echo "    - $c"
        done
        echo ""

        blue "  [2/3] Updating config file..."
        update_courses_conf
        green "  Config file updated"
    else
        yellow "  No valid fixture files found, using existing config"
    fi

    echo ""

    blue "  [3/3] Displaying assignment requirements..."
    echo ""
    bold "========== Requirements Overview =========="
    echo ""

    local course_count=0
    declare -A DISPLAYED_SEEN

    while IFS= read -r course; do
        [ -z "$course" ] && continue
        [ "${DISPLAYED_SEEN[$course]:-}" = "1" ] && continue
        DISPLAYED_SEEN[$course]=1

        extract_course_info "$course"
        ((course_count++)) || true
    done < <(config_list_courses)

    echo "  -------- Summary --------"
    echo "  Courses: $course_count"
    echo "  Fields:  ${#DISPLAY_ORDER[@]} items"
    echo ""
    green "  Done"
    log_info "extractor: scanned $course_count courses from $CONFIG_FILE"
}