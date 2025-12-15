# sync_to_target.ps1
# 文件同步工具 - PowerShell 版本
# 用法: 
#   1. 使用配置文件: .\sync_to_target.ps1
#   2. 使用命令行参数: .\sync_to_target.ps1 -TargetPath "路径"

param(
    [Parameter(Mandatory=$false)]
    [string]$TargetPath,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = ""
)

# 获取脚本所在目录
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) {
    $ScriptDir = Get-Location
}

# 读取 JSON 配置文件
function Read-JsonConfigFile {
    param([string]$ConfigPath)
    
    try {
        $jsonContent = Get-Content -Path $ConfigPath -Encoding UTF8 -Raw
        $jsonObj = $jsonContent | ConvertFrom-Json
        
        $config = @{
            SourcePath = ""
            TargetPaths = @()
        }
        
        # 解析 source_path
        if ($jsonObj.source_path) {
            $config.SourcePath = $jsonObj.source_path
        }
        
        # 解析 target_paths（支持对象和数组两种格式）
        if ($jsonObj.target_paths) {
            if ($jsonObj.target_paths -is [System.Array]) {
                # 数组格式: "target_paths": ["path1", "path2"]
                $config.TargetPaths = $jsonObj.target_paths
            } elseif ($jsonObj.target_paths -is [PSCustomObject]) {
                # 对象格式: "target_paths": {"key": "path1", "key2": "path2"}
                $config.TargetPaths = $jsonObj.target_paths.PSObject.Properties.Value
            }
        }
        
        return $config
    } catch {
        Write-Host "错误: JSON 配置文件格式不正确: $_" -ForegroundColor Red
        return $null
    }
}

# 读取配置文件（JSON 格式）
function Read-ConfigFile {
    param([string]$ScriptDir)
    
    $jsonConfigPath = Join-Path $ScriptDir "config.json"
    if (Test-Path $jsonConfigPath) {
        Write-Host "读取配置文件: $jsonConfigPath" -ForegroundColor Yellow
        return Read-JsonConfigFile -ConfigPath $jsonConfigPath
    }
    
    return $null
}

# 解析路径（支持相对路径和绝对路径）
function Resolve-PathSafe {
    param([string]$Path, [string]$BaseDir)
    
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    } else {
        return [System.IO.Path]::GetFullPath((Join-Path $BaseDir $Path))
    }
}

