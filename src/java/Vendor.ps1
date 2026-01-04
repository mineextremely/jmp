# src/java/Vendor.ps1

function Detect-Vendor($Path) {
    if (-not $Path) {
        return "unknown"
    }

    if ($Global:JmpDebug) {
        Log-Debug "Detecting vendor for path: $Path"
    }

    # 策略1: 路径关键词检测（快速）
    $vendor = Detect-VendorByPath $Path
    if ($Global:JmpDebug) {
        Log-Debug "Vendor by path: $vendor"
    }
    if ($vendor -ne "unknown") {
        return $vendor
    }

    # 策略2: release 文件检测（准确）
    $vendor = Detect-VendorByReleaseFile $Path
    if ($Global:JmpDebug) {
        Log-Debug "Vendor by release file: $vendor"
    }
    if ($vendor -ne "unknown") {
        return $vendor
    }

    # 策略3: java --version 输出检测（兜底）
    $vendor = Detect-VendorByVersionOutput $Path
    if ($Global:JmpDebug) {
        Log-Debug "Vendor by version output: $vendor"
    }
    if ($vendor -ne "unknown") {
        return $vendor
    }

    # 所有策略都失败，返回 unknown
    return "unknown"
}

function Detect-VendorByPath($Path) {
    $pathLower = $Path.ToLower()
    $vendors = @()
    
    if ($pathLower -match "temurin|adoptium") { $vendors += "temurin" }
    if ($pathLower -match "graalvm") { $vendors += "graalvm" }
    if ($pathLower -match "zulu") { $vendors += "zulu" }
    if ($pathLower -match "oracle") { $vendors += "oracle" }
    if ($pathLower -match "liberica|bellsoft") { $vendors += "liberica" }
    if ($pathLower -match "corretto|amazon") { $vendors += "corretto" }
    
    if ($vendors.Count -eq 0) { return "unknown" }
    return $vendors[0]
}

function Detect-VendorByReleaseFile($Path) {
    $releaseFile = Join-Path $Path "release"

    if (-not (Test-Path $releaseFile)) {
        if ($Global:JmpDebug) {
            Log-Debug "Release file not found: $releaseFile"
        }
        return "unknown"
    }

    try {
        $releaseContent = Get-Content $releaseFile -Raw -ErrorAction Stop

        if ($Global:JmpDebug) {
            if ($releaseContent.Length -gt 0) {
                Log-Debug "Release file content (first 500 chars): $($releaseContent.Substring(0, [Math]::Min(500, $releaseContent.Length)))"
            } else {
                Log-Debug "Release file content is empty"
            }
        }

        # 解析 IMPLEMENTOR 字段
        if ($releaseContent -match 'IMPLEMENTOR="([^"]+)"') {
            $implementor = $matches[1].ToLower()

            if ($Global:JmpDebug) {
                Log-Debug "Found IMPLEMENTOR: $implementor"
            }

            # 映射 IMPLEMENTOR 到标准 vendor 名称（使用大小写不敏感匹配）
            if ($implementor -imatch "bellsoft|liberica") { return "liberica" }
            if ($implementor -imatch "amazon|corretto") { return "corretto" }
            if ($implementor -imatch "eclipse|temurin|adoptium") { return "temurin" }
            if ($implementor -imatch "azul|zulu") { return "zulu" }
            if ($implementor -imatch "oracle") { return "oracle" }
            if ($implementor -imatch "graalvm") { return "graalvm" }
        }

        return "unknown"
    } catch {
        if ($Global:JmpDebug) {
            Log-Debug "Error reading release file: $_"
        }
        return "unknown"
    }
}

function Detect-VendorByVersionOutput($Path) {
    $javaExe = Join-Path $Path "bin\java.exe"

    if (-not (Test-Path $javaExe)) {
        return "unknown"
    }

    try {
        # 使用 -XshowSettings:properties 获取更详细的信息
        $output = & $javaExe -XshowSettings:properties -version 2>&1 | Out-String

        if ($Global:JmpDebug) {
            if ($output.Length -gt 0) {
                Log-Debug "Java properties output (first 500 chars): $($output.Substring(0, [Math]::Min(500, $output.Length)))"
            } else {
                Log-Debug "Java properties output is empty"
            }
        }

        # 检查 GraalVM（优先检查，因为 GraalVM 可能基于其他发行版）
        if ($output -imatch "graalvm") { return "graalvm" }

        # 解析 java.vendor 属性
        if ($output -match 'java\.vendor\s*=\s*(.+)') {
            $vendor = $matches[1].Trim()

            if ($Global:JmpDebug) {
                Log-Debug "Found java.vendor: $vendor"
            }

            # 根据 java.vendor 值进行匹配
            if ($vendor -imatch "BellSoft") { return "liberica" }
            if ($vendor -imatch "Amazon\.com Inc\.") { return "corretto" }
            if ($vendor -imatch "Amazon") { return "corretto" }
            if ($vendor -imatch "Eclipse Adoptium") { return "temurin" }
            if ($vendor -imatch "Adoptium") { return "temurin" }
            if ($vendor -imatch "Azul Systems") { return "zulu" }
            if ($vendor -imatch "Oracle Corporation") { return "oracle" }
            if ($vendor -imatch "Microsoft") { return "microsoft" }
        }

        # 兜底：检查输出中的其他关键词
        $outputLower = $output.ToLower()
        if ($outputLower -match "corretto") { return "corretto" }
        if ($outputLower -match "liberica|bellsoft") { return "liberica" }
        if ($outputLower -match "temurin|adoptium") { return "temurin" }
        if ($outputLower -match "zulu|azul") { return "zulu" }
        if ($outputLower -match "oracle") { return "oracle" }

        return "unknown"
    } catch {
        if ($Global:JmpDebug) {
            Log-Debug "Error executing java -XshowSettings:properties: $_"
        }
        return "unknown"
    }
}

function Get-VendorPriority {
    $vendorFile = Load-Json (Join-Path $Script:ProjectRoot "config\vendor-priority.json")
    if ($vendorFile -and $vendorFile.priority) {
        return $vendorFile.priority
    } else {
        # 默认优先级
        return @("temurin", "zulu", "oracle", "graalvm", "unknown")
    }
}