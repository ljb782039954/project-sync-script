# Bug Fix: Total Sync Log Not Accumulating Files

## Problem
The `total_sync_log.json` file was not correctly accumulating files across multiple syncs. While the summary counts (total_files_added, total_files_modified, total_files_deleted) were being calculated correctly, the actual file arrays (all_files.added, all_files.modified, all_files.deleted) were not being merged properly.

## Root Cause
The `parse_json_array()` function in `sync_to_target.sh` had a bug when parsing single-line JSON arrays.

### Original Code
```bash
parse_json_array() {
    local json_file="$1"
    local array_path="$2"
    local key="${array_path##*.}"
    
    local array_content=$(sed -n "/\"$key\":[[:space:]]*\[/,/\]/p" "$json_file" | sed '1d;$d')
    echo "$array_content" | grep -o '"[^"]*"' | sed 's/"//g'
}
```

### The Bug
The command `sed '1d;$d'` deletes the first and last lines. This works fine for multi-line arrays:
```json
"modified": [
    "file1.js",
    "file2.js"
]
```

But fails for single-line arrays:
```json
"modified": ["file1.js"]
```

In the single-line case, the first and last line are the same line, so the entire content is deleted, resulting in no files being parsed.

### Fixed Code (Version 2 - Using awk)
```bash
parse_json_array() {
    local json_file="$1"
    local array_path="$2"
    local key="${array_path##*.}"
    
    awk -v key="\"$key\"" '
        $0 ~ key": \\[" {
            if ($0 ~ /\]/) {
                match($0, /\[.*\]/)
                content = substr($0, RSTART+1, RLENGTH-2)
                print content
                exit
            } else {
                in_array = 1
                next
            }
        }
        in_array {
            if ($0 ~ /\]/) {
                exit
            } else {
                print $0
            }
        }
    ' "$json_file" | grep -o '"[^"]*"' | sed 's/"//g'
}
```

### The Fix
使用 awk 进行精确的 JSON 数组提取：
1. 查找匹配的键（如 `"added": [`）
2. 检查是否是单行数组（包含 `]`）
   - 单行：提取 `[` 和 `]` 之间的内容
   - 多行：标记进入数组模式，收集直到遇到 `]`
3. 从提取的内容中提取所有引号内的字符串
4. 不会误提取其他键名（如 `"modified"`, `"deleted"`）

这个方法可以正确处理：
- 单行数组：`"added": ["file1.js"]`
- 单行多元素：`"added": ["file1.js", "file2.js"]`
- 多行数组
- 空数组：`"added": []`
- 嵌套在对象中的数组

## Testing
Run the test script to verify the fix:
```bash
bash source_path/syncScript/test_parse_fix.sh
```

## Impact
- **Bash script** (`sync_to_target.sh`): Fixed
- **PowerShell script** (`sync_to_target.ps1`): No fix needed (uses native JSON parsing)

## Next Steps
1. Delete the existing `total_sync_log.json` files to start fresh
2. Run multiple syncs to verify files are being accumulated correctly
3. Check that all three arrays (added, modified, deleted) are being tracked properly
