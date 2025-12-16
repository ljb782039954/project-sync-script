#!/bin/bash
# sync_to_target.sh
# 文件同步工具 - Bash 版本
# 用法: 
#   1. 增量同步（默认）: ./sync_to_target.sh
#   2. 完全同步: ./sync_to_target.sh --all

FULL_SYNC=false
if [ "$1" = "--all" ]; then
    FULL_SYNC=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 读取 JSON 配置文件（使用 jq 如果可用，否则使用简单解析）
read_json_config_file() {
    local config_path="$1"
    local source_path=""
    local target_paths=()
    
    if [ ! -f "$config_path" ]; then
        return 1
    fi
    
        # 检查是否有 jq 命令
    local exclude_patterns=()
    if command -v jq >/dev/null 2>&1; then
        # 使用 jq 解析 JSON
        source_path=$(jq -r '.source_path // empty' "$config_path" 2>/dev/null)
        
        # 检查 target_paths 是数组还是对象
        local target_type=$(jq -r 'if .target_paths | type == "array" then "array" elif .target_paths | type == "object" then "object" else "empty" end' "$config_path" 2>/dev/null)
        
        if [ "$target_type" = "array" ]; then
            # 数组格式
            while IFS= read -r path; do
                if [ -n "$path" ] && [ "$path" != "null" ]; then
                    target_paths+=("$path")
                fi
            done < <(jq -r '.target_paths[]?' "$config_path" 2>/dev/null)
        elif [ "$target_type" = "object" ]; then
            # 对象格式
            while IFS= read -r path; do
                if [ -n "$path" ] && [ "$path" != "null" ]; then
                    target_paths+=("$path")
                fi
            done < <(jq -r '.target_paths | to_entries[] | .value' "$config_path" 2>/dev/null)
        fi
        
        # 解析 exclude_patterns
        while IFS= read -r pattern; do
            if [ -n "$pattern" ] && [ "$pattern" != "null" ]; then
                exclude_patterns+=("$pattern")
            fi
        done < <(jq -r '.exclude_patterns[]?' "$config_path" 2>/dev/null)
    else
        # 简单的 JSON 解析（不依赖 jq）
        # 提取 source_path
        source_path=$(grep -o '"source_path"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_path" | sed 's/.*"source_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
        
        # 提取 target_paths（支持对象和数组格式）
        # 对象格式: "key": "value"
        while IFS= read -r line; do
            local path=$(echo "$line" | sed 's/.*"[^"]*"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            if [ -n "$path" ] && [ "$path" != "null" ]; then
                target_paths+=("$path")
            fi
        done < <(grep -E '"[^"]*"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_path" | grep -v '"source_path"')
        
        # 如果没找到，尝试数组格式
        if [ ${#target_paths[@]} -eq 0 ]; then
            while IFS= read -r line; do
                local path=$(echo "$line" | sed 's/.*"\([^"]*\)".*/\1/')
                if [ -n "$path" ] && [ "$path" != "null" ] && [ "$path" != "target_paths" ] && [ "$path" != "exclude_patterns" ]; then
                    target_paths+=("$path")
                fi
            done < <(grep -A 100 '"target_paths"' "$config_path" | grep -E '"[^"]*"' | head -20)
        fi
        
        # 简单解析 exclude_patterns（不使用 jq）
        local in_exclude=false
        while IFS= read -r line; do
            if [[ "$line" =~ exclude_patterns ]]; then
                in_exclude=true
                continue
            fi
            if [ "$in_exclude" = true ]; then
                if [[ "$line" =~ \] ]]; then
                    break
                fi
                local pattern=$(echo "$line" | sed 's/.*"\([^"]*\)".*/\1/')
                if [ -n "$pattern" ] && [ "$pattern" != "null" ]; then
                    exclude_patterns+=("$pattern")
                fi
            fi
        done < "$config_path"
    fi
    
    echo "$source_path"
    for path in "${target_paths[@]}"; do
        echo "$path"
    done
    # 输出排除模式（用特殊分隔符）
    echo "---EXCLUDE_PATTERNS---"
    for pattern in "${exclude_patterns[@]}"; do
        echo "$pattern"
    done
}

# 读取配置文件（JSON 格式）
read_config_file() {
    local script_dir="$1"
    local json_config="$script_dir/config.json"
    
    if [ -f "$json_config" ]; then
        echo "读取配置文件: $json_config" >&2
        read_json_config_file "$json_config"
        return $?
    fi
    
    return 1
}

# 解析路径（支持相对路径和绝对路径）
resolve_path_safe() {
    local path="$1"
    local base_dir="$2"
    
    if [[ "$path" == /* ]]; then
        echo "$(cd "$path" 2>/dev/null && pwd)"
    else
        echo "$(cd "$base_dir/$path" 2>/dev/null && pwd)"
    fi
}

# 安装 Git Hook
install_git_hook() {
    local script_dir="$1"
    local source_dir="$2"
    
    local hook_template="$script_dir/.git_hooks/post-commit"
    local git_hooks_dir="$source_dir/.git/hooks"
    local hook_path="$git_hooks_dir/post-commit"
    
    if [ ! -f "$hook_template" ]; then
        return 1
    fi
    
    if [ ! -d "$git_hooks_dir" ]; then
        echo "警告: .git/hooks 目录不存在，跳过 Git Hook 安装" >&2
        return 1
    fi
    
    # 检查是否需要更新 Hook
    local need_install=false
    if [ ! -f "$hook_path" ]; then
        need_install=true
    else
        if ! cmp -s "$hook_template" "$hook_path"; then
            need_install=true
        fi
    fi
    
    if [ "$need_install" = true ]; then
        cp "$hook_template" "$hook_path"
        chmod +x "$hook_path"
        echo "Git Hook 已安装/更新: $hook_path" >&2
        return 0
    fi
    
    return 1
}

# 获取 Git 变更文件列表
get_git_changed_files() {
    local source_dir="$1"
    local has_git_repo=false
    local changed_files=""
    
    local original_dir=$(pwd)
    cd "$source_dir" || return 1
    
    if git rev-parse --git-dir > /dev/null 2>&1; then
        has_git_repo=true
        changed_files=$(git diff --name-status HEAD~1 HEAD 2>/dev/null)
        if [ $? -ne 0 ]; then
            # 如果没有上一个 commit，返回空
            changed_files=""
        fi
    fi
    
    cd "$original_dir" || return 1
    
    echo "$has_git_repo"
    echo "$changed_files"
}

# 读取 .gitignore 文件获取排除规则
get_gitignore_patterns() {
    local source_dir="$1"
    local gitignore_path="$source_dir/.gitignore"
    
    if [ -f "$gitignore_path" ]; then
        grep -v '^#' "$gitignore_path" | grep -v '^[[:space:]]*$' | while IFS= read -r line; do
            echo "$line"
        done
    fi
}

# 检查文件路径是否匹配排除模式
test_exclude_pattern() {
    local file_path="$1"
    shift
    local exclude_patterns=("$@")
    
    for pattern in "${exclude_patterns[@]}"; do
        local normalized_pattern=$(echo "$pattern" | tr '/' '\\')
        local normalized_file_path=$(echo "$file_path" | tr '/' '\\')
        
        # 如果模式为空，跳过
        if [ -z "$normalized_pattern" ]; then
            continue
        fi
        
        # 如果模式以 \ 开头，从根目录匹配
        if [[ "$normalized_pattern" == \\* ]]; then
            normalized_pattern="${normalized_pattern#\\}"
            if [[ "$normalized_file_path" == *"\\$normalized_pattern"* ]] || [[ "$normalized_file_path" == "$normalized_pattern"* ]]; then
                return 0
            fi
        # 如果模式包含 \，表示路径匹配
        elif [[ "$normalized_pattern" == *\\* ]]; then
            if [[ "$normalized_file_path" == *"\\$normalized_pattern"* ]] || [[ "$normalized_file_path" == *"\\$normalized_pattern\\"* ]] || [[ "$normalized_file_path" == "$normalized_pattern" ]]; then
                return 0
            fi
        # 否则匹配文件名或目录名
        else
            local file_name=$(basename "$normalized_file_path")
            if [[ "$file_name" == $normalized_pattern ]] || [[ "$normalized_file_path" == *"\\$normalized_pattern"* ]] || [[ "$normalized_file_path" == *"\\$normalized_pattern\\"* ]]; then
                return 0
            fi
        fi
    done
    
    return 1
}

# 同步到单个目标目录的函数
sync_to_target() {
    local source_dir="$1"
    local target_dir="$2"
    local full_sync="$3"
    shift 3
    local exclude_patterns=("$@")
    
    echo ""
    echo "开始同步到: $target_dir"
    echo "同步模式: $(if [ "$full_sync" = true ]; then echo '完全同步'; else echo '增量同步'; fi)"
    
    # 自动创建目标目录（如果不存在）
    if [ ! -d "$target_dir" ]; then
        echo "目标目录不存在，正在创建: $target_dir"
        if mkdir -p "$target_dir"; then
            echo "目标目录创建成功"
        else
            echo "错误: 无法创建目标目录" >&2
            return 1
        fi
    fi
    
    # 创建源项目日志目录
    local source_log_dir="$source_dir/.syncScript_logs"
    mkdir -p "$source_log_dir"
    
    # 创建目标项目日志目录
    local target_log_dir="$target_dir/.syncScript_logs"
    mkdir -p "$target_log_dir"
    
    # 生成日志文件名（带时间戳）
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local target_name=$(basename "$target_dir")
    local source_log_file="$source_log_dir/sync_${target_name}_${timestamp}.txt"
    local target_log_file="$target_log_dir/sync_${timestamp}.txt"
    
    # 获取 Git 信息
    local git_info=$(get_git_changed_files "$source_dir")
    local has_git_repo=$(echo "$git_info" | head -1)
    local changed_files=$(echo "$git_info" | tail -n +2)
    
    # 记录同步开始
    local log_file=$(mktemp)
    {
        echo "=================================================================================="
        echo "同步时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "同步模式: $(if [ "$full_sync" = true ]; then echo '完全同步'; else echo '增量同步'; fi)"
        echo "原始项目: $source_dir"
        echo "目标项目: $target_dir"
        echo "Git 仓库: $(if [ "$has_git_repo" = true ]; then echo '是'; else echo '否'; fi)"
        echo "=================================================================================="
        echo ""
    } > "$log_file"
    
    # 统计变量
    local added_count=0
    local modified_count=0
    local deleted_count=0
    
    # 解析 Git 变更并记录
    local files_to_sync=()
    local files_to_delete=()
    
    if [ "$full_sync" = true ]; then
        # 完全同步模式：同步所有文件
        echo "[完全同步] 同步所有文件（排除 syncScript、.git、.syncScript_logs 和 .gitignore 中的文件）" >> "$log_file"
        echo "" >> "$log_file"
    else
        # 增量同步模式：只同步 Git 变更的文件
        if [ -n "$changed_files" ]; then
            while IFS=$'\t' read -r status file_path; do
                # 排除 syncScript 文件夹
                if [[ "$file_path" == syncScript/* ]] || [[ "$file_path" == syncScript\\* ]]; then
                    continue
                fi
                
                # 检查是否匹配配置的排除模式
                if test_exclude_pattern "$file_path" "${exclude_patterns[@]}"; then
                    echo "[跳过] $file_path (匹配排除模式)" >> "$log_file"
                    continue
                fi
                
                case "$status" in
                    A)
                        echo "[新增] $file_path" >> "$log_file"
                        files_to_sync+=("$file_path")
                        ((added_count++))
                        ;;
                    M)
                        echo "[修改] $file_path" >> "$log_file"
                        files_to_sync+=("$file_path")
                        ((modified_count++))
                        ;;
                    D)
                        echo "[删除] $file_path" >> "$log_file"
                        files_to_delete+=("$file_path")
                        ((deleted_count++))
                        ;;
                esac
            done <<< "$changed_files"
        else
            if [ "$has_git_repo" = true ]; then
                echo "[增量同步] 未检测到 Git 变更" >> "$log_file"
            else
                echo "[增量同步] 当前目录不是 Git 仓库，无法进行增量同步" >> "$log_file"
            fi
        fi
    fi
    
    # 执行文件同步
    echo "" >> "$log_file"
    echo "开始同步文件..." >> "$log_file"
    echo "" >> "$log_file"
    
    # 构建 rsync 排除参数
    local exclude_args=()
    exclude_args+=("--exclude=.git")
    exclude_args+=("--exclude=.syncScript_logs")
    exclude_args+=("--exclude=syncScript")
    
    # 读取 .gitignore 中的排除规则
    while IFS= read -r pattern; do
        if [ -n "$pattern" ]; then
            exclude_args+=("--exclude=$pattern")
        fi
    done < <(get_gitignore_patterns "$source_dir")
    
    # 添加配置中的排除模式
    for pattern in "${exclude_patterns[@]}"; do
        if [ -n "$pattern" ]; then
            exclude_args+=("--exclude=$pattern")
        fi
    done
    
    if [ "$full_sync" = true ] || [ ${#files_to_sync[@]} -eq 0 ]; then
        # 完全同步或全量同步
        rsync -av "${exclude_args[@]}" "$source_dir/" "$target_dir/" >> "$log_file" 2>&1
        
        local rsync_exit_code=$?
        if [ $rsync_exit_code -ne 0 ]; then
            echo "警告: rsync 同步过程中出现错误 (返回码: $rsync_exit_code)" >> "$log_file"
        else
            echo "文件同步完成 (rsync 返回码: $rsync_exit_code)" >> "$log_file"
        fi
    else
        # 增量同步：只同步变更的文件
        for file_path in "${files_to_sync[@]}"; do
            local source_file="$source_dir/$file_path"
            local target_file="$target_dir/$file_path"
            local target_file_dir=$(dirname "$target_file")
            
            if [ ! -d "$target_file_dir" ]; then
                mkdir -p "$target_file_dir"
            fi
            
            if [ -f "$source_file" ] || [ -d "$source_file" ]; then
                cp -r "$source_file" "$target_file" 2>/dev/null
                echo "[已同步] $file_path" >> "$log_file"
            fi
        done
        echo "增量文件同步完成" >> "$log_file"
    fi
    
    # 处理删除的文件
    for file_path in "${files_to_delete[@]}"; do
        local target_file="$target_dir/$file_path"
        if [ -f "$target_file" ] || [ -d "$target_file" ]; then
            rm -rf "$target_file"
            if [ $? -eq 0 ]; then
                echo "[已删除] $file_path" >> "$log_file"
            else
                echo "[删除失败] $file_path" >> "$log_file"
            fi
        else
            echo "[跳过删除] $file_path - 文件不存在于目标目录" >> "$log_file"
        fi
    done
    
    # 记录同步结果
    {
        echo ""
        echo "=================================================================================="
        echo "同步完成"
        echo "新增文件: $added_count"
        echo "修改文件: $modified_count"
        echo "删除文件: $deleted_count"
        echo "源项目日志: $source_log_file"
        echo "目标项目日志: $target_log_file"
        echo "=================================================================================="
    } >> "$log_file"
    
    # 复制日志文件到源项目和目标项目
    cp "$log_file" "$source_log_file"
    cp "$log_file" "$target_log_file"
    rm "$log_file"
    
    # 显示结果
    echo "同步完成!"
    echo "原始项目: $source_dir"
    echo "目标项目: $target_dir"
    echo "新增: $added_count | 修改: $modified_count | 删除: $deleted_count"
    echo "源项目日志: $source_log_file"
    echo "目标项目日志: $target_log_file"
    
    return 0
}

# ============================================================================
# 主程序逻辑
# ============================================================================

# 读取配置文件
mapfile -t config_lines < <(read_config_file "$SCRIPT_DIR")

if [ ${#config_lines[@]} -eq 0 ]; then
    echo "错误: 配置文件不存在或格式不正确"
    echo "提示: 请创建 config.json 文件"
    echo ""
    echo "JSON 格式示例 (config.json):"
    echo '{'
    echo '  "source_path": "原始项目路径",'
    echo '  "target_paths": {'
    echo '    "default": "目标项目路径1",'
    echo '    "version2": "目标项目路径2"'
    echo '  }'
    echo '}'
    exit 1
fi

# 第一行是源路径
source_path="${config_lines[0]}"
source_dir=$(resolve_path_safe "$source_path" "$SCRIPT_DIR")

if [ ! -d "$source_dir" ]; then
    echo "错误: 原始项目目录不存在: $source_dir"
    exit 1
fi

# 安装 Git Hook
install_git_hook "$SCRIPT_DIR" "$source_dir"

# 解析配置行，找到排除模式分隔符
target_paths=()
exclude_patterns=()
found_separator=false

for ((i=1; i<${#config_lines[@]}; i++)); do
    if [ "${config_lines[$i]}" = "---EXCLUDE_PATTERNS---" ]; then
        found_separator=true
        continue
    fi
    
    if [ "$found_separator" = true ]; then
        exclude_patterns+=("${config_lines[$i]}")
    else
        target_path=$(resolve_path_safe "${config_lines[$i]}" "$SCRIPT_DIR")
        target_paths+=("$target_path")
    fi
done

if [ ${#target_paths[@]} -eq 0 ]; then
    echo "错误: 配置文件中没有找到目标路径"
    exit 1
fi

echo "找到 ${#target_paths[@]} 个目标路径"
if [ ${#exclude_patterns[@]} -gt 0 ]; then
    echo "配置了 ${#exclude_patterns[@]} 个排除模式"
fi

# 执行同步到所有目标路径
success_count=0
fail_count=0

for target_path in "${target_paths[@]}"; do
    if sync_to_target "$source_dir" "$target_path" "$FULL_SYNC" "${exclude_patterns[@]}"; then
        ((success_count++))
    else
        ((fail_count++))
    fi
done

# 显示总结
echo ""
echo "=================================================================================="
echo "同步总结"
echo "成功: $success_count | 失败: $fail_count"
echo "=================================================================================="
echo ""
