# Git post-commit hook (PowerShell 版本)
# 自动同步到目标项目（增量同步模式）
# 
# 此 Hook 会在每次 git commit 后自动触发同步脚本
# 同步模式：增量同步（只同步变更的文件）

# 获取脚本所在目录
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SyncScriptDir = Join-Path (Split-Path -Parent $ScriptDir) "syncScript"

# 检查脚本是否存在
$SyncScript = Join-Path $SyncScriptDir "sync_to_target.ps1"
if (-not (Test-Path $SyncScript)) {
    Write-Host "警告: 同步脚本不存在: $SyncScript"
    exit 0
}

# 执行同步脚本（增量同步模式，不传 --All 参数）
& $SyncScript

exit 0

