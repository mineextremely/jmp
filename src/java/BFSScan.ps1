# BFS 深度扫描模块
# 包含广度优先搜索功能，覆盖更全面

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