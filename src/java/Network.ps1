# 网络下载模块
# 包含网络检测、下载逻辑等功能

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