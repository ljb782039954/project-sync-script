# sync_to_target.ps1
# 文件同步工具 - PowerShell 版本
# 用法: 
#   1. 增量同步（默认）: .\sync_to_target.ps1
#   2. 完全同步: .\sync_to_target.ps1 --all 或 .\sync_to_target.ps1 -All

param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$RemainingArgs
)

# 手动解析命令行参数
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

# 检查依赖工具
function Test-Dependencies {
    $missingDeps = @()
    
    # 检查 Git
    try {
        $null = git --version 2>$null
    } catch {
        $missingDeps += "Git"
    }
    
    # 检查 robocopy（Windows 内置，通常都有）
    try {
        $null = robocopy /? 2>$null
    } catch {
        $missingDeps += "robocopy"
    }
    
    if ($missingDeps.Count -gt 0) {
        Write-Host "错误: 缺少必要的工具: $($missingDeps -join ', ')" -ForegroundColor Red
        Write-Host "请安装这些工具后重试" -ForegroundColor Yellow
        return $false
    }
    
    return $true
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
            ExcludePatterns = @()
            LogRetention = @{
                MaxLogs = 30
                AutoCleanup = $true
            }
            SyncOptions = @{
                PreviewMode = $false
                RequireConfirmation = $false
            }
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
        
        # 解析 exclude_patterns（排除模式，类似 .gitignore）
        if ($jsonObj.exclude_patterns) {
            if ($jsonObj.exclude_patterns -is [System.Array]) {
                $config.ExcludePatterns = $jsonObj.exclude_patterns
            }
        }
        
        # 解析 log_retention
        if ($jsonObj.log_retention) {
            if ($jsonObj.log_retention.max_logs) {
                $config.LogRetention.MaxLogs = $jsonObj.log_retention.max_logs
            }
            if ($null -ne $jsonObj.log_retention.auto_cleanup) {
                $config.LogRetention.AutoCleanup = $jsonObj.log_retention.auto_cleanup
            }
        }
        
        # 解析 sync_options
        if ($jsonObj.sync_options) {
            if ($null -ne $jsonObj.sync_options.preview_mode) {
                $config.SyncOptions.PreviewMode = $jsonObj.sync_options.preview_mode
            }
            if ($null -ne $jsonObj.sync_options.require_confirmation) {
                $config.SyncOptions.RequireConfirmation = $jsonObj.sync_options.require_confirmation
            }
        }
        
        return $config
    } catch {
        Write-Host "错误: JSON 配置文件格式不正确: $_" -ForegroundColor Red
        return $null
    }
}

# 验证配置文件
function Test-ConfigFile {
    param([object]$Config)
    
    $errors = @()
    
    if ([string]::IsNullOrWhiteSpace($Config.SourcePath)) {
        $errors += "source_path 不能为空"
    }
    
    if ($Config.TargetPaths.Count -eq 0) {
        $errors += "至少需要配置一个目标路径"
    }
    
    # 检查源路径是否存在
    if (-not [string]::IsNullOrWhiteSpace($Config.SourcePath)) {
        $sourcePath = Resolve-PathSafe -Path $Config.SourcePath -BaseDir $PSScriptRoot
        if (-not (Test-Path $sourcePath)) {
            $errors += "源路径不存在: $sourcePath"
        }
    }
    
    # 验证日志保留配置
    if ($Config.LogRetention.MaxLogs -lt 1) {
        $errors += "max_logs 必须大于 0"
    }
    
    if ($errors.Count -gt 0) {
        Write-Host "配置文件错误:" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        return $false
    }
    
    return $true
}

