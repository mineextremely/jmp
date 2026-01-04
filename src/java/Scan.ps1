# Everything (ES) 相关函数

function Get-ESPath {
    # 只检查 PATH 中的 es 命令
    $esCmd = Get-Command es -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if ($esCmd -and (Test-Path $esCmd)) { return $esCmd }
    
    return $null
}

function Test-ESAvailable {
    param(
        [string]$EsExePath
    )

    if (-not (Test-Path $EsExePath)) {
        Write-Warning "ES executable not found at $EsExePath"
        return $false
    }

    # 测试ES是否可用（通过搜索notepad.exe）
    $maxRetries = 3
    $retryCount = 0
    
    while ($retryCount -lt $maxRetries) {
        try {
            # 尝试搜索一个肯定存在的文件来测试ES服务
            $testOutput = & $EsExePath "-name" "notepad.exe" "-count" "1" 2>$null
            
            if ($LASTEXITCODE -eq 0) {
                # 即使没有结果，只要命令成功执行就表示服务正常
                if ($Global:JmpDebug) {
                    Log-Debug "ES test successful, exit code: $LASTEXITCODE"
                }
                return $true
            } else {
                if ($Global:JmpDebug) {
                    Log-Debug "ES test failed, exit code: $LASTEXITCODE"
                }
            }
        } catch {
            if ($Global:JmpDebug) {
                Log-Debug "ES test exception: $_"
            }
        }
        
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Write-Info "Waiting 1 second before retry $retryCount of $maxRetries..."
            Start-Sleep -Seconds 1
        }
    }

    Write-Warning "ES test failed after $maxRetries attempts. Will fallback."
    return $false
}

function Scan-Java-WithES {
    param($EsPath)

    $results = @()

    try {
        # 使用正确的ES搜索参数
        $searchQuery = 'java.exe'
        
        # 使用ES搜索所有java.exe文件，返回JSON格式
        $rawOutput = & $EsPath "-json" "-count" "1000" "-name" $searchQuery 2>$null
        
        if (-not $rawOutput) {
            # ES 没找到结果，或者出错了
            if ($Global:JmpDebug) {
                Log-Debug "ES returned no output for query: $searchQuery"
            }
            throw "No output from ES"
        }

        $esOutput = $rawOutput | ConvertFrom-Json
        
        foreach ($item in $esOutput) {
            $javaExe  = $item.filename
            
            # [Safety] 确保路径有效且确实是 bin\java.exe 结尾
            if (-not ($javaExe -match 'bin\\java\.exe$')) { continue }

            $javaHome = Split-Path (Split-Path $javaExe -Parent) -Parent
            $release  = Join-Path $javaHome "release"

            if (-not (Test-Path $release)) { continue }

            $verLine = Get-Content $release -ErrorAction SilentlyContinue |
                Where-Object { $_ -like 'JAVA_VERSION=*' }

            if (-not $verLine) { continue }

            $version = ($verLine -split '"')[1].Trim('"')
            
            # 处理vendor字段，如果是数组则取第一个值
            $vendor  = Detect-Vendor $javaHome

            $parsedVersion = Parse-JavaVersion $version
            
            $results += [pscustomobject]@{
                name    = Split-Path $javaHome -Leaf
                version = $version
                versionObj = $parsedVersion
                vendor  = $vendor
                path    = $javaHome
                source  = "es"
            }
        }
    } catch {
        # fallback 逻辑保持不变...
        try {
            & $EsPath "java.exe" 2>$null |
            Where-Object { $_ -match '\\bin\\java\.exe$' } |
            ForEach-Object {
                $javaExe  = $_
                $javaHome = Split-Path (Split-Path $javaExe -Parent) -Parent
                $release  = Join-Path $javaHome "release"

                if (-not (Test-Path $release)) { return }

                $verLine = Get-Content $release -ErrorAction SilentlyContinue |
                    Where-Object { $_ -like 'JAVA_VERSION=*' }

                if (-not $verLine) { return }

                $version = ($verLine -split '"')[1].Trim('"')
                $vendor  = Detect-Vendor $javaHome

                $parsedVersion = Parse-JavaVersion $version
                
                $results += [pscustomobject]@{
                    name    = Split-Path $javaHome -Leaf
                    version = $version
                    versionObj = $parsedVersion
                    vendor  = $vendor
                    path    = $javaHome
                    source  = "es"
                }
            }
        } catch {
            Write-Warning "ES fallback search also failed: $_"
        }
    }

    return $results
}

# FD Scan (使用 fd 进行逐盘搜索)

