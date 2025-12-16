# 测试基本语法
Write-Host "测试开始" -ForegroundColor Green

# 检查依赖工具
function Test-Dependencies {
    $missingDeps = @()
    
    # 检查 Git
    try {
        $null = git --version 2>$null
    } catch {
        $missingDeps += "Git"
    }
    
    if ($missingDeps.Count -gt 0) {
        Write-Host "错误: 缺少必要的工具: $($missingDeps -join ', ')" -ForegroundColor Red
        return $false
    }
    
    return $true
}

# 测试函数
if (Test-Dependencies) {
    Write-Host "依赖检查通过" -ForegroundColor Green
} else {
    Write-Host "依赖检查失败" -ForegroundColor Red
}

Write-Host "测试完成" -ForegroundColor Green