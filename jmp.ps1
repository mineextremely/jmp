# ========================
# 参数处理
# ========================

# 初始化参数数组
$JmpArgs = @()
$EnableDebug = $false

foreach ($arg in $args) {
    if ($arg -eq "-debug") {
        $EnableDebug = $true
    } else {
        # 强制转换为字符串，避免数字截断
        $JmpArgs += [string]$arg
    }
}

if ($EnableDebug) {
    Write-Host "Debug: Raw JmpArgs count: $($JmpArgs.Count)" -ForegroundColor Gray
    for ($i = 0; $i -lt $JmpArgs.Count; $i++) {
        Write-Host "Debug: Raw JmpArgs[$i]: '$($JmpArgs[$i])' (Type: $($JmpArgs[$i].GetType().Name))" -ForegroundColor Gray
    }
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$VersionTag = "Beta3"

# ========================
# Utilities
# ========================

function Show-Header {
    Write-Host "JMP $VersionTag - Java Manage Powershell"
}

function Parse-JavaVersion {
    param([string]$VersionString)
    
    # 初始化版本对象
    $versionObj = [pscustomobject]@{
        original = $VersionString
        major = $null
        minor = $null
        patch = $null
        build = $null
        isJava8 = $false
    }
    
    # 处理Java 8的特殊格式: 1.8.0_472
    if ($VersionString -match '^1\.8\.0_(\d+)$') {
        $versionObj.major = 8
        $versionObj.minor = 0
        $versionObj.patch = [int]$matches[1]
        $versionObj.build = $matches[1]
        $versionObj.isJava8 = $true
        return $versionObj
    }
    
    # 处理标准格式: major.minor.patch
    if ($VersionString -match '^(\d+)\.(\d+)\.(\d+)$') {
        $versionObj.major = [int]$matches[1]
        $versionObj.minor = [int]$matches[2]
        $versionObj.patch = [int]$matches[3]
        return $versionObj
    }
    
    # 处理可能的两段格式: major.minor
    if ($VersionString -match '^(\d+)\.(\d+)$') {
        $versionObj.major = [int]$matches[1]
        $versionObj.minor = [int]$matches[2]
        $versionObj.patch = $null
        return $versionObj
    }
    
    # 处理只有major的格式: major
    if ($VersionString -match '^(\d+)$') {
        $versionObj.major = [int]$matches[1]
        $versionObj.minor = $null
        $versionObj.patch = $null
        return $versionObj
    }
    
    # 如果都不匹配，尝试更通用的解析
    # 移除下划线和加号等特殊字符，替换为点
    $normalized = $VersionString -replace '[_\+\+]', '.'
    $parts = $normalized -split '\.' | Where-Object { $_ -match '\d' }
    
    if ($parts.Count -ge 1) {
        $versionObj.major = [int]$parts[0]
        $versionObj.minor = if ($parts.Count -ge 2) { [int]$parts[1] } else { $null }
        $versionObj.patch = if ($parts.Count -ge 3) { [int]$parts[2] } else { $null }
        
        # 特殊处理：如果major=1且minor=8，则认为是Java 8
        if ($versionObj.major -eq 1 -and $versionObj.minor -eq 8) {
            $versionObj.major = 8
            $versionObj.minor = $null  # 用户输入"1.8"意味着他们只关心Java 8，不关心具体的minor/patch
            $versionObj.isJava8 = $true
        }
    }
    
    return $versionObj
}

function ConvertTo-SortableVersion {
    param([string]$VersionString)
    # 将下划线替换为点，以便System.Version可以解析
    $normalized = $VersionString -replace '_', '.'
    # 移除可能存在的非数字后缀（如+号等）
    # 但Java版本字符串通常是干净的，所以直接返回
    return $normalized
}

function Show-Usage {
    Write-Warning "Usage: jmp <command> [args]"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  scan                 - Discover Java installations (ES-first)"
    Write-Host "  list                 - List all discovered Java"
    Write-Host "  use <version> [vendor]- Switch Java version"
    Write-Host "  current              - Show current JAVA_HOME"
    Write-Host "  version              - Show script version"
    Write-Host "  help                 - Show this help"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -debug               - Enable debug output"
    Show-Header
}

function Load-Json($Path) {
    if (-not (Test-Path $Path)) { return $null }
    try {
        return Get-Content $Path -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "Failed to read JSON file: $Path"
        return $null
    }
}

function Save-Json($Path, $Obj) {
    try {
        $Obj | ConvertTo-Json -Depth 6 | Set-Content $Path -Encoding UTF8
    } catch {
        Write-Warning "Failed to save JSON file: $Path"
    }
}

function Detect-Vendor($Path) {
    $pathLower = $Path.ToLower()
    $vendors = @()
    
    if ($pathLower -match "temurin|adoptium") { $vendors += "temurin" }
    if ($pathLower -match "graalvm") { $vendors += "graalvm" }
    if ($pathLower -match "zulu") { $vendors += "zulu" }
    if ($pathLower -match "oracle") { $vendors += "oracle" }
    
    # 如果没有检测到任何vendor，返回"unknown"
    if ($vendors.Count -eq 0) { return "unknown" }
    
    # 如果检测到多个vendor，返回第一个，但可以记录所有
    return $vendors[0]
}

# ========================
# Everything (ES)
# ========================

function Get-ESPath {
    # 首先检查PATH中的es命令
    $esCmd = Get-Command es -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if ($esCmd -and (Test-Path $esCmd)) {
        return $esCmd
    }
    
    # 如果PATH中没有，检查常见安装位置
    $commonPaths = @(
        "$env:ProgramFiles\Everything\es.exe",
        "$env:LOCALAPPDATA\Everything\es.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    
    return $commonPaths
}

function Scan-Java-WithES {
    param($EsPath)

    $results = @()

    try {
        # [FIX] remove double backslash, use single quotes for literal string
        $searchQuery = 'bin\java.exe' 
        
        # 使用ES搜索所有java.exe文件，返回JSON格式
        # 注意：若 es 没找到任何内容，它会返回空字符串，ConvertFrom-Json 会报错，
        # 所以我们允许报错进入 catch 或者是处理空输出。
        $rawOutput = & $EsPath "-json" "-count" "1000" $searchQuery 2>$null
        
        if (-not $rawOutput) {
            # ES 没找到结果，或者出错了
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
        # 只有在真的出错时才显示 Warning，如果只是没找到，可能不需要太啰嗦，
        # 但为了调试，保留 Warning 是好的。
        # 注意：如果是 "No output from ES" 错误，说明真的没搜到。
        # Write-Warning "ES scan failed or found nothing: $_"
        
        # fallback 逻辑保持不变...
        try {
            & $EsPath "java.exe" 2>$null |
            Where-Object { $_ -match '\\bin\\java\.exe$' } |
            ForEach-Object {
                # ... (原有 fallback 代码保持不变) ...
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
                    source  = "es-fallback"
                }
            }
        } catch {
            Write-Warning "ES fallback search also failed: $_"
        }
    }

    return $results
}

# ========================
# Fallback Scan
# ========================

function Scan-Java-Fallback {
    $candidates = @()

    if ($env:JAVA_HOME) {
        $candidates += $env:JAVA_HOME
    }

    try {
        $javaPaths = where java 2>$null
        if ($javaPaths) {
            $javaPaths | ForEach-Object {
                $candidates += Split-Path (Split-Path $_ -Parent) -Parent
            }
        }
    } catch {}

    $knownRoots = @(
        "$env:ProgramFiles\Java",
        "D:\Program Files\Java"
    ) | Where-Object { Test-Path $_ }

    foreach ($root in $knownRoots) {
        $subdirs = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue
        if ($subdirs) {
            $subdirs | ForEach-Object { $candidates += $_.FullName }
        }
    }

    $results = @()

    $candidates | Sort-Object -Unique | ForEach-Object {
        $javaHome = $_
        if (-not (Test-Path (Join-Path $javaHome "bin\java.exe"))) { return }
        if (-not (Test-Path (Join-Path $javaHome "release"))) { return }

        $verLine = Get-Content (Join-Path $javaHome "release") -ErrorAction SilentlyContinue |
            Where-Object { $_ -like 'JAVA_VERSION=*' }

        if (-not $verLine) { return }

        $version = ($verLine -split '"')[1].Trim('"')
        $parsedVersion = Parse-JavaVersion $version
        
        $results += [pscustomobject]@{
            name    = Split-Path $javaHome -Leaf
            version = $version
            versionObj = $parsedVersion
            vendor  = Detect-Vendor $javaHome
            path    = $javaHome
            source  = "fallback"
        }
    }

    return $results
}

# ========================
# Scan (Controller)
# ========================

function Scan-Java {
    $results = @()
    $es = Get-ESPath

    if ($es) {
        if ($EnableDebug) { Write-Info "Using Everything (ES) for scanning" }
        $results = Scan-Java-WithES $es
    } else {
        if ($EnableDebug) { Write-Warning "Everything not found, using fallback scan" }
        $results = Scan-Java-Fallback
    }

    # 在保存前转换versionObj为可序列化的对象
    $serializableResults = @()
    foreach ($item in $results) {
        $serializableItem = [ordered]@{
            name = $item.name
            version = $item.version
            versionObj = @{
                original = $item.versionObj.original
                major = $item.versionObj.major
                minor = $item.versionObj.minor
                patch = $item.versionObj.patch
                build = $item.versionObj.build
                isJava8 = $item.versionObj.isJava8
            }
            vendor = $item.vendor
            path = $item.path
            source = $item.source
        }
        $serializableResults += $serializableItem
    }
    
    Save-Json (Join-Path $ScriptRoot "java-versions.json") $serializableResults
    Write-Success "Scan completed. Found $($results.Count) Java installations."
    if ($results.Count -gt 0) {
        $results | ForEach-Object { Write-Info "  - $($_.version) ($($_.vendor)) at $($_.path)" }
    }
}

function List-Java {
    $data = Load-Json (Join-Path $ScriptRoot "java-versions.json")
    if (-not $data) {
        Write-Warning "No scan data found. Run 'jmp scan' first."
        return
    }

    if ($data.Count -eq 0) {
        Write-Warning "No Java installations found. Please run 'jmp scan' to discover Java installations."
        return
    }

    Write-Info "Available Java installations:"
    $data |
        Sort-Object { 
            if ($_.versionObj -and $_.versionObj.major -ne $null) {
                # 使用解析后的版本对象进行排序
                $major = $_.versionObj.major
                $minor = $_.versionObj.minor
                $patch = $_.versionObj.patch
                # 创建可排序的字符串
                "{0:D4}.{1:D4}.{2:D4}" -f $major, $minor, $patch
            } else {
                # 回退到原始版本字符串
                $_.version
            }
        } |
        Format-Table version, vendor, name, source -AutoSize
}

function Show-Current {
    if ($env:JAVA_HOME) {
        Write-Info "JAVA_HOME=$env:JAVA_HOME"
        try {
            $javaCmd = "$env:JAVA_HOME\bin\java.exe"
            if (Test-Path $javaCmd) {
                $javaVersion = & $javaCmd -version 2>&1 | Select-Object -First 1
                Write-Info "Java version: $javaVersion"
            } else {
                Write-Warning "Java executable not found at: $javaCmd"
            }
        } catch {
            Write-Warning "Java not accessible at $env:JAVA_HOME"
        }
    } else {
        Write-Warning "JAVA_HOME not set."
    }
}

function Show-Usage {
    Write-Warning "Usage: jmp <command> [args]"
    Write-Info ""
    Write-Info "Commands:"
    Write-Info "  scan                 - Discover Java installations (ES-first)"
    Write-Info "  list                 - List all discovered Java"
    Write-Info "  use <version> [vendor]- Switch Java version"
    Write-Info "  current              - Show current JAVA_HOME"
    Write-Info "  version              - Show script version"
    Write-Info "  help                 - Show this help"
    Write-Info ""
    Write-Info "Options:"
    Write-Info "  -debug               - Enable debug output"
    Show-Header
}

# 将输出函数定义移到脚本开头（在Show-Header之后）
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# ========================
# List
# ========================

function List-Java {
    $data = Load-Json (Join-Path $ScriptRoot "java-versions.json")
    if (-not $data) {
        Write-Warning "No scan data found. Run 'jmp scan' first."
        return
    }

    if ($data.Count -eq 0) {
        Write-Host "No Java installations found. Please run 'jmp scan' to discover Java installations."
        return
    }

    Write-Host "Available Java installations:"
    $data |
        Sort-Object { 
            if ($_.versionObj -and $_.versionObj.major -ne $null) {
                # 使用解析后的版本对象进行排序
                $major = $_.versionObj.major
                $minor = $_.versionObj.minor
                $patch = $_.versionObj.patch
                # 创建可排序的字符串
                "{0:D4}.{1:D4}.{2:D4}" -f $major, $minor, $patch
            } else {
                # 回退到原始版本字符串
                $_.version
            }
        } |
        Format-Table version, vendor, name, source -AutoSize
}

# ========================
# Use
# ========================

function Get-VendorPriority {
    $vendorFile = Load-Json (Join-Path $ScriptRoot "vendor-priority.json")
    if ($vendorFile -and $vendorFile.priority) {
        return $vendorFile.priority
    } else {
        # 默认优先级
        return @("temurin", "zulu", "oracle", "graalvm", "unknown")
    }
}

function Use-Java {
    param(
        [string]$Version,
        [string]$Vendor
    )

    # 确保Version是字符串
    $Version = [string]$Version
    if ($EnableDebug) { Write-Host "Debug: Received version '$Version' (Type: $($Version.GetType().Name)) and vendor '$Vendor'" }
    
    $jsonData = Load-Json (Join-Path $ScriptRoot "java-versions.json")
    if (-not $jsonData) {
        Write-ErrorMsg "No scan data found. Run 'jmp scan' first."
        return
    }

    if ($jsonData.Count -eq 0) {
        Write-ErrorMsg "No Java installations found. Run 'jmp scan' first."
        return
    }
    
    # 转换JSON数据为PSCustomObject以便更容易访问
    $data = @()
    foreach ($item in $jsonData) {
        $data += [pscustomobject]@{
            name = $item.name
            version = $item.version
            versionObj = [pscustomobject]$item.versionObj
            vendor = $item.vendor
            path = $item.path
            source = $item.source
        }
    }

    if ($EnableDebug) { Write-Host "Looking for Java version: $Version" }
    
    # 解析用户输入的版本
    $userVersion = Parse-JavaVersion $Version
    if ($EnableDebug) { 
        Write-Host "Debug: Parsed user version - Major: $($userVersion.major), Minor: $($userVersion.minor), Patch: $($userVersion.patch), IsJava8: $($userVersion.isJava8)"
    }
    
    # 收集所有可用版本用于显示
    $allVersions = $data.version | Sort-Object -Unique
    if ($EnableDebug) { Write-Host "Available versions: $($allVersions -join ', ')" }
    
    # 基于解析后的版本进行匹配
    $candidates = @()
    
    foreach ($item in $data) {
        $itemVersion = $item.versionObj
        
        if (-not $itemVersion -or $itemVersion.major -eq $null) {
            # 如果版本对象解析失败，跳过
            continue
        }
        
        # 检查版本是否匹配
        $match = $false
        
        # 情况1: 用户指定了完整版本 (如 "17.0.17")
        if ($userVersion.major -ne $null -and $userVersion.minor -ne $null -and $userVersion.patch -ne $null) {
            if ($itemVersion.major -eq $userVersion.major -and 
                $itemVersion.minor -eq $userVersion.minor -and 
                $itemVersion.patch -eq $userVersion.patch) {
                $match = $true
            }
        }
        # 情况2: 用户指定了主版本和次版本 (如 "17.0")
        elseif ($userVersion.major -ne $null -and $userVersion.minor -ne $null -and $userVersion.patch -eq $null) {
            if ($itemVersion.major -eq $userVersion.major -and 
                $itemVersion.minor -eq $userVersion.minor) {
                $match = $true
            }
        }
        # 情况3: 用户只指定了主版本 (如 "17", "8")
        elseif ($userVersion.major -ne $null -and $userVersion.minor -eq $null -and $userVersion.patch -eq $null) {
            if ($itemVersion.major -eq $userVersion.major) {
                $match = $true
            }
        }

        
        if ($match) {
            $candidates += $item
        }
    }

    # 修改 Use-Java 函数中的提示信息
    if ($candidates.Count -eq 0) {
        # 构建可用主版本号列表
        $availableMajors = $data | ForEach-Object { $_.versionObj.major } | Sort-Object -Unique

        # 针对 "1.8" 提示
        if ($Version -eq "1.8") {
            Write-Warning "You entered '$Version', but this is not a valid Java version format."
            Write-Info "If you want to switch to Java 8, please enter '8'."
        } else {
            # 改进提示：如果用户输入1-7，给出更友好的提示
            if ($userVersion.major -ne $null -and $userVersion.major -lt 8) {
                Write-Warning "Java version '$Version' not found. Java versions before 8 are not supported."
                Write-Info "The first LTS version is Java 8 (released in 2014)."
            } else {
                Write-Warning "Java version '$Version' not found."
            }
            Write-Info "Available major versions: $($availableMajors -join ', ')"
        }
        return
    }

    if ($EnableDebug) { Write-Host "Found $($candidates.Count) matching version(s): $($candidates.version -join ', ')" }

    # 初始化$match变量
    $match = $null

    if ($Vendor) {
        # 修正vendor匹配逻辑
        $match = $candidates | Where-Object { 
            if ($_.vendor -is [array]) {
                $_.vendor -contains $Vendor
            } else {
                $_.vendor -eq $Vendor
            }
        } | Select-Object -First 1
    
        if (-not $match) {
            Write-Warning "Vendor '$Vendor' not found for version '$Version'."
        
            # 显示该版本下可用的vendor
            $availableVendors = $candidates.vendor | Sort-Object -Unique
            Write-Info "Available vendors for version '$Version': $($availableVendors -join ', ')"
        
            # 回退到优先级列表，但明确告知用户
            Write-Info "Falling back to default vendor priority."
            $Vendor = $null
        }
    }

    # 如果没有指定vendor或指定vendor没找到，使用优先级列表
    if (-not $match) {
        foreach ($v in Get-VendorPriority) {
            $match = $candidates | Where-Object { 
                if ($_.vendor -is [array]) {
                    $_.vendor -contains $v
                } else {
                    $_.vendor -eq $v
                }
            } | Select-Object -First 1
            if ($match) { 
                if ($EnableDebug) { Write-Host "Selected vendor: $v" }
                break 
            }
        }
    }

    # 如果还没有找到，选择第一个候选
    if (-not $match) {
        $match = $candidates | Select-Object -First 1
    }

    if (-not $match) {
        Write-ErrorMsg "No suitable Java found for version '$Version'."
        return
    }

    $env:JAVA_HOME = $match.path
    # 移除旧的JAVA_HOME路径，然后添加新的路径
    $env:PATH = $env:PATH -replace [regex]::Escape("$env:JAVA_HOME\bin;"), ""
    $env:PATH = $env:PATH -replace [regex]::Escape("$env:JAVA_HOME\bin"), ""
    $env:PATH = "$($match.path)\bin;$env:PATH"
    
    Write-Success "Switched to Java $($match.versionObj.major) ($($match.vendor))"
    Write-Info "JAVA_HOME = $($match.path)"
    Write-Info "Version: $($match.version)"
    Write-Info "Added to PATH: $($match.path)\bin"
    
    # 验证Java版本
    try {
        $javaCmd = "$($match.path)\bin\java.exe"
        if (Test-Path $javaCmd) {
            $javaVersion = & $javaCmd -version 2>&1 | Select-Object -First 1
            Write-Info "Java version: $javaVersion"
        } else {
            Write-Warning "Java executable not found at: $javaCmd"
        }
    } catch {
        Write-Warning "Could not verify Java installation: $_"
    }
}

# ========================
# Current
# ========================

function Show-Current {
    if ($env:JAVA_HOME) {
        Write-Host "JAVA_HOME=$env:JAVA_HOME"
        try {
            $javaCmd = "$env:JAVA_HOME\bin\java.exe"
            if (Test-Path $javaCmd) {
                $javaVersion = & $javaCmd -version 2>&1
                Write-Host "Java version: $javaVersion"
            } else {
                Write-Warning "Java executable not found at: $javaCmd"
            }
        } catch {
            Write-Warning "Java not accessible at $env:JAVA_HOME"
        }
    } else {
        Write-Warning "JAVA_HOME not set."
    }
}

# ========================
# 命令分发
# ========================

if ($JmpArgs.Count -eq 0) {
    Show-Usage
    return
}

$Command = $JmpArgs[0]

switch ($Command) {
    "scan"    { Scan-Java }
    "list"    { List-Java }
    "current" { Show-Current }
    "version" { Show-Header }
    "help"    { Show-Usage }

    "use" {
        if ($JmpArgs.Count -lt 2) { Show-Usage; return }

        # 直接索引，确保是字符串
        $version = [string]$JmpArgs[1]
        $vendor  = if ($JmpArgs.Count -ge 3) { [string]$JmpArgs[2] } else { $null }

        if ($EnableDebug) { 
            Write-Host "Debug: Calling Use-Java with version '$version' and vendor '$vendor'" -ForegroundColor Gray
            Write-Host "Debug: version type: $($version.GetType().Name)" -ForegroundColor Gray
        }

        Use-Java -Version $version -Vendor $vendor
    }

    default {
        Write-Warning "Unknown command: $Command"
        Show-Usage
    }
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}