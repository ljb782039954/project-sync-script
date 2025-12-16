# 调试测试脚本
$ScriptDir = $PSScriptRoot
Write-Host "ScriptDir: $ScriptDir"

# 读取配置
$config = Get-Content .\config.json | ConvertFrom-Json
Write-Host "Config source_path: $($config.source_path)"

# 解析路径
function Resolve-PathSafe {
    param([string]$Path, [string]$BaseDir)
    
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    } else {
        return [System.IO.Path]::GetFullPath((Join-Path $BaseDir $Path))
    }
}

$SourceDir = Resolve-PathSafe -Path $config.source_path -BaseDir $ScriptDir
Write-Host "Resolved SourceDir: $SourceDir"
Write-Host "SourceDir exists: $(Test-Path $SourceDir)"

# 测试目标路径
$TargetPaths = $config.target_paths.PSObject.Properties.Value
Write-Host "Target paths count: $($TargetPaths.Count)"
foreach ($path in $TargetPaths) {
    $resolvedPath = Resolve-PathSafe -Path $path -BaseDir $ScriptDir
    Write-Host "Target: $resolvedPath (exists: $(Test-Path $resolvedPath))"
}