# 同步到单个目标目录的函数
function Sync-ToTarget {
    param(
        [string]$SourceDir,
        [string]$TargetDir
    )
    
    Write-Host "`n开始同步到: $TargetDir" -ForegroundColor Cyan
    
    # 检查目标目录是否存在
    if (-not (Test-Path $TargetDir)) {
        Write-Host "错误: 目标目录不存在: $TargetDir" -ForegroundColor Red
        Write-Host "提示: 请先创建目标目录，或检查路径是否正确" -ForegroundColor Yellow
        return $false
    }
    
    # 创建日志目录
    $LogDir = Join-Path $SourceDir ".sync_logs"
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir | Out-Null
    }
    
    # 生成日志文件名（带时间戳）
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $LogFile = Join-Path $LogDir "sync_$(Split-Path -Leaf $TargetDir)_$Timestamp.txt"

    # 获取 Git 变更的文件（相对于仓库根目录）
    $ChangedFiles = @()
    $HasGitRepo = $false
    
    try {
        # 检查是否在 Git 仓库中
        Push-Location $SourceDir
        $GitRoot = git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0) {
            $HasGitRepo = $true
            
            # 获取最后一次 commit 的变更文件
            $GitDiff = git diff --name-status HEAD~1 HEAD 2>$null
            if ($LASTEXITCODE -ne 0) {
                # 如果没有上一个 commit，获取所有已跟踪的文件
                $GitFiles = git ls-files 2>$null
                if ($GitFiles) {
                    $ChangedFiles = $GitFiles | ForEach-Object { "A`t$_" }
                }
            } else {
                $ChangedFiles = $GitDiff
            }
        }
        Pop-Location
    } catch {
        Write-Host "警告: 无法获取 Git 变更信息，将同步所有文件" -ForegroundColor Yellow
    }
    
    # 记录同步开始
    $LogContent = @()
    $LogContent += "=" * 80
    $LogContent += "同步时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $LogContent += "原始项目: $SourceDir"
    $LogContent += "目标项目: $TargetDir"
    $LogContent += "Git 仓库: $(if ($HasGitRepo) { '是' } else { '否' })"
    $LogContent += "=" * 80
    $LogContent += ""
    
    # 统计变量
    $AddedCount = 0
    $ModifiedCount = 0
    $DeletedCount = 0
    
    # 解析 Git 变更并记录
    $FilesToSync = @()
    $FilesToDelete = @()
    
    if ($ChangedFiles.Count -gt 0) {
        foreach ($Line in $ChangedFiles) {
            if ($Line -match '^([AMD])\s+(.+)$') {
                $Status = $Matches[1]
                $FilePath = $Matches[2]
                
                $SourceFile = Join-Path $SourceDir $FilePath
                
                switch ($Status) {
                    'A' {
                        # 新增文件
                        if (Test-Path $SourceFile) {
                            $FilesToSync += $FilePath
                            $AddedCount++
                            $LogContent += "[新增] $FilePath"
                        }
                    }
                    'M' {
                        # 修改文件
                        if (Test-Path $SourceFile) {
                            $FilesToSync += $FilePath
                            $ModifiedCount++
                            $LogContent += "[修改] $FilePath"
                        }
                    }
                    'D' {
                        # 删除文件
                        $FilesToDelete += $FilePath
                        $DeletedCount++
                        $LogContent += "[删除] $FilePath"
                    }
                }
            }
        }
    } else {
        # 如果没有 Git 变更信息，记录全量同步
        Write-Host "未检测到 Git 变更，将同步所有文件..." -ForegroundColor Yellow
        $LogContent += "[全量同步] 未检测到 Git 变更，同步所有文件"
    }
    
    # 执行文件同步
    $LogContent += ""
    $LogContent += "开始同步文件..."
    $LogContent += ""
    
    # 使用 robocopy 进行同步（排除 .git 和同步日志目录）
    $RobocopyArgs = @(
        $SourceDir,
        $TargetDir,
        "/E",           # 包含子目录
        "/XD", ".git", ".sync_logs",  # 排除目录
        "/XF", "sync_to_target.ps1", "sync_to_target.sh", "config.json",  # 排除脚本和配置文件
        "/NP",          # 不显示进度百分比
        "/NFL",         # 不列出文件
        "/NDL",         # 不列出目录
        "/NJH",         # 不显示作业标头
        "/NJS"          # 不显示作业摘要
    )
    
    $RobocopyResult = & robocopy @RobocopyArgs 2>&1 | Out-Null
    $RobocopyExitCode = $LASTEXITCODE
    
    # robocopy 返回码: 0-7 表示成功，8+ 表示错误
    if ($RobocopyExitCode -ge 8) {
        Write-Host "警告: robocopy 同步过程中出现错误 (返回码: $RobocopyExitCode)" -ForegroundColor Yellow
        $LogContent += "警告: robocopy 返回码: $RobocopyExitCode"
    } else {
        $LogContent += "文件同步完成 (robocopy 返回码: $RobocopyExitCode)"
    }
    
    # 处理删除的文件
    foreach ($FilePath in $FilesToDelete) {
        $TargetFile = Join-Path $TargetDir $FilePath
        if (Test-Path $TargetFile) {
            try {
                Remove-Item -Path $TargetFile -Force -Recurse -ErrorAction Stop
                $LogContent += "[已删除] $FilePath"
            } catch {
                $LogContent += "[删除失败] $FilePath - 错误: $_"
                Write-Host "警告: 无法删除文件 $FilePath" -ForegroundColor Yellow
            }
        } else {
            $LogContent += "[跳过删除] $FilePath - 文件不存在于目标目录"
        }
    }
    
    # 记录同步结果
    $LogContent += ""
    $LogContent += "=" * 80
    $LogContent += "同步完成"
    $LogContent += "新增文件: $AddedCount"
    $LogContent += "修改文件: $ModifiedCount"
    $LogContent += "删除文件: $DeletedCount"
    $LogContent += "日志文件: $LogFile"
    $LogContent += "=" * 80
    
    # 写入日志文件（使用 UTF-8 with BOM 编码）
    $Utf8WithBom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllLines($LogFile, $LogContent, $Utf8WithBom)
    
    # 显示结果
    Write-Host "同步完成!" -ForegroundColor Green
    Write-Host "原始项目: $SourceDir" -ForegroundColor Cyan
    Write-Host "目标项目: $TargetDir" -ForegroundColor Cyan
    Write-Host "新增: $AddedCount | 修改: $ModifiedCount | 删除: $DeletedCount" -ForegroundColor Cyan
    Write-Host "日志文件: $LogFile" -ForegroundColor Yellow
    
    return $true
}

