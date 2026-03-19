# Everything (ES) 相关函数

# FD 下载相关函数

function Test-NetworkConnectivity {
    # 缓存检测结果（5 分钟有效）
    if ($Script:NetworkTestCache -and 
        (Get-Date) -lt $Script:NetworkTestCache.Expiry) {
        return $Script:NetworkTestCache.Result
    }
    
    $connected = $false
    
    try {
        # 尝试 ICMP 检测（使用阿里云 DNS 223.5.5.5）
        $connected = Test-Connection -ComputerName 223.5.5.5 -Count 2 -Quiet -ErrorAction SilentlyContinue
        
        if ($Global:JmpDebug) {
            Log-Debug "ICMP connectivity test result: $connected"
        }
        
        # 如果 ICMP 失败，尝试 HTTP 检测（备用方案）
        if (-not $connected) {
            try {
                $response = Invoke-WebRequest -Uri "http://www.baidu.com" -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
                $connected = ($response.StatusCode -eq 200)
                
                if ($Global:JmpDebug) {
                    Log-Debug "HTTP connectivity test result: $connected"
                }
            } catch {
                if ($Global:JmpDebug) {
                    Log-Debug "HTTP connectivity test failed: $_"
                }
                $connected = $false
            }
        }
    } catch {
        if ($Global:JmpDebug) {
            Log-Debug "Network connectivity test failed: $_"
        }
        $connected = $false
    }
    
    # 缓存结果
    $Script:NetworkTestCache = @{
        Result = $connected
        Expiry = (Get-Date).AddMinutes(5)
    }
    
    return $connected
}

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

        # 生成 ghproxy.org 加速链接
        $ghproxyOrgUrl = "https://gh-proxy.org/$originalUrl"
        
        # 生成 ghproxy.net 加速链接
        $ghproxyNetUrl = "https://ghproxy.net/$originalUrl"

        if ($Global:JmpDebug) {
            Log-Debug "Original URL: $originalUrl"
            Log-Debug "ghproxy.org URL: $ghproxyOrgUrl"
            Log-Debug "ghproxy.net URL: $ghproxyNetUrl"
        }

        return @{
            Original = $originalUrl
            GhproxyOrg = $ghproxyOrgUrl
            GhproxyNet = $ghproxyNetUrl
            Version = $version
        }
    } catch {
        Write-Warning "Failed to fetch fd release info: $_"
        return $null
    }
}

function Download-FileParallel {
    param(
        [string[]]$Urls,
        [string]$OutputPath,
        [int]$TimeoutSeconds = 60
    )
    
    if ($Global:JmpDebug) {
        Log-Debug "Starting parallel download from $($Urls.Count) sources"
    }
    
    $tasks = @()
    $webClients = @()
    $completed = $false
    $successUrl = $null
    
    # 为每个 URL 创建独立的 WebClient 实例
    foreach ($url in $Urls) {
        $tempFile = "$OutputPath.temp.$([Guid]::NewGuid())"
        $webClient = New-Object System.Net.WebClient
        $webClients += $webClient
        
        $task = @{
            Url = $url
            TempFile = $tempFile
            AsyncResult = $null
            WebClient = $webClient
        }
        
        try {
            $task.AsyncResult = $webClient.DownloadFileTaskAsync($url, $tempFile)
            $tasks += $task
            
            if ($Global:JmpDebug) {
                Log-Debug "Started download from: $url"
            }
        } catch {
            if ($Global:JmpDebug) {
                Log-Debug "Failed to start download from ${url}: $_"
            }
            # 清理失败的 WebClient
            try {
                $webClient.Dispose()
            } catch {
                # 忽略清理错误
            }
        }
    }
    
    # 等待第一个成功的任务
    $timeout = [Diagnostics.Stopwatch]::StartNew()
    while (-not $completed -and $timeout.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        foreach ($task in $tasks) {
            if ($task.AsyncResult -and $task.AsyncResult.IsCompleted) {
                if ($task.AsyncResult.IsFaulted) {
                    if ($Global:JmpDebug) {
                        Log-Debug "Download failed from $($task.Url): $($task.AsyncResult.Exception.Message)"
                    }
                } else {
                    # 下载成功
                    $successUrl = $task.Url
                    $completed = $true
                    
                    # 取消其他下载
                    foreach ($otherTask in $tasks) {
                        if ($otherTask.WebClient -and $otherTask -ne $task) {
                            try {
                                $otherTask.WebClient.CancelAsync()
                            } catch {
                                # 忽略取消错误
                            }
                        }
                    }
                    
                    # 移动临时文件到目标路径
                    if (Test-Path $task.TempFile) {
                        Move-Item -Path $task.TempFile -Destination $OutputPath -Force
                        
                        if ($Global:JmpDebug) {
                            Log-Debug "Successfully downloaded from: $successUrl"
                        }
                    }
                    
                    break
                }
            }
        }
        
        Start-Sleep -Milliseconds 100
    }
    
    # 清理
    foreach ($wc in $webClients) {
        try {
            $wc.Dispose()
        } catch {
            # 忽略清理错误
        }
    }
    
    # 清理临时文件
    foreach ($task in $tasks) {
        if ($task.TempFile -ne $OutputPath -and (Test-Path $task.TempFile)) {
            try {
                Remove-Item $task.TempFile -Force -ErrorAction SilentlyContinue
            } catch {
                # 忽略清理错误
            }
        }
    }
    
    return $completed
}

