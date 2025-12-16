#!/bin/bash

# Test the fixed parse_json_array function

# 简单的 JSON 数组解析函数（不依赖 jq）
parse_json_array() {
    local json_file="$1"
    local array_path="$2"
    local key="${array_path##*.}"
    
    # 提取整个数组部分（从 "key": [ 到 ]）
    local array_section=$(sed -n "/\"$key\":[[:space:]]*\[/,/\]/p" "$json_file")
    
    # 直接从整个数组部分提取所有带引号的字符串
    # 这样可以处理单行和多行数组
    echo "$array_section" | grep -o '"[^"]*"' | sed 's/"//g' | grep -v "^$key$"
}

# Create test JSON files
cat > /tmp/test_single_line.json << 'EOF'
{
    "all_files": {
        "added": ["file1.js", "file2.js"],
        "modified": ["file3.js"],
        "deleted": []
    }
}
EOF

cat > /tmp/test_multi_line.json << 'EOF'
{
    "all_files": {
        "added": [
            "file1.js",
            "file2.js"
        ],
        "modified": [
            "file3.js"
        ],
        "deleted": []
    }
}
EOF

echo "=== Test 1: Single-line array with multiple items ==="
echo "Expected: file1.js, file2.js"
echo "Actual:"
parse_json_array "/tmp/test_single_line.json" "all_files.added"

echo ""
echo "=== Test 2: Single-line array with one item ==="
echo "Expected: file3.js"
echo "Actual:"
parse_json_array "/tmp/test_single_line.json" "all_files.modified"

echo ""
echo "=== Test 3: Single-line empty array ==="
echo "Expected: (nothing)"
echo "Actual:"
parse_json_array "/tmp/test_single_line.json" "all_files.deleted"

echo ""
echo "=== Test 4: Multi-line array with multiple items ==="
echo "Expected: file1.js, file2.js"
echo "Actual:"
parse_json_array "/tmp/test_multi_line.json" "all_files.added"

echo ""
echo "=== Test 5: Multi-line array with one item ==="
echo "Expected: file3.js"
echo "Actual:"
parse_json_array "/tmp/test_multi_line.json" "all_files.modified"

# Cleanup
rm -f /tmp/test_single_line.json /tmp/test_multi_line.json

echo ""
echo "=== All tests complete ==="
