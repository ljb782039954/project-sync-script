# sync_to_target_new.ps1
# 文件同步工具 - PowerShell 版本（重新编写）

param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$RemainingArgs
)

# 解析命令行参数
$FullSyncMode = $false
$PreviewMode = $false
$RequireConfirmation = $false

if ($RemainingArgs) {
    foreach ($arg in $RemainingArgs) {
        switch ($arg) {
            { $_ -eq "--all" -or $_ -eq "-All" -or $_ -eq "-all" } {
                $FullSyncMode = $true
            }
            { $_ -eq "--preview" -or $_ -eq "-Preview" -or $_ -eq "-p" } {
                $PreviewMode = $true
            }
            { $_ -eq "--confirm" -or $_ -eq "-Confirm" -or $_ -eq "-c" } {
                $RequireConfirmation = $true
            }
        }
    }
}

# 获取脚本所在目录
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) {
    $ScriptDir = Get-Location
}

# 读取配置文件
function Read-ConfigFile {
    param([string]$ScriptDir)
    
    $configPath = Join-Path $ScriptDir "config.json"
    if (-not (Test-Path $configPath)) {
        return $null
    }
    
    try {
        $jsonContent = Get-Content -Path $configPath -Encoding UTF8 -Raw
        return $jsonContent | ConvertFrom-Json
    } catch {
        Write-Host "错误: 配置文件格式不正确: $_" -ForegroundColor Red
        return $null
    }
}

# 解析路径
function Resolve-PathSafe {
    param([string]$Path, [string]$BaseDir)
    
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    } else {
        return [System.IO.Path]::GetFullPath((Join-Path $BaseDir $Path))
    }
}

# 获取 Git 变更文件
function Get-GitChangedFiles {
    param([string]$SourceDir)
    
    $ChangedFiles = @()
    $HasGitRepo = $false
    
    try {
        Push-Location $SourceDir
        $GitRoot = git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0) {
            $HasGitRepo = $true
            $GitDiff = git diff --name-status HEAD~1 HEAD 2>$null
            if ($LASTEXITCODE -eq 0) {
                $ChangedFiles = $GitDiff
            }
        }
        Pop-Location
    } catch {
        Write-Host "警告: 无法获取 Git 变更信息" -ForegroundColor Yellow
    }
    
    return @{
        HasGitRepo = $HasGitRepo
        ChangedFiles = $ChangedFiles
    }
}