# 清理旧日志文件
function Clear-OldLogs {
    param(
        [string]$LogDir,
        [int]$MaxLogs,
        [bool]$AutoCleanup
    )
    
    if (-not $AutoCleanup -or -not (Test-Path $LogDir)) {
        return
    }
    
    try {
        $logFiles = Get-ChildItem -Path $LogDir -Filter "sync_*.txt" | Sort-Object CreationTime -Descending
        
        if ($logFiles.Count -gt $MaxLogs) {
            $filesToDelete = $logFiles | Select-Object -Skip $MaxLogs
            $deletedCount = 0
            
            foreach ($file in $filesToDelete) {
                try {
                    Remove-Item -Path $file.FullName -Force
                    $deletedCount++
                } catch {
                    Write-Host "警告: 无法删除日志文件 $($file.Name)" -ForegroundColor Yellow
                }
            }
            
            if ($deletedCount -gt 0) {
                Write-Host "已清理 $deletedCount 个旧日志文件" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "警告: 清理日志文件时出错: $_" -ForegroundColor Yellow
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

# 安装 Git Hook
function Install-GitHook {
    param([string]$ScriptDir, [string]$SourceDir)
    
    $HookTemplatePath = Join-Path $ScriptDir ".git_hooks\post-commit"
    $GitHooksDir = Join-Path $SourceDir ".git\hooks"
    $HookPath = Join-Path $GitHooksDir "post-commit"
    
    if (-not (Test-Path $HookTemplatePath)) {
        return $false
    }
    
    if (-not (Test-Path $GitHooksDir)) {
        Write-Host "警告: .git\hooks 目录不存在，跳过 Git Hook 安装" -ForegroundColor Yellow
        return $false
    }
    
    # 检查是否需要更新 Hook
    $NeedInstall = $false
    if (-not (Test-Path $HookPath)) {
        $NeedInstall = $true
    } else {
        $TemplateHash = (Get-FileHash -Path $HookTemplatePath -Algorithm MD5).Hash
        $HookHash = (Get-FileHash -Path $HookPath -Algorithm MD5).Hash
        if ($TemplateHash -ne $HookHash) {
            $NeedInstall = $true
        }
    }
    
    if ($NeedInstall) {
        Copy-Item -Path $HookTemplatePath -Destination $HookPath -Force
        Write-Host "Git Hook 已安装/更新: $HookPath" -ForegroundColor Green
        return $true
    }
    
    return $false
}

# 获取 Git 变更文件列表
function Get-GitChangedFiles {
    param([string]$SourceDir)
    
    $ChangedFiles = @()
    $HasGitRepo = $false
    
    try {
        Push-Location $SourceDir
        $GitRoot = git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0) {
            $HasGitRepo = $true
            
            # 获取最后一次 commit 的变更文件
            $GitDiff = git diff --name-status HEAD~1 HEAD 2>$null
            if ($LASTEXITCODE -ne 0) {
                # 如果没有上一个 commit，返回空数组（表示首次提交）
                $ChangedFiles = @()
            } else {
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

# 读取 .gitignore 文件获取排除规则
function Get-GitIgnorePatterns {
    param([string]$SourceDir)
    
    $GitIgnorePath = Join-Path $SourceDir ".gitignore"
    $Patterns = @()
    
    if (Test-Path $GitIgnorePath) {
        $Lines = Get-Content -Path $GitIgnorePath -Encoding UTF8
        foreach ($Line in $Lines) {
            $Line = $Line.Trim()
            if ($Line -and -not $Line.StartsWith("#")) {
                $Patterns += $Line
            }
        }
    }
    
    return $Patterns
}

# 检查文件路径是否匹配排除模式
function Test-ExcludePattern {
    param(
        [string]$FilePath,
        [string[]]$ExcludePatterns
    )
    
    foreach ($Pattern in $ExcludePatterns) {
        # 支持通配符匹配
        # 如果模式以 / 或 \ 开头，表示从根目录匹配
        # 如果模式包含 / 或 \，表示目录匹配
        # 否则表示文件名匹配
        
        $NormalizedPattern = $Pattern.Trim()
        if ([string]::IsNullOrWhiteSpace($NormalizedPattern)) {
            continue
        }
        
        # 转换为 Windows 路径分隔符
        $NormalizedPattern = $NormalizedPattern.Replace('/', '\')
        $NormalizedFilePath = $FilePath.Replace('/', '\')
        
        # 如果模式以 \ 开头，从根目录匹配
        if ($NormalizedPattern.StartsWith('\')) {
            $NormalizedPattern = $NormalizedPattern.Substring(1)
            if ($NormalizedFilePath -like "*\$NormalizedPattern" -or $NormalizedFilePath -like "$NormalizedPattern*") {
                return $true
            }
        }
        # 如果模式包含 \，表示路径匹配
        elseif ($NormalizedPattern.Contains('\')) {
            if ($NormalizedFilePath -like "*\$NormalizedPattern" -or $NormalizedFilePath -like "*\$NormalizedPattern\*" -or $NormalizedFilePath -eq $NormalizedPattern) {
                return $true
            }
        }
        # 否则匹配文件名或目录名
        else {
            $FileName = Split-Path -Leaf $NormalizedFilePath
            if ($FileName -like $NormalizedPattern -or $NormalizedFilePath -like "*\$NormalizedPattern" -or $NormalizedFilePath -like "*\$NormalizedPattern\*") {
                return $true
            }
        }
    }
    
    return $false
}

# 显示同步预览
function Show-SyncPreview {
    param(
        [string]$SourceDir,
        [string]$TargetDir,
        [bool]$FullSync,
        [array]$FilesToSync,
        [array]$FilesToDelete,
        [int]$AddedCount,
        [int]$ModifiedCount,
        [int]$DeletedCount
    )
    
    Write-Host "`n" + "=" * 60 -ForegroundColor Cyan
    Write-Host "同步预览" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host "源目录: $SourceDir" -ForegroundColor Yellow
    Write-Host "目标目录: $TargetDir" -ForegroundColor Yellow
    Write-Host "同步模式: $(if ($FullSync) { '完全同步' } else { '增量同步' })" -ForegroundColor Yellow
    Write-Host ""
    
    if ($FullSync) {
        Write-Host "将执行完全同步（所有文件）" -ForegroundColor Green
    } else {
        Write-Host "统计信息:" -ForegroundColor White
        Write-Host "  新增文件: $AddedCount" -ForegroundColor Green
        Write-Host "  修改文件: $ModifiedCount" -ForegroundColor Yellow
        Write-Host "  删除文件: $DeletedCount" -ForegroundColor Red
        
        if ($FilesToSync.Count -gt 0) {
            Write-Host "`n将同步的文件:" -ForegroundColor White
            $FilesToSync | ForEach-Object { Write-Host "  + $_" -ForegroundColor Green }
        }
        
        if ($FilesToDelete.Count -gt 0) {
            Write-Host "`n将删除的文件:" -ForegroundColor White
            $FilesToDelete | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        }
        
        if ($FilesToSync.Count -eq 0 -and $FilesToDelete.Count -eq 0) {
            Write-Host "没有文件需要同步" -ForegroundColor Gray
        }
    }
    
    Write-Host "`n" + "=" * 60 -ForegroundColor Cyan
}

# 用户确认函数
function Get-UserConfirmation {
    param([string]$Message = "是否继续执行同步？")
    
    do {
        $response = Read-Host "$Message (y/n)"
        $response = $response.ToLower().Trim()
        
        if ($response -eq 'y' -or $response -eq 'yes') {
            return $true
        } elseif ($response -eq 'n' -or $response -eq 'no') {
            return $false
        } else {
            Write-Host "请输入 y 或 n" -ForegroundColor Yellow
        }
    } while ($true)
}

# 同步到单个目标目录的函数
function Sync-ToTarget {
    param(
        [string]$SourceDir,
        [string]$TargetDir,
        [bool]$FullSync = $false,
        [string[]]$ExcludePatterns = @(),
        [object]$SyncOptions = @{}
    )
    
    Write-Host "`n开始同步到: $TargetDir" -ForegroundColor Cyan
    Write-Host "同步模式: $(if ($FullSync) { '完全同步' } else { '增量同步' })" -ForegroundColor Cyan
    
    # 自动创建目标目录（如果不存在）
    if (-not (Test-Path $TargetDir)) {
        Write-Host "目标目录不存在，正在创建: $TargetDir" -ForegroundColor Yellow
        try {
            New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
            Write-Host "目标目录创建成功" -ForegroundColor Green
        } catch {
            Write-Host "错误: 无法创建目标目录: $_" -ForegroundColor Red
            return $false
        }
    }
    
    # 创建源项目日志目录
    $SourceLogDir = Join-Path $SourceDir ".syncScript_logs"
    if (-not (Test-Path $SourceLogDir)) {
        New-Item -ItemType Directory -Path $SourceLogDir -Force | Out-Null
    }
    
    # 创建目标项目日志目录
    $TargetLogDir = Join-Path $TargetDir ".syncScript_logs"
    if (-not (Test-Path $TargetLogDir)) {
        New-Item -ItemType Directory -Path $TargetLogDir -Force | Out-Null
    }
    
    # 生成日志文件名（带时间戳）
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $TargetName = Split-Path -Leaf $TargetDir
    $SourceLogFile = Join-Path $SourceLogDir "sync_${TargetName}_${Timestamp}.txt"
    $TargetLogFile = Join-Path $TargetLogDir "sync_${Timestamp}.txt"
    
    # 获取 Git 信息
    $GitInfo = Get-GitChangedFiles -SourceDir $SourceDir
    $HasGitRepo = $GitInfo.HasGitRepo
    $ChangedFiles = $GitInfo.ChangedFiles
    
    # 记录同步开始
    $LogContent = @()
    $LogContent += "=" * 80
    $LogContent += "同步时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $LogContent += "同步模式: $(if ($FullSync) { '完全同步' } else { '增量同步' })"
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
    
    if ($FullSync) {
        # 完全同步模式：同步所有文件
        $LogContent += "[完全同步] 同步所有文件（排除 syncScript、.git、.syncScript_logs 和 .gitignore 中的文件）"
        $LogContent += ""
    } else {
        # 增量同步模式：只同步 Git 变更的文件
        if ($ChangedFiles.Count -gt 0) {
            foreach ($Line in $ChangedFiles) {
                if ($Line -match '^([AMD])\s+(.+)$') {
                    $Status = $Matches[1]
                    $FilePath = $Matches[2]
                    
                    # 排除 syncScript 文件夹
                    if ($FilePath -like "syncScript\*" -or $FilePath -like "syncScript/*") {
                        continue
                    }
                    
                    # 检查是否匹配配置的排除模式
                    if (Test-ExcludePattern -FilePath $FilePath -ExcludePatterns $ExcludePatterns) {
                        $LogContent += "[跳过] $FilePath (匹配排除模式)"
                        continue
                    }
                    
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
            if ($HasGitRepo) {
                $LogContent += "[增量同步] 未检测到 Git 变更"
            } else {
                $LogContent += "[增量同步] 当前目录不是 Git 仓库，无法进行增量同步"
            }
        }
    }
    
    # 显示预览（如果启用）
    if ($SyncOptions.PreviewMode -or $SyncOptions.RequireConfirmation) {
        Show-SyncPreview -SourceDir $SourceDir -TargetDir $TargetDir -FullSync $FullSync -FilesToSync $FilesToSync -FilesToDelete $FilesToDelete -AddedCount $AddedCount -ModifiedCount $ModifiedCount -DeletedCount $DeletedCount
        
        if ($SyncOptions.PreviewMode) {
            Write-Host "预览模式：不执行实际同步操作" -ForegroundColor Yellow
            return $true
        }
        
        if ($SyncOptions.RequireConfirmation) {
            if (-not (Get-UserConfirmation)) {
                Write-Host "用户取消同步操作" -ForegroundColor Yellow
                return $true
            }
        }
    }
    
    # 执行文件同步
    $LogContent += ""
    $LogContent += "开始同步文件..."
    $LogContent += ""
    
    # 构建 robocopy 排除参数
    $ExcludeDirs = @(".git", ".syncScript_logs", "syncScript")
    $ExcludeFiles = @()
    
    # 读取 .gitignore 中的排除规则
    $GitIgnorePatterns = Get-GitIgnorePatterns -SourceDir $SourceDir
    foreach ($Pattern in $GitIgnorePatterns) {
        if ($Pattern -like "*\*" -or $Pattern -like "*/*") {
            # 目录模式
            $ExcludeDirs += $Pattern.TrimStart('/').TrimStart('\')
        } else {
            # 文件模式
            $ExcludeFiles += $Pattern
        }
    }
    
    # 添加配置中的排除模式
    foreach ($Pattern in $ExcludePatterns) {
        $NormalizedPattern = $Pattern.Trim().Replace('/', '\')
        if ([string]::IsNullOrWhiteSpace($NormalizedPattern)) {
            continue
        }
        
        # 判断是目录还是文件模式
        if ($NormalizedPattern.EndsWith('\') -or $NormalizedPattern.Contains('\') -or $NormalizedPattern -like "*/") {
            # 目录模式
            $DirPattern = $NormalizedPattern.TrimEnd('\').TrimEnd('/')
            if ($DirPattern -and $ExcludeDirs -notcontains $DirPattern) {
                $ExcludeDirs += $DirPattern
            }
        } else {
            # 文件模式（通配符）
            if ($ExcludeFiles -notcontains $NormalizedPattern) {
                $ExcludeFiles += $NormalizedPattern
            }
        }
    }
    
    # 使用 robocopy 进行同步
    $RobocopyArgs = @(
        $SourceDir,
        $TargetDir,
        "/E",           # 包含子目录
        "/NP",          # 不显示进度百分比
        "/NFL",         # 不列出文件
        "/NDL",         # 不列出目录
        "/NJH",         # 不显示作业标头
        "/NJS"          # 不显示作业摘要
    )
    
    # 添加排除目录
    if ($ExcludeDirs.Count -gt 0) {
        $RobocopyArgs += "/XD"
        $RobocopyArgs += $ExcludeDirs
    }
    
    # 添加排除文件
    if ($ExcludeFiles.Count -gt 0) {
        $RobocopyArgs += "/XF"
        $RobocopyArgs += $ExcludeFiles
    }
    
    # 如果是增量同步且有指定文件，需要特殊处理
    if (-not $FullSync -and $FilesToSync.Count -gt 0) {
        # robocopy 不支持只同步指定文件列表，所以我们需要手动复制
        foreach ($FilePath in $FilesToSync) {
            $SourceFile = Join-Path $SourceDir $FilePath
            $TargetFile = Join-Path $TargetDir $FilePath
            $TargetFileDir = Split-Path -Parent $TargetFile
            
            if (-not (Test-Path $TargetFileDir)) {
                New-Item -ItemType Directory -Path $TargetFileDir -Force | Out-Null
            }
            
            if (Test-Path $SourceFile) {
                Copy-Item -Path $SourceFile -Destination $TargetFile -Force
                $LogContent += "[已同步] $FilePath"
            }
        }
        $LogContent += "增量文件同步完成"
    } else {
        # 完全同步或全量同步
        $RobocopyResult = & robocopy @RobocopyArgs 2>&1 | Out-Null
        $RobocopyExitCode = $LASTEXITCODE
        
        # robocopy 返回码: 0-7 表示成功，8+ 表示错误
        if ($RobocopyExitCode -ge 8) {
            Write-Host "警告: robocopy 同步过程中出现错误 (返回码: $RobocopyExitCode)" -ForegroundColor Yellow
            $LogContent += "警告: robocopy 返回码: $RobocopyExitCode"
        } else {
            $LogContent += "文件同步完成 (robocopy 返回码: $RobocopyExitCode)"
        }
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
    $LogContent += "源项目日志: $SourceLogFile"
    $LogContent += "目标项目日志: $TargetLogFile"
    $LogContent += "=" * 80
    
    # 写入日志文件（使用 UTF-8 with BOM 编码）
    $Utf8WithBom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllLines($SourceLogFile, $LogContent, $Utf8WithBom)
    [System.IO.File]::WriteAllLines($TargetLogFile, $LogContent, $Utf8WithBom)
    
    # 清理旧日志文件
    if ($SyncOptions.LogRetention) {
        Clear-OldLogs -LogDir $SourceLogDir -MaxLogs $SyncOptions.LogRetention.MaxLogs -AutoCleanup $SyncOptions.LogRetention.AutoCleanup
        Clear-OldLogs -LogDir $TargetLogDir -MaxLogs $SyncOptions.LogRetention.MaxLogs -AutoCleanup $SyncOptions.LogRetention.AutoCleanup
    }
    
    # 显示结果
    Write-Host "同步完成!" -ForegroundColor Green
    Write-Host "原始项目: $SourceDir" -ForegroundColor Cyan
    Write-Host "目标项目: $TargetDir" -ForegroundColor Cyan
    Write-Host "新增: $AddedCount | 修改: $ModifiedCount | 删除: $DeletedCount" -ForegroundColor Cyan
    Write-Host "源项目日志: $SourceLogFile" -ForegroundColor Yellow
    Write-Host "目标项目日志: $TargetLogFile" -ForegroundColor Yellow
    
    return $true
}

# ============================================================================
# 主程序逻辑
# ============================================================================

# 检查依赖工具
if (-not (Test-Dependencies)) {
    exit 1
}

# 读取配置文件
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
    Write-Host '  },' -ForegroundColor Gray
    Write-Host '  "log_retention": {' -ForegroundColor Gray
    Write-Host '    "max_logs": 30,' -ForegroundColor Gray
    Write-Host '    "auto_cleanup": true' -ForegroundColor Gray
    Write-Host '  },' -ForegroundColor Gray
    Write-Host '  "sync_options": {' -ForegroundColor Gray
    Write-Host '    "preview_mode": false,' -ForegroundColor Gray
    Write-Host '    "require_confirmation": false' -ForegroundColor Gray
    Write-Host '  }' -ForegroundColor Gray
    Write-Host '}' -ForegroundColor Gray
    exit 1
}

# 验证配置文件
if (-not (Test-ConfigFile -Config $config)) {
    exit 1
}

# 解析源路径
$SourceDir = Resolve-PathSafe -Path $config.SourcePath -BaseDir $ScriptDir

if (-not (Test-Path $SourceDir)) {
    Write-Host "错误: 原始项目目录不存在: $SourceDir" -ForegroundColor Red
    exit 1
}

# 安装 Git Hook
Install-GitHook -ScriptDir $ScriptDir -SourceDir $SourceDir | Out-Null

# 解析目标路径
$TargetPaths = $config.TargetPaths | ForEach-Object {
    Resolve-PathSafe -Path $_ -BaseDir $ScriptDir
}

if ($TargetPaths.Count -eq 0) {
    Write-Host "错误: 配置文件中没有找到目标路径" -ForegroundColor Red
    exit 1
}

Write-Host "找到 $($TargetPaths.Count) 个目标路径" -ForegroundColor Green

# 执行同步到所有目标路径
$SuccessCount = 0
$FailCount = 0

# 获取排除模式
$ExcludePatterns = @()
if ($config.ExcludePatterns) {
    $ExcludePatterns = $config.ExcludePatterns
}

# 应用命令行参数覆盖配置文件设置
if ($PreviewMode) {
    $config.SyncOptions.PreviewMode = $true
}
if ($RequireConfirmation) {
    $config.SyncOptions.RequireConfirmation = $true
}

foreach ($TargetPath in $TargetPaths) {
    if (Sync-ToTarget -SourceDir $SourceDir -TargetDir $TargetPath -FullSync $FullSyncMode -ExcludePatterns $ExcludePatterns -SyncOptions $config) {
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
