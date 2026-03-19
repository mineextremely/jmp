# src/commands/Scan.ps1

function Invoke-Scan {
    param($Ctx)
    
    $results = @()
    
    # 根据 ScanMode 决定扫描策略
    if ($Ctx.ScanMode -eq "light") {
        # 轻量模式：仅使用注册表、Microsoft Store 和常见目录
        if ($Global:JmpDebug) {
            Log-Debug "ScanMode: light - Using registry, Microsoft Store, and common paths"
        }
        Write-Info "Running light scan (fast mode, no external dependencies)..."
        $results = @(Scan-Java-Light)
    } elseif ($Ctx.ScanMode -eq "deep") {
        # 深度模式：使用 FD 全盘搜索
        if ($Global:JmpDebug) {
            Log-Debug "ScanMode: deep - Using FD for full disk search"
        }
        Write-Info "Running deep scan (comprehensive mode, requires fd.exe)..."
        
        # 检查 fd.exe 是否存在
        $binDir = Join-Path $Script:ProjectRoot "bin"
        $fdPath = Join-Path $binDir "fd.exe"
        
        if (-not (Test-Path $fdPath)) {
            Write-Warning "fd.exe not found in bin directory."
            # 询问用户是否下载
            $downloaded = Ask-DownloadFd
            if (-not $downloaded) {
                Write-Info "Skipping deep scan. Use 'jmp scan' for default scan."
                return
            }
        }
        
        $results = @(Scan-Java-WithFD)
    } else {
        # 默认模式：轻量模式 + BFS 深度扫描
        if ($Global:JmpDebug) {
            Log-Debug "ScanMode: default - Using light scan + BFS deep scan"
        }
        Write-Info "Running default scan (balanced mode: light + BFS)..."
        
        # 1. 先执行轻量模式扫描（快速找到常见 Java）
        $results = @(Scan-Java-Light)
        
        # 2. 执行 BFS 深度扫描（查找更多 Java）
        $bfsResults = @(Scan-Java-BFS -MaxDepth 8)
        
        # 3. 合并结果并去重
        $uniqueResults = @{}
        foreach ($result in $results) {
            if (-not $uniqueResults.ContainsKey($result.path)) {
                $uniqueResults[$result.path] = $result
            }
        }
        foreach ($result in $bfsResults) {
            if (-not $uniqueResults.ContainsKey($result.path)) {
                $uniqueResults[$result.path] = $result
            }
        }
        
        $results = @($uniqueResults.Values | Sort-Object { $_.versionObj.Major }, { $_.versionObj.Minor }, { $_.versionObj.Patch })
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