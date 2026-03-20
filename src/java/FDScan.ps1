# FD 深度扫描模块
# 使用 fd 工具进行全磁盘搜索

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