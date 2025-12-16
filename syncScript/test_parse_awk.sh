#!/bin/bash

# 测试新的 parse_json_array 函数

# 简单的 JSON 数组解析函数（不依赖 jq）
parse_json_array() {
    local json_file="$1"
    local array_path="$2"
    local key="${array_path##*.}"
    
    # 使用 awk 提取指定键的数组内容
    # 这个方法可以正确处理单行和多行数组
    awk -v key="\"$key\"" '
        # 找到匹配的键
        $0 ~ key": \\[" {
            # 检查是否是单行数组
            if ($0 ~ /\]/) {
                # 单行数组：提取 [ 和 ] 之间的内容
                match($0, /\[.*\]/)
                content = substr($0, RSTART+1, RLENGTH-2)
                print content
                exit
            } else {
                # 多行数组：标记开始
                in_array = 1
                next
            }
        }
        # 在数组内部
        in_array {
            if ($0 ~ /\]/) {
                # 数组结束
                exit
            } else {
                # 收集数组内容
                print $0
            }
        }
    ' "$json_file" | grep -o '"[^"]*"' | sed 's/"//g'
}

# 创建测试 JSON 文件
cat > /tmp/test_json.json << 'EOF'
{
    "timestamp": "2025-12-16T10:33:58.483Z",
    "sync_mode": "incremental",
    "files": {
        "added": ["src/app/test1.txt"],
        "modified": ["src/app/test_merge_fix.js"],
        "deleted": ["src/hooks/hooks2.js"]
    },
    "all_files": {
        "added": ["file1.js", "file2.js"],
        "modified": [],
        "deleted": []
    }
}
EOF

echo "=== 测试 1: 单行数组 - files.added ==="
echo "期望: src/app/test1.txt"
echo "实际:"
parse_json_array "/tmp/test_json.json" "files.added"

echo ""
echo "=== 测试 2: 单行数组 - files.modified ==="
echo "期望: src/app/test_merge_fix.js"
echo "实际:"
parse_json_array "/tmp/test_json.json" "files.modified"

echo ""
echo "=== 测试 3: 单行数组 - files.deleted ==="
echo "期望: src/hooks/hooks2.js"
echo "实际:"
parse_json_array "/tmp/test_json.json" "files.deleted"

echo ""
echo "=== 测试 4: 单行数组多个元素 - all_files.added ==="
echo "期望: file1.js 和 file2.js"
echo "实际:"
parse_json_array "/tmp/test_json.json" "all_files.added"

echo ""
echo "=== 测试 5: 空数组 - all_files.modified ==="
echo "期望: (无输出)"
echo "实际:"
parse_json_array "/tmp/test_json.json" "all_files.modified"

# 创建多行数组测试
cat > /tmp/test_multiline.json << 'EOF'
{
    "all_files": {
        "added": [
            "file1.js",
            "file2.js",
            "file3.js"
        ],
        "modified": [
            "file4.js"
        ],
        "deleted": []
    }
}
EOF

echo ""
echo "=== 测试 6: 多行数组 - all_files.added ==="
echo "期望: file1.js, file2.js, file3.js"
echo "实际:"
parse_json_array "/tmp/test_multiline.json" "all_files.added"

echo ""
echo "=== 测试 7: 多行数组单个元素 - all_files.modified ==="
echo "期望: file4.js"
echo "实际:"
parse_json_array "/tmp/test_multiline.json" "all_files.modified"

# 清理
rm -f /tmp/test_json.json /tmp/test_multiline.json

echo ""
echo "=== 测试完成 ==="