# 同步函数
function Sync-ToTarget {
    param(
        [string]$SourceDir,
        [string]$TargetDir,
        [bool]$FullSync = $false,
        [bool]$PreviewOnly = $false
    )
    
    Write-Host "`n开始同步到: $TargetDir" -ForegroundColor Cyan
    Write-Host "同步模式: $(if ($FullSync) { '完全同步' } else { '增量同步' })" -ForegroundColor Cyan
    
    # 创建目标目录
    if (-not (Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }
    
    # 创建日志目录
    $SourceLogDir = Join-Path $SourceDir ".syncScript_logs"
    $TargetLogDir = Join-Path $TargetDir ".syncScript_logs"
    
    if (-not (Test-Path $SourceLogDir)) {
        New-Item -ItemType Directory -Path $SourceLogDir -Force | Out-Null
    }
    if (-not (Test-Path $TargetLogDir)) {
        New-Item -ItemType Directory -Path $TargetLogDir -Force | Out-Null
    }
    
    # 生成日志文件名
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $TargetName = Split-Path -Leaf $TargetDir
    $SourceLogFile = Join-Path $SourceLogDir "sync_${TargetName}_${Timestamp}.json"
    $TargetLogFile = Join-Path $TargetLogDir "sync_${Timestamp}.json"
    $TotalLogFile = Join-Path $TargetLogDir "total_sync_log.json"
    
    # 获取 Git 信息
    $GitInfo = Get-GitChangedFiles -SourceDir $SourceDir
    
    # 初始化日志数据
    $LogData = @{
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        sync_mode = if ($FullSync) { "full" } else { "incremental" }
        source_dir = $SourceDir
        target_dir = $TargetDir
        git_repo = $GitInfo.HasGitRepo
        statistics = @{
            added = 0
            modified = 0
            deleted = 0
        }
        files = @{
            added = @()
            modified = @()
            deleted = @()
        }
        duration_ms = 0
        status = "success"
        errors = @()
    }
    
    # 解析变更文件
    $FilesToSync = @()
    $FilesToDelete = @()
    
    if (-not $FullSync -and $GitInfo.ChangedFiles.Count -gt 0) {
        foreach ($Line in $GitInfo.ChangedFiles) {
            if ($Line -match '^([AMD])\s+(.+)') {
                $Status = $Matches[1]
                $FilePath = $Matches[2]
                
                # 排除 syncScript 文件夹
                if ($FilePath -like "syncScript\*" -or $FilePath -like "syncScript/*") {
                    continue
                }
                
                switch ($Status) {
                    'A' {
                        $FilesToSync += $FilePath
                        $LogData.files.added += $FilePath
                        $LogData.statistics.added++
                        Write-Host "[新增] $FilePath" -ForegroundColor Green
                    }
                    'M' {
                        $FilesToSync += $FilePath
                        $LogData.files.modified += $FilePath
                        $LogData.statistics.modified++
                        Write-Host "[修改] $FilePath" -ForegroundColor Yellow
                    }
                    'D' {
                        $FilesToDelete += $FilePath
                        $LogData.files.deleted += $FilePath
                        $LogData.statistics.deleted++
                        Write-Host "[删除] $FilePath" -ForegroundColor Red
                    }
                }
            }
        }
    }
    
    # 如果是预览模式，只生成日志不执行同步
    if ($PreviewOnly) {
        Write-Host "预览模式：不执行实际同步操作" -ForegroundColor Yellow
        $LogData.status = "preview"
    } else {
        # 执行实际同步
        if ($FullSync) {
            Write-Host "执行完全同步..." -ForegroundColor Green
            # 这里可以添加 robocopy 或其他同步逻辑
        } else {
            Write-Host "执行增量同步..." -ForegroundColor Green
            # 同步文件
            foreach ($FilePath in $FilesToSync) {
                $SourceFile = Join-Path $SourceDir $FilePath
                $TargetFile = Join-Path $TargetDir $FilePath
                $TargetFileDir = Split-Path -Parent $TargetFile
                
                if (-not (Test-Path $TargetFileDir)) {
                    New-Item -ItemType Directory -Path $TargetFileDir -Force | Out-Null
                }
                
                if (Test-Path $SourceFile) {
                    Copy-Item -Path $SourceFile -Destination $TargetFile -Force
                    Write-Host "[已同步] $FilePath" -ForegroundColor Green
                }
            }
            
            # 删除文件
            foreach ($FilePath in $FilesToDelete) {
                $TargetFile = Join-Path $TargetDir $FilePath
                if (Test-Path $TargetFile) {
                    Remove-Item -Path $TargetFile -Force -Recurse
                    Write-Host "[已删除] $FilePath" -ForegroundColor Red
                }
            }
        }
    }
    
    # 写入日志文件
    try {
        $LogJson = $LogData | ConvertTo-Json -Depth 10 -Compress:$false
        [System.IO.File]::WriteAllText($SourceLogFile, $LogJson, [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($TargetLogFile, $LogJson, [System.Text.Encoding]::UTF8)
        
        # 更新统计日志
        Update-TotalSyncLog -TotalLogFile $TotalLogFile -LogData $LogData
        
        Write-Host "日志已保存: $SourceLogFile" -ForegroundColor Green
    } catch {
        Write-Host "警告: 无法写入日志文件: $_" -ForegroundColor Yellow
    }
    
    return $true
}

# 更新统计日志
function Update-TotalSyncLog {
    param(
        [string]$TotalLogFile,
        [object]$LogData
    )
    
    try {
        $totalLog = @{
            last_updated = $LogData.timestamp
            total_syncs = 1
            summary = @{
                total_files_added = $LogData.statistics.added
                total_files_modified = $LogData.statistics.modified
                total_files_deleted = $LogData.statistics.deleted
            }
            all_files = @{
                added = @($LogData.files.added)
                modified = @($LogData.files.modified)
                deleted = @($LogData.files.deleted)
            }
        }
        
        # 如果文件已存在，合并数据
        if (Test-Path $TotalLogFile) {
            $existingLog = Get-Content -Path $TotalLogFile -Encoding UTF8 -Raw | ConvertFrom-Json
            
            $totalLog.total_syncs = $existingLog.total_syncs + 1
            $totalLog.summary.total_files_added = $existingLog.summary.total_files_added + $LogData.statistics.added
            $totalLog.summary.total_files_modified = $existingLog.summary.total_files_modified + $LogData.statistics.modified
            $totalLog.summary.total_files_deleted = $existingLog.summary.total_files_deleted + $LogData.statistics.deleted
            
            # 合并文件列表
            $totalLog.all_files.added = @($existingLog.all_files.added) + @($LogData.files.added)
            $totalLog.all_files.modified = @($existingLog.all_files.modified) + @($LogData.files.modified)
            $totalLog.all_files.deleted = @($existingLog.all_files.deleted) + @($LogData.files.deleted)
        }
        
        $totalLogJson = $totalLog | ConvertTo-Json -Depth 10 -Compress:$false
        [System.IO.File]::WriteAllText($TotalLogFile, $totalLogJson, [System.Text.Encoding]::UTF8)
        
    } catch {
        Write-Host "警告: 无法更新统计日志: $_" -ForegroundColor Yellow
    }
}

# 主程序
Write-Host "文件同步工具 - PowerShell 版本" -ForegroundColor Cyan

# 读取配置
$config = Read-ConfigFile -ScriptDir $ScriptDir
if (-not $config) {
    Write-Host "错误: 无法读取配置文件" -ForegroundColor Red
    exit 1
}

# 解析路径
$SourceDir = Resolve-PathSafe -Path $config.source_path -BaseDir $ScriptDir
if (-not (Test-Path $SourceDir)) {
    Write-Host "错误: 源目录不存在: $SourceDir" -ForegroundColor Red
    exit 1
}

$TargetPaths = @()
$config.target_paths.PSObject.Properties | ForEach-Object {
    $TargetPaths += Resolve-PathSafe -Path $_.Value -BaseDir $ScriptDir
}

if ($TargetPaths.Count -eq 0) {
    Write-Host "错误: 没有找到目标路径" -ForegroundColor Red
    exit 1
}

Write-Host "源目录: $SourceDir" -ForegroundColor Green
Write-Host "找到 $($TargetPaths.Count) 个目标路径" -ForegroundColor Green

# 应用命令行参数
$UsePreview = $PreviewMode -or $config.sync_options.preview_mode
$UseConfirm = $RequireConfirmation -or $config.sync_options.require_confirmation

# 执行同步
$SuccessCount = 0
foreach ($TargetPath in $TargetPaths) {
    if (Sync-ToTarget -SourceDir $SourceDir -TargetDir $TargetPath -FullSync $FullSyncMode -PreviewOnly $UsePreview) {
        $SuccessCount++
    }
}

Write-Host ""
Write-Host "Sync completed! Success: $SuccessCount" -ForegroundColor Green