function Download-Fd {
    param(
        [bool]$EnableParallelDownload = $true
    )
    
    $fdInfo = Get-FdDownloadUrl
    if (-not $fdInfo) {
        Write-ErrorMsg "Failed to get fd download information."
        return $false
    }

    # 创建 bin 目录（如果不存在）
    $binDir = Join-Path $Script:ProjectRoot "bin"
    if (-not (Test-Path $binDir)) {
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }

    $fdExePath = Join-Path $binDir "fd.exe"
    $tempDir = Join-Path $env:TEMP "jmp-fd-download"
    $zipFile = Join-Path $tempDir "fd.zip"

    # 创建临时目录
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    # 网络检测
    $networkConnected = Test-NetworkConnectivity
    
    if ($Global:JmpDebug) {
        Log-Debug "Network connectivity: $networkConnected"
        Log-Debug "Parallel download enabled: $EnableParallelDownload"
    }
    
    # 根据网络状态和并行下载设置决定下载策略
    if ($EnableParallelDownload -and $networkConnected) {
        # 网络正常 + 并行下载启用：并行尝试所有源
        Write-Info "Downloading fd $($fdInfo.Version)..."
        Write-Info "Using parallel download from multiple sources..."
        
        $urls = @($fdInfo.GhproxyNet, $fdInfo.GhproxyOrg, $fdInfo.Original)
        $downloadSuccess = Download-FileParallel -Urls $urls -OutputPath $zipFile -TimeoutSeconds 60
        
        if (-not $downloadSuccess) {
            Write-ErrorMsg "All parallel download attempts failed or timed out."
            return $false
        }
    } else {
        # 网络异常或并行下载禁用：顺序下载
        if ($networkConnected) {
            Write-Info "Downloading fd $($fdInfo.Version)..."
            Write-Info "Using ghproxy.net for faster download..."
            
            # 优先使用 ghproxy.net
            try {
                Invoke-WebRequest -Uri $fdInfo.GhproxyNet -OutFile $zipFile -ErrorAction Stop
            } catch {
                Write-Warning "ghproxy.net download failed, trying ghproxy.org..."
                try {
                    Invoke-WebRequest -Uri $fdInfo.GhproxyOrg -OutFile $zipFile -ErrorAction Stop
                } catch {
                    Write-Warning "ghproxy.org download failed, trying original URL..."
                    try {
                        Invoke-WebRequest -Uri $fdInfo.Original -OutFile $zipFile -ErrorAction Stop
                    } catch {
                        Write-ErrorMsg "All download attempts failed: $_"
                        return $false
                    }
                }
            }
        } else {
            Write-Info "Downloading fd $($fdInfo.Version)..."
            Write-Info "Network unstable, using ghproxy.org..."
            
            # 网络不稳定时，顺序尝试
            try {
                Invoke-WebRequest -Uri $fdInfo.GhproxyOrg -OutFile $zipFile -ErrorAction Stop
            } catch {
                Write-Warning "ghproxy.org download failed, trying ghproxy.net..."
                try {
                    Invoke-WebRequest -Uri $fdInfo.GhproxyNet -OutFile $zipFile -ErrorAction Stop
                } catch {
                    Write-Warning "ghproxy.net download failed, trying original URL..."
                    try {
                        Invoke-WebRequest -Uri $fdInfo.Original -OutFile $zipFile -ErrorAction Stop
                    } catch {
                        Write-ErrorMsg "All download attempts failed: $_"
                        return $false
                    }
                }
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

        # 复制到 bin 目录
        Copy-Item $extractedFd.FullName $fdExePath -Force

        Write-Success "fd.exe downloaded successfully to: $fdExePath"

        return $true
    } catch {
        Write-ErrorMsg "Failed to extract fd.exe: $_"
        return $false
    } finally {
        # 清理临时文件（无论成功或失败）
        if (Test-Path $tempDir) {
            try {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                if ($Global:JmpDebug) {
                    Log-Debug "Cleaned up temporary directory: $tempDir"
                }
            } catch {
                if ($Global:JmpDebug) {
                    Log-Debug "Failed to clean up temporary directory: $tempDir"
                }
            }
        }
    }
}

function Ask-DownloadFd {
    param(
        [bool]$EnableParallelDownload = $true
    )
    
    Write-Info "fd tool not found. fd can provide faster Java scanning."
    Write-Info "Would you like to download fd.exe? (Y/N, default: Y)"

    $response = Read-Host
    # 空字符串或 y/Y 都表示同意
    if ($response -eq "" -or $response -match "^[Yy]") {
        return Download-Fd -EnableParallelDownload $EnableParallelDownload
    } elseif ($response -match "^[Nn]") {
        Write-Info "Skipping fd download. Using fallback scan method."
        return $false
    } else {
        # 其他输入也视为同意
        return Download-Fd -EnableParallelDownload $EnableParallelDownload
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

        # 使用ES搜索所有java.exe文件，返回JSON格式，包含完整路径
        $rawOutput = & $EsPath "-json" "-count" "1000" "-full-path-and-name" "-name" $searchQuery 2>$null
        
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

        # ConvertFrom-Json 返回的是直接数组，不需要访问 .value 属性
        $fileList = $esOutput

        if ($Global:JmpDebug) {
            Log-Debug "File list type: $($fileList.GetType().Name)"
            Log-Debug "File list count: $($fileList.Count)"
        }

        foreach ($item in $fileList) {
            # ES 返回的字段是 filename（完整路径）
            $javaExe  = $item.filename

            # [Safety] 确保路径有效且确实是 bin\java.exe 结尾
            if (-not ($javaExe -match 'bin\\java\.exe$')) {
                if ($Global:JmpDebug) {
                    Log-Debug "Skipping non-bin path: $javaExe"
                }
                continue
            }

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
    
    $binDir = Join-Path $Script:ProjectRoot "bin"
    $fdPath = Join-Path $binDir "fd.exe"
    
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

# ============================================================================
# 轻量模式扫描器（基于注册表和常见目录，无需外部依赖）
# ============================================================================

function Scan-Java-Registry {
    $results = @()
    
    try {
        # JavaSoft 官方注册表路径
        $registryPaths = @(
            "HKLM:\SOFTWARE\JavaSoft\Java Development Kit",
            "HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment",
            "HKLM:\SOFTWARE\WOW6432Node\JavaSoft\Java Development Kit",
            "HKLM:\SOFTWARE\WOW6432Node\JavaSoft\Java Runtime Environment"
        )
        
        foreach ($regPath in $registryPaths) {
            if (-not (Test-Path $regPath)) { continue }
            
            try {
                $versions = Get-ChildItem $regPath -ErrorAction SilentlyContinue
                foreach ($version in $versions) {
                    try {
                        $javaHome = (Get-ItemProperty $version.PSPath -ErrorAction SilentlyContinue).JavaHome
                        if (-not $javaHome) { continue }
                        
                        # 验证路径有效性
                        if ($javaHome -match '[<>:"|?*]') { continue }
                        
                        $javaExe = Join-Path $javaHome "bin\java.exe"
                        if (-not (Test-Path $javaExe)) { continue }
                        
                        # 获取版本信息
                        $release = Join-Path $javaHome "release"
                        if (Test-Path $release) {
                            $verLine = Get-Content $release -ErrorAction SilentlyContinue |
                                Where-Object { $_ -like 'JAVA_VERSION=*' }
                            if ($verLine) {
                                $version = ($verLine -split '"')[1].Trim('"')
                                $vendor = Detect-Vendor $javaHome
                                $parsedVersion = Parse-JavaVersion $version
                                
                                $results += [pscustomobject]@{
                                    name    = Split-Path $javaHome -Leaf
                                    version = $version
                                    versionObj = $parsedVersion
                                    vendor  = $vendor
                                    path    = $javaHome
                                    source  = "registry"
                                }
                                
                                if ($Global:JmpDebug) {
                                    Log-Debug "Found Java from registry: $javaHome ($version)"
                                }
                            }
                        }
                    } catch {
                        if ($Global:JmpDebug) {
                            Log-Debug "Error reading registry key ${version.PSPath}: $_"
                        }
                    }
                }
            } catch {
                if ($Global:JmpDebug) {
                    Log-Debug "Error accessing registry path ${regPath}: $_"
                }
            }
        }
        
        # 品牌特定注册表路径
        $brandPaths = @(
            "HKLM:\SOFTWARE\Azul Systems\Zulu",
            "HKLM:\SOFTWARE\BellSoft\Liberica"
        )
        
        foreach ($brandPath in $brandPaths) {
            if (-not (Test-Path $brandPath)) { continue }
            
            try {
                $installations = Get-ChildItem $brandPath -ErrorAction SilentlyContinue
                foreach ($installation in $installations) {
                    try {
                        $installPath = (Get-ItemProperty $installation.PSPath -ErrorAction SilentlyContinue).InstallationPath
                        if (-not $installPath) { continue }
                        
                        # 验证路径有效性
                        if ($installPath -match '[<>:"|?*]') { continue }
                        
                        $javaExe = Join-Path $installPath "bin\java.exe"
                        if (-not (Test-Path $javaExe)) { continue }
                        
                        # 获取版本信息
                        $release = Join-Path $installPath "release"
                        if (Test-Path $release) {
                            $verLine = Get-Content $release -ErrorAction SilentlyContinue |
                                Where-Object { $_ -like 'JAVA_VERSION=*' }
                            if ($verLine) {
                                $version = ($verLine -split '"')[1].Trim('"')
                                $vendor = Detect-Vendor $installPath
                                $parsedVersion = Parse-JavaVersion $version
                                
                                $results += [pscustomobject]@{
                                    name    = Split-Path $installPath -Leaf
                                    version = $version
                                    versionObj = $parsedVersion
                                    vendor  = $vendor
                                    path    = $installPath
                                    source  = "registry"
                                }
                                
                                if ($Global:JmpDebug) {
                                    Log-Debug "Found Java from brand registry: $installPath ($version)"
                                }
                            }
                        }
                    } catch {
                        if ($Global:JmpDebug) {
                            Log-Debug "Error reading brand registry key $($installation.PSPath): $_"
                        }
                    }
                }
            } catch {
                if ($Global:JmpDebug) {
                    Log-Debug "Error accessing brand registry path ${brandPath}: $_"
                }
            }
        }
    } catch {
        Write-Warning "Registry scan failed: $_"
    }
    
    if ($Global:JmpDebug) {
        Log-Debug "Registry scan completed. Found $($results.Count) Java installations."
    }
    
    return $results
}

function Scan-Java-MicrosoftStore {
    $results = @()
    
    try {
        $storePath = Join-Path $env:LOCALAPPDATA `
            "Packages\Microsoft.4297127D64EC6_8wekyb3d8bbwe\LocalCache\Local\runtime"
        
        if (-not (Test-Path $storePath)) {
            if ($Global:JmpDebug) {
                Log-Debug "Microsoft Store Java path not found: $storePath"
            }
            return $results
        }
        
        # 第一级：java-runtime* 目录
        $runtimeDirs = Get-ChildItem $storePath -Directory -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -like "java-runtime*" }
        
        foreach ($runtimeDir in $runtimeDirs) {
            try {
                # 第二级：架构目录 (windows-x64等)
                $archDirs = Get-ChildItem $runtimeDir.FullName -Directory -ErrorAction SilentlyContinue
                
                foreach ($archDir in $archDirs) {
                    try {
                        # 第三级：版本目录
                        $versionDirs = Get-ChildItem $archDir.FullName -Directory -ErrorAction SilentlyContinue
                        
                        foreach ($versionDir in $versionDirs) {
                            $javaExe = Join-Path $versionDir.FullName "bin\java.exe"
                            if (Test-Path $javaExe) {
                                $release = Join-Path $versionDir.FullName "release"
                                $version = ""
                                
                                if (Test-Path $release) {
                                    $verLine = Get-Content $release -ErrorAction SilentlyContinue |
                                        Where-Object { $_ -like 'JAVA_VERSION=*' }
                                    if ($verLine) {
                                        $version = ($verLine -split '"')[1].Trim('"')
                                    }
                                }
                                
                                if (-not $version) {
                                    # 如果无法从 release 文件获取版本，尝试从目录名解析
                                    if ($versionDir.Name -match '(\d+)') {
                                        $version = $matches[1]
                                    }
                                }
                                
                                $vendor = "microsoft"
                                $parsedVersion = Parse-JavaVersion $version
                                
                                $results += [pscustomobject]@{
                                    name    = $versionDir.Name
                                    version = $version
                                    versionObj = $parsedVersion
                                    vendor  = $vendor
                                    path    = $versionDir.FullName
                                    source  = "store"
                                }
                                
                                Write-Info "Found Microsoft Store Java: $javaExe"
                                
                                if ($Global:JmpDebug) {
                                    Log-Debug "Microsoft Store Java: $javaExe ($version)"
                                }
                            }
                        }
                    } catch {
                        if ($Global:JmpDebug) {
                                            Log-Debug "Error scanning arch directory ${archDir.FullName}: $_"
                                        }                    }
                }
            } catch {
                if ($Global:JmpDebug) {
                    Log-Debug "Error scanning runtime directory ${runtimeDir.FullName}: $_"
                }
            }
        }
    } catch {
        Write-Warning "Microsoft Store Java scan failed: $_"
    }
    
    if ($Global:JmpDebug) {
        Log-Debug "Microsoft Store scan completed. Found $($results.Count) Java installations."
    }
    
    return $results
}

function Scan-Java-CommonPaths {
    $results = @()
    $candidates = @()
    
    try {
        # 1. PATH 下的 java.exe
        $cmds = Get-Command java -ErrorAction SilentlyContinue
        foreach ($c in $cmds) {
            if ($c.Source) {
                $javaHome = Split-Path (Split-Path $c.Source -Parent) -Parent
                $candidates += $javaHome
            }
        }
        
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
                    $javaExe = Join-Path $d.FullName "bin\java.exe"
                    if (Test-Path $javaExe) {
                        $candidates += $d.FullName
                    }
                }
            } catch {
                if ($Global:JmpDebug) {
                    Log-Debug "Error scanning common path ${root}: $_"
                }
            }
        }
        
        # 去重
        $candidates = $candidates | Sort-Object -Unique
        
        # 构建结果对象
        foreach ($javaHome in $candidates) {
            $javaExe = Join-Path $javaHome "bin\java.exe"
            if (-not (Test-Path $javaExe)) { continue }
            
            # 尝试获取版本
            $release = Join-Path $javaHome "release"
            $version = ""
            
            if (Test-Path $release) {
                $verLine = Get-Content $release -ErrorAction SilentlyContinue |
                    Where-Object { $_ -like 'JAVA_VERSION=*' }
                if ($verLine) {
                    $version = ($verLine -split '"')[1].Trim('"')
                }
            }
            
            # 如果无法从 release 文件获取版本，尝试运行 java -version
            if (-not $version) {
                try {
                    $verLine = & $javaExe -version 2>&1 | Select-Object -First 1
                    if ($verLine -match '"([\d._]+)"') {
                        $version = $matches[1]
                    }
                } catch {}
            }
            
            $vendor = Detect-Vendor $javaHome
            $parsedVersion = Parse-JavaVersion $version
            
            $results += [pscustomobject]@{
                name    = Split-Path $javaHome -Leaf
                version = $version
                versionObj = $parsedVersion
                vendor  = $vendor
                path    = $javaHome
                source  = "common"
            }
            
            if ($Global:JmpDebug) {
                Log-Debug "Found Java from common paths: $javaHome ($version)"
            }
        }
    } catch {
        Write-Warning "Common paths scan failed: $_"
    }
    
    if ($Global:JmpDebug) {
        Log-Debug "Common paths scan completed. Found $($results.Count) Java installations."
    }
    
    return $results
}

function Scan-Java-Light {
    $results = @()
    
    Write-Info "Running light scan (fast mode)..."
    
    # 1. 注册表扫描（极快，< 1秒）
    Write-Info "Scanning registry..."
    $results += Scan-Java-Registry
    
    # 2. Microsoft Store 扫描（极快，< 0.5秒）
    $results += Scan-Java-MicrosoftStore
    
    # 3. 常见目录扫描（中等，< 2秒）
    Write-Info "Scanning common paths..."
    $results += Scan-Java-CommonPaths
    
    # 去重（按路径）
    $uniqueResults = @{}
    foreach ($result in $results) {
        if (-not $uniqueResults.ContainsKey($result.path)) {
            $uniqueResults[$result.path] = $result
        }
    }
    
    $finalResults = @($uniqueResults.Values | Sort-Object { $_.versionObj.Major }, { $_.versionObj.Minor }, { $_.versionObj.Patch })
    
    Write-Success "Light scan completed. Found $($finalResults.Count) Java installations."
    
    return $finalResults
}

# ============================================================================
# BFS 深度扫描器（广度优先搜索，覆盖更全面）
# ============================================================================

# Java 相关关键词
$Script:JavaKeywords = @(
    "java", "jdk", "jre", "openjdk", "adoptium", "temurin", 
    "zulu", "corretto", "graalvm", "liberica", "microsoft"
)

# 需要排除的目录关键词
$Script:ExcludeKeywords = @(
    "windows", "system32", "winsxs", "node_modules", "cache", "temp", 
    "microsoft", "google", "adobe", "nvidia", "intel", "amd"
)

function Get-SearchRoots {
    $roots = @()
    
    # 添加用户目录
    $roots += $env:APPDATA
    $roots += $env:LOCALAPPDATA
    $roots += $env:USERPROFILE
    
    # 添加项目目录
    $roots += $Script:ProjectRoot
    
    # 添加 Program Files 目录
    if (Test-Path $env:ProgramFiles) {
        $roots += $env:ProgramFiles
    }
    if (Test-Path "$env:ProgramFiles(x86)") {
        $roots += "$env:ProgramFiles(x86)"
    }
    
    # 添加所有固定驱动器的 Program Files 和 Java 关键词目录
    try {
        $drives = Get-PSDrive -PSProvider FileSystem | 
            Where-Object { $_.Root -match '^[A-Z]:\\$' } | 
            Select-Object -ExpandProperty Root
        
        foreach ($drive in $drives) {
            # 不添加驱动器根目录，避免扫描整个驱动器
            
            # 添加驱动器下的 Program Files
            $programFiles = Join-Path $drive "Program Files"
            $programFilesX86 = Join-Path $drive "Program Files (x86)"
            
            if (Test-Path $programFiles) {
                $roots += $programFiles
            }
            if (Test-Path $programFilesX86) {
                $roots += $programFilesX86
            }
            
            # 添加根目录下包含 Java 关键词的目录
            try {
                $rootDirs = Get-ChildItem $drive -Directory -ErrorAction SilentlyContinue |
                    Where-Object { 
                        $dirName = $_.Name.ToLower()
                        $Script:JavaKeywords | Where-Object { $dirName -like "*$_*" }
                    }
                
                foreach ($dir in $rootDirs) {
                    $roots += $dir.FullName
                }
            } catch {
                if ($Global:JmpDebug) {
                    Log-Debug "Error scanning drive ${drive}: $_"
                }
            }
        }
    } catch {
        if ($Global:JmpDebug) {
            Log-Debug "Error getting drives: $_"
        }
    }
    
    # 去重并过滤不存在的路径
    $uniqueRoots = $roots | 
        Sort-Object -Unique | 
        Where-Object { Test-Path $_ }
    
    if ($Global:JmpDebug) {
        Log-Debug "Search roots: $($uniqueRoots -join ', ')"
    }
    
    return $uniqueRoots
}

function ShouldScanDirectory {
    param([string]$Path)
    
    $dirName = Split-Path $Path -Leaf
    
    # 检查是否包含排除关键词
    $dirNameLower = $dirName.ToLower()
    foreach ($exclude in $Script:ExcludeKeywords) {
        if ($dirNameLower -like "*$exclude*") {
            if ($Global:JmpDebug) {
                Log-Debug "Excluding directory (matches exclude keyword): $Path"
            }
            return $false
        }
    }
    
    # 检查是否包含 Java 关键词
    foreach ($keyword in $Script:JavaKeywords) {
        if ($dirNameLower -like "*$keyword*") {
            return $true
        }
    }
    
    return $false
}

function Scan-Java-BFS {
    param([int]$MaxDepth = 8)
    
    $results = @()
    $searchRoots = Get-SearchRoots
    
    if ($Global:JmpDebug) {
        Write-Info "Running BFS deep scan (depth: $MaxDepth)..."
        Write-Info "Searching $($searchRoots.Count) root directories..."
    } else {
        Write-Info "Scanning for additional Java installations..."
    }
    
    $processedCount = 0
    $foundCount = 0
    
    foreach ($root in $searchRoots) {
        if ($Global:JmpDebug) {
            Log-Debug "BFS scanning root: $root"
        }
        
        # 使用队列实现 BFS
        $queue = [System.Collections.Queue]::new()
        $queue.Enqueue(@($root, 0))
        
        while ($queue.Count -gt 0) {
            $item = $queue.Dequeue()
            $current = $item[0]
            $depth = $item[1]
            
            # 超过最大深度，跳过
            if ($depth -gt $MaxDepth) {
                continue
            }
            
            # 检查目录是否存在
            if (-not (Test-Path $current)) {
                continue
            }
            
            $processedCount++
            
            # 每 100 个目录显示一次进度（仅在调试模式下）
            if ($Global:JmpDebug -and $processedCount % 100 -eq 0) {
                Write-Info "Scanned $processedCount directories, found $foundCount Java installations..."
            }
            
            try {
                # 使用 .NET Directory.EnumerateDirectories 提升性能
                $dirs = [System.IO.Directory]::EnumerateDirectories($current)
                
                foreach ($dir in $dirs) {
                    try {
                        $dirName = Split-Path $dir -Leaf
                        
                        # 深度 0：只扫描包含关键词的目录
                        # 但是对于 Program Files 等关键目录，放宽限制
                        if ($depth -eq 0) {
                            $parentDir = Split-Path $dir -Parent
                            # 如果父目录是 Program Files 或项目根目录，允许搜索
                            $isKeyParent = ($parentDir -like "*Program Files*") -or 
                                          ($parentDir -eq $Script:ProjectRoot) -or
                                          ($parentDir -like "*Java*")
                            
                            if (-not $isKeyParent -and -not (ShouldScanDirectory $dir)) {
                                continue
                            }
                        }
                        
                        # 检查是否包含 java.exe
                        $javaExe = Join-Path $dir "bin\java.exe"
                        if (Test-Path $javaExe) {
                            # 验证是否是有效的 Java 安装
                            $release = Join-Path $dir "release"
                            $version = ""
                            
                            if (Test-Path $release) {
                                $verLine = Get-Content $release -ErrorAction SilentlyContinue |
                                    Where-Object { $_ -like 'JAVA_VERSION=*' }
                                if ($verLine) {
                                    $version = ($verLine -split '"')[1].Trim('"')
                                }
                            }
                            
                            # 如果无法从 release 文件获取版本，尝试运行 java -version
                            if (-not $version) {
                                try {
                                    $verLine = & $javaExe -version 2>&1 | Select-Object -First 1
                                    if ($verLine -match '"([\d._]+)"') {
                                        $version = $matches[1]
                                    }
                                } catch {}
                            }
                            
                            if ($version) {
                                $vendor = Detect-Vendor $dir
                                $parsedVersion = Parse-JavaVersion $version
                                
                                $results += [pscustomobject]@{
                                    name    = Split-Path $dir -Leaf
                                    version = $version
                                    versionObj = $parsedVersion
                                    vendor  = $vendor
                                    path    = $dir
                                    source  = "bfs"
                                }
                                
                                $foundCount++
                                
                                if ($Global:JmpDebug) {
                                    Log-Debug "Found Java from BFS: $dir ($version)"
                                }
                            }
                        } else {
                            # 如果不是 Java 目录，继续深度搜索
                            $queue.Enqueue(@($dir, $depth + 1))
                        }
                    } catch {
                        # 忽略单个目录的错误
                        if ($Global:JmpDebug) {
                            Log-Debug "Error processing directory ${dir}: $_"
                        }
                    }
                }
            } catch {
                # 忽略目录枚举错误（权限问题等）
                if ($Global:JmpDebug) {
                    Log-Debug "Error enumerating directory ${current}: $_"
                }
            }
        }
    }
    
    if ($Global:JmpDebug) {
        Write-Info "BFS scan completed. Scanned $processedCount directories, found $foundCount Java installations."
    }
    
    return $results
}
