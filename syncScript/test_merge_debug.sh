#!/bin/bash

# Test the parse and merge functions

# 简单的 JSON 数组解析函数（不依赖 jq）
parse_json_array() {
    local json_file="$1"
    local array_path="$2"
    local key="${array_path##*.}"
    
    # 使用 sed 提取数组内容
    # 匹配 "key": [ ... ] 的内容
    local array_content=$(sed -n "/\"$key\":[[:space:]]*\[/,/\]/p" "$json_file" | sed '1d;$d')
    
    # 提取所有带引号的字符串，排除逗号和空白
    echo "$array_content" | grep -o '"[^"]*"' | sed 's/"//g'
}

# 合并 JSON 数组（不依赖 jq）
merge_json_arrays() {
    local existing_items=("$@")
    
    echo "DEBUG: Number of items: ${#existing_items[@]}" >&2
    echo "DEBUG: Items: ${existing_items[@]}" >&2
    
    # 如果没有项目或第一个项目为空，返回空数组
    if [ ${#existing_items[@]} -eq 0 ] || [ -z "${existing_items[0]}" ]; then
        echo "[]"
        return
    fi
    
    # 构建 JSON 数组
    local json_array="["
    local first=true
    for item in "${existing_items[@]}"; do
        # 跳过空项
        if [ -z "$item" ]; then
            continue
        fi
        
        if [ "$first" = true ]; then
            json_array+="\"$item\""
            first=false
        else
            json_array+=",\"$item\""
        fi
    done
    json_array+="]"
    
    echo "$json_array"
}

# Test with the actual total_sync_log.json
total_log="../target_path/test/target-test-path/.syncScript_logs/total_sync_log.json"

echo "=== Testing parse_json_array ==="
echo "Parsing added files:"
parse_json_array "$total_log" "all_files.added"

echo ""
echo "=== Testing merge with new file ==="
existing_added_files=()
while IFS= read -r file; do
    [ -n "$file" ] && existing_added_files+=("$file")
done < <(parse_json_array "$total_log" "all_files.added")

echo "Existing files: ${existing_added_files[@]}"
echo "Adding new file: src/app/test_merge_fix.js"
existing_added_files+=("src/app/test_merge_fix.js")

echo "Merged result:"
merge_json_arrays "${existing_added_files[@]}"