function Scan-Java-WithFD {
    $results = @()
    
    $fdPath = Join-Path $Script:ProjectRoot "fd.exe"
    if (-not (Test-Path $fdPath)) {
        Write-Warning "fd.exe not found at $fdPath. Cannot perform FD scan."
        return $results
    }
    
    Write-Info "Using fd for disk-by-disk search..."
    
    # 获取所有文件系统驱动器
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' } | Select-Object -ExpandProperty Root
    
    if (-not $drives) {
        Write-Warning "No drives found for FD scan."
        return $results
    }
    
    if ($Global:JmpDebug) {
        Log-Debug "Found drives: $($drives -join ', ')"
    }
    
    foreach ($drive in $drives) {
        Write-Info "Searching drive $drive..."
        
        try {
            # 使用 fd 搜索 java.exe 可执行文件
            $fdOutput = & $fdPath -tx "java.exe" $drive --absolute-path 2>$null
            
            if ($fdOutput) {
                foreach ($javaExe in $fdOutput) {
                    # 确保路径以 bin\java.exe 结尾
                    if (-not ($javaExe -match '\\bin\\java\.exe$')) { continue }
                    
                    $javaHome = Split-Path (Split-Path $javaExe -Parent) -Parent
                    
                    # 检查是否已经处理过相同的 javaHome（去重）
                    if ($results.path -contains $javaHome) { continue }
                    
                    $release = Join-Path $javaHome "release"
                    
                    if (-not (Test-Path $release)) { continue }
                    
                    $verLine = Get-Content $release -ErrorAction SilentlyContinue |
                        Where-Object { $_ -like 'JAVA_VERSION=*' }
                    
                    if (-not $verLine) { continue }
                    
                    $version = ($verLine -split '"')[1].Trim('"')
                    $vendor = Detect-Vendor $javaHome
                    $parsedVersion = Parse-JavaVersion $version
                    
                    $results += [pscustomobject]@{
                        name    = Split-Path $javaHome -Leaf
                        version = $version
                        versionObj = $parsedVersion
                        vendor  = $vendor
                        path    = $javaHome
                        source  = "fd"
                    }
                }
            }
        } catch {
            Write-Warning "Error scanning drive $drive with fd: $_"
        }
    }
    
    return $results
}

# Fallback Scan

function Scan-Java-Fallback {
    $results = @()
    $candidates = @()

    # 1. PATH 下的 java.exe
    try {
        $cmds = Get-Command java -ErrorAction SilentlyContinue
        foreach ($c in $cmds) {
            if ($c.Source) {
                $javaHome = Split-Path (Split-Path $c.Source -Parent) -Parent
                $candidates += $javaHome
            }
        }
    } catch {}

    # 2. 常见目录
    $commonRoots = @(
        "$env:ProgramFiles\Java",
        "$env:ProgramFiles(x86)\Java",
        "$env:LOCALAPPDATA\Programs\Java",
        "$env:USERPROFILE\.jdks"
    ) | Where-Object { Test-Path $_ }

    foreach ($root in $commonRoots) {
        try {
            $dirs = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue
            foreach ($d in $dirs) {
                # 只要 bin\java.exe 存在，就加入
                $javaExe = Join-Path $d.FullName "bin\java.exe"
                if (Test-Path $javaExe) {
                    $candidates += $d.FullName
                }
            }
        } catch {}
    }

    # 去重
    $candidates = $candidates | Sort-Object -Unique

    # 构建结果对象
    foreach ($javaHome in $candidates) {
        $javaExe = Join-Path $javaHome "bin\java.exe"
        if (-not (Test-Path $javaExe)) { continue }

        # 尝试获取版本
        $ver = ""
        try {
            $verLine = & $javaExe -version 2>&1 | Select-Object -First 1
            if ($verLine -match '"([\d._]+)"') { $ver = $matches[1] }
        } catch {}

        $results += [pscustomobject]@{
            name = Split-Path $javaHome -Leaf
            version = $ver
            versionObj = Parse-JavaVersion $ver
            vendor = Detect-Vendor $javaHome
            path = $javaHome
            source = "fallback"
        }
    }

    return $results
}

# 辅助函数：尝试使用 fd，如果不可用则使用 fallback
function Invoke-FallbackScan {
    $fdPath = Join-Path $Script:ProjectRoot "fd.exe"
    if (Test-Path $fdPath) {
        if ($Global:JmpDebug) { Log-Debug "Using fd for disk-by-disk scan" }
        return Scan-Java-WithFD
    } else {
        if ($Global:JmpDebug) { Log-Debug "fd.exe not found, using fallback scan" }
        return Scan-Java-Fallback
    }
}