# ============================================================================
# 主程序逻辑
# ============================================================================

$SourceDir = ""
$TargetPaths = @()

# 如果提供了命令行参数，优先使用命令行参数
if ($TargetPath) {
    Write-Host "使用命令行参数模式" -ForegroundColor Yellow
    $SourceDir = $ScriptDir
    $TargetPaths = @($TargetPath)
} else {
    # 读取配置文件（自动检测 JSON 或 TXT）
    $config = Read-ConfigFile -ScriptDir $ScriptDir
    
    if ($null -eq $config -or [string]::IsNullOrWhiteSpace($config.SourcePath)) {
        Write-Host "错误: 配置文件不存在或格式不正确" -ForegroundColor Red
        Write-Host "提示: 请创建 config.json 文件" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "JSON 格式示例 (config.json):" -ForegroundColor Cyan
        Write-Host '{' -ForegroundColor Gray
        Write-Host '  "source_path": "原始项目路径",' -ForegroundColor Gray
        Write-Host '  "target_paths": {' -ForegroundColor Gray
        Write-Host '    "default": "目标项目路径1",' -ForegroundColor Gray
        Write-Host '    "version2": "目标项目路径2"' -ForegroundColor Gray
        Write-Host '  }' -ForegroundColor Gray
        Write-Host '}' -ForegroundColor Gray
        Write-Host ""
        Write-Host "或使用数组格式:" -ForegroundColor Cyan
        Write-Host '{' -ForegroundColor Gray
        Write-Host '  "source_path": "原始项目路径",' -ForegroundColor Gray
        Write-Host '  "target_paths": [' -ForegroundColor Gray
        Write-Host '    "目标项目路径1",' -ForegroundColor Gray
        Write-Host '    "目标项目路径2"' -ForegroundColor Gray
        Write-Host '  ]' -ForegroundColor Gray
        Write-Host '}' -ForegroundColor Gray
        exit 1
    }
    
    # 解析源路径
    $SourceDir = Resolve-PathSafe -Path $config.SourcePath -BaseDir $ScriptDir
    
    if (-not (Test-Path $SourceDir)) {
        Write-Host "错误: 原始项目目录不存在: $SourceDir" -ForegroundColor Red
        exit 1
    }
    
    # 解析目标路径
    $TargetPaths = $config.TargetPaths | ForEach-Object {
        Resolve-PathSafe -Path $_ -BaseDir $ScriptDir
    }
    
    if ($TargetPaths.Count -eq 0) {
        Write-Host "错误: 配置文件中没有找到目标路径 (path_to_*)" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "找到 $($TargetPaths.Count) 个目标路径" -ForegroundColor Green
}

# 执行同步到所有目标路径
$SuccessCount = 0
$FailCount = 0

foreach ($TargetPath in $TargetPaths) {
    if (Sync-ToTarget -SourceDir $SourceDir -TargetDir $TargetPath) {
        $SuccessCount++
    } else {
        $FailCount++
    }
}

# 显示总结
Write-Host ""
$separator = "=" * 80
Write-Host $separator -ForegroundColor Cyan
Write-Host "同步总结" -ForegroundColor Cyan
Write-Host "成功: $SuccessCount | 失败: $FailCount" -ForegroundColor $(if ($FailCount -eq 0) { "Green" } else { "Yellow" })
Write-Host $separator -ForegroundColor Cyan
Write-Host ""

