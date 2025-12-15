#!/bin/bash
# sync_to_target.sh
# 文件同步工具 - Bash 版本
# 用法: 
#   1. 使用配置文件: ./sync_to_target.sh
#   2. 使用命令行参数: ./sync_to_target.sh "路径"

TARGET_PATH="$1"

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
                if [ -n "$path" ] && [ "$path" != "null" ] && [ "$path" != "target_paths" ]; then
                    target_paths+=("$path")
                fi
            done < <(grep -A 100 '"target_paths"' "$config_path" | grep -E '"[^"]*"' | head -20)
        fi
    fi
    
    echo "$source_path"
    for path in "${target_paths[@]}"; do
        echo "$path"
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

# 同步到单个目标目录的函数
sync_to_target() {
    local source_dir="$1"
    local target_dir="$2"
    
    echo ""
    echo "开始同步到: $target_dir"
    
    # 检查目标目录是否存在
    if [ ! -d "$target_dir" ]; then
        echo "错误: 目标目录不存在: $target_dir"
        echo "提示: 请先创建目标目录，或检查路径是否正确"
        return 1
    fi
    
    # 创建日志目录
    local log_dir="$source_dir/.sync_logs"
    mkdir -p "$log_dir"
    
    # 生成日志文件名（带时间戳）
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local target_name=$(basename "$target_dir")
    local log_file="$log_dir/sync_${target_name}_${timestamp}.txt"
    
    # 检查是否在 Git 仓库中
    local has_git_repo=false
    local original_dir=$(pwd)
    cd "$source_dir" || return 1
    
    if git rev-parse --git-dir > /dev/null 2>&1; then
        has_git_repo=true
    fi
    
    # 获取 Git 变更的文件
    local changed_files=""
    if [ "$has_git_repo" = true ]; then
        changed_files=$(git diff --name-status HEAD~1 HEAD 2>/dev/null)
        if [ $? -ne 0 ]; then
            # 如果没有上一个 commit，获取所有已跟踪的文件
            changed_files=$(git ls-files 2>/dev/null | sed 's/^/A\t/')
        fi
    fi
    
    cd "$original_dir" || return 1
    
    # 记录同步开始
    {
        echo "=================================================================================="
        echo "同步时间: $(date '+%Y-%m-%d %H:%M:%S')"
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
    local files_to_delete=()
    
    if [ -n "$changed_files" ]; then
        while IFS=$'\t' read -r status file_path; do
            case "$status" in
                A)
                    echo "[新增] $file_path" >> "$log_file"
                    ((added_count++))
                    ;;
                M)
                    echo "[修改] $file_path" >> "$log_file"
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
        # 如果没有 Git 变更信息，记录全量同步
        echo "[全量同步] 未检测到 Git 变更，同步所有文件" >> "$log_file"
    fi
    
    # 使用 rsync 进行同步（排除 .git 和同步日志目录）
    echo "" >> "$log_file"
    echo "开始同步文件..." >> "$log_file"
    echo "" >> "$log_file"
    
    rsync -av \
        --exclude='.git' \
        --exclude='.sync_logs' \
        --exclude='sync_to_target.ps1' \
        --exclude='sync_to_target.sh' \
        --exclude='config.json' \
        "$source_dir/" "$target_dir/" >> "$log_file" 2>&1
    
    local rsync_exit_code=$?
    if [ $rsync_exit_code -ne 0 ]; then
        echo "警告: rsync 同步过程中出现错误 (返回码: $rsync_exit_code)" >> "$log_file"
    else
        echo "文件同步完成 (rsync 返回码: $rsync_exit_code)" >> "$log_file"
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
        echo "日志文件: $log_file"
        echo "=================================================================================="
    } >> "$log_file"
    
    # 显示结果
    echo "同步完成!"
    echo "原始项目: $source_dir"
    echo "目标项目: $target_dir"
    echo "新增: $added_count | 修改: $modified_count | 删除: $deleted_count"
    echo "日志文件: $log_file"
    
    return 0
}

# ============================================================================
# 主程序逻辑
# ============================================================================

config_path="$SCRIPT_DIR/$CONFIG_FILE"
source_dir=""
target_paths=()

# 如果提供了命令行参数，优先使用命令行参数
if [ -n "$TARGET_PATH" ]; then
    echo "使用命令行参数模式"
    source_dir="$SCRIPT_DIR"
    target_paths=("$TARGET_PATH")
else
    # 读取配置文件（自动检测 JSON 或 TXT）
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
        echo ""
        echo "或使用数组格式:"
        echo '{'
        echo '  "source_path": "原始项目路径",'
        echo '  "target_paths": ['
        echo '    "目标项目路径1",'
        echo '    "目标项目路径2"'
        echo '  ]'
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
    
    # 其余行是目标路径
    for ((i=1; i<${#config_lines[@]}; i++)); do
        target_path=$(resolve_path_safe "${config_lines[$i]}" "$SCRIPT_DIR")
        target_paths+=("$target_path")
    done
    
    if [ ${#target_paths[@]} -eq 0 ]; then
        echo "错误: 配置文件中没有找到目标路径 (path_to_*)"
        exit 1
    fi
    
    echo "找到 ${#target_paths[@]} 个目标路径"
fi

# 执行同步到所有目标路径
success_count=0
fail_count=0

for target_path in "${target_paths[@]}"; do
    if sync_to_target "$source_dir" "$target_path"; then
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
