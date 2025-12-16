# Test JSON log generation
$LogData = @{
    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    sync_mode = "incremental"
    source_dir = "F:\person\gitUpdateFiles\source_path"
    target_dir = "F:\person\gitUpdateFiles\target_path\test\target-test-path"
    git_repo = $true
    statistics = @{
        added = 1
        modified = 0
        deleted = 0
    }
    files = @{
        added = @("test.js")
        modified = @()
        deleted = @()
    }
    duration_ms = 1250
    status = "success"
    errors = @()
}

$LogJson = $LogData | ConvertTo-Json -Depth 10 -Compress:$false
Write-Host "Generated JSON:"
Write-Host $LogJson

$LogFile = "test_sync_log.json"
[System.IO.File]::WriteAllText($LogFile, $LogJson, [System.Text.Encoding]::UTF8)
Write-Host "JSON saved to: $LogFile"