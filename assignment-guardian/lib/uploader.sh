#!/bin/bash
# ============================================================
# uploader.sh — 模块3: 一键打包上传
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SCP_TIMEOUT=300
MAX_RETRY=3
CHUNK_SIZE=$((1024 * 1024 * 50))

parse_target() {
    local target="$1"
    local user host path
    
    if [[ "$target" =~ ^([^@]+)@([^:]+):(.+)$ ]]; then
        user="${BASH_REMATCH[1]}"
        host="${BASH_REMATCH[2]}"
        path="${BASH_REMATCH[3]}"
        echo "$user|$host|$path"
    else
        echo "||$target"
    fi
}

check_remote_dir() {
    local target="$1"
    local parsed=$(parse_target "$target")
    local user=$(echo "$parsed" | cut -d'|' -f1)
    local host=$(echo "$parsed" | cut -d'|' -f2)
    local path=$(echo "$parsed" | cut -d'|' -f3)
    
    # 去除尾部斜杠
    path=$(echo "$path" | sed 's|/$||')
    
    if [ -z "$host" ] || [ "$host" = ":" ]; then
        if [ -d "$path" ]; then
            return 0
        else
            return 1
        fi
    fi
    
    if ssh -o ConnectTimeout=10 "$user@$host" "test -d '$path'" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

upload_chunked() {
    local local_file="$1"
    local target="$2"
    local parsed=$(parse_target "$target")
    local user=$(echo "$parsed" | cut -d'|' -f1)
    local host=$(echo "$parsed" | cut -d'|' -f2)
    local remote_path=$(echo "$parsed" | cut -d'|' -f3)
    remote_path=$(echo "$remote_path" | sed 's|/$||')
    local base_name=$(basename "$local_file")
    local file_size=$(stat -c%s "$local_file" 2>/dev/null || stat -f%z "$local_file" 2>/dev/null || echo 0)
    local num_chunks=$((file_size / CHUNK_SIZE + 1))
    local chunk=0
    
    echo "  分片上传: $base_name ($file_size bytes, $num_chunks 片)"
    
    while [ $chunk -lt $num_chunks ]; do
        local start=$((chunk * CHUNK_SIZE))
        local chunk_file="${base_name}.part${chunk}"
        
        echo "    上传分片 ${chunk}/${num_chunks}..."
        dd if="$local_file" of="$chunk_file" bs="$CHUNK_SIZE" skip="$chunk" count=1 2>/dev/null
        
        if [ -z "$host" ] || [ "$host" = ":" ]; then
            cp "$chunk_file" "$remote_path/"
        else
            if scp -o ConnectTimeout=30 "$chunk_file" "$user@$host:$remote_path/" 2>/dev/null; then
                green "    ✓ 分片 ${chunk} 上传成功"
                rm -f "$chunk_file"
            else
                red "    ✗ 分片 ${chunk} 上传失败"
                rm -f "$chunk_file"
                return 1
            fi
        fi
        
        ((chunk++)) || true
    done
    
    echo "  在目标合并分片..."
    if [ -z "$host" ] || [ "$host" = ":" ]; then
        cat "$remote_path/${base_name}.part"* > "$remote_path/$base_name"
        rm -f "$remote_path/${base_name}.part"*
    else
        if ssh "$user@$host" "cd '$remote_path' && cat ${base_name}.part* > '$base_name' && rm -f ${base_name}.part*" 2>/dev/null; then
            green "  ✓ 分片合并完成"
            return 0
        else
            red "  ✗ 分片合并失败"
            return 1
        fi
    fi
    green "  ✓ 分片合并完成"
    return 0
}

upload_rsync() {
    local local_file="$1"
    local target="$2"
    
    if command_exists rsync; then
        echo "  使用 rsync 断点续传..."
        if rsync -avz --progress --partial --timeout=300 "$local_file" "$target" 2>&1; then
            green "  ✓ rsync 上传完成"
            return 0
        else
            yellow "  rsync 失败，回退到 cp/scp"
            return 1
        fi
    else
        return 1
    fi
}

upload_scp() {
    local local_file="$1"
    local target="$2"
    local parsed=$(parse_target "$target")
    local user=$(echo "$parsed" | cut -d'|' -f1)
    local host=$(echo "$parsed" | cut -d'|' -f2)
    local remote_path=$(echo "$parsed" | cut -d'|' -f3)
    remote_path=$(echo "$remote_path" | sed 's|/$||')
    local retry=0
    local max_retry="$MAX_RETRY"
    
    if [ -z "$host" ] || [ "$host" = ":" ]; then
        echo "  本地复制..."
        local dest_file="$remote_path/$(basename "$local_file")"
        if cp "$local_file" "$dest_file"; then
            green "  ✓ 本地复制完成"
            if [ -f "$dest_file" ]; then
                return 0
            else
                red "  ✗ 本地复制失败：目标文件不存在"
                return 1
            fi
        else
            red "  ✗ 本地复制失败"
            return 1
        fi
    fi
    
    while [ $retry -lt $max_retry ]; do
        echo "  SCP 上传 (尝试 $((retry + 1))/$max_retry)..."
        
        if timeout "$SCP_TIMEOUT" scp -o ConnectTimeout=30 "$local_file" "$user@$host:$remote_path/" 2>/dev/null; then
            green "  ✓ SCP 上传成功"
            return 0
        fi
        
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            yellow "  SCP 超时，重试..."
        elif [ $exit_code -eq 1 ]; then
            red "  SCP 认证失败或连接拒绝"
            return 1
        else
            yellow "  SCP 失败 (代码: $exit_code)，重试..."
        fi
        
        ((retry++)) || true
        sleep $((retry * 2))
    done
    
    red "  ✗ SCP 上传失败，已达最大重试次数"
    return 1
}

uploader_upload() {
    local course="$1"
    local dry_run="${2:-false}"
    local skip_verify="${3:-false}"
    
    local target=$(config_get "$course" "target")
    local naming=$(config_get "$course" "naming")
    local submit_method=$(config_get "$course" "submit")
    
    if [ -z "$target" ]; then
        red "错误: 课程 '$course' 未配置提交目标 (target)"
        return 1
    fi
    
    echo ""
    bold "========== 打包上传: $course =========="
    echo ""
    
    local tarball="${naming:-${course}_backup.tar.gz}"
    tarball=$(echo "$tarball" | sed "s/学号/${STUDENT_ID:-unknown}/g")
    tarball=$(echo "$tarball" | sed "s/姓名/${STUDENT_NAME:-}/g")
    
    echo "  打包文件: $tarball"
    echo "  提交目标: $target"
    echo "  提交方式: $submit_method"
    
    if [ "$dry_run" = "true" ]; then
        yellow "  [DRY-RUN] 跳过实际打包和上传"
        echo ""
        return 0
    fi
    
    if [ "$skip_verify" = "false" ]; then
        echo "  [0/4] 执行前置规范检查..."
        if ! checker_verify "$course" "."; then
            red "  [0/4] 规范检查未通过，阻止上传"
            log_error "uploader: $course 规范检查失败，上传被阻止"
            return 1
        fi
        green "  [0/4] 规范检查通过"
    fi
    
    echo ""
    echo "  [1/4] 正在打包..."
    
    rm -f "$tarball"
    
    local exclude_opts="--exclude=logs --exclude=.git --exclude=*.tar.gz --exclude=*.zip --exclude=.DS_Store --exclude=__pycache__"
    
    local tar_output=$(tar czf "$tarball" $exclude_opts . 2>&1)
    
    if [ -f "$tarball" ] && [ -s "$tarball" ]; then
        local size=$(du -h "$tarball" | cut -f1)
        green "  [1/4] 打包完成 ($size): $tarball"
    else
        red "  [1/4] 打包失败"
        return 1
    fi
    
    echo ""
    echo "  [2/4] 检查目标目录..."
    if ! check_remote_dir "$target"; then
        red "  [2/4] 错误: 目标目录不存在: $target"
        red "       请手动创建目录后再上传"
        return 1
    fi
    green "  [2/4] 目标目录就绪"
    
    echo ""
    echo "  [3/4] 正在上传..."
    
    local file_size=$(stat -c%s "$tarball" 2>/dev/null || stat -f%z "$tarball" 2>/dev/null || echo 0)
    
    # 去除目标路径尾部斜杠
    local target_no_slash=$(echo "$target" | sed 's|/$||')
    
    if [ "$file_size" -gt $((1024 * 1024 * 500)) ]; then
        if ! upload_chunked "$tarball" "$target"; then
            red "  [3/4] 分片上传失败"
            return 1
        fi
    else
        local parsed=$(parse_target "$target")
        local host=$(echo "$parsed" | cut -d'|' -f1)
        local remote_path=$(echo "$parsed" | cut -d'|' -f3)
        remote_path=$(echo "$remote_path" | sed 's|/$||')
        
        if [ -z "$host" ] || [ "$host" = ":" ]; then
            echo "  本地路径，使用 cp 复制..."
            local dest_file="$remote_path/$(basename "$tarball")"
            
            if cp "$tarball" "$dest_file"; then
                green "  ✓ 本地复制完成"
                if [ -f "$dest_file" ]; then
                    echo "  已上传到: $dest_file"
                else
                    red "  ✗ 本地复制失败：目标文件不存在"
                    return 1
                fi
            else
                red "  ✗ 本地复制失败"
                return 1
            fi
        else
            if ! upload_rsync "$tarball" "$target"; then
                if ! upload_scp "$tarball" "$target"; then
                    red "  [3/4] 上传失败"
                    return 1
                fi
            fi
        fi
    fi
    green "  [3/4] 上传完成"
    
    echo ""
    echo "  [4/4] 正在校验..."
    local local_md5 remote_md5
    local_md5=$(file_md5 "$tarball")
    
    local dest_file="$target_no_slash/$(basename "$tarball")"
    
    if [ -f "$dest_file" ]; then
        remote_md5=$(file_md5 "$dest_file")
    else
        red "  [4/4] 错误: 目标文件不存在!"
        return 1
    fi
    
    if [ -n "$remote_md5" ] && [ "$local_md5" = "$remote_md5" ]; then
        green "  [4/4] 校验通过: MD5=$local_md5"
    else
        yellow "  [4/4] 校验失败"
        yellow "       本地MD5: $local_md5"
        yellow "       远程MD5: $remote_md5"
        return 1
    fi
    
    echo ""
    green "  ✓ 上传流程完成"
    log_info "uploader: $course → $target  tarball=$tarball  md5=$local_md5"
}

uploader_package_only() {
    local course="$1"
    
    local naming=$(config_get "$course" "naming")
    local tarball="${naming:-${course}_backup.tar.gz}"
    tarball=$(echo "$tarball" | sed "s/学号/${STUDENT_ID:-unknown}/g")
    tarball=$(echo "$tarball" | sed "s/姓名/${STUDENT_NAME:-}/g")
    
    echo ""
    bold "========== 仅打包: $course =========="
    echo ""
    
    echo "  打包文件: $tarball"
    
    rm -f "$tarball"
    
    local exclude_opts="--exclude=logs --exclude=.git --exclude=*.tar.gz --exclude=*.zip --exclude=.DS_Store --exclude=__pycache__"
    
    local tar_output=$(tar czf "$tarball" $exclude_opts . 2>&1)
    
    if [ -f "$tarball" ] && [ -s "$tarball" ]; then
        local size=$(du -h "$tarball" | cut -f1)
        green "  ✓ 打包完成 ($size): $tarball"
        log_info "uploader: $course 仅打包完成 tarball=$tarball"
        return 0
    else
        red "  ✗ 打包失败"
        return 1
    fi
}
