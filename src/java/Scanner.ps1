# Everything (ES) 相关函数

# FD 下载相关函数

function Get-FdDownloadUrl {
    try {
        $apiUrl = "https://api.github.com/repos/sharkdp/fd/releases/latest"
        $response = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop

        # 查找 x86_64-pc-windows-gnu 的 zip 文件
        $asset = $response.assets | Where-Object { $_.name -match "x86_64-pc-windows-gnu\.zip$" } | Select-Object -First 1

        if (-not $asset) {
            Write-Warning "No fd Windows binary found in latest release."
            return $null
        }

        $originalUrl = $asset.browser_download_url
        $version = $response.tag_name

        # 生成 jsdelivr 加速链接
        $jsdelivrUrl = $originalUrl -replace "https://github.com/([^/]+)/([^/]+)/releases/download/([^/]+)/(.+)", "https://cdn.jsdelivr.net/gh/`$1/`$2@`$3/`$4"

        # 生成 ghproxy 加速链接
        $ghproxyUrl = "https://gh-proxy.org/$originalUrl"

        if ($Global:JmpDebug) {
            Log-Debug "Original URL: $originalUrl"
            Log-Debug "jsDelivr URL: $jsdelivrUrl"
            Log-Debug "ghproxy URL: $ghproxyUrl"
        }

        return @{
            Original = $originalUrl
            Jsdelivr = $jsdelivrUrl
            Ghproxy = $ghproxyUrl
            Version = $version
        }
    } catch {
        Write-Warning "Failed to fetch fd release info: $_"
        return $null
    }
}

function Download-Fd {
    $fdInfo = Get-FdDownloadUrl
    if (-not $fdInfo) {
        Write-ErrorMsg "Failed to get fd download information."
        return $false
    }

    $fdExePath = Join-Path $Script:ProjectRoot "fd.exe"
    $tempDir = Join-Path $env:TEMP "jmp-fd-download"
    $zipFile = Join-Path $tempDir "fd.zip"

    # 创建临时目录
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    # 尝试使用 jsdelivr 加速链接下载
    Write-Info "Downloading fd $($fdInfo.Version)..."
    Write-Info "Using jsDelivr CDN for faster download..."

    try {
        Invoke-WebRequest -Uri $fdInfo.Jsdelivr -OutFile $zipFile -ErrorAction Stop
    } catch {
        Write-Warning "jsDelivr download failed, trying ghproxy..."
        try {
            Invoke-WebRequest -Uri $fdInfo.Ghproxy -OutFile $zipFile -ErrorAction Stop
        } catch {
            Write-Warning "ghproxy download failed, trying original URL..."
            try {
                Invoke-WebRequest -Uri $fdInfo.Original -OutFile $zipFile -ErrorAction Stop
            } catch {
                Write-ErrorMsg "All download attempts failed: $_"
                return $false
            }
        }
    }

    # 解压 zip 文件
    Write-Info "Extracting fd.exe..."
    try {
        # 使用 PowerShell 的 Expand-Archive 解压（需要 PS 5.1+）
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $tempDir)

        # 查找 fd.exe
        $extractedFd = Get-ChildItem $tempDir -Recurse -Filter "fd.exe" | Select-Object -First 1

        if (-not $extractedFd) {
            Write-ErrorMsg "fd.exe not found in downloaded archive."
            return $false
        }

        # 复制到项目根目录
        Copy-Item $extractedFd.FullName $fdExePath -Force

        Write-Success "fd.exe downloaded successfully to: $fdExePath"

        # 清理临时文件
        Remove-Item $tempDir -Recurse -Force

        return $true
    } catch {
        Write-ErrorMsg "Failed to extract fd.exe: $_"
        return $false
    }
}

function Ask-DownloadFd {
    Write-Info "fd tool not found. fd can provide faster Java scanning."
    Write-Info "Would you like to download fd.exe? (Y/N)"

    $response = Read-Host
    if ($response -match "^[Yy]") {
        return Download-Fd
    } else {
        Write-Info "Skipping fd download. Using fallback scan method."
        return $false
    }
}

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

        if ($Global:JmpDebug) {
            Log-Debug "Raw ES output type: $($rawOutput.GetType().Name)"
            Log-Debug "Raw ES output length: $($rawOutput.Length)"
            Log-Debug "Raw ES output (first 200 chars): $($rawOutput.Substring(0, [Math]::Min(200, $rawOutput.Length)))"
        }

        $esOutput = $rawOutput | ConvertFrom-Json

        if ($Global:JmpDebug) {
            Log-Debug "Parsed ES output type: $($esOutput.GetType().Name)"
            Log-Debug "Parsed ES output count: $($esOutput.Count)"
        }
        
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
            if ($Global:JmpDebug) {
                Log-Debug "Executing: $fdPath -t x -F java.exe $drive --absolute-path"
            }
            $fdOutput = & $fdPath -t x -F "java.exe" $drive --absolute-path 2>$null
            
            if ($Global:JmpDebug) {
                if ($fdOutput) {
                    Log-Debug "fd output type: $($fdOutput.GetType().Name)"
                    Log-Debug "fd output count: $($fdOutput.Count)"
                } else {
                    Log-Debug "fd output is null"
                }
            }
            
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

# 辅助函数：尝试使用 fd，如果不可用则询问用户是否下载，否则使用 fallback
function Invoke-FallbackScan {
    $fdPath = Join-Path $Script:ProjectRoot "fd.exe"
    if (Test-Path $fdPath) {
        if ($Global:JmpDebug) { Log-Debug "Using fd for disk-by-disk scan" }
        return (Scan-Java-WithFD)
    } else {
        if ($Global:JmpDebug) { Log-Debug "fd.exe not found" }

        # 询问用户是否下载 fd
        $downloaded = Ask-DownloadFd

        if ($downloaded) {
            # 下载成功，使用 fd 扫描
            if ($Global:JmpDebug) { Log-Debug "fd.exe downloaded, using fd for disk-by-disk scan" }
            return (Scan-Java-WithFD)
        } else {
            # 用户拒绝或下载失败，使用 fallback 扫描
            if ($Global:JmpDebug) { Log-Debug "Using fallback scan" }
            return (Scan-Java-Fallback)
        }
    }
}
