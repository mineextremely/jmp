# 轻量模式扫描模块
# 包含注册表、Microsoft Store、常见目录的快速扫描功能

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
                        }
                    }
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
