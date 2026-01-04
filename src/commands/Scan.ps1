# src/commands/Scan.ps1

function Invoke-Scan {
    param($Ctx)
    
    $results = @()
    
    # 根据 FallbackMode 决定扫描策略
    if ($Ctx.FallbackMode -eq 2) {
        # -fallback 2: 直接使用 fallback（跳过 ES 和 FD）
        if ($Global:JmpDebug) {
            Log-Debug "FallbackMode 2: Direct fallback scan, skipping Everything and fd"
        }
        $results = Scan-Java-Fallback
    } elseif ($Ctx.FallbackMode -eq 1) {
        # -fallback 1: 跳过 ES，尝试使用 FD，如果不可用则使用 fallback
        if ($Global:JmpDebug) {
            Log-Debug "FallbackMode 1: Skip Everything, try fd, then fallback"
        }
        $results = Invoke-FallbackScan
    } else {
        # FallbackMode 0: 自动模式（默认）
        # 1. 检查 PATH 中是否有 es
        if ($esPath = Get-ESPath) {
            if ($Global:JmpDebug) {
                Log-Debug "Found es in PATH: $esPath"
            }
            
            # 测试 ES 是否可用
            if (Test-ESAvailable $esPath) {
                Write-Info "Everything (ES) is available, using ES for scanning"
                $results = Scan-Java-WithES $esPath
            } else {
                Write-Warning "ES test failed, falling back to fd or fallback"
                # 降级：尝试使用 fd，如果不可用则使用 fallback
                $results = Invoke-FallbackScan
            }
        } else {
            # PATH 中没有 es，尝试使用 fd
            if ($Global:JmpDebug) {
                Log-Debug "es not found in PATH, trying fd"
            }
            $results = Invoke-FallbackScan
        }
    }
    
    # 保存结果到 JSON 文件
    if ($results) {
        Save-Json (Join-Path $Script:ProjectRoot "java-versions.json") $results
    }
    
    Write-Success "Scan completed. Found $($results.Count) Java installations."
    if ($results.Count -gt 0) {
        $results | ForEach-Object { Write-Info "  - $($_.version) ($($_.vendor)) at $($_.path)" }
    }
}