# 简单测试脚本
function Test-Function {
    param(
        [string]$SourceDir,
        [string]$TargetDir
    )
    
    Write-Host "函数内 SourceDir: '$SourceDir'"
    Write-Host "函数内 TargetDir: '$TargetDir'"
}

$TestSource = "F:\person\gitUpdateFiles\source_path"
$TestTarget = "F:\person\gitUpdateFiles\target_path\test\target-test-path"

Write-Host "调用前 TestSource: '$TestSource'"
Write-Host "调用前 TestTarget: '$TestTarget'"

Test-Function -SourceDir $TestSource -TargetDir $TestTarget