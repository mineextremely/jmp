function Find-Java {
    param(
        [string]$Version,
        [string]$Vendor
    )

    # 确保Version是字符串
    $Version = [string]$Version
    if ($Global:JmpDebug) { 
        Log-Debug "Received version '$Version' (Type: $($Version.GetType().Name)) and vendor '$Vendor'" 
    }
    
    $jsonData = Load-Json (Join-Path $Script:ProjectRoot "java-versions.json")
    if (-not $jsonData) {
        Write-ErrorMsg "No scan data found. Run 'jmp scan' first."
        return $null
    }

    if ($jsonData.Count -eq 0) {
        Write-ErrorMsg "No Java installations found. Run 'jmp scan' first."
        return $null
    }
    
    # 转换JSON数据为PSCustomObject以便更容易访问
    $data = @()
    foreach ($item in $jsonData) {
        $data += [pscustomobject]@{
            Name = $item.name
            Version = $item.version
            VersionObj = [pscustomobject]$item.versionObj
            Vendor = $item.vendor
            Path = $item.path
            Source = $item.source
        }
    }

    if ($Global:JmpDebug) { Log-Debug "Looking for Java version: $Version" }
    
    # 解析用户输入的版本
    $userVersion = Parse-JavaVersion $Version
    if ($Global:JmpDebug) { 
        Log-Debug "Parsed user version - Major: $($userVersion.major), Minor: $($userVersion.minor), Patch: $($userVersion.patch), IsJava8: $($userVersion.isJava8)"
    }
    
    # 收集所有可用版本用于显示
    $allVersions = $data.Version | Sort-Object -Unique
    if ($Global:JmpDebug) { Log-Debug "Available versions: $($allVersions -join ', ')" }
    
    # 基于解析后的版本进行匹配
    $candidates = @()
    
    foreach ($item in $data) {
        $itemVersion = $item.VersionObj
        
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

    # 修改提示信息
    if ($candidates.Count -eq 0) {
        # 构建可用主版本号列表
        $availableMajors = $data | ForEach-Object { $_.VersionObj.major } | Sort-Object -Unique

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
        return $null
    }

    if ($Global:JmpDebug) { Log-Debug "Found $($candidates.Count) matching version(s): $($candidates.Version -join ', ')" }

    # 初始化$match变量
    $match = $null

    if ($Vendor) {
        # 修正vendor匹配逻辑
        $match = $candidates | Where-Object { 
            if ($_.Vendor -is [array]) {
                $_.Vendor -contains $Vendor
            } else {
                $_.Vendor -eq $Vendor
            }
        } | Select-Object -First 1
    
        if (-not $match) {
            Write-Warning "Vendor '$Vendor' not found for version '$Version'."
        
            # 显示该版本下可用的vendor
            $availableVendors = $candidates.Vendor | Sort-Object -Unique
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
                if ($_.Vendor -is [array]) {
                    $_.Vendor -contains $v
                } else {
                    $_.Vendor -eq $v
                }
            } | Select-Object -First 1
            if ($match) { 
                if ($Global:JmpDebug) { Log-Debug "Selected vendor: $v" }
                break 
            }
        }
    }

    # 如果还没有找到，选择第一个候选
    if (-not $match) {
        $match = $candidates | Select-Object -First 1
    }

    return $